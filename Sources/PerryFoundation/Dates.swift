import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

// NSDate is an Objective-C wrapper around swift-foundation's Date: Mach-O
// code needs the Objective-C class, and Date provides the value.

/// Seconds between 1970-01-01 and Darwin's reference date, 2001-01-01 UTC.
let referenceDateOffset = Date.timeIntervalBetween1970AndReferenceDate

/// CFAbsoluteTime: seconds since the reference date.
func absoluteTimeNow() -> Double {
    Date.now.timeIntervalSinceReferenceDate
}

/// An NSDate's value.
final class DateStorage {
    let date: Date

    init(_ date: Date) {
        self.date = date
    }
}

enum Dates {
    nonisolated(unsafe) static var dateClass: Class!

    static let distantFuture = Date.distantFuture.timeIntervalSinceReferenceDate
    static let distantPast = Date.distantPast.timeIntervalSinceReferenceDate

    static func date(_ object: id?) -> Date {
        Storage.get(object, as: DateStorage.self)?.date ?? Date(timeIntervalSinceReferenceDate: 0)
    }

    /// Seconds since the reference date, which run loops and timers use.
    static func interval(_ object: id?) -> Double {
        date(object).timeIntervalSinceReferenceDate
    }

    static func autoreleased(_ date: Date, cls: id? = nil) -> id? {
        guard let object = Storage.allocate(cls ?? UnsafeMutableRawPointer(dateClass)) else { return nil }
        Storage.set(object, DateStorage(date))
        return ObjC.autorelease(object)
    }

    static func autoreleased(_ interval: Double, cls: id? = nil) -> id? {
        autoreleased(Date(timeIntervalSinceReferenceDate: interval), cls: cls)
    }

    static func initialize(_ object: id?, _ date: Date) -> id? {
        if let object { Storage.set(object, DateStorage(date)) }
        return object
    }

    private static let descriptionStyle = Date.ISO8601FormatStyle(
        dateSeparator: .dash, dateTimeSeparator: .space, timeSeparator: .colon,
        timeZoneSeparator: .omitted, includingFractionalSeconds: false, timeZone: .gmt)

    /// "2001-01-01 00:00:00 +0000": -[NSDate description] in UTC.
    static func description(_ date: Date) -> String {
        var text = date.formatted(descriptionStyle)
        if text.hasSuffix("Z") { text.removeLast() }
        return text + " +0000"
    }

    static func install(superclass: Class) {
        dateClass = ClassDefinition(PERRY_CLASS_NSDate, name: "NSDate", superclass: superclass,
                                    StorageAllocation.self, NSDateMethods.self).cls
    }
}

@ObjCImplementation
enum NSDateMethods {
    // MARK: Creating

    @ObjCClassMethod("date")
    static func date(_ cls: id?) -> id? { Dates.autoreleased(Date.now, cls: cls) }

    @ObjCClassMethod("dateWithTimeIntervalSinceNow:")
    static func date(_ cls: id?, sinceNow seconds: Double) -> id? {
        Dates.autoreleased(Date(timeIntervalSinceNow: seconds), cls: cls)
    }

    @ObjCClassMethod("dateWithTimeIntervalSince1970:")
    static func date(_ cls: id?, since1970 seconds: Double) -> id? {
        Dates.autoreleased(Date(timeIntervalSince1970: seconds), cls: cls)
    }

    @ObjCClassMethod("dateWithTimeIntervalSinceReferenceDate:")
    static func date(_ cls: id?, sinceReferenceDate seconds: Double) -> id? { Dates.autoreleased(Date(timeIntervalSinceReferenceDate: seconds), cls: cls) }

    @ObjCClassMethod("distantFuture")
    static func distantFuture(_ cls: id?) -> id? { Dates.autoreleased(Date.distantFuture, cls: cls) }

    @ObjCClassMethod("distantPast")
    static func distantPast(_ cls: id?) -> id? { Dates.autoreleased(Date.distantPast, cls: cls) }

    @ObjCClassMethod("timeIntervalSinceReferenceDate")
    static func now(_ cls: id?) -> Double { absoluteTimeNow() }

    @ObjCMethod("init")
    static func initialize(_ object: id?) -> id? { Dates.initialize(object, Date.now) }

    @ObjCMethod("initWithTimeIntervalSinceNow:")
    static func initialize(_ object: id?, sinceNow seconds: Double) -> id? {
        Dates.initialize(object, Date(timeIntervalSinceNow: seconds))
    }

    @ObjCMethod("initWithTimeIntervalSince1970:")
    static func initialize(_ object: id?, since1970 seconds: Double) -> id? {
        Dates.initialize(object, Date(timeIntervalSince1970: seconds))
    }

    @ObjCMethod("initWithTimeIntervalSinceReferenceDate:")
    static func initialize(_ object: id?, sinceReferenceDate seconds: Double) -> id? {
        Dates.initialize(object, Date(timeIntervalSinceReferenceDate: seconds))
    }

    @ObjCMethod("dealloc")
    static func dealloc(_ object: id?) {
        guard let object else { return }
        Storage.set(object, nil)
        ObjC.superDealloc(object, from: Dates.dateClass)
    }

    // MARK: Intervals

    @ObjCMethod("timeIntervalSinceReferenceDate")
    static func sinceReferenceDate(_ object: id?) -> Double { Dates.interval(object) }

    @ObjCMethod("timeIntervalSince1970")
    static func since1970(_ object: id?) -> Double { Dates.date(object).timeIntervalSince1970 }

    @ObjCMethod("timeIntervalSinceNow")
    static func sinceNow(_ object: id?) -> Double { Dates.date(object).timeIntervalSinceNow }

    @ObjCMethod("timeIntervalSinceDate:")
    static func since(_ object: id?, date other: id?) -> Double { Dates.date(object).timeIntervalSince(Dates.date(other)) }

    @ObjCMethod("dateByAddingTimeInterval:")
    static func adding(_ object: id?, _ seconds: Double) -> id? { Dates.autoreleased(Dates.date(object).addingTimeInterval(seconds)) }

    // MARK: Comparing

    @ObjCMethod("compare:")
    static func compare(_ object: id?, _ other: id?) -> Int {
        let a = Dates.date(object), b = Dates.date(other)
        return a < b ? -1 : (a > b ? 1 : 0)
    }

    @ObjCMethod("isEqualToDate:")
    static func isEqual(_ object: id?, toDate other: id?) -> Bool { Dates.date(object) == Dates.date(other) }

    @ObjCMethod("isEqual:")
    static func isEqual(_ object: id?, _ other: id?) -> Bool {
        ObjC.isKind(other, of: Dates.dateClass) && isEqual(object, toDate: other)
    }

    @ObjCMethod("hash")
    static func hash(_ object: id?) -> UInt { UInt(bitPattern: Dates.date(object).hashValue) }

    @ObjCMethod("earlierDate:")
    static func earlier(_ object: id?, _ other: id?) -> id? {
        Dates.interval(other) < Dates.interval(object) ? other : object
    }

    @ObjCMethod("laterDate:")
    static func later(_ object: id?, _ other: id?) -> id? {
        Dates.interval(other) > Dates.interval(object) ? other : object
    }

    @ObjCMethod("description")
    static func description(_ object: id?) -> id? { Strings.autoreleased(Dates.description(Dates.date(object))) }

    @ObjCMethod("copyWithZone:")
    static func copy(_ object: id?, zone: UnsafeMutableRawPointer?) -> id? { ObjC.retain(object) }
}

@c(_CFAbsoluteTimeGetCurrent)
public func CFAbsoluteTimeGetCurrent() -> Double {
    absoluteTimeNow()
}
