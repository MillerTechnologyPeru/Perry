import _DarwinFoundation2._time
import _DarwinFoundation2.sys_time.timeval

// timeval and timespec as Swift Durations, and back.

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, visionOS 1.0, *)
extension timeval {
    /// The duration, to the microsecond (truncated), with a nonnegative
    /// tv_usec.
    public init(_ duration: Duration) {
        let (seconds, attoseconds) = duration.components
        var whole = seconds
        var micro = attoseconds / 1_000_000_000_000
        if micro < 0 {
            whole -= 1
            micro += 1_000_000
        }
        self.init(tv_sec: __darwin_time_t(whole), tv_usec: __darwin_suseconds_t(micro))
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, visionOS 1.0, *)
extension Duration {
    public init(_ tv: timeval) {
        self = .seconds(Int64(tv.tv_sec)) + .microseconds(Int64(tv.tv_usec))
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, visionOS 1.0, *)
extension timespec {
    /// The duration, to the nanosecond (truncated), with a nonnegative
    /// tv_nsec.
    public init(_ duration: Duration) {
        let (seconds, attoseconds) = duration.components
        var whole = seconds
        var nano = attoseconds / 1_000_000_000
        if nano < 0 {
            whole -= 1
            nano += 1_000_000_000
        }
        self.init(tv_sec: __darwin_time_t(whole), tv_nsec: Int(nano))
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, visionOS 1.0, *)
extension Duration {
    public init(_ ts: timespec) {
        self = .seconds(Int64(ts.tv_sec)) + .nanoseconds(Int64(ts.tv_nsec))
    }
}
