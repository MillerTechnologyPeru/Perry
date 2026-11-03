import CPerryFoundation
import FoundationEssentials
import FoundationInternationalization
import PerryObjCInterop
import _FoundationICU

// NSDateFormatter, NSISO8601DateFormatter and NSNumberFormatter over ICU's
// C API, as CoreFoundation's CFDateFormatter and CFNumberFormatter are on
// Darwin: a formatter keeps its settings and opens an ICU formatter from
// them when it next formats or parses.

typealias DateHandle = UnsafeMutablePointer<UDateFormat?>
typealias NumberHandle = UnsafeMutablePointer<UNumberFormat?>

/// NSFormatter, the abstract superclass.
@ObjCClass("NSFormatter")
public class NSFormatter: NSObject {
    @ObjCMethod("stringForObjectValue:") func formatterString(forObjectValue value: ObjCObject?) -> String? { nil }

    @ObjCMethod("editingStringForObjectValue:")
    func editingString(forObjectValue value: ObjCObject?) -> String? {
        guard let value else { return nil }
        typealias Send = @convention(c) (id, SEL, id) -> id?
        return Strings.value(of: unsafeBitCast(ObjC.msgSend, to: Send.self)(
            objcObject, ObjC.selector("stringForObjectValue:"), value.id))
    }

    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjC.retain(objcObject)! }
}

// MARK: - Dates

final class DateFormatterStorage {
    var locale: Locale?
    var timeZone: TimeZone?
    var calendar: Calendar?
    var dateStyle = 0
    var timeStyle = 0
    /// A format set with -setDateFormat:; otherwise the styles' pattern.
    var format: String?
    var lenient = false
    private var cached: (key: String, handle: DateHandle)?

    deinit {
        if let cached { swift_udat_close(cached.handle) }
    }

    func changed() {
        if let cached { swift_udat_close(cached.handle) }
        cached = nil
    }

    var effectiveLocale: Locale { locale ?? Locales.current }
    var effectiveTimeZone: TimeZone { timeZone ?? TimeZones.current }

    /// The locale ICU formats in, with the calendar as a keyword when it is
    /// not the locale's own.
    var localeID: String {
        let locale = effectiveLocale
        guard let calendar, calendar.identifier != locale.calendar.identifier else { return locale.identifier }
        return locale.identifier + "@calendar=" + CalendarIdentifiers.name(calendar.identifier)
    }

    /// NSDateFormatterStyle as ICU's style.
    static func icuStyle(_ style: Int) -> UDateFormatStyle {
        switch style {
        case 1: return UDAT_SHORT
        case 2: return UDAT_MEDIUM
        case 3: return UDAT_LONG
        case 4: return UDAT_FULL
        default: return UDAT_NONE
        }
    }

    static func open(time: UDateFormatStyle, date: UDateFormatStyle, locale: String, zone: String,
                     pattern: String?) -> DateHandle? {
        var status = U_ZERO_ERROR
        let handle = ICU.withUChars(zone) { zoneChars, zoneLength in
            if let pattern {
                return ICU.withUChars(pattern) { patternChars, patternLength in
                    swift_udat_open(time, date, locale, zoneChars, zoneLength, patternChars, patternLength, &status)
                }
            }
            return swift_udat_open(time, date, locale, zoneChars, zoneLength, nil, 0, &status)
        }
        return ICU.failed(status) ? nil : handle
    }

    /// The pattern: the format set, or the styles' pattern for the locale.
    var pattern: String {
        if let format { return format }
        guard dateStyle != 0 || timeStyle != 0,
              let handle = Self.open(time: Self.icuStyle(timeStyle), date: Self.icuStyle(dateStyle), locale: localeID,
                                     zone: effectiveTimeZone.identifier, pattern: nil) else { return "" }
        defer { swift_udat_close(handle) }
        return ICU.string { swift_udat_toPattern(handle, 0, $0, $1, $2) } ?? ""
    }

    var handle: DateHandle? {
        let pattern = self.pattern
        let key = "\(pattern)|\(localeID)|\(effectiveTimeZone.identifier)|\(lenient)"
        if let cached, cached.key == key { return cached.handle }
        changed()
        guard let handle = Self.open(time: UDAT_PATTERN, date: UDAT_PATTERN, locale: localeID,
                                     zone: effectiveTimeZone.identifier, pattern: pattern) else { return nil }
        swift_udat_setLenient(handle, lenient ? 1 : 0)
        cached = (key, handle)
        return handle
    }

    func string(from date: Date) -> String {
        guard !pattern.isEmpty, let handle else { return "" }
        let milliseconds = date.timeIntervalSince1970 * 1000
        return ICU.string { swift_udat_format(handle, milliseconds, $0, $1, nil, $2) } ?? ""
    }

    /// The date, when the whole string parses.
    func date(from string: String) -> Date? {
        guard let handle else { return nil }
        return ICU.withUChars(string) { chars, length in
            var position: Int32 = 0
            var status = U_ZERO_ERROR
            let milliseconds = swift_udat_parse(handle, chars, length, &position, &status)
            guard !ICU.failed(status), position == length else { return nil }
            return Date(timeIntervalSince1970: milliseconds / 1000)
        }
    }

    /// A symbol list; ICU's weekdays start at index 1.
    func symbols(_ type: UDateFormatSymbolType) -> [String] {
        guard let handle = Self.open(time: UDAT_DEFAULT, date: UDAT_DEFAULT, locale: localeID,
                                     zone: effectiveTimeZone.identifier, pattern: nil) else { return [] }
        defer { swift_udat_close(handle) }
        let count = swift_udat_countSymbols(handle, type)
        let first: Int32 = [UDAT_WEEKDAYS, UDAT_SHORT_WEEKDAYS, UDAT_NARROW_WEEKDAYS, UDAT_STANDALONE_WEEKDAYS,
                            UDAT_STANDALONE_SHORT_WEEKDAYS, UDAT_STANDALONE_NARROW_WEEKDAYS].contains(type) ? 1 : 0
        return (first..<count).compactMap { index in ICU.string { swift_udat_getSymbols(handle, type, index, $0, $1, $2) } }
    }

    /// The best pattern for a template (skeleton) in a locale.
    static func pattern(fromTemplate template: String, locale: String) -> String? {
        var status = U_ZERO_ERROR
        guard let generator = swift_udatpg_open(locale, &status), !ICU.failed(status) else { return nil }
        defer { swift_udatpg_close(generator) }
        return ICU.withUChars(template) { chars, length in
            ICU.string { swift_udatpg_getBestPattern(generator, chars, length, $0, $1, $2) }
        }
    }
}

enum DateFormatters {
    nonisolated(unsafe) static var formatterClass: Class!

    static func storage(_ object: id) -> DateFormatterStorage {
        if let storage = Storage.get(object, as: DateFormatterStorage.self) { return storage }
        let storage = DateFormatterStorage()
        Storage.set(object, storage)
        return storage
    }
}

/// NSDateFormatter.
@ObjCClass("NSDateFormatter")
public final class NSDateFormatter: NSFormatter {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        DateFormatters.formatterClass = cls.storage
    }

    var storage: DateFormatterStorage { DateFormatters.storage(objcObject) }

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = storage
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: DateFormatters.formatterClass)
    }

    @ObjCMethod("stringFromDate:") func string(from date: NSDate) -> String { storage.string(from: date.date) }

    @ObjCMethod("stringForObjectValue:")
    func dateString(forObjectValue value: ObjCObject?) -> String? {
        guard let value, ObjC.isKind(value.id, of: Dates.dateClass) else { return nil }
        return storage.string(from: Dates.date(value.id))
    }

    @ObjCMethod("dateFromString:")
    func date(from string: String) -> UnsafeMutableRawPointer? { storage.date(from: string).flatMap { Dates.autoreleased($0) } }

    @ObjCMethod("getObjectValue:forString:errorDescription:")
    func getObjectValue(_ value: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, for string: String,
                        errorDescription: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        guard let date = storage.date(from: string) else { return false }
        value?.pointee = Dates.autoreleased(date)
        return true
    }

    @ObjCMethod("dateFormat") func dateFormat() -> String { storage.pattern }

    @ObjCMethod("setDateFormat:")
    func setDateFormat(_ format: String?) {
        storage.format = format
        storage.changed()
    }

    @ObjCMethod("dateStyle") func dateStyle() -> UInt { UInt(storage.dateStyle) }

    /// Setting a style replaces the format, as on Darwin.
    @ObjCMethod("setDateStyle:")
    func setDateStyle(_ style: UInt) {
        storage.dateStyle = Int(style)
        storage.format = nil
        storage.changed()
    }

    @ObjCMethod("timeStyle") func timeStyle() -> UInt { UInt(storage.timeStyle) }

    @ObjCMethod("setTimeStyle:")
    func setTimeStyle(_ style: UInt) {
        storage.timeStyle = Int(style)
        storage.format = nil
        storage.changed()
    }

    @ObjCMethod("locale") func locale() -> UnsafeMutableRawPointer { Locales.autoreleased(storage.effectiveLocale) }

    @ObjCMethod("setLocale:")
    func setLocale(_ locale: ObjCObject?) {
        storage.locale = locale.map { Locales.locale($0.id) }
        storage.changed()
    }

    @ObjCMethod("timeZone") func timeZone() -> UnsafeMutableRawPointer { TimeZones.autoreleased(storage.effectiveTimeZone) }

    @ObjCMethod("setTimeZone:")
    func setTimeZone(_ zone: ObjCObject?) {
        storage.timeZone = TimeZones.zone(zone?.id)
        storage.changed()
    }

    @ObjCMethod("calendar")
    func calendar() -> UnsafeMutableRawPointer {
        var calendar = storage.calendar ?? Calendar(identifier: storage.effectiveLocale.calendar.identifier)
        calendar.locale = storage.effectiveLocale
        calendar.timeZone = storage.effectiveTimeZone
        return Calendars.autoreleased(calendar)
    }

    @ObjCMethod("setCalendar:")
    func setCalendar(_ calendar: ObjCObject?) {
        storage.calendar = Calendars.calendar(calendar?.id)
        storage.changed()
    }

    @ObjCMethod("isLenient") func isLenient() -> Bool { storage.lenient }

    @ObjCMethod("setLenient:")
    func setLenient(_ lenient: Bool) {
        storage.lenient = lenient
        storage.changed()
    }

    @ObjCMethod("setLocalizedDateFormatFromTemplate:")
    func setLocalizedDateFormat(fromTemplate template: String) {
        storage.format = DateFormatterStorage.pattern(fromTemplate: template, locale: storage.localeID)
        storage.changed()
    }

    @ObjCClassMethod("dateFormatFromTemplate:options:locale:")
    static func dateFormat(fromTemplate template: String, options: UInt, locale: ObjCObject?) -> String? {
        DateFormatterStorage.pattern(fromTemplate: template, locale: Locales.locale(locale?.id).identifier)
    }

    @ObjCClassMethod("localizedStringFromDate:dateStyle:timeStyle:")
    static func localizedString(from date: NSDate, dateStyle: UInt, timeStyle: UInt) -> String {
        let storage = DateFormatterStorage()
        storage.dateStyle = Int(dateStyle)
        storage.timeStyle = Int(timeStyle)
        return storage.string(from: date.date)
    }

    // MARK: Symbols

    private func symbols(_ type: UDateFormatSymbolType) -> ObjCObject { Locales.strings(storage.symbols(type)) }

    @ObjCMethod("eraSymbols") func eraSymbols() -> ObjCObject { symbols(UDAT_ERAS) }
    @ObjCMethod("longEraSymbols") func longEraSymbols() -> ObjCObject { symbols(UDAT_ERA_NAMES) }
    @ObjCMethod("monthSymbols") func monthSymbols() -> ObjCObject { symbols(UDAT_MONTHS) }
    @ObjCMethod("shortMonthSymbols") func shortMonthSymbols() -> ObjCObject { symbols(UDAT_SHORT_MONTHS) }
    @ObjCMethod("veryShortMonthSymbols") func veryShortMonthSymbols() -> ObjCObject { symbols(UDAT_NARROW_MONTHS) }
    @ObjCMethod("standaloneMonthSymbols") func standaloneMonthSymbols() -> ObjCObject { symbols(UDAT_STANDALONE_MONTHS) }
    @ObjCMethod("shortStandaloneMonthSymbols")
    func shortStandaloneMonthSymbols() -> ObjCObject { symbols(UDAT_STANDALONE_SHORT_MONTHS) }
    @ObjCMethod("weekdaySymbols") func weekdaySymbols() -> ObjCObject { symbols(UDAT_WEEKDAYS) }
    @ObjCMethod("shortWeekdaySymbols") func shortWeekdaySymbols() -> ObjCObject { symbols(UDAT_SHORT_WEEKDAYS) }
    @ObjCMethod("veryShortWeekdaySymbols") func veryShortWeekdaySymbols() -> ObjCObject { symbols(UDAT_NARROW_WEEKDAYS) }
    @ObjCMethod("standaloneWeekdaySymbols") func standaloneWeekdaySymbols() -> ObjCObject { symbols(UDAT_STANDALONE_WEEKDAYS) }
    @ObjCMethod("quarterSymbols") func quarterSymbols() -> ObjCObject { symbols(UDAT_QUARTERS) }
    @ObjCMethod("shortQuarterSymbols") func shortQuarterSymbols() -> ObjCObject { symbols(UDAT_SHORT_QUARTERS) }
    @ObjCMethod("AMSymbol") func amSymbol() -> String { storage.symbols(UDAT_AM_PMS).first ?? "AM" }
    @ObjCMethod("PMSymbol") func pmSymbol() -> String { storage.symbols(UDAT_AM_PMS).dropFirst().first ?? "PM" }
}

/// NSISO8601DateFormatter: a fixed pattern in en_US_POSIX's Gregorian
/// calendar, built from the format options.
final class ISO8601Storage {
    var options: UInt = 1907    // NSISO8601DateFormatWithInternetDateTime
    var timeZone: TimeZone = .gmt

    var pattern: String {
        func has(_ bit: UInt) -> Bool { options & bit != 0 }
        let year = has(1), month = has(2), week = has(4), day = has(16), time = has(32), zone = has(64)
        let space = has(128), dash = has(256), colon = has(512), zoneColon = has(1024), fraction = has(2048)
        var pattern = ""
        let separator = dash ? "-" : ""
        if year { pattern += week ? "YYYY" : "yyyy" }
        if month { pattern += (pattern.isEmpty ? "" : separator) + "MM" }
        if week { pattern += (pattern.isEmpty ? "" : separator) + "'W'ww" }
        if day {
            pattern += (pattern.isEmpty ? "" : separator) + (week ? "ee" : month ? "dd" : "DDD")
        }
        if time {
            if !pattern.isEmpty { pattern += space ? " " : "'T'" }
            pattern += colon ? "HH:mm:ss" : "HHmmss"
            if fraction { pattern += ".SSS" }
        }
        if zone { pattern += zoneColon ? "XXXXX" : "XXXX" }
        return pattern
    }

    var formatter: DateFormatterStorage {
        let formatter = DateFormatterStorage()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.format = pattern
        return formatter
    }
}

/// NSISO8601DateFormatter.
@ObjCClass("NSISO8601DateFormatter")
public final class NSISO8601DateFormatter: NSFormatter {
    nonisolated(unsafe) static var formatterClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        formatterClass = cls.storage
    }

    var storage: ISO8601Storage {
        if let storage = Storage.get(objcObject, as: ISO8601Storage.self) { return storage }
        let storage = ISO8601Storage()
        Storage.set(objcObject, storage)
        return storage
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = storage
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSISO8601DateFormatter.formatterClass)
    }

    @ObjCMethod("formatOptions") func formatOptions() -> UInt { storage.options }
    @ObjCMethod("setFormatOptions:") func setFormatOptions(_ options: UInt) { storage.options = options }
    @ObjCMethod("timeZone") func timeZone() -> UnsafeMutableRawPointer { TimeZones.autoreleased(storage.timeZone) }
    @ObjCMethod("setTimeZone:") func setTimeZone(_ zone: ObjCObject?) { storage.timeZone = TimeZones.zone(zone?.id) ?? .gmt }

    @ObjCMethod("stringFromDate:") func string(from date: NSDate) -> String { storage.formatter.string(from: date.date) }

    @ObjCMethod("stringForObjectValue:")
    func isoString(forObjectValue value: ObjCObject?) -> String? {
        guard let value, ObjC.isKind(value.id, of: Dates.dateClass) else { return nil }
        return storage.formatter.string(from: Dates.date(value.id))
    }

    @ObjCMethod("dateFromString:")
    func date(from string: String) -> UnsafeMutableRawPointer? {
        storage.formatter.date(from: string).flatMap { Dates.autoreleased($0) }
    }

    @ObjCClassMethod("stringFromDate:timeZone:formatOptions:")
    static func string(from date: NSDate, timeZone: ObjCObject?, formatOptions: UInt) -> String {
        let storage = ISO8601Storage()
        storage.options = formatOptions
        storage.timeZone = TimeZones.zone(timeZone?.id) ?? .gmt
        return storage.formatter.string(from: date.date)
    }
}

// MARK: - Numbers

final class NumberFormatterStorage {
    var style = 0
    var locale: Locale?
    var lenient = false
    var pattern: String?
    var attributes: [UInt32: Int32] = [:]
    var doubleAttributes: [UInt32: Double] = [:]
    var textAttributes: [UInt32: String] = [:]
    var symbols: [UInt32: String] = [:]
    private var cached: NumberHandle?

    deinit {
        if let cached { swift_unum_close(cached) }
    }

    func changed() {
        if let cached { swift_unum_close(cached) }
        cached = nil
    }

    /// A new style starts from the style's defaults.
    func setStyle(_ style: Int) {
        self.style = style
        pattern = nil
        attributes = [:]
        doubleAttributes = [:]
        textAttributes = textAttributes.filter { $0.key == UNUM_CURRENCY_CODE.rawValue }
        symbols = [:]
        changed()
    }

    /// NSNumberFormatterStyle as ICU's style.
    var icuStyle: UNumberFormatStyle {
        switch style {
        case 1: return UNUM_DECIMAL
        case 2: return UNUM_CURRENCY
        case 3: return UNUM_PERCENT
        case 4: return UNUM_SCIENTIFIC
        case 5: return UNUM_SPELLOUT
        case 6: return UNUM_ORDINAL
        case 8: return UNUM_CURRENCY_ISO
        case 9: return UNUM_CURRENCY_PLURAL
        case 10: return UNUM_CURRENCY_ACCOUNTING
        default: return UNUM_DECIMAL
        }
    }

    var handle: NumberHandle? {
        if let cached { return cached }
        var status = U_ZERO_ERROR
        guard let handle = swift_unum_open(icuStyle, nil, 0, (locale ?? Locales.current).identifier, nil, &status),
              !ICU.failed(status) else { return nil }
        if style == 0 {
            // NSNumberFormatterNoStyle: whole numbers without grouping.
            swift_unum_setAttribute(handle, UNUM_MAX_FRACTION_DIGITS, 0)
            swift_unum_setAttribute(handle, UNUM_GROUPING_USED, 0)
        }
        if let pattern {
            ICU.withUChars(pattern) { chars, length in
                var status = U_ZERO_ERROR
                swift_unum_applyPattern(handle, 0, chars, length, nil, &status)
            }
        }
        for (tag, value) in textAttributes.sorted(by: { $0.key < $1.key }) {
            ICU.withUChars(value) { chars, length in
                var status = U_ZERO_ERROR
                swift_unum_setTextAttribute(handle, UNumberFormatTextAttribute(rawValue: tag), chars, length, &status)
            }
        }
        for (attribute, value) in attributes.sorted(by: { $0.key < $1.key }) {
            swift_unum_setAttribute(handle, UNumberFormatAttribute(rawValue: attribute), value)
        }
        for (attribute, value) in doubleAttributes {
            swift_unum_setDoubleAttribute(handle, UNumberFormatAttribute(rawValue: attribute), value)
        }
        for (symbol, value) in symbols {
            ICU.withUChars(value) { chars, length in
                var status = U_ZERO_ERROR
                swift_unum_setSymbol(handle, UNumberFormatSymbol(rawValue: symbol), chars, length, &status)
            }
        }
        swift_unum_setAttribute(handle, UNUM_LENIENT_PARSE, lenient ? 1 : 0)
        cached = handle
        return handle
    }

    func attribute(_ attribute: UNumberFormatAttribute) -> Int {
        handle.map { Int(swift_unum_getAttribute($0, attribute)) } ?? 0
    }

    func setAttribute(_ attribute: UNumberFormatAttribute, _ value: Int) {
        attributes[attribute.rawValue] = Int32(clamping: value)
        changed()
    }

    func text(_ tag: UNumberFormatTextAttribute) -> String {
        guard let handle else { return "" }
        return ICU.string { swift_unum_getTextAttribute(handle, tag, $0, $1, $2) } ?? ""
    }

    func setText(_ tag: UNumberFormatTextAttribute, _ value: String?) {
        textAttributes[tag.rawValue] = value
        changed()
    }

    func symbol(_ symbol: UNumberFormatSymbol) -> String {
        guard let handle else { return "" }
        return ICU.string { swift_unum_getSymbol(handle, symbol, $0, $1, $2) } ?? ""
    }

    func setSymbol(_ symbol: UNumberFormatSymbol, _ value: String?) {
        symbols[symbol.rawValue] = value
        changed()
    }

    func string(from number: id) -> String? {
        guard let handle else { return nil }
        let value = Numbers.storage(number)
        if case .double(let double) = value.value {
            return ICU.string { swift_unum_formatDouble(handle, double, $0, $1, nil, $2) }
        }
        let integer = value.int64
        return ICU.string { swift_unum_formatInt64(handle, integer, $0, $1, nil, $2) }
    }

    /// The number, when the whole string parses: whole numbers as integers.
    func number(from string: String) -> id? {
        guard let handle else { return nil }
        return ICU.withUChars(string) { chars, length -> id? in
            var position: Int32 = 0
            var status = U_ZERO_ERROR
            let value = swift_unum_parseDouble(handle, chars, length, &position, &status)
            guard !ICU.failed(status), position == length else { return nil }
            if value == value.rounded(), abs(value) < 9e15 { return Numbers.make(nil, .signed(Int64(value))) }
            return Numbers.make(nil, .double(value))
        }
    }

    var positiveFormat: String {
        guard let handle else { return "" }
        let pattern = ICU.string { swift_unum_toPattern(handle, 0, $0, $1, $2) } ?? ""
        return String(pattern.split(separator: ";", maxSplits: 1).first ?? "")
    }

    var negativeFormat: String {
        guard let handle else { return "" }
        let pattern = ICU.string { swift_unum_toPattern(handle, 0, $0, $1, $2) } ?? ""
        let parts = pattern.split(separator: ";", maxSplits: 1)
        return parts.count > 1 ? String(parts[1]) : "-" + (parts.first.map(String.init) ?? "")
    }
}

enum NumberFormatters {
    nonisolated(unsafe) static var formatterClass: Class!

    static func storage(_ object: id) -> NumberFormatterStorage {
        if let storage = Storage.get(object, as: NumberFormatterStorage.self) { return storage }
        let storage = NumberFormatterStorage()
        Storage.set(object, storage)
        return storage
    }
}

/// NSNumberFormatter.
@ObjCClass("NSNumberFormatter")
public final class NSNumberFormatter: NSFormatter {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        NumberFormatters.formatterClass = cls.storage
    }

    var storage: NumberFormatterStorage { NumberFormatters.storage(objcObject) }

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = storage
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NumberFormatters.formatterClass)
    }

    @ObjCMethod("stringFromNumber:") func string(from number: ObjCObject) -> String? { storage.string(from: number.id) }

    @ObjCMethod("stringForObjectValue:")
    func numberString(forObjectValue value: ObjCObject?) -> String? { value.flatMap { storage.string(from: $0.id) } }

    @ObjCMethod("numberFromString:")
    func number(from string: String) -> UnsafeMutableRawPointer? { storage.number(from: string) }

    @ObjCMethod("getObjectValue:forString:errorDescription:")
    func getObjectValue(_ value: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, for string: String,
                        errorDescription: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        guard let number = storage.number(from: string) else { return false }
        value?.pointee = number
        return true
    }

    @ObjCClassMethod("localizedStringFromNumber:numberStyle:")
    static func localizedString(from number: ObjCObject, numberStyle style: UInt) -> String {
        let storage = NumberFormatterStorage()
        storage.setStyle(Int(style))
        return storage.string(from: number.id) ?? ""
    }

    @ObjCMethod("numberStyle") func numberStyle() -> UInt { UInt(storage.style) }
    @ObjCMethod("setNumberStyle:") func setNumberStyle(_ style: UInt) { storage.setStyle(Int(style)) }

    @ObjCMethod("locale") func locale() -> UnsafeMutableRawPointer { Locales.autoreleased(storage.locale ?? Locales.current) }

    @ObjCMethod("setLocale:")
    func setLocale(_ locale: ObjCObject?) {
        storage.locale = locale.map { Locales.locale($0.id) }
        storage.changed()
    }

    @ObjCMethod("isLenient") func isLenient() -> Bool { storage.lenient }

    @ObjCMethod("setLenient:")
    func setLenient(_ lenient: Bool) {
        storage.lenient = lenient
        storage.changed()
    }

    // MARK: Digits and rounding

    @ObjCMethod("minimumIntegerDigits") func minimumIntegerDigits() -> UInt { UInt(storage.attribute(UNUM_MIN_INTEGER_DIGITS)) }
    @ObjCMethod("setMinimumIntegerDigits:")
    func setMinimumIntegerDigits(_ value: UInt) { storage.setAttribute(UNUM_MIN_INTEGER_DIGITS, Int(value)) }
    @ObjCMethod("maximumIntegerDigits") func maximumIntegerDigits() -> UInt { UInt(storage.attribute(UNUM_MAX_INTEGER_DIGITS)) }
    @ObjCMethod("setMaximumIntegerDigits:")
    func setMaximumIntegerDigits(_ value: UInt) { storage.setAttribute(UNUM_MAX_INTEGER_DIGITS, Int(value)) }
    @ObjCMethod("minimumFractionDigits") func minimumFractionDigits() -> UInt { UInt(storage.attribute(UNUM_MIN_FRACTION_DIGITS)) }
    @ObjCMethod("setMinimumFractionDigits:")
    func setMinimumFractionDigits(_ value: UInt) { storage.setAttribute(UNUM_MIN_FRACTION_DIGITS, Int(value)) }
    @ObjCMethod("maximumFractionDigits") func maximumFractionDigits() -> UInt { UInt(storage.attribute(UNUM_MAX_FRACTION_DIGITS)) }
    @ObjCMethod("setMaximumFractionDigits:")
    func setMaximumFractionDigits(_ value: UInt) { storage.setAttribute(UNUM_MAX_FRACTION_DIGITS, Int(value)) }

    @ObjCMethod("usesSignificantDigits")
    func usesSignificantDigits() -> Bool { storage.attribute(UNUM_SIGNIFICANT_DIGITS_USED) != 0 }
    @ObjCMethod("setUsesSignificantDigits:")
    func setUsesSignificantDigits(_ value: Bool) { storage.setAttribute(UNUM_SIGNIFICANT_DIGITS_USED, value ? 1 : 0) }
    @ObjCMethod("minimumSignificantDigits")
    func minimumSignificantDigits() -> UInt { UInt(storage.attribute(UNUM_MIN_SIGNIFICANT_DIGITS)) }
    @ObjCMethod("setMinimumSignificantDigits:")
    func setMinimumSignificantDigits(_ value: UInt) {
        storage.setAttribute(UNUM_SIGNIFICANT_DIGITS_USED, 1)
        storage.setAttribute(UNUM_MIN_SIGNIFICANT_DIGITS, Int(value))
    }
    @ObjCMethod("maximumSignificantDigits")
    func maximumSignificantDigits() -> UInt { UInt(storage.attribute(UNUM_MAX_SIGNIFICANT_DIGITS)) }
    @ObjCMethod("setMaximumSignificantDigits:")
    func setMaximumSignificantDigits(_ value: UInt) {
        storage.setAttribute(UNUM_SIGNIFICANT_DIGITS_USED, 1)
        storage.setAttribute(UNUM_MAX_SIGNIFICANT_DIGITS, Int(value))
    }

    /// NSNumberFormatterRoundingMode has ICU's values.
    @ObjCMethod("roundingMode") func roundingMode() -> UInt { UInt(storage.attribute(UNUM_ROUNDING_MODE)) }
    @ObjCMethod("setRoundingMode:") func setRoundingMode(_ mode: UInt) { storage.setAttribute(UNUM_ROUNDING_MODE, Int(mode)) }

    @ObjCMethod("roundingIncrement")
    func roundingIncrement() -> UnsafeMutableRawPointer? {
        let increment = storage.handle.map { swift_unum_getDoubleAttribute($0, UNUM_ROUNDING_INCREMENT) } ?? 0
        return Numbers.make(nil, .double(max(increment, 0)))
    }

    @ObjCMethod("setRoundingIncrement:")
    func setRoundingIncrement(_ increment: ObjCObject?) {
        storage.doubleAttributes[UNUM_ROUNDING_INCREMENT.rawValue] = increment.map { Numbers.storage($0.id).double } ?? 0
        storage.changed()
    }

    @ObjCMethod("multiplier")
    func multiplier() -> UnsafeMutableRawPointer? { Numbers.make(nil, .signed(Int64(storage.attribute(UNUM_MULTIPLIER)))) }

    @ObjCMethod("setMultiplier:")
    func setMultiplier(_ multiplier: ObjCObject?) {
        storage.setAttribute(UNUM_MULTIPLIER, multiplier.map { Int(Numbers.storage($0.id).int64) } ?? 1)
    }

    // MARK: Grouping and padding

    @ObjCMethod("alwaysShowsDecimalSeparator")
    func alwaysShowsDecimalSeparator() -> Bool { storage.attribute(UNUM_DECIMAL_ALWAYS_SHOWN) != 0 }
    @ObjCMethod("setAlwaysShowsDecimalSeparator:")
    func setAlwaysShowsDecimalSeparator(_ value: Bool) { storage.setAttribute(UNUM_DECIMAL_ALWAYS_SHOWN, value ? 1 : 0) }
    @ObjCMethod("usesGroupingSeparator") func usesGroupingSeparator() -> Bool { storage.attribute(UNUM_GROUPING_USED) != 0 }
    @ObjCMethod("setUsesGroupingSeparator:")
    func setUsesGroupingSeparator(_ value: Bool) { storage.setAttribute(UNUM_GROUPING_USED, value ? 1 : 0) }
    @ObjCMethod("groupingSize") func groupingSize() -> UInt { UInt(storage.attribute(UNUM_GROUPING_SIZE)) }
    @ObjCMethod("setGroupingSize:") func setGroupingSize(_ value: UInt) { storage.setAttribute(UNUM_GROUPING_SIZE, Int(value)) }
    @ObjCMethod("secondaryGroupingSize")
    func secondaryGroupingSize() -> UInt { UInt(storage.attribute(UNUM_SECONDARY_GROUPING_SIZE)) }
    @ObjCMethod("setSecondaryGroupingSize:")
    func setSecondaryGroupingSize(_ value: UInt) { storage.setAttribute(UNUM_SECONDARY_GROUPING_SIZE, Int(value)) }
    @ObjCMethod("formatWidth") func formatWidth() -> UInt { UInt(storage.attribute(UNUM_FORMAT_WIDTH)) }
    @ObjCMethod("setFormatWidth:") func setFormatWidth(_ value: UInt) { storage.setAttribute(UNUM_FORMAT_WIDTH, Int(value)) }
    @ObjCMethod("paddingCharacter") func paddingCharacter() -> String { storage.text(UNUM_PADDING_CHARACTER) }
    @ObjCMethod("setPaddingCharacter:")
    func setPaddingCharacter(_ value: String?) { storage.setText(UNUM_PADDING_CHARACTER, value) }
    @ObjCMethod("paddingPosition") func paddingPosition() -> UInt { UInt(storage.attribute(UNUM_PADDING_POSITION)) }
    @ObjCMethod("setPaddingPosition:")
    func setPaddingPosition(_ value: UInt) { storage.setAttribute(UNUM_PADDING_POSITION, Int(value)) }

    // MARK: Patterns, affixes and symbols

    @ObjCMethod("positiveFormat") func positiveFormat() -> String { storage.positiveFormat }
    @ObjCMethod("negativeFormat") func negativeFormat() -> String { storage.negativeFormat }

    @ObjCMethod("setPositiveFormat:")
    func setPositiveFormat(_ format: String?) {
        storage.pattern = format
        storage.changed()
    }

    @ObjCMethod("setNegativeFormat:")
    func setNegativeFormat(_ format: String?) {
        guard let format else { return }
        storage.pattern = storage.positiveFormat + ";" + format
        storage.changed()
    }

    @ObjCMethod("positivePrefix") func positivePrefix() -> String { storage.text(UNUM_POSITIVE_PREFIX) }
    @ObjCMethod("setPositivePrefix:") func setPositivePrefix(_ value: String?) { storage.setText(UNUM_POSITIVE_PREFIX, value) }
    @ObjCMethod("positiveSuffix") func positiveSuffix() -> String { storage.text(UNUM_POSITIVE_SUFFIX) }
    @ObjCMethod("setPositiveSuffix:") func setPositiveSuffix(_ value: String?) { storage.setText(UNUM_POSITIVE_SUFFIX, value) }
    @ObjCMethod("negativePrefix") func negativePrefix() -> String { storage.text(UNUM_NEGATIVE_PREFIX) }
    @ObjCMethod("setNegativePrefix:") func setNegativePrefix(_ value: String?) { storage.setText(UNUM_NEGATIVE_PREFIX, value) }
    @ObjCMethod("negativeSuffix") func negativeSuffix() -> String { storage.text(UNUM_NEGATIVE_SUFFIX) }
    @ObjCMethod("setNegativeSuffix:") func setNegativeSuffix(_ value: String?) { storage.setText(UNUM_NEGATIVE_SUFFIX, value) }

    @ObjCMethod("currencyCode") func currencyCode() -> String { storage.text(UNUM_CURRENCY_CODE) }
    @ObjCMethod("setCurrencyCode:") func setCurrencyCode(_ value: String?) { storage.setText(UNUM_CURRENCY_CODE, value) }

    @ObjCMethod("decimalSeparator") func decimalSeparator() -> String { storage.symbol(UNUM_DECIMAL_SEPARATOR_SYMBOL) }
    @ObjCMethod("setDecimalSeparator:")
    func setDecimalSeparator(_ value: String?) { storage.setSymbol(UNUM_DECIMAL_SEPARATOR_SYMBOL, value) }
    @ObjCMethod("groupingSeparator") func groupingSeparator() -> String { storage.symbol(UNUM_GROUPING_SEPARATOR_SYMBOL) }
    @ObjCMethod("setGroupingSeparator:")
    func setGroupingSeparator(_ value: String?) { storage.setSymbol(UNUM_GROUPING_SEPARATOR_SYMBOL, value) }
    @ObjCMethod("currencySymbol") func currencySymbol() -> String { storage.symbol(UNUM_CURRENCY_SYMBOL) }
    @ObjCMethod("setCurrencySymbol:")
    func setCurrencySymbol(_ value: String?) { storage.setSymbol(UNUM_CURRENCY_SYMBOL, value) }
    @ObjCMethod("internationalCurrencySymbol")
    func internationalCurrencySymbol() -> String { storage.symbol(UNUM_INTL_CURRENCY_SYMBOL) }
    @ObjCMethod("percentSymbol") func percentSymbol() -> String { storage.symbol(UNUM_PERCENT_SYMBOL) }
    @ObjCMethod("setPercentSymbol:") func setPercentSymbol(_ value: String?) { storage.setSymbol(UNUM_PERCENT_SYMBOL, value) }
    @ObjCMethod("minusSign") func minusSign() -> String { storage.symbol(UNUM_MINUS_SIGN_SYMBOL) }
    @ObjCMethod("setMinusSign:") func setMinusSign(_ value: String?) { storage.setSymbol(UNUM_MINUS_SIGN_SYMBOL, value) }
    @ObjCMethod("plusSign") func plusSign() -> String { storage.symbol(UNUM_PLUS_SIGN_SYMBOL) }
    @ObjCMethod("setPlusSign:") func setPlusSign(_ value: String?) { storage.setSymbol(UNUM_PLUS_SIGN_SYMBOL, value) }
    @ObjCMethod("exponentSymbol") func exponentSymbol() -> String { storage.symbol(UNUM_EXPONENTIAL_SYMBOL) }
    @ObjCMethod("perMillSymbol") func perMillSymbol() -> String { storage.symbol(UNUM_PERMILL_SYMBOL) }
    @ObjCMethod("zeroSymbol") func zeroSymbol() -> String? { nil }
    @ObjCMethod("notANumberSymbol") func notANumberSymbol() -> String { storage.symbol(UNUM_NAN_SYMBOL) }
    @ObjCMethod("positiveInfinitySymbol") func positiveInfinitySymbol() -> String { storage.symbol(UNUM_INFINITY_SYMBOL) }
    @ObjCMethod("currencyDecimalSeparator")
    func currencyDecimalSeparator() -> String { storage.symbol(UNUM_MONETARY_SEPARATOR_SYMBOL) }
    @ObjCMethod("currencyGroupingSeparator")
    func currencyGroupingSeparator() -> String { storage.symbol(UNUM_MONETARY_GROUPING_SEPARATOR_SYMBOL) }
}
