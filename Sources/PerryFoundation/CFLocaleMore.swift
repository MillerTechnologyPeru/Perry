import CPerryFoundation
import FoundationEssentials
import FoundationInternationalization
import PerryObjCInterop

// The rest of CFLocale: the ISO code lists, available identifiers, display
// names, canonical identifiers, the old Mac OS Script Manager's and
// Windows' codes for locales, and languages' directions.

enum CFLocaleMore {
    /// An array of strings, +1, leaving nothing in the caller's pool.
    static func strings(_ values: [String]) -> id? {
        ObjC.autoreleasepool { ObjC.retain(Arrays.autoreleased(values.map { Strings.autoreleased($0) })) }
    }

    /// A string, +1.
    static func string(_ value: String?) -> id? { value.map(Strings.make) }

    /// CFLocaleLanguageDirection: unknown 0, left to right 1, right to left
    /// 2, top to bottom 3, bottom to top 4.
    static func direction(_ direction: Locale.LanguageDirection) -> Int {
        switch direction {
        case .leftToRight: return 1
        case .rightToLeft: return 2
        case .topToBottom: return 3
        case .bottomToTop: return 4
        default: return 0
        }
    }

    /// The Script Manager's language codes (LangCode, langEnglish 0 on),
    /// as the identifiers CoreFoundation gives them.
    static let languages: [Int16: String] = [
        0: "en", 1: "fr", 2: "de", 3: "it", 4: "nl", 5: "sv", 6: "es", 7: "da", 8: "pt", 9: "nb",
        10: "he", 11: "ja", 12: "ar", 13: "fi", 14: "el", 15: "is", 16: "mt", 17: "tr", 18: "hr", 19: "zh_Hant",
        20: "ur", 21: "hi", 22: "th", 23: "ko", 24: "lt", 25: "pl", 26: "hu", 27: "et", 28: "lv", 29: "se",
        30: "fo", 31: "fa", 32: "ru", 33: "zh_Hans", 34: "nl_BE", 35: "ga", 36: "sq", 37: "ro", 38: "cs", 39: "sk",
        40: "sl", 41: "yi", 42: "sr", 43: "mk", 44: "bg", 45: "uk", 46: "be", 47: "uz_Cyrl", 48: "kk", 49: "az_Cyrl",
        50: "az_Arab", 51: "hy", 52: "ka", 53: "ro_MD", 54: "ky", 55: "tg_Cyrl", 56: "tk", 57: "mn_Mong", 58: "mn_Cyrl", 59: "ps",
        60: "ku", 61: "ks", 62: "sd", 63: "bo", 64: "ne", 65: "sa", 66: "mr", 67: "bn", 68: "as", 69: "gu",
        70: "pa", 71: "or", 72: "ml", 73: "kn", 74: "ta", 75: "te", 76: "si", 77: "my", 78: "km", 79: "lo",
        80: "vi", 81: "id", 82: "fil", 83: "ms", 84: "ms_Arab", 85: "am", 86: "ti", 87: "om", 88: "so", 89: "sw",
        90: "rw", 91: "rn", 92: "ny", 93: "mg", 94: "eo",
        128: "cy", 129: "eu", 130: "ca", 131: "la", 132: "qu", 133: "gn", 134: "ay", 135: "tt_Cyrl", 136: "ug", 137: "dz",
        138: "jv", 139: "su", 140: "gl", 141: "af", 142: "br", 143: "iu", 144: "gd", 145: "gv", 146: "ga_Latg", 147: "to",
        148: "grc", 149: "kl", 150: "az_Latn", 151: "nn",
    ]

    /// The Script Manager's region codes (RegionCode, verUS 0 on), as
    /// locale identifiers.
    static let regions: [Int16: String] = [
        0: "en_US", 1: "fr_FR", 2: "en_GB", 3: "de_DE", 4: "it_IT", 5: "nl_NL", 6: "nl_BE", 7: "sv_SE", 8: "es_ES", 9: "da_DK",
        10: "pt_PT", 11: "fr_CA", 12: "nb_NO", 13: "he_IL", 14: "ja_JP", 15: "en_AU", 16: "ar", 17: "fi_FI", 18: "fr_CH", 19: "de_CH",
        20: "el_GR", 21: "is_IS", 22: "mt_MT", 23: "el_CY", 24: "tr_TR", 25: "hr_HR", 33: "hi_IN", 34: "ur_PK", 36: "it_CH",
        37: "en_001", 39: "ro_RO", 40: "grc", 41: "lt_LT", 42: "pl_PL", 43: "hu_HU", 44: "et_EE", 45: "lv_LV", 46: "se",
        47: "fo_FO", 48: "fa_IR", 49: "ru_RU", 50: "ga_IE", 51: "ko_KR", 52: "zh_CN", 53: "zh_TW", 54: "th_TH", 56: "cs_CZ",
        57: "sk_SK", 59: "hu_HU", 60: "bn", 61: "be_BY", 62: "uk_UA", 64: "el_GR", 65: "sr_RS", 66: "sl_SI", 67: "mk_MK",
        68: "hr_HR", 70: "de_DE", 71: "pt_BR", 72: "bg_BG", 73: "ca_ES", 75: "gd", 76: "gv", 77: "br", 78: "iu_CA", 79: "cy",
        81: "ga_IE", 82: "en_CA", 83: "dz_BT", 84: "hy_AM", 85: "ka_GE", 86: "es_419", 88: "to_TO", 91: "fr", 92: "de_AT",
        94: "gu_IN", 95: "pa", 96: "ur_IN", 97: "vi_VN", 98: "fr_BE", 99: "uz_UZ", 100: "en_SG", 101: "nn_NO", 102: "af_ZA",
        103: "eo", 104: "mr_IN", 105: "bo", 106: "ne_NP", 107: "kl", 108: "en_IE",
    ]

    /// The Script Manager's script (and Mac encoding) for a language: Roman
    /// 0 for those not listed.
    static let scripts: [String: Int16] = [
        "ja": 1, "zh_Hant": 2, "ko": 3, "ar": 4, "fa": 4, "ur": 4, "ps": 4, "ku": 4, "sd": 4, "ug": 4, "ms_Arab": 4, "az_Arab": 4,
        "he": 5, "yi": 5, "el": 6, "grc": 6, "ru": 7, "uk": 7, "bg": 7, "be": 7, "sr": 7, "mk": 7, "kk": 7, "ky": 7,
        "uz_Cyrl": 7, "az_Cyrl": 7, "tg_Cyrl": 7, "mn_Cyrl": 7, "tt_Cyrl": 7, "ro_MD": 7, "hi": 9, "mr": 9, "ne": 9, "sa": 9,
        "pa": 10, "gu": 11, "or": 12, "bn": 13, "as": 13, "ta": 14, "te": 15, "kn": 16, "ml": 17, "si": 18, "my": 19, "km": 20,
        "th": 21, "lo": 22, "ka": 23, "hy": 24, "zh_Hans": 25, "bo": 26, "dz": 26, "mn_Mong": 27, "am": 28, "ti": 28, "om": 28,
        "cs": 29, "sk": 29, "pl": 29, "hu": 29, "et": 29, "lv": 29, "lt": 29, "sl": 29, "vi": 30,
    ]

    /// Mac encodings that differ from the language's script's.
    static let encodings: [String: UInt32] = [
        "tr": 35, "hr": 36, "sl": 36, "is": 37, "fo": 37, "ro": 38, "cy": 39, "gd": 40, "gv": 40, "ga_Latg": 40,
        "fa": 0x8C, "uk": 0x98, "iu": 0xEC, "ga": 39, "br": 39,
    ]

    /// Windows locale codes (LCIDs) and their locales.
    static let windowsLocales: [UInt32: String] = [
        0x0401: "ar_SA", 0x0402: "bg_BG", 0x0403: "ca_ES", 0x0404: "zh_TW", 0x0405: "cs_CZ", 0x0406: "da_DK", 0x0407: "de_DE",
        0x0408: "el_GR", 0x0409: "en_US", 0x040A: "es_ES", 0x040B: "fi_FI", 0x040C: "fr_FR", 0x040D: "he_IL", 0x040E: "hu_HU",
        0x040F: "is_IS", 0x0410: "it_IT", 0x0411: "ja_JP", 0x0412: "ko_KR", 0x0413: "nl_NL", 0x0414: "nb_NO", 0x0415: "pl_PL",
        0x0416: "pt_BR", 0x0418: "ro_RO", 0x0419: "ru_RU", 0x041A: "hr_HR", 0x041B: "sk_SK", 0x041C: "sq_AL", 0x041D: "sv_SE",
        0x041E: "th_TH", 0x041F: "tr_TR", 0x0420: "ur_PK", 0x0421: "id_ID", 0x0422: "uk_UA", 0x0423: "be_BY", 0x0424: "sl_SI",
        0x0425: "et_EE", 0x0426: "lv_LV", 0x0427: "lt_LT", 0x0429: "fa_IR", 0x042A: "vi_VN", 0x042B: "hy_AM", 0x042D: "eu_ES",
        0x042F: "mk_MK", 0x0436: "af_ZA", 0x0437: "ka_GE", 0x0438: "fo_FO", 0x0439: "hi_IN", 0x043A: "mt_MT", 0x043E: "ms_MY",
        0x043F: "kk_KZ", 0x0441: "sw_KE", 0x0445: "bn_IN", 0x0446: "pa_IN", 0x0447: "gu_IN", 0x0449: "ta_IN", 0x044A: "te_IN",
        0x044B: "kn_IN", 0x044C: "ml_IN", 0x044E: "mr_IN", 0x0452: "cy_GB", 0x0456: "gl_ES", 0x0461: "ne_NP", 0x0464: "fil_PH",
        0x0801: "ar_IQ", 0x0804: "zh_CN", 0x0807: "de_CH", 0x0809: "en_GB", 0x080A: "es_MX", 0x080C: "fr_BE", 0x0810: "it_CH",
        0x0813: "nl_BE", 0x0814: "nn_NO", 0x0816: "pt_PT", 0x083C: "ga_IE", 0x0C01: "ar_EG", 0x0C04: "zh_HK", 0x0C07: "de_AT",
        0x0C09: "en_AU", 0x0C0A: "es_ES", 0x0C0C: "fr_CA", 0x0C1A: "sr_RS", 0x1004: "zh_SG", 0x1009: "en_CA", 0x100C: "fr_CH",
        0x1409: "en_NZ", 0x1809: "en_IE", 0x1C09: "en_ZA", 0x2C0A: "es_AR", 0x4009: "en_IN", 0x4809: "en_SG",
    ]
}

/// The locale identifiers there is data for, +1.
@c(_CFLocaleCopyAvailableLocaleIdentifiers)
public func CFLocaleCopyAvailableLocaleIdentifiers() -> id? { CFLocaleMore.strings(Locale.availableIdentifiers) }

/// ISO 639 language codes, +1.
@c(_CFLocaleCopyISOLanguageCodes)
public func CFLocaleCopyISOLanguageCodes() -> id? {
    CFLocaleMore.strings(Locale.LanguageCode.isoLanguageCodes.map(\.identifier))
}

/// ISO 3166 country codes, +1.
@c(_CFLocaleCopyISOCountryCodes)
public func CFLocaleCopyISOCountryCodes() -> id? { CFLocaleMore.strings(Locale.Region.isoRegions.map(\.identifier)) }

/// ISO 4217 currency codes, +1.
@c(_CFLocaleCopyISOCurrencyCodes)
public func CFLocaleCopyISOCurrencyCodes() -> id? { CFLocaleMore.strings(Locale.Currency.isoCurrencies.map(\.identifier)) }

/// The currency codes in common use, +1.
@c(_CFLocaleCopyCommonISOCurrencyCodes)
public func CFLocaleCopyCommonISOCurrencyCodes() -> id? { CFLocaleMore.strings(Locale.commonISOCurrencyCodes) }

/// A value of a locale property (identifier, language, country, script,
/// variant, currency, collation) named in the display locale's language,
/// +1; NULL where it has no name.
@c(_CFLocaleCopyDisplayNameForPropertyValue)
public func CFLocaleCopyDisplayNameForPropertyValue(_ locale: id?, _ key: id?, _ value: id?) -> id? {
    guard let locale, value != nil else { return nil }
    return ObjC.autoreleasepool { ObjC.retain(ObjC.send(locale, ObjC.selector("displayNameForKey:value:"), key, value)) }
}

/// The canonical form of a locale identifier, by ICU, +1.
@c(_CFLocaleCreateCanonicalLocaleIdentifierFromString)
public func CFLocaleCreateCanonicalLocaleIdentifierFromString(_ allocator: UnsafeRawPointer?, _ identifier: id?) -> id? {
    guard let string = Strings.value(of: identifier) else { return nil }
    return Strings.make(CFLocaleMore.canonical(string))
}

extension CFLocaleMore {
    /// An identifier with each part in its case, as Darwin gives it: the
    /// language lowercase, a script capitalized and after a hyphen, a region
    /// uppercase and a variant lowercase. The other separators stay as they
    /// are, hyphens or underscores.
    static func canonical(_ identifier: String) -> String {
        var parts: [(separator: String, text: String)] = []
        var current = "", separator = ""
        for character in identifier {
            if character == "-" || character == "_" {
                parts.append((separator, current))
                (separator, current) = (String(character), "")
            } else {
                current.append(character)
            }
        }
        parts.append((separator, current))
        var result = ""
        for (index, part) in parts.enumerated() {
            let text = part.text
            if index == 0 {
                result += text.lowercased()
            } else if text.count == 4, text.allSatisfy(\.isLetter) {
                result += "-" + text.prefix(1).uppercased() + text.dropFirst().lowercased()
            } else if (text.count == 2 && text.allSatisfy(\.isLetter)) || (text.count == 3 && text.allSatisfy(\.isNumber)) {
                result += part.separator + text.uppercased()
            } else {
                result += part.separator + text.lowercased()
            }
        }
        return result
    }
}

/// The identifier of the old Mac OS Script Manager's language and region
/// codes, +1: the language's, with the region's country; the region's own
/// for no language (-1); NULL if neither is known.
@c(_CFLocaleCreateCanonicalLocaleIdentifierFromScriptManagerCodes)
public func CFLocaleCreateCanonicalLocaleIdentifierFromScriptManagerCodes(_ allocator: UnsafeRawPointer?, _ language: Int16,
                                                                          _ region: Int16) -> id? {
    let regionIdentifier = CFLocaleMore.regions[region]
    guard let languageIdentifier = CFLocaleMore.languages[language] else { return CFLocaleMore.string(regionIdentifier) }
    guard let regionIdentifier else { return Strings.make(languageIdentifier) }
    let country = Locales.components(regionIdentifier)[LocaleKeys.NSLocaleCountryCode]
    let hasCountry = Locales.components(languageIdentifier)[LocaleKeys.NSLocaleCountryCode] != nil
    guard let country, !hasCountry else { return Strings.make(languageIdentifier) }
    return Strings.make(languageIdentifier + "_" + country)
}

/// A locale's Script Manager language, region and script codes and Mac
/// string encoding, each -1 (or kCFStringEncodingInvalidId) where there is
/// none; false when the language has no code.
@c(_CFLocaleGetLanguageRegionEncodingForLocaleIdentifier)
public func CFLocaleGetLanguageRegionEncodingForLocaleIdentifier(_ identifier: id?, _ languageCode: UnsafeMutablePointer<Int16>?,
                                                                 _ regionCode: UnsafeMutablePointer<Int16>?,
                                                                 _ scriptCode: UnsafeMutablePointer<Int16>?,
                                                                 _ encoding: UnsafeMutablePointer<UInt32>?) -> Bool {
    guard let string = Strings.value(of: identifier) else { return false }
    let canonical = Locale.canonicalIdentifier(from: string)
    let components = Locales.components(canonical)
    guard let language = components[LocaleKeys.NSLocaleLanguageCode] else { return false }
    let script = components[LocaleKeys.NSLocaleScriptCode]
    let country = components[LocaleKeys.NSLocaleCountryCode]
    // The most specific of language_Script, language_COUNTRY (nl_BE) and
    // language that has a code; Chinese by its script, or its country's.
    var candidates: [String] = []
    if let script { candidates.append(language + "_" + script) }
    if let country { candidates.append(language + "_" + country) }
    if language == "zh" {
        let traditional = script == "Hant" || (script == nil && ["TW", "HK", "MO"].contains(country ?? ""))
        candidates.append(traditional ? "zh_Hant" : "zh_Hans")
    }
    if language == "no" { candidates.append("nb") }
    candidates.append(language)
    guard let match = candidates.lazy.compactMap({ name in
        CFLocaleMore.languages.first { $0.value == name }.map { (name: name, code: $0.key) }
    }).first else { return false }
    languageCode?.pointee = match.code
    let region = CFLocaleMore.regions.filter { $0.value == canonical || (country != nil && $0.value == language + "_" + country!) }
        .min { $0.key < $1.key }?.key
    regionCode?.pointee = region ?? -1
    let scriptManagerScript = CFLocaleMore.scripts[match.name] ?? 0
    scriptCode?.pointee = scriptManagerScript
    encoding?.pointee = CFLocaleMore.encodings[match.name] ?? UInt32(scriptManagerScript)
    return true
}

/// The locale of a Windows locale code (LCID), +1; for an unknown sort or
/// sublanguage, the language's main locale; NULL for an unknown language.
@c(_CFLocaleCreateLocaleIdentifierFromWindowsLocaleCode)
public func CFLocaleCreateLocaleIdentifierFromWindowsLocaleCode(_ allocator: UnsafeRawPointer?, _ code: UInt32) -> id? {
    let lcid = code & 0xFFFF
    if let identifier = CFLocaleMore.windowsLocales[lcid] { return Strings.make(identifier) }
    let primary = lcid & 0x3FF
    return CFLocaleMore.string(CFLocaleMore.windowsLocales[0x400 | primary])
}

/// The direction of a language's characters within a line.
@c(_CFLocaleGetLanguageCharacterDirection)
public func CFLocaleGetLanguageCharacterDirection(_ language: id?) -> Int {
    guard let code = Strings.value(of: language) else { return 0 }
    return CFLocaleMore.direction(Locale.Language(identifier: code).characterDirection)
}

/// The direction of a language's lines on a page.
@c(_CFLocaleGetLanguageLineDirection)
public func CFLocaleGetLanguageLineDirection(_ language: id?) -> Int {
    guard let code = Strings.value(of: language) else { return 0 }
    return CFLocaleMore.direction(Locale.Language(identifier: code).lineLayoutDirection)
}

/// The locale itself, retained: locales are immutable.
@c(_CFLocaleCreateCopy)
public func CFLocaleCreateCopy(_ allocator: UnsafeRawPointer?, _ locale: id?) -> id? { ObjC.retain(locale) }
