// Notification, the value NSNotification bridges to, and the Combine
// publishers of notifications and timer ticks.

import Combine

// MARK: - Notification

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
public struct Notification: ReferenceConvertible, Equatable, Hashable {
    public typealias ReferenceType = NSNotification
    public typealias Name = NSNotification.Name

    /// A tag identifying the notification.
    public var name: Name

    /// An object that the poster wishes to send to observers.
    public var object: Any?

    /// Storage for values or objects related to this notification.
    public var userInfo: [AnyHashable: Any]?

    /// Initialize a new `Notification`.
    public init(name: Name, object: Any? = nil, userInfo: [AnyHashable: Any]? = nil) {
        self.name = name
        self.object = object
        self.userInfo = userInfo
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        if let object = object as? AnyHashable {
            hasher.combine(object)
        } else if let object = object.map({ $0 as AnyObject }) {
            hasher.combine(ObjectIdentifier(object))
        }
    }

    public var description: String {
        "name = \(name.rawValue), object = \(String(describing: object)), userInfo = \(String(describing: userInfo))"
    }

    public var debugDescription: String {
        description
    }

    public static func == (lhs: Notification, rhs: Notification) -> Bool {
        guard lhs.name == rhs.name else { return false }
        switch (lhs.object, rhs.object) {
        case (nil, nil): break
        case let (l?, r?):
            if let l = l as? AnyHashable, let r = r as? AnyHashable {
                guard l == r else { return false }
            } else {
                guard (l as AnyObject) === (r as AnyObject) else { return false }
            }
        default: return false
        }
        switch (lhs.userInfo, rhs.userInfo) {
        case (nil, nil): return true
        case let (l?, r?): return (l as NSDictionary).isEqual(to: r)
        default: return false
        }
    }
}

@available(*, unavailable)
extension Notification: Sendable {}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension Notification: CustomReflectable {
    public var customMirror: Mirror {
        Mirror(self, children: ["name": name.rawValue, "object": object as Any, "userInfo": userInfo as Any],
               displayStyle: .struct)
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension Notification: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSNotification

    public static func _getObjectiveCType() -> Any.Type {
        NSNotification.self
    }

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSNotification {
        NSNotification(name: name, object: object, userInfo: userInfo)
    }

    static func _bridging(_ x: NSNotification) -> Notification {
        Notification(name: x.name, object: x.object, userInfo: x.userInfo)
    }

    public static func _forceBridgeFromObjectiveC(_ x: NSNotification, result: inout Notification?) {
        result = _bridging(x)
    }

    public static func _conditionallyBridgeFromObjectiveC(_ x: NSNotification, result: inout Notification?) -> Bool {
        result = _bridging(x)
        return true
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNotification?) -> Notification {
        _bridging(source!)
    }
}

@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension NSNotification: _HasCustomAnyHashableRepresentation {
    @nonobjc
    public func _toCustomAnyHashable() -> AnyHashable? {
        AnyHashable(Notification._bridging(self))
    }
}

// MARK: - NotificationCenter.Publisher

// swift-foundation's own NotificationCenter takes the Swift name here; these
// are members of the Objective-C class, which apps built against Darwin's
// Foundation call. Only an unavailable declaration may name it by its
// Objective-C name; availability is the compiler's, and binds nothing.

@available(*, unavailable)
extension NSNotificationCenter {
    /// Returns a publisher that emits events when broadcasting
    /// notifications.
    public func publisher(for name: Notification.Name, object: AnyObject? = nil) -> NSNotificationCenter.Publisher {
        Publisher(center: self, name: name, object: object)
    }
}

@available(*, unavailable)
extension NSNotificationCenter {
    /// A publisher that emits elements when broadcasting notifications.
    public struct Publisher: Combine.Publisher {
        public typealias Output = Notification
        public typealias Failure = Never

        public let center: NSNotificationCenter
        public let name: Notification.Name
        public let object: AnyObject?

        public init(center: NSNotificationCenter, name: Notification.Name, object: AnyObject? = nil) {
            self.center = center
            self.name = name
            self.object = object
        }

        public func receive<S>(subscriber: S) where S: Subscriber, S.Failure == Never, S.Input == Notification {
            subscriber.receive(subscription: NotificationSubscription(publisher: self, subscriber: subscriber))
        }
    }
}

@available(*, unavailable)
extension NSNotificationCenter.Publisher: Sendable {}

@available(*, unavailable)
extension NSNotificationCenter.Publisher: Equatable {
    public static func == (lhs: NSNotificationCenter.Publisher, rhs: NSNotificationCenter.Publisher) -> Bool {
        lhs.center === rhs.center && lhs.name == rhs.name && lhs.object === rhs.object
    }
}

@available(*, unavailable)
extension NSNotificationCenter {
    /// The notifications named, as an asynchronous sequence: each posted
    /// while the sequence is being iterated, and no end to it.
    @preconcurrency
    public func notifications(named name: Notification.Name, object: (AnyObject & Sendable)? = nil) -> NSNotificationCenter.Notifications {
        Notifications(center: self, name: name, object: object)
    }

    final public class Notifications: AsyncSequence, @unchecked Sendable {
        public typealias Element = Notification

        private let stream: AsyncStream<Notification>

        init(center: NSNotificationCenter, name: Notification.Name, object: AnyObject?) {
            var continuation: AsyncStream<Notification>.Continuation!
            stream = AsyncStream { continuation = $0 }
            let yielding = continuation!
            let observer = center.addObserver(forName: name, object: object, queue: nil) { yielding.yield($0) }
            let token = ObserverToken(center: center, observer: observer)
            yielding.onTermination = { _ in token.remove() }
        }

        public struct Iterator: AsyncIteratorProtocol {
            fileprivate let box: IteratorBox

            public func next() async -> Notification? { await box.next() }
        }

        final public __consuming func makeAsyncIterator() -> NSNotificationCenter.Notifications.Iterator {
            Iterator(box: IteratorBox(stream.makeAsyncIterator()))
        }
    }
}

@available(*, unavailable)
private final class IteratorBox: @unchecked Sendable {
    private var iterator: AsyncStream<Notification>.Iterator

    init(_ iterator: AsyncStream<Notification>.Iterator) { self.iterator = iterator }

    func next() async -> Notification? {
        var local = iterator
        let notification = await local.next()
        iterator = local
        return notification
    }
}

@available(*, unavailable)
private final class ObserverToken: @unchecked Sendable {
    private let center: NSNotificationCenter
    private let observer: NSObjectProtocol

    init(center: NSNotificationCenter, observer: NSObjectProtocol) {
        self.center = center
        self.observer = observer
    }

    func remove() { center.removeObserver(observer) }
}

/// Observes the center while its subscriber wants notifications, and sends
/// them as long as it asks for more.
@available(*, unavailable)
private final class NotificationSubscription<S: Subscriber>: Subscription, @unchecked Sendable
where S.Input == Notification, S.Failure == Never {
    private let lock = NSLock()
    private var subscriber: S?
    private var demand = Subscribers.Demand.none
    private var observer: NSObjectProtocol?
    private let center: NSNotificationCenter

    init(publisher: NSNotificationCenter.Publisher, subscriber: S) {
        self.subscriber = subscriber
        center = publisher.center
        observer = center.addObserver(forName: publisher.name, object: publisher.object, queue: nil) { [weak self] notification in
            self?.deliver(notification)
        }
    }

    private func deliver(_ notification: Notification) {
        lock.lock()
        guard let subscriber, demand > 0 else { lock.unlock(); return }
        demand -= 1
        lock.unlock()
        let more = subscriber.receive(notification)
        lock.lock()
        demand += more
        lock.unlock()
    }

    func request(_ demand: Subscribers.Demand) {
        lock.lock()
        self.demand += demand
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        let observer = observer
        self.observer = nil
        subscriber = nil
        lock.unlock()
        if let observer { center.removeObserver(observer) }
    }
}

// MARK: - Timer.TimerPublisher

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension Timer {
    /// Returns a publisher that repeatedly emits the current date on the
    /// given interval.
    public static func publish(every interval: TimeInterval, tolerance: TimeInterval? = nil, on runLoop: RunLoop,
                               in mode: RunLoop.Mode, options: RunLoop.SchedulerOptions? = nil) -> Timer.TimerPublisher {
        TimerPublisher(interval: interval, tolerance: tolerance, runLoop: runLoop, mode: mode, options: options)
    }

    /// A publisher that repeatedly emits the current date on a given
    /// interval, once connected.
    final public class TimerPublisher: ConnectablePublisher {
        public typealias Output = Date
        public typealias Failure = Never

        final public let interval: TimeInterval
        final public let tolerance: TimeInterval?
        final public let runLoop: RunLoop
        final public let mode: RunLoop.Mode
        final public let options: RunLoop.SchedulerOptions?

        private let lock = NSLock()
        private var subscriptions: [ObjectIdentifier: TimerSubscription] = [:]
        private var timer: Timer?

        public init(interval: TimeInterval, tolerance: TimeInterval? = nil, runLoop: RunLoop, mode: RunLoop.Mode,
                    options: RunLoop.SchedulerOptions? = nil) {
            self.interval = interval
            self.tolerance = tolerance
            self.runLoop = runLoop
            self.mode = mode
            self.options = options
        }

        /// Starts the timer; cancelling what this returns stops it.
        final public func connect() -> any Cancellable {
            lock.lock()
            if timer == nil {
                let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.fire() }
                if let tolerance { timer.tolerance = tolerance }
                self.timer = timer
                lock.unlock()
                runLoop.add(timer, forMode: mode)
            } else {
                lock.unlock()
            }
            return AnyCancellable { [weak self] in self?.disconnect() }
        }

        private func disconnect() {
            lock.lock()
            let timer = timer
            self.timer = nil
            lock.unlock()
            timer?.invalidate()
        }

        private func fire() {
            lock.lock()
            let current = Array(subscriptions.values)
            lock.unlock()
            let date = Date()
            current.forEach { $0.deliver(date) }
        }

        fileprivate func remove(_ subscription: TimerSubscription) {
            lock.lock()
            subscriptions[ObjectIdentifier(subscription)] = nil
            lock.unlock()
        }

        final public func receive<S>(subscriber: S) where S: Subscriber, S.Failure == Never, S.Input == Date {
            let subscription = TimerSubscription(publisher: self, subscriber: AnySubscriber(subscriber))
            lock.lock()
            subscriptions[ObjectIdentifier(subscription)] = subscription
            lock.unlock()
            subscriber.receive(subscription: subscription)
        }

        deinit {
            timer?.invalidate()
        }

        /// One subscriber's demand for the timer's dates.
        fileprivate final class TimerSubscription: Subscription, @unchecked Sendable {
            private let lock = NSLock()
            private weak var publisher: TimerPublisher?
            private var subscriber: AnySubscriber<Date, Never>?
            private var demand = Subscribers.Demand.none

            init(publisher: TimerPublisher, subscriber: AnySubscriber<Date, Never>) {
                self.publisher = publisher
                self.subscriber = subscriber
            }

            func deliver(_ date: Date) {
                lock.lock()
                guard let subscriber, demand > 0 else { lock.unlock(); return }
                demand -= 1
                lock.unlock()
                let more = subscriber.receive(date)
                lock.lock()
                demand += more
                lock.unlock()
            }

            func request(_ demand: Subscribers.Demand) {
                lock.lock()
                self.demand += demand
                lock.unlock()
            }

            func cancel() {
                lock.lock()
                subscriber = nil
                lock.unlock()
                publisher?.remove(self)
            }
        }
    }
}

@available(*, unavailable)
extension Timer.TimerPublisher: Sendable {}

// MARK: - PersonNameComponents

/// The separate parts of a person's name.
@available(macOS 10.11, iOS 9.0, watchOS 2.0, tvOS 9.0, *)
public struct PersonNameComponents: ReferenceConvertible, Hashable, Equatable, Sendable {
    public typealias ReferenceType = NSPersonNameComponents

    /// The phonetic representation, boxed since it is another value of
    /// this type.
    final class Phonetic: Sendable {
        let components: PersonNameComponents
        init(_ components: PersonNameComponents) { self.components = components }
    }

    public var namePrefix: String?
    public var givenName: String?
    public var middleName: String?
    public var familyName: String?
    public var nameSuffix: String?
    public var nickname: String?
    var phonetic: Phonetic?

    public var phoneticRepresentation: PersonNameComponents? {
        get { phonetic?.components }
        set { phonetic = newValue.map(Phonetic.init) }
    }

    public init() {}

    public init(namePrefix: String? = nil, givenName: String? = nil, middleName: String? = nil, familyName: String? = nil,
                nameSuffix: String? = nil, nickname: String? = nil, phoneticRepresentation: PersonNameComponents? = nil) {
        self.namePrefix = namePrefix
        self.givenName = givenName
        self.middleName = middleName
        self.familyName = familyName
        self.nameSuffix = nameSuffix
        self.nickname = nickname
        self.phoneticRepresentation = phoneticRepresentation
    }

    private var parts: [String?] { [namePrefix, givenName, middleName, familyName, nameSuffix, nickname] }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(parts)
        hasher.combine(phoneticRepresentation)
    }

    public static func == (lhs: PersonNameComponents, rhs: PersonNameComponents) -> Bool {
        lhs.parts == rhs.parts && lhs.phoneticRepresentation == rhs.phoneticRepresentation
    }
}

@available(macOS 10.11, iOS 9.0, watchOS 2.0, tvOS 9.0, *)
extension PersonNameComponents: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The name's parts in order, separated by spaces.
    public var description: String {
        [namePrefix, givenName, middleName, familyName, nameSuffix].compactMap { $0 }.joined(separator: " ")
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(self, children: [
            "namePrefix": namePrefix as Any, "givenName": givenName as Any, "middleName": middleName as Any,
            "familyName": familyName as Any, "nameSuffix": nameSuffix as Any, "nickname": nickname as Any,
        ], displayStyle: .struct)
    }
}

@available(macOS 10.11, iOS 9.0, watchOS 2.0, tvOS 9.0, *)
extension PersonNameComponents: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSPersonNameComponents

    public static func _getObjectiveCType() -> Any.Type {
        NSPersonNameComponents.self
    }

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> NSPersonNameComponents {
        let result = NSPersonNameComponents()
        result.namePrefix = namePrefix
        result.givenName = givenName
        result.middleName = middleName
        result.familyName = familyName
        result.nameSuffix = nameSuffix
        result.nickname = nickname
        result.phoneticRepresentation = phoneticRepresentation
        return result
    }

    static func _bridging(_ x: NSPersonNameComponents) -> PersonNameComponents {
        PersonNameComponents(namePrefix: x.namePrefix, givenName: x.givenName, middleName: x.middleName,
                             familyName: x.familyName, nameSuffix: x.nameSuffix, nickname: x.nickname,
                             phoneticRepresentation: x.phoneticRepresentation)
    }

    public static func _forceBridgeFromObjectiveC(_ x: NSPersonNameComponents, result: inout PersonNameComponents?) {
        result = _bridging(x)
    }

    public static func _conditionallyBridgeFromObjectiveC(_ x: NSPersonNameComponents, result: inout PersonNameComponents?) -> Bool {
        result = _bridging(x)
        return true
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSPersonNameComponents?) -> PersonNameComponents {
        source.map(_bridging) ?? PersonNameComponents()
    }
}
