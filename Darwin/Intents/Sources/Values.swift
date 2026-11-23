import Foundation

// INShortcut and INMediaDestination: Swift enums bridged to the
// Objective-C classes the headers name INShortcut and INMediaDestination
// (imported as INShortcutReference and INMediaDestinationReference).

@available(iOS 12.0, macOS 11.0, watchOS 5.0, *)
@available(tvOS, unavailable)
public enum INShortcut: ReferenceConvertible {
    public typealias ReferenceType = INShortcutReference
    case intent(INIntent)
    case userActivity(NSUserActivity)
}

@available(iOS 12.0, macOS 11.0, watchOS 5.0, *)
@available(tvOS, unavailable)
extension INShortcut {
    /// A shortcut of an intent; nil when Intents finds the intent invalid
    /// for one (no title, no shortcut types), as its initializer does.
    public init?(intent: INIntent) {
        guard INShortcutReference(intent: intent) != nil else { return nil }
        self = .intent(intent)
    }

    public init(userActivity: NSUserActivity) {
        self = .userActivity(userActivity)
    }
}

@available(iOS 12.0, macOS 11.0, watchOS 5.0, *)
@available(tvOS, unavailable)
extension INShortcut {
    public var intent: INIntent? {
        guard case let .intent(intent) = self else { return nil }
        return intent
    }

    public var userActivity: NSUserActivity? {
        guard case let .userActivity(activity) = self else { return nil }
        return activity
    }
}

@available(iOS 12.0, macOS 11.0, watchOS 5.0, *)
@available(tvOS, unavailable)
extension INShortcut: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .intent(intent): return "INShortcut.intent(\(intent))"
        case let .userActivity(activity): return "INShortcut.userActivity(\(activity))"
        }
    }
}

@available(iOS 12.0, macOS 11.0, watchOS 5.0, *)
@available(tvOS, unavailable)
extension INShortcut: CustomDebugStringConvertible {
    public var debugDescription: String { description }
}

@available(iOS 12.0, macOS 11.0, watchOS 5.0, *)
@available(tvOS, unavailable)
extension INShortcut: Hashable {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .intent(intent):
            hasher.combine(0)
            hasher.combine(intent)
        case let .userActivity(activity):
            hasher.combine(1)
            hasher.combine(activity)
        }
    }

    public var hashValue: Int {
        var hasher = Hasher()
        hash(into: &hasher)
        return hasher.finalize()
    }
}

@available(iOS 12.0, macOS 11.0, watchOS 5.0, *)
@available(tvOS, unavailable)
extension INShortcut: Equatable {
    public static func == (a: INShortcut, b: INShortcut) -> Bool {
        switch (a, b) {
        case let (.intent(a), .intent(b)): return a.isEqual(b)
        case let (.userActivity(a), .userActivity(b)): return a.isEqual(b)
        default: return false
        }
    }
}

@available(iOS 12.0, macOS 11.0, watchOS 5.0, *)
@available(tvOS, unavailable)
extension INShortcut: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> INShortcutReference {
        switch self {
        case let .intent(intent):
            // A shortcut of an intent was checked when made.
            return INShortcutReference(intent: intent)!
        case let .userActivity(activity):
            return INShortcutReference(userActivity: activity)
        }
    }

    public static func _forceBridgeFromObjectiveC(_ source: INShortcutReference, result: inout INShortcut?) {
        result = _unconditionallyBridgeFromObjectiveC(source)
    }

    public static func _conditionallyBridgeFromObjectiveC(_ source: INShortcutReference, result: inout INShortcut?) -> Bool {
        if let intent = source.intent {
            result = .intent(intent)
        } else if let activity = source.userActivity {
            result = .userActivity(activity)
        } else {
            result = nil
        }
        return result != nil
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: INShortcutReference?) -> INShortcut {
        var result: INShortcut?
        if let source, _conditionallyBridgeFromObjectiveC(source, result: &result), let result {
            return result
        }
        fatalError("INShortcut with neither an intent nor a user activity")
    }

    @available(macOS 11.0, iOS 12.0, watchOS 5.0, *)
    @available(tvOS, unavailable)
    public typealias _ObjectiveCType = INShortcutReference
}

@available(macOS 10.15.4, iOS 13.0, watchOS 6.0, tvOS 14.0, *)
@available(macOS, unavailable)
public enum INMediaDestination: ReferenceConvertible {
    public typealias ReferenceType = INMediaDestinationReference
    case library
    case playlist(String)
}

@available(macOS 10.15.4, iOS 13.0, watchOS 6.0, tvOS 14.0, *)
@available(macOS, unavailable)
extension INMediaDestination {
    public var playlistName: String? {
        guard case let .playlist(name) = self else { return nil }
        return name
    }
}

@available(macOS 10.15.4, iOS 13.0, watchOS 6.0, tvOS 14.0, *)
@available(macOS, unavailable)
extension INMediaDestination: CustomStringConvertible {
    public var description: String {
        switch self {
        case .library: return "INMediaDestination.library"
        case let .playlist(name): return "INMediaDestination.playlist(\(name))"
        }
    }
}

@available(macOS 10.15.4, iOS 13.0, watchOS 6.0, tvOS 14.0, *)
@available(macOS, unavailable)
extension INMediaDestination: CustomDebugStringConvertible {
    public var debugDescription: String { description }
}

@available(macOS 10.15.4, iOS 13.0, watchOS 6.0, tvOS 14.0, *)
@available(macOS, unavailable)
extension INMediaDestination: Hashable {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .library:
            hasher.combine(0)
        case let .playlist(name):
            hasher.combine(1)
            hasher.combine(name)
        }
    }

    public var hashValue: Int {
        var hasher = Hasher()
        hash(into: &hasher)
        return hasher.finalize()
    }
}

@available(macOS 10.15.4, iOS 13.0, watchOS 6.0, tvOS 14.0, *)
@available(macOS, unavailable)
extension INMediaDestination: Equatable {
    public static func == (a: INMediaDestination, b: INMediaDestination) -> Bool {
        switch (a, b) {
        case (.library, .library): return true
        case let (.playlist(a), .playlist(b)): return a == b
        default: return false
        }
    }
}

@available(macOS 10.15.4, iOS 13.0, watchOS 6.0, tvOS 14.0, *)
@available(macOS, unavailable)
extension INMediaDestination: _ObjectiveCBridgeable {
    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> INMediaDestinationReference {
        switch self {
        case .library: return INMediaDestinationReference.library()
        case let .playlist(name): return INMediaDestinationReference.playlistDestination(withName: name)
        }
    }

    public static func _forceBridgeFromObjectiveC(_ source: INMediaDestinationReference, result: inout INMediaDestination?) {
        result = _unconditionallyBridgeFromObjectiveC(source)
    }

    public static func _conditionallyBridgeFromObjectiveC(_ source: INMediaDestinationReference, result: inout INMediaDestination?) -> Bool {
        switch source.mediaDestinationType {
        case .library: result = .library
        case .playlist: result = .playlist(source.playlistName ?? "")
        default: result = nil
        }
        return result != nil
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: INMediaDestinationReference?) -> INMediaDestination {
        var result: INMediaDestination?
        if let source, _conditionallyBridgeFromObjectiveC(source, result: &result), let result {
            return result
        }
        return .library
    }

    @available(iOS 13.0, tvOS 14.0, watchOS 6.0, *)
    @available(macOS, unavailable, introduced: 10.15.4)
    public typealias _ObjectiveCType = INMediaDestinationReference
}
