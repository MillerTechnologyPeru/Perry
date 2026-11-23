import Foundation

// CLMonitor: conditions monitored under a name, their events as an async
// sequence, over the Objective-C CLMonitor the headers refine for Swift.

@available(macOS 14.0, iOS 17.0, *)
@available(watchOS, unavailable)
@available(tvOS, unavailable)
@available(visionOS, unavailable)
public protocol CLCondition: Decodable, Encodable, Sendable {}

/// An Objective-C condition carried across a Sendable boundary; conditions
/// are immutable.
private struct SendableObject<Object: AnyObject>: @unchecked Sendable {
    let object: Object
}

@available(macOS 14.0, iOS 17.0, *)
@available(watchOS, unavailable)
@available(tvOS, unavailable)
@available(visionOS, unavailable)
public actor CLMonitor {
    private let monitor: SendableObject<__CLMonitor>

    public var identifiers: [String] {
        monitor.object.monitoredIdentifiers
    }

    public final let events: CLMonitor.Events

    public struct Record: Sendable {
        public let lastEvent: CLMonitor.Event
        public let condition: any CLCondition

        init(_ record: __CLMonitoringRecord) {
            lastEvent = Event(record.lastEvent)
            condition = swiftCondition(record.condition)
        }
    }

    public struct Event: Sendable {
        public typealias State = __CLMonitoringState

        private let event: SendableObject<__CLMonitoringEvent>
        public let refinement: (any CLCondition)?

        init(_ event: __CLMonitoringEvent) {
            self.event = SendableObject(object: event)
            refinement = event.refinement.map(swiftCondition)
        }

        public var identifier: String { event.object.identifier }
        public var state: CLMonitor.Event.State { event.object.state }
        public var date: Date { event.object.date }

        @available(macOS 15.0, iOS 18.0, *)
        @available(watchOS, unavailable)
        @available(tvOS, unavailable)
        public var authorizationDenied: Bool { event.object.authorizationDenied }

        @available(macOS 15.0, iOS 18.0, *)
        @available(watchOS, unavailable)
        @available(tvOS, unavailable)
        public var authorizationDeniedGlobally: Bool { event.object.authorizationDeniedGlobally }

        @available(macOS 15.0, iOS 18.0, *)
        @available(watchOS, unavailable)
        @available(tvOS, unavailable)
        public var authorizationRestricted: Bool { event.object.authorizationRestricted }

        @available(macOS 15.0, iOS 18.0, *)
        @available(watchOS, unavailable)
        @available(tvOS, unavailable)
        public var insufficientlyInUse: Bool { event.object.insufficientlyInUse }

        @available(macOS 15.0, iOS 18.0, *)
        @available(watchOS, unavailable)
        @available(tvOS, unavailable)
        public var accuracyLimited: Bool { event.object.accuracyLimited }

        @available(macOS 15.0, iOS 18.0, *)
        @available(watchOS, unavailable)
        @available(tvOS, unavailable)
        public var conditionUnsupported: Bool { event.object.conditionUnsupported }

        @available(macOS 15.0, iOS 18.0, *)
        @available(watchOS, unavailable)
        @available(tvOS, unavailable)
        public var conditionLimitExceeded: Bool { event.object.conditionLimitExceeded }

        @available(macOS 15.0, iOS 18.0, *)
        @available(watchOS, unavailable)
        @available(tvOS, unavailable)
        public var persistenceUnavailable: Bool { event.object.persistenceUnavailable }

        @available(macOS 15.0, iOS 18.0, *)
        @available(watchOS, unavailable)
        @available(tvOS, unavailable)
        public var serviceSessionRequired: Bool { event.object.serviceSessionRequired }

        @available(macOS 15.0, iOS 18.0, *)
        @available(watchOS, unavailable)
        @available(tvOS, unavailable)
        public var authorizationRequestInProgress: Bool { event.object.authorizationRequestInProgress }
    }

    /// The monitor's events, as its Objective-C event handler delivers them.
    public struct Events: AsyncSequence, Sendable {
        public typealias Element = CLMonitor.Event

        let stream: AsyncStream<CLMonitor.Event>

        public struct Iterator: AsyncIteratorProtocol {
            var iterator: AsyncStream<CLMonitor.Event>.Iterator

            public mutating func next() async throws -> CLMonitor.Events.Element? {
                await iterator.next()
            }

            @available(macOS 14.0, iOS 17.0, *)
            @available(tvOS, unavailable)
            @available(watchOS, unavailable)
            @available(visionOS, unavailable)
            public typealias Element = CLMonitor.Events.Element
        }

        public func makeAsyncIterator() -> CLMonitor.Events.Iterator {
            Iterator(iterator: stream.makeAsyncIterator())
        }

        @available(macOS 14.0, iOS 17.0, *)
        @available(tvOS, unavailable)
        @available(watchOS, unavailable)
        @available(visionOS, unavailable)
        public typealias AsyncIterator = CLMonitor.Events.Iterator
    }

    public struct CircularGeographicCondition: CLCondition, Sendable {
        public let center: CLLocationCoordinate2D
        public let radius: CLLocationDistance

        public init(center: CLLocationCoordinate2D, radius: CLLocationDistance) {
            self.center = center
            self.radius = radius
        }

        private enum CodingKeys: String, CodingKey {
            case latitude, longitude, radius
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            center = CLLocationCoordinate2D(latitude: try container.decode(Double.self, forKey: .latitude),
                                            longitude: try container.decode(Double.self, forKey: .longitude))
            radius = try container.decode(CLLocationDistance.self, forKey: .radius)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(center.latitude, forKey: .latitude)
            try container.encode(center.longitude, forKey: .longitude)
            try container.encode(radius, forKey: .radius)
        }
    }

    public func add(_ Condition: any CLCondition, identifier: String) {
        guard let condition = objectiveCCondition(Condition) else { return }
        monitor.object.addCondition(forMonitoring: condition, identifier: identifier)
    }

    public func add(_ condition: any CLCondition, identifier: String, assuming state: CLMonitor.Event.State) {
        guard let condition = objectiveCCondition(condition) else { return }
        monitor.object.addCondition(forMonitoring: condition, identifier: identifier, assumedState: state)
    }

    public func remove(_ identifier: String) {
        monitor.object.removeConditionFromMonitoring(withIdentifier: identifier)
    }

    public func record(for identifier: String) -> CLMonitor.Record? {
        monitor.object.monitoringRecord(forIdentifier: identifier).map(Record.init)
    }

    /// Asks Core Location for the monitor of this name, its events
    /// delivered on a queue of its own into `events`.
    public init(_ name: String) async {
        let (stream, continuation) = AsyncStream<CLMonitor.Event>.makeStream()
        let queue = DispatchQueue(label: "CLMonitor.\(name)")
        let configuration = __CLMonitorConfiguration.config(withMonitorName: name, queue: queue) { _, event in
            continuation.yield(Event(event))
        }
        let monitor = await withCheckedContinuation { (result: CheckedContinuation<SendableObject<__CLMonitor>, Never>) in
            __CLMonitor.__request(with: configuration) { monitor in
                result.resume(returning: SendableObject(object: monitor))
            }
        }.object
        self.monitor = SendableObject(object: monitor)
        events = Events(stream: stream)
    }
}

@available(iOS 17.0, macOS 14.0, *)
@available(macCatalyst, unavailable)
@available(watchOS, unavailable)
@available(tvOS, unavailable)
@available(visionOS, unavailable)
extension CLMonitor {
    public struct BeaconIdentityCondition: CLCondition, Sendable {
        public let uuid: UUID
        public let major: UInt16?
        public let minor: UInt16?

        public init(uuid: UUID) {
            self.uuid = uuid
            major = nil
            minor = nil
        }

        public init(uuid: UUID, major: UInt16) {
            self.uuid = uuid
            self.major = major
            minor = nil
        }

        public init(uuid: UUID, major: UInt16, minor: UInt16) {
            self.uuid = uuid
            self.major = major
            self.minor = minor
        }

        private enum CodingKeys: String, CodingKey {
            case uuid, major, minor
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            uuid = try container.decode(UUID.self, forKey: .uuid)
            major = try container.decodeIfPresent(UInt16.self, forKey: .major)
            minor = try container.decodeIfPresent(UInt16.self, forKey: .minor)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(uuid, forKey: .uuid)
            try container.encodeIfPresent(major, forKey: .major)
            try container.encodeIfPresent(minor, forKey: .minor)
        }
    }
}

/// A condition of a kind this overlay doesn't know, kept as the Objective-C
/// object's keyed archive so that it can be handed back.
@available(macOS 14.0, iOS 17.0, *)
private struct ArchivedCondition: CLCondition {
    let archive: Data

    var object: __CLCondition? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: __CLCondition.self, from: archive)
    }
}

/// An Objective-C condition as the Swift condition of its kind.
@available(macOS 14.0, iOS 17.0, *)
private func swiftCondition(_ condition: __CLCondition) -> any CLCondition {
    if let circle = condition as? __CLCircularGeographicCondition {
        return CLMonitor.CircularGeographicCondition(center: circle.center, radius: circle.radius)
    }
    #if !targetEnvironment(macCatalyst)
    if let beacon = condition as? __CLBeaconIdentityCondition {
        switch (beacon.__major, beacon.__minor) {
        case let (major?, minor?):
            return CLMonitor.BeaconIdentityCondition(uuid: beacon.uuid, major: major.uint16Value, minor: minor.uint16Value)
        case let (major?, nil):
            return CLMonitor.BeaconIdentityCondition(uuid: beacon.uuid, major: major.uint16Value)
        default:
            return CLMonitor.BeaconIdentityCondition(uuid: beacon.uuid)
        }
    }
    #endif
    let archive = (try? NSKeyedArchiver.archivedData(withRootObject: condition, requiringSecureCoding: true)) ?? Data()
    return ArchivedCondition(archive: archive)
}

/// A Swift condition as Core Location's object; nil for one of a kind
/// Core Location can't monitor.
@available(macOS 14.0, iOS 17.0, *)
private func objectiveCCondition(_ condition: any CLCondition) -> __CLCondition? {
    if let circle = condition as? CLMonitor.CircularGeographicCondition {
        return __CLCircularGeographicCondition(center: circle.center, radius: circle.radius)
    }
    #if !targetEnvironment(macCatalyst)
    if let beacon = condition as? CLMonitor.BeaconIdentityCondition {
        switch (beacon.major, beacon.minor) {
        case let (major?, minor?):
            return __CLBeaconIdentityCondition(uuid: beacon.uuid, major: major, minor: minor)
        case let (major?, nil):
            return __CLBeaconIdentityCondition(uuid: beacon.uuid, major: major)
        default:
            return __CLBeaconIdentityCondition(uuid: beacon.uuid)
        }
    }
    #endif
    if let archived = condition as? ArchivedCondition {
        return archived.object
    }
    return nil
}
