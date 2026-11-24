import CPerryFoundation
import FoundationEssentials
import PerryObjCInterop
import _FoundationICU

// CFStringTokenizer over ICU's break iterators: words, word boundaries,
// sentences and line breaks are ICU's; paragraphs end at each line
// terminator. A string's tokens are found when it's set, and the tokenizer
// moves through them.

/// A token: its range in the string, and what CFStringTokenizerTokenType
/// says of it.
struct StringToken {
    var range: CFRange
    var type: UInt
}

final class TokenizerStorage {
    /// kCFStringTokenizerUnitWord and the rest, and the attributes asked for.
    let options: UInt
    let locale: String
    let languageCode: String?
    var string: id?
    var units: [UInt16] = []
    var tokens: [StringToken] = []
    /// The current token, if any.
    var current: Int?
    /// The token the next advance goes to.
    var next = 0

    init(options: UInt, locale: Locale?) {
        self.options = options
        self.locale = locale?.identifier ?? ""
        self.languageCode = locale?.language.languageCode?.identifier
    }

    deinit {
        if let string { ObjC.release(string) }
    }

    var unit: UInt { options & 0xFF }

    func set(_ string: id?, range: CFRange) {
        let old = self.string
        self.string = string.flatMap { ObjC.retain($0) }
        if let old { ObjC.release(old) }
        units = Array((Strings.value(of: string) ?? "").utf16)
        let start = max(0, min(range.location, units.count))
        let end = max(start, min(range.location + range.length, units.count))
        tokens = Tokenizers.tokens(Array(units[start..<end]), unit: unit, locale: locale).map { token in
            var shifted = token
            shifted.range.location += start
            return shifted
        }
        current = nil
        next = 0
    }

    func text(_ range: CFRange) -> String {
        String(decoding: units[range.location..<(range.location + range.length)], as: UTF16.self)
    }
}

enum Tokenizers {
    nonisolated(unsafe) static var tokenizerClass: Class!

    static let none: UInt = 0, normal: UInt = 1, hasSubTokens: UInt = 2, hasDerivedSubTokens: UInt = 4
    static let hasNumbers: UInt = 8, hasNonLetters: UInt = 16, isCJWord: UInt = 32

    static let word: UInt = 0, sentence: UInt = 1, paragraph: UInt = 2, lineBreak: UInt = 3, wordBoundary: UInt = 4
    static let latinTranscription: UInt = 1 << 16, language: UInt = 1 << 17

    static func storage(_ tokenizer: id?) -> TokenizerStorage? { Storage.get(tokenizer, as: TokenizerStorage.self) }

    /// The tokens of `units` in `unit`.
    static func tokens(_ units: [UInt16], unit: UInt, locale: String) -> [StringToken] {
        guard !units.isEmpty else { return [] }
        if unit == paragraph { return paragraphs(units) }
        let type: UBreakIteratorType = switch unit {
        case sentence: UBRK_SENTENCE
        case lineBreak: UBRK_LINE
        default: UBRK_WORD
        }
        let text = String(decoding: units, as: UTF16.self)
        return ICU.withUChars(text) { chars, length in
            var status = U_ZERO_ERROR
            guard let iterator = swift_ubrk_open(type, locale, chars, length, &status), !ICU.failed(status) else { return [] }
            defer { swift_ubrk_close(iterator) }
            var tokens: [StringToken] = []
            var start = swift_ubrk_first(iterator)
            while true {
                let end = swift_ubrk_next(iterator)
                guard end != UBRK_DONE else { break }
                defer { start = end }
                let range = CFRange(location: Int(start), length: Int(end - start))
                let piece = Array(units[Int(start)..<Int(end)])
                if type != UBRK_WORD {
                    tokens.append(StringToken(range: range, type: normal))
                    continue
                }
                // Words are what ICU's rules call one; boundaries are every
                // piece.
                let isWord = swift_ubrk_getRuleStatus(iterator) >= UBRK_WORD_NONE_LIMIT.rawValue
                if unit == word, !isWord { continue }
                tokens.append(StringToken(range: range, type: wordType(piece, subTokens: unit == word)))
            }
            return tokens
        }
    }

    /// Paragraphs: each up to and with its line terminator.
    static func paragraphs(_ units: [UInt16]) -> [StringToken] {
        var tokens: [StringToken] = []
        var start = 0, index = 0
        while index < units.count {
            let unit = units[index]
            var end: Int?
            if unit == 0x0D {
                end = index + 1 < units.count && units[index + 1] == 0x0A ? index + 2 : index + 1
            } else if [0x0A, 0x0B, 0x0C, 0x85, 0x2028, 0x2029].contains(unit) {
                end = index + 1
            }
            if let end {
                tokens.append(StringToken(range: CFRange(location: start, length: end - start), type: normal))
                start = end
                index = end
            } else {
                index += 1
            }
        }
        if start < units.count { tokens.append(StringToken(range: CFRange(location: start, length: units.count - start), type: normal)) }
        return tokens
    }

    static func scalars(_ units: [UInt16]) -> [Unicode.Scalar] { Array(String(decoding: units, as: UTF16.self).unicodeScalars) }

    static func isCJ(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF, 0x31F0...0x31FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0xFF66...0xFF9F, 0x20000...0x2FFFF: true
        default: false
        }
    }

    /// A word's type: numbers in it, no letters in it, Chinese or Japanese.
    static func wordType(_ units: [UInt16], subTokens: Bool) -> UInt {
        let scalars = scalars(units)
        var type = normal
        let digits = scalars.contains { $0.properties.numericType != nil }
        if digits {
            type |= hasNumbers
            if subTokens { type |= hasSubTokens }
        }
        if !scalars.contains(where: { $0.properties.isAlphabetic || $0.properties.numericType != nil }) { type |= hasNonLetters }
        if !scalars.isEmpty, scalars.allSatisfy(isCJ) { type |= isCJWord }
        return type
    }

    /// A word with numbers in it, as its runs of letters, digits and the
    /// rest; any other token, whole.
    static func subTokens(of token: StringToken, in units: [UInt16]) -> [CFRange] {
        guard token.type & hasSubTokens != 0 else { return [token.range] }
        func kind(_ unit: UInt16) -> Int {
            guard let scalar = Unicode.Scalar(unit) else { return 0 }
            if scalar.properties.numericType != nil { return 1 }
            return scalar.properties.isAlphabetic ? 0 : 2
        }
        var ranges: [CFRange] = []
        var start = token.range.location
        let end = token.range.location + token.range.length
        while start < end {
            var finish = start + 1
            while finish < end, kind(units[finish]) == kind(units[start]) { finish += 1 }
            ranges.append(CFRange(location: start, length: finish - start))
            start = finish
        }
        return ranges
    }

    /// Text in Latin letters, by ICU's Any-Latin transliteration.
    static func latin(_ text: String) -> String? {
        var status = U_ZERO_ERROR
        let transliterator = ICU.withUChars("Any-Latin") { id, length in
            swift_utrans_openU(id, length, UTRANS_FORWARD, nil, 0, nil, &status)
        }
        guard let transliterator, !ICU.failed(status) else { return nil }
        defer { swift_utrans_close(transliterator) }
        var units = Array(text.utf16)
        let capacity = max(units.count * 4, 16)
        units += Array(repeating: 0, count: capacity - units.count)
        var length = Int32(text.utf16.count), limit = length
        units.withUnsafeMutableBufferPointer { buffer in
            swift_utrans_transUChars(transliterator, buffer.baseAddress, &length, Int32(capacity), 0, &limit, &status)
        }
        guard !ICU.failed(status) else { return nil }
        return String(decoding: units[0..<Int(length)], as: UTF16.self)
    }
}

// MARK: - Languages

enum StringLanguages {
    /// Common words of the languages told apart by them.
    static let words: [(String, Set<String>)] = [
        ("en", ["the", "a", "an", "and", "of", "to", "is", "in", "it", "that", "with", "for", "on", "are", "this", "was", "be", "as", "at", "by", "over"]),
        ("fr", ["le", "la", "les", "et", "est", "sur", "avec", "des", "un", "une", "du", "que", "qui", "dans", "pour", "pas", "au", "ce"]),
        ("es", ["el", "la", "los", "las", "y", "en", "con", "de", "que", "es", "un", "una", "por", "para", "del", "se", "al"]),
        ("it", ["il", "lo", "la", "gli", "le", "e", "è", "sul", "con", "di", "che", "un", "una", "per", "non", "del", "nel", "i"]),
        ("de", ["der", "die", "das", "und", "ist", "ein", "eine", "mit", "nicht", "zu", "den", "von", "im", "dem", "des", "sich", "auf", "dies"]),
        ("pt", ["o", "os", "as", "e", "é", "de", "que", "um", "uma", "com", "para", "não", "do", "da", "em", "no", "na"]),
        ("nl", ["de", "het", "een", "en", "is", "van", "op", "met", "niet", "dat", "zijn", "voor"]),
    ]

    /// The language a text is most likely in: by its script, and for Latin
    /// text by its common words. Nil when it can't tell.
    static func best(_ text: String) -> String? {
        var kana = 0, hangul = 0, han = 0, latin = 0
        var others: [String: Int] = [:]
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F: kana += 1
            case 0xAC00...0xD7AF, 0x1100...0x11FF, 0x3130...0x318F: hangul += 1
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF: han += 1
            case 0x0400...0x04FF: others["ru", default: 0] += 1
            case 0x0370...0x03FF: others["el", default: 0] += 1
            case 0x0590...0x05FF: others["he", default: 0] += 1
            case 0x0600...0x06FF: others["ar", default: 0] += 1
            case 0x0900...0x097F: others["hi", default: 0] += 1
            case 0x0E00...0x0E7F: others["th", default: 0] += 1
            default: if scalar.properties.isAlphabetic { latin += 1 }
            }
        }
        if kana > 0 { return "ja" }
        if hangul > 0 { return "ko" }
        if han > 0 { return "zh-Hant" }
        if let (language, _) = others.max(by: { $0.value < $1.value }), others.values.reduce(0, +) > latin { return language }
        guard latin > 0 else { return nil }
        let words = text.lowercased().split { !$0.isLetter }.map(String.init)
        var best: (String, Int)?
        for (language, common) in Self.words {
            let score = words.filter(common.contains).count
            if score > (best?.1 ?? 0) { best = (language, score) }
        }
        return best?.0
    }
}

// MARK: - Functions

@ObjCClass("__NSCFStringTokenizer")
final class NSCFStringTokenizer: NSObject {
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Tokenizers.tokenizerClass = cls.storage
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Tokenizers.tokenizerClass)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { 40 }
}

@c(_CFStringTokenizerGetTypeID) public func CFStringTokenizerGetTypeID() -> UInt { 40 }

@c(_CFStringTokenizerCreate)
public func CFStringTokenizerCreate(_ allocator: UnsafeRawPointer?, _ string: id?, _ range: CFRange, _ options: UInt,
                                    _ locale: id?) -> id? {
    guard let object = Storage.allocate(UnsafeMutableRawPointer(Tokenizers.tokenizerClass)) else { return nil }
    let storage = TokenizerStorage(options: options, locale: locale.map { Locales.locale($0) })
    Storage.set(object, storage)
    storage.set(string, range: range)
    return object
}

@c(_CFStringTokenizerSetString)
public func CFStringTokenizerSetString(_ tokenizer: id?, _ string: id?, _ range: CFRange) {
    Tokenizers.storage(tokenizer)?.set(string, range: range)
}

/// The token at `index`, which becomes the current one; none between
/// tokens, the next advance then going to the token after it.
@c(_CFStringTokenizerGoToTokenAtIndex)
public func CFStringTokenizerGoToTokenAtIndex(_ tokenizer: id?, _ index: Int) -> UInt {
    guard let storage = Tokenizers.storage(tokenizer) else { return Tokenizers.none }
    if let found = storage.tokens.firstIndex(where: { index >= $0.range.location && index < $0.range.location + $0.range.length }) {
        storage.current = found
        storage.next = found + 1
        return storage.tokens[found].type
    }
    storage.current = nil
    storage.next = storage.tokens.firstIndex { $0.range.location > index } ?? storage.tokens.count
    return Tokenizers.none
}

@c(_CFStringTokenizerAdvanceToNextToken)
public func CFStringTokenizerAdvanceToNextToken(_ tokenizer: id?) -> UInt {
    guard let storage = Tokenizers.storage(tokenizer) else { return Tokenizers.none }
    guard storage.next < storage.tokens.count else {
        storage.current = nil
        return Tokenizers.none
    }
    storage.current = storage.next
    storage.next += 1
    return storage.tokens[storage.current!].type
}

/// {kCFNotFound, 0} without a current token.
@c(_CFStringTokenizerGetCurrentTokenRange)
public func CFStringTokenizerGetCurrentTokenRange(_ tokenizer: id?) -> CFRange {
    guard let storage = Tokenizers.storage(tokenizer), let current = storage.current else { return CFRange(location: -1, length: 0) }
    return storage.tokens[current].range
}

/// The current token's Latin transcription, or the language of the locale
/// it was made with; as on Darwin, whether or not they were asked for when
/// it was made.
@c(_CFStringTokenizerCopyCurrentTokenAttribute)
public func CFStringTokenizerCopyCurrentTokenAttribute(_ tokenizer: id?, _ attribute: UInt) -> id? {
    guard let storage = Tokenizers.storage(tokenizer), let current = storage.current else { return nil }
    switch attribute {
    case Tokenizers.latinTranscription: return Tokenizers.latin(storage.text(storage.tokens[current].range)).map(Strings.make)
    case Tokenizers.language: return storage.languageCode.map(Strings.make)
    default: return nil
    }
}

/// The current token's sub-tokens, up to `maximum` ranges, and their text
/// appended to `derived`: their count.
@c(_CFStringTokenizerGetCurrentSubTokens)
public func CFStringTokenizerGetCurrentSubTokens(_ tokenizer: id?, _ ranges: UnsafeMutablePointer<CFRange>?, _ maximum: Int,
                                                 _ derived: id?) -> Int {
    guard let storage = Tokenizers.storage(tokenizer), let current = storage.current else { return 0 }
    let subTokens = Tokenizers.subTokens(of: storage.tokens[current], in: storage.units)
    let count = ranges == nil ? subTokens.count : min(subTokens.count, max(maximum, 0))
    for (index, range) in subTokens.prefix(count).enumerated() {
        ranges?[index] = range
        if let derived {
            let text = Strings.make(storage.text(range))
            CFArrayAppendValue(derived, UnsafeRawPointer(text))
            ObjC.release(text)
        }
    }
    return count
}

@c(_CFStringTokenizerCopyBestStringLanguage)
public func CFStringTokenizerCopyBestStringLanguage(_ string: id?, _ range: CFRange) -> id? {
    let units = Array((Strings.value(of: string) ?? "").utf16)
    let start = max(0, min(range.location, units.count))
    let end = max(start, min(range.location + range.length, units.count))
    return StringLanguages.best(String(decoding: units[start..<end], as: UTF16.self)).map(Strings.make)
}
