import Combine
import Dispatch

// Foundation's adoptions of Combine: run loops and operation queues are
// schedulers, as Combine's operators take them.

// MARK: RunLoop

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension RunLoop: Scheduler {
    /// A moment the scheduler runs work at: a date.
    public struct SchedulerTimeType: Strideable, Codable, Hashable, Sendable {
        public var date: Date

        public init(_ date: Date) { self.date = date }

        public func distance(to other: SchedulerTimeType) -> Stride {
            Stride(other.date.timeIntervalSince(date))
        }

        public func advanced(by n: Stride) -> SchedulerTimeType {
            SchedulerTimeType(date.addingTimeInterval(n.magnitude))
        }

        /// A time interval, in seconds.
        public struct Stride: ExpressibleByFloatLiteral, Comparable, SignedNumeric, Codable, SchedulerTimeIntervalConvertible, Sendable {
            public typealias FloatLiteralType = TimeInterval
            public typealias IntegerLiteralType = TimeInterval

            public var magnitude: TimeInterval
            public var timeInterval: TimeInterval { magnitude }

            public init(integerLiteral value: TimeInterval) { magnitude = value }
            public init(floatLiteral value: TimeInterval) { magnitude = value }
            public init(_ timeInterval: TimeInterval) { magnitude = timeInterval }
            public init?<T: BinaryInteger>(exactly source: T) {
                guard let value = TimeInterval(exactly: source) else { return nil }
                magnitude = value
            }

            public static func < (lhs: Stride, rhs: Stride) -> Bool { lhs.magnitude < rhs.magnitude }
            public static func * (lhs: Stride, rhs: Stride) -> Stride { Stride(lhs.magnitude * rhs.magnitude) }
            public static func + (lhs: Stride, rhs: Stride) -> Stride { Stride(lhs.magnitude + rhs.magnitude) }
            public static func - (lhs: Stride, rhs: Stride) -> Stride { Stride(lhs.magnitude - rhs.magnitude) }
            public static func *= (lhs: inout Stride, rhs: Stride) { lhs = lhs * rhs }
            public static func += (lhs: inout Stride, rhs: Stride) { lhs = lhs + rhs }
            public static func -= (lhs: inout Stride, rhs: Stride) { lhs = lhs - rhs }

            public static func seconds(_ s: Int) -> Stride { Stride(TimeInterval(s)) }
            public static func seconds(_ s: Double) -> Stride { Stride(s) }
            public static func milliseconds(_ ms: Int) -> Stride { Stride(TimeInterval(ms) / 1_000) }
            public static func microseconds(_ us: Int) -> Stride { Stride(TimeInterval(us) / 1_000_000) }
            public static func nanoseconds(_ ns: Int) -> Stride { Stride(TimeInterval(ns) / 1_000_000_000) }
        }
    }

    public struct SchedulerOptions: Sendable {}

    public var now: SchedulerTimeType { SchedulerTimeType(Date()) }
    public var minimumTolerance: SchedulerTimeType.Stride { SchedulerTimeType.Stride(0) }

    /// Runs the action on this run loop's next pass.
    public func schedule(options: SchedulerOptions?, _ action: @escaping () -> Void) {
        perform(action)
    }

    /// Runs the action once, at the date, from a timer in the default mode.
    public func schedule(after date: SchedulerTimeType, tolerance: SchedulerTimeType.Stride, options: SchedulerOptions?,
                         _ action: @escaping () -> Void) {
        let timer = Timer(fire: date.date, interval: 0, repeats: false) { _ in action() }
        timer.tolerance = tolerance.magnitude
        add(timer, forMode: .default)
    }

    /// Runs the action at the date and every interval after, until
    /// cancelled.
    public func schedule(after date: SchedulerTimeType, interval: SchedulerTimeType.Stride, tolerance: SchedulerTimeType.Stride,
                         options: SchedulerOptions?, _ action: @escaping () -> Void) -> any Cancellable {
        let timer = Timer(fire: date.date, interval: interval.magnitude, repeats: true) { _ in action() }
        timer.tolerance = tolerance.magnitude
        add(timer, forMode: .default)
        return AnyCancellable { timer.invalidate() }
    }
}

// MARK: OperationQueue

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension OperationQueue: Scheduler {
    /// A moment the scheduler runs work at: a date.
    public struct SchedulerTimeType: Strideable, Codable, Hashable, Sendable {
        public var date: Date

        public init(_ date: Date) { self.date = date }

        public func distance(to other: SchedulerTimeType) -> Stride {
            Stride(other.date.timeIntervalSince(date))
        }

        public func advanced(by n: Stride) -> SchedulerTimeType {
            SchedulerTimeType(date.addingTimeInterval(n.magnitude))
        }

        /// A time interval, in seconds.
        public struct Stride: ExpressibleByFloatLiteral, Comparable, SignedNumeric, Codable, SchedulerTimeIntervalConvertible, Sendable {
            public typealias FloatLiteralType = TimeInterval
            public typealias IntegerLiteralType = TimeInterval

            public var magnitude: TimeInterval
            public var timeInterval: TimeInterval { magnitude }

            public init(integerLiteral value: TimeInterval) { magnitude = value }
            public init(floatLiteral value: TimeInterval) { magnitude = value }
            public init(_ timeInterval: TimeInterval) { magnitude = timeInterval }
            public init?<T: BinaryInteger>(exactly source: T) {
                guard let value = TimeInterval(exactly: source) else { return nil }
                magnitude = value
            }

            public static func < (lhs: Stride, rhs: Stride) -> Bool { lhs.magnitude < rhs.magnitude }
            public static func * (lhs: Stride, rhs: Stride) -> Stride { Stride(lhs.magnitude * rhs.magnitude) }
            public static func + (lhs: Stride, rhs: Stride) -> Stride { Stride(lhs.magnitude + rhs.magnitude) }
            public static func - (lhs: Stride, rhs: Stride) -> Stride { Stride(lhs.magnitude - rhs.magnitude) }
            public static func *= (lhs: inout Stride, rhs: Stride) { lhs = lhs * rhs }
            public static func += (lhs: inout Stride, rhs: Stride) { lhs = lhs + rhs }
            public static func -= (lhs: inout Stride, rhs: Stride) { lhs = lhs - rhs }

            public static func seconds(_ s: Int) -> Stride { Stride(TimeInterval(s)) }
            public static func seconds(_ s: Double) -> Stride { Stride(s) }
            public static func milliseconds(_ ms: Int) -> Stride { Stride(TimeInterval(ms) / 1_000) }
            public static func microseconds(_ us: Int) -> Stride { Stride(TimeInterval(us) / 1_000_000) }
            public static func nanoseconds(_ ns: Int) -> Stride { Stride(TimeInterval(ns) / 1_000_000_000) }
        }
    }

    public struct SchedulerOptions: Sendable {}

    public var now: SchedulerTimeType { SchedulerTimeType(Date()) }
    public var minimumTolerance: SchedulerTimeType.Stride { SchedulerTimeType.Stride(0) }

    public func schedule(options: SchedulerOptions?, _ action: @escaping () -> Void) {
        addOperation(action)
    }

    /// Adds the action as an operation once the date comes.
    public func schedule(after date: SchedulerTimeType, tolerance: SchedulerTimeType.Stride, options: SchedulerOptions?,
                         _ action: @escaping () -> Void) {
        let delay = Swift.max(date.date.timeIntervalSinceNow, 0)
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in self?.addOperation(action) }
    }

    /// Adds the action as an operation at the date and every interval after,
    /// until cancelled.
    public func schedule(after date: SchedulerTimeType, interval: SchedulerTimeType.Stride, tolerance: SchedulerTimeType.Stride,
                         options: SchedulerOptions?, _ action: @escaping () -> Void) -> any Cancellable {
        let timer = DispatchSource.makeTimerSource()
        timer.schedule(deadline: .now() + Swift.max(date.date.timeIntervalSinceNow, 0), repeating: interval.magnitude,
                       leeway: .nanoseconds(Int(tolerance.magnitude * 1_000_000_000)))
        timer.setEventHandler { [weak self] in self?.addOperation(action) }
        timer.resume()
        return AnyCancellable { timer.cancel() }
    }
}
