import Darwin

// DispatchTime (the uptime clock), DispatchWallTime (the calendar clock)
// and DispatchTimeInterval, over dispatch_time_t, as the overlay's API has
// them.

private let nanosecondsPerSecond: Int64 = 1_000_000_000

/// dispatch_time and dispatch_walltime, which Swift's import of the headers
/// leaves out in favor of these types.
@_silgen_name("dispatch_time")
private func dispatchTime(_ when: dispatch_time_t, _ delta: Int64) -> dispatch_time_t

@_silgen_name("dispatch_walltime")
private func dispatchWallTime(_ when: UnsafePointer<timespec>?, _ delta: Int64) -> dispatch_time_t

/// DISPATCH_TIME_NOW and DISPATCH_TIME_FOREVER.
let dispatchTimeNow: dispatch_time_t = 0
let dispatchTimeForever: dispatch_time_t = ~0

public struct DispatchTime: Comparable, Sendable {
    public let rawValue: dispatch_time_t

    public static func now() -> DispatchTime {
        DispatchTime(rawValue: dispatchTime(dispatchTimeNow, 0))
    }

    public static let distantFuture = DispatchTime(rawValue: dispatchTimeForever)

    private init(rawValue: dispatch_time_t) {
        self.rawValue = rawValue
    }

    /// A time this many nanoseconds after the clock started. On Darwin the
    /// uptime clock counts nanoseconds; the forever value is kept.
    public init(uptimeNanoseconds: UInt64) {
        rawValue = uptimeNanoseconds == dispatchTimeForever ? dispatchTimeForever - 1 : uptimeNanoseconds
    }

    public var uptimeNanoseconds: UInt64 { rawValue }

    /// Internal: from a raw value, for the arithmetic below.
    init(_raw: dispatch_time_t) {
        rawValue = _raw
    }
}

extension DispatchTime {
    public static func < (a: DispatchTime, b: DispatchTime) -> Bool { a.rawValue < b.rawValue }
    public static func == (a: DispatchTime, b: DispatchTime) -> Bool { a.rawValue == b.rawValue }
}

public struct DispatchWallTime: Comparable, Sendable {
    public let rawValue: dispatch_time_t

    public static func now() -> DispatchWallTime {
        DispatchWallTime(_raw: dispatchWallTime(nil, 0))
    }

    public static let distantFuture = DispatchWallTime(_raw: dispatchTimeForever)

    init(_raw: dispatch_time_t) {
        rawValue = _raw
    }

    public init(timespec: timespec) {
        var time = timespec
        rawValue = dispatchWallTime(&time, 0)
    }
}

extension DispatchWallTime {
    /// Wall times are stored as negative numbers, so the comparison is of
    /// their magnitudes; forever is after every other time.
    public static func < (a: DispatchWallTime, b: DispatchWallTime) -> Bool {
        if b.rawValue == dispatchTimeForever { return a.rawValue != dispatchTimeForever }
        if a.rawValue == dispatchTimeForever { return false }
        return -Int64(bitPattern: a.rawValue) < -Int64(bitPattern: b.rawValue)
    }

    public static func == (a: DispatchWallTime, b: DispatchWallTime) -> Bool { a.rawValue == b.rawValue }
}

public enum DispatchTimeInterval: Equatable, Sendable {
    case seconds(Int)
    case milliseconds(Int)
    case microseconds(Int)
    case nanoseconds(Int)
    case never

    /// Nanoseconds, saturated at Int64's range; never is Int64.max.
    var rawValue: Int64 {
        switch self {
        case .seconds(let s): return scaled(s, by: nanosecondsPerSecond)
        case .milliseconds(let ms): return scaled(ms, by: 1_000_000)
        case .microseconds(let us): return scaled(us, by: 1_000)
        case .nanoseconds(let ns): return Int64(ns)
        case .never: return .max
        }
    }

    public static func == (lhs: DispatchTimeInterval, rhs: DispatchTimeInterval) -> Bool {
        switch (lhs, rhs) {
        case (.never, .never): return true
        case (.never, _), (_, .never): return false
        default: return lhs.rawValue == rhs.rawValue
        }
    }
}

/// `value` times `factor`, saturated at Int64's range.
private func scaled(_ value: Int, by factor: Int64) -> Int64 {
    let product = Int64(value).multipliedReportingOverflow(by: factor)
    return product.overflow ? (value < 0 ? .min : .max) : product.partialValue
}

/// Nanoseconds in `seconds`, saturated.
private func nanoseconds(_ seconds: Double) -> Int64 {
    let value = (seconds * Double(nanosecondsPerSecond)).rounded()
    if value >= Double(Int64.max) { return .max }
    if value <= Double(Int64.min) { return .min }
    return Int64(value)
}

/// An interval of never added to a time gives forever.
private func offset(_ time: dispatch_time_t, _ interval: DispatchTimeInterval) -> dispatch_time_t {
    interval == .never ? dispatchTimeForever : dispatchTime(time, interval.rawValue)
}

public func + (time: DispatchTime, interval: DispatchTimeInterval) -> DispatchTime {
    DispatchTime(_raw: offset(time.rawValue, interval))
}

public func - (time: DispatchTime, interval: DispatchTimeInterval) -> DispatchTime {
    interval == .never ? DispatchTime(_raw: dispatchTimeForever) : DispatchTime(_raw: dispatchTime(time.rawValue, -interval.rawValue))
}

public func + (time: DispatchTime, seconds: Double) -> DispatchTime {
    DispatchTime(_raw: dispatchTime(time.rawValue, nanoseconds(seconds)))
}

public func - (time: DispatchTime, seconds: Double) -> DispatchTime {
    DispatchTime(_raw: dispatchTime(time.rawValue, nanoseconds(-seconds)))
}

public func + (time: DispatchWallTime, interval: DispatchTimeInterval) -> DispatchWallTime {
    DispatchWallTime(_raw: offset(time.rawValue, interval))
}

public func - (time: DispatchWallTime, interval: DispatchTimeInterval) -> DispatchWallTime {
    interval == .never ? DispatchWallTime(_raw: dispatchTimeForever) : DispatchWallTime(_raw: dispatchTime(time.rawValue, -interval.rawValue))
}

public func + (time: DispatchWallTime, seconds: Double) -> DispatchWallTime {
    DispatchWallTime(_raw: dispatchTime(time.rawValue, nanoseconds(seconds)))
}

public func - (time: DispatchWallTime, seconds: Double) -> DispatchWallTime {
    DispatchWallTime(_raw: dispatchTime(time.rawValue, nanoseconds(-seconds)))
}

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension DispatchTime {
    public func distance(to other: DispatchTime) -> DispatchTimeInterval {
        let to = other.rawValue, from = rawValue
        if to == dispatchTimeForever || from == dispatchTimeForever { return .never }
        return .nanoseconds(to >= from ? Int(clamping: to - from) : -Int(clamping: from - to))
    }

    public func advanced(by n: DispatchTimeInterval) -> DispatchTime { self + n }
}
