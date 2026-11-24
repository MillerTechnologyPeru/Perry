import CPerryFoundation
import FoundationEssentials
import FoundationInternationalization
import PerryObjCInterop
import _FoundationICU

// NSDateIntervalFormatter, NSRelativeDateTimeFormatter and NSListFormatter
// over ICU's interval, relative date and list formatters, as Darwin's are;
// NSMassFormatter and NSEnergyFormatter write their units as Darwin does
// in English, with numbers from their number formatter, as
// NSLengthFormatter does.

enum MoreFormatterSupport {
    /// A new, initialized instance of the object's class, +1: what a
    /// formatter's -copy starts from.
    static func fresh(like object: id) -> id? {
        let cls = ObjC.objectGetClass(object).map { UnsafeMutableRawPointer($0) }
        return ObjC.send(ObjC.send(cls, ObjC.selector("alloc")), ObjC.selector("init"))
    }

    /// A number formatter that writes up to three fraction digits, as the
    /// unit formatters' own does, +1.
    static func makeNumberFormatter() -> id? {
        guard let cls = "NSNumberFormatter".withCString({ ObjC.getClass($0) }),
              let made = ObjC.send(ObjC.send(UnsafeMutableRawPointer(cls), ObjC.selector("alloc")), ObjC.selector("init")) else { return nil }
        typealias SetUInt = @convention(c) (id, SEL, UInt) -> Void
        unsafeBitCast(ObjC.msgSend, to: SetUInt.self)(made, ObjC.selector("setNumberStyle:"), 1)
        unsafeBitCast(ObjC.msgSend, to: SetUInt.self)(made, ObjC.selector("setMaximumFractionDigits:"), 3)
        return made
    }

    /// A number as the formatter writes it.
    static func string(_ value: Double, formatter: id?) -> String {
        if let formatter,
           let text = Strings.value(of: ObjC.send(formatter, ObjC.selector("stringFromNumber:"), Numbers.make(nil, .double(value)))) {
            return text
        }
        return String(value)
    }

    /// Whether the number reads as one: a unit's singular name follows.
    static func isOne(_ text: String, formatter: id?) -> Bool {
        let unsigned = text.hasPrefix("-") ? String(text.dropFirst()) : text
        return unsigned == string(1, formatter: formatter)
    }

    /// The number formatter's locale, which picks a unit formatter's
    /// measurement system on Darwin.
    static func locale(of formatter: id?) -> Locale {
        guard let formatter, let locale = ObjC.send(formatter, ObjC.selector("locale")) else { return Locales.current }
        return Locales.locale(locale)
    }

    /// Whether a locale measures in pounds and calories: the United
    /// States, Liberia and Myanmar.
    static func imperial(_ locale: Locale) -> Bool {
        ["US", "LR", "MM"].contains(locale.region?.identifier ?? "")
    }

    /// The locale ICU formats in, with the calendar as a keyword when it is
    /// not the locale's own.
    static func localeID(_ locale: Locale, calendar: Calendar?) -> String {
        guard let calendar, calendar.identifier != locale.calendar.identifier else { return locale.identifier }
        return locale.identifier + "@calendar=" + CalendarIdentifiers.name(calendar.identifier)
    }

    static func double(_ number: id) -> Double {
        typealias Fn = @convention(c) (id, SEL) -> Double
        return unsafeBitCast(ObjC.msgSend, to: Fn.self)(number, ObjC.selector("doubleValue"))
    }
}

// MARK: - NSDateIntervalFormatter

final class DateIntervalFormatterStorage {
    var locale: Locale?
    var calendar: Calendar?
    var timeZone: TimeZone?
    /// NSDateIntervalFormatterStyle: none 0, short 1, medium 2, long 3,
    /// full 4. Darwin's formatters start short and short.
    var dateStyle = 1
    var timeStyle = 1
    /// A template set with -setDateTemplate:, used until a style is set.
    var template: String?
    var templateFromStyles = true

    var effectiveLocale: Locale { locale ?? Locales.current }
    var effectiveZone: TimeZone { timeZone ?? TimeZones.current }
    var localeID: String { MoreFormatterSupport.localeID(effectiveLocale, calendar: calendar) }

    func copy(from other: DateIntervalFormatterStorage) {
        locale = other.locale
        calendar = other.calendar
        timeZone = other.timeZone
        dateStyle = other.dateStyle
        timeStyle = other.timeStyle
        template = other.template
        templateFromStyles = other.templateFromStyles
    }

    private static func icuStyle(_ style: Int) -> UDateFormatStyle {
        switch style {
        case 1: return UDAT_SHORT
        case 2: return UDAT_MEDIUM
        case 3: return UDAT_LONG
        case 4: return UDAT_FULL
        default: return UDAT_NONE
        }
    }

    /// The date formatter's pattern for the styles, which -dateTemplate
    /// gives until a template is set.
    var stylesPattern: String {
        guard dateStyle != 0 || timeStyle != 0 else { return "" }
        var status = U_ZERO_ERROR
        let handle = ICU.withUChars(effectiveZone.identifier) { zone, zoneLength in
            swift_udat_open(Self.icuStyle(timeStyle), Self.icuStyle(dateStyle), localeID, zone, zoneLength, nil, 0, &status)
        }
        guard let handle, !ICU.failed(status) else { return "" }
        defer { swift_udat_close(handle) }
        return ICU.string { swift_udat_toPattern(handle, 0, $0, $1, $2) } ?? ""
    }

    var dateTemplate: String? { templateFromStyles ? stylesPattern : template }

    /// The skeleton ICU's interval formatter takes: the template, or the
    /// styles' pattern's skeleton, as CFDateIntervalFormatter makes it.
    var skeleton: String {
        guard templateFromStyles else { return template ?? "" }
        let pattern = stylesPattern
        guard !pattern.isEmpty else { return "" }
        return ICU.withUChars(pattern) { chars, length in
            ICU.string { swift_udatpg_getSkeleton(nil, chars, length, $0, $1, $2) }
        } ?? ""
    }

    func string(from start: Date, to end: Date) -> String {
        let skeleton = self.skeleton
        guard !skeleton.isEmpty else { return "" }
        var status = U_ZERO_ERROR
        let handle: OpaquePointer? = ICU.withUChars(skeleton) { chars, length in
            ICU.withUChars(effectiveZone.identifier) { zone, zoneLength in
                swift_udtitvfmt_open(localeID, chars, length, zone, zoneLength, &status)
            }
        }
        guard let handle, !ICU.failed(status) else { return "" }
        defer { swift_udtitvfmt_close(handle) }
        let from = start.timeIntervalSince1970 * 1000, to = end.timeIntervalSince1970 * 1000
        return ICU.string { swift_udtitvfmt_format(handle, from, to, $0, $1, nil, $2) } ?? ""
    }
}

/// NSDateIntervalFormatter: two dates as one range, "Nov 14 – 15, 2023".
@ObjCClass("NSDateIntervalFormatter")
public class NSDateIntervalFormatter: NSFormatter {
    nonisolated(unsafe) static var formatterClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        formatterClass = cls.storage
    }

    var state: DateIntervalFormatterStorage {
        if let state = Storage.get(objcObject, as: DateIntervalFormatterStorage.self) { return state }
        let state = DateIntervalFormatterStorage()
        Storage.set(objcObject, state)
        return state
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = state
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSDateIntervalFormatter.formatterClass)
    }

    @ObjCMethod("copyWithZone:")
    func copyIntervalFormatter(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let copy = MoreFormatterSupport.fresh(like: objcObject) else { return nil }
        Storage.get(copy, as: DateIntervalFormatterStorage.self)?.copy(from: state)
        return copy
    }

    @ObjCMethod("locale") func locale() -> UnsafeMutableRawPointer { Locales.autoreleased(state.effectiveLocale) }
    @ObjCMethod("setLocale:") func setLocale(_ locale: ObjCObject?) { state.locale = locale.map { Locales.locale($0.objcObject) } }

    @ObjCMethod("calendar")
    func calendar() -> UnsafeMutableRawPointer {
        var calendar = state.calendar ?? Calendar(identifier: state.effectiveLocale.calendar.identifier)
        if state.calendar == nil {
            calendar.locale = state.effectiveLocale
            calendar.timeZone = state.effectiveZone
        }
        return Calendars.autoreleased(calendar)
    }

    @ObjCMethod("setCalendar:") func setCalendar(_ calendar: ObjCObject?) { state.calendar = Calendars.calendar(calendar?.objcObject) }

    @ObjCMethod("timeZone") func timeZone() -> UnsafeMutableRawPointer { TimeZones.autoreleased(state.effectiveZone) }
    @ObjCMethod("setTimeZone:") func setTimeZone(_ zone: ObjCObject?) { state.timeZone = TimeZones.zone(zone?.objcObject) }

    /// The template set, or the date format the styles make.
    @ObjCMethod("dateTemplate") func dateTemplate() -> String? { state.dateTemplate }

    @ObjCMethod("setDateTemplate:")
    func setDateTemplate(_ template: String?) {
        state.template = template
        state.templateFromStyles = false
    }

    /// Setting a style replaces the template, as on Darwin.
    @ObjCMethod("dateStyle") func dateStyle() -> UInt { UInt(state.dateStyle) }
    @ObjCMethod("setDateStyle:")
    func setDateStyle(_ style: UInt) {
        state.dateStyle = Int(style)
        state.templateFromStyles = true
    }

    @ObjCMethod("timeStyle") func timeStyle() -> UInt { UInt(state.timeStyle) }
    @ObjCMethod("setTimeStyle:")
    func setTimeStyle(_ style: UInt) {
        state.timeStyle = Int(style)
        state.templateFromStyles = true
    }

    @ObjCMethod("stringFromDate:toDate:")
    func string(fromDate start: ObjCObject?, toDate end: ObjCObject?) -> String {
        guard let start, let end else { return "" }
        return state.string(from: Dates.date(start.objcObject), to: Dates.date(end.objcObject))
    }

    @ObjCMethod("stringFromDateInterval:")
    func string(fromDateInterval interval: ObjCObject?) -> String? {
        guard let interval = Storage.get(interval?.objcObject, as: DateIntervalStorage.self) else { return nil }
        return state.string(from: interval.start, to: interval.start.addingTimeInterval(interval.duration))
    }

    /// An NSDateInterval's text; nil for anything else.
    @ObjCMethod("stringForObjectValue:")
    func intervalString(forObjectValue value: ObjCObject?) -> String? { string(fromDateInterval: value) }
}

// MARK: - NSRelativeDateTimeFormatter

final class RelativeDateTimeFormatterStorage {
    /// NSRelativeDateTimeFormatterStyle: numeric 0, named 1.
    var dateTimeStyle = 0
    /// NSRelativeDateTimeFormatterUnitsStyle: full 0, spell out 1, short 2,
    /// abbreviated 3.
    var unitsStyle = 0
    /// NSFormattingContext.
    var formattingContext = 0
    var calendar: Calendar?
    var locale: Locale?

    var effectiveLocale: Locale { locale ?? Locales.current }
    var effectiveCalendar: Calendar { calendar ?? Calendars.make(Locales.current.calendar.identifier) }

    func copy(from other: RelativeDateTimeFormatterStorage) {
        dateTimeStyle = other.dateTimeStyle
        unitsStyle = other.unitsStyle
        formattingContext = other.formattingContext
        calendar = other.calendar
        locale = other.locale
    }

    /// The units a relative date is told in, largest first.
    static let units: [(component: Calendar.Component, unit: URelativeDateTimeUnit)] = [
        (.year, UDAT_REL_UNIT_YEAR), (.month, UDAT_REL_UNIT_MONTH), (.weekOfMonth, UDAT_REL_UNIT_WEEK), (.day, UDAT_REL_UNIT_DAY),
        (.hour, UDAT_REL_UNIT_HOUR), (.minute, UDAT_REL_UNIT_MINUTE), (.second, UDAT_REL_UNIT_SECOND),
    ]

    /// NSFormattingContext as ICU's capitalization.
    private var capitalization: UDisplayContext {
        switch formattingContext {
        case 2: return UDISPCTX_CAPITALIZATION_FOR_STANDALONE
        case 3: return UDISPCTX_CAPITALIZATION_FOR_UI_LIST_OR_MENU
        case 4: return UDISPCTX_CAPITALIZATION_FOR_BEGINNING_OF_SENTENCE
        case 5: return UDISPCTX_CAPITALIZATION_FOR_MIDDLE_OF_SENTENCE
        default: return UDISPCTX_CAPITALIZATION_NONE
        }
    }

    /// "in 2 days", "yesterday": a count of a unit, as ICU's relative date
    /// formatter writes it, with names ("tomorrow") in the named style.
    func string(_ value: Int, _ unit: URelativeDateTimeUnit) -> String {
        let localeID = effectiveLocale.identifier
        var status = U_ZERO_ERROR
        var numberFormat: UnsafeMutablePointer<UNumberFormat?>? = nil
        if unitsStyle == 1 {
            var numberStatus = U_ZERO_ERROR
            numberFormat = swift_unum_open(UNUM_SPELLOUT, nil, 0, localeID, nil, &numberStatus)
            if ICU.failed(numberStatus), let made = numberFormat {
                swift_unum_close(made)
                numberFormat = nil
            }
        }
        let width: UDateRelativeDateTimeFormatterStyle
        switch unitsStyle {
        case 2: width = UDAT_STYLE_SHORT
        case 3: width = UDAT_STYLE_NARROW
        default: width = UDAT_STYLE_LONG
        }
        // The formatter adopts the number format.
        let handle: OpaquePointer? = swift_ureldatefmt_open(localeID, numberFormat, width, capitalization, &status)
        guard let handle, !ICU.failed(status) else { return "" }
        defer { swift_ureldatefmt_close(handle) }
        let offset = Double(value)
        if dateTimeStyle == 1 {
            return ICU.string { swift_ureldatefmt_format(handle, offset, unit, $0, $1, $2) } ?? ""
        }
        return ICU.string { swift_ureldatefmt_formatNumeric(handle, offset, unit, $0, $1, $2) } ?? ""
    }

    /// The largest unit with a count, or the smallest given when none has
    /// one; nil when the components give none of the units.
    func string(from components: DateComponents) -> String? {
        var chosen: (value: Int, unit: URelativeDateTimeUnit)?
        for entry in Self.units {
            guard let value = components.value(for: entry.component), value != Int.max else { continue }
            if value != 0 { return string(value, entry.unit) }
            chosen = (0, entry.unit)
        }
        return chosen.map { string($0.value, $0.unit) }
    }

    func string(for date: Date, relativeTo reference: Date) -> String {
        let components = effectiveCalendar.dateComponents(Set(Self.units.map(\.component)), from: reference, to: date)
        return string(from: components) ?? string(0, UDAT_REL_UNIT_SECOND)
    }
}

/// NSRelativeDateTimeFormatter: a date relative to another, "2 days ago".
@ObjCClass("NSRelativeDateTimeFormatter")
public class NSRelativeDateTimeFormatter: NSFormatter {
    nonisolated(unsafe) static var formatterClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        formatterClass = cls.storage
    }

    var state: RelativeDateTimeFormatterStorage {
        if let state = Storage.get(objcObject, as: RelativeDateTimeFormatterStorage.self) { return state }
        let state = RelativeDateTimeFormatterStorage()
        Storage.set(objcObject, state)
        return state
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = state
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSRelativeDateTimeFormatter.formatterClass)
    }

    @ObjCMethod("copyWithZone:")
    func copyRelativeFormatter(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let copy = MoreFormatterSupport.fresh(like: objcObject) else { return nil }
        Storage.get(copy, as: RelativeDateTimeFormatterStorage.self)?.copy(from: state)
        return copy
    }

    @ObjCMethod("dateTimeStyle") func dateTimeStyle() -> Int { state.dateTimeStyle }
    @ObjCMethod("setDateTimeStyle:") func setDateTimeStyle(_ style: Int) { state.dateTimeStyle = style }
    @ObjCMethod("unitsStyle") func unitsStyle() -> Int { state.unitsStyle }
    @ObjCMethod("setUnitsStyle:") func setUnitsStyle(_ style: Int) { state.unitsStyle = style }
    @ObjCMethod("formattingContext") func formattingContext() -> Int { state.formattingContext }
    @ObjCMethod("setFormattingContext:") func setFormattingContext(_ context: Int) { state.formattingContext = context }

    @ObjCMethod("calendar") func calendar() -> UnsafeMutableRawPointer { Calendars.autoreleased(state.effectiveCalendar) }
    @ObjCMethod("setCalendar:") func setCalendar(_ calendar: ObjCObject?) { state.calendar = Calendars.calendar(calendar?.objcObject) }
    @ObjCMethod("locale") func locale() -> UnsafeMutableRawPointer { Locales.autoreleased(state.effectiveLocale) }
    @ObjCMethod("setLocale:") func setLocale(_ locale: ObjCObject?) { state.locale = locale.map { Locales.locale($0.objcObject) } }

    /// The largest unit the components give a count of; nil when they give
    /// none of year, month, week of month, day, hour, minute and second, as
    /// on Darwin.
    @ObjCMethod("localizedStringFromDateComponents:")
    func localizedString(fromDateComponents components: ObjCObject?) -> String? {
        state.string(from: DateComponentsBox.value(components?.objcObject))
    }

    @ObjCMethod("localizedStringFromTimeInterval:")
    func localizedString(fromTimeInterval interval: Double) -> String {
        let now = Date()
        return state.string(for: now.addingTimeInterval(interval), relativeTo: now)
    }

    @ObjCMethod("localizedStringForDate:relativeToDate:")
    func localizedString(forDate date: ObjCObject?, relativeToDate reference: ObjCObject?) -> String {
        state.string(for: Dates.date(date?.objcObject), relativeTo: Dates.date(reference?.objcObject))
    }

    /// A date relative to now; nil for anything else.
    @ObjCMethod("stringForObjectValue:")
    func relativeString(forObjectValue value: ObjCObject?) -> String? {
        guard let value, ObjC.isKind(value.objcObject, of: Dates.dateClass) else { return nil }
        return state.string(for: Dates.date(value.objcObject), relativeTo: Date())
    }
}

// MARK: - NSListFormatter

final class ListFormatterStorage {
    var locale: Locale?
    var itemFormatter: id?

    deinit {
        if let itemFormatter { ObjC.release(itemFormatter) }
    }

    var effectiveLocale: Locale { locale ?? Locales.current }

    /// An item's text: the item formatter's, else the string's, else its
    /// description.
    func text(_ item: id) -> String {
        if let itemFormatter, let text = Strings.value(of: ObjC.send(itemFormatter, ObjC.selector("stringForObjectValue:"), item)) {
            return text
        }
        if let text = Strings.value(of: item) { return text }
        return Strings.value(of: ObjC.send(item, ObjC.selector("description"))) ?? ""
    }

    /// The items joined as the locale lists them, "a, b, and c".
    static func join(_ items: [String], locale: Locale) -> String {
        var status = U_ZERO_ERROR
        let handle: OpaquePointer? = swift_ulistfmt_open(locale.identifier, &status)
        guard let handle, !ICU.failed(status) else { return items.joined(separator: ", ") }
        defer { swift_ulistfmt_close(handle) }
        // One buffer holds every item; each pointer is an offset into it.
        var units: [UChar] = []
        var offsets: [Int] = []
        var lengths: [Int32] = []
        for item in items {
            offsets.append(units.count)
            let itemUnits = Array(item.utf16)
            lengths.append(Int32(itemUnits.count))
            units += itemUnits
        }
        units.append(0)
        return units.withUnsafeBufferPointer { buffer -> String in
            let base = buffer.baseAddress!
            let pointers: [UnsafePointer<UChar>?] = offsets.map { base + $0 }
            return ICU.string { swift_ulistfmt_format(handle, pointers, lengths, Int32(items.count), $0, $1, $2) }
                ?? items.joined(separator: ", ")
        }
    }
}

/// NSListFormatter: items as a list, "apples, pears, and plums".
@ObjCClass("NSListFormatter")
public class NSListFormatter: NSFormatter {
    nonisolated(unsafe) static var formatterClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        formatterClass = cls.storage
    }

    var state: ListFormatterStorage {
        if let state = Storage.get(objcObject, as: ListFormatterStorage.self) { return state }
        let state = ListFormatterStorage()
        Storage.set(objcObject, state)
        return state
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = state
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSListFormatter.formatterClass)
    }

    @ObjCMethod("copyWithZone:")
    func copyListFormatter(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let copy = MoreFormatterSupport.fresh(like: objcObject),
              let theirs = Storage.get(copy, as: ListFormatterStorage.self) else { return nil }
        theirs.locale = state.locale
        theirs.itemFormatter = state.itemFormatter.flatMap { ObjC.retain($0) }
        return copy
    }

    @ObjCClassMethod("localizedStringByJoiningStrings:")
    static func localizedString(byJoiningStrings strings: ObjCObject?) -> String {
        let items = Arrays.elements(strings?.objcObject).map { Strings.value(of: $0) ?? "" }
        return ListFormatterStorage.join(items, locale: Locales.current)
    }

    @ObjCMethod("locale") func locale() -> UnsafeMutableRawPointer { Locales.autoreleased(state.effectiveLocale) }
    @ObjCMethod("setLocale:") func setLocale(_ locale: ObjCObject?) { state.locale = locale.map { Locales.locale($0.objcObject) } }

    @ObjCMethod("itemFormatter") func itemFormatter() -> UnsafeMutableRawPointer? { state.itemFormatter }

    /// A copy, as the property is declared copy.
    @ObjCMethod("setItemFormatter:")
    func setItemFormatter(_ formatter: ObjCObject?) {
        let copy = formatter.flatMap { ObjC.send($0.objcObject, Selectors.copyWithZone, nil) }
        if let old = state.itemFormatter { ObjC.release(old) }
        state.itemFormatter = copy
    }

    @ObjCMethod("stringFromItems:")
    func string(fromItems items: ObjCObject?) -> String? {
        guard let items else { return nil }
        let state = state
        return ListFormatterStorage.join(Arrays.elements(items.objcObject).map(state.text), locale: state.effectiveLocale)
    }

    /// An array's items as a list; nil for anything else.
    @ObjCMethod("stringForObjectValue:")
    func listString(forObjectValue value: ObjCObject?) -> String? {
        guard let value, ObjC.isKind(value.objcObject, of: Arrays.arrayClass) else { return nil }
        return string(fromItems: value)
    }
}

// MARK: - Mass and energy

/// A unit of NSMassFormatterUnit or NSEnergyFormatterUnit: its size in the
/// base unit and its writings: after a number in the short style, alone in
/// the short style, in the medium style, and in the long style.
struct FormatterUnitNames {
    let size: Double
    let short: String
    let shortAlone: String
    let medium: String
    let singular: String
    let plural: String
    /// The long name alone, when it is not the singular or plural by count.
    var longAlone: String? = nil
}

final class UnitFormatterStorage {
    /// NSFormattingUnitStyle: short 1, medium 2, long 3.
    var unitStyle = 2
    /// forPersonMassUse or forFoodEnergyUse.
    var special = false
    var numberFormatter: id?

    deinit {
        if let numberFormatter { ObjC.release(numberFormatter) }
    }

    var formatter: id? {
        if numberFormatter == nil { numberFormatter = MoreFormatterSupport.makeNumberFormatter() }
        return numberFormatter
    }

    func copy(from other: UnitFormatterStorage) {
        unitStyle = other.unitStyle
        special = other.special
        if let numberFormatter { ObjC.release(numberFormatter) }
        numberFormatter = other.numberFormatter.flatMap { ObjC.send($0, Selectors.copyWithZone, nil) }
    }

    func number(_ value: Double) -> String { MoreFormatterSupport.string(value, formatter: formatter) }

    /// A value and its unit's name in the style.
    func string(_ value: Double, _ names: FormatterUnitNames) -> String {
        let text = number(value)
        switch unitStyle {
        case 1: return text + names.short
        case 3: return text + " " + (MoreFormatterSupport.isOne(text, formatter: formatter) ? names.singular : names.plural)
        default: return text + " " + names.medium
        }
    }

    /// A unit's name alone, as for a value.
    func unitString(_ value: Double, _ names: FormatterUnitNames) -> String {
        switch unitStyle {
        case 1: return names.shortAlone
        case 3:
            if let alone = names.longAlone { return alone }
            return MoreFormatterSupport.isOne(number(value), formatter: formatter) ? names.singular : names.plural
        default: return names.medium
        }
    }
}

/// NSMassFormatter: a mass as text, "2.5 kg".
@ObjCClass("NSMassFormatter")
public class NSMassFormatter: NSFormatter {
    nonisolated(unsafe) static var formatterClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        formatterClass = cls.storage
    }

    var state: UnitFormatterStorage {
        if let state = Storage.get(objcObject, as: UnitFormatterStorage.self) { return state }
        let state = UnitFormatterStorage()
        Storage.set(objcObject, state)
        return state
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = state
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSMassFormatter.formatterClass)
    }

    @ObjCMethod("copyWithZone:")
    func copyMassFormatter(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let copy = MoreFormatterSupport.fresh(like: objcObject) else { return nil }
        Storage.get(copy, as: UnitFormatterStorage.self)?.copy(from: state)
        return copy
    }

    @ObjCMethod("unitStyle") func unitStyle() -> Int { state.unitStyle }
    @ObjCMethod("setUnitStyle:") func setUnitStyle(_ style: Int) { state.unitStyle = style }

    /// Kept; Darwin picks the same units for a person's mass.
    @ObjCMethod("isForPersonMassUse") func isForPersonMassUse() -> Bool { state.special }
    @ObjCMethod("setForPersonMassUse:") func setForPersonMassUse(_ use: Bool) { state.special = use }

    @ObjCMethod("numberFormatter") func numberFormatter() -> UnsafeMutableRawPointer? { state.formatter }

    /// Nil restores a formatter of up to three fraction digits.
    @ObjCMethod("setNumberFormatter:")
    func setNumberFormatter(_ formatter: ObjCObject?) {
        let copy = formatter.flatMap { ObjC.send($0.objcObject, Selectors.copyWithZone, nil) }
        if let old = state.numberFormatter { ObjC.release(old) }
        state.numberFormatter = copy
    }

    /// NSMassFormatterUnit: gram 11, kilogram 14, ounce 1537, pound 1538,
    /// stone 1539, with kilograms per unit.
    private static let units: [Int: FormatterUnitNames] = [
        11: FormatterUnitNames(size: 0.001, short: "g", shortAlone: "g", medium: "g", singular: "gram", plural: "grams"),
        14: FormatterUnitNames(size: 1, short: "kg", shortAlone: "kg", medium: "kg", singular: "kilogram", plural: "kilograms"),
        1537: FormatterUnitNames(size: 0.028349523125, short: "oz", shortAlone: "oz", medium: "oz", singular: "ounce", plural: "ounces"),
        1538: FormatterUnitNames(size: 0.45359237, short: "#", shortAlone: "lb", medium: "lb", singular: "pound", plural: "pounds"),
        1539: FormatterUnitNames(size: 6.35029318, short: "st", shortAlone: "st", medium: "st", singular: "stone", plural: "stones",
                                 longAlone: "stone"),
    ]

    @ObjCMethod("stringFromValue:unit:")
    func string(fromValue value: Double, unit: Int) -> String {
        guard let names = NSMassFormatter.units[unit] else { return state.number(value) }
        // Stones with a fraction: whole stones, then the rest in pounds.
        if unit == 1539, value > 0, value != value.rounded(.down), let pounds = NSMassFormatter.units[1538] {
            let whole = value.rounded(.down), rest = (value - whole) * 14
            switch state.unitStyle {
            case 1: return state.string(whole, names) + " " + state.string(rest, pounds)
            default: return state.string(whole, names) + ", " + state.string(rest, pounds)
            }
        }
        return state.string(value, names)
    }

    @ObjCMethod("unitStringFromValue:unit:")
    func unitString(fromValue value: Double, unit: Int) -> String {
        NSMassFormatter.units[unit].map { state.unitString(value, $0) } ?? ""
    }

    /// The unit that suits a mass in kilograms, and the mass in it: grams
    /// or ounces up to a kilogram or a pound, as on Darwin.
    private func suited(_ kilograms: Double) -> (value: Double, unit: Int) {
        if MoreFormatterSupport.imperial(MoreFormatterSupport.locale(of: state.formatter)) {
            let pounds = kilograms / 0.45359237
            return pounds > 0 && pounds <= 1 ? (kilograms / 0.028349523125, 1537) : (pounds, 1538)
        }
        return kilograms > 0 && kilograms <= 1 ? (kilograms * 1000, 11) : (kilograms, 14)
    }

    @ObjCMethod("stringFromKilograms:")
    func string(fromKilograms kilograms: Double) -> String {
        let (value, unit) = suited(kilograms)
        return string(fromValue: value, unit: unit)
    }

    @ObjCMethod("unitStringFromKilograms:usedUnit:")
    func unitString(fromKilograms kilograms: Double, usedUnit: UnsafeMutablePointer<Int>?) -> String {
        let (value, unit) = suited(kilograms)
        usedUnit?.pointee = unit
        return unitString(fromValue: value, unit: unit)
    }

    /// Darwin's mass formatter does not parse.
    @ObjCMethod("getObjectValue:forString:errorDescription:")
    func massObjectValue(_ value: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, for string: String?,
                         errorDescription: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool { false }

    /// A number of kilograms; nil for anything else.
    @ObjCMethod("stringForObjectValue:")
    func massString(forObjectValue value: ObjCObject?) -> String? {
        guard let value, ObjC.isKind(value.objcObject, of: Numbers.numberClass) else { return nil }
        return string(fromKilograms: MoreFormatterSupport.double(value.objcObject))
    }
}

/// NSEnergyFormatter: an energy as text, "1,000 cal".
@ObjCClass("NSEnergyFormatter")
public class NSEnergyFormatter: NSFormatter {
    nonisolated(unsafe) static var formatterClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        formatterClass = cls.storage
    }

    var state: UnitFormatterStorage {
        if let state = Storage.get(objcObject, as: UnitFormatterStorage.self) { return state }
        let state = UnitFormatterStorage()
        Storage.set(objcObject, state)
        return state
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = state
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSEnergyFormatter.formatterClass)
    }

    @ObjCMethod("copyWithZone:")
    func copyEnergyFormatter(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let copy = MoreFormatterSupport.fresh(like: objcObject) else { return nil }
        Storage.get(copy, as: UnitFormatterStorage.self)?.copy(from: state)
        return copy
    }

    @ObjCMethod("unitStyle") func unitStyle() -> Int { state.unitStyle }
    @ObjCMethod("setUnitStyle:") func setUnitStyle(_ style: Int) { state.unitStyle = style }

    /// Food energy: kilocalories are Calories.
    @ObjCMethod("isForFoodEnergyUse") func isForFoodEnergyUse() -> Bool { state.special }
    @ObjCMethod("setForFoodEnergyUse:") func setForFoodEnergyUse(_ use: Bool) { state.special = use }

    @ObjCMethod("numberFormatter") func numberFormatter() -> UnsafeMutableRawPointer? { state.formatter }

    /// Nil restores a formatter of up to three fraction digits.
    @ObjCMethod("setNumberFormatter:")
    func setNumberFormatter(_ formatter: ObjCObject?) {
        let copy = formatter.flatMap { ObjC.send($0.objcObject, Selectors.copyWithZone, nil) }
        if let old = state.numberFormatter { ObjC.release(old) }
        state.numberFormatter = copy
    }

    /// NSEnergyFormatterUnit: joule 11, kilojoule 14, calorie 1793,
    /// kilocalorie 1794, with joules per unit.
    private static let units: [Int: FormatterUnitNames] = [
        11: FormatterUnitNames(size: 1, short: "J", shortAlone: "J", medium: "J", singular: "joule", plural: "joules"),
        14: FormatterUnitNames(size: 1000, short: "kJ", shortAlone: "kJ", medium: "kJ", singular: "kilojoule", plural: "kilojoules"),
        1793: FormatterUnitNames(size: 4.184, short: "cal", shortAlone: "cal", medium: "cal", singular: "calorie", plural: "calories"),
        1794: FormatterUnitNames(size: 4184, short: "kcal", shortAlone: "kcal", medium: "kcal", singular: "kilocalorie",
                                 plural: "kilocalories"),
    ]
    /// A kilocalorie of food: a Calorie.
    private static let foodCalorie = FormatterUnitNames(size: 4184, short: "Cal", shortAlone: "C", medium: "Cal", singular: "Calorie",
                                                         plural: "Calories", longAlone: "Calories")

    private func names(_ unit: Int) -> FormatterUnitNames? {
        unit == 1794 && state.special ? NSEnergyFormatter.foodCalorie : NSEnergyFormatter.units[unit]
    }

    @ObjCMethod("stringFromValue:unit:")
    func string(fromValue value: Double, unit: Int) -> String {
        guard let names = names(unit) else { return state.number(value) }
        return state.string(value, names)
    }

    @ObjCMethod("unitStringFromValue:unit:")
    func unitString(fromValue value: Double, unit: Int) -> String { names(unit).map { state.unitString(value, $0) } ?? "" }

    /// The unit that suits an energy in joules, and the energy in it:
    /// joules or calories up to a kilojoule or a kilocalorie, as on Darwin.
    private func suited(_ joules: Double) -> (value: Double, unit: Int) {
        if MoreFormatterSupport.imperial(MoreFormatterSupport.locale(of: state.formatter)) {
            return joules > 0 && joules <= 4184 ? (joules / 4.184, 1793) : (joules / 4184, 1794)
        }
        return joules > 0 && joules <= 1000 ? (joules, 11) : (joules / 1000, 14)
    }

    @ObjCMethod("stringFromJoules:")
    func string(fromJoules joules: Double) -> String {
        let (value, unit) = suited(joules)
        return string(fromValue: value, unit: unit)
    }

    @ObjCMethod("unitStringFromJoules:usedUnit:")
    func unitString(fromJoules joules: Double, usedUnit: UnsafeMutablePointer<Int>?) -> String {
        let (value, unit) = suited(joules)
        usedUnit?.pointee = unit
        return unitString(fromValue: value, unit: unit)
    }

    /// Darwin's energy formatter does not parse.
    @ObjCMethod("getObjectValue:forString:errorDescription:")
    func energyObjectValue(_ value: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, for string: String?,
                           errorDescription: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool { false }

    /// A number of joules; nil for anything else.
    @ObjCMethod("stringForObjectValue:")
    func energyString(forObjectValue value: ObjCObject?) -> String? {
        guard let value, ObjC.isKind(value.objcObject, of: Numbers.numberClass) else { return nil }
        return string(fromJoules: MoreFormatterSupport.double(value.objcObject))
    }
}
