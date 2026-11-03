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

    /// A new NSDate wrapped for returning, +0.
    static func wrapped(_ date: Date, cls: ObjCClass? = nil) -> NSDate {
        NSDate(objCReturnValue: autoreleased(date, cls: cls?.pointer))
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

}

/// NSDate.
@ObjCClass("NSDate")
public final class NSDate: NSObject {
    /// Set-up after the class is defined.
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Dates.dateClass = cls.storage
    }

    var date: Date { Dates.date(objcObject) }

    private func setDate(_ date: Date) -> Self {
        Storage.set(objcObject, DateStorage(date))
        return self
    }

    // MARK: Creating

    @ObjCClassMethod("date")
    static func now(_ cls: ObjCClass) -> NSDate { Dates.wrapped(.now, cls: cls) }

    @ObjCClassMethod("dateWithTimeIntervalSinceNow:")
    static func date(_ cls: ObjCClass, sinceNow seconds: Double) -> NSDate {
        Dates.wrapped(Date(timeIntervalSinceNow: seconds), cls: cls)
    }

    @ObjCClassMethod("dateWithTimeIntervalSince1970:")
    static func date(_ cls: ObjCClass, since1970 seconds: Double) -> NSDate {
        Dates.wrapped(Date(timeIntervalSince1970: seconds), cls: cls)
    }

    @ObjCClassMethod("dateWithTimeIntervalSinceReferenceDate:")
    static func date(_ cls: ObjCClass, sinceReferenceDate seconds: Double) -> NSDate {
        Dates.wrapped(Date(timeIntervalSinceReferenceDate: seconds), cls: cls)
    }

    @ObjCClassMethod("distantFuture")
    static func distantFuture(_ cls: ObjCClass) -> NSDate { Dates.wrapped(.distantFuture, cls: cls) }

    @ObjCClassMethod("distantPast")
    static func distantPast(_ cls: ObjCClass) -> NSDate { Dates.wrapped(.distantPast, cls: cls) }

    @ObjCClassMethod("timeIntervalSinceReferenceDate")
    static func timeIntervalSinceReferenceDate() -> Double { Date.now.timeIntervalSinceReferenceDate }

    @ObjCMethod("init") func initialize() -> Self { setDate(.now) }

    @ObjCMethod("initWithTimeIntervalSinceNow:")
    func initialize(sinceNow seconds: Double) -> Self { setDate(Date(timeIntervalSinceNow: seconds)) }

    @ObjCMethod("initWithTimeIntervalSince1970:")
    func initialize(since1970 seconds: Double) -> Self { setDate(Date(timeIntervalSince1970: seconds)) }

    @ObjCMethod("initWithTimeIntervalSinceReferenceDate:")
    func initialize(sinceReferenceDate seconds: Double) -> Self { setDate(Date(timeIntervalSinceReferenceDate: seconds)) }

    @ObjCMethod("initWithTimeInterval:sinceDate:")
    func initialize(timeInterval seconds: Double, since date: ObjCObject?) -> Self {
        setDate(Dates.date(date?.id).addingTimeInterval(seconds))
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Dates.dateClass)
    }

    // MARK: Intervals

    @ObjCMethod("timeIntervalSinceReferenceDate")
    func sinceReferenceDate() -> Double { date.timeIntervalSinceReferenceDate }

    @ObjCMethod("timeIntervalSince1970")
    func since1970() -> Double { date.timeIntervalSince1970 }

    @ObjCMethod("timeIntervalSinceNow")
    func sinceNow() -> Double { date.timeIntervalSinceNow }

    @ObjCMethod("timeIntervalSinceDate:")
    func since(_ other: NSDate) -> Double { date.timeIntervalSince(other.date) }

    @ObjCMethod("dateByAddingTimeInterval:")
    func adding(_ seconds: Double) -> NSDate { Dates.wrapped(date.addingTimeInterval(seconds)) }

    // MARK: Comparing

    @ObjCMethod("compare:")
    func compare(_ other: NSDate) -> Int { date < other.date ? -1 : (date > other.date ? 1 : 0) }

    @ObjCMethod("isEqualToDate:")
    func isEqual(toDate other: NSDate?) -> Bool { other?.date == date }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool {
        guard let other, other.is(NSDate.self) else { return false }
        return isEqual(toDate: other.unsafeCast(to: NSDate.self))
    }

    @ObjCMethod("hash")
    func hash() -> UInt { UInt(bitPattern: date.hashValue) }

    @ObjCMethod("earlierDate:")
    func earlier(_ other: NSDate) -> NSDate { other.date < date ? other : self }

    @ObjCMethod("laterDate:")
    func later(_ other: NSDate) -> NSDate { other.date > date ? other : self }

    @ObjCMethod("description")
    func description() -> String { Dates.description(date) }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> NSDate { self }
}

@c(_CFAbsoluteTimeGetCurrent)
public func CFAbsoluteTimeGetCurrent() -> Double {
    absoluteTimeNow()
}
