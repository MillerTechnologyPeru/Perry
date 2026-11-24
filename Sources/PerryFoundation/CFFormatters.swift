import CPerryFoundation
import FoundationEssentials
import FoundationInternationalization
import PerryObjCInterop
import _FoundationICU

// CFNumberFormatter and CFDateFormatter: the toll-free bridged
// NSNumberFormatter and NSDateFormatter, whose storage these functions read
// and set. Unlike the Objective-C classes, CoreFoundation parses as much of
// a string as it can, and says how much in the range given.

/// Objects a formatter keeps alive for as long as it lives: what its Get
/// functions return, and properties it only keeps.
final class HeldObjects {
    private var objects: [String: id] = [:]

    deinit {
        for object in objects.values { ObjC.release(object) }
    }

    /// Keeps `object` under `key`, releasing what was there; returns it.
    @discardableResult
    func hold(_ key: String, _ object: id?) -> id? {
        let old = objects[key]
        objects[key] = object.flatMap { ObjC.retain($0) }
        if let old { ObjC.release(old) }
        return objects[key]
    }

    subscript(key: String) -> id? { objects[key] }
}

enum CFFormatting {
    /// The string's text in `range`, in UTF-16 units, or all of it.
    static func text(_ string: id?, in range: UnsafeMutablePointer<CFRange>?) -> String? {
        guard let value = Strings.value(of: string) else { return nil }
        guard let range else { return value }
        let units = Array(value.utf16)
        let start = max(0, min(range.pointee.location, units.count))
        let end = max(start, min(start + range.pointee.length, units.count))
        return String(decoding: units[start..<end], as: UTF16.self)
    }

    /// A CFNumber of a value: whole numbers as SInt64, unless `integer` is
    /// false, and the rest as Float64. Retained.
    static func number(_ value: Double, integer: Bool = true) -> id? {
        if integer, value == value.rounded(), abs(value) < 9.2e18 {
            var integer = Int64(value)
            return CFNumberCreate(nil, CFNumberTypes.sint64, &integer)
        }
        var real = value
        return CFNumberCreate(nil, CFNumberTypes.float64, &real)
    }

    static func boolean(_ value: Bool) -> id? { ObjC.retain(Numbers.make(nil, .bool(value))) }

    static func strings(_ values: [String]) -> id? { ObjC.retain(Arrays.autoreleased(values.map { Strings.autoreleased($0) })) }
}

// MARK: - Numbers

extension NumberFormatterStorage {
    /// The pattern, positive and negative.
    var fullPattern: String {
        guard let handle else { return "" }
        return ICU.string { swift_unum_toPattern(handle, 0, $0, $1, $2) } ?? ""
    }

    /// The number at the start of `text`, and how many UTF-16 units it
    /// takes.
    func parse(_ text: String, integersOnly: Bool) -> (value: Double, length: Int)? {
        guard let handle else { return nil }
        if integersOnly { swift_unum_setAttribute(handle, UNUM_PARSE_INT_ONLY, 1) }
        defer { if integersOnly { swift_unum_setAttribute(handle, UNUM_PARSE_INT_ONLY, 0) } }
        return ICU.withUChars(text) { chars, length in
            var position: Int32 = 0
            var status = U_ZERO_ERROR
            let value = swift_unum_parseDouble(handle, chars, length, &position, &status)
            guard !ICU.failed(status), position > 0 else { return nil }
            if !allowsFloats, value != value.rounded() { return nil }
            return (value, Int(position))
        }
    }
}

/// What a CFNumberFormatter property is in ICU's terms.
enum NumberFormatterProperty {
    case symbol(UNumberFormatSymbol)
    case text(UNumberFormatTextAttribute)
    case integer(UNumberFormatAttribute)
    case flag(UNumberFormatAttribute)
    case roundingIncrement, zeroSymbol, lenient, defaultFormat

    /// By the key's value, as CoreFoundation names them.
    nonisolated(unsafe) static let byKey: [String: NumberFormatterProperty] = [
        "kCFNumberFormatterCurrencyCodeKey": .text(UNUM_CURRENCY_CODE),
        "kCFNumberFormatterDecimalSeparatorKey": .symbol(UNUM_DECIMAL_SEPARATOR_SYMBOL),
        "kCFNumberFormatterCurrencyDecimalSeparatorKey": .symbol(UNUM_MONETARY_SEPARATOR_SYMBOL),
        "kCFNumberFormatterAlwaysShowDecimalSeparatorKey": .flag(UNUM_DECIMAL_ALWAYS_SHOWN),
        "kCFNumberFormatterGroupingSeparatorKey": .symbol(UNUM_GROUPING_SEPARATOR_SYMBOL),
        "kCFNumberFormatterUseGroupingSeparatorKey": .flag(UNUM_GROUPING_USED),
        "kCFNumberFormatterPercentSymbolKey": .symbol(UNUM_PERCENT_SYMBOL),
        "kCFNumberFormatterZeroSymbolKey": .zeroSymbol,
        "kCFNumberFormatterNaNSymbolKey": .symbol(UNUM_NAN_SYMBOL),
        "kCFNumberFormatterInfinitySymbolKey": .symbol(UNUM_INFINITY_SYMBOL),
        "kCFNumberFormatterMinusSignKey": .symbol(UNUM_MINUS_SIGN_SYMBOL),
        "kCFNumberFormatterPlusSignKey": .symbol(UNUM_PLUS_SIGN_SYMBOL),
        "kCFNumberFormatterCurrencySymbolKey": .symbol(UNUM_CURRENCY_SYMBOL),
        "kCFNumberFormatterExponentSymbolKey": .symbol(UNUM_EXPONENTIAL_SYMBOL),
        "kCFNumberFormatterMinIntegerDigitsKey": .integer(UNUM_MIN_INTEGER_DIGITS),
        "kCFNumberFormatterMaxIntegerDigitsKey": .integer(UNUM_MAX_INTEGER_DIGITS),
        "kCFNumberFormatterMinFractionDigitsKey": .integer(UNUM_MIN_FRACTION_DIGITS),
        "kCFNumberFormatterMaxFractionDigitsKey": .integer(UNUM_MAX_FRACTION_DIGITS),
        "kCFNumberFormatterGroupingSizeKey": .integer(UNUM_GROUPING_SIZE),
        "kCFNumberFormatterSecondaryGroupingSizeKey": .integer(UNUM_SECONDARY_GROUPING_SIZE),
        "kCFNumberFormatterRoundingModeKey": .integer(UNUM_ROUNDING_MODE),
        "kCFNumberFormatterRoundingIncrementKey": .roundingIncrement,
        "kCFNumberFormatterFormatWidthKey": .integer(UNUM_FORMAT_WIDTH),
        "kCFNumberFormatterPaddingPositionKey": .integer(UNUM_PADDING_POSITION),
        "kCFNumberFormatterPaddingCharacterKey": .text(UNUM_PADDING_CHARACTER),
        "kCFNumberFormatterDefaultFormatKey": .defaultFormat,
        "kCFNumberFormatterMultiplierKey": .integer(UNUM_MULTIPLIER),
        "kCFNumberFormatterPositivePrefixKey": .text(UNUM_POSITIVE_PREFIX),
        "kCFNumberFormatterPositiveSuffixKey": .text(UNUM_POSITIVE_SUFFIX),
        "kCFNumberFormatterNegativePrefixKey": .text(UNUM_NEGATIVE_PREFIX),
        "kCFNumberFormatterNegativeSuffixKey": .text(UNUM_NEGATIVE_SUFFIX),
        "kCFNumberFormatterPerMillSymbolKey": .symbol(UNUM_PERMILL_SYMBOL),
        "kCFNumberFormatterInternationalCurrencySymbolKey": .symbol(UNUM_INTL_CURRENCY_SYMBOL),
        "kCFNumberFormatterCurrencyGroupingSeparatorKey": .symbol(UNUM_MONETARY_GROUPING_SEPARATOR_SYMBOL),
        "kCFNumberFormatterIsLenientKey": .lenient,
        "kCFNumberFormatterUseSignificantDigitsKey": .flag(UNUM_SIGNIFICANT_DIGITS_USED),
        "kCFNumberFormatterMinSignificantDigitsKey": .integer(UNUM_MIN_SIGNIFICANT_DIGITS),
        "kCFNumberFormatterMaxSignificantDigitsKey": .integer(UNUM_MAX_SIGNIFICANT_DIGITS),
        "kCFNumberFormatterMinGroupingDigitsKey": .integer(UNUM_MINIMUM_GROUPING_DIGITS),
    ]
}

/// CFNumberFormatter's property keys.
@ObjCConstants
enum NumberFormatterKeys {
    static let kCFNumberFormatterCurrencyCode = "kCFNumberFormatterCurrencyCodeKey"
    static let kCFNumberFormatterDecimalSeparator = "kCFNumberFormatterDecimalSeparatorKey"
    static let kCFNumberFormatterCurrencyDecimalSeparator = "kCFNumberFormatterCurrencyDecimalSeparatorKey"
    static let kCFNumberFormatterAlwaysShowDecimalSeparator = "kCFNumberFormatterAlwaysShowDecimalSeparatorKey"
    static let kCFNumberFormatterGroupingSeparator = "kCFNumberFormatterGroupingSeparatorKey"
    static let kCFNumberFormatterUseGroupingSeparator = "kCFNumberFormatterUseGroupingSeparatorKey"
    static let kCFNumberFormatterPercentSymbol = "kCFNumberFormatterPercentSymbolKey"
    static let kCFNumberFormatterZeroSymbol = "kCFNumberFormatterZeroSymbolKey"
    static let kCFNumberFormatterNaNSymbol = "kCFNumberFormatterNaNSymbolKey"
    static let kCFNumberFormatterInfinitySymbol = "kCFNumberFormatterInfinitySymbolKey"
    static let kCFNumberFormatterMinusSign = "kCFNumberFormatterMinusSignKey"
    static let kCFNumberFormatterPlusSign = "kCFNumberFormatterPlusSignKey"
    static let kCFNumberFormatterCurrencySymbol = "kCFNumberFormatterCurrencySymbolKey"
    static let kCFNumberFormatterExponentSymbol = "kCFNumberFormatterExponentSymbolKey"
    static let kCFNumberFormatterMinIntegerDigits = "kCFNumberFormatterMinIntegerDigitsKey"
    static let kCFNumberFormatterMaxIntegerDigits = "kCFNumberFormatterMaxIntegerDigitsKey"
    static let kCFNumberFormatterMinFractionDigits = "kCFNumberFormatterMinFractionDigitsKey"
    static let kCFNumberFormatterMaxFractionDigits = "kCFNumberFormatterMaxFractionDigitsKey"
    static let kCFNumberFormatterGroupingSize = "kCFNumberFormatterGroupingSizeKey"
    static let kCFNumberFormatterSecondaryGroupingSize = "kCFNumberFormatterSecondaryGroupingSizeKey"
    static let kCFNumberFormatterRoundingMode = "kCFNumberFormatterRoundingModeKey"
    static let kCFNumberFormatterRoundingIncrement = "kCFNumberFormatterRoundingIncrementKey"
    static let kCFNumberFormatterFormatWidth = "kCFNumberFormatterFormatWidthKey"
    static let kCFNumberFormatterPaddingPosition = "kCFNumberFormatterPaddingPositionKey"
    static let kCFNumberFormatterPaddingCharacter = "kCFNumberFormatterPaddingCharacterKey"
    static let kCFNumberFormatterDefaultFormat = "kCFNumberFormatterDefaultFormatKey"
    static let kCFNumberFormatterMultiplier = "kCFNumberFormatterMultiplierKey"
    static let kCFNumberFormatterPositivePrefix = "kCFNumberFormatterPositivePrefixKey"
    static let kCFNumberFormatterPositiveSuffix = "kCFNumberFormatterPositiveSuffixKey"
    static let kCFNumberFormatterNegativePrefix = "kCFNumberFormatterNegativePrefixKey"
    static let kCFNumberFormatterNegativeSuffix = "kCFNumberFormatterNegativeSuffixKey"
    static let kCFNumberFormatterPerMillSymbol = "kCFNumberFormatterPerMillSymbolKey"
    static let kCFNumberFormatterInternationalCurrencySymbol = "kCFNumberFormatterInternationalCurrencySymbolKey"
    static let kCFNumberFormatterCurrencyGroupingSeparator = "kCFNumberFormatterCurrencyGroupingSeparatorKey"
    static let kCFNumberFormatterIsLenient = "kCFNumberFormatterIsLenientKey"
    static let kCFNumberFormatterUseSignificantDigits = "kCFNumberFormatterUseSignificantDigitsKey"
    static let kCFNumberFormatterMinSignificantDigits = "kCFNumberFormatterMinSignificantDigitsKey"
    static let kCFNumberFormatterMaxSignificantDigits = "kCFNumberFormatterMaxSignificantDigitsKey"
    static let kCFNumberFormatterMinGroupingDigits = "kCFNumberFormatterMinGroupingDigitsKey"
}

@c(_CFNumberFormatterGetTypeID) public func CFNumberFormatterGetTypeID() -> UInt { CFTypeIDs.numberFormatter }

/// An NSNumberFormatter, whose styles are CFNumberFormatterStyle's numbers,
/// in the locale given.
@c(_CFNumberFormatterCreate)
public func CFNumberFormatterCreate(_ allocator: UnsafeRawPointer?, _ locale: id?, _ style: Int) -> id? {
    guard let object = Storage.allocate(UnsafeMutableRawPointer(NumberFormatters.formatterClass)) else { return nil }
    let storage = NumberFormatters.storage(object)
    storage.locale = locale.map { Locales.locale($0) }
    storage.setStyle(style)
    return object
}

@c(_CFNumberFormatterGetLocale)
public func CFNumberFormatterGetLocale(_ formatter: id?) -> id? {
    guard let formatter else { return nil }
    let storage = NumberFormatters.storage(formatter)
    return storage.held.hold("locale", Locales.autoreleased(storage.locale ?? Locales.current))
}

@c(_CFNumberFormatterGetStyle)
public func CFNumberFormatterGetStyle(_ formatter: id?) -> Int { formatter.map { NumberFormatters.storage($0).style } ?? 0 }

@c(_CFNumberFormatterGetFormat)
public func CFNumberFormatterGetFormat(_ formatter: id?) -> id? {
    guard let formatter else { return nil }
    let storage = NumberFormatters.storage(formatter)
    return storage.held.hold("format", Strings.autoreleased(storage.fullPattern))
}

@c(_CFNumberFormatterSetFormat)
public func CFNumberFormatterSetFormat(_ formatter: id?, _ format: id?) {
    guard let formatter, let format = Strings.value(of: format) else { return }
    let storage = NumberFormatters.storage(formatter)
    storage.pattern = format
    storage.explicitNegative = nil
    storage.changed()
}

@c(_CFNumberFormatterCreateStringWithNumber)
public func CFNumberFormatterCreateStringWithNumber(_ allocator: UnsafeRawPointer?, _ formatter: id?, _ number: id?) -> id? {
    guard let formatter, let number else { return nil }
    return NumberFormatters.storage(formatter).string(from: number).map(Strings.make)
}

/// The value at `value`, of CFNumberType `type`, formatted.
@c(_CFNumberFormatterCreateStringWithValue)
public func CFNumberFormatterCreateStringWithValue(_ allocator: UnsafeRawPointer?, _ formatter: id?, _ type: Int,
                                                 _ value: UnsafeRawPointer?) -> id? {
    guard let number = CFNumberCreate(nil, type, value) else { return nil }
    defer { ObjC.release(number) }
    return CFNumberFormatterCreateStringWithNumber(allocator, formatter, number)
}

/// The number at the start of the string, or of `range` of it, which then
/// becomes the range parsed. kCFNumberFormatterParseIntegersOnly (1) stops
/// at a fraction. As on Darwin, the number is an integer when integers
/// were asked for, or the whole string parsed as one, and a float if not.
@c(_CFNumberFormatterCreateNumberFromString)
public func CFNumberFormatterCreateNumberFromString(_ allocator: UnsafeRawPointer?, _ formatter: id?, _ string: id?,
                                                   _ range: UnsafeMutablePointer<CFRange>?, _ options: UInt) -> id? {
    let integersOnly = options & 1 != 0
    guard let formatter, let text = CFFormatting.text(string, in: range),
          let (value, length) = NumberFormatters.storage(formatter).parse(text, integersOnly: integersOnly) else { return nil }
    let start = range?.pointee.location ?? 0
    let whole = start == 0 && length == (Strings.value(of: string)?.utf16.count ?? 0)
    range?.pointee.length = length
    return CFFormatting.number(value, integer: integersOnly || whole)
}

/// Parses as CFNumberFormatterCreateNumberFromString, and stores the
/// number as CFNumberType `type`: false when there's none, or it doesn't
/// fit.
@c(_CFNumberFormatterGetValueFromString)
public func CFNumberFormatterGetValueFromString(_ formatter: id?, _ string: id?, _ range: UnsafeMutablePointer<CFRange>?,
                                               _ type: Int, _ value: UnsafeMutableRawPointer?) -> Bool {
    guard let number = CFNumberFormatterCreateNumberFromString(nil, formatter, string, range, 0) else { return false }
    defer { ObjC.release(number) }
    return CFNumberGetValue(number, type, value)
}

@c(_CFNumberFormatterSetProperty)
public func CFNumberFormatterSetProperty(_ formatter: id?, _ key: id?, _ value: id?) {
    guard let formatter, let name = Strings.value(of: key), let property = NumberFormatterProperty.byKey[name] else { return }
    let storage = NumberFormatters.storage(formatter)
    switch property {
    case .symbol(let symbol): storage.setSymbol(symbol, Strings.value(of: value))
    case .text(let tag): storage.setText(tag, Strings.value(of: value))
    case .integer(let attribute): storage.setAttribute(attribute, Int(Numbers.storage(value).int64))
    case .flag(let attribute): storage.setAttribute(attribute, Numbers.storage(value).int64 != 0 ? 1 : 0)
    case .roundingIncrement:
        storage.doubleAttributes[UNUM_ROUNDING_INCREMENT.rawValue] = Numbers.storage(value).double
        storage.changed()
    case .zeroSymbol: storage.zeroSymbol = Strings.value(of: value)
    case .lenient:
        storage.lenient = Numbers.storage(value).int64 != 0
        storage.changed()
    case .defaultFormat: break
    }
}

@c(_CFNumberFormatterCopyProperty)
public func CFNumberFormatterCopyProperty(_ formatter: id?, _ key: id?) -> id? {
    guard let formatter, let name = Strings.value(of: key), let property = NumberFormatterProperty.byKey[name] else { return nil }
    let storage = NumberFormatters.storage(formatter)
    switch property {
    case .symbol(let symbol): return Strings.make(storage.symbol(symbol))
    case .text(let tag): return Strings.make(storage.text(tag))
    case .integer(let attribute): return CFFormatting.number(Double(storage.attribute(attribute)))
    case .flag(let attribute): return CFFormatting.boolean(storage.attribute(attribute) != 0)
    case .roundingIncrement:
        let increment = storage.handle.map { swift_unum_getDoubleAttribute($0, UNUM_ROUNDING_INCREMENT) } ?? 0
        var real = max(increment, 0)
        return CFNumberCreate(nil, CFNumberTypes.float64, &real)
    case .zeroSymbol: return storage.zeroSymbol.map(Strings.make)
    case .lenient: return CFFormatting.boolean(storage.lenient)
    case .defaultFormat:
        let plain = NumberFormatterStorage()
        plain.locale = storage.locale
        plain.setStyle(storage.style)
        return Strings.make(plain.fullPattern)
    }
}

/// A currency's fraction digits and rounding increment, from ICU's data:
/// false for a code that isn't three letters.
@c(_CFNumberFormatterGetDecimalInfoForCurrencyCode)
public func CFNumberFormatterGetDecimalInfoForCurrencyCode(_ code: id?, _ digits: UnsafeMutablePointer<Int32>?,
                                                          _ rounding: UnsafeMutablePointer<Double>?) -> Bool {
    guard let code = Strings.value(of: code), code.count == 3, code.allSatisfy({ $0.isLetter }) else { return false }
    let storage = NumberFormatterStorage()
    storage.locale = Locale(identifier: "en_US_POSIX")
    storage.setStyle(2)
    storage.setText(UNUM_CURRENCY_CODE, code.uppercased())
    guard let handle = storage.handle else { return false }
    digits?.pointee = swift_unum_getAttribute(handle, UNUM_MAX_FRACTION_DIGITS)
    rounding?.pointee = max(swift_unum_getDoubleAttribute(handle, UNUM_ROUNDING_INCREMENT), 0)
    return true
}

// MARK: - Dates

extension DateFormatterStorage {
    /// The date at the start of `text`, and how many UTF-16 units it takes.
    func parse(_ text: String) -> (date: Date, length: Int)? {
        guard !pattern.isEmpty else { return nil }
        return parseStart(text)
    }

    /// The styles' pattern, whatever format is set.
    var defaultPattern: String {
        let plain = DateFormatterStorage()
        plain.locale = locale
        plain.timeZone = timeZone
        plain.calendar = calendar
        plain.dateStyle = dateStyle
        plain.timeStyle = timeStyle
        return plain.pattern
    }
}

/// What a CFDateFormatter property is.
enum DateFormatterProperty {
    case lenient, timeZone, calendarName, calendar, defaultFormat, relative
    case twoDigitStart, defaultDate, gregorianStart
    case symbols(UDateFormatSymbolType)
    case amPM(Int32)

    nonisolated(unsafe) static let byKey: [String: DateFormatterProperty] = [
        "kCFDateFormatterIsLenientKey": .lenient,
        "kCFDateFormatterTimeZoneKey": .timeZone,
        "kCFDateFormatterCalendarNameKey": .calendarName,
        "kCFDateFormatterDefaultFormatKey": .defaultFormat,
        "kCFDateFormatterTwoDigitStartDateKey": .twoDigitStart,
        "kCFDateFormatterDefaultDateKey": .defaultDate,
        "kCFDateFormatterCalendarKey": .calendar,
        "kCFDateFormatterEraSymbolsKey": .symbols(UDAT_ERAS),
        "kCFDateFormatterMonthSymbolsKey": .symbols(UDAT_MONTHS),
        "kCFDateFormatterShortMonthSymbolsKey": .symbols(UDAT_SHORT_MONTHS),
        "kCFDateFormatterWeekdaySymbolsKey": .symbols(UDAT_WEEKDAYS),
        "kCFDateFormatterShortWeekdaySymbolsKey": .symbols(UDAT_SHORT_WEEKDAYS),
        "kCFDateFormatterAMSymbolKey": .amPM(0),
        "kCFDateFormatterPMSymbolKey": .amPM(1),
        "kCFDateFormatterLongEraSymbolsKey": .symbols(UDAT_ERA_NAMES),
        "kCFDateFormatterVeryShortMonthSymbolsKey": .symbols(UDAT_NARROW_MONTHS),
        "kCFDateFormatterStandaloneMonthSymbolsKey": .symbols(UDAT_STANDALONE_MONTHS),
        "kCFDateFormatterShortStandaloneMonthSymbolsKey": .symbols(UDAT_STANDALONE_SHORT_MONTHS),
        "kCFDateFormatterVeryShortStandaloneMonthSymbolsKey": .symbols(UDAT_STANDALONE_NARROW_MONTHS),
        "kCFDateFormatterVeryShortWeekdaySymbolsKey": .symbols(UDAT_NARROW_WEEKDAYS),
        "kCFDateFormatterStandaloneWeekdaySymbolsKey": .symbols(UDAT_STANDALONE_WEEKDAYS),
        "kCFDateFormatterShortStandaloneWeekdaySymbolsKey": .symbols(UDAT_STANDALONE_SHORT_WEEKDAYS),
        "kCFDateFormatterVeryShortStandaloneWeekdaySymbolsKey": .symbols(UDAT_STANDALONE_NARROW_WEEKDAYS),
        "kCFDateFormatterQuarterSymbolsKey": .symbols(UDAT_QUARTERS),
        "kCFDateFormatterShortQuarterSymbolsKey": .symbols(UDAT_SHORT_QUARTERS),
        "kCFDateFormatterStandaloneQuarterSymbolsKey": .symbols(UDAT_STANDALONE_QUARTERS),
        "kCFDateFormatterShortStandaloneQuarterSymbolsKey": .symbols(UDAT_STANDALONE_SHORT_QUARTERS),
        "kCFDateFormatterGregorianStartDateKey": .gregorianStart,
        "kCFDateFormatterDoesRelativeDateFormattingKey": .relative,
    ]
}

/// CFDateFormatter's property keys.
@ObjCConstants
enum DateFormatterKeys {
    static let kCFDateFormatterIsLenient = "kCFDateFormatterIsLenientKey"
    static let kCFDateFormatterTimeZone = "kCFDateFormatterTimeZoneKey"
    static let kCFDateFormatterCalendarName = "kCFDateFormatterCalendarNameKey"
    static let kCFDateFormatterDefaultFormat = "kCFDateFormatterDefaultFormatKey"
    static let kCFDateFormatterTwoDigitStartDate = "kCFDateFormatterTwoDigitStartDateKey"
    static let kCFDateFormatterDefaultDate = "kCFDateFormatterDefaultDateKey"
    static let kCFDateFormatterCalendar = "kCFDateFormatterCalendarKey"
    static let kCFDateFormatterEraSymbols = "kCFDateFormatterEraSymbolsKey"
    static let kCFDateFormatterMonthSymbols = "kCFDateFormatterMonthSymbolsKey"
    static let kCFDateFormatterShortMonthSymbols = "kCFDateFormatterShortMonthSymbolsKey"
    static let kCFDateFormatterWeekdaySymbols = "kCFDateFormatterWeekdaySymbolsKey"
    static let kCFDateFormatterShortWeekdaySymbols = "kCFDateFormatterShortWeekdaySymbolsKey"
    static let kCFDateFormatterAMSymbol = "kCFDateFormatterAMSymbolKey"
    static let kCFDateFormatterPMSymbol = "kCFDateFormatterPMSymbolKey"
    static let kCFDateFormatterLongEraSymbols = "kCFDateFormatterLongEraSymbolsKey"
    static let kCFDateFormatterVeryShortMonthSymbols = "kCFDateFormatterVeryShortMonthSymbolsKey"
    static let kCFDateFormatterStandaloneMonthSymbols = "kCFDateFormatterStandaloneMonthSymbolsKey"
    static let kCFDateFormatterShortStandaloneMonthSymbols = "kCFDateFormatterShortStandaloneMonthSymbolsKey"
    static let kCFDateFormatterVeryShortStandaloneMonthSymbols = "kCFDateFormatterVeryShortStandaloneMonthSymbolsKey"
    static let kCFDateFormatterVeryShortWeekdaySymbols = "kCFDateFormatterVeryShortWeekdaySymbolsKey"
    static let kCFDateFormatterStandaloneWeekdaySymbols = "kCFDateFormatterStandaloneWeekdaySymbolsKey"
    static let kCFDateFormatterShortStandaloneWeekdaySymbols = "kCFDateFormatterShortStandaloneWeekdaySymbolsKey"
    static let kCFDateFormatterVeryShortStandaloneWeekdaySymbols = "kCFDateFormatterVeryShortStandaloneWeekdaySymbolsKey"
    static let kCFDateFormatterQuarterSymbols = "kCFDateFormatterQuarterSymbolsKey"
    static let kCFDateFormatterShortQuarterSymbols = "kCFDateFormatterShortQuarterSymbolsKey"
    static let kCFDateFormatterStandaloneQuarterSymbols = "kCFDateFormatterStandaloneQuarterSymbolsKey"
    static let kCFDateFormatterShortStandaloneQuarterSymbols = "kCFDateFormatterShortStandaloneQuarterSymbolsKey"
    static let kCFDateFormatterGregorianStartDate = "kCFDateFormatterGregorianStartDateKey"
    static let kCFDateFormatterDoesRelativeDateFormattingKey = "kCFDateFormatterDoesRelativeDateFormattingKey"
}

@c(_CFDateFormatterGetTypeID) public func CFDateFormatterGetTypeID() -> UInt { CFTypeIDs.dateFormatter }

/// An NSDateFormatter with CFDateFormatterStyle's styles, which are
/// NSDateFormatterStyle's numbers, in the locale given.
@c(_CFDateFormatterCreate)
public func CFDateFormatterCreate(_ allocator: UnsafeRawPointer?, _ locale: id?, _ dateStyle: Int, _ timeStyle: Int) -> id? {
    guard let object = Storage.allocate(UnsafeMutableRawPointer(DateFormatters.formatterClass)) else { return nil }
    let storage = DateFormatters.storage(object)
    storage.locale = locale.map { Locales.locale($0) }
    storage.dateStyle = dateStyle
    storage.timeStyle = timeStyle
    return object
}

/// A formatter for ISO 8601 with CFISO8601DateFormatOptions, which are
/// NSISO8601DateFormatOptions: en_US_POSIX, in the current time zone, as on
/// Darwin.
@c(_CFDateFormatterCreateISO8601Formatter)
public func CFDateFormatterCreateISO8601Formatter(_ allocator: UnsafeRawPointer?, _ options: UInt) -> id? {
    guard let object = CFDateFormatterCreate(allocator, nil, 0, 0) else { return nil }
    let iso = ISO8601Storage()
    iso.options = options
    let storage = DateFormatters.storage(object)
    storage.locale = Locale(identifier: "en_US_POSIX")
    storage.format = iso.pattern
    storage.changed()
    return object
}

@c(_CFDateFormatterCreateDateFormatFromTemplate)
public func CFDateFormatterCreateDateFormatFromTemplate(_ allocator: UnsafeRawPointer?, _ template: id?, _ options: UInt,
                                                       _ locale: id?) -> id? {
    guard let template = Strings.value(of: template) else { return nil }
    let identifier = (locale.map { Locales.locale($0) } ?? Locales.current).identifier
    return DateFormatterStorage.pattern(fromTemplate: template, locale: identifier).map(Strings.make)
}

@c(_CFDateFormatterGetLocale)
public func CFDateFormatterGetLocale(_ formatter: id?) -> id? {
    guard let formatter else { return nil }
    let storage = DateFormatters.storage(formatter)
    return storage.held.hold("locale", Locales.autoreleased(storage.effectiveLocale))
}

@c(_CFDateFormatterGetDateStyle)
public func CFDateFormatterGetDateStyle(_ formatter: id?) -> Int { formatter.map { DateFormatters.storage($0).dateStyle } ?? 0 }

@c(_CFDateFormatterGetTimeStyle)
public func CFDateFormatterGetTimeStyle(_ formatter: id?) -> Int { formatter.map { DateFormatters.storage($0).timeStyle } ?? 0 }

@c(_CFDateFormatterGetFormat)
public func CFDateFormatterGetFormat(_ formatter: id?) -> id? {
    guard let formatter else { return nil }
    let storage = DateFormatters.storage(formatter)
    return storage.held.hold("format", Strings.autoreleased(storage.pattern))
}

@c(_CFDateFormatterSetFormat)
public func CFDateFormatterSetFormat(_ formatter: id?, _ format: id?) {
    guard let formatter, let format = Strings.value(of: format) else { return }
    let storage = DateFormatters.storage(formatter)
    storage.format = format
    storage.changed()
}

@c(_CFDateFormatterCreateStringWithDate)
public func CFDateFormatterCreateStringWithDate(_ allocator: UnsafeRawPointer?, _ formatter: id?, _ date: id?) -> id? {
    guard let formatter, let date else { return nil }
    return Strings.make(DateFormatters.storage(formatter).string(from: Dates.date(date)))
}

@c(_CFDateFormatterCreateStringWithAbsoluteTime)
public func CFDateFormatterCreateStringWithAbsoluteTime(_ allocator: UnsafeRawPointer?, _ formatter: id?,
                                                       _ time: Double.ObjCType) -> id? {
    guard let formatter else { return nil }
    let date = Date(timeIntervalSinceReferenceDate: Double(objCArgument: time))
    return Strings.make(DateFormatters.storage(formatter).string(from: date))
}

/// The date at the start of the string, or of `range` of it, which then
/// becomes the range parsed.
@c(_CFDateFormatterCreateDateFromString)
public func CFDateFormatterCreateDateFromString(_ allocator: UnsafeRawPointer?, _ formatter: id?, _ string: id?,
                                               _ range: UnsafeMutablePointer<CFRange>?) -> id? {
    guard let formatter, let text = CFFormatting.text(string, in: range),
          let (date, length) = DateFormatters.storage(formatter).parse(text) else { return nil }
    range?.pointee.length = length
    return ObjC.retain(Dates.autoreleased(date))
}

@c(_CFDateFormatterGetAbsoluteTimeFromString)
public func CFDateFormatterGetAbsoluteTimeFromString(_ formatter: id?, _ string: id?, _ range: UnsafeMutablePointer<CFRange>?,
                                                    _ time: UnsafeMutablePointer<Double>?) -> Bool {
    guard let formatter, let text = CFFormatting.text(string, in: range),
          let (date, length) = DateFormatters.storage(formatter).parse(text) else { return false }
    range?.pointee.length = length
    time?.pointee = date.timeIntervalSinceReferenceDate
    return true
}

@c(_CFDateFormatterSetProperty)
public func CFDateFormatterSetProperty(_ formatter: id?, _ key: id?, _ value: id?) {
    guard let formatter, let name = Strings.value(of: key), let property = DateFormatterProperty.byKey[name] else { return }
    let storage = DateFormatters.storage(formatter)
    switch property {
    case .lenient: storage.lenient = Numbers.storage(value).int64 != 0
    case .timeZone: storage.timeZone = TimeZones.zone(value)
    case .calendarName:
        storage.calendar = Strings.value(of: value).flatMap(CalendarIdentifiers.identifier).map { Calendar(identifier: $0) }
    case .calendar: storage.calendar = Calendars.calendar(value)
    case .amPM(let index): storage.amPMSymbols[index] = Strings.value(of: value)
    case .relative: storage.relative = Numbers.storage(value).int64 != 0
    case .twoDigitStart: storage.twoDigitStart = value.map { Dates.date($0) } ?? Date(timeIntervalSince1970: -631_152_000)
    case .defaultDate: storage.defaultDate = value.map { Dates.date($0) }
    case .gregorianStart: storage.gregorianStart = value.map { Dates.date($0) }
    case .symbols(let type):
        storage.symbolOverrides[type.rawValue] = value.map { Arrays.elements($0).map { Strings.value(of: $0) ?? "" } }
    case .defaultFormat: break
    }
    storage.changed()
}

@c(_CFDateFormatterCopyProperty)
public func CFDateFormatterCopyProperty(_ formatter: id?, _ key: id?) -> id? {
    guard let formatter, let name = Strings.value(of: key), let property = DateFormatterProperty.byKey[name] else { return nil }
    let storage = DateFormatters.storage(formatter)
    switch property {
    case .lenient: return CFFormatting.boolean(storage.lenient)
    case .timeZone: return ObjC.retain(TimeZones.autoreleased(storage.effectiveTimeZone))
    case .calendarName:
        return Strings.make(CalendarIdentifiers.name(storage.calendar?.identifier ?? storage.effectiveLocale.calendar.identifier))
    case .calendar:
        var calendar = storage.calendar ?? Calendar(identifier: storage.effectiveLocale.calendar.identifier)
        calendar.locale = storage.effectiveLocale
        calendar.timeZone = storage.effectiveTimeZone
        return ObjC.retain(Calendars.autoreleased(calendar))
    case .defaultFormat: return Strings.make(storage.defaultPattern)
    case .symbols(let type): return CFFormatting.strings(storage.symbols(type))
    case .amPM(let index):
        let symbols = storage.symbols(UDAT_AM_PMS)
        return Strings.make(storage.amPMSymbols[index] ?? (symbols.count > Int(index) ? symbols[Int(index)] : (index == 0 ? "AM" : "PM")))
    case .relative: return CFFormatting.boolean(storage.relative)
    case .twoDigitStart: return ObjC.retain(Dates.autoreleased(storage.twoDigitStart))
    case .defaultDate: return storage.defaultDate.flatMap { ObjC.retain(Dates.autoreleased($0)) }
    case .gregorianStart: return ObjC.retain(Dates.autoreleased(storage.gregorianStart ?? Date(timeIntervalSince1970: -12_219_292_800)))
    }
}
