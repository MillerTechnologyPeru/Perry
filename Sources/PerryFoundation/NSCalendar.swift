import CPerryFoundation
import FoundationEssentials
import FoundationInternationalization
import PerryObjCInterop

// NSCalendar and NSDateComponents over swift-foundation's Calendar and
// DateComponents, the implementation Darwin's Foundation uses.

/// Calendar identifiers, CoreFoundation's strings.
enum CalendarIdentifiers {
    static let table: [(String, Calendar.Identifier)] = [
        ("gregorian", .gregorian), ("buddhist", .buddhist), ("chinese", .chinese), ("coptic", .coptic),
        ("ethiopic", .ethiopicAmeteMihret), ("ethiopic-amete-alem", .ethiopicAmeteAlem), ("hebrew", .hebrew),
        ("iso8601", .iso8601), ("indian", .indian), ("islamic", .islamic), ("islamic-civil", .islamicCivil),
        ("japanese", .japanese), ("persian", .persian), ("roc", .republicOfChina), ("islamic-tbla", .islamicTabular),
        ("islamic-umalqura", .islamicUmmAlQura),
    ]

    /// Calendars Darwin added later (iOS 26's Indian regional calendars,
    /// Dangi, Vietnamese), named by value: another file exports their
    /// NSCalendarIdentifier constants.
    static let newer: Set<String> = [
        "bangla", "dangi", "gujarati", "kannada", "malayalam", "marathi", "odia", "tamil", "telugu", "vietnamese", "vikram",
    ]

    static func identifier(_ name: String) -> Calendar.Identifier? {
        if let known = table.first(where: { $0.0 == name })?.1 { return known }
        // One of the newer calendars, when this system's Foundation and ICU
        // know it: a locale asking for it then has it; nil otherwise.
        guard newer.contains(name) else { return nil }
        let found = Locale(identifier: "en_US@calendar=" + name).calendar.identifier
        return found == .gregorian ? nil : found
    }

    static func name(_ identifier: Calendar.Identifier) -> String {
        table.first { $0.1 == identifier }?.0 ?? identifier.debugDescription
    }
}

@ObjCConstants
enum CalendarIdentifierNames {
    static let NSCalendarIdentifierGregorian = "gregorian"
    static let NSCalendarIdentifierBuddhist = "buddhist"
    static let NSCalendarIdentifierChinese = "chinese"
    static let NSCalendarIdentifierCoptic = "coptic"
    static let NSCalendarIdentifierEthiopicAmeteMihret = "ethiopic"
    static let NSCalendarIdentifierEthiopicAmeteAlem = "ethiopic-amete-alem"
    static let NSCalendarIdentifierHebrew = "hebrew"
    static let NSCalendarIdentifierISO8601 = "iso8601"
    static let NSCalendarIdentifierIndian = "indian"
    static let NSCalendarIdentifierIslamic = "islamic"
    static let NSCalendarIdentifierIslamicCivil = "islamic-civil"
    static let NSCalendarIdentifierJapanese = "japanese"
    static let NSCalendarIdentifierPersian = "persian"
    static let NSCalendarIdentifierRepublicOfChina = "roc"
    static let NSCalendarIdentifierIslamicTabular = "islamic-tbla"
    static let NSCalendarIdentifierIslamicUmmAlQura = "islamic-umalqura"
    static let NSGregorianCalendar = "gregorian"
    static let NSBuddhistCalendar = "buddhist"
    static let NSChineseCalendar = "chinese"
    static let NSHebrewCalendar = "hebrew"
    static let NSIslamicCalendar = "islamic"
    static let NSIslamicCivilCalendar = "islamic-civil"
    static let NSJapaneseCalendar = "japanese"
    static let NSRepublicOfChinaCalendar = "roc"
    static let NSPersianCalendar = "persian"
    static let NSIndianCalendar = "indian"
    static let NSISO8601Calendar = "iso8601"
    static let NSCalendarDayChangedNotification = "NSCalendarDayChangedNotification"
    // CoreFoundation's names for the same calendars.
    static let kCFGregorianCalendar = NSCalendarIdentifierGregorian
    static let kCFBuddhistCalendar = NSCalendarIdentifierBuddhist
    static let kCFChineseCalendar = NSCalendarIdentifierChinese
    static let kCFHebrewCalendar = NSCalendarIdentifierHebrew
    static let kCFIslamicCalendar = NSCalendarIdentifierIslamic
    static let kCFIslamicCivilCalendar = NSCalendarIdentifierIslamicCivil
    static let kCFJapaneseCalendar = NSCalendarIdentifierJapanese
    static let kCFRepublicOfChinaCalendar = NSCalendarIdentifierRepublicOfChina
    static let kCFPersianCalendar = NSCalendarIdentifierPersian
    static let kCFIndianCalendar = NSCalendarIdentifierIndian
    static let kCFISO8601Calendar = NSCalendarIdentifierISO8601
}

/// NSCalendarUnit bits.
enum CalendarUnits {
    static let table: [(UInt, Calendar.Component)] = [
        (1 << 1, .era), (1 << 2, .year), (1 << 3, .month), (1 << 4, .day), (1 << 5, .hour), (1 << 6, .minute),
        (1 << 7, .second), (1 << 9, .weekday), (1 << 10, .weekdayOrdinal), (1 << 11, .quarter),
        (1 << 12, .weekOfMonth), (1 << 13, .weekOfYear), (1 << 14, .yearForWeekOfYear), (1 << 15, .nanosecond),
        (1 << 16, .dayOfYear), (1 << 20, .calendar), (1 << 21, .timeZone),
    ]

    static func components(_ units: UInt) -> Set<Calendar.Component> {
        Set(table.filter { units & $0.0 != 0 }.map(\.1))
    }

    static func component(_ unit: UInt) -> Calendar.Component? {
        table.first { $0.0 == unit }?.1
    }

    /// NSWeekCalendarUnit, the deprecated week: the week of the year, kept
    /// apart in date components as Darwin keeps it.
    static let week: UInt = 1 << 8
}

/// A calendar, which NSCalendar's setters change in place.
final class CalendarStorage {
    var calendar: Calendar

    init(_ calendar: Calendar) {
        self.calendar = calendar
    }
}

enum Calendars {
    nonisolated(unsafe) static var calendarClass: Class!

    static func calendar(_ object: id?) -> Calendar? {
        Storage.get(object, as: CalendarStorage.self)?.calendar
    }

    /// A calendar made the way +calendarWithIdentifier: makes one: in the
    /// default time zone and the current locale.
    static func make(_ identifier: Calendar.Identifier) -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = TimeZones.current
        calendar.locale = Locales.current
        return calendar
    }

    static func autoreleased(_ calendar: Calendar) -> id {
        let object = Storage.allocate(UnsafeMutableRawPointer(calendarClass))!
        Storage.set(object, CalendarStorage(calendar))
        return ObjC.autorelease(object)!
    }

    /// NSCalendarOptions' matching and wrapping bits.
    static func wraps(_ options: UInt) -> Bool { options & (1 << 0) != 0 }

    /// NSCalendarOptions for searches: NSCalendarMatchStrictly (1 << 1),
    /// NSCalendarSearchBackwards (1 << 2), the previous or next time
    /// preserving smaller units (1 << 8, 1 << 9), the next time (1 << 10,
    /// the default here where Darwin requires one) and the first or last
    /// of repeated times (1 << 12, 1 << 13).
    static func search(_ options: UInt) -> (policy: Calendar.MatchingPolicy, repeated: Calendar.RepeatedTimePolicy,
                                           direction: Calendar.SearchDirection) {
        let policy: Calendar.MatchingPolicy = options & (1 << 1) != 0 ? .strict
            : options & (1 << 8) != 0 ? .previousTimePreservingSmallerComponents
            : options & (1 << 9) != 0 ? .nextTimePreservingSmallerComponents : .nextTime
        return (policy, options & (1 << 13) != 0 ? .last : .first, options & (1 << 2) != 0 ? .backward : .forward)
    }
}

/// NSCalendar.
@ObjCClass("NSCalendar")
public final class NSCalendar: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Calendars.calendarClass = cls.storage
    }

    private var storage: CalendarStorage {
        if let storage = Storage.get(objcObject, as: CalendarStorage.self) { return storage }
        let storage = CalendarStorage(Calendars.make(.gregorian))
        Storage.set(objcObject, storage)
        return storage
    }

    var calendar: Calendar { storage.calendar }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Calendars.calendarClass)
    }

    @ObjCClassMethod("calendarWithIdentifier:")
    static func calendar(_ cls: ObjCClass, identifier: String) -> UnsafeMutableRawPointer? {
        CalendarIdentifiers.identifier(identifier).map { Calendars.autoreleased(Calendars.make($0)) }
    }

    @ObjCMethod("initWithCalendarIdentifier:")
    func initialize(identifier: String) -> UnsafeMutableRawPointer? {
        guard let identifier = CalendarIdentifiers.identifier(identifier) else { return nil }
        Storage.set(objcObject, CalendarStorage(Calendars.make(identifier)))
        // The receiver's wrapper adopted its reference; the result is +1.
        return ObjC.retain(objcObject)
    }

    @ObjCClassMethod("currentCalendar")
    static func current() -> UnsafeMutableRawPointer { Calendars.autoreleased(Calendars.make(Locales.current.calendar.identifier)) }

    @ObjCClassMethod("autoupdatingCurrentCalendar")
    static func autoupdating() -> UnsafeMutableRawPointer { current() }

    @ObjCMethod("calendarIdentifier") func calendarIdentifier() -> String { CalendarIdentifiers.name(calendar.identifier) }

    @ObjCMethod("timeZone") func timeZone() -> UnsafeMutableRawPointer { TimeZones.autoreleased(calendar.timeZone) }
    @ObjCMethod("setTimeZone:")
    func setTimeZone(_ zone: ObjCObject?) { storage.calendar.timeZone = TimeZones.zone(zone?.id) ?? TimeZones.current }

    @ObjCMethod("locale") func locale() -> UnsafeMutableRawPointer? { calendar.locale.map(Locales.autoreleased) }
    @ObjCMethod("setLocale:") func setLocale(_ locale: ObjCObject?) { storage.calendar.locale = Locales.locale(locale?.id) }

    @ObjCMethod("firstWeekday") func firstWeekday() -> UInt { UInt(calendar.firstWeekday) }
    @ObjCMethod("setFirstWeekday:") func setFirstWeekday(_ value: UInt) { storage.calendar.firstWeekday = Int(value) }
    @ObjCMethod("minimumDaysInFirstWeek") func minimumDaysInFirstWeek() -> UInt { UInt(calendar.minimumDaysInFirstWeek) }
    @ObjCMethod("setMinimumDaysInFirstWeek:")
    func setMinimumDaysInFirstWeek(_ value: UInt) { storage.calendar.minimumDaysInFirstWeek = Int(value) }

    // MARK: Symbols

    @ObjCMethod("eraSymbols") func eraSymbols() -> ObjCObject { Locales.strings(calendar.eraSymbols) }
    @ObjCMethod("longEraSymbols") func longEraSymbols() -> ObjCObject { Locales.strings(calendar.longEraSymbols) }
    @ObjCMethod("monthSymbols") func monthSymbols() -> ObjCObject { Locales.strings(calendar.monthSymbols) }
    @ObjCMethod("shortMonthSymbols") func shortMonthSymbols() -> ObjCObject { Locales.strings(calendar.shortMonthSymbols) }
    @ObjCMethod("veryShortMonthSymbols") func veryShortMonthSymbols() -> ObjCObject { Locales.strings(calendar.veryShortMonthSymbols) }
    @ObjCMethod("standaloneMonthSymbols") func standaloneMonthSymbols() -> ObjCObject { Locales.strings(calendar.standaloneMonthSymbols) }
    @ObjCMethod("shortStandaloneMonthSymbols")
    func shortStandaloneMonthSymbols() -> ObjCObject { Locales.strings(calendar.shortStandaloneMonthSymbols) }
    @ObjCMethod("weekdaySymbols") func weekdaySymbols() -> ObjCObject { Locales.strings(calendar.weekdaySymbols) }
    @ObjCMethod("shortWeekdaySymbols") func shortWeekdaySymbols() -> ObjCObject { Locales.strings(calendar.shortWeekdaySymbols) }
    @ObjCMethod("veryShortWeekdaySymbols")
    func veryShortWeekdaySymbols() -> ObjCObject { Locales.strings(calendar.veryShortWeekdaySymbols) }
    @ObjCMethod("standaloneWeekdaySymbols")
    func standaloneWeekdaySymbols() -> ObjCObject { Locales.strings(calendar.standaloneWeekdaySymbols) }
    @ObjCMethod("quarterSymbols") func quarterSymbols() -> ObjCObject { Locales.strings(calendar.quarterSymbols) }
    @ObjCMethod("shortQuarterSymbols") func shortQuarterSymbols() -> ObjCObject { Locales.strings(calendar.shortQuarterSymbols) }
    @ObjCMethod("standaloneQuarterSymbols")
    func standaloneQuarterSymbols() -> ObjCObject { Locales.strings(calendar.standaloneQuarterSymbols) }
    @ObjCMethod("shortStandaloneQuarterSymbols")
    func shortStandaloneQuarterSymbols() -> ObjCObject { Locales.strings(calendar.shortStandaloneQuarterSymbols) }
    @ObjCMethod("shortStandaloneWeekdaySymbols")
    func shortStandaloneWeekdaySymbols() -> ObjCObject { Locales.strings(calendar.shortStandaloneWeekdaySymbols) }
    @ObjCMethod("veryShortStandaloneWeekdaySymbols")
    func veryShortStandaloneWeekdaySymbols() -> ObjCObject { Locales.strings(calendar.veryShortStandaloneWeekdaySymbols) }
    @ObjCMethod("veryShortStandaloneMonthSymbols")
    func veryShortStandaloneMonthSymbols() -> ObjCObject { Locales.strings(calendar.veryShortStandaloneMonthSymbols) }
    @ObjCMethod("AMSymbol") func amSymbol() -> String { calendar.amSymbol }
    @ObjCMethod("PMSymbol") func pmSymbol() -> String { calendar.pmSymbol }

    // MARK: Components

    /// NSWeekCalendarUnit gives the week of the year as the deprecated week.
    @ObjCMethod("components:fromDate:")
    func components(_ units: UInt, from date: NSDate) -> UnsafeMutableRawPointer {
        let object = DateComponentsBox.autoreleased(calendar.dateComponents(CalendarUnits.components(units), from: date.date))
        if units & CalendarUnits.week != 0 {
            DateComponentsBox.box(object).week = calendar.component(.weekOfYear, from: date.date)
        }
        return object
    }

    @ObjCMethod("componentsInTimeZone:fromDate:")
    func components(in zone: NSTimeZone, from date: NSDate) -> UnsafeMutableRawPointer {
        DateComponentsBox.autoreleased(calendar.dateComponents(in: zone.zone, from: date.date))
    }

    @ObjCMethod("components:fromDate:toDate:options:")
    func components(_ units: UInt, from start: NSDate, to end: NSDate, options: UInt) -> UnsafeMutableRawPointer {
        DateComponentsBox.autoreleased(calendar.dateComponents(CalendarUnits.components(units), from: start.date, to: end.date))
    }

    @ObjCMethod("components:fromDateComponents:toDateComponents:options:")
    func components(_ units: UInt, fromComponents start: ObjCObject, to end: ObjCObject, options: UInt) -> UnsafeMutableRawPointer {
        DateComponentsBox.autoreleased(calendar.dateComponents(CalendarUnits.components(units),
                                                               from: DateComponentsBox.value(start.id),
                                                               to: DateComponentsBox.value(end.id)))
    }

    @ObjCMethod("component:fromDate:")
    func component(_ unit: UInt, from date: NSDate) -> Int {
        if unit == CalendarUnits.week { return calendar.component(.weekOfYear, from: date.date) }
        return CalendarUnits.component(unit).map { calendar.component($0, from: date.date) } ?? Int.max
    }

    /// Each pointer given gets its component; one Foundation can't compute
    /// is left as it is.
    @ObjCMethod("getEra:year:month:day:fromDate:")
    func get(era: UnsafeMutablePointer<Int>?, year: UnsafeMutablePointer<Int>?, month: UnsafeMutablePointer<Int>?,
             day: UnsafeMutablePointer<Int>?, from date: NSDate) {
        let parts = calendar.dateComponents([.era, .year, .month, .day], from: date.date)
        if let value = parts.era { era?.pointee = value }
        if let value = parts.year { year?.pointee = value }
        if let value = parts.month { month?.pointee = value }
        if let value = parts.day { day?.pointee = value }
    }

    @ObjCMethod("getEra:yearForWeekOfYear:weekOfYear:weekday:fromDate:")
    func get(era: UnsafeMutablePointer<Int>?, yearForWeekOfYear: UnsafeMutablePointer<Int>?, weekOfYear: UnsafeMutablePointer<Int>?,
             weekday: UnsafeMutablePointer<Int>?, from date: NSDate) {
        let parts = calendar.dateComponents([.era, .yearForWeekOfYear, .weekOfYear, .weekday], from: date.date)
        if let value = parts.era { era?.pointee = value }
        if let value = parts.yearForWeekOfYear { yearForWeekOfYear?.pointee = value }
        if let value = parts.weekOfYear { weekOfYear?.pointee = value }
        if let value = parts.weekday { weekday?.pointee = value }
    }

    @ObjCMethod("getHour:minute:second:nanosecond:fromDate:")
    func get(hour: UnsafeMutablePointer<Int>?, minute: UnsafeMutablePointer<Int>?, second: UnsafeMutablePointer<Int>?,
             nanosecond: UnsafeMutablePointer<Int>?, from date: NSDate) {
        let parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date.date)
        if let value = parts.hour { hour?.pointee = value }
        if let value = parts.minute { minute?.pointee = value }
        if let value = parts.second { second?.pointee = value }
        if let value = parts.nanosecond { nanosecond?.pointee = value }
    }

    @ObjCMethod("dateFromComponents:")
    func date(from components: ObjCObject) -> UnsafeMutableRawPointer? {
        calendar.date(from: DateComponentsBox.value(components.id)).flatMap { Dates.autoreleased($0) }
    }

    @ObjCMethod("dateByAddingComponents:toDate:options:")
    func date(byAdding components: ObjCObject, to date: NSDate, options: UInt) -> UnsafeMutableRawPointer? {
        calendar.date(byAdding: DateComponentsBox.value(components.id), to: date.date, wrappingComponents: Calendars.wraps(options))
            .flatMap { Dates.autoreleased($0) }
    }

    @ObjCMethod("dateByAddingUnit:value:toDate:options:")
    func date(byAdding unit: UInt, value: Int, to date: NSDate, options: UInt) -> UnsafeMutableRawPointer? {
        guard let component = CalendarUnits.component(unit) else { return nil }
        return calendar.date(byAdding: component, value: value, to: date.date, wrappingComponents: Calendars.wraps(options))
            .flatMap { Dates.autoreleased($0) }
    }

    @ObjCMethod("dateBySettingHour:minute:second:ofDate:options:")
    func date(settingHour hour: Int, minute: Int, second: Int, of date: NSDate, options: UInt) -> UnsafeMutableRawPointer? {
        calendar.date(bySettingHour: hour, minute: minute, second: second, of: date.date).flatMap { Dates.autoreleased($0) }
    }

    @ObjCMethod("dateBySettingUnit:value:ofDate:options:")
    func date(setting unit: UInt, value: Int, of date: NSDate, options: UInt) -> UnsafeMutableRawPointer? {
        guard let component = CalendarUnits.component(unit) else { return nil }
        return calendar.date(bySetting: component, value: value, of: date.date).flatMap { Dates.autoreleased($0) }
    }

    @ObjCMethod("dateWithEra:year:month:day:hour:minute:second:nanosecond:")
    func date(era: Int, year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int,
              nanosecond: Int) -> UnsafeMutableRawPointer? {
        let components = DateComponents(era: era, year: year, month: month, day: day, hour: hour, minute: minute,
                                        second: second, nanosecond: nanosecond)
        return calendar.date(from: components).flatMap { Dates.autoreleased($0) }
    }

    @ObjCMethod("dateWithEra:yearForWeekOfYear:weekOfYear:weekday:hour:minute:second:nanosecond:")
    func date(era: Int, yearForWeekOfYear: Int, weekOfYear: Int, weekday: Int, hour: Int, minute: Int, second: Int,
              nanosecond: Int) -> UnsafeMutableRawPointer? {
        var components = DateComponents(era: era, hour: hour, minute: minute, second: second, nanosecond: nanosecond,
                                        weekday: weekday, weekOfYear: weekOfYear)
        components.yearForWeekOfYear = yearForWeekOfYear
        return calendar.date(from: components).flatMap { Dates.autoreleased($0) }
    }

    @ObjCMethod("startOfDayForDate:")
    func startOfDay(for date: NSDate) -> UnsafeMutableRawPointer? { Dates.autoreleased(calendar.startOfDay(for: date.date)) }

    @ObjCMethod("rangeOfUnit:inUnit:forDate:")
    func range(of smaller: UInt, in larger: UInt, for date: NSDate) -> NSRange {
        guard let small = CalendarUnits.component(smaller), let large = CalendarUnits.component(larger),
              let range = calendar.range(of: small, in: large, for: date.date) else {
            return NSRange(location: Int.max, length: 0)
        }
        return NSRange(location: range.lowerBound, length: range.count)
    }

    @ObjCMethod("minimumRangeOfUnit:")
    func minimumRange(of unit: UInt) -> NSRange {
        guard let component = CalendarUnits.component(unit), let range = calendar.minimumRange(of: component) else {
            return NSRange(location: Int.max, length: 0)
        }
        return NSRange(location: range.lowerBound, length: range.count)
    }

    @ObjCMethod("maximumRangeOfUnit:")
    func maximumRange(of unit: UInt) -> NSRange {
        guard let component = CalendarUnits.component(unit), let range = calendar.maximumRange(of: component) else {
            return NSRange(location: Int.max, length: 0)
        }
        return NSRange(location: range.lowerBound, length: range.count)
    }

    @ObjCMethod("ordinalityOfUnit:inUnit:forDate:")
    func ordinality(of smaller: UInt, in larger: UInt, for date: NSDate) -> UInt {
        guard let small = CalendarUnits.component(smaller), let large = CalendarUnits.component(larger),
              let ordinal = calendar.ordinality(of: small, in: large, for: date.date) else { return UInt(Int.max) }
        return UInt(ordinal)
    }

    @ObjCMethod("rangeOfUnit:startDate:interval:forDate:")
    func range(of unit: UInt, start: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
               interval: UnsafeMutablePointer<Double>?, for date: NSDate) -> Bool {
        guard let component = CalendarUnits.component(unit),
              let found = calendar.dateInterval(of: component, for: date.date) else { return false }
        start?.pointee = Dates.autoreleased(found.start)
        interval?.pointee = found.duration
        return true
    }

    @ObjCMethod("isDate:inSameDayAsDate:")
    func isDate(_ first: NSDate, inSameDayAs second: NSDate) -> Bool { calendar.isDate(first.date, inSameDayAs: second.date) }

    @ObjCMethod("isDate:equalToDate:toUnitGranularity:")
    func isDate(_ first: NSDate, equalTo second: NSDate, toUnitGranularity unit: UInt) -> Bool {
        CalendarUnits.component(unit).map { calendar.isDate(first.date, equalTo: second.date, toGranularity: $0) } ?? false
    }

    /// NSComparisonResult: -1, 0 or 1.
    @ObjCMethod("compareDate:toDate:toUnitGranularity:")
    func compare(_ first: NSDate, to second: NSDate, toUnitGranularity unit: UInt) -> Int {
        guard let component = CalendarUnits.component(unit) else { return 0 }
        switch calendar.compare(first.date, to: second.date, toGranularity: component) {
        case .orderedAscending: return -1
        case .orderedSame: return 0
        case .orderedDescending: return 1
        }
    }

    @ObjCMethod("isDateInToday:") func isDateInToday(_ date: NSDate) -> Bool { calendar.isDateInToday(date.date) }
    @ObjCMethod("isDateInYesterday:") func isDateInYesterday(_ date: NSDate) -> Bool { calendar.isDateInYesterday(date.date) }
    @ObjCMethod("isDateInTomorrow:") func isDateInTomorrow(_ date: NSDate) -> Bool { calendar.isDateInTomorrow(date.date) }
    @ObjCMethod("isDateInWeekend:") func isDateInWeekend(_ date: NSDate) -> Bool { calendar.isDateInWeekend(date.date) }

    @ObjCMethod("nextDateAfterDate:matchingComponents:options:")
    func nextDate(after date: NSDate, matching components: ObjCObject, options: UInt) -> UnsafeMutableRawPointer? {
        nextDate(after: date.date, matching: DateComponentsBox.value(components.id), options: options)
    }

    private func nextDate(after date: Date, matching components: DateComponents, options: UInt) -> UnsafeMutableRawPointer? {
        let search = Calendars.search(options)
        return calendar.nextDate(after: date, matching: components, matchingPolicy: search.policy,
                                 repeatedTimePolicy: search.repeated, direction: search.direction).flatMap { Dates.autoreleased($0) }
    }

    @ObjCMethod("nextDateAfterDate:matchingUnit:value:options:")
    func nextDate(after date: NSDate, matchingUnit unit: UInt, value: Int, options: UInt) -> UnsafeMutableRawPointer? {
        guard let component = CalendarUnits.component(unit) else { return nil }
        var components = DateComponents()
        components.setValue(value, for: component)
        return nextDate(after: date.date, matching: components, options: options)
    }

    @ObjCMethod("nextDateAfterDate:matchingHour:minute:second:options:")
    func nextDate(after date: NSDate, matchingHour hour: Int, minute: Int, second: Int, options: UInt) -> UnsafeMutableRawPointer? {
        // A component given as NSDateComponentUndefined is not matched.
        func given(_ value: Int) -> Int? { value == dateComponentUndefined ? nil : value }
        let components = DateComponents(hour: given(hour), minute: given(minute), second: given(second))
        return nextDate(after: date.date, matching: components, options: options)
    }

    /// Calls the block with each date matching the components after the
    /// date, whether it matched exactly, and a stop flag; a strict search
    /// that finds nothing gives nil once and ends.
    @ObjCMethod("enumerateDatesStartingAfterDate:matchingComponents:options:usingBlock:")
    func enumerateDates(after date: NSDate, matching components: ObjCObject, options: UInt, using block: ObjCObject) {
        typealias Invoke = @convention(c) (id, id?, Bool, UnsafeMutablePointer<Bool>) -> Void
        let invoke = Blocks.invoke(block.id, as: Invoke.self)
        let search = Calendars.search(options)
        calendar.enumerateDates(startingAfter: date.date, matching: DateComponentsBox.value(components.id),
                                matchingPolicy: search.policy, repeatedTimePolicy: search.repeated,
                                direction: search.direction) { found, exact, stop in
            var stopped = false
            ObjC.autoreleasepool { invoke(block.id, found.flatMap { Dates.autoreleased($0) }, exact, &stopped) }
            if stopped { stop = true }
        }
    }

    @ObjCMethod("date:matchesComponents:")
    func date(_ date: NSDate, matchesComponents components: ObjCObject) -> Bool {
        calendar.date(date.date, matchesComponents: DateComponentsBox.value(components.id))
    }

    /// The weekend containing the date: its start and length. NO for a date
    /// on a weekday.
    @ObjCMethod("rangeOfWeekendStartDate:interval:containingDate:")
    func rangeOfWeekend(start: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, interval: UnsafeMutablePointer<Double>?,
                        containing date: NSDate) -> Bool {
        guard let weekend = calendar.dateIntervalOfWeekend(containing: date.date) else { return false }
        start?.pointee = Dates.autoreleased(weekend.start)
        interval?.pointee = weekend.duration
        return true
    }

    /// The next weekend after the date, or with NSCalendarSearchBackwards
    /// the one before it.
    @ObjCMethod("nextWeekendStartDate:interval:options:afterDate:")
    func nextWeekend(start: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, interval: UnsafeMutablePointer<Double>?,
                     options: UInt, after date: NSDate) -> Bool {
        guard let weekend = calendar.nextWeekend(startingAfter: date.date, direction: Calendars.search(options).direction) else {
            return false
        }
        start?.pointee = Dates.autoreleased(weekend.start)
        interval?.pointee = weekend.duration
        return true
    }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool { Calendars.calendar(other?.id) == calendar }

    @ObjCMethod("hash") func hash() -> UInt { UInt(bitPattern: calendar.hashValue) }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjC.retain(Calendars.autoreleased(calendar))! }

    @ObjCMethod("description")
    func description() -> String { "<_NSCopyOnWriteCalendarWrapper: \(objcObject)>" }
}

// MARK: - Date components

/// NSDateComponentUndefined, NSIntegerMax.
let dateComponentUndefined = Int.max

final class DateComponentsBox {
    var components = DateComponents()
    /// The deprecated week (NSWeekCalendarUnit), which DateComponents lacks.
    var week: Int?
    /// iOS 26's repeatedDay: whether the day is a repeated one (some
    /// lunisolar calendars have them).
    var repeatedDay = false

    nonisolated(unsafe) static var componentsClass: Class!

    static func value(_ object: id?) -> DateComponents {
        Storage.get(object, as: DateComponentsBox.self)?.components ?? DateComponents()
    }

    static func box(_ object: id) -> DateComponentsBox {
        if let box = Storage.get(object, as: DateComponentsBox.self) { return box }
        let box = DateComponentsBox()
        Storage.set(object, box)
        return box
    }

    static func autoreleased(_ components: DateComponents) -> id {
        let object = Storage.allocate(UnsafeMutableRawPointer(componentsClass))!
        box(object).components = components
        return ObjC.autorelease(object)!
    }

    static func get(_ object: id, _ component: Calendar.Component) -> Int {
        box(object).components.value(for: component) ?? dateComponentUndefined
    }

    static func set(_ object: id, _ component: Calendar.Component, _ value: Int) {
        box(object).components.setValue(value == dateComponentUndefined ? nil : value, for: component)
    }
}

/// NSDateComponents.
@ObjCClass("NSDateComponents")
public final class NSDateComponents: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        DateComponentsBox.componentsClass = cls.storage
    }

    var box: DateComponentsBox { DateComponentsBox.box(objcObject) }

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = box
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: DateComponentsBox.componentsClass)
    }

    @ObjCMethod("era") func getEra() -> Int { DateComponentsBox.get(objcObject, .era) }
    @ObjCMethod("setEra:") func setEra(_ value: Int) { DateComponentsBox.set(objcObject, .era, value) }
    @ObjCMethod("year") func getYear() -> Int { DateComponentsBox.get(objcObject, .year) }
    @ObjCMethod("setYear:") func setYear(_ value: Int) { DateComponentsBox.set(objcObject, .year, value) }
    @ObjCMethod("month") func getMonth() -> Int { DateComponentsBox.get(objcObject, .month) }
    @ObjCMethod("setMonth:") func setMonth(_ value: Int) { DateComponentsBox.set(objcObject, .month, value) }
    @ObjCMethod("day") func getDay() -> Int { DateComponentsBox.get(objcObject, .day) }
    @ObjCMethod("setDay:") func setDay(_ value: Int) { DateComponentsBox.set(objcObject, .day, value) }
    @ObjCMethod("hour") func getHour() -> Int { DateComponentsBox.get(objcObject, .hour) }
    @ObjCMethod("setHour:") func setHour(_ value: Int) { DateComponentsBox.set(objcObject, .hour, value) }
    @ObjCMethod("minute") func getMinute() -> Int { DateComponentsBox.get(objcObject, .minute) }
    @ObjCMethod("setMinute:") func setMinute(_ value: Int) { DateComponentsBox.set(objcObject, .minute, value) }
    @ObjCMethod("second") func getSecond() -> Int { DateComponentsBox.get(objcObject, .second) }
    @ObjCMethod("setSecond:") func setSecond(_ value: Int) { DateComponentsBox.set(objcObject, .second, value) }
    @ObjCMethod("nanosecond") func getNanosecond() -> Int { DateComponentsBox.get(objcObject, .nanosecond) }
    @ObjCMethod("setNanosecond:") func setNanosecond(_ value: Int) { DateComponentsBox.set(objcObject, .nanosecond, value) }
    @ObjCMethod("weekday") func getWeekday() -> Int { DateComponentsBox.get(objcObject, .weekday) }
    @ObjCMethod("setWeekday:") func setWeekday(_ value: Int) { DateComponentsBox.set(objcObject, .weekday, value) }
    @ObjCMethod("weekdayOrdinal") func getWeekdayOrdinal() -> Int { DateComponentsBox.get(objcObject, .weekdayOrdinal) }
    @ObjCMethod("setWeekdayOrdinal:") func setWeekdayOrdinal(_ value: Int) { DateComponentsBox.set(objcObject, .weekdayOrdinal, value) }
    @ObjCMethod("quarter") func getQuarter() -> Int { DateComponentsBox.get(objcObject, .quarter) }
    @ObjCMethod("setQuarter:") func setQuarter(_ value: Int) { DateComponentsBox.set(objcObject, .quarter, value) }
    @ObjCMethod("weekOfMonth") func getWeekOfMonth() -> Int { DateComponentsBox.get(objcObject, .weekOfMonth) }
    @ObjCMethod("setWeekOfMonth:") func setWeekOfMonth(_ value: Int) { DateComponentsBox.set(objcObject, .weekOfMonth, value) }
    @ObjCMethod("weekOfYear") func getWeekOfYear() -> Int { DateComponentsBox.get(objcObject, .weekOfYear) }
    @ObjCMethod("setWeekOfYear:") func setWeekOfYear(_ value: Int) { DateComponentsBox.set(objcObject, .weekOfYear, value) }
    @ObjCMethod("yearForWeekOfYear") func getYearForWeekOfYear() -> Int { DateComponentsBox.get(objcObject, .yearForWeekOfYear) }
    @ObjCMethod("setYearForWeekOfYear:") func setYearForWeekOfYear(_ value: Int) { DateComponentsBox.set(objcObject, .yearForWeekOfYear, value) }
    @ObjCMethod("dayOfYear") func getDayOfYear() -> Int { DateComponentsBox.get(objcObject, .dayOfYear) }
    @ObjCMethod("setDayOfYear:") func setDayOfYear(_ value: Int) { DateComponentsBox.set(objcObject, .dayOfYear, value) }

    @ObjCMethod("isLeapMonth") func isLeapMonth() -> Bool { box.components.isLeapMonth ?? false }
    @ObjCMethod("setLeapMonth:") func setLeapMonth(_ value: Bool) { box.components.isLeapMonth = value }
    @ObjCMethod("isRepeatedDay") func isRepeatedDay() -> Bool { box.repeatedDay }
    @ObjCMethod("setRepeatedDay:") func setRepeatedDay(_ value: Bool) { box.repeatedDay = value }

    /// The deprecated week, apart from the week of the month and of the year.
    @ObjCMethod("week") func getWeek() -> Int { box.week ?? dateComponentUndefined }
    @ObjCMethod("setWeek:") func setWeek(_ value: Int) { box.week = value == dateComponentUndefined ? nil : value }

    @ObjCMethod("calendar") func calendar() -> UnsafeMutableRawPointer? { box.components.calendar.map(Calendars.autoreleased) }
    @ObjCMethod("setCalendar:") func setCalendar(_ calendar: ObjCObject?) { box.components.calendar = Calendars.calendar(calendar?.id) }
    @ObjCMethod("timeZone") func timeZone() -> UnsafeMutableRawPointer? { box.components.timeZone.map(TimeZones.autoreleased) }
    @ObjCMethod("setTimeZone:") func setTimeZone(_ zone: ObjCObject?) { box.components.timeZone = TimeZones.zone(zone?.id) }

    @ObjCMethod("date") func date() -> UnsafeMutableRawPointer? { box.components.date.flatMap { Dates.autoreleased($0) } }
    @ObjCMethod("isValidDate") func isValidDate() -> Bool { box.components.isValidDate }

    @ObjCMethod("isValidDateInCalendar:")
    func isValidDate(in calendar: ObjCObject) -> Bool {
        Calendars.calendar(calendar.id).map { box.components.isValidDate(in: $0) } ?? false
    }

    @ObjCMethod("valueForComponent:")
    func value(forComponent unit: UInt) -> Int {
        if unit == CalendarUnits.week { return getWeek() }
        return CalendarUnits.component(unit).map { DateComponentsBox.get(objcObject, $0) } ?? dateComponentUndefined
    }

    @ObjCMethod("setValue:forComponent:")
    func setValue(_ value: Int, forComponent unit: UInt) {
        if unit == CalendarUnits.week { return setWeek(value) }
        if let component = CalendarUnits.component(unit) { DateComponentsBox.set(objcObject, component, value) }
    }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer {
        let copy = DateComponentsBox.autoreleased(box.components)
        let copied = DateComponentsBox.box(copy)
        (copied.week, copied.repeatedDay) = (box.week, box.repeatedDay)
        return ObjC.retain(copy)!
    }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool {
        guard let other = Storage.get(other?.id, as: DateComponentsBox.self) else { return false }
        return other.components == box.components && other.week == box.week && other.repeatedDay == box.repeatedDay
    }

    @ObjCMethod("hash") func hash() -> UInt { UInt(bitPattern: box.components.hashValue) }

    /// Darwin's form: the class, then each set component on its own line.
    @ObjCMethod("description")
    func description() -> String {
        let components = box.components
        var lines: [String] = []
        if let calendar = components.calendar { lines.append("Calendar: \(CalendarIdentifiers.name(calendar.identifier))") }
        if let zone = components.timeZone { lines.append("TimeZone: \(zone.identifier)") }
        let names: [(String, Calendar.Component)] = [
            ("Era", .era), ("Calendar Year", .year), ("Month", .month), ("Leap Month", .isLeapMonth), ("Day", .day),
            ("Hour", .hour), ("Minute", .minute), ("Second", .second), ("Nanosecond", .nanosecond),
            ("Quarter", .quarter), ("Year for Week of Year", .yearForWeekOfYear), ("Week of Year", .weekOfYear),
            ("Week of Month", .weekOfMonth), ("Weekday", .weekday), ("Weekday Ordinal", .weekdayOrdinal),
        ]
        for (name, component) in names {
            if component == .isLeapMonth {
                if let leap = components.isLeapMonth { lines.append("\(name): \(leap ? 1 : 0)") }
            } else if let value = components.value(for: component) {
                lines.append("\(name): \(value)")
            }
        }
        return "<NSDateComponents: \(objcObject)>\n" + lines.map { "    \($0)" }.joined(separator: "\n")
    }
}
