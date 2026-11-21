import os.log
import os.signpost
import os.lock

// What OSSignposter's transparent interval methods call: the state an
// interval hands from its begin to its end, and the check that it ends
// once.

@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
public struct OSSignpostID: Sendable {
    public let rawValue: os_signpost_id_t

    public init(_ value: UInt64) {
        rawValue = value
    }
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
@usableFromInline
internal enum OSSignpostError {
    case doubleEnd
    case none
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public class OSSignpostIntervalState: Codable, @unchecked Sendable {
    @usableFromInline
    internal final let signpostID: OSSignpostID
    private var isOpen: Bool
    private var lock = os_unfair_lock()

    @usableFromInline
    internal init(id: OSSignpostID, isOpen: Bool = true) {
        signpostID = id
        self.isOpen = isOpen
    }

    private enum CodingKeys: String, CodingKey {
        case signpostID
        case isOpen
    }

    public required init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        signpostID = OSSignpostID(try container.decode(UInt64.self, forKey: .signpostID))
        isOpen = try container.decode(Bool.self, forKey: .isOpen)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(signpostID.rawValue, forKey: .signpostID)
        try container.encode(isOpen, forKey: .isOpen)
    }

    public func _hasValue(id: OSSignpostID, isOpen: Bool) -> Bool {
        signpostID.rawValue == id.rawValue && self.isOpen == isOpen
    }

    /// Closes the interval, saying whether it was closed already.
    fileprivate func consume() -> OSSignpostError {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard isOpen else { return .doubleEnd }
        isOpen = false
        return .none
    }
}

@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
@usableFromInline
internal func checkForErrorAndConsumeState(state: OSSignpostIntervalState) -> OSSignpostError {
    state.consume()
}
