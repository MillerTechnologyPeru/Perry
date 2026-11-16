// NSObject's Combine publisher of key-value observing, which apps call as
// `object.publisher(for: \.property)`.

import Combine

/// What gives NSObject and its subclasses the publisher.
public protocol _KeyValueCodingAndObservingPublishing {}

extension NSObject: _KeyValueCodingAndObservingPublishing {}

extension _KeyValueCodingAndObservingPublishing where Self: NSObject {
    /// A publisher of the property's values: its current one when the
    /// options ask for it, and each one it changes to.
    public func publisher<Value>(for keyPath: KeyPath<Self, Value>,
                                 options: NSKeyValueObservingOptions = [.initial, .new])
        -> NSObject.KeyValueObservingPublisher<Self, Value> {
        NSObject.KeyValueObservingPublisher(object: self, keyPath: keyPath, options: options)
    }
}

extension NSObject {
    /// A publisher of a property's values, as key-value observing reports
    /// them.
    public struct KeyValueObservingPublisher<Subject, Value>: Equatable where Subject: NSObject {
        public let object: Subject
        public let keyPath: KeyPath<Subject, Value>
        public let options: NSKeyValueObservingOptions

        public init(object: Subject, keyPath: KeyPath<Subject, Value>, options: NSKeyValueObservingOptions) {
            self.object = object
            self.keyPath = keyPath
            self.options = options
        }

        public static func == (lhs: KeyValueObservingPublisher<Subject, Value>,
                               rhs: KeyValueObservingPublisher<Subject, Value>) -> Bool {
            lhs.object === rhs.object && lhs.keyPath == rhs.keyPath && lhs.options == rhs.options
        }
    }
}

@available(*, unavailable)
extension NSObject.KeyValueObservingPublisher: Sendable {}

extension NSObject.KeyValueObservingPublisher {
    /// A publisher of the changes alone, without the values.
    public func didChange() -> Publishers.Map<NSObject.KeyValueObservingPublisher<Subject, Value>, Void> {
        map { _ in () }
    }
}

extension NSObject.KeyValueObservingPublisher: Publisher {
    public typealias Output = Value
    public typealias Failure = Never

    public func receive<S>(subscriber: S) where Value == S.Input, S: Subscriber, S.Failure == Never {
        subscriber.receive(subscription: KeyValueObservingSubscription(publisher: self, subscriber: subscriber))
    }
}

/// One subscriber's observation: values go to it while it has asked for
/// them, and the observation ends when it cancels.
private final class KeyValueObservingSubscription<Subject, Value, S>: Subscription
where Subject: NSObject, S: Subscriber, S.Input == Value, S.Failure == Never {
    private let lock = NSLock()
    private var subscriber: S?
    private var demand = Subscribers.Demand.none
    private var observation: NSKeyValueObservation?
    private let object: Subject
    private let keyPath: KeyPath<Subject, Value>

    init(publisher: NSObject.KeyValueObservingPublisher<Subject, Value>, subscriber: S) {
        self.subscriber = subscriber
        self.object = publisher.object
        self.keyPath = publisher.keyPath
        observation = publisher.object.observe(publisher.keyPath, options: publisher.options) { [weak self] _, _ in
            self?.send()
        }
    }

    func request(_ demand: Subscribers.Demand) {
        lock.lock()
        self.demand += demand
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        let observation = self.observation
        self.observation = nil
        subscriber = nil
        lock.unlock()
        observation?.invalidate()
    }

    private func send() {
        lock.lock()
        guard let subscriber, demand > .none else {
            lock.unlock()
            return
        }
        demand -= 1
        lock.unlock()
        let more = subscriber.receive(object[keyPath: keyPath])
        lock.lock()
        demand += more
        lock.unlock()
    }
}
