import CPerryFoundation
import FoundationEssentials
import PerryObjCInterop

// CFDateInterval, CoreFoundation's private type that NSDateInterval bridges
// to: a date interval is an NSDateInterval object, a start date and a
// non-negative duration. Darwin gives it no public type ID function.

private enum DateIntervalObjects {
    /// NSDateInterval's class, looked up by name.
    static var intervalClass: id? { ObjC.getClass("NSDateInterval").map(UnsafeMutableRawPointer.init) }

    static func value(_ object: id?) -> DateInterval {
        guard let storage = Storage.get(object, as: DateIntervalStorage.self) else {
            return DateInterval(start: Date(timeIntervalSinceReferenceDate: 0), duration: 0)
        }
        return DateInterval(start: storage.start, duration: max(storage.duration, 0))
    }

    /// A new interval (+1).
    static func make(start: Date, duration: Double) -> id? {
        guard let object = Storage.allocate(intervalClass) else { return nil }
        Storage.set(object, DateIntervalStorage(start: start, duration: max(duration, 0)))
        return object
    }
}

/// An interval of the duration from the start date (+1).
@DarwinC("_CFDateIntervalCreate")
public func CFDateIntervalCreate(_ allocator: UnsafeRawPointer?, _ start: id?, _ duration: Double) -> id? {
    DateIntervalObjects.make(start: Dates.date(start), duration: duration)
}

/// The interval from the start date to the end date (+1); an end before
/// the start makes it empty.
@c(_CFDateIntervalCreateWithEndDate)
public func CFDateIntervalCreateWithEndDate(_ allocator: UnsafeRawPointer?, _ start: id?, _ end: id?) -> id? {
    let startDate = Dates.date(start)
    return DateIntervalObjects.make(start: startDate, duration: Dates.date(end).timeIntervalSince(startDate))
}

/// The start date (+1).
@c(_CFDateIntervalCopyStartDate)
public func CFDateIntervalCopyStartDate(_ interval: id?) -> id? {
    ObjC.retain(Dates.autoreleased(DateIntervalObjects.value(interval).start))
}

/// The end date (+1).
@c(_CFDateIntervalCopyEndDate)
public func CFDateIntervalCopyEndDate(_ interval: id?) -> id? {
    ObjC.retain(Dates.autoreleased(DateIntervalObjects.value(interval).end))
}

@DarwinC("_CFDateIntervalGetDuration")
public func CFDateIntervalGetDuration(_ interval: id?) -> Double { DateIntervalObjects.value(interval).duration }

/// CFComparisonResult: by start date, then by duration.
@c(_CFDateIntervalCompare)
public func CFDateIntervalCompare(_ interval: id?, _ other: id?) -> Int {
    switch DateIntervalObjects.value(interval).compare(DateIntervalObjects.value(other)) {
    case .orderedAscending: return -1
    case .orderedSame: return 0
    case .orderedDescending: return 1
    }
}

/// Whether the date is within the interval, its ends included.
@c(_CFDateIntervalContainsDate)
public func CFDateIntervalContainsDate(_ interval: id?, _ date: id?) -> Bool {
    DateIntervalObjects.value(interval).contains(Dates.date(date))
}

/// Whether the intervals overlap or meet.
@c(_CFDateIntervalIntersectsDateInterval)
public func CFDateIntervalIntersectsDateInterval(_ interval: id?, _ other: id?) -> Bool {
    DateIntervalObjects.value(interval).intersects(DateIntervalObjects.value(other))
}

/// The intervals' overlap (+1), or NULL if they don't meet.
@c(_CFDateIntervalCreateIntersectionWithDateInterval)
public func CFDateIntervalCreateIntersectionWithDateInterval(_ allocator: UnsafeRawPointer?, _ interval: id?, _ other: id?) -> id? {
    guard let overlap = DateIntervalObjects.value(interval).intersection(with: DateIntervalObjects.value(other)) else { return nil }
    return DateIntervalObjects.make(start: overlap.start, duration: overlap.duration)
}
