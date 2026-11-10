// GroupActivities: SharePlay. There is no FaceTime call to share an activity
// in, so this reports what an app finds with no call going: the device is not
// eligible for a group session, no session ever starts, and an activity that
// asks to start one is told activation is disabled. Apps that offer SharePlay
// where it is available then show no such offer. The declarations are the
// framework's own (what apps bind to by Swift symbol), so library evolution
// is on and the types are resilient.
import Combine
import CoreGraphics
import Foundation

// MARK: - Sessions

@available(iOS 15, macOS 12, tvOS 15, *)
@available(watchOS, unavailable)
final public class GroupSession<ActivityType>: ObservableObject where ActivityType: GroupActivity {
    public enum State: Sendable {
        case waiting
        case joined
        case invalidated(reason: any Error)
    }

    final public let id = UUID()

    @Published final public private(set) var state: State = .waiting
    @Published final public var activity: ActivityType
    @Published final public private(set) var activeParticipants: Set<Participant> = []

    final public let localParticipant = Participant(id: UUID())

    @available(iOS 17, macOS 14, tvOS 17, visionOS 1, *)
    @available(watchOS, unavailable)
    final public var sceneSessionIdentifier: String? { nil }

    @available(iOS 18.0, watchOS 11.0, visionOS 2.0, macCatalyst 18.0, macOS 15.0, *)
    final public var isLocallyInitiated: Bool { true }

    init(activity: ActivityType) { self.activity = activity }

    final public func join() {}
    final public func leave() { state = .invalidated(reason: GroupSessionError.ended) }
    final public func end() { state = .invalidated(reason: GroupSessionError.ended) }
    final public func requestForegroundPresentation() {}

    @available(macOS 12, iOS 15, tvOS 15, *)
    @available(watchOS, unavailable)
    public typealias ObjectWillChangePublisher = ObservableObjectPublisher
}

private enum GroupSessionError: Error { case ended }

@available(iOS 15, macOS 12, tvOS 15, *)
@available(watchOS, unavailable)
extension GroupSession.State: Equatable {
    public static func == (lhs: GroupSession<ActivityType>.State, rhs: GroupSession<ActivityType>.State) -> Bool {
        switch (lhs, rhs) {
        case (.waiting, .waiting), (.joined, .joined): return true
        case (.invalidated, .invalidated): return true
        default: return false
        }
    }
}

@available(iOS 15, macOS 12, tvOS 15, *)
@available(watchOS, unavailable)
extension GroupSession: CustomStringConvertible {
    final public var description: String { "GroupSession(id: \(id), state: \(state))" }
}

@available(iOS 15, macOS 12, tvOS 15, *)
@available(watchOS, unavailable)
extension GroupSession {
    /// The sessions that start for an activity type: none do, so it ends at once.
    public struct Sessions: AsyncSequence {
        public typealias Element = GroupSession<ActivityType>

        public func makeAsyncIterator() -> Iterator { Iterator() }

        public struct Iterator: AsyncIteratorProtocol {
            public mutating func next() async -> GroupSession<ActivityType>? { nil }
            public typealias Element = GroupSession<ActivityType>
        }
    }
}

@available(iOS 15, macOS 12, tvOS 15, *)
@available(watchOS, unavailable)
extension GroupSession.Sessions: Sendable where ActivityType: Sendable {}
@available(iOS 15, macOS 12, tvOS 15, *)
@available(watchOS, unavailable)
extension GroupSession.Sessions.Iterator: Sendable where ActivityType: Sendable {}

// MARK: - Activities

@available(iOS 15, macOS 12, tvOS 15, *)
@available(watchOS, unavailable)
public enum GroupActivityActivationResult: Sendable {
    case activationPreferred
    case activationDisabled
    case cancelled
}

@available(iOS 15, macOS 12, tvOS 15, *)
@available(watchOS, unavailable)
public protocol GroupActivity: Decodable, Encodable {
    static var activityIdentifier: String { get }
    var metadata: GroupActivityMetadata { get async }
    static func _identifiable(by activityIdentifier: String) -> Bool
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, *)
    @available(watchOS, unavailable)
    static func _identifiable(by activityIdentifier: String, staticIdentifier: String?) -> Bool
}

@available(iOS 15, macOS 12, tvOS 15, *)
@available(watchOS, unavailable)
extension GroupActivity {
    public static var activityIdentifier: String { String(reflecting: Self.self) }

    public static func _identifiable(by activityIdentifier: String) -> Bool {
        Self.activityIdentifier == activityIdentifier
    }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, *)
    @available(watchOS, unavailable)
    public static func _identifiable(by activityIdentifier: String, staticIdentifier: String?) -> Bool {
        _identifiable(by: activityIdentifier)
    }
}

@available(iOS 15, macOS 12, tvOS 15, *)
@available(watchOS, unavailable)
extension GroupActivity {
    public func prepareForActivation() async -> GroupActivityActivationResult { .activationDisabled }
    public func activate() async throws -> Bool { false }
}

@available(iOS 15, macOS 12, tvOS 15, *)
@available(watchOS, unavailable)
extension GroupActivity {
    public typealias Sessions = GroupSession<Self>.Sessions
    public static func sessions() -> Self.Sessions { GroupSession<Self>.Sessions() }
}

// MARK: - State

@available(iOS 15, macOS 12, tvOS 15, *)
@available(watchOS, unavailable)
final public class GroupStateObserver: ObservableObject {
    @Published final public private(set) var isEligibleForGroupSession: Bool = false

    private init(unused: Void) {}

    convenience public init() { self.init(unused: ()) }

    @available(macOS 12, iOS 15, tvOS 15, *)
    @available(watchOS, unavailable)
    public typealias ObjectWillChangePublisher = ObservableObjectPublisher
}

// MARK: - Messages

@available(iOS 15, macOS 12, tvOS 15, *)
@available(watchOS, unavailable)
final public class GroupSessionMessenger: @unchecked Sendable {
    private let mode: DeliveryMode

    @available(iOS 16, macOS 13, tvOS 16, *)
    @available(watchOS, unavailable)
    final public var deliveryMode: DeliveryMode { mode }

    public init<Activity>(session: GroupSession<Activity>) where Activity: GroupActivity {
        mode = .reliable
    }

    @available(iOS 16, macOS 13, tvOS 16, *)
    @available(watchOS, unavailable)
    public init<Activity>(session: GroupSession<Activity>, deliveryMode: DeliveryMode) where Activity: GroupActivity {
        mode = deliveryMode
    }
}

@available(iOS 15, macOS 12, tvOS 15, *)
@available(watchOS, unavailable)
extension GroupSessionMessenger {
    public enum DeliveryMode: Sendable {
        case reliable
        case unreliable
    }

    public struct MessageContext: Sendable {
        public var source: Participant
    }

    /// The messages received: none, with nobody else in the session.
    public struct Messages<Message>: AsyncSequence where Message: Decodable, Message: Encodable {
        public typealias Element = (Message, MessageContext)

        public func makeAsyncIterator() -> Iterator { Iterator() }

        public struct Iterator: AsyncIteratorProtocol {
            public mutating func next() async -> (Message, MessageContext)? { nil }
            public typealias Element = (Message, MessageContext)
        }
    }

    final public func send<Message>(_ value: Message, to participants: Participants = .all,
                                    completion: @escaping ((any Error)?) -> Void) where Message: Decodable, Message: Encodable {
        completion(nil)
    }

    final public func send(_ value: Data, to participants: Participants = .all, completion: @escaping ((any Error)?) -> Void) {
        completion(nil)
    }

    @_unsafeInheritExecutor
    final public func send<Message>(_ value: Message, to participants: Participants = .all) async throws
        where Message: Decodable, Message: Encodable {}

    @_unsafeInheritExecutor
    final public func send(_ value: Data, to participants: Participants = .all) async throws {}

    final public func messages<Message>(of type: Message.Type) -> Messages<Message> where Message: Decodable, Message: Encodable {
        Messages<Message>()
    }

    final public func messages(of type: Data.Type) -> Messages<Data> { Messages<Data>() }
}

@available(iOS 15, macOS 12, tvOS 15, *)
@available(watchOS, unavailable)
extension GroupSessionMessenger.Messages: Sendable where Message: Sendable {}
@available(iOS 15, macOS 12, tvOS 15, *)
@available(watchOS, unavailable)
extension GroupSessionMessenger.Messages.Iterator: Sendable where Message: Sendable {}

public protocol CustomMessageIdentifiable {
    static var messageIdentifier: String { get }
}

// MARK: - Participants

public struct Participant: Hashable, Identifiable, Sendable {
    public let id: UUID

    @available(macCatalyst, unavailable)
    public var isNearbyWithLocalParticipant: Bool { false }
}

extension Participant: CustomStringConvertible {
    public var description: String { "Participant(id: \(id))" }
}

public enum Participants: Sendable {
    case all
    case only(Set<Participant>)
}

extension Participants {
    public static func only(_ participant: Participant) -> Participants { .only([participant]) }
}

// MARK: - Metadata

@available(iOS 15, macOS 12, tvOS 15, *)
@available(watchOS, unavailable)
public struct BroadcastOptions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let mirroredVideo = BroadcastOptions(rawValue: 1)
}

public struct SceneAssociationBehavior: Equatable, Sendable {
    private let content: String?
    private let none: Bool

    public static let `default` = SceneAssociationBehavior(content: nil, none: false)
    public static func content(_ contentIdentifier: String) -> SceneAssociationBehavior {
        SceneAssociationBehavior(content: contentIdentifier, none: false)
    }
    public static let none = SceneAssociationBehavior(content: nil, none: true)
}

public struct GroupActivityMetadata: Equatable, Sendable {
    public struct ActivityType: Hashable, Sendable {
        private let name: String
        public static let generic = ActivityType(name: "generic")
        public static let listenTogether = ActivityType(name: "listenTogether")
        public static let watchTogether = ActivityType(name: "watchTogether")
        public static let playTogether = ActivityType(name: "playTogether")
        public static let workoutTogether = ActivityType(name: "workoutTogether")
        public static let shopTogether = ActivityType(name: "shopTogether")
        public static let readTogether = ActivityType(name: "readTogether")
        public static let exploreTogether = ActivityType(name: "exploreTogether")
        public static let learnTogether = ActivityType(name: "learnTogether")
        public static let createTogether = ActivityType(name: "createTogether")
    }

    public struct LifetimePolicy: Hashable, Sendable {
        private let name: String
        public static let automatic = LifetimePolicy(name: "automatic")
        public static let endsWhenInitiatorLeaves = LifetimePolicy(name: "endsWhenInitiatorLeaves")
    }

    public var type: ActivityType = .generic
    public var title: String?
    public var subtitle: String?
    public var previewImage: CGImage?
    public var fallbackURL: URL?
    public var preferredBroadcastOptions: BroadcastOptions = []
    public var supportsContinuationOnTV: Bool = false
    public var sceneAssociationBehavior: SceneAssociationBehavior = .default
    public var lifetimePolicy: LifetimePolicy = .automatic

    public init() {}

    public static func == (a: GroupActivityMetadata, b: GroupActivityMetadata) -> Bool {
        a.type == b.type && a.title == b.title && a.subtitle == b.subtitle && a.fallbackURL == b.fallbackURL
            && a.preferredBroadcastOptions == b.preferredBroadcastOptions
            && a.supportsContinuationOnTV == b.supportsContinuationOnTV
            && a.sceneAssociationBehavior == b.sceneAssociationBehavior && a.lifetimePolicy == b.lifetimePolicy
    }
}

extension GroupActivityMetadata: Codable {
    private enum Keys: String, CodingKey { case title, subtitle, fallbackURL }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: Keys.self)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        subtitle = try values.decodeIfPresent(String.self, forKey: .subtitle)
        fallbackURL = try values.decodeIfPresent(URL.self, forKey: .fallbackURL)
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: Keys.self)
        try values.encodeIfPresent(title, forKey: .title)
        try values.encodeIfPresent(subtitle, forKey: .subtitle)
        try values.encodeIfPresent(fallbackURL, forKey: .fallbackURL)
    }
}
