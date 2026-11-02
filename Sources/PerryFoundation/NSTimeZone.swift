import CPerryFoundation
import FoundationEssentials
import FoundationInternationalization
import PerryObjCInterop

/// An NSTimeZone's zone: swift-foundation's TimeZone.
final class TimeZoneStorage {
    let zone: TimeZone

    init(_ zone: TimeZone) {
        self.zone = zone
    }
}

enum TimeZones {
    nonisolated(unsafe) static var zoneClass: Class!
    /// +setDefaultTimeZone:'s zone; the system's until set.
    nonisolated(unsafe) static var defaultZone: TimeZone?

    static func zone(_ object: id?) -> TimeZone? {
        Storage.get(object, as: TimeZoneStorage.self)?.zone
    }

    static func autoreleased(_ zone: TimeZone) -> id {
        let object = Storage.allocate(UnsafeMutableRawPointer(zoneClass))!
        Storage.set(object, TimeZoneStorage(zone))
        return ObjC.autorelease(object)!
    }

    /// The zone formatters and calendars use when given none.
    static var current: TimeZone { defaultZone ?? TimeZone.current }

    static func initialize(_ object: id, _ zone: TimeZone?) -> id? {
        guard let zone else {
            ObjC.release(object)
            return nil
        }
        Storage.set(object, TimeZoneStorage(zone))
        return object
    }

    /// The abbreviation as Darwin gives it: the short name in English
    /// ("EST", "EDT"), or the offset from GMT where English has none.
    static func abbreviation(_ zone: TimeZone, _ date: Date) -> String? {
        let style: TimeZone.NameStyle = zone.isDaylightSavingTime(for: date) ? .shortDaylightSaving : .shortStandard
        return zone.localizedName(for: style, locale: Locale(identifier: "en_US")) ?? zone.abbreviation(for: date)
    }

    /// NSTimeZoneNameStyle as TimeZone.NameStyle.
    static func nameStyle(_ style: Int) -> TimeZone.NameStyle {
        switch style {
        case 1: return .shortStandard
        case 2: return .daylightSaving
        case 3: return .shortDaylightSaving
        case 4: return .generic
        case 5: return .shortGeneric
        default: return .standard
        }
    }
}

/// NSTimeZone.
@ObjCClass("NSTimeZone")
public final class NSTimeZone: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        TimeZones.zoneClass = cls.storage
    }

    var zone: TimeZone { TimeZones.zone(objcObject) ?? .gmt }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: TimeZones.zoneClass)
    }

    @ObjCClassMethod("timeZoneWithName:")
    static func zone(_ cls: ObjCClass, name: String) -> UnsafeMutableRawPointer? {
        TimeZone(identifier: name).map(TimeZones.autoreleased)
    }

    @ObjCClassMethod("timeZoneWithName:data:")
    static func zone(_ cls: ObjCClass, name: String, data: ObjCObject?) -> UnsafeMutableRawPointer? {
        TimeZone(identifier: name).map(TimeZones.autoreleased)
    }

    @ObjCClassMethod("timeZoneForSecondsFromGMT:")
    static func zone(_ cls: ObjCClass, secondsFromGMT seconds: Int) -> UnsafeMutableRawPointer? {
        TimeZone(secondsFromGMT: seconds).map(TimeZones.autoreleased)
    }

    @ObjCClassMethod("timeZoneWithAbbreviation:")
    static func zone(_ cls: ObjCClass, abbreviation: String) -> UnsafeMutableRawPointer? {
        TimeZone(abbreviation: abbreviation).map(TimeZones.autoreleased)
    }

    @ObjCMethod("initWithName:")
    func initialize(name: String) -> UnsafeMutableRawPointer? { TimeZones.initialize(objcObject, TimeZone(identifier: name)) }

    @ObjCMethod("initWithName:data:")
    func initialize(name: String, data: ObjCObject?) -> UnsafeMutableRawPointer? {
        TimeZones.initialize(objcObject, TimeZone(identifier: name))
    }

    @ObjCClassMethod("systemTimeZone") static func system() -> UnsafeMutableRawPointer { TimeZones.autoreleased(.current) }
    @ObjCClassMethod("localTimeZone") static func local() -> UnsafeMutableRawPointer { TimeZones.autoreleased(TimeZones.current) }
    @ObjCClassMethod("defaultTimeZone") static func defaultZone() -> UnsafeMutableRawPointer { TimeZones.autoreleased(TimeZones.current) }

    @ObjCClassMethod("setDefaultTimeZone:")
    static func setDefault(_ zone: ObjCObject?) { TimeZones.defaultZone = TimeZones.zone(zone?.id) }

    @ObjCClassMethod("resetSystemTimeZone") static func resetSystem() {}

    @ObjCClassMethod("knownTimeZoneNames")
    static func knownNames() -> ObjCObject {
        ObjCObject(Arrays.autoreleased(TimeZone.knownTimeZoneIdentifiers.map { Strings.autoreleased($0) }))
    }

    @ObjCClassMethod("abbreviationDictionary")
    static func abbreviations() -> ObjCObject {
        ObjCObject(Dictionaries.autoreleased(TimeZone.abbreviationDictionary.sorted { $0.key < $1.key }.map {
            (key: Strings.autoreleased($0.key), value: Strings.autoreleased($0.value))
        }))
    }

    @ObjCClassMethod("timeZoneDataVersion") static func dataVersion() -> String { TimeZone.timeZoneDataVersion }

    @ObjCMethod("name") func name() -> String { zone.identifier }
    @ObjCMethod("abbreviation") func abbreviation() -> String? { TimeZones.abbreviation(zone, Date()) }
    @ObjCMethod("abbreviationForDate:") func abbreviation(for date: NSDate) -> String? { TimeZones.abbreviation(zone, date.date) }
    @ObjCMethod("secondsFromGMT") func secondsFromGMT() -> Int { zone.secondsFromGMT() }
    @ObjCMethod("secondsFromGMTForDate:") func secondsFromGMT(for date: NSDate) -> Int { zone.secondsFromGMT(for: date.date) }
    @ObjCMethod("isDaylightSavingTime") func isDaylightSavingTime() -> Bool { zone.isDaylightSavingTime() }

    @ObjCMethod("isDaylightSavingTimeForDate:")
    func isDaylightSavingTime(for date: NSDate) -> Bool { zone.isDaylightSavingTime(for: date.date) }

    @ObjCMethod("daylightSavingTimeOffset") func daylightSavingTimeOffset() -> Double { zone.daylightSavingTimeOffset() }

    @ObjCMethod("daylightSavingTimeOffsetForDate:")
    func daylightSavingTimeOffset(for date: NSDate) -> Double { zone.daylightSavingTimeOffset(for: date.date) }

    @ObjCMethod("nextDaylightSavingTimeTransition")
    func nextTransition() -> UnsafeMutableRawPointer? { zone.nextDaylightSavingTimeTransition.flatMap { Dates.autoreleased($0) } }

    @ObjCMethod("nextDaylightSavingTimeTransitionAfterDate:")
    func nextTransition(after date: NSDate) -> UnsafeMutableRawPointer? {
        zone.nextDaylightSavingTimeTransition(after: date.date).flatMap { Dates.autoreleased($0) }
    }

    @ObjCMethod("localizedName:locale:")
    func localizedName(_ style: Int, locale: ObjCObject?) -> String? {
        zone.localizedName(for: TimeZones.nameStyle(style), locale: Locales.locale(locale?.id))
    }

    @ObjCMethod("isEqualToTimeZone:")
    func isEqual(toTimeZone other: ObjCObject?) -> Bool { TimeZones.zone(other?.id) == zone }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool { TimeZones.zone(other?.id) == zone }

    @ObjCMethod("hash") func hash() -> UInt { Strings.hash(zone.identifier) }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjC.retain(objcObject)! }

    /// "America/New_York (EST) offset -18000", with " (Daylight)" in summer.
    @ObjCMethod("description")
    func description() -> String {
        let zone = self.zone
        let daylight = zone.isDaylightSavingTime() ? " (Daylight)" : ""
        return "\(zone.identifier) (\(TimeZones.abbreviation(zone, Date()) ?? "")) offset \(zone.secondsFromGMT())\(daylight)"
    }
}
