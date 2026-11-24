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

    /// Date and number formatters behave as since Mac OS X 10.4
    /// (NSDateFormatterBehavior10_4, NSNumberFormatterBehavior10_4: 1040),
    /// the only behavior iOS has.
    @ObjCMethod("formatterBehavior") func formatterBehavior() -> UInt { 1040 }
    @ObjCMethod("setFormatterBehavior:") func setFormatterBehavior(_ behavior: UInt) {}
    @ObjCClassMethod("defaultFormatterBehavior") static func defaultFormatterBehavior() -> UInt { 1040 }
    @ObjCClassMethod("setDefaultFormatterBehavior:") static func setDefaultFormatterBehavior(_ behavior: UInt) {}

    /// Nil, unless a subclass writes attributed strings.
    @ObjCMethod("attributedStringForObjectValue:withDefaultAttributes:")
    func formatterAttributedString(forObjectValue value: ObjCObject?, withDefaultAttributes attributes: ObjCObject?) -> UnsafeMutableRawPointer? {
        nil
    }

    /// Abstract: Darwin raises for a formatter that doesn't parse; NO here,
    /// with no value, so subclasses that don't parse answer as Darwin's do.
    @ObjCMethod("getObjectValue:forString:errorDescription:")
    func formatterObjectValue(_ value: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, for string: String?,
                              errorDescription: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        value?.pointee = nil
        return false
    }

    /// Every partial string is valid, and none is replaced, unless a
    /// subclass says otherwise.
    @ObjCMethod("isPartialStringValid:newEditingString:errorDescription:")
    func isPartialStringValid(_ partial: String?, newEditingString: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                              errorDescription: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool { true }

    /// Asks -isPartialStringValid:newEditingString:errorDescription:; a
    /// replacement it gives becomes the partial string, with the selection
    /// at its end, as on Darwin.
    @ObjCMethod("isPartialStringValid:proposedSelectedRange:originalString:originalSelectedRange:errorDescription:")
    func isPartialStringValid(_ partial: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                              proposedSelectedRange: UnsafeMutablePointer<NSRange>?, originalString: ObjCObject?,
                              originalSelectedRange: NSRange,
                              errorDescription: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        guard let partial else { return true }
        typealias Check = @convention(c) (id, SEL, id?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                                          UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool
        var replacement: UnsafeMutableRawPointer?
        let valid = unsafeBitCast(ObjC.msgSend, to: Check.self)(
            objcObject, ObjC.selector("isPartialStringValid:newEditingString:errorDescription:"), partial.pointee, &replacement,
            errorDescription)
        if !valid, let replacement {
            partial.pointee = replacement
            proposedSelectedRange?.pointee = NSRange(location: UInt(Strings.value(of: replacement)?.utf16.count ?? 0), length: 0)
        }
        return valid
    }
}

enum FormatterErrors {
    /// NSFormattingError, NSCocoaErrorDomain's 2048, with the description
    /// given: the error a formatter's parse reports.
    static func formatting(_ description: String) -> UnsafeMutableRawPointer? {
        Errors.autoreleased(domain: Errors.cocoaDomain, code: 2048, description: description)
    }

    /// "The value “abc” is invalid.", Darwin's words for a string that
    /// isn't a value.
    static func invalid(_ string: String) -> String { "The value \u{201C}\(string)\u{201D} is invalid." }

    /// The UTF-16 range of a string a range pointer names, clamped to it,
    /// or all of it.
    static func text(_ string: String, in range: UnsafeMutablePointer<NSRange>?) -> String {
        guard let range else { return string }
        let units = Array(string.utf16)
        let start = min(Int(range.pointee.location), units.count)
        let end = min(start + Int(range.pointee.length), units.count)
        return String(decoding: units[start..<end], as: UTF16.self)
    }
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
    /// AM and PM symbols set over the locale's, by their index in ICU's list.
    var amPMSymbols: [Int32: String] = [:]
    /// Symbol lists set over the locale's, by UDateFormatSymbolType.
    var symbolOverrides: [UInt32: [String]] = [:]
    /// "Today", "Yesterday", "Tomorrow" for those days, in the date style.
    var relative = false
    /// The NSFormattingContext set, if one was.
    var context: Int?
    /// Where two-digit years start: 1950, as on Darwin.
    var twoDigitStart = Date(timeIntervalSince1970: -631_152_000)
    /// Where parsed dates take the fields the string leaves out.
    var defaultDate: Date?
    /// When the Gregorian calendar replaced the Julian, if moved from
    /// 15 October 1582.
    var gregorianStart: Date?
    var generatesCalendarDates = false
    var allowsNaturalLanguage = false
    /// What CFDateFormatter's Get functions return, and properties it only
    /// keeps, alive as long as the formatter.
    let held = HeldObjects()
    private var cached: (key: String, handle: DateHandle)?
    /// Held while the settings change and while the cached ICU formatter is
    /// in use: Darwin's date formatters are thread-safe (since iOS 7), and
    /// apps share one across threads, which closed a handle twice or while
    /// another thread formatted with it.
    let lock = NSRecursiveLockStorage()

    /// Changes the settings, and drops the formatter made from the old ones.
    func update(_ body: (DateFormatterStorage) -> Void) {
        lock.locked {
            body(self)
            changed()
        }
    }

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
        lock.locked {
            if let format { return format }
            guard dateStyle != 0 || timeStyle != 0,
                  let handle = Self.open(time: Self.icuStyle(timeStyle), date: Self.icuStyle(dateStyle), locale: localeID,
                                         zone: effectiveTimeZone.identifier, pattern: nil) else { return "" }
            defer { swift_udat_close(handle) }
            return ICU.string { swift_udat_toPattern(handle, 0, $0, $1, $2) } ?? ""
        }
    }

    /// Whether ICU's relative date style formats: relative formatting with
    /// a date style and no format set, as CFDateFormatter has it.
    private var formatsRelatively: Bool { relative && dateStyle != 0 && format == nil }

    /// NSFormattingContext as ICU's capitalization context.
    static func capitalization(_ context: Int) -> UDisplayContext {
        switch context {
        case 2: return UDISPCTX_CAPITALIZATION_FOR_STANDALONE
        case 3: return UDISPCTX_CAPITALIZATION_FOR_UI_LIST_OR_MENU
        case 4: return UDISPCTX_CAPITALIZATION_FOR_BEGINNING_OF_SENTENCE
        case 5: return UDISPCTX_CAPITALIZATION_FOR_MIDDLE_OF_SENTENCE
        default: return UDISPCTX_CAPITALIZATION_NONE
        }
    }

    static func firstSymbolIndex(_ type: UDateFormatSymbolType) -> Int32 {
        [UDAT_WEEKDAYS, UDAT_SHORT_WEEKDAYS, UDAT_NARROW_WEEKDAYS, UDAT_STANDALONE_WEEKDAYS,
         UDAT_STANDALONE_SHORT_WEEKDAYS, UDAT_STANDALONE_NARROW_WEEKDAYS].contains(type) ? 1 : 0
    }

    var handle: DateHandle? {
        // A format set while formatting relatively is put aside for the
        // styles' pattern, as CFDateFormatter does.
        let pattern = relative && format != nil ? defaultPattern : self.pattern
        let relativeStyles = formatsRelatively
        let key = "\(pattern)|\(localeID)|\(effectiveTimeZone.identifier)|\(lenient)|\(amPMSymbols)|\(relativeStyles)|\(context ?? -1)"
        if let cached, cached.key == key { return cached.handle }
        changed()
        let opened: DateHandle?
        if relativeStyles {
            let date = UDateFormatStyle(rawValue: Self.icuStyle(dateStyle).rawValue | UDAT_RELATIVE.rawValue)
            opened = Self.open(time: Self.icuStyle(timeStyle), date: date, locale: localeID, zone: effectiveTimeZone.identifier, pattern: nil)
        } else {
            opened = Self.open(time: UDAT_PATTERN, date: UDAT_PATTERN, locale: localeID, zone: effectiveTimeZone.identifier, pattern: pattern)
        }
        guard let handle = opened else { return nil }
        var status = U_ZERO_ERROR
        // Relative days are capitalized unless a context says otherwise.
        if relative { swift_udat_setContext(handle, UDISPCTX_CAPITALIZATION_FOR_UI_LIST_OR_MENU, &status) }
        if let context {
            status = U_ZERO_ERROR
            swift_udat_setContext(handle, Self.capitalization(context), &status)
        }
        swift_udat_setLenient(handle, lenient ? 1 : 0)
        status = U_ZERO_ERROR
        swift_udat_set2DigitYearStart(handle, twoDigitStart.timeIntervalSince1970 * 1000, &status)
        for (index, symbol) in amPMSymbols {
            var status = U_ZERO_ERROR
            ICU.withUChars(symbol) { swift_udat_setSymbols(handle, UDAT_AM_PMS, index, UnsafeMutablePointer(mutating: $0), $1, &status) }
        }
        for (raw, symbols) in symbolOverrides {
            let type = UDateFormatSymbolType(rawValue: raw)
            let first = Self.firstSymbolIndex(type)
            for (index, symbol) in symbols.enumerated() {
                var status = U_ZERO_ERROR
                ICU.withUChars(symbol) {
                    swift_udat_setSymbols(handle, type, first + Int32(index), UnsafeMutablePointer(mutating: $0), $1, &status)
                }
            }
        }
        if let gregorianStart, let current = swift_udat_getCalendar(handle) {
            status = U_ZERO_ERROR
            if let changed = swift_ucal_clone(current, &status), !ICU.failed(status) {
                swift_ucal_setGregorianChange(changed, gregorianStart.timeIntervalSince1970 * 1000, &status)
                swift_udat_setCalendar(handle, changed)
                swift_ucal_close(changed)
            }
        }
        cached = (key, handle)
        return handle
    }

    func string(from date: Date) -> String {
        lock.locked {
            guard !(relative && format != nil ? defaultPattern : pattern).isEmpty, let handle else { return "" }
            let milliseconds = date.timeIntervalSince1970 * 1000
            return ICU.string { swift_udat_format(handle, milliseconds, $0, $1, nil, $2) } ?? ""
        }
    }

    /// Parses the start of `text` into a calendar that holds the default
    /// date, or else 1 January 2000 in a Gregorian calendar (the epoch in
    /// another), as CFDateFormatter does: the fields the string leaves out
    /// come from it. The date and how many UTF-16 units it took.
    func parseStart(_ text: String) -> (date: Date, length: Int)? {
        lock.locked {
            guard let handle, let formatCalendar = swift_udat_getCalendar(handle) else { return nil }
            var status = U_ZERO_ERROR
            guard let parsing = swift_ucal_clone(formatCalendar, &status), !ICU.failed(status) else { return nil }
            defer { swift_ucal_close(parsing) }
            if let defaultDate {
                swift_ucal_setMillis(parsing, defaultDate.timeIntervalSince1970 * 1000, &status)
            } else {
                swift_ucal_clear(parsing)
                if (calendar ?? Calendar(identifier: effectiveLocale.calendar.identifier)).identifier == .gregorian {
                    swift_ucal_set(parsing, UCAL_YEAR, 2000)
                }
            }
            return ICU.withUChars(text) { chars, length -> (date: Date, length: Int)? in
                var position: Int32 = 0
                var status = U_ZERO_ERROR
                swift_udat_parseCalendar(handle, parsing, chars, length, &position, &status)
                guard !ICU.failed(status), position > 0 else { return nil }
                let milliseconds = swift_ucal_getMillis(parsing, &status)
                guard !ICU.failed(status) else { return nil }
                return (Date(timeIntervalSince1970: milliseconds / 1000), Int(position))
            }
        }
    }

    /// The date, when the whole string parses.
    func date(from string: String) -> Date? {
        guard let (date, length) = parseStart(string), length == string.utf16.count else { return nil }
        return date
    }

    /// A symbol list: the one set, or the locale's.
    func symbols(_ type: UDateFormatSymbolType) -> [String] {
        if let set = symbolOverrides[type.rawValue] { return set }
        return localeSymbols(type)
    }

    /// The locale's symbol list; ICU's weekdays start at index 1.
    func localeSymbols(_ type: UDateFormatSymbolType) -> [String] {
        guard let handle = Self.open(time: UDAT_DEFAULT, date: UDAT_DEFAULT, locale: localeID,
                                     zone: effectiveTimeZone.identifier, pattern: nil) else { return [] }
        defer { swift_udat_close(handle) }
        let count = swift_udat_countSymbols(handle, type)
        let first = Self.firstSymbolIndex(type)
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

    /// Nil for no date, as on Darwin.
    @ObjCMethod("stringFromDate:") func string(from date: NSDate?) -> String? { date.map { storage.string(from: $0.date) } }

    @ObjCMethod("stringForObjectValue:")
    func dateString(forObjectValue value: ObjCObject?) -> String? {
        guard let value, ObjC.isKind(value.id, of: Dates.dateClass) else { return nil }
        return storage.string(from: Dates.date(value.id))
    }

    @ObjCMethod("dateFromString:")
    func date(from string: String?) -> UnsafeMutableRawPointer? { string.flatMap { storage.date(from: $0) }.flatMap { Dates.autoreleased($0) } }

    @ObjCMethod("getObjectValue:forString:errorDescription:")
    func getObjectValue(_ value: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, for string: String,
                        errorDescription: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        guard let date = storage.date(from: string) else {
            errorDescription?.pointee = Strings.autoreleased(FormatterErrors.invalid(string))
            return false
        }
        value?.pointee = Dates.autoreleased(date)
        return true
    }

    /// The date at the start of the range (or string), which becomes the
    /// range parsed; NSFormattingError when there's none, as on Darwin.
    @ObjCMethod("getObjectValue:forString:range:error:")
    func getObjectValue(_ value: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, for string: String?,
                        range: UnsafeMutablePointer<NSRange>?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        let text = FormatterErrors.text(string ?? "", in: range)
        guard let (date, length) = storage.parse(text) else {
            error?.pointee = FormatterErrors.formatting(FormatterErrors.invalid(text))
            return false
        }
        range?.pointee.length = UInt(length)
        value?.pointee = Dates.autoreleased(date)
        return true
    }

    /// The legacy initializer: the format, and whether natural language
    /// was asked for, which is kept and nothing more, as on iOS.
    @ObjCMethod("initWithDateFormat:allowNaturalLanguage:")
    func initialize(dateFormat: String?, allowNaturalLanguage: Bool) -> Self {
        storage.update {
            $0.format = dateFormat
            $0.allowsNaturalLanguage = allowNaturalLanguage
        }
        return self
    }

    @ObjCMethod("allowsNaturalLanguage") func allowsNaturalLanguage() -> Bool { storage.allowsNaturalLanguage }

    /// Whether "Today", "Yesterday" and "Tomorrow" stand for those days,
    /// in a date style: ICU's relative date styles.
    @ObjCMethod("doesRelativeDateFormatting") func doesRelativeDateFormatting() -> Bool { storage.relative }
    @ObjCMethod("setDoesRelativeDateFormatting:")
    func setDoesRelativeDateFormatting(_ relative: Bool) { storage.update { $0.relative = relative } }

    /// NSFormattingContext: how names are capitalized.
    @ObjCMethod("formattingContext") func formattingContext() -> Int { storage.context ?? 0 }
    @ObjCMethod("setFormattingContext:")
    func setFormattingContext(_ context: Int) { storage.update { $0.context = context } }

    @ObjCMethod("defaultDate") func defaultDate() -> UnsafeMutableRawPointer? { storage.defaultDate.flatMap { Dates.autoreleased($0) } }
    @ObjCMethod("setDefaultDate:")
    func setDefaultDate(_ date: ObjCObject?) { storage.update { $0.defaultDate = date.map { Dates.date($0.id) } } }

    @ObjCMethod("twoDigitStartDate") func twoDigitStartDate() -> UnsafeMutableRawPointer? { Dates.autoreleased(storage.twoDigitStart) }
    @ObjCMethod("setTwoDigitStartDate:")
    func setTwoDigitStartDate(_ date: ObjCObject?) {
        storage.update { $0.twoDigitStart = date.map { Dates.date($0.id) } ?? Date(timeIntervalSince1970: -631_152_000) }
    }

    /// 15 October 1582 unless set.
    @ObjCMethod("gregorianStartDate")
    func gregorianStartDate() -> UnsafeMutableRawPointer? {
        Dates.autoreleased(storage.gregorianStart ?? Date(timeIntervalSince1970: -12_219_292_800))
    }
    @ObjCMethod("setGregorianStartDate:")
    func setGregorianStartDate(_ date: ObjCObject?) { storage.update { $0.gregorianStart = date.map { Dates.date($0.id) } } }

    /// Kept: NSCalendarDate isn't on iOS, so dates are NSDates either way.
    @ObjCMethod("generatesCalendarDates") func generatesCalendarDates() -> Bool { storage.generatesCalendarDates }
    @ObjCMethod("setGeneratesCalendarDates:")
    func setGeneratesCalendarDates(_ generates: Bool) { storage.update { $0.generatesCalendarDates = generates } }

    @ObjCMethod("dateFormat") func dateFormat() -> String { storage.pattern }

    @ObjCMethod("setDateFormat:")
    func setDateFormat(_ format: String?) {
        storage.update { $0.format = format }
    }

    @ObjCMethod("dateStyle") func dateStyle() -> UInt { UInt(storage.dateStyle) }

    /// Setting a style replaces the format, as on Darwin.
    @ObjCMethod("setDateStyle:")
    func setDateStyle(_ style: UInt) {
        storage.update { $0.dateStyle = Int(style); $0.format = nil }
    }

    @ObjCMethod("timeStyle") func timeStyle() -> UInt { UInt(storage.timeStyle) }

    @ObjCMethod("setTimeStyle:")
    func setTimeStyle(_ style: UInt) {
        storage.update { $0.timeStyle = Int(style); $0.format = nil }
    }

    @ObjCMethod("locale") func locale() -> UnsafeMutableRawPointer { Locales.autoreleased(storage.effectiveLocale) }

    @ObjCMethod("setLocale:")
    func setLocale(_ locale: ObjCObject?) {
        storage.update { storage in storage.locale = locale.map { Locales.locale($0.id) } }
    }

    @ObjCMethod("timeZone") func timeZone() -> UnsafeMutableRawPointer { TimeZones.autoreleased(storage.effectiveTimeZone) }

    @ObjCMethod("setTimeZone:")
    func setTimeZone(_ zone: ObjCObject?) {
        storage.update { $0.timeZone = TimeZones.zone(zone?.id) }
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
        storage.update { $0.calendar = Calendars.calendar(calendar?.id) }
    }

    @ObjCMethod("isLenient") func isLenient() -> Bool { storage.lenient }

    @ObjCMethod("setLenient:")
    func setLenient(_ lenient: Bool) {
        storage.update { $0.lenient = lenient }
    }

    @ObjCMethod("setLocalizedDateFormatFromTemplate:")
    func setLocalizedDateFormat(fromTemplate template: String) {
        storage.update { $0.format = DateFormatterStorage.pattern(fromTemplate: template, locale: storage.localeID) }
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
    @ObjCMethod("standaloneQuarterSymbols") func standaloneQuarterSymbols() -> ObjCObject { symbols(UDAT_STANDALONE_QUARTERS) }
    @ObjCMethod("shortStandaloneQuarterSymbols")
    func shortStandaloneQuarterSymbols() -> ObjCObject { symbols(UDAT_STANDALONE_SHORT_QUARTERS) }
    @ObjCMethod("veryShortStandaloneMonthSymbols")
    func veryShortStandaloneMonthSymbols() -> ObjCObject { symbols(UDAT_STANDALONE_NARROW_MONTHS) }
    @ObjCMethod("shortStandaloneWeekdaySymbols")
    func shortStandaloneWeekdaySymbols() -> ObjCObject { symbols(UDAT_STANDALONE_SHORT_WEEKDAYS) }
    @ObjCMethod("veryShortStandaloneWeekdaySymbols")
    func veryShortStandaloneWeekdaySymbols() -> ObjCObject { symbols(UDAT_STANDALONE_NARROW_WEEKDAYS) }

    /// Sets a symbol list over the locale's; nil goes back to the locale's.
    private func setSymbols(_ type: UDateFormatSymbolType, _ list: ObjCObject?) {
        let values = list.map { Arrays.elements($0.id).map { Strings.value(of: $0) ?? "" } }
        storage.update { $0.symbolOverrides[type.rawValue] = values }
    }

    @ObjCMethod("setEraSymbols:") func setEraSymbols(_ list: ObjCObject?) { setSymbols(UDAT_ERAS, list) }
    @ObjCMethod("setLongEraSymbols:") func setLongEraSymbols(_ list: ObjCObject?) { setSymbols(UDAT_ERA_NAMES, list) }
    @ObjCMethod("setMonthSymbols:") func setMonthSymbols(_ list: ObjCObject?) { setSymbols(UDAT_MONTHS, list) }
    @ObjCMethod("setShortMonthSymbols:") func setShortMonthSymbols(_ list: ObjCObject?) { setSymbols(UDAT_SHORT_MONTHS, list) }
    @ObjCMethod("setVeryShortMonthSymbols:")
    func setVeryShortMonthSymbols(_ list: ObjCObject?) { setSymbols(UDAT_NARROW_MONTHS, list) }
    @ObjCMethod("setStandaloneMonthSymbols:")
    func setStandaloneMonthSymbols(_ list: ObjCObject?) { setSymbols(UDAT_STANDALONE_MONTHS, list) }
    @ObjCMethod("setShortStandaloneMonthSymbols:")
    func setShortStandaloneMonthSymbols(_ list: ObjCObject?) { setSymbols(UDAT_STANDALONE_SHORT_MONTHS, list) }
    @ObjCMethod("setVeryShortStandaloneMonthSymbols:")
    func setVeryShortStandaloneMonthSymbols(_ list: ObjCObject?) { setSymbols(UDAT_STANDALONE_NARROW_MONTHS, list) }
    @ObjCMethod("setWeekdaySymbols:") func setWeekdaySymbols(_ list: ObjCObject?) { setSymbols(UDAT_WEEKDAYS, list) }
    @ObjCMethod("setShortWeekdaySymbols:") func setShortWeekdaySymbols(_ list: ObjCObject?) { setSymbols(UDAT_SHORT_WEEKDAYS, list) }
    @ObjCMethod("setVeryShortWeekdaySymbols:")
    func setVeryShortWeekdaySymbols(_ list: ObjCObject?) { setSymbols(UDAT_NARROW_WEEKDAYS, list) }
    @ObjCMethod("setStandaloneWeekdaySymbols:")
    func setStandaloneWeekdaySymbols(_ list: ObjCObject?) { setSymbols(UDAT_STANDALONE_WEEKDAYS, list) }
    @ObjCMethod("setShortStandaloneWeekdaySymbols:")
    func setShortStandaloneWeekdaySymbols(_ list: ObjCObject?) { setSymbols(UDAT_STANDALONE_SHORT_WEEKDAYS, list) }
    @ObjCMethod("setVeryShortStandaloneWeekdaySymbols:")
    func setVeryShortStandaloneWeekdaySymbols(_ list: ObjCObject?) { setSymbols(UDAT_STANDALONE_NARROW_WEEKDAYS, list) }
    @ObjCMethod("setQuarterSymbols:") func setQuarterSymbols(_ list: ObjCObject?) { setSymbols(UDAT_QUARTERS, list) }
    @ObjCMethod("setShortQuarterSymbols:") func setShortQuarterSymbols(_ list: ObjCObject?) { setSymbols(UDAT_SHORT_QUARTERS, list) }
    @ObjCMethod("setStandaloneQuarterSymbols:")
    func setStandaloneQuarterSymbols(_ list: ObjCObject?) { setSymbols(UDAT_STANDALONE_QUARTERS, list) }
    @ObjCMethod("setShortStandaloneQuarterSymbols:")
    func setShortStandaloneQuarterSymbols(_ list: ObjCObject?) { setSymbols(UDAT_STANDALONE_SHORT_QUARTERS, list) }
    @ObjCMethod("AMSymbol")
    func amSymbol() -> String { storage.amPMSymbols[0] ?? storage.symbols(UDAT_AM_PMS).first ?? "AM" }
    @ObjCMethod("PMSymbol")
    func pmSymbol() -> String { storage.amPMSymbols[1] ?? storage.symbols(UDAT_AM_PMS).dropFirst().first ?? "PM" }
    @ObjCMethod("setAMSymbol:") func setAMSymbol(_ symbol: String?) { storage.amPMSymbols[0] = symbol }
    @ObjCMethod("setPMSymbol:") func setPMSymbol(_ symbol: String?) { storage.amPMSymbols[1] = symbol }
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

    @ObjCMethod("getObjectValue:forString:errorDescription:")
    func getObjectValue(_ value: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, for string: String,
                        errorDescription: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        guard let date = storage.formatter.date(from: string) else {
            errorDescription?.pointee = Strings.autoreleased(FormatterErrors.invalid(string))
            return false
        }
        value?.pointee = Dates.autoreleased(date)
        return true
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
    /// Kept as set; parsed numbers are NSNumbers either way.
    var generatesDecimalNumbers = false
    /// Whether a parsed string may have a fraction.
    var allowsFloats = true
    /// The fields the formatter was unarchived with, to archive it again.
    var archived: ArchivedFields?
    var pattern: String?
    var attributes: [UInt32: Int32] = [:]
    var doubleAttributes: [UInt32: Double] = [:]
    var textAttributes: [UInt32: String] = [:]
    var symbols: [UInt32: String] = [:]
    /// What zero formats as, instead of its digits.
    var zeroSymbol: String?
    /// What NSNumberFormatter writes nil and the infinities as: Darwin's
    /// "", "+∞" and "-∞" until set (nil for ICU's).
    var nilSymbol = ""
    var positiveInfinitySymbol: String? = "+\u{221E}"
    var negativeInfinitySymbol: String? = "-\u{221E}"
    /// The negative format as set, which Darwin gives back as it was.
    var explicitNegative: String?
    var localizesFormat = true
    var formattingContext = 0
    var partialStringValidation = false
    /// What CFNumberFormatter's Get functions return, alive as long as the
    /// formatter.
    let held = HeldObjects()
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
        explicitNegative = nil
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
        if let zeroSymbol, value.double == 0 { return zeroSymbol }
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
            if !allowsFloats, value != value.rounded() { return nil }
            if value == value.rounded(), abs(value) < 9e15 { return Numbers.make(nil, .signed(Int64(value))) }
            return Numbers.make(nil, .double(value))
        }
    }

    var positiveFormat: String {
        guard let handle else { return "" }
        let pattern = ICU.string { swift_unum_toPattern(handle, 0, $0, $1, $2) } ?? ""
        return String(pattern.split(separator: ";", maxSplits: 1).first ?? "")
    }

    /// The negative format as set; else the pattern's negative part, or
    /// the positive format when it has none, as Darwin answers.
    var negativeFormat: String {
        if let explicitNegative { return explicitNegative }
        guard let handle else { return "" }
        let pattern = ICU.string { swift_unum_toPattern(handle, 0, $0, $1, $2) } ?? ""
        let parts = pattern.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
        return parts.count > 1 ? String(parts[1]) : String(parts.first ?? "")
    }

    /// Keeps a copy of an object under `key`, or nothing.
    func keep(_ key: String, copying object: id?) {
        let copy = object.flatMap { ObjC.send($0, Selectors.copyWithZone, nil) }
        held.hold(key, copy)
        if let copy { ObjC.release(copy) }
    }

    /// A double as the formatter writes it.
    func string(fromDouble value: Double) -> String {
        guard let handle else { return "" }
        return ICU.string { swift_unum_formatDouble(handle, value, $0, $1, nil, $2) } ?? ""
    }
}

extension NumberFormatterStorage {
    /// A decimal formatter in the current locale that rounds half up, to
    /// fraction digits or to significant digits: what NSByteCountFormatter
    /// writes its numbers with.
    static func roundingHalfUp(fractionDigits: (min: Int, max: Int)? = nil,
                               significantDigits: (min: Int, max: Int)? = nil) -> NumberFormatterStorage {
        let formatter = NumberFormatterStorage()
        formatter.setStyle(1)
        formatter.setAttribute(UNUM_ROUNDING_MODE, 6)    // UNUM_ROUND_HALFUP
        if let fractionDigits {
            formatter.setAttribute(UNUM_MIN_FRACTION_DIGITS, fractionDigits.min)
            formatter.setAttribute(UNUM_MAX_FRACTION_DIGITS, fractionDigits.max)
        }
        if let significantDigits {
            formatter.setAttribute(UNUM_SIGNIFICANT_DIGITS_USED, 1)
            formatter.setAttribute(UNUM_MIN_SIGNIFICANT_DIGITS, significantDigits.min)
            formatter.setAttribute(UNUM_MAX_SIGNIFICANT_DIGITS, significantDigits.max)
        }
        return formatter
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

    private static let archivedFields: [ArchivedFields.Field] = [
        ("NS.attributes", .object), ("NS.positiveformat", .object), ("NS.negativeformat", .object), ("NS.positiveattrs", .object),
        ("NS.negativeattrs", .object), ("NS.zero", .object), ("NS.nil", .object), ("NS.nan", .object), ("NS.min", .object),
        ("NS.max", .object), ("NS.rounding", .object), ("NS.decimal", .object), ("NS.thousand", .object), ("NS.hasthousands", .bool),
        ("NS.localized", .bool), ("NS.allowsfloats", .bool),
    ]

    /// From a keyed archive or nib: the style, the formats and whether
    /// fractions are allowed are used; the rest is kept to archive again.
    @ObjCMethod("initWithCoder:")
    func initialize(coder: ObjCObject) -> Self {
        let fields = ArchivedFields(coder: coder.id, fields: Self.archivedFields)
        let storage = storage
        if let attributes = fields.object("NS.attributes"), ObjC.isKind(attributes, of: Dictionaries.dictionaryClass),
           let style = ObjC.send(attributes, ObjC.selector("objectForKey:"), Strings.autoreleased("numberStyle")) {
            storage.setStyle(ObjC.sendInt(style, ObjC.selector("integerValue"), nil))
        }
        if let positive = fields.string("NS.positiveformat"), !positive.isEmpty {
            let negative = fields.string("NS.negativeformat") ?? ""
            storage.pattern = negative.isEmpty || negative == positive ? positive : positive + ";" + negative
        }
        if let allows = fields.bool("NS.allowsfloats") { storage.allowsFloats = allows }
        storage.archived = fields
        storage.changed()
        return self
    }

    @ObjCMethod("encodeWithCoder:")
    func encode(coder: ObjCObject) {
        if let archived = storage.archived { return archived.encode(coder: coder.id) }
        typealias EncodeObject = @convention(c) (id?, SEL, id?, id?) -> Void
        typealias EncodeBool = @convention(c) (id?, SEL, Bool, id?) -> Void
        let object = unsafeBitCast(ObjC.msgSend, to: EncodeObject.self), bool = unsafeBitCast(ObjC.msgSend, to: EncodeBool.self)
        object(coder.id, ObjC.selector("encodeObject:forKey:"), Strings.autoreleased(storage.positiveFormat), Strings.autoreleased("NS.positiveformat"))
        object(coder.id, ObjC.selector("encodeObject:forKey:"), Strings.autoreleased(storage.negativeFormat), Strings.autoreleased("NS.negativeformat"))
        bool(coder.id, ObjC.selector("encodeBool:forKey:"), storage.allowsFloats, Strings.autoreleased("NS.allowsfloats"))
    }

    /// A number as written: the infinities by their symbols, as on Darwin.
    private func written(_ number: id) -> String? {
        let value = Numbers.storage(number).double
        if value.isInfinite, let symbol = value > 0 ? storage.positiveInfinitySymbol : storage.negativeInfinitySymbol {
            return symbol
        }
        return storage.string(from: number)
    }

    @ObjCMethod("stringFromNumber:")
    func string(from number: ObjCObject?) -> String? { number.flatMap { written($0.id) } }

    /// The nil symbol for nil; nil for what isn't a number.
    @ObjCMethod("stringForObjectValue:")
    func numberString(forObjectValue value: ObjCObject?) -> String? {
        guard let value else { return storage.nilSymbol }
        guard ObjC.isKind(value.id, of: Numbers.numberClass) else { return nil }
        return written(value.id)
    }

    /// The number a whole string is, the infinities by their symbols and
    /// NaN never; or why it isn't, in Darwin's words.
    private func parsed(_ string: String) -> (number: id?, error: String?) {
        var number: id?
        if let symbol = storage.positiveInfinitySymbol, string == symbol {
            number = Numbers.make(nil, .double(.infinity))
        } else if let symbol = storage.negativeInfinitySymbol, string == symbol {
            number = Numbers.make(nil, .double(-.infinity))
        } else {
            number = storage.number(from: string)
        }
        guard let number, !Numbers.storage(number).double.isNaN else { return (nil, FormatterErrors.invalid(string)) }
        return checked(number)
    }

    /// The number, unless it's below the minimum or above the maximum.
    private func checked(_ number: id) -> (number: id?, error: String?) {
        let value = Numbers.storage(number).double
        if let minimum = storage.held["minimum"], value < Numbers.storage(minimum).double {
            return (nil, "The value \(written(number) ?? "") is too small.")
        }
        if let maximum = storage.held["maximum"], value > Numbers.storage(maximum).double {
            return (nil, "The value \(written(number) ?? "") is too large.")
        }
        return (number, nil)
    }

    @ObjCMethod("numberFromString:")
    func number(from string: String?) -> UnsafeMutableRawPointer? { string.flatMap { parsed($0).number } }

    @ObjCMethod("getObjectValue:forString:errorDescription:")
    func getObjectValue(_ value: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, for string: String,
                        errorDescription: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        let (number, error) = parsed(string)
        guard let number else {
            errorDescription?.pointee = error.map { Strings.autoreleased($0) }
            return false
        }
        value?.pointee = number
        return true
    }

    /// The number at the start of the range (or string), which becomes the
    /// range parsed; NSFormattingError when there's none or it's out of
    /// bounds.
    @ObjCMethod("getObjectValue:forString:range:error:")
    func getObjectValue(_ value: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, for string: String?,
                        range: UnsafeMutablePointer<NSRange>?, error: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        let text = FormatterErrors.text(string ?? "", in: range)
        guard let (parsedValue, length) = storage.parse(text, integersOnly: false), !parsedValue.isNaN else {
            error?.pointee = FormatterErrors.formatting(FormatterErrors.invalid(text))
            return false
        }
        let whole = parsedValue == parsedValue.rounded() && abs(parsedValue) < 9e15
        guard let made = Numbers.make(nil, whole ? .signed(Int64(parsedValue)) : .double(parsedValue)) else { return false }
        let (number, failure) = checked(made)
        guard let number else {
            error?.pointee = FormatterErrors.formatting(failure ?? FormatterErrors.invalid(text))
            return false
        }
        range?.pointee.length = UInt(length)
        value?.pointee = number
        return true
    }

    /// The value written with the default attributes and the text
    /// attributes set for its kind (zero, negative, ...) over them.
    @ObjCMethod("attributedStringForObjectValue:withDefaultAttributes:")
    func numberAttributedString(forObjectValue value: ObjCObject?, withDefaultAttributes defaults: ObjCObject?) -> UnsafeMutableRawPointer? {
        guard let text = numberString(forObjectValue: value) else { return nil }
        let kind: String
        if let value {
            let double = Numbers.storage(value.id).double
            kind = double.isNaN ? "NotANumber" : double.isInfinite ? (double > 0 ? "PositiveInfinity" : "NegativeInfinity")
                : double == 0 ? "Zero" : double < 0 ? "NegativeValues" : "PositiveValues"
        } else {
            kind = "Nil"
        }
        var entries = defaults.map { Dictionaries.entries($0.id) } ?? []
        if let extra = storage.held["textAttributesFor" + kind] {
            for entry in Dictionaries.entries(extra) {
                entries.removeAll { AttributedStorage.equal($0.key, entry.key) }
                entries.append(entry)
            }
        }
        let attributes = Dictionaries.make(entries)
        defer { ObjC.release(attributes) }
        return ObjC.autorelease(AttributedStrings.make(AttributedStorage(units: Array(text.utf16), attributes: attributes), mutable: false))
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

    @ObjCMethod("allowsFloats") func allowsFloats() -> Bool { storage.allowsFloats }
    @ObjCMethod("setAllowsFloats:") func setAllowsFloats(_ allows: Bool) { storage.allowsFloats = allows }

    @ObjCMethod("generatesDecimalNumbers") func generatesDecimalNumbers() -> Bool { storage.generatesDecimalNumbers }
    @ObjCMethod("setGeneratesDecimalNumbers:")
    func setGeneratesDecimalNumbers(_ generates: Bool) { storage.generatesDecimalNumbers = generates }

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
        storage.explicitNegative = nil
        storage.changed()
    }

    @ObjCMethod("setNegativeFormat:")
    func setNegativeFormat(_ format: String?) {
        guard let format else { return }
        storage.pattern = storage.positiveFormat + ";" + format
        storage.explicitNegative = format
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
    @ObjCMethod("zeroSymbol") func zeroSymbol() -> String? { storage.zeroSymbol }
    @ObjCMethod("setZeroSymbol:") func setZeroSymbol(_ value: String?) { storage.zeroSymbol = value }
    @ObjCMethod("notANumberSymbol") func notANumberSymbol() -> String { storage.symbol(UNUM_NAN_SYMBOL) }
    @ObjCMethod("currencyDecimalSeparator")
    func currencyDecimalSeparator() -> String { storage.symbol(UNUM_MONETARY_SEPARATOR_SYMBOL) }
    @ObjCMethod("currencyGroupingSeparator")
    func currencyGroupingSeparator() -> String { storage.symbol(UNUM_MONETARY_GROUPING_SEPARATOR_SYMBOL) }
    @ObjCMethod("setCurrencyDecimalSeparator:")
    func setCurrencyDecimalSeparator(_ value: String?) { storage.setSymbol(UNUM_MONETARY_SEPARATOR_SYMBOL, value) }
    @ObjCMethod("setCurrencyGroupingSeparator:")
    func setCurrencyGroupingSeparator(_ value: String?) { storage.setSymbol(UNUM_MONETARY_GROUPING_SEPARATOR_SYMBOL, value) }
    @ObjCMethod("setInternationalCurrencySymbol:")
    func setInternationalCurrencySymbol(_ value: String?) { storage.setSymbol(UNUM_INTL_CURRENCY_SYMBOL, value) }
    @ObjCMethod("setExponentSymbol:") func setExponentSymbol(_ value: String?) { storage.setSymbol(UNUM_EXPONENTIAL_SYMBOL, value) }
    @ObjCMethod("setPerMillSymbol:") func setPerMillSymbol(_ value: String?) { storage.setSymbol(UNUM_PERMILL_SYMBOL, value) }
    /// Nil goes back to the locale's.
    @ObjCMethod("setNotANumberSymbol:") func setNotANumberSymbol(_ value: String?) { storage.setSymbol(UNUM_NAN_SYMBOL, value) }

    @ObjCMethod("nilSymbol") func nilSymbol() -> String { storage.nilSymbol }
    @ObjCMethod("setNilSymbol:") func setNilSymbol(_ value: String?) { storage.nilSymbol = value ?? "" }

    /// "+∞" and "-∞" until set; nil writes ICU's.
    @ObjCMethod("positiveInfinitySymbol") func positiveInfinitySymbol() -> String? { storage.positiveInfinitySymbol }
    @ObjCMethod("setPositiveInfinitySymbol:")
    func setPositiveInfinitySymbol(_ value: String?) { storage.positiveInfinitySymbol = value }
    @ObjCMethod("negativeInfinitySymbol") func negativeInfinitySymbol() -> String? { storage.negativeInfinitySymbol }
    @ObjCMethod("setNegativeInfinitySymbol:")
    func setNegativeInfinitySymbol(_ value: String?) { storage.negativeInfinitySymbol = value }

    @ObjCMethod("minimumGroupingDigits")
    func minimumGroupingDigits() -> Int { max(1, storage.attribute(UNUM_MINIMUM_GROUPING_DIGITS)) }
    @ObjCMethod("setMinimumGroupingDigits:")
    func setMinimumGroupingDigits(_ value: Int) { storage.setAttribute(UNUM_MINIMUM_GROUPING_DIGITS, value) }

    // MARK: Bounds, contexts and validation

    /// Parsed numbers below the minimum or above the maximum fail; numbers
    /// format whatever their value, as on Darwin.
    @ObjCMethod("minimum") func minimum() -> UnsafeMutableRawPointer? { storage.held["minimum"] }
    @ObjCMethod("setMinimum:")
    func setMinimum(_ value: ObjCObject?) { storage.keep("minimum", copying: value?.id) }
    @ObjCMethod("maximum") func maximum() -> UnsafeMutableRawPointer? { storage.held["maximum"] }
    @ObjCMethod("setMaximum:")
    func setMaximum(_ value: ObjCObject?) { storage.keep("maximum", copying: value?.id) }

    @ObjCMethod("formattingContext") func formattingContext() -> Int { storage.formattingContext }
    @ObjCMethod("setFormattingContext:") func setFormattingContext(_ context: Int) { storage.formattingContext = context }
    @ObjCMethod("isPartialStringValidationEnabled") func isPartialStringValidationEnabled() -> Bool { storage.partialStringValidation }
    @ObjCMethod("setPartialStringValidationEnabled:")
    func setPartialStringValidationEnabled(_ enabled: Bool) { storage.partialStringValidation = enabled }

    /// A handler of the rounding mode, as an NSRoundingMode: ceiling and up
    /// round up, floor, down and half down round down, half even is the
    /// bankers', half up plain; its scale is NSDecimalNoScale.
    @ObjCMethod("roundingBehavior")
    func roundingBehavior() -> UnsafeMutableRawPointer? {
        let modes: [UInt] = [2, 1, 1, 2, 3, 1, 0]
        let mode = storage.attribute(UNUM_ROUNDING_MODE)
        guard let cls = Units.named("NSDecimalNumberHandler") else { return nil }
        typealias Make = @convention(c) (id?, SEL, UInt, Int16, Bool, Bool, Bool, Bool) -> id?
        return unsafeBitCast(ObjC.msgSend, to: Make.self)(
            UnsafeMutableRawPointer(cls),
            ObjC.selector("decimalNumberHandlerWithRoundingMode:scale:raiseOnExactness:raiseOnOverflow:raiseOnUnderflow:raiseOnDivideByZero:"),
            modes.indices.contains(mode) ? modes[mode] : 0, Int16.max, false, false, false, false)
    }

    /// Sets the rounding mode from the behavior's: plain rounds half up,
    /// down down, up up, the bankers' half even. Its scale isn't used, as
    /// on Darwin.
    @ObjCMethod("setRoundingBehavior:")
    func setRoundingBehavior(_ behavior: ObjCObject?) {
        guard let behavior else { return }
        typealias Mode = @convention(c) (id, SEL) -> UInt
        let mode = unsafeBitCast(ObjC.msgSend, to: Mode.self)(behavior.id, ObjC.selector("roundingMode"))
        let modes = [6, 2, 3, 4]
        storage.setAttribute(UNUM_ROUNDING_MODE, mode < 4 ? modes[Int(mode)] : 6)
    }

    // MARK: Attributed strings

    /// What a symbol writes as, as an attributed string: the one set, while
    /// its text is still the symbol, or the symbol without attributes.
    private func attributed(_ key: String, _ symbol: String?) -> UnsafeMutableRawPointer? {
        guard let symbol else { return nil }
        if let kept = storage.held[key], Strings.value(of: ObjC.send(kept, ObjC.selector("string"))) == symbol { return kept }
        return ObjC.autorelease(AttributedStrings.make(AttributedStorage(units: Array(symbol.utf16), attributes: nil), mutable: false))
    }

    /// Keeps an attributed string set for a symbol; its text.
    private func keepAttributed(_ key: String, _ value: ObjCObject?) -> String? {
        storage.keep(key, copying: value?.id)
        return value.flatMap { Strings.value(of: ObjC.send($0.id, ObjC.selector("string"))) }
    }

    @ObjCMethod("attributedStringForZero")
    func attributedStringForZero() -> UnsafeMutableRawPointer? { attributed("attributedStringForZero", storage.zeroSymbol) }
    @ObjCMethod("setAttributedStringForZero:")
    func setAttributedStringForZero(_ value: ObjCObject?) { storage.zeroSymbol = keepAttributed("attributedStringForZero", value) }
    @ObjCMethod("attributedStringForNil")
    func attributedStringForNil() -> UnsafeMutableRawPointer? { attributed("attributedStringForNil", storage.nilSymbol) }
    @ObjCMethod("setAttributedStringForNil:")
    func setAttributedStringForNil(_ value: ObjCObject?) { storage.nilSymbol = keepAttributed("attributedStringForNil", value) ?? "" }
    @ObjCMethod("attributedStringForNotANumber")
    func attributedStringForNotANumber() -> UnsafeMutableRawPointer? { attributed("attributedStringForNotANumber", notANumberSymbol()) }
    @ObjCMethod("setAttributedStringForNotANumber:")
    func setAttributedStringForNotANumber(_ value: ObjCObject?) {
        storage.setSymbol(UNUM_NAN_SYMBOL, keepAttributed("attributedStringForNotANumber", value))
    }

    /// Text attributes, kept for -attributedStringForObjectValue:withDefaultAttributes:;
    /// plain strings don't have them.
    private func textAttributes(_ kind: String) -> UnsafeMutableRawPointer? { storage.held["textAttributesFor" + kind] }
    private func setTextAttributes(_ kind: String, _ value: ObjCObject?) {
        storage.keep("textAttributesFor" + kind, copying: value?.id)
    }

    @ObjCMethod("textAttributesForPositiveValues") func textAttributesForPositiveValues() -> UnsafeMutableRawPointer? { textAttributes("PositiveValues") }
    @ObjCMethod("setTextAttributesForPositiveValues:")
    func setTextAttributesForPositiveValues(_ value: ObjCObject?) { setTextAttributes("PositiveValues", value) }
    @ObjCMethod("textAttributesForNegativeValues") func textAttributesForNegativeValues() -> UnsafeMutableRawPointer? { textAttributes("NegativeValues") }
    @ObjCMethod("setTextAttributesForNegativeValues:")
    func setTextAttributesForNegativeValues(_ value: ObjCObject?) { setTextAttributes("NegativeValues", value) }
    @ObjCMethod("textAttributesForZero") func textAttributesForZero() -> UnsafeMutableRawPointer? { textAttributes("Zero") }
    @ObjCMethod("setTextAttributesForZero:") func setTextAttributesForZero(_ value: ObjCObject?) { setTextAttributes("Zero", value) }
    @ObjCMethod("textAttributesForNil") func textAttributesForNil() -> UnsafeMutableRawPointer? { textAttributes("Nil") }
    @ObjCMethod("setTextAttributesForNil:") func setTextAttributesForNil(_ value: ObjCObject?) { setTextAttributes("Nil", value) }
    @ObjCMethod("textAttributesForNotANumber") func textAttributesForNotANumber() -> UnsafeMutableRawPointer? { textAttributes("NotANumber") }
    @ObjCMethod("setTextAttributesForNotANumber:")
    func setTextAttributesForNotANumber(_ value: ObjCObject?) { setTextAttributes("NotANumber", value) }
    @ObjCMethod("textAttributesForPositiveInfinity")
    func textAttributesForPositiveInfinity() -> UnsafeMutableRawPointer? { textAttributes("PositiveInfinity") }
    @ObjCMethod("setTextAttributesForPositiveInfinity:")
    func setTextAttributesForPositiveInfinity(_ value: ObjCObject?) { setTextAttributes("PositiveInfinity", value) }
    @ObjCMethod("textAttributesForNegativeInfinity")
    func textAttributesForNegativeInfinity() -> UnsafeMutableRawPointer? { textAttributes("NegativeInfinity") }
    @ObjCMethod("setTextAttributesForNegativeInfinity:")
    func setTextAttributesForNegativeInfinity(_ value: ObjCObject?) { setTextAttributes("NegativeInfinity", value) }

    // MARK: Legacy (Mac OS X 10.0) behavior

    /// The grouping separator and whether it's used, by their 10.0 names.
    @ObjCMethod("thousandSeparator") func thousandSeparator() -> String { groupingSeparator() }
    @ObjCMethod("setThousandSeparator:") func setThousandSeparator(_ value: String?) { setGroupingSeparator(value) }
    @ObjCMethod("hasThousandSeparators") func hasThousandSeparators() -> Bool { usesGroupingSeparator() }
    @ObjCMethod("setHasThousandSeparators:") func setHasThousandSeparators(_ value: Bool) { setUsesGroupingSeparator(value) }
    /// Kept: the symbols are the locale's either way.
    @ObjCMethod("localizesFormat") func localizesFormat() -> Bool { storage.localizesFormat }
    @ObjCMethod("setLocalizesFormat:") func setLocalizesFormat(_ value: Bool) { storage.localizesFormat = value }

    /// "positive;zero;negative": the zero part is the zero symbol, or zero
    /// as the formatter writes it.
    @ObjCMethod("format")
    func format() -> String {
        let zero = storage.zeroSymbol ?? Numbers.make(nil, .signed(0)).flatMap { storage.string(from: $0) } ?? "0"
        return storage.positiveFormat + ";" + zero + ";" + storage.negativeFormat
    }

    /// Sets the positive format, then: with three parts, the zero symbol
    /// and the negative format; with two, the negative format; with one,
    /// that format with a minus sign. Without a zero part, zero is kept as
    /// the formatter then writes it, as on Darwin.
    @ObjCMethod("setFormat:")
    func setFormat(_ format: String?) {
        guard let format else { return }
        let parts = format.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        let positive = parts[0]
        let negative = parts.count >= 3 ? parts[2] : parts.count == 2 ? parts[1] : "-" + positive
        storage.pattern = positive + ";" + negative
        storage.explicitNegative = negative
        storage.changed()
        storage.zeroSymbol = parts.count >= 3 ? parts[1] : Numbers.make(nil, .signed(0)).flatMap { storage.string(from: $0) }
    }
}
