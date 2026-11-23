import FoundationEssentials
import FoundationInternationalization
import PerryObjCInterop

// NSCalendarDate, Foundation's date of the Mac OS X 10.0 to 10.5 years: an
// NSDate with a time zone and a calendar format, strftime's %-sequences,
// which its description and -descriptionWithCalendarFormat: use and
// -initWithString:calendarFormat: reads. Its fields are the Gregorian
// calendar's in its zone. Programs of those years link the class
// (iWeb's and iWork's archiving maps it to their files' dates).

/// A calendar date's value: its date, zone and format.
final class CalendarDateStorage: DateStorage {
    let zone: TimeZone
    let format: String

    init(_ date: Date, zone: TimeZone, format: String) {
        (self.zone, self.format) = (zone, format)
        super.init(date)
    }
}

enum CalendarDates {
    static let defaultFormat = "%Y-%m-%d %H:%M:%S %z"

    static func storage(_ object: id?) -> CalendarDateStorage? { Storage.get(object, as: CalendarDateStorage.self) }
    static func zone(_ object: id?) -> TimeZone { storage(object)?.zone ?? TimeZones.current }
    static func format(_ object: id?) -> String { storage(object)?.format ?? defaultFormat }

    static func set(_ object: id, _ date: Date, zone: TimeZone?, format: String?) {
        Storage.set(object, CalendarDateStorage(date, zone: zone ?? TimeZones.current, format: format ?? defaultFormat))
    }

    /// A new calendar date, +0.
    static func make(_ date: Date, zone: TimeZone?, format: String?, cls: ObjCClass) -> NSCalendarDate {
        let object = Storage.allocate(cls.pointer)!
        set(object, date, zone: zone, format: format)
        return NSCalendarDate(objCReturnValue: ObjC.autorelease(object))
    }

    static func calendar(_ zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    static func components(_ date: Date, _ zone: TimeZone) -> DateComponents {
        calendar(zone).dateComponents([.era, .year, .month, .day, .hour, .minute, .second, .nanosecond, .weekday], from: date)
    }

    static let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
                             "October", "November", "December"]
    static let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    static func pad(_ value: Int, _ width: Int, _ fill: Character = "0") -> String {
        let text = String(value)
        return text.count >= width ? text : String(repeating: fill, count: width - text.count) + text
    }

    /// The zone's offset at the date as +hhmm.
    static func offset(_ zone: TimeZone, _ date: Date) -> String {
        let seconds = zone.secondsFromGMT(for: date)
        return (seconds < 0 ? "-" : "+") + pad(abs(seconds) / 3600, 2) + pad(abs(seconds) % 3600 / 60, 2)
    }

    /// The date in a calendar format.
    static func describe(_ date: Date, format: String, zone: TimeZone) -> String {
        let parts = components(date, zone)
        let year = parts.year ?? 1, month = parts.month ?? 1, day = parts.day ?? 1
        let hour = parts.hour ?? 0, minute = parts.minute ?? 0, second = parts.second ?? 0
        let weekday = (parts.weekday ?? 1) - 1
        let dayOfYear = calendar(zone).ordinality(of: .day, in: .year, for: date) ?? 1
        var out = ""
        var characters = format.makeIterator()
        while let character = characters.next() {
            guard character == "%", let code = characters.next() else {
                out.append(character)
                continue
            }
            switch code {
            case "%": out += "%"
            case "a": out += String(dayNames[weekday].prefix(3))
            case "A": out += dayNames[weekday]
            case "b": out += String(monthNames[month - 1].prefix(3))
            case "B": out += monthNames[month - 1]
            case "c": out += describe(date, format: "%X %x", zone: zone)
            case "d": out += pad(day, 2)
            case "e": out += pad(day, 2, " ")
            case "F": out += pad((parts.nanosecond ?? 0) / 1_000_000, 3)
            case "H": out += pad(hour, 2)
            case "I": out += pad(hour % 12 == 0 ? 12 : hour % 12, 2)
            case "j": out += pad(dayOfYear, 3)
            case "m": out += pad(month, 2)
            case "M": out += pad(minute, 2)
            case "p": out += hour < 12 ? "AM" : "PM"
            case "S": out += pad(second, 2)
            case "w": out += String(weekday)
            case "x": out += describe(date, format: "%m/%d/%y", zone: zone)
            case "X": out += describe(date, format: "%H:%M:%S", zone: zone)
            case "y": out += pad(year % 100, 2)
            case "Y": out += String(year)
            case "Z": out += TimeZones.abbreviation(zone, date) ?? offset(zone, date)
            case "z": out += offset(zone, date)
            default: out += "%" + String(code)
            }
        }
        return out
    }

    /// A date read from a string in a calendar format, in the zone unless
    /// the string gives one (%z); nil when it doesn't match.
    static func parse(_ text: String, format: String, zone: TimeZone) -> Date? {
        var parts = DateComponents(year: 1, month: 1, day: 1, hour: 0, minute: 0, second: 0)
        var zone = zone
        var pm: Bool?
        let input = Array(text)
        var at = 0
        func skipSpaces() { while at < input.count, input[at] == " " { at += 1 } }
        func number(_ most: Int) -> Int? {
            skipSpaces()
            var sign = 1
            if at < input.count, input[at] == "-" || input[at] == "+" {
                sign = input[at] == "-" ? -1 : 1
                at += 1
            }
            var digits = 0, value = 0
            while at < input.count, digits < most, let digit = input[at].wholeNumberValue {
                value = value * 10 + digit
                at += 1
                digits += 1
            }
            return digits > 0 ? sign * value : nil
        }
        func name(_ names: [String]) -> Int? {
            skipSpaces()
            let rest = String(input[at...]).lowercased()
            for (index, full) in names.enumerated() {
                for candidate in [full, String(full.prefix(3))] where rest.hasPrefix(candidate.lowercased()) {
                    at += candidate.count
                    return index
                }
            }
            return nil
        }
        var characters = format.makeIterator()
        while let character = characters.next() {
            if character != "%" {
                if character == " " { skipSpaces(); continue }
                guard at < input.count, input[at] == character else { return nil }
                at += 1
                continue
            }
            guard let code = characters.next() else { break }
            switch code {
            case "Y": guard let value = number(4) else { return nil }; parts.year = value
            case "y": guard let value = number(2) else { return nil }; parts.year = value < 70 ? 2000 + value : 1900 + value
            case "m": guard let value = number(2) else { return nil }; parts.month = value
            case "d", "e": guard let value = number(2) else { return nil }; parts.day = value
            case "j": guard let value = number(3) else { return nil }; parts.month = 1; parts.day = value
            case "H": guard let value = number(2) else { return nil }; parts.hour = value
            case "I": guard let value = number(2) else { return nil }; parts.hour = value % 12
            case "M": guard let value = number(2) else { return nil }; parts.minute = value
            case "S": guard let value = number(2) else { return nil }; parts.second = value
            case "F": guard let value = number(3) else { return nil }; parts.nanosecond = value * 1_000_000
            case "b", "B": guard let index = name(monthNames) else { return nil }; parts.month = index + 1
            case "a", "A": guard name(dayNames) != nil else { return nil }
            case "p":
                skipSpaces()
                let rest = String(input[at...]).uppercased()
                guard rest.hasPrefix("AM") || rest.hasPrefix("PM") else { return nil }
                pm = rest.hasPrefix("PM")
                at += 2
            case "z":
                guard let value = number(4) else { return nil }
                let seconds = (abs(value) / 100 * 3600 + abs(value) % 100 * 60) * (value < 0 ? -1 : 1)
                zone = TimeZone(secondsFromGMT: seconds) ?? zone
            case "Z":
                skipSpaces()
                var abbreviation = ""
                while at < input.count, input[at].isLetter { abbreviation.append(input[at]); at += 1 }
                if let named = TimeZone(abbreviation: abbreviation) { zone = named }
            case "%":
                guard at < input.count, input[at] == "%" else { return nil }
                at += 1
            default: return nil
            }
        }
        if let pm, let hour = parts.hour { parts.hour = hour % 12 + (pm ? 12 : 0) }
        return calendar(zone).date(from: parts)
    }
}

/// NSCalendarDate.
@ObjCClass("NSCalendarDate")
public final class NSCalendarDate: NSDate {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
    }

    var zone: TimeZone { CalendarDates.zone(objcObject) }
    var format: String { CalendarDates.format(objcObject) }
    var parts: DateComponents { CalendarDates.components(date, zone) }

    // MARK: Creating

    @ObjCClassMethod("calendarDate")
    static func calendarDate(_ cls: ObjCClass) -> NSCalendarDate { CalendarDates.make(.now, zone: nil, format: nil, cls: cls) }

    @ObjCClassMethod("dateWithYear:month:day:hour:minute:second:timeZone:")
    static func date(_ cls: ObjCClass, year: Int, month: UInt, day: UInt, hour: UInt, minute: UInt, second: UInt,
                     timeZone: ObjCObject?) -> NSCalendarDate {
        let zone = TimeZones.zone(timeZone?.id) ?? TimeZones.current
        let parts = DateComponents(year: year, month: Int(month), day: Int(day), hour: Int(hour), minute: Int(minute), second: Int(second))
        return CalendarDates.make(CalendarDates.calendar(zone).date(from: parts) ?? .now, zone: zone, format: nil, cls: cls)
    }

    @ObjCClassMethod("dateWithString:calendarFormat:")
    static func date(_ cls: ObjCClass, string: String?, calendarFormat: String?) -> NSCalendarDate? {
        let format = calendarFormat ?? CalendarDates.defaultFormat
        guard let string, let date = CalendarDates.parse(string, format: format, zone: TimeZones.current) else { return nil }
        return CalendarDates.make(date, zone: nil, format: format, cls: cls)
    }

    @ObjCClassMethod("dateWithString:calendarFormat:locale:")
    static func date(_ cls: ObjCClass, string: String?, calendarFormat: String?, locale: ObjCObject?) -> NSCalendarDate? {
        date(cls, string: string, calendarFormat: calendarFormat)
    }

    @ObjCMethod("initWithYear:month:day:hour:minute:second:timeZone:")
    func initialize(year: Int, month: UInt, day: UInt, hour: UInt, minute: UInt, second: UInt, timeZone: ObjCObject?) -> Self {
        let zone = TimeZones.zone(timeZone?.id) ?? TimeZones.current
        let parts = DateComponents(year: year, month: Int(month), day: Int(day), hour: Int(hour), minute: Int(minute), second: Int(second))
        CalendarDates.set(objcObject, CalendarDates.calendar(zone).date(from: parts) ?? .now, zone: zone, format: nil)
        return self
    }

    /// Nil, as Foundation's, for a string the format doesn't read.
    @ObjCMethod("initWithString:calendarFormat:")
    func initialize(string: String?, calendarFormat: String?) -> UnsafeMutableRawPointer? {
        let format = calendarFormat ?? CalendarDates.defaultFormat
        guard let string, let date = CalendarDates.parse(string, format: format, zone: TimeZones.current) else { return nil }
        CalendarDates.set(objcObject, date, zone: nil, format: format)
        return ObjC.retain(objcObject)
    }

    @ObjCMethod("initWithString:calendarFormat:locale:")
    func initialize(string: String?, calendarFormat: String?, locale: ObjCObject?) -> UnsafeMutableRawPointer? {
        initialize(string: string, calendarFormat: calendarFormat)
    }

    @ObjCMethod("initWithString:")
    func initialize(string: String?) -> UnsafeMutableRawPointer? { initialize(string: string, calendarFormat: nil) }

    // MARK: Zone and format

    @ObjCMethod("timeZone") func timeZoneObject() -> UnsafeMutableRawPointer { TimeZones.autoreleased(zone) }
    @ObjCMethod("setTimeZone:")
    func setTimeZone(_ value: ObjCObject?) { CalendarDates.set(objcObject, date, zone: TimeZones.zone(value?.id), format: format) }
    @ObjCMethod("calendarFormat") func calendarFormat() -> String { format }
    @ObjCMethod("setCalendarFormat:")
    func setCalendarFormat(_ value: String?) { CalendarDates.set(objcObject, date, zone: zone, format: value) }

    // MARK: Fields

    @ObjCMethod("yearOfCommonEra") func yearOfCommonEra() -> Int { parts.year ?? 1 }
    @ObjCMethod("monthOfYear") func monthOfYear() -> Int { parts.month ?? 1 }
    @ObjCMethod("dayOfMonth") func dayOfMonth() -> Int { parts.day ?? 1 }
    @ObjCMethod("dayOfWeek") func dayOfWeek() -> Int { (parts.weekday ?? 1) - 1 }
    @ObjCMethod("dayOfYear") func dayOfYear() -> Int { CalendarDates.calendar(zone).ordinality(of: .day, in: .year, for: date) ?? 1 }
    @ObjCMethod("dayOfCommonEra") func dayOfCommonEra() -> Int { CalendarDates.calendar(zone).ordinality(of: .day, in: .era, for: date) ?? 1 }
    @ObjCMethod("hourOfDay") func hourOfDay() -> Int { parts.hour ?? 0 }
    @ObjCMethod("minuteOfHour") func minuteOfHour() -> Int { parts.minute ?? 0 }
    @ObjCMethod("secondOfMinute") func secondOfMinute() -> Int { parts.second ?? 0 }

    // MARK: Text

    @ObjCMethod("description") func calendarDescription() -> String { CalendarDates.describe(date, format: format, zone: zone) }
    @ObjCMethod("descriptionWithLocale:") func description(locale: ObjCObject?) -> String { calendarDescription() }
    @ObjCMethod("descriptionWithCalendarFormat:")
    func description(calendarFormat: String?) -> String {
        CalendarDates.describe(date, format: calendarFormat ?? format, zone: zone)
    }
    @ObjCMethod("descriptionWithCalendarFormat:locale:")
    func description(calendarFormat: String?, locale: ObjCObject?) -> String { description(calendarFormat: calendarFormat) }

    // MARK: Arithmetic

    /// The date with the calendar amounts added, in its zone, keeping its
    /// zone and format.
    @ObjCMethod("dateByAddingYears:months:days:hours:minutes:seconds:")
    func adding(years: Int, months: Int, days: Int, hours: Int, minutes: Int, seconds: Int) -> NSCalendarDate {
        let amounts = DateComponents(year: years, month: months, day: days, hour: hours, minute: minutes, second: seconds)
        let moved = CalendarDates.calendar(zone).date(byAdding: amounts, to: date) ?? date
        return CalendarDates.make(moved, zone: zone, format: format, cls: NSCalendarDate.objCClass)
    }

    /// The differences from another date, in calendar units, each pointer
    /// given taking the largest unit not taken by one before it.
    @ObjCMethod("years:months:days:hours:minutes:seconds:sinceDate:")
    func since(years: UnsafeMutablePointer<Int>?, months: UnsafeMutablePointer<Int>?, days: UnsafeMutablePointer<Int>?,
               hours: UnsafeMutablePointer<Int>?, minutes: UnsafeMutablePointer<Int>?, seconds: UnsafeMutablePointer<Int>?,
               sinceDate other: ObjCObject?) {
        var units: Set<Calendar.Component> = []
        if years != nil { units.insert(.year) }
        if months != nil { units.insert(.month) }
        if days != nil { units.insert(.day) }
        if hours != nil { units.insert(.hour) }
        if minutes != nil { units.insert(.minute) }
        if seconds != nil { units.insert(.second) }
        let difference = CalendarDates.calendar(zone).dateComponents(units, from: Dates.date(other?.id), to: date)
        years?.pointee = difference.year ?? 0
        months?.pointee = difference.month ?? 0
        days?.pointee = difference.day ?? 0
        hours?.pointee = difference.hour ?? 0
        minutes?.pointee = difference.minute ?? 0
        seconds?.pointee = difference.second ?? 0
    }
}

/// NSDate's methods that make and describe calendar dates.
@ObjCCategory("NSCalendarDateExtras")
extension NSDate {
    @ObjCMethod("dateWithCalendarFormat:timeZone:")
    func calendarDate(format: String?, timeZone: ObjCObject?) -> NSCalendarDate {
        CalendarDates.make(date, zone: TimeZones.zone(timeZone?.id), format: format, cls: NSCalendarDate.objCClass)
    }

    @ObjCMethod("descriptionWithCalendarFormat:timeZone:locale:")
    func description(calendarFormat: String?, timeZone: ObjCObject?, locale: ObjCObject?) -> String {
        CalendarDates.describe(date, format: calendarFormat ?? CalendarDates.defaultFormat,
                               zone: TimeZones.zone(timeZone?.id) ?? TimeZones.current)
    }
}
