// The Dispatch overlay's own types that the scheduler's API names. This
// module is compiled over the C headers alone, as the overlay it adds to
// is, so it declares them again, laid out as the overlay's are; programs
// take them from the overlay, which the loader looks in first.

public struct DispatchTime: Comparable, Sendable {
    public let rawValue: dispatch_time_t

    init(rawValue: dispatch_time_t) {
        self.rawValue = rawValue
    }

    public static func now() -> DispatchTime {
        DispatchTime(rawValue: __dispatch_time(0, 0))
    }

    public init(uptimeNanoseconds: UInt64) {
        rawValue = uptimeNanoseconds
    }

    public var uptimeNanoseconds: UInt64 { rawValue }

    public static func < (a: DispatchTime, b: DispatchTime) -> Bool { a.rawValue < b.rawValue }
    public static func == (a: DispatchTime, b: DispatchTime) -> Bool { a.rawValue == b.rawValue }
}

public enum DispatchTimeInterval: Equatable, Sendable {
    case seconds(Int)
    case milliseconds(Int)
    case microseconds(Int)
    case nanoseconds(Int)
    case never
}

public struct DispatchQoS: Equatable, Sendable {
    public let qosClass: QoSClass
    public let relativePriority: Int

    public static let unspecified = DispatchQoS(qosClass: .unspecified, relativePriority: 0)

    public enum QoSClass: Sendable {
        case background
        case utility
        case `default`
        case userInitiated
        case userInteractive
        case unspecified
    }
}

public struct DispatchWorkItemFlags: OptionSet, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }
}
