import Combine
import Darwin

// DispatchQueue as a Combine scheduler, which the Dispatch overlay has had
// since Combine came: receive(on:), debounce and delay on a queue.

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
extension DispatchQueue: Scheduler {
    /// A time on a queue's clock: a DispatchTime.
    public struct SchedulerTimeType: Strideable, Codable, Hashable, Sendable {
        public var dispatchTime: DispatchTime

        public init(_ time: DispatchTime) {
            dispatchTime = time
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            dispatchTime = DispatchTime(uptimeNanoseconds: try container.decode(UInt64.self))
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(dispatchTime.uptimeNanoseconds)
        }

        public func distance(to other: SchedulerTimeType) -> Stride {
            let from = dispatchTime.uptimeNanoseconds, to = other.dispatchTime.uptimeNanoseconds
            return Stride(nanoseconds: to >= from ? Int(clamping: to - from) : -Int(clamping: from - to))
        }

        public func advanced(by n: Stride) -> SchedulerTimeType {
            let now = dispatchTime.uptimeNanoseconds
            let moved = n.magnitude >= 0
                ? now.addingReportingOverflow(UInt64(n.magnitude))
                : now.subtractingReportingOverflow(UInt64(-(n.magnitude + 1)) + 1)
            let nanoseconds = moved.overflow ? (n.magnitude >= 0 ? UInt64.max : 0) : moved.partialValue
            return SchedulerTimeType(DispatchTime(uptimeNanoseconds: nanoseconds))
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(dispatchTime.uptimeNanoseconds)
        }

        public static func == (lhs: SchedulerTimeType, rhs: SchedulerTimeType) -> Bool {
            lhs.dispatchTime.uptimeNanoseconds == rhs.dispatchTime.uptimeNanoseconds
        }

        public static func < (lhs: SchedulerTimeType, rhs: SchedulerTimeType) -> Bool {
            lhs.dispatchTime.uptimeNanoseconds < rhs.dispatchTime.uptimeNanoseconds
        }

        /// A length of time, in nanoseconds.
        public struct Stride: SchedulerTimeIntervalConvertible, Comparable, SignedNumeric, ExpressibleByFloatLiteral, Hashable, Codable {
            public typealias FloatLiteralType = Double
            public typealias IntegerLiteralType = Int
            public typealias Magnitude = Int

            /// Nanoseconds.
            public var magnitude: Int

            public var timeInterval: DispatchTimeInterval { .nanoseconds(magnitude) }

            init(nanoseconds: Int) {
                magnitude = nanoseconds
            }

            public init(_ timeInterval: DispatchTimeInterval) {
                switch timeInterval {
                case .seconds(let value): magnitude = Stride.scaled(value, by: 1_000_000_000)
                case .milliseconds(let value): magnitude = Stride.scaled(value, by: 1_000_000)
                case .microseconds(let value): magnitude = Stride.scaled(value, by: 1_000)
                case .nanoseconds(let value): magnitude = value
                case .never: magnitude = .max
                @unknown default: magnitude = .max
                }
            }

            public init(floatLiteral value: Double) {
                magnitude = Stride.nanoseconds(seconds: value)
            }

            public init(integerLiteral value: Int) {
                magnitude = Stride.scaled(value, by: 1_000_000_000)
            }

            public init?<T>(exactly source: T) where T: BinaryInteger {
                guard let value = Int(exactly: source) else { return nil }
                magnitude = Stride.scaled(value, by: 1_000_000_000)
            }

            private static func scaled(_ value: Int, by factor: Int) -> Int {
                let result = value.multipliedReportingOverflow(by: factor)
                return result.overflow ? (value < 0 ? .min : .max) : result.partialValue
            }

            private static func nanoseconds(seconds: Double) -> Int {
                let value = seconds * 1_000_000_000
                guard value.isFinite else { return value < 0 ? .min : .max }
                return Int(exactly: value.rounded()) ?? (value < 0 ? .min : .max)
            }

            public static func < (lhs: Stride, rhs: Stride) -> Bool { lhs.magnitude < rhs.magnitude }
            public static func == (a: Stride, b: Stride) -> Bool { a.magnitude == b.magnitude }

            public static func * (lhs: Stride, rhs: Stride) -> Stride {
                Stride(nanoseconds: scaled(lhs.magnitude, by: rhs.magnitude))
            }

            public static func + (lhs: Stride, rhs: Stride) -> Stride {
                let sum = lhs.magnitude.addingReportingOverflow(rhs.magnitude)
                return Stride(nanoseconds: sum.overflow ? (rhs.magnitude < 0 ? .min : .max) : sum.partialValue)
            }

            public static func - (lhs: Stride, rhs: Stride) -> Stride {
                let difference = lhs.magnitude.subtractingReportingOverflow(rhs.magnitude)
                return Stride(nanoseconds: difference.overflow ? (rhs.magnitude < 0 ? .max : .min) : difference.partialValue)
            }

            public static func -= (lhs: inout Stride, rhs: Stride) { lhs = lhs - rhs }
            public static func *= (lhs: inout Stride, rhs: Stride) { lhs = lhs * rhs }
            public static func += (lhs: inout Stride, rhs: Stride) { lhs = lhs + rhs }

            public static func seconds(_ s: Double) -> Stride { Stride(nanoseconds: nanoseconds(seconds: s)) }
            public static func seconds(_ s: Int) -> Stride { Stride(nanoseconds: scaled(s, by: 1_000_000_000)) }
            public static func milliseconds(_ ms: Int) -> Stride { Stride(nanoseconds: scaled(ms, by: 1_000_000)) }
            public static func microseconds(_ us: Int) -> Stride { Stride(nanoseconds: scaled(us, by: 1_000)) }
            public static func nanoseconds(_ ns: Int) -> Stride { Stride(nanoseconds: ns) }

            public func encode(to encoder: any Encoder) throws {
                var container = encoder.singleValueContainer()
                try container.encode(magnitude)
            }

            public init(from decoder: any Decoder) throws {
                magnitude = try decoder.singleValueContainer().decode(Int.self)
            }

            public func hash(into hasher: inout Hasher) {
                hasher.combine(magnitude)
            }
        }
    }

    /// How a scheduled action runs: its quality of service, its work item
    /// flags and a group it joins.
    public struct SchedulerOptions: Sendable {
        public var qos: DispatchQoS
        public var flags: DispatchWorkItemFlags
        public var group: DispatchGroup?

        public init(qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [], group: DispatchGroup? = nil) {
            self.qos = qos
            self.flags = flags
            self.group = group
        }
    }

    public var minimumTolerance: SchedulerTimeType.Stride { .nanoseconds(0) }

    public var now: SchedulerTimeType { SchedulerTimeType(.now()) }

    public func schedule(options: SchedulerOptions?, _ action: @escaping () -> Void) {
        if let group = options?.group {
            __dispatch_group_async(group, self, action)
        } else {
            __dispatch_async(self, action)
        }
    }

    public func schedule(after date: SchedulerTimeType, tolerance: SchedulerTimeType.Stride, options: SchedulerOptions?,
                         _ action: @escaping () -> Void) {
        __dispatch_after(date.dispatchTime.rawValue, self, action)
    }

    public func schedule(after date: SchedulerTimeType, interval: SchedulerTimeType.Stride, tolerance: SchedulerTimeType.Stride,
                         options: SchedulerOptions?, _ action: @escaping () -> Void) -> any Cancellable {
        let timer = __dispatch_source_create(timerSourceType, 0, 0, self)
        __dispatch_source_set_event_handler(timer, action)
        __dispatch_source_set_timer(timer, date.dispatchTime.rawValue, UInt64(max(interval.magnitude, 0)),
                                  UInt64(max(tolerance.magnitude, 0)))
        resumeObject(timer)
        return AnyCancellable { __dispatch_source_cancel(timer) }
    }
}

/// DISPATCH_SOURCE_TYPE_TIMER, a macro over the address of a structure the
/// headers leave incomplete.
private let timerSourceType = OpaquePointer(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_dispatch_source_type_timer"))!

/// dispatch_resume, which the headers give Swift as a method of the
/// overlay's.
@_silgen_name("dispatch_resume")
private func resumeObject(_ object: AnyObject)
