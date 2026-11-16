// ActivityKit: Live Activities, the status an app keeps on the lock screen
// and in the Dynamic Island. There is neither here: activities are not
// enabled, requesting one fails as unsupported, and no activity exists to
// update or end. The declarations are the framework's own (what apps bind
// to by Swift symbol), so library evolution is on and the types are
// resilient.
import Foundation

// MARK: - Attributes

@available(iOS 16.1, *)
public protocol ActivityAttributes: Decodable, Encodable {
    associatedtype ContentState: Decodable, Encodable, Hashable
}

@available(iOS 16.1, *)
public enum ActivityStyle {
    case standard
    case transient
}

// MARK: - Content

@available(iOS 16.2, *)
public struct ActivityContent<State> where State: Decodable, State: Encodable, State: Hashable {
    public let state: State
    public let staleDate: Date?
    public let relevanceScore: Double

    public init(state: State, staleDate: Date?, relevanceScore: Double = 0.0) {
        self.state = state
        self.staleDate = staleDate
        self.relevanceScore = relevanceScore
    }
}

@available(iOS 16.2, *)
extension ActivityContent: Sendable where State: Sendable {}

@available(iOS 16.2, *)
extension ActivityContent: CustomStringConvertible {
    public var description: String {
        "ActivityContent(state: \(state), staleDate: \(staleDate.map { "\($0)" } ?? "nil"), relevanceScore: \(relevanceScore))"
    }
}

@available(iOS 16.1, *)
public enum ActivityState: Sendable, Codable, Hashable {
    @available(iOS 26.0, *)
    case pending
    case active
    case ended
    case dismissed
    @available(iOS 16.2, *)
    case stale
}

// MARK: - Alerts and dismissal

public struct AlertConfiguration: Equatable, Sendable {
    public var title: LocalizedStringResource
    public var body: LocalizedStringResource
    public var sound: AlertSound

    public init(title: LocalizedStringResource, body: LocalizedStringResource, sound: AlertSound) {
        self.title = title
        self.body = body
        self.sound = sound
    }

    public struct AlertSound: Equatable, Sendable {
        var name: String?

        public static var `default`: AlertSound { AlertSound(name: nil) }

        public static func named(_ name: String) -> AlertSound { AlertSound(name: name) }
    }
}

public struct ActivityUIDismissalPolicy: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case `default`
        case immediate
        case after(Date)
    }

    var kind: Kind

    public static let `default` = ActivityUIDismissalPolicy(kind: .default)
    public static let immediate = ActivityUIDismissalPolicy(kind: .immediate)

    public static func after(_ date: Date) -> ActivityUIDismissalPolicy { ActivityUIDismissalPolicy(kind: .after(date)) }
}

public struct PushType: Equatable {
    var channel: String?

    public static var token: PushType { PushType(channel: nil) }

    public static func channel(_ name: String) -> PushType { PushType(channel: name) }
}

// MARK: - Authorization

public enum ActivityAuthorizationError: CustomNSError, LocalizedError {
    case attributesTooLarge
    case unsupported
    case denied
    case globalMaximumExceeded
    case targetMaximumExceeded
    case unsupportedTarget
    case visibility
    case persistenceFailure
    case missingProcessIdentifier
    case unentitled
    case malformedActivityIdentifier
    case reconnectNotPermitted

    public static var errorDomain: String { "ActivityKit.ActivityAuthorizationError" }

    public var errorCode: Int {
        switch self {
        case .attributesTooLarge: 0
        case .unsupported: 1
        case .denied: 2
        case .globalMaximumExceeded: 3
        case .targetMaximumExceeded: 4
        case .unsupportedTarget: 5
        case .visibility: 6
        case .persistenceFailure: 7
        case .missingProcessIdentifier: 8
        case .unentitled: 9
        case .malformedActivityIdentifier: 10
        case .reconnectNotPermitted: 11
        }
    }

    public var failureReason: String? {
        switch self {
        case .unsupported: "Live Activities are not supported on this device."
        case .denied: "Live Activities are turned off."
        default: "The activity could not be started."
        }
    }

    public var recoverySuggestion: String? { nil }
}

/// Whether activities can be started: they cannot, and that never changes.
final public class ActivityAuthorizationInfo {
    public struct ActivityEnablementUpdates: AsyncSequence {
        public typealias Element = Bool

        public func makeAsyncIterator() -> Iterator { Iterator() }

        public struct Iterator: AsyncIteratorProtocol {
            public mutating func next() async -> Bool? { nil }
        }
    }

    public struct FrequentPushEnablementUpdates: AsyncSequence {
        public typealias Element = Bool

        public func makeAsyncIterator() -> Iterator { Iterator() }

        public struct Iterator: AsyncIteratorProtocol {
            public mutating func next() async -> Bool? { nil }
        }
    }

    final public var frequentPushesEnabled: Bool { false }
    final public var areActivitiesEnabled: Bool { false }
    final public let activityEnablementUpdates: ActivityEnablementUpdates
    final public let frequentPushEnablementUpdates: FrequentPushEnablementUpdates

    public init() {
        activityEnablementUpdates = ActivityEnablementUpdates()
        frequentPushEnablementUpdates = FrequentPushEnablementUpdates()
    }
}

// MARK: - Activity

@available(iOS 16.1, *)
public class Activity<Attributes>: Identifiable where Attributes: ActivityAttributes {
    public typealias ContentState = Attributes.ContentState

    // Requests fail: there is no activity to hand back.
    public static func request(attributes: Attributes, contentState: ContentState, pushType: PushType? = nil) throws -> Activity<Attributes> {
        throw ActivityAuthorizationError.unsupported
    }

    @available(iOS 16.2, *)
    public static func request(attributes: Attributes, content: ActivityContent<ContentState>, pushType: PushType? = nil) throws -> Activity<Attributes> {
        throw ActivityAuthorizationError.unsupported
    }

    @available(iOS 18.0, *)
    public static func request(attributes: Attributes, content: ActivityContent<ContentState>, pushType: PushType? = nil, style: ActivityStyle) throws -> Activity<Attributes> {
        throw ActivityAuthorizationError.unsupported
    }

    @available(iOS 26.0, *)
    public static func request(attributes: Attributes, content: ActivityContent<ContentState>, pushType: PushType? = nil, style: ActivityStyle, alertConfiguration: AlertConfiguration, start: Date) throws -> Activity<Attributes> {
        throw ActivityAuthorizationError.unsupported
    }

    @available(iOS 26.0, *)
    public static func request(attributes: Attributes, content: ActivityContent<ContentState>, pushType: PushType? = nil, style: ActivityStyle, alertConfiguration: AlertConfiguration, startDate: Date) throws -> Activity<Attributes> {
        throw ActivityAuthorizationError.unsupported
    }

    public static var activities: [Activity<Attributes>] { [] }

    public static var activityUpdates: ActivityUpdates { ActivityUpdates() }

    final public let id: String

    public var activityState: ActivityState { .ended }

    public var activityStateUpdates: ActivityStateUpdates { ActivityStateUpdates() }

    public var contentState: ContentState { storedContent.state }

    public var contentStateUpdates: ContentStateUpdates { ContentStateUpdates() }

    @available(iOS 16.2, *)
    public var content: ActivityContent<ContentState> { storedContent }

    @available(iOS 16.2, *)
    public var contentUpdates: ContentUpdates { ContentUpdates() }

    public var pushToken: Data? { nil }

    public var pushTokenUpdates: PushTokenUpdates { PushTokenUpdates() }

    @available(iOS 17.2, *)
    public static var pushToStartTokenUpdates: PushTokenUpdates { PushTokenUpdates() }

    @available(iOS 17.2, *)
    public static var pushToStartToken: Data? { nil }

    final public let attributes: Attributes

    private let storedContent: ActivityContent<ContentState>

    init(id: String, attributes: Attributes, content: ActivityContent<ContentState>) {
        self.id = id
        self.attributes = attributes
        self.storedContent = content
    }

    public func update(using contentState: ContentState) async {}

    @available(iOS 16.2, *)
    public func update(_ content: ActivityContent<ContentState>) async {}

    public func update(using contentState: ContentState, alertConfiguration: AlertConfiguration? = nil) async {}

    @available(iOS 16.2, *)
    public func update(_ content: ActivityContent<ContentState>, alertConfiguration: AlertConfiguration? = nil) async {}

    @available(iOS 17.2, *)
    public func update(_ content: ActivityContent<ContentState>, alertConfiguration: AlertConfiguration? = nil, timestamp: Date) async {}

    public func end(using contentState: ContentState? = nil, dismissalPolicy: ActivityUIDismissalPolicy = .default) async {}

    @available(iOS 16.2, *)
    public func end(_ content: ActivityContent<ContentState>?, dismissalPolicy: ActivityUIDismissalPolicy = .default) async {}

    @available(iOS 17.2, *)
    public func end(_ content: ActivityContent<ContentState>?, dismissalPolicy: ActivityUIDismissalPolicy = .default, timestamp: Date) async {}

    public typealias ID = String
}

// Updates of activities arrive from the system, which has none: each
// sequence ends as it begins.
@available(iOS 16.1, *)
extension Activity {
    public struct ActivityUpdates: AsyncSequence {
        public typealias Element = Activity<Attributes>

        public func makeAsyncIterator() -> Iterator { Iterator() }

        public struct Iterator: AsyncIteratorProtocol {
            public func next() async -> Element? { nil }
        }
    }

    public struct ActivityStateUpdates: AsyncSequence {
        public typealias Element = ActivityState

        public func makeAsyncIterator() -> Iterator { Iterator() }

        public struct Iterator: AsyncIteratorProtocol, Sendable {
            public func next() async -> Element? { nil }
        }
    }

    public struct ContentStateUpdates: AsyncSequence {
        public typealias Element = ContentState

        public func makeAsyncIterator() -> Iterator { Iterator() }

        public struct Iterator: AsyncIteratorProtocol {
            public func next() async -> Element? { nil }
        }
    }

    @available(iOS 16.2, *)
    public struct ContentUpdates: AsyncSequence {
        public typealias Element = ActivityContent<ContentState>

        public func makeAsyncIterator() -> Iterator { Iterator() }

        public struct Iterator: AsyncIteratorProtocol {
            public func next() async -> Element? { nil }
        }
    }

    public struct PushTokenUpdates: AsyncSequence {
        public typealias Element = Data

        public func makeAsyncIterator() -> Iterator { Iterator() }

        public struct Iterator: AsyncIteratorProtocol {
            public func next() async -> Element? { nil }
        }
    }
}
