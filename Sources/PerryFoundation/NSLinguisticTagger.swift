import CPerryFoundation
import FoundationEssentials
import PerryObjCInterop
import _FoundationICU

// NSLinguisticTagger and NSOrthography. Words and sentences are ICU's break
// iterators' (with English clitics and French elisions split off words, as
// Darwin's tokenizer does), paragraphs end at each paragraph separator.
// Token types (Word, Punctuation, Whitespace, Other), scripts and languages
// are found here; lexical classes, names and lemmas need the language models
// Linux lacks, so those schemes answer as Darwin does for a language it has
// no model for: words are OtherWord (Other for names), punctuation and
// whitespace by kind, lemmas nil. Languages are guessed from the script and,
// for Latin text, common words.

// MARK: - Scripts and languages

enum LinguisticScripts {
    /// A letter's ISO 15924 script; nil for anything but a letter.
    static func code(_ scalar: Unicode.Scalar) -> String? {
        guard scalar.properties.isAlphabetic else { return nil }
        switch scalar.value {
        case 0x0000...0x02AF, 0x1D00...0x1DBF, 0x1E00...0x1EFF, 0x2C60...0x2C7F, 0xA720...0xA7FF, 0xAB30...0xAB6F, 0xFB00...0xFB06,
             0xFF21...0xFF3A, 0xFF41...0xFF5A: return "Latn"
        case 0x0370...0x03FF, 0x1F00...0x1FFF: return "Grek"
        case 0x0400...0x052F, 0x1C80...0x1C8F, 0x2DE0...0x2DFF, 0xA640...0xA69F: return "Cyrl"
        case 0x0530...0x058F: return "Armn"
        case 0x0590...0x05FF, 0xFB1D...0xFB4F: return "Hebr"
        case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF: return "Arab"
        case 0x0900...0x097F: return "Deva"
        case 0x0980...0x09FF: return "Beng"
        case 0x0A00...0x0A7F: return "Guru"
        case 0x0A80...0x0AFF: return "Gujr"
        case 0x0B00...0x0B7F: return "Orya"
        case 0x0B80...0x0BFF: return "Taml"
        case 0x0C00...0x0C7F: return "Telu"
        case 0x0C80...0x0CFF: return "Knda"
        case 0x0D00...0x0D7F: return "Mlym"
        case 0x0D80...0x0DFF: return "Sinh"
        case 0x0E00...0x0E7F: return "Thai"
        case 0x0E80...0x0EFF: return "Laoo"
        case 0x0F00...0x0FFF: return "Tibt"
        case 0x1000...0x109F: return "Mymr"
        case 0x10A0...0x10FF: return "Geor"
        case 0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF: return "Hang"
        case 0x1200...0x139F: return "Ethi"
        case 0x13A0...0x13FF: return "Cher"
        case 0x1400...0x167F: return "Cans"
        case 0x1780...0x17FF: return "Khmr"
        case 0x1800...0x18AF: return "Mong"
        case 0x3040...0x309F: return "Hira"
        case 0x30A0...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F: return "Kana"
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FFFF: return "Hani"
        default: return nil
        }
    }

    /// The scripts of a text's letters, most used first: kana with Han is
    /// Japanese (Jpan), Hangul with Han Korean (Kore).
    static func scripts(_ units: ArraySlice<UInt16>) -> [String] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for scalar in String(decoding: units, as: UTF16.self).unicodeScalars {
            guard let letter = code(scalar) else { continue }
            if counts[letter] == nil { order.append(letter) }
            counts[letter, default: 0] += 1
        }
        func merge(_ parts: [String], into name: String) {
            let total = parts.reduce(0) { $0 + (counts[$1] ?? 0) }
            guard total > 0 else { return }
            let first = order.firstIndex { parts.contains($0) } ?? order.count
            order.removeAll { parts.contains($0) }
            parts.forEach { counts[$0] = nil }
            counts[name] = total
            order.insert(name, at: min(first, order.count))
        }
        if counts["Hira"] != nil || counts["Kana"] != nil {
            merge(["Hira", "Kana", "Hani"], into: "Jpan")
        } else if counts["Hang"] != nil {
            merge(["Hang", "Hani"], into: "Kore")
        }
        return order.enumerated().sorted {
            let (a, b) = (counts[$0.element] ?? 0, counts[$1.element] ?? 0)
            return a != b ? a > b : $0.offset < $1.offset
        }.map(\.element)
    }

    /// The script a language is written in by default.
    static func script(forLanguage language: String) -> String {
        let parts = language.split { $0 == "-" || $0 == "_" }.map(String.init)
        if let script = parts.dropFirst().first(where: { $0.count == 4 && $0.allSatisfy(\.isLetter) }) {
            return script.prefix(1).uppercased() + script.dropFirst().lowercased()
        }
        let base = parts.first?.lowercased() ?? ""
        switch base {
        case "und", "": return "Zyyy"
        case "ja": return "Jpan"
        case "ko": return "Kore"
        case "zh": return parts.dropFirst().contains { ["TW", "HK", "MO"].contains($0.uppercased()) } ? "Hant" : "Hans"
        case "ru", "uk", "be", "bg", "mk", "kk", "ky", "tg", "mn", "tt", "ba", "cv", "ce", "os": return "Cyrl"
        case "el": return "Grek"
        case "he", "yi", "iw": return "Hebr"
        case "ar", "fa", "ur", "ps", "ug", "sd", "ckb": return "Arab"
        case "hi", "mr", "ne", "sa", "kok", "mai": return "Deva"
        case "bn", "as": return "Beng"
        case "pa": return "Guru"
        case "gu": return "Gujr"
        case "or": return "Orya"
        case "ta": return "Taml"
        case "te": return "Telu"
        case "kn": return "Knda"
        case "ml": return "Mlym"
        case "si": return "Sinh"
        case "th": return "Thai"
        case "lo": return "Laoo"
        case "bo", "dz": return "Tibt"
        case "my": return "Mymr"
        case "ka": return "Geor"
        case "hy": return "Armn"
        case "am", "ti": return "Ethi"
        case "km": return "Khmr"
        case "chr": return "Cher"
        case "iu": return "Cans"
        default: return "Latn"
        }
    }

    /// The language text in a script is taken to be in, for scripts mostly
    /// used for one.
    static func language(forScript script: String) -> String? {
        switch script {
        case "Cyrl": "ru"
        case "Grek": "el"
        case "Hebr": "he"
        case "Arab": "ar"
        case "Deva": "hi"
        case "Beng": "bn"
        case "Guru": "pa"
        case "Gujr": "gu"
        case "Orya": "or"
        case "Taml": "ta"
        case "Telu": "te"
        case "Knda": "kn"
        case "Mlym": "ml"
        case "Sinh": "si"
        case "Thai": "th"
        case "Laoo": "lo"
        case "Tibt": "bo"
        case "Mymr": "my"
        case "Geor": "ka"
        case "Armn": "hy"
        case "Ethi": "am"
        case "Khmr": "km"
        case "Cher": "chr"
        case "Cans": "iu"
        case "Mong": "mn"
        case "Jpan", "Hira", "Kana": "ja"
        case "Kore", "Hang": "ko"
        case "Hani", "Hans": "zh-Hans"
        case "Hant": "zh-Hant"
        default: nil
        }
    }

    /// Whether a token's script is written within an orthography's: Han
    /// letters within Japanese, Korean or Chinese.
    static func matching(_ script: String, in orthography: OrthographyStorage) -> String {
        if script == "Hani" || script == "Hira" || script == "Kana" || script == "Hang" {
            for candidate in ["Jpan", "Kore", "Hans", "Hant", "Hani"] where orthography.languages(for: candidate) != nil {
                if script == "Hani" || (candidate == "Jpan" && script != "Hang") || (candidate == "Kore" && script == "Hang") { return candidate }
            }
        }
        return script
    }

    /// The language of a text's Latin letters, by its common words: "und"
    /// when it can't tell. Letters of other scripts are left out.
    static func latinLanguage(_ units: ArraySlice<UInt16>) -> String {
        var latin = ""
        for scalar in String(decoding: units, as: UTF16.self).unicodeScalars {
            if let script = code(scalar), script != "Latn" { latin.unicodeScalars.append(" ") } else { latin.unicodeScalars.append(scalar) }
        }
        guard let language = StringLanguages.best(latin), ["en", "fr", "es", "it", "de", "pt", "nl"].contains(language) else { return "und" }
        return language
    }

    /// A text's language: nil without letters, "und" when it can't tell.
    static func dominantLanguage(_ units: ArraySlice<UInt16>) -> String? {
        guard let first = scripts(units).first else { return nil }
        return first == "Latn" ? latinLanguage(units) : language(forScript: first) ?? "und"
    }

    /// The orthography a text appears to be written in.
    static func orthography(_ units: ArraySlice<UInt16>) -> OrthographyStorage {
        let found = scripts(units)
        guard let dominant = found.first else {
            return OrthographyStorage(dominantScript: "Zyyy", map: [("Zyyy", ["und"])])
        }
        let map = found.map { script -> (String, [String]) in
            (script, [script == "Latn" ? latinLanguage(units) : language(forScript: script) ?? "und"])
        }
        return OrthographyStorage(dominantScript: dominant, map: map)
    }
}

// MARK: - NSOrthography

/// A dominant script and the languages each script is in, in order.
final class OrthographyStorage {
    let dominantScript: String?
    let map: [(script: String, languages: [String])]

    init(dominantScript: String?, map: [(String, [String])]) {
        self.dominantScript = dominantScript
        self.map = map.map { (script: $0.0, languages: $0.1) }
    }

    static func from(dominantScript: String?, languageMap: id?) -> OrthographyStorage {
        let entries = Dictionaries.entries(languageMap).compactMap { entry -> (String, [String])? in
            guard let script = Strings.value(of: entry.key) else { return nil }
            return (script, Arrays.elements(entry.value).compactMap { Strings.value(of: $0) })
        }
        return OrthographyStorage(dominantScript: dominantScript, map: entries)
    }

    func languages(for script: String) -> [String]? { map.first { $0.script == script }?.languages }

    var dominantLanguage: String? { dominantScript.flatMap { languages(for: $0)?.first } }

    /// The dominant script, then the others in the map's order.
    var allScripts: [String] {
        guard let dominantScript else { return map.map(\.script) }
        return [dominantScript] + map.map(\.script).filter { $0 != dominantScript }
    }

    var allLanguages: [String] {
        var languages: [String] = []
        for script in allScripts {
            for language in self.languages(for: script) ?? [] where !languages.contains(language) { languages.append(language) }
        }
        return languages
    }

    func isEqual(to other: OrthographyStorage) -> Bool {
        guard dominantScript == other.dominantScript, map.count == other.map.count else { return false }
        return map.allSatisfy { other.languages(for: $0.script) == $0.languages }
    }

    /// The map as an NSDictionary of arrays of strings (+0).
    func languageMap() -> id {
        Dictionaries.autoreleased(map.map { entry in
            (key: Strings.autoreleased(entry.script), value: Arrays.autoreleased(entry.languages.map { Strings.autoreleased($0) }))
        })
    }

    static func defaultFor(_ language: String) -> OrthographyStorage {
        let script = LinguisticScripts.script(forLanguage: language)
        return OrthographyStorage(dominantScript: script, map: [(script, [language])])
    }
}

enum Orthographies {
    nonisolated(unsafe) static var orthographyClass: Class!

    static func storage(_ object: id?) -> OrthographyStorage? { Storage.get(object, as: OrthographyStorage.self) }

    /// A new NSOrthography (+0) holding `storage`.
    static func object(_ storage: OrthographyStorage) -> id? {
        guard let object = Storage.allocate(UnsafeMutableRawPointer(orthographyClass)) else { return nil }
        Storage.set(object, storage)
        return ObjC.autorelease(object)
    }

    static func strings(_ values: [String]) -> id { Arrays.autoreleased(values.map { Strings.autoreleased($0) }) }
}

/// NSOrthography: the scripts a text is written in and the languages each
/// script's text is in.
@ObjCClass("NSOrthography")
public final class NSOrthography: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Orthographies.orthographyClass = cls.storage
    }

    private var storage: OrthographyStorage { Orthographies.storage(objcObject) ?? OrthographyStorage(dominantScript: nil, map: []) }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Orthographies.orthographyClass)
    }

    @ObjCClassMethod("orthographyWithDominantScript:languageMap:")
    static func make(dominantScript: String?, languageMap: ObjCObject?) -> UnsafeMutableRawPointer? {
        Orthographies.object(OrthographyStorage.from(dominantScript: dominantScript, languageMap: languageMap?.id))
    }

    /// The language's usual script, holding just that language.
    @ObjCClassMethod("defaultOrthographyForLanguage:")
    static func defaultOrthography(forLanguage language: String) -> UnsafeMutableRawPointer? {
        Orthographies.object(.defaultFor(language))
    }

    @ObjCMethod("initWithDominantScript:languageMap:")
    func initialize(dominantScript: String?, languageMap: ObjCObject?) -> Self {
        Storage.set(objcObject, OrthographyStorage.from(dominantScript: dominantScript, languageMap: languageMap?.id))
        return self
    }

    @ObjCMethod("dominantScript") func dominantScript() -> String? { storage.dominantScript }
    @ObjCMethod("languageMap") func languageMap() -> UnsafeMutableRawPointer { storage.languageMap() }
    @ObjCMethod("dominantLanguage") func dominantLanguage() -> String? { storage.dominantLanguage }
    @ObjCMethod("allScripts") func allScripts() -> UnsafeMutableRawPointer { Orthographies.strings(storage.allScripts) }
    @ObjCMethod("allLanguages") func allLanguages() -> UnsafeMutableRawPointer { Orthographies.strings(storage.allLanguages) }

    @ObjCMethod("languagesForScript:")
    func languages(forScript script: String) -> UnsafeMutableRawPointer? { storage.languages(for: script).map(Orthographies.strings) }

    @ObjCMethod("dominantLanguageForScript:")
    func dominantLanguage(forScript script: String) -> String? { storage.languages(for: script)?.first }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool {
        guard let other = Orthographies.storage(other?.id) else { return false }
        return storage.isEqual(to: other)
    }

    @ObjCMethod("hash") func hash() -> UInt { UInt(bitPattern: (storage.dominantScript ?? "").hashValue ^ storage.map.count) }

    /// Orthographies don't change: a copy is the same object.
    @ObjCMethod("copyWithZone:") func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { ObjC.retain(objcObject)! }

    // MARK: NSSecureCoding

    @ObjCClassMethod("supportsSecureCoding") static func supportsSecureCoding() -> Bool { true }

    /// NSDominantScript and NSLanguageMap, as Darwin archives them.
    @ObjCMethod("encodeWithCoder:")
    func encode(coder: ObjCObject) {
        typealias EncodeObject = @convention(c) (id?, SEL, id?, id?) -> Void
        let encode = unsafeBitCast(ObjC.msgSend, to: EncodeObject.self)
        let selector = ObjC.selector("encodeObject:forKey:")
        encode(coder.id, selector, storage.dominantScript.map { Strings.autoreleased($0) }, Strings.autoreleased("NSDominantScript"))
        encode(coder.id, selector, storage.languageMap(), Strings.autoreleased("NSLanguageMap"))
    }

    @ObjCMethod("initWithCoder:")
    func initialize(coder: ObjCObject) -> Self {
        let script = ObjC.send(coder.id, ObjC.selector("decodeObjectForKey:"), Strings.autoreleased("NSDominantScript"))
        let map = ObjC.send(coder.id, ObjC.selector("decodeObjectForKey:"), Strings.autoreleased("NSLanguageMap"))
        Storage.set(objcObject, OrthographyStorage.from(dominantScript: Strings.value(of: script), languageMap: map))
        return self
    }

    /// As Darwin describes one: "{Latn->en and fr, plus Cyrl}".
    @ObjCMethod("description")
    func description() -> String {
        let storage = storage
        var text = storage.dominantScript ?? "(null)"
        let languages = storage.dominantScript.flatMap { storage.languages(for: $0) } ?? []
        if !languages.isEmpty {
            text += "->" + (languages.count > 1 ? languages.dropLast().joined(separator: ", ") + " and " + languages.last! : languages[0])
        }
        let others = storage.allScripts.dropFirst()
        if !others.isEmpty { text += ", plus " + others.joined(separator: ", ") }
        return "<NSOrthography: \(objcObject)>{\(text)}"
    }
}

// MARK: - Tokens

/// What NSLinguisticTagSchemeTokenType says of a token.
enum LinguisticTokenKind {
    case word, punctuation, whitespace, other

    var tag: String {
        switch self {
        case .word: "Word"
        case .punctuation: "Punctuation"
        case .whitespace: "Whitespace"
        case .other: "Other"
        }
    }

    /// NSLinguisticTaggerOptions: omit words 1, punctuation 2, whitespace
    /// 4, other 8.
    func omitted(by options: UInt) -> Bool {
        switch self {
        case .word: options & 1 != 0
        case .punctuation: options & 2 != 0
        case .whitespace: options & 4 != 0
        case .other: options & 8 != 0
        }
    }
}

struct LinguisticToken {
    var start: Int
    var end: Int
    var kind: LinguisticTokenKind

    var range: NSRange { NSRange(location: start, length: end - start) }
    func intersects(_ start: Int, _ end: Int) -> Bool { self.start < end && self.end > start }
}

enum LinguisticTokens {
    /// NSLinguisticTaggerUnit: word 0, sentence 1, paragraph 2, document 3.
    static let word = 0, sentence = 1, paragraph = 2, document = 3

    static func kind(_ units: ArraySlice<UInt16>) -> LinguisticTokenKind {
        let scalars = String(decoding: units, as: UTF16.self).unicodeScalars
        if scalars.allSatisfy({ $0.properties.isWhitespace }) { return .whitespace }
        if scalars.contains(where: { $0.properties.isAlphabetic || $0.properties.numericType != nil }) { return .word }
        let punctuation = scalars.allSatisfy {
            switch $0.properties.generalCategory {
            case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation, .initialPunctuation,
                 .finalPunctuation, .otherPunctuation: true
            default: false
            }
        }
        return punctuation ? .punctuation : .other
    }

    /// Words, punctuation, whitespace and the rest, covering the text.
    static func words(_ units: [UInt16]) -> [LinguisticToken] {
        var tokens: [LinguisticToken] = []
        for (start, end) in breaks(units, type: UBRK_WORD, locale: "en_US_POSIX") {
            let found = kind(units[start..<end])
            if found == .word {
                for (pieceStart, pieceEnd) in clitics(units, start, end) {
                    tokens.append(LinguisticToken(start: pieceStart, end: pieceEnd, kind: .word))
                }
            } else {
                tokens.append(LinguisticToken(start: start, end: end, kind: found))
            }
        }
        return tokens
    }

    /// Sentences, each with the whitespace after it; abbreviations such as
    /// "Dr." don't end one.
    static func sentences(_ units: [UInt16]) -> [LinguisticToken] {
        breaks(units, type: UBRK_SENTENCE, locale: "en_US@ss=standard").map { LinguisticToken(start: $0.0, end: $0.1, kind: .word) }
    }

    /// Paragraphs, each up to and with its separator: a line feed, a
    /// carriage return (with its line feed), U+2029 or NEL. Darwin doesn't
    /// end one at U+2028.
    static func paragraphs(_ units: [UInt16]) -> [LinguisticToken] {
        var tokens: [LinguisticToken] = []
        var start = 0, index = 0
        while index < units.count {
            let unit = units[index]
            var end: Int?
            if unit == 0x0D {
                end = index + 1 < units.count && units[index + 1] == 0x0A ? index + 2 : index + 1
            } else if unit == 0x0A || unit == 0x2029 || unit == 0x85 {
                end = index + 1
            }
            if let end {
                tokens.append(LinguisticToken(start: start, end: end, kind: .word))
                (start, index) = (end, end)
            } else {
                index += 1
            }
        }
        if start < units.count { tokens.append(LinguisticToken(start: start, end: units.count, kind: .word)) }
        return tokens
    }

    static func breaks(_ units: [UInt16], type: UBreakIteratorType, locale: String) -> [(Int, Int)] {
        guard !units.isEmpty else { return [] }
        return units.withUnsafeBufferPointer { buffer in
            var status = U_ZERO_ERROR
            guard let iterator = swift_ubrk_open(type, locale, buffer.baseAddress, Int32(buffer.count), &status), !ICU.failed(status) else {
                return [(0, units.count)]
            }
            defer { swift_ubrk_close(iterator) }
            var pieces: [(Int, Int)] = []
            var start = swift_ubrk_first(iterator)
            while true {
                let end = swift_ubrk_next(iterator)
                guard end != UBRK_DONE else { break }
                if end > start { pieces.append((Int(start), Int(end))) }
                start = end
            }
            return pieces
        }
    }

    private static func isApostrophe(_ unit: UInt16) -> Bool { unit == 0x27 || unit == 0x2019 }

    private static let englishSuffixes: Set<String> = ["s", "re", "ll", "ve", "d", "m"]
    private static let elisions: Set<String> = ["c", "d", "j", "l", "m", "n", "s", "t", "qu", "jusqu", "lorsqu", "puisqu"]

    /// A word with its clitics apart: "do" "n't", "it" "'s", "l'" "enfant".
    static func clitics(_ units: [UInt16], _ start: Int, _ end: Int) -> [(Int, Int)] {
        let word = units[start..<end]
        guard word.contains(where: isApostrophe) else { return [(start, end)] }
        let lower = String(decoding: word, as: UTF16.self).lowercased()
        let normalized = Array(lower.replacingOccurrences(of: "\u{2019}", with: "'").utf16)
        guard normalized.count == word.count else { return [(start, end)] }
        let count = normalized.count
        if count > 3, String(decoding: normalized[(count - 3)...], as: UTF16.self) == "n't" {
            return [(start, end - 3), (end - 3, end)]
        }
        if let last = normalized.lastIndex(of: 0x27), last > 0,
           englishSuffixes.contains(String(decoding: normalized[(last + 1)...], as: UTF16.self)) {
            return [(start, start + last), (start + last, end)]
        }
        if let first = normalized.firstIndex(of: 0x27), first > 0, first + 1 < count,
           elisions.contains(String(decoding: normalized[..<first], as: UTF16.self)) {
            return [(start, start + first + 1), (start + first + 1, end)]
        }
        return [(start, end)]
    }
}

// MARK: - The tagger

final class LinguisticTaggerStorage {
    let schemes: [String]
    /// The string, retained: an edited mutable string is read again.
    private(set) var string: id?
    private(set) var units: [UInt16] = []
    /// Orthographies set on ranges, latest last, retained.
    private var orthographies: [(start: Int, end: Int, object: id)] = []
    private var cache: [Int: [LinguisticToken]] = [:]

    init(schemes: [String]) {
        self.schemes = schemes
    }

    deinit {
        ObjC.release(string)
        orthographies.forEach { ObjC.release($0.object) }
    }

    var length: Int { units.count }

    func set(_ string: id?) {
        let old = self.string
        self.string = ObjC.retain(string)
        ObjC.release(old)
        orthographies.forEach { ObjC.release($0.object) }
        orthographies = []
        reload()
    }

    func reload() {
        units = Array((Strings.value(of: string) ?? "").utf16)
        cache = [:]
    }

    /// The string changed in `range` (its new extent) by `delta` units:
    /// orthographies after it move, those over it are dropped.
    func edited(_ range: NSRange, delta: Int) {
        let start = Int(range.location), end = Int(range.location + range.length)
        let oldEnd = end - delta
        var kept: [(start: Int, end: Int, object: id)] = []
        for entry in orthographies {
            if entry.end <= start {
                kept.append(entry)
            } else if entry.start >= oldEnd {
                kept.append((entry.start + delta, entry.end + delta, entry.object))
            } else {
                ObjC.release(entry.object)
            }
        }
        orthographies = kept
        reload()
    }

    func tokens(_ unit: Int) -> [LinguisticToken] {
        if let tokens = cache[unit] { return tokens }
        let tokens: [LinguisticToken] = switch unit {
        case LinguisticTokens.word: LinguisticTokens.words(units)
        case LinguisticTokens.sentence: LinguisticTokens.sentences(units)
        case LinguisticTokens.paragraph: LinguisticTokens.paragraphs(units)
        default: []
        }
        cache[unit] = tokens
        return tokens
    }

    func token(at index: Int, unit: Int) -> LinguisticToken? { tokens(unit).first { $0.start <= index && index < $0.end } }

    func setOrthography(_ object: id?, start: Int, end: Int) {
        guard let object, end > start else { return }
        orthographies.append((start, end, ObjC.retain(object)!))
    }

    /// The orthography at `index`: one set over it, else what its
    /// paragraph's text appears to be in. The effective range is where that
    /// holds.
    func orthography(at index: Int) -> (storage: OrthographyStorage, object: id?, start: Int, end: Int) {
        if let set = orthographies.last(where: { $0.start <= index && index < $0.end }),
           let storage = Orthographies.storage(set.object) {
            return (storage, set.object, set.start, set.end)
        }
        let paragraph = token(at: index, unit: LinguisticTokens.paragraph) ?? LinguisticToken(start: 0, end: length, kind: .word)
        var start = paragraph.start, end = paragraph.end
        for entry in orthographies where entry.start < end && entry.end > start {
            if entry.end <= index { start = max(start, entry.end) } else if entry.start > index { end = min(end, entry.start) }
        }
        return (LinguisticScripts.orthography(units[paragraph.start..<paragraph.end]), nil, start, end)
    }

    /// Quote marks that open and close alike: the first of a pair opens.
    private func opensQuote(_ token: LinguisticToken) -> Bool {
        let mark = units[token.start]
        let before = tokens(LinguisticTokens.word).filter { $0.end <= token.start && $0.end - $0.start == 1 && units[$0.start] == mark }
        return before.count % 2 == 0
    }

    /// What lexical-class tagging without a model says of punctuation.
    private func punctuationClass(_ token: LinguisticToken) -> String {
        guard token.end - token.start == 1, let scalar = Unicode.Scalar(units[token.start]) else { return "Punctuation" }
        switch scalar.value {
        case 0x2E, 0x3F, 0x21, 0x3002, 0xFF0E, 0xFF1F, 0xFF01, 0x203C, 0x2047, 0x2048, 0x2049: return "SentenceTerminator"
        case 0x22, 0x27: return opensQuote(token) ? "OpenQuote" : "CloseQuote"
        case 0x2D, 0x2010: return "Dash"
        default: break
        }
        switch scalar.properties.generalCategory {
        case .initialPunctuation: return "OpenQuote"
        case .finalPunctuation: return "CloseQuote"
        case .openPunctuation: return "OpenParenthesis"
        case .closePunctuation: return "CloseParenthesis"
        default: return "Punctuation"
        }
    }

    /// The tag `scheme` gives a token of `unit`; nil for a scheme the
    /// tagger wasn't made with.
    func tag(_ token: LinguisticToken, unit: Int, scheme: String) -> String? {
        guard schemes.contains(scheme) else { return nil }
        let isWord = unit == LinguisticTokens.word
        switch scheme {
        case "TokenType":
            return isWord ? token.kind.tag : "Word"
        case "Script", "Language":
            let scripts = LinguisticScripts.scripts(units[token.start..<token.end])
            guard let first = scripts.first, !isWord || token.kind == .word else { return nil }
            let written = orthography(at: token.start).storage
            let script = LinguisticScripts.matching(first, in: written)
            if scheme == "Script" { return script }
            return written.languages(for: script)?.first ?? written.languages(for: first)?.first ?? "und"
        case "LexicalClass", "NameType", "NameTypeOrLexicalClass":
            let other = scheme == "LexicalClass" ? "OtherWord" : "Other"
            guard isWord else { return other }
            switch token.kind {
            case .word, .other: return other
            case .whitespace: return "Whitespace"
            case .punctuation: return punctuationClass(token)
            }
        default:
            // Lemmas, and schemes Darwin has models for that Linux doesn't.
            return nil
        }
    }

    /// Each token of `unit` that meets `range` and the options keep, with
    /// its tag, until `body` says stop.
    func enumerate(_ range: NSRange, unit: Int, scheme: String, options: UInt, _ body: (String?, LinguisticToken) -> Bool) {
        guard schemes.contains(scheme) else { return }
        let start = Int(range.location), end = Int(range.location + range.length)
        for token in tokens(unit) where token.intersects(start, end) {
            if unit == LinguisticTokens.word, token.kind.omitted(by: options) { continue }
            if !body(tag(token, unit: unit, scheme: scheme), token) { return }
        }
    }
}

enum LinguisticTaggers {
    nonisolated(unsafe) static var taggerClass: Class!

    static let allSchemes = ["TokenType", "LexicalClass", "NameType", "NameTypeOrLexicalClass", "Lemma", "Language", "Script"]

    /// What Darwin offers for a language it has no models for.
    static func available(unit: Int) -> [String] { unit == LinguisticTokens.word ? ["Language", "Script", "TokenType"] : ["Language", "Script"] }

    static func strings(_ values: [String]) -> id { Arrays.autoreleased(values.map { Strings.autoreleased($0) }) }

    static func rangeValue(_ range: NSRange) -> id {
        var range = range
        return ObjC.autorelease(Values.make(UnsafeMutableRawPointer(Values.valueClass), bytes: &range, type: NSRange.objCTypeEncoding))!
    }

    /// The range Darwin gives where there is no token (a document's, or no
    /// sentence): {NSUIntegerMax, 0}, not NSNotFound.
    static let noRange = NSRange(location: UInt.max, length: 0)

    static func outOfBounds(_ method: String) -> Never {
        Exceptions.raise(name: "NSRangeException", reason: "*** -[NSLinguisticTagger \(method)]: Range or index out of bounds")
    }

    /// A tagger for the class methods: one scheme, the string, and the
    /// orthography over all of it.
    static func temporary(_ string: id?, scheme: String, orthography: id?) -> LinguisticTaggerStorage {
        let storage = LinguisticTaggerStorage(schemes: [scheme])
        storage.set(string)
        storage.setOrthography(orthography, start: 0, end: storage.length)
        return storage
    }
}

/// NSLinguisticTagger.
@ObjCClass("NSLinguisticTagger")
public final class NSLinguisticTagger: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        LinguisticTaggers.taggerClass = cls.storage
    }

    private var storage: LinguisticTaggerStorage {
        if let storage = Storage.get(objcObject, as: LinguisticTaggerStorage.self) { return storage }
        let storage = LinguisticTaggerStorage(schemes: [])
        Storage.set(objcObject, storage)
        return storage
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: LinguisticTaggers.taggerClass)
    }

    @ObjCMethod("initWithTagSchemes:options:")
    func initialize(tagSchemes: ObjCObject?, options: UInt) -> Self {
        let schemes = Arrays.elements(tagSchemes?.id).compactMap { Strings.value(of: $0) }
        Storage.set(objcObject, LinguisticTaggerStorage(schemes: schemes))
        return self
    }

    @ObjCMethod("tagSchemes") func tagSchemes() -> UnsafeMutableRawPointer { LinguisticTaggers.strings(storage.schemes) }

    // MARK: Schemes and languages

    /// Language, script and token type for words; language and script for
    /// longer units. Darwin's lexical class, name and lemma models are not
    /// on Linux.
    @ObjCClassMethod("availableTagSchemesForUnit:language:")
    static func availableTagSchemes(forUnit unit: Int, language: String?) -> UnsafeMutableRawPointer {
        LinguisticTaggers.strings(LinguisticTaggers.available(unit: unit))
    }

    @ObjCClassMethod("availableTagSchemesForLanguage:")
    static func availableTagSchemes(forLanguage language: String?) -> UnsafeMutableRawPointer {
        LinguisticTaggers.strings(LinguisticTaggers.available(unit: LinguisticTokens.word))
    }

    /// The language a string is most likely in; nil when it has no letters,
    /// "und" when it can't be told.
    @ObjCClassMethod("dominantLanguageForString:")
    static func dominantLanguage(for string: String?) -> String? {
        guard let string else { return nil }
        return LinguisticScripts.dominantLanguage(Array(string.utf16)[...])
    }

    // MARK: The string

    @ObjCMethod("string") func string() -> UnsafeMutableRawPointer? { storage.string }
    @ObjCMethod("setString:") func setString(_ string: ObjCObject?) { storage.set(string?.id) }

    @ObjCMethod("stringEditedInRange:changeInLength:")
    func stringEdited(in range: NSRange, changeInLength delta: Int) { storage.edited(range, delta: delta) }

    @ObjCMethod("dominantLanguage")
    func dominantLanguage() -> String? {
        let storage = storage
        guard storage.string != nil else { return nil }
        return LinguisticScripts.dominantLanguage(storage.units[...])
    }

    // MARK: Orthographies

    @ObjCMethod("setOrthography:range:")
    func setOrthography(_ orthography: ObjCObject?, range: NSRange) {
        storage.setOrthography(orthography?.id, start: Int(range.location), end: Int(range.location + range.length))
    }

    @ObjCMethod("orthographyAtIndex:effectiveRange:")
    func orthography(at index: UInt, effectiveRange: UnsafeMutablePointer<NSRange>?) -> UnsafeMutableRawPointer? {
        let storage = storage
        guard Int(index) < storage.length else { LinguisticTaggers.outOfBounds("orthographyAtIndex:effectiveRange:") }
        let found = storage.orthography(at: Int(index))
        effectiveRange?.pointee = NSRange(location: found.start, length: found.end - found.start)
        return found.object ?? Orthographies.object(found.storage)
    }

    // MARK: Ranges

    @ObjCMethod("tokenRangeAtIndex:unit:")
    func tokenRange(at index: UInt, unit: Int) -> NSRange {
        let storage = storage
        guard Int(index) < storage.length else { LinguisticTaggers.outOfBounds("tokenRangeAtIndex:unit:") }
        return storage.token(at: Int(index), unit: unit)?.range ?? LinguisticTaggers.noRange
    }

    /// The sentences `range` touches, together.
    @ObjCMethod("sentenceRangeForRange:")
    func sentenceRange(for range: NSRange) -> NSRange {
        let storage = storage
        let start = Int(range.location), end = Int(range.location + range.length)
        guard end <= storage.length else { LinguisticTaggers.outOfBounds("_sentenceRangeForRange:") }
        let sentences = storage.tokens(LinguisticTokens.sentence)
        let touched = sentences.filter { $0.intersects(start, max(end, start + 1)) }
        guard let first = touched.first, let last = touched.last else { return LinguisticTaggers.noRange }
        return NSRange(location: first.start, length: last.end - first.start)
    }

    // MARK: Tags

    @ObjCMethod("enumerateTagsInRange:unit:scheme:options:usingBlock:")
    func enumerateTags(in range: NSRange, unit: Int, scheme: String, options: UInt, using block: ObjCObject) {
        typealias Invoke = @convention(c) (id, id?, NSRange, UnsafeMutablePointer<Bool>) -> Void
        let storage = storage
        guard Int(range.location + range.length) <= storage.length else {
            LinguisticTaggers.outOfBounds("enumerateTagsInRange:unit:scheme:options:usingBlock:")
        }
        let invoke = Blocks.invoke(block.id, as: Invoke.self)
        storage.enumerate(range, unit: unit, scheme: scheme, options: options) { tag, token in
            var stop = false
            ObjC.autoreleasepool { invoke(block.id, tag.map { Strings.autoreleased($0) }, token.range, &stop) }
            return !stop
        }
    }

    /// Words, each with the sentence it is in.
    @ObjCMethod("enumerateTagsInRange:scheme:options:usingBlock:")
    func enumerateTags(in range: NSRange, scheme: String, options: UInt, using block: ObjCObject) {
        typealias Invoke = @convention(c) (id, id?, NSRange, NSRange, UnsafeMutablePointer<Bool>) -> Void
        let storage = storage
        guard Int(range.location + range.length) <= storage.length else {
            LinguisticTaggers.outOfBounds("enumerateTagsInRange:scheme:options:usingBlock:")
        }
        let invoke = Blocks.invoke(block.id, as: Invoke.self)
        storage.enumerate(range, unit: LinguisticTokens.word, scheme: scheme, options: options) { tag, token in
            let sentence = storage.token(at: token.start, unit: LinguisticTokens.sentence)?.range ?? token.range
            var stop = false
            ObjC.autoreleasepool { invoke(block.id, tag.map { Strings.autoreleased($0) }, token.range, sentence, &stop) }
            return !stop
        }
    }

    private func tag(at index: UInt, unit: Int, scheme: String, tokenRange: UnsafeMutablePointer<NSRange>?,
                     sentenceRange: UnsafeMutablePointer<NSRange>?, method: String) -> String? {
        let storage = storage
        guard Int(index) < storage.length else { LinguisticTaggers.outOfBounds(method) }
        guard storage.schemes.contains(scheme) else { return nil }
        guard let token = storage.token(at: Int(index), unit: unit) else {
            tokenRange?.pointee = LinguisticTaggers.noRange
            return nil
        }
        tokenRange?.pointee = token.range
        if let sentenceRange {
            sentenceRange.pointee = storage.token(at: Int(index), unit: LinguisticTokens.sentence)?.range ?? token.range
        }
        return storage.tag(token, unit: unit, scheme: scheme)
    }

    @ObjCMethod("tagAtIndex:unit:scheme:tokenRange:")
    func tag(at index: UInt, unit: Int, scheme: String, tokenRange: UnsafeMutablePointer<NSRange>?) -> String? {
        tag(at: index, unit: unit, scheme: scheme, tokenRange: tokenRange, sentenceRange: nil, method: "tagAtIndex:unit:scheme:tokenRange:")
    }

    @ObjCMethod("tagAtIndex:scheme:tokenRange:sentenceRange:")
    func tag(at index: UInt, scheme: String, tokenRange: UnsafeMutablePointer<NSRange>?, sentenceRange: UnsafeMutablePointer<NSRange>?) -> String? {
        tag(at: index, unit: LinguisticTokens.word, scheme: scheme, tokenRange: tokenRange, sentenceRange: sentenceRange,
            method: "_tagAtIndex:scheme:tokenRange:sentenceRange:")
    }

    private func tags(in range: NSRange, unit: Int, scheme: String, options: UInt, tokenRanges: UnsafeMutablePointer<id?>?,
                      method: String) -> UnsafeMutableRawPointer {
        let storage = storage
        guard Int(range.location + range.length) <= storage.length else { LinguisticTaggers.outOfBounds(method) }
        var tags: [id] = [], ranges: [id] = []
        storage.enumerate(range, unit: unit, scheme: scheme, options: options) { tag, token in
            if let tag {
                tags.append(Strings.autoreleased(tag))
                ranges.append(LinguisticTaggers.rangeValue(token.range))
            }
            return true
        }
        tokenRanges?.pointee = Arrays.autoreleased(ranges)
        return Arrays.autoreleased(tags)
    }

    @ObjCMethod("tagsInRange:unit:scheme:options:tokenRanges:")
    func tags(in range: NSRange, unit: Int, scheme: String, options: UInt, tokenRanges: UnsafeMutablePointer<id?>?) -> UnsafeMutableRawPointer {
        tags(in: range, unit: unit, scheme: scheme, options: options, tokenRanges: tokenRanges, method: "tagsInRange:unit:scheme:options:tokenRanges:")
    }

    @ObjCMethod("tagsInRange:scheme:options:tokenRanges:")
    func tags(in range: NSRange, scheme: String, options: UInt, tokenRanges: UnsafeMutablePointer<id?>?) -> UnsafeMutableRawPointer {
        tags(in: range, unit: LinguisticTokens.word, scheme: scheme, options: options, tokenRanges: tokenRanges,
             method: "tagsInRange:scheme:options:tokenRanges:")
    }

    /// The one tag there is, scored 1: no model weighs others.
    @ObjCMethod("possibleTagsAtIndex:scheme:tokenRange:sentenceRange:scores:")
    func possibleTags(at index: UInt, scheme: String, tokenRange: UnsafeMutablePointer<NSRange>?, sentenceRange: UnsafeMutablePointer<NSRange>?,
                      scores: UnsafeMutablePointer<id?>?) -> UnsafeMutableRawPointer? {
        let found = tag(at: index, unit: LinguisticTokens.word, scheme: scheme, tokenRange: tokenRange, sentenceRange: sentenceRange,
                        method: "possibleTagsAtIndex:scheme:tokenRange:sentenceRange:scores:")
        guard let found else {
            scores?.pointee = nil
            return nil
        }
        scores?.pointee = Arrays.autoreleased([Numbers.make(nil, .double(1))!])
        return Arrays.autoreleased([Strings.autoreleased(found)])
    }

    // MARK: Class methods

    @ObjCClassMethod("tagForString:atIndex:unit:scheme:orthography:tokenRange:")
    static func tag(for string: ObjCObject?, at index: UInt, unit: Int, scheme: String, orthography: ObjCObject?,
                    tokenRange: UnsafeMutablePointer<NSRange>?) -> String? {
        let storage = LinguisticTaggers.temporary(string?.id, scheme: scheme, orthography: orthography?.id)
        guard Int(index) < storage.length else { LinguisticTaggers.outOfBounds("tagAtIndex:unit:scheme:tokenRange:") }
        guard let token = storage.token(at: Int(index), unit: unit) else {
            tokenRange?.pointee = LinguisticTaggers.noRange
            return nil
        }
        tokenRange?.pointee = token.range
        return storage.tag(token, unit: unit, scheme: scheme)
    }

    @ObjCClassMethod("tagsForString:range:unit:scheme:options:orthography:tokenRanges:")
    static func tags(for string: ObjCObject?, range: NSRange, unit: Int, scheme: String, options: UInt, orthography: ObjCObject?,
                     tokenRanges: UnsafeMutablePointer<id?>?) -> UnsafeMutableRawPointer {
        let storage = LinguisticTaggers.temporary(string?.id, scheme: scheme, orthography: orthography?.id)
        guard Int(range.location + range.length) <= storage.length else {
            LinguisticTaggers.outOfBounds("tagsInRange:unit:scheme:options:tokenRanges:")
        }
        var tags: [id] = [], ranges: [id] = []
        storage.enumerate(range, unit: unit, scheme: scheme, options: options) { tag, token in
            if let tag {
                tags.append(Strings.autoreleased(tag))
                ranges.append(LinguisticTaggers.rangeValue(token.range))
            }
            return true
        }
        tokenRanges?.pointee = Arrays.autoreleased(ranges)
        return Arrays.autoreleased(tags)
    }

    @ObjCClassMethod("enumerateTagsForString:range:unit:scheme:options:orthography:usingBlock:")
    static func enumerateTags(for string: ObjCObject?, range: NSRange, unit: Int, scheme: String, options: UInt,
                              orthography: ObjCObject?, using block: ObjCObject) {
        typealias Invoke = @convention(c) (id, id?, NSRange, UnsafeMutablePointer<Bool>) -> Void
        let storage = LinguisticTaggers.temporary(string?.id, scheme: scheme, orthography: orthography?.id)
        guard Int(range.location + range.length) <= storage.length else {
            LinguisticTaggers.outOfBounds("enumerateTagsInRange:unit:scheme:options:usingBlock:")
        }
        let invoke = Blocks.invoke(block.id, as: Invoke.self)
        storage.enumerate(range, unit: unit, scheme: scheme, options: options) { tag, token in
            var stop = false
            ObjC.autoreleasepool { invoke(block.id, tag.map { Strings.autoreleased($0) }, token.range, &stop) }
            return !stop
        }
    }
}
