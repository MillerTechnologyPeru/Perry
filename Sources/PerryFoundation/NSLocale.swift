import CPerryFoundation
import FoundationEssentials
import FoundationInternationalization
import Glibc
import PerryObjCInterop
import _FoundationICU

/// An NSLocale's locale: swift-foundation's Locale.
final class LocaleStorage {
    let locale: Locale

    init(_ locale: Locale) {
        self.locale = locale
    }
}

enum Locales {
    nonisolated(unsafe) static var localeClass: Class!

    /// The current locale: the environment's language, as LANG and its
    /// overrides name it, or en_US, an iOS device's own, for C and POSIX.
    static let current: Locale = {
        let environment = ["LC_ALL", "LC_MESSAGES", "LANG"].lazy.compactMap { name -> String? in
            guard let value = getenv(name) else { return nil }
            let string = String(decoding: UnsafeRawBufferPointer(start: value, count: strlen(value)), as: UTF8.self)
            return string.isEmpty ? nil : string
        }.first
        let identifier = environment.map { String($0.split(separator: ".").first ?? "") } ?? ""
        return Locale(identifier: ["", "C", "POSIX"].contains(identifier) ? "en_US" : identifier)
    }()

    /// The locale, or the current one for nil, as formatters take it.
    static func locale(_ object: id?) -> Locale {
        Storage.get(object, as: LocaleStorage.self)?.locale ?? current
    }

    static func autoreleased(_ locale: Locale) -> id {
        let object = Storage.allocate(UnsafeMutableRawPointer(localeClass))!
        Storage.set(object, LocaleStorage(locale))
        return ObjC.autorelease(object)!
    }

    static func strings(_ values: [String]) -> ObjCObject {
        ObjCObject(Arrays.autoreleased(values.map { Strings.autoreleased($0) }))
    }

    /// An identifier's parts, keyed as CoreFoundation keys them, read by
    /// ICU as CFLocaleCreateComponentsFromLocaleIdentifier does.
    static func components(_ identifier: String) -> [String: String] {
        typealias Part = (UnsafePointer<CChar>?, UnsafeMutablePointer<CChar>?, Int32,
                          UnsafeMutablePointer<UErrorCode>?) -> Int32
        func part(_ read: Part) -> String? {
            var buffer = [CChar](repeating: 0, count: 157)
            var status = U_ZERO_ERROR
            let length = identifier.withCString { read($0, &buffer, Int32(buffer.count), &status) }
            guard !ICU.failed(status), length > 0 else { return nil }
            return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        var components: [String: String] = [:]
        components[LocaleKeys.NSLocaleLanguageCode] = part(swift_uloc_getLanguage)
        components[LocaleKeys.NSLocaleScriptCode] = part(swift_uloc_getScript)
        components[LocaleKeys.NSLocaleCountryCode] = part(swift_uloc_getCountry)
        components[LocaleKeys.NSLocaleVariantCode] = part(swift_uloc_getVariant)
        // Keywords ("@calendar=japanese") are keyed by their names.
        if let at = identifier.firstIndex(of: "@") {
            for pair in identifier[identifier.index(after: at)...].split(separator: ";") {
                let halves = pair.split(separator: "=", maxSplits: 1)
                if halves.count == 2 { components[String(halves[0])] = String(halves[1]) }
            }
        }
        return components
    }

    /// The reverse: language_Script_COUNTRY_VARIANT@keyword=value;…
    static func identifier(_ components: [String: String]) -> String {
        var identifier = components[LocaleKeys.NSLocaleLanguageCode] ?? ""
        if let script = components[LocaleKeys.NSLocaleScriptCode] { identifier += "_" + script }
        if let country = components[LocaleKeys.NSLocaleCountryCode] { identifier += "_" + country }
        if let variant = components[LocaleKeys.NSLocaleVariantCode] {
            identifier += (components[LocaleKeys.NSLocaleCountryCode] == nil ? "__" : "_") + variant
        }
        let parts: Set<String> = [LocaleKeys.NSLocaleLanguageCode, LocaleKeys.NSLocaleScriptCode,
                                  LocaleKeys.NSLocaleCountryCode, LocaleKeys.NSLocaleVariantCode]
        let keywords = components.filter { !parts.contains($0.key) }.sorted { $0.key < $1.key }
        if !keywords.isEmpty { identifier += "@" + keywords.map { "\($0.key)=\($0.value)" }.joined(separator: ";") }
        return identifier
    }

    /// A string as an object, or nil.
    static func object(_ value: String?) -> UnsafeMutableRawPointer? {
        value.map { Strings.autoreleased($0) }
    }
}

/// NSLocale's keys, CoreFoundation's kCFLocale… values.
@ObjCConstants
enum LocaleKeys {
    static let NSLocaleIdentifier = "locale:id"
    static let NSLocaleLanguageCode = "kCFLocaleLanguageCodeKey"
    static let NSLocaleCountryCode = "kCFLocaleCountryCodeKey"
    static let NSLocaleScriptCode = "kCFLocaleScriptCodeKey"
    static let NSLocaleVariantCode = "kCFLocaleVariantCodeKey"
    static let NSLocaleExemplarCharacterSet = "locale:exemplar characters set"
    static let NSLocaleCalendar = "kCFLocaleCalendarKey"
    static let NSLocaleCollationIdentifier = "collation"
    static let NSLocaleUsesMetricSystem = "locale:uses metric"
    static let NSLocaleMeasurementSystem = "kCFLocaleMeasurementSystemKey"
    static let NSLocaleDecimalSeparator = "locale:decimal separator"
    static let NSLocaleGroupingSeparator = "locale:grouping separator"
    static let NSLocaleCurrencySymbol = "locale:currency symbol"
    static let NSLocaleCurrencyCode = "currency"
    static let NSLocaleCollatorIdentifier = "locale:collator id"
    static let NSLocaleQuotationBeginDelimiterKey = "kCFLocaleQuotationBeginDelimiterKey"
    static let NSLocaleQuotationEndDelimiterKey = "kCFLocaleQuotationEndDelimiterKey"
    static let NSLocaleAlternateQuotationBeginDelimiterKey = "kCFLocaleAlternateQuotationBeginDelimiterKey"
    static let NSLocaleAlternateQuotationEndDelimiterKey = "kCFLocaleAlternateQuotationEndDelimiterKey"
    static let NSCurrentLocaleDidChangeNotification = "kCFLocaleCurrentLocaleDidChangeNotification"
    // CoreFoundation's names for the same objects.
    static let kCFLocaleIdentifier = NSLocaleIdentifier
    static let kCFLocaleLanguageCode = NSLocaleLanguageCode
    static let kCFLocaleCountryCode = NSLocaleCountryCode
    static let kCFLocaleScriptCode = NSLocaleScriptCode
    static let kCFLocaleVariantCode = NSLocaleVariantCode
    static let kCFLocaleExemplarCharacterSet = NSLocaleExemplarCharacterSet
    static let kCFLocaleCalendar = NSLocaleCalendar
    static let kCFLocaleCollationIdentifier = NSLocaleCollationIdentifier
    static let kCFLocaleUsesMetricSystem = NSLocaleUsesMetricSystem
    static let kCFLocaleMeasurementSystem = NSLocaleMeasurementSystem
    static let kCFLocaleDecimalSeparator = NSLocaleDecimalSeparator
    static let kCFLocaleGroupingSeparator = NSLocaleGroupingSeparator
    static let kCFLocaleCurrencySymbol = NSLocaleCurrencySymbol
    static let kCFLocaleCurrencyCode = NSLocaleCurrencyCode
    static let kCFLocaleCollatorIdentifier = NSLocaleCollatorIdentifier
    static let kCFLocaleCurrentLocaleDidChangeNotification = NSCurrentLocaleDidChangeNotification
}

/// NSLocale.
@ObjCClass("NSLocale")
public final class NSLocale: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Locales.localeClass = cls.storage
    }

    var locale: Locale { Locales.locale(objcObject) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Locales.localeClass)
    }

    @ObjCClassMethod("localeWithLocaleIdentifier:")
    static func locale(_ cls: ObjCClass, identifier: String) -> UnsafeMutableRawPointer {
        Locales.autoreleased(Locale(identifier: identifier))
    }

    @ObjCMethod("initWithLocaleIdentifier:")
    func initialize(identifier: String) -> Self {
        Storage.set(objcObject, LocaleStorage(Locale(identifier: identifier)))
        return self
    }

    @ObjCClassMethod("currentLocale") static func current() -> UnsafeMutableRawPointer { Locales.autoreleased(Locales.current) }
    @ObjCClassMethod("autoupdatingCurrentLocale") static func autoupdating() -> UnsafeMutableRawPointer { Locales.autoreleased(Locales.current) }
    @ObjCClassMethod("systemLocale") static func system() -> UnsafeMutableRawPointer { Locales.autoreleased(Locale(identifier: "")) }

    @ObjCClassMethod("availableLocaleIdentifiers") static func available() -> ObjCObject { Locales.strings(Locale.availableIdentifiers) }

    @ObjCClassMethod("ISOLanguageCodes")
    static func languageCodes() -> ObjCObject { Locales.strings(Locale.LanguageCode.isoLanguageCodes.map(\.identifier)) }

    @ObjCClassMethod("ISOCountryCodes")
    static func countryCodes() -> ObjCObject { Locales.strings(Locale.Region.isoRegions.map(\.identifier)) }

    @ObjCClassMethod("ISOCurrencyCodes")
    static func currencyCodes() -> ObjCObject { Locales.strings(Locale.Currency.isoCurrencies.map(\.identifier)) }

    @ObjCClassMethod("commonISOCurrencyCodes")
    static func commonCurrencyCodes() -> ObjCObject { Locales.strings(Locale.commonISOCurrencyCodes) }

    @ObjCClassMethod("preferredLanguages") static func preferredLanguages() -> ObjCObject { Locales.strings(Locale.preferredLanguages) }

    @ObjCClassMethod("componentsFromLocaleIdentifier:")
    static func components(fromIdentifier identifier: String) -> ObjCObject {
        let components = Locales.components(identifier).sorted { $0.key < $1.key }
        return ObjCObject(Dictionaries.autoreleased(components.map {
            (key: Strings.autoreleased($0.key), value: Strings.autoreleased($0.value))
        }))
    }

    @ObjCClassMethod("localeIdentifierFromComponents:")
    static func identifier(fromComponents dictionary: ObjCObject) -> String {
        var components: [String: String] = [:]
        for entry in Dictionaries.entries(dictionary.id) {
            if let key = Strings.value(of: entry.key), let value = Strings.value(of: entry.value) { components[key] = value }
        }
        return Locales.identifier(components)
    }

    @ObjCClassMethod("canonicalLocaleIdentifierFromString:")
    static func canonicalIdentifier(_ string: String) -> String { Locale.canonicalIdentifier(from: string) }

    @ObjCClassMethod("canonicalLanguageIdentifierFromString:")
    static func canonicalLanguageIdentifier(_ string: String) -> String { Locale.canonicalLanguageIdentifier(from: string) }

    /// NSLocaleLanguageDirection: left to right is 1, right to left 2.
    @ObjCClassMethod("characterDirectionForLanguage:")
    static func characterDirection(_ language: String) -> UInt {
        switch Locale.Language(identifier: language).characterDirection {
        case .rightToLeft: return 2
        case .leftToRight: return 1
        case .topToBottom: return 3
        case .bottomToTop: return 4
        default: return 0
        }
    }

    @ObjCMethod("localeIdentifier") func localeIdentifier() -> String { locale.identifier }
    @ObjCMethod("languageCode") func languageCode() -> String { locale.language.languageCode?.identifier ?? "" }
    @ObjCMethod("countryCode") func countryCode() -> String? { locale.region?.identifier }
    @ObjCMethod("regionCode") func regionCode() -> String? { locale.region?.identifier }
    @ObjCMethod("scriptCode") func scriptCode() -> String? { locale.language.script?.identifier }
    @ObjCMethod("variantCode") func variantCode() -> String? { locale.variant?.identifier }
    @ObjCMethod("collationIdentifier") func collationIdentifier() -> String? { locale.collation.identifier }
    @ObjCMethod("calendarIdentifier") func calendarIdentifier() -> String { CalendarIdentifiers.name(locale.calendar.identifier) }
    @ObjCMethod("decimalSeparator") func decimalSeparator() -> String { locale.decimalSeparator ?? "." }
    @ObjCMethod("groupingSeparator") func groupingSeparator() -> String { locale.groupingSeparator ?? "" }
    @ObjCMethod("currencySymbol") func currencySymbol() -> String { locale.currencySymbol ?? "" }
    @ObjCMethod("currencyCode") func currencyCode() -> String? { locale.currency?.identifier }
    @ObjCMethod("usesMetricSystem") func usesMetricSystem() -> Bool { locale.measurementSystem != .us }
    @ObjCMethod("quotationBeginDelimiter") func quotationBegin() -> String { locale.quotationBeginDelimiter ?? "\u{201C}" }
    @ObjCMethod("quotationEndDelimiter") func quotationEnd() -> String { locale.quotationEndDelimiter ?? "\u{201D}" }

    @ObjCMethod("alternateQuotationBeginDelimiter")
    func alternateQuotationBegin() -> String { locale.alternateQuotationBeginDelimiter ?? "\u{2018}" }

    @ObjCMethod("alternateQuotationEndDelimiter")
    func alternateQuotationEnd() -> String { locale.alternateQuotationEndDelimiter ?? "\u{2019}" }

    @ObjCMethod("calendar")
    func calendar() -> UnsafeMutableRawPointer { Calendars.autoreleased(locale.calendar) }

    @ObjCMethod("objectForKey:")
    func object(forKey key: ObjCObject?) -> UnsafeMutableRawPointer? {
        let locale = self.locale
        switch Strings.value(of: key?.id) {
        case LocaleKeys.NSLocaleIdentifier: return Locales.object(locale.identifier)
        case LocaleKeys.NSLocaleLanguageCode: return Locales.object(locale.language.languageCode?.identifier)
        case LocaleKeys.NSLocaleCountryCode: return Locales.object(locale.region?.identifier)
        case LocaleKeys.NSLocaleScriptCode: return Locales.object(locale.language.script?.identifier)
        case LocaleKeys.NSLocaleVariantCode: return Locales.object(locale.variant?.identifier)
        case LocaleKeys.NSLocaleCalendar: return Calendars.autoreleased(locale.calendar)
        case LocaleKeys.NSLocaleCollationIdentifier: return Locales.object(locale.collation.identifier)
        case LocaleKeys.NSLocaleUsesMetricSystem:
            return perry_foundation_boolean(locale.measurementSystem != .us ? 1 : 0)
        case LocaleKeys.NSLocaleMeasurementSystem:
            return Locales.object(locale.measurementSystem == .us ? "U.S." : locale.measurementSystem == .uk ? "U.K." : "Metric")
        case LocaleKeys.NSLocaleDecimalSeparator: return Locales.object(locale.decimalSeparator)
        case LocaleKeys.NSLocaleGroupingSeparator: return Locales.object(locale.groupingSeparator)
        case LocaleKeys.NSLocaleCurrencySymbol: return Locales.object(locale.currencySymbol)
        case LocaleKeys.NSLocaleCurrencyCode: return Locales.object(locale.currency?.identifier)
        case LocaleKeys.NSLocaleCollatorIdentifier: return Locales.object(locale.collatorIdentifier)
        case LocaleKeys.NSLocaleQuotationBeginDelimiterKey: return Locales.object(locale.quotationBeginDelimiter)
        case LocaleKeys.NSLocaleQuotationEndDelimiterKey: return Locales.object(locale.quotationEndDelimiter)
        case LocaleKeys.NSLocaleAlternateQuotationBeginDelimiterKey: return Locales.object(locale.alternateQuotationBeginDelimiter)
        case LocaleKeys.NSLocaleAlternateQuotationEndDelimiterKey: return Locales.object(locale.alternateQuotationEndDelimiter)
        default: return nil
        }
    }

    @ObjCMethod("displayNameForKey:value:")
    func displayName(forKey key: ObjCObject?, value: ObjCObject?) -> String? {
        guard let value = Strings.value(of: value?.id) else { return nil }
        let locale = self.locale
        switch Strings.value(of: key?.id) {
        case LocaleKeys.NSLocaleIdentifier: return locale.localizedString(forIdentifier: value)
        case LocaleKeys.NSLocaleLanguageCode: return locale.localizedString(forLanguageCode: value)
        case LocaleKeys.NSLocaleCountryCode: return locale.localizedString(forRegionCode: value)
        case LocaleKeys.NSLocaleScriptCode: return locale.localizedString(forScriptCode: value)
        case LocaleKeys.NSLocaleVariantCode: return locale.localizedString(forVariantCode: value)
        case LocaleKeys.NSLocaleCurrencyCode: return locale.localizedString(forCurrencyCode: value)
        case LocaleKeys.NSLocaleCollationIdentifier: return locale.localizedString(forCollationIdentifier: value)
        case LocaleKeys.NSLocaleCurrencySymbol: return locale.localizedString(forCurrencyCode: value)
        default: return nil
        }
    }

    @ObjCMethod("localizedStringForLocaleIdentifier:")
    func localizedString(forLocaleIdentifier value: String) -> String? { locale.localizedString(forIdentifier: value) }

    @ObjCMethod("localizedStringForLanguageCode:")
    func localizedString(forLanguageCode value: String) -> String? { locale.localizedString(forLanguageCode: value) }

    @ObjCMethod("localizedStringForCountryCode:")
    func localizedString(forCountryCode value: String) -> String? { locale.localizedString(forRegionCode: value) }

    @ObjCMethod("localizedStringForScriptCode:")
    func localizedString(forScriptCode value: String) -> String? { locale.localizedString(forScriptCode: value) }

    @ObjCMethod("localizedStringForVariantCode:")
    func localizedString(forVariantCode value: String) -> String? { locale.localizedString(forVariantCode: value) }

    @ObjCMethod("localizedStringForCurrencyCode:")
    func localizedString(forCurrencyCode value: String) -> String? { locale.localizedString(forCurrencyCode: value) }

    @ObjCMethod("localizedStringForCalendarIdentifier:")
    func localizedString(forCalendarIdentifier value: String) -> String? {
        CalendarIdentifiers.identifier(value).flatMap { locale.localizedString(for: $0) }
    }

    @ObjCMethod("isEqual:") func isEqual(_ other: ObjCObject?) -> Bool {
        guard let other = Storage.get(other?.id, as: LocaleStorage.self) else { return false }
        return other.locale.identifier == locale.identifier
    }

    @ObjCMethod("hash") func hash() -> UInt { Strings.hash(locale.identifier) }
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjC.retain(objcObject)! }

    @ObjCMethod("description")
    func description() -> String { "<NSLocale: \(objcObject)> \(locale.identifier) (fixed)" }
}
