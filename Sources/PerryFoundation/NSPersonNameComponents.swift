import CPerryFoundation
import FoundationEssentials
import PerryObjCInterop

// NSPersonNameComponents and NSPersonNameComponentsFormatter: a person's
// name in parts, and the parts as a locale writes them. Darwin orders and
// abbreviates names by their script and the locale's name order (family
// name first in Japanese, Chinese, Korean, Hungarian and Vietnamese), and
// parses a string with a name model of its own; here the same rules are
// written out, and parsing knows common prefixes, suffixes and particles.

/// The attribute key of an annotated name, and its values.
@ObjCConstants
enum PersonNameComponentKeys {
    static let NSPersonNameComponentKey = "NSPersonNameComponentKey"
    static let NSPersonNameComponentGivenName = "givenName"
    static let NSPersonNameComponentFamilyName = "familyName"
    static let NSPersonNameComponentMiddleName = "middleName"
    static let NSPersonNameComponentPrefix = "namePrefix"
    static let NSPersonNameComponentSuffix = "nameSuffix"
    static let NSPersonNameComponentNickname = "nickname"
    static let NSPersonNameComponentDelimiter = "delimiter"
}

/// A name's parts; the phonetic representation is another
/// NSPersonNameComponents, held.
final class PersonNameValues {
    var namePrefix: String?
    var givenName: String?
    var middleName: String?
    var familyName: String?
    var nameSuffix: String?
    var nickname: String?
    var phonetic: id? {
        didSet {
            if let oldValue { ObjC.release(oldValue) }
        }
    }

    init() {}

    deinit {
        if let phonetic { ObjC.release(phonetic) }
    }

    /// A copy, with a copy of the phonetic representation, as -copy makes.
    func copied() -> PersonNameValues {
        let copy = PersonNameValues()
        copy.namePrefix = namePrefix
        copy.givenName = givenName
        copy.middleName = middleName
        copy.familyName = familyName
        copy.nameSuffix = nameSuffix
        copy.nickname = nickname
        copy.phonetic = phonetic.flatMap { ObjC.send($0, Selectors.copyWithZone, nil) }
        return copy
    }

    var strings: [String?] { [namePrefix, givenName, middleName, familyName, nameSuffix, nickname] }

    func isEqual(to other: PersonNameValues) -> Bool {
        guard strings == other.strings else { return false }
        switch (phonetic, other.phonetic) {
        case (nil, nil): return true
        case let (mine?, theirs?): return mine == theirs || ObjC.sendBool(mine, Selectors.isEqual, theirs)
        default: return false
        }
    }

    /// Darwin's archive keys, those of _NSPersonNameComponentsData.
    static let keys = ["NS.namePrefix", "NS.givenName", "NS.middleName", "NS.familyName", "NS.nameSuffix", "NS.nickname"]

    func encode(coder: id) {
        typealias EncodeObject = @convention(c) (id?, SEL, id?, id?) -> Void
        let encode = unsafeBitCast(ObjC.msgSend, to: EncodeObject.self)
        for (key, value) in zip(Self.keys, strings) {
            encode(coder, ObjC.selector("encodeObject:forKey:"), value.map { Strings.autoreleased($0) }, Strings.autoreleased(key))
        }
        encode(coder, ObjC.selector("encodeObject:forKey:"), phonetic, Strings.autoreleased("NS.phoneticRepresentation"))
    }

    func decode(coder: id) {
        let decode = { (key: String) in ObjC.send(coder, ObjC.selector("decodeObjectForKey:"), Strings.autoreleased(key)) }
        let values = Self.keys.map { Strings.value(of: decode($0)) }
        namePrefix = values[0]
        givenName = values[1]
        middleName = values[2]
        familyName = values[3]
        nameSuffix = values[4]
        nickname = values[5]
        if let representation = decode("NS.phoneticRepresentation"), ObjC.isKind(representation, of: PersonNames.componentsClass) {
            phonetic = ObjC.retain(representation)
        }
    }
}

enum PersonNames {
    nonisolated(unsafe) static var componentsClass: Class!
    nonisolated(unsafe) static var dataClass: Class!

    static func values(_ object: id?) -> PersonNameValues? { Storage.get(object, as: PersonNameValues.self) }

    /// A new NSPersonNameComponents holding `values`, +1.
    static func make(_ values: PersonNameValues) -> id? {
        guard let object = Storage.allocate(UnsafeMutableRawPointer(componentsClass)) else { return nil }
        Storage.set(object, values)
        return object
    }
}

/// NSPersonNameComponents.
@ObjCClass("NSPersonNameComponents")
public final class NSPersonNameComponents: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        PersonNames.componentsClass = cls.storage
    }

    var values: PersonNameValues {
        if let values = PersonNames.values(objcObject) { return values }
        let values = PersonNameValues()
        Storage.set(objcObject, values)
        return values
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = values
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: PersonNames.componentsClass)
    }

    @ObjCMethod("namePrefix") func namePrefix() -> String? { values.namePrefix }
    @ObjCMethod("setNamePrefix:") func setNamePrefix(_ value: String?) { values.namePrefix = value }
    @ObjCMethod("givenName") func givenName() -> String? { values.givenName }
    @ObjCMethod("setGivenName:") func setGivenName(_ value: String?) { values.givenName = value }
    @ObjCMethod("middleName") func middleName() -> String? { values.middleName }
    @ObjCMethod("setMiddleName:") func setMiddleName(_ value: String?) { values.middleName = value }
    @ObjCMethod("familyName") func familyName() -> String? { values.familyName }
    @ObjCMethod("setFamilyName:") func setFamilyName(_ value: String?) { values.familyName = value }
    @ObjCMethod("nameSuffix") func nameSuffix() -> String? { values.nameSuffix }
    @ObjCMethod("setNameSuffix:") func setNameSuffix(_ value: String?) { values.nameSuffix = value }
    @ObjCMethod("nickname") func nickname() -> String? { values.nickname }
    @ObjCMethod("setNickname:") func setNickname(_ value: String?) { values.nickname = value }

    @ObjCMethod("phoneticRepresentation") func phoneticRepresentation() -> UnsafeMutableRawPointer? { values.phonetic }

    /// A copy, as the property is declared copy.
    @ObjCMethod("setPhoneticRepresentation:")
    func setPhoneticRepresentation(_ value: ObjCObject?) {
        values.phonetic = value.flatMap { ObjC.send($0.objcObject, Selectors.copyWithZone, nil) }
    }

    @ObjCMethod("copyWithZone:")
    func copyName(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { PersonNames.make(values.copied()) }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: ObjCObject?) -> Bool {
        guard let other else { return false }
        if other.objcObject == objcObject { return true }
        guard ObjC.isKind(other.objcObject, of: PersonNames.componentsClass), let theirs = PersonNames.values(other.objcObject) else {
            return false
        }
        return values.isEqual(to: theirs)
    }

    @ObjCMethod("hash")
    func hashValue() -> UInt {
        var hasher = Hasher()
        for value in values.strings { hasher.combine(value) }
        return UInt(bitPattern: hasher.finalize())
    }

    @ObjCMethod("description")
    func description() -> String {
        let v = values
        func show(_ value: String?) -> String { value ?? "(null)" }
        let phonetic = v.phonetic.flatMap { Strings.value(of: ObjC.send($0, ObjC.selector("description"))) } ?? "(null)"
        return "<NSPersonNameComponents: \(objcObject)> {givenName = \(show(v.givenName)), familyName = \(show(v.familyName)), "
            + "middleName = \(show(v.middleName)), namePrefix = \(show(v.namePrefix)), nameSuffix = \(show(v.nameSuffix)), "
            + "nickname = \(show(v.nickname)) phoneticRepresentation = \(phonetic) }"
    }

    // MARK: Coding

    /// As Darwin archives a name: its parts in a _NSPersonNameComponentsData
    /// under NS.nameComponentsPrivate.
    @ObjCClassMethod("supportsSecureCoding") static func supportsSecureCoding() -> Bool { true }

    @ObjCMethod("initWithCoder:")
    func initialize(coder: ObjCObject) -> Self {
        let decoded = PersonNameValues()
        if let data = ObjC.send(coder.objcObject, ObjC.selector("decodeObjectForKey:"), Strings.autoreleased("NS.nameComponentsPrivate")),
           let held = PersonNames.values(data) {
            Storage.set(objcObject, held.copied())
            return self
        }
        // An archive that keeps the parts themselves.
        decoded.decode(coder: coder.objcObject)
        Storage.set(objcObject, decoded)
        return self
    }

    @ObjCMethod("encodeWithCoder:")
    func encode(coder: ObjCObject) {
        // Autoreleased, not released: the archiver knows objects by their
        // address until it finishes.
        guard let data = Storage.allocate(UnsafeMutableRawPointer(PersonNames.dataClass)) else { return }
        Storage.set(data, values.copied())
        typealias EncodeObject = @convention(c) (id?, SEL, id?, id?) -> Void
        unsafeBitCast(ObjC.msgSend, to: EncodeObject.self)(coder.objcObject, ObjC.selector("encodeObject:forKey:"),
                                                            ObjC.autorelease(data), Strings.autoreleased("NS.nameComponentsPrivate"))
    }
}

/// _NSPersonNameComponentsData: the parts of an archived name.
@ObjCClass("_NSPersonNameComponentsData")
public final class NSPersonNameComponentsArchivedData: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        PersonNames.dataClass = cls.storage
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        Storage.set(objcObject, PersonNameValues())
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: PersonNames.dataClass)
    }

    @ObjCClassMethod("supportsSecureCoding") static func supportsSecureCoding() -> Bool { true }

    @ObjCMethod("initWithCoder:")
    func initialize(coder: ObjCObject) -> Self {
        let values = PersonNameValues()
        values.decode(coder: coder.objcObject)
        Storage.set(objcObject, values)
        return self
    }

    @ObjCMethod("encodeWithCoder:")
    func encode(coder: ObjCObject) {
        (PersonNames.values(objcObject) ?? PersonNameValues()).encode(coder: coder.objcObject)
    }
}

// MARK: - Layout

/// The writing system a name is in, which decides its order, its
/// delimiters and how it abbreviates.
enum PersonNameScript {
    /// Latin, Cyrillic, Greek and other alphabets: parts apart, initials.
    case alphabetic
    /// Chinese and Japanese: family name first, parts together.
    case han
    /// Korean: family and given name together.
    case hangul
    /// Parts in different scripts, or not starting with a letter.
    case mixed

    static func of(_ text: String) -> PersonNameScript {
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if (0xAC00...0xD7AF).contains(value) || (0x1100...0x11FF).contains(value) || (0x3130...0x318F).contains(value) {
                return .hangul
            }
            if (0x4E00...0x9FFF).contains(value) || (0x3400...0x4DBF).contains(value) || (0x3040...0x30FF).contains(value)
                || (0x31F0...0x31FF).contains(value) || (0xF900...0xFAFF).contains(value) || (0xFF66...0xFF9F).contains(value)
                || (0x20000...0x2FFFF).contains(value) {
                return .han
            }
        }
        guard let first = text.unicodeScalars.first, first.properties.isAlphabetic else { return .mixed }
        return .alphabetic
    }
}

/// A name's non-empty parts, laid out for a style.
struct PersonNameLayout {
    typealias Part = (key: String, text: String)

    var prefix: String?
    var given: String?
    var middle: String?
    var family: String?
    var suffix: String?
    var nickname: String?

    init(_ values: PersonNameValues?) {
        func part(_ value: String?) -> String? { value.flatMap { $0.isEmpty ? nil : $0 } }
        prefix = part(values?.namePrefix)
        given = part(values?.givenName)
        middle = part(values?.middleName)
        family = part(values?.familyName)
        suffix = part(values?.nameSuffix)
        nickname = part(values?.nickname)
    }

    /// Languages that write the family name first.
    static func familyFirst(_ locale: Locale) -> Bool {
        let language = locale.identifier.split(whereSeparator: { $0 == "_" || $0 == "-" || $0 == "@" }).first.map(String.init) ?? ""
        return ["ja", "zh", "ko", "hu", "vi", "yue", "mn"].contains(language)
    }

    var script: PersonNameScript {
        let scripts = [given, middle, family].compactMap { $0 }.map(PersonNameScript.of)
        guard let first = scripts.first else { return .alphabetic }
        return scripts.allSatisfy({ $0 == first }) ? first : .mixed
    }

    /// Whether the given and family names are Korean while another part is
    /// not: Darwin then keeps the locale's order, with the two together.
    private var hangulCore: Bool {
        let core = [given, family].compactMap { $0 }
        return !core.isEmpty && core.allSatisfy { PersonNameScript.of($0) == .hangul }
    }

    private func parts(_ list: [(String, String?)]) -> [Part] {
        list.compactMap { entry in entry.1.map { (key: entry.0, text: $0) } }
    }

    /// Parts with delimiters between them, as `delimiter` says.
    private func joined(_ parts: [Part], _ delimiter: (Part, Part) -> String) -> [Part] {
        var result: [Part] = []
        for part in parts {
            if let last = result.last {
                let text = delimiter(last, part)
                if !text.isEmpty { result.append((key: "delimiter", text: text)) }
            }
            result.append(part)
        }
        return result
    }

    private func spaced(_ parts: [Part]) -> [Part] { joined(parts) { _, _ in " " } }

    private var nicknameParts: [Part] { parts([("nickname", nickname)]) }

    /// NSPersonNameComponentsFormatterStyle: default 0 (medium), short 1,
    /// medium 2, long 3, abbreviated 4.
    func parts(style: Int, familyFirst: Bool) -> [Part] {
        let script = self.script
        let ordered = familyFirst
            ? [("familyName", family), ("givenName", given), ("middleName", middle)]
            : [("givenName", given), ("middleName", middle), ("familyName", family)]
        let core = parts(ordered.filter { $0.0 != "middleName" })
        let full = parts([("namePrefix", prefix)] + ordered + [("nameSuffix", suffix)])
        switch script {
        case .alphabetic:
            switch style {
            case 1:
                return Array(parts([("nickname", nickname), ("givenName", given), ("familyName", family)]).prefix(1))
            case 3:
                return full.isEmpty ? nicknameParts : spaced(full)
            case 4:
                let initials = core.map { part in (key: part.key, text: part.text.first.map { String($0).uppercased() } ?? "") }
                return initials.isEmpty ? nicknameParts : initials
            default:
                return spaced(core)
            }
        case .han, .hangul:
            // Family name first and the parts together, in any locale; a
            // Korean name abbreviates to its given name.
            let names = parts([("familyName", family), ("givenName", given), ("middleName", middle), ("nameSuffix", suffix)])
            let long = joined(parts([("namePrefix", prefix)]) + names) { first, _ in first.key == "namePrefix" ? " " : "" }
            switch style {
            case 1: return nickname == nil ? long : nicknameParts
            case 3: return long.isEmpty ? nicknameParts : long
            case 4:
                let abbreviation = script == .hangul
                    ? [("givenName", given), ("familyName", family)]
                    : [("familyName", family), ("givenName", given)]
                return Array(parts(abbreviation).prefix(1))
            default: return parts([("familyName", family), ("givenName", given)])
            }
        case .mixed where hangulCore:
            let together = { (first: Part, second: Part) -> String in
                Set([first.key, second.key]) == Set(["familyName", "givenName"]) ? "" : " "
            }
            let long = joined(full, together)
            switch style {
            case 1: return nickname == nil ? long : nicknameParts
            case 3: return long.isEmpty ? nicknameParts : long
            case 4: return Array(parts([("givenName", given), ("familyName", family)]).prefix(1))
            default: return joined(core, together)
            }
        case .mixed:
            let long = spaced(full)
            switch style {
            case 1: return nickname == nil ? long : nicknameParts
            case 3: return long.isEmpty ? nicknameParts : long
            case 4:
                if let family, PersonNameScript.of(family) == .han { return [(key: "familyName", text: family)] }
                return spaced(core)
            default: return spaced(core)
            }
        }
    }

    // MARK: Parsing

    private static let prefixes: Set<String> = [
        "mr", "mrs", "ms", "miss", "mx", "dr", "prof", "sir", "dame", "rev", "fr", "lord", "lady", "hon", "capt", "col", "gen",
        "lt", "sgt", "mme", "mlle", "herr", "frau", "sra", "srta",
    ]
    private static let suffixes: Set<String> = [
        "jr", "sr", "ii", "iii", "iv", "phd", "md", "esq", "dds", "dvm", "rn", "cpa", "jd", "mba", "ret",
    ]
    private static let particles: Set<String> = [
        "van", "von", "der", "den", "de", "da", "di", "du", "del", "della", "la", "le", "bin", "ibn", "al", "el", "ten", "ter",
        "dos", "das", "do", "st.", "mac",
    ]

    private static func normalized(_ token: String) -> String {
        var text = token.lowercased()
        while text.hasSuffix(".") || text.hasSuffix(",") { text.removeLast() }
        return text
    }

    private static func isInitial(_ token: String) -> Bool {
        let letters = token.hasSuffix(".") ? String(token.dropLast()) : token
        return letters.count == 1 && letters.first?.isLetter == true
    }

    /// The parts of a written name: a known prefix and suffix, "Family,
    /// Given", a middle initial, and a family name from its first particle
    /// ("van der Berg") or after the given name. Nil for no name.
    static func parse(_ string: String) -> PersonNameValues? {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let values = PersonNameValues()
        var familyFirst = false
        if let comma = text.firstIndex(of: ",") {
            let before = String(text[..<comma]).trimmingCharacters(in: .whitespacesAndNewlines)
            let after = String(text[text.index(after: comma)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if suffixes.contains(normalized(after)) {
                values.nameSuffix = after
                text = before
            } else if !before.isEmpty, !after.isEmpty {
                values.familyName = before
                text = after
                familyFirst = true
            }
        }
        var tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return values.familyName == nil ? nil : values }
        if tokens.count > 1, prefixes.contains(normalized(tokens[0])) { values.namePrefix = tokens.removeFirst() }
        if tokens.count > 1, values.nameSuffix == nil, suffixes.contains(normalized(tokens[tokens.count - 1])) {
            values.nameSuffix = tokens.removeLast()
        }
        if familyFirst {
            values.givenName = tokens[0]
            if tokens.count > 1 { values.middleName = tokens[1...].joined(separator: " ") }
            return values
        }
        if tokens.count == 1 {
            if values.namePrefix != nil || values.nameSuffix != nil {
                values.familyName = tokens[0]
            } else {
                values.givenName = tokens[0]
            }
            return values
        }
        if tokens.allSatisfy({ PersonNameScript.of($0) == .han || PersonNameScript.of($0) == .hangul }) {
            values.familyName = tokens[0]
            values.givenName = tokens[1...].joined()
            return values
        }
        if let particle = tokens.indices.dropFirst().first(where: { particles.contains(tokens[$0].lowercased()) }) {
            values.givenName = tokens[..<particle].joined(separator: " ")
            values.familyName = tokens[particle...].joined(separator: " ")
            return values
        }
        values.givenName = tokens[0]
        if tokens.count > 2, isInitial(tokens[1]) {
            values.middleName = tokens[1]
            values.familyName = tokens[2...].joined(separator: " ")
        } else {
            values.familyName = tokens[1...].joined(separator: " ")
        }
        return values
    }
}

// MARK: - NSPersonNameComponentsFormatter

final class PersonNameFormatterStorage {
    var style = 0
    var phonetic = false
    var locale: Locale?

    var effectiveLocale: Locale { locale ?? Locales.current }

    /// The name's parts as the formatter writes them.
    func parts(_ components: id?) -> [PersonNameLayout.Part] {
        guard var values = PersonNames.values(components) else { return [] }
        if phonetic {
            guard let representation = values.phonetic.flatMap(PersonNames.values) else { return [] }
            values = representation
        }
        return PersonNameLayout(values).parts(style: style, familyFirst: PersonNameLayout.familyFirst(effectiveLocale))
    }

    func string(_ components: id?) -> String { parts(components).map(\.text).joined() }
}

/// NSPersonNameComponentsFormatter.
@ObjCClass("NSPersonNameComponentsFormatter")
public class NSPersonNameComponentsFormatter: NSFormatter {
    nonisolated(unsafe) static var formatterClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        formatterClass = cls.storage
    }

    var state: PersonNameFormatterStorage {
        if let state = Storage.get(objcObject, as: PersonNameFormatterStorage.self) { return state }
        let state = PersonNameFormatterStorage()
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
        ObjC.superDealloc(objcObject, from: NSPersonNameComponentsFormatter.formatterClass)
    }

    /// A new formatter with the same settings.
    @ObjCMethod("copyWithZone:")
    func copyNameFormatter(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let copy = ObjC.send(ObjC.send(UnsafeMutableRawPointer(ObjC.objectGetClass(objcObject)), ObjC.selector("alloc")),
                                   ObjC.selector("init")) else { return nil }
        let theirs = Storage.get(copy, as: PersonNameFormatterStorage.self)
        theirs?.style = state.style
        theirs?.phonetic = state.phonetic
        theirs?.locale = state.locale
        return copy
    }

    @ObjCMethod("style") func style() -> Int { state.style }
    @ObjCMethod("setStyle:") func setStyle(_ style: Int) { state.style = style }
    @ObjCMethod("isPhonetic") func isPhonetic() -> Bool { state.phonetic }
    @ObjCMethod("setPhonetic:") func setPhonetic(_ phonetic: Bool) { state.phonetic = phonetic }

    @ObjCMethod("locale") func locale() -> UnsafeMutableRawPointer { Locales.autoreleased(state.effectiveLocale) }
    @ObjCMethod("setLocale:") func setLocale(_ locale: ObjCObject?) { state.locale = locale.map { Locales.locale($0.objcObject) } }

    /// NSPersonNameComponentsFormatterPhonetic is 1 << 1.
    @ObjCClassMethod("localizedStringFromPersonNameComponents:style:options:")
    static func localizedString(fromPersonNameComponents components: ObjCObject, style: Int, options: UInt) -> String {
        let state = PersonNameFormatterStorage()
        state.style = style
        state.phonetic = options & 2 != 0
        return state.string(components.objcObject)
    }

    @ObjCMethod("stringFromPersonNameComponents:")
    func string(fromPersonNameComponents components: ObjCObject?) -> String { state.string(components?.objcObject) }

    /// The name with each part's range annotated NSPersonNameComponentKey:
    /// the part's name, or "delimiter" between parts.
    @ObjCMethod("annotatedStringFromPersonNameComponents:")
    func annotatedString(fromPersonNameComponents components: ObjCObject?) -> UnsafeMutableRawPointer? {
        let parts = state.parts(components?.objcObject)
        let storage = AttributedStorage(units: [], attributes: nil)
        let key = Strings.autoreleased("NSPersonNameComponentKey")
        for part in parts {
            let units = Array(part.text.utf16)
            guard !units.isEmpty else { continue }
            storage.units += units
            storage.runs.append(AttributeRun(length: units.count,
                                             attributes: Dictionaries.make([(key: key, value: Strings.autoreleased(part.key))])))
        }
        return AttributedStrings.make(storage, mutable: false).flatMap { ObjC.autorelease($0) }
    }

    @ObjCMethod("personNameComponentsFromString:")
    func personNameComponents(from string: String?) -> UnsafeMutableRawPointer? {
        guard let string, let values = PersonNameLayout.parse(string), let object = PersonNames.make(values) else { return nil }
        return ObjC.autorelease(object)
    }

    @ObjCMethod("getObjectValue:forString:errorDescription:")
    func personNameObjectValue(_ value: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, for string: String?,
                               errorDescription: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Bool {
        guard let components = personNameComponents(from: string) else { return false }
        value?.pointee = components
        return true
    }

    @ObjCMethod("stringForObjectValue:")
    func personNameString(forObjectValue value: ObjCObject?) -> String? {
        guard let value, ObjC.isKind(value.objcObject, of: PersonNames.componentsClass) else { return nil }
        return state.string(value.objcObject)
    }
}
