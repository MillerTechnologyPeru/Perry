// CMTime and CMTimeRange's Swift API (initializers, properties, operators
// and the macros of CMTime.h and CMTimeRange.h as functions) over Core
// Media's C functions, as the Swift 5.0 overlay had it.

extension CMTime {
    public init(seconds: Double, preferredTimescale: CMTimeScale) {
        self = CMTimeMakeWithSeconds(seconds, preferredTimescale: preferredTimescale)
    }

    public init(value: CMTimeValue, timescale: CMTimeScale) {
        self = CMTimeMake(value: value, timescale: timescale)
    }
}

extension CMTime {
    public var isValid: Bool { flags.contains(.valid) }
    public var isPositiveInfinity: Bool { isValid && flags.contains(.positiveInfinity) }
    public var isNegativeInfinity: Bool { isValid && flags.contains(.negativeInfinity) }
    public var isIndefinite: Bool { isValid && flags.contains(.indefinite) }

    public var isNumeric: Bool {
        flags.intersection([.valid, .impliedValueFlagsMask]) == .valid
    }

    public var hasBeenRounded: Bool { isNumeric && flags.contains(.hasBeenRounded) }
    public var seconds: Double { CMTimeGetSeconds(self) }

    public func convertScale(_ newTimescale: Int32, method: CMTimeRoundingMethod) -> CMTime {
        CMTimeConvertScale(self, timescale: newTimescale, method: method)
    }
}

public func CMTIME_IS_VALID(_ time: CMTime) -> Bool { time.isValid }
public func CMTIME_IS_INVALID(_ time: CMTime) -> Bool { !time.isValid }
public func CMTIME_IS_POSITIVEINFINITY(_ time: CMTime) -> Bool { time.isPositiveInfinity }
public func CMTIME_IS_NEGATIVEINFINITY(_ time: CMTime) -> Bool { time.isNegativeInfinity }
public func CMTIME_IS_INDEFINITE(_ time: CMTime) -> Bool { time.isIndefinite }
public func CMTIME_IS_NUMERIC(_ time: CMTime) -> Bool { time.isNumeric }
public func CMTIME_HAS_BEEN_ROUNDED(_ time: CMTime) -> Bool { time.hasBeenRounded }

extension CMTime {
    public static func + (addend1: CMTime, addend2: CMTime) -> CMTime {
        CMTimeAdd(addend1, addend2)
    }

    public static func - (minuend: CMTime, subtrahend: CMTime) -> CMTime {
        CMTimeSubtract(minuend, subtrahend)
    }
}

extension CMTime: Equatable, Comparable {
    public static func < (time1: CMTime, time2: CMTime) -> Bool { CMTimeCompare(time1, time2) < 0 }
    public static func <= (time1: CMTime, time2: CMTime) -> Bool { CMTimeCompare(time1, time2) <= 0 }
    public static func > (time1: CMTime, time2: CMTime) -> Bool { CMTimeCompare(time1, time2) > 0 }
    public static func >= (time1: CMTime, time2: CMTime) -> Bool { CMTimeCompare(time1, time2) >= 0 }
    public static func == (time1: CMTime, time2: CMTime) -> Bool { CMTimeCompare(time1, time2) == 0 }
    public static func != (time1: CMTime, time2: CMTime) -> Bool { CMTimeCompare(time1, time2) != 0 }
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
extension CMTime: Hashable {
    /// Equal times hash alike: a numeric time as its epoch and its value
    /// over its timescale in lowest terms (1/2 equals 2/4), any other by
    /// the flags that make it what it is.
    public func hash(into hasher: inout Hasher) {
        if isNumeric {
            var a = value.magnitude, b = UInt64(timescale.magnitude)
            while b != 0 { (a, b) = (b, a % b) }
            let divisor = Int64(max(a, 1))
            hasher.combine(epoch)
            hasher.combine(value / divisor)
            hasher.combine(Int64(timescale) / divisor)
        } else {
            hasher.combine(flags.intersection([.valid, .impliedValueFlagsMask]).rawValue)
        }
    }

    public var hashValue: Int {
        var hasher = Hasher()
        hash(into: &hasher)
        return hasher.finalize()
    }
}

extension CMTimeRange {
    public init(start: CMTime, end: CMTime) {
        self = CMTimeRangeFromTimeToTime(start: start, end: end)
    }

    public var isValid: Bool {
        start.isValid && duration.isValid && duration.epoch == 0 && duration.value >= 0
    }

    public var isIndefinite: Bool {
        isValid && (start.isIndefinite || duration.isIndefinite)
    }

    public var isEmpty: Bool {
        isValid && duration == .zero
    }

    public var end: CMTime { CMTimeRangeGetEnd(self) }

    public func union(_ otherRange: CMTimeRange) -> CMTimeRange {
        CMTimeRangeGetUnion(self, otherRange: otherRange)
    }

    public func intersection(_ otherRange: CMTimeRange) -> CMTimeRange {
        CMTimeRangeGetIntersection(self, otherRange: otherRange)
    }

    public func containsTime(_ time: CMTime) -> Bool {
        CMTimeRangeContainsTime(self, time: time)
    }

    public func containsTimeRange(_ range: CMTimeRange) -> Bool {
        CMTimeRangeContainsTimeRange(self, otherRange: range)
    }
}

public func CMTIMERANGE_IS_VALID(_ range: CMTimeRange) -> Bool { range.isValid }
public func CMTIMERANGE_IS_INVALID(_ range: CMTimeRange) -> Bool { !range.isValid }
public func CMTIMERANGE_IS_INDEFINITE(_ range: CMTimeRange) -> Bool { range.isIndefinite }
public func CMTIMERANGE_IS_EMPTY(_ range: CMTimeRange) -> Bool { range.isEmpty }

extension CMTimeRange: Equatable {
    public static func == (range1: CMTimeRange, range2: CMTimeRange) -> Bool {
        CMTimeRangeEqual(range1, range2)
    }

    public static func != (range1: CMTimeRange, range2: CMTimeRange) -> Bool {
        !CMTimeRangeEqual(range1, range2)
    }
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
extension CMTimeRange: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(start)
        hasher.combine(duration)
    }

    public var hashValue: Int {
        var hasher = Hasher()
        hash(into: &hasher)
        return hasher.finalize()
    }
}
