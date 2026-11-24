import CPerryFoundation
import PerryObjCInterop

// Grammar for automatic grammatical agreement: a word's morphology (gender,
// number, part of speech…), pronouns, terms of address and the rules that
// inflect localized strings. Darwin keeps the user's own morphology and term
// of address in settings no one has made here, so the user's are
// unspecified, and these classes keep what a program gives them. Languages
// Darwin inflects are the ones it answers -canInflectLanguage: for.

private func grammarClass(_ name: String) -> id? {
    name.withCString { ObjC.getClass($0) }.map { UnsafeMutableRawPointer($0) }
}

private func grammarEncode(_ coder: id?, integer value: Int, _ key: String) {
    typealias Encode = @convention(c) (id?, SEL, Int, id?) -> Void
    unsafeBitCast(ObjC.msgSend, to: Encode.self)(coder, ObjC.selector("encodeInteger:forKey:"), value, Strings.autoreleased(key))
}

private func grammarDecodeInteger(_ coder: id?, _ key: String) -> Int {
    ObjC.sendInt(coder, ObjC.selector("decodeIntegerForKey:"), Strings.autoreleased(key))
}

private func grammarEncode(_ coder: id?, object: id?, _ key: String) {
    guard let object else { return }
    _ = ObjC.send(coder, ObjC.selector("encodeObject:forKey:"), object, Strings.autoreleased(key))
}

private func grammarDecodeObject(_ coder: id?, _ key: String) -> id? {
    ObjC.send(coder, ObjC.selector("decodeObjectForKey:"), Strings.autoreleased(key))
}

private func copyOf(_ object: id?) -> ObjCObject? {
    object.flatMap { ObjC.send($0, Selectors.copyWithZone, nil) }.map { ObjCObject(objCOwned: $0) }
}

private func equal(_ a: id?, _ b: id?) -> Bool {
    guard let a, let b else { return a == nil && b == nil }
    return a == b || ObjC.sendBool(a, Selectors.isEqual, b)
}

/// A new instance of a class with storage, autoreleased.
private func makeGrammar(_ cls: UnsafeMutableRawPointer?, _ storage: AnyObject) -> id? {
    guard let object = Storage.allocate(cls) else { return nil }
    Storage.set(object, storage)
    return ObjC.autorelease(object)
}

/// A language's code, without its region or script.
private func languageCode(_ language: String) -> String {
    String(language.prefix { $0 != "-" && $0 != "_" }).lowercased()
}

// MARK: - Morphology

/// The grammatical features, NSMorphology's properties, in Darwin's order
/// of description, with their values' names.
private let morphologyFeatures: [(key: String, label: String, names: [String])] = [
    ("grammaticalGender", "grammaticalGender", ["NotSet", "Feminine", "Masculine", "Neuter"]),
    ("number", "number", ["NotSet", "Singular", "Zero", "Plural", "PluralTwo", "PluralFew", "PluralMany"]),
    ("partOfSpeech", "partOfSpeech", ["NotSet", "Determiner", "Pronoun", "Letter", "Adverb", "Particle", "Adjective", "Adposition",
                                      "Verb", "Noun", "Conjunction", "Numeral", "Interjection", "Preposition", "Abbreviation"]),
    ("grammaticalCase", "case", ["NotSet", "Nominative", "Accusative", "Dative", "Genitive", "Prepositional", "Ablative", "Adessive",
                                 "Allative", "Elative", "Illative", "Essive", "Inessive", "Locative", "Translative"]),
    ("definiteness", "definiteness", ["NotSet", "Indefinite", "Definite"]),
    ("determination", "determination", ["NotSet", "Independent", "Dependent"]),
    ("grammaticalPerson", "grammaticalPerson", ["NotSet", "First", "Second", "Third"]),
    ("pronounType", "pronounType", ["NotSet", "Personal", "Reflexive", "Possessive"]),
]

final class MorphologyStorage {
    var features: [String: Int] = [:]
    /// Custom pronouns by language, each a copy (retained).
    var customPronouns: [String: ObjCObject] = [:]

    func copy() -> MorphologyStorage {
        let copy = MorphologyStorage()
        copy.features = features
        copy.customPronouns = customPronouns.compactMapValues { copyOf($0.id) }
        return copy
    }
}

@ObjCClass("NSMorphology")
open class NSMorphology: NSObject {
    nonisolated(unsafe) static var morphologyClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        morphologyClass = cls.storage
    }

    var storage: MorphologyStorage {
        if let storage = Storage.get(objcObject, as: MorphologyStorage.self) { return storage }
        let storage = MorphologyStorage()
        Storage.set(objcObject, storage)
        return storage
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = storage
        return self
    }

    private func feature(_ key: String) -> Int { storage.features[key] ?? 0 }
    private func setFeature(_ key: String, _ value: Int) { storage.features[key] = value == 0 ? nil : value }

    @ObjCMethod("grammaticalGender") func grammaticalGender() -> Int { feature("grammaticalGender") }
    @ObjCMethod("setGrammaticalGender:") func setGrammaticalGender(_ value: Int) { setFeature("grammaticalGender", value) }
    @ObjCMethod("partOfSpeech") func partOfSpeech() -> Int { feature("partOfSpeech") }
    @ObjCMethod("setPartOfSpeech:") func setPartOfSpeech(_ value: Int) { setFeature("partOfSpeech", value) }
    @ObjCMethod("number") func number() -> Int { feature("number") }
    @ObjCMethod("setNumber:") func setNumber(_ value: Int) { setFeature("number", value) }
    @ObjCMethod("grammaticalCase") func grammaticalCase() -> Int { feature("grammaticalCase") }
    @ObjCMethod("setGrammaticalCase:") func setGrammaticalCase(_ value: Int) { setFeature("grammaticalCase", value) }
    @ObjCMethod("determination") func determination() -> Int { feature("determination") }
    @ObjCMethod("setDetermination:") func setDetermination(_ value: Int) { setFeature("determination", value) }
    @ObjCMethod("grammaticalPerson") func grammaticalPerson() -> Int { feature("grammaticalPerson") }
    @ObjCMethod("setGrammaticalPerson:") func setGrammaticalPerson(_ value: Int) { setFeature("grammaticalPerson", value) }
    @ObjCMethod("pronounType") func pronounType() -> Int { feature("pronounType") }
    @ObjCMethod("setPronounType:") func setPronounType(_ value: Int) { setFeature("pronounType", value) }
    @ObjCMethod("definiteness") func definiteness() -> Int { feature("definiteness") }
    @ObjCMethod("setDefiniteness:") func setDefiniteness(_ value: Int) { setFeature("definiteness", value) }

    /// No feature set and no custom pronoun.
    @ObjCMethod("isUnspecified") func isUnspecified() -> Bool { storage.features.isEmpty && storage.customPronouns.isEmpty }

    /// The user's, which no settings here specify.
    @ObjCClassMethod("userMorphology")
    static func userMorphology(_ cls: ObjCClass) -> UnsafeMutableRawPointer? {
        makeGrammar(UnsafeMutableRawPointer(morphologyClass), MorphologyStorage())
    }

    @ObjCMethod("customPronounForLanguage:")
    func customPronoun(forLanguage language: String?) -> UnsafeMutableRawPointer? {
        language.flatMap { storage.customPronouns[$0]?.id }
    }

    /// Kept if the language takes custom pronouns and every form it needs is
    /// given; else NSKeyValueValidationError naming what is invalid, as on
    /// Darwin. nil removes the language's.
    @ObjCMethod("setCustomPronoun:forLanguage:error:")
    func setCustomPronoun(_ pronoun: UnsafeMutableRawPointer?, forLanguage language: String?, error: UnsafeMutablePointer<id?>?) -> Bool {
        guard let language else { return false }
        guard let pronoun else {
            storage.customPronouns[language] = nil
            return true
        }
        func invalid(_ value: String) -> Bool {
            error?.pointee = ObjC.autorelease(Errors.make(domain: Errors.cocoaDomain, code: 1024,
                                                          entries: [("NSInvalidValue", Strings.autoreleased(value))]))
            return false
        }
        guard NSMorphologyCustomPronoun.supported(language) else { return invalid("self") }
        for key in NSMorphologyCustomPronoun.requiredKeys(language) where ObjC.send(pronoun, ObjC.selector(key)) == nil {
            return invalid(key)
        }
        storage.customPronouns[language] = copyOf(pronoun)
        return true
    }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let copy = Storage.allocate(ObjC.objectGetClass(objcObject).map { UnsafeMutableRawPointer($0) }) else { return nil }
        Storage.set(copy, storage.copy())
        return copy
    }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: UnsafeMutableRawPointer?) -> Bool {
        guard let other else { return false }
        if other == objcObject { return true }
        guard let theirs = Storage.get(other, as: MorphologyStorage.self) else { return false }
        let ours = storage
        guard ours.features == theirs.features, Set(ours.customPronouns.keys) == Set(theirs.customPronouns.keys) else { return false }
        return ours.customPronouns.allSatisfy { equal($0.value.id, theirs.customPronouns[$0.key]?.id) }
    }

    @ObjCMethod("hash")
    func hash() -> UInt {
        morphologyFeatures.reduce(0) { $0 &* 31 &+ UInt(bitPattern: feature($1.key)) }
    }

    @ObjCClassMethod("supportsSecureCoding") static func supportsSecureCoding(_ cls: ObjCClass) -> Bool { true }

    @ObjCMethod("encodeWithCoder:")
    func encode(coder: UnsafeMutableRawPointer?) {
        for feature in morphologyFeatures { grammarEncode(coder, integer: self.feature(feature.key), "NS." + feature.key) }
        if !storage.customPronouns.isEmpty {
            let entries = storage.customPronouns.map { (key: Strings.autoreleased($0.key), value: $0.value.id) }
            grammarEncode(coder, object: Dictionaries.autoreleased(entries), "NS.customPronouns")
        }
    }

    @ObjCMethod("initWithCoder:")
    func initialize(coder: UnsafeMutableRawPointer?) -> Self {
        let storage = MorphologyStorage()
        for feature in morphologyFeatures {
            let value = grammarDecodeInteger(coder, "NS." + feature.key)
            if value != 0 { storage.features[feature.key] = value }
        }
        for (key, value) in Dictionaries.entries(grammarDecodeObject(coder, "NS.customPronouns")) {
            if let language = Strings.value(of: key) { storage.customPronouns[language] = ObjCObject(value) }
        }
        Storage.set(objcObject, storage)
        return self
    }

    @ObjCMethod("description")
    func description() -> String { NSMorphology.describe(objcObject) }

    static func describe(_ object: id) -> String {
        let storage = Storage.get(object, as: MorphologyStorage.self) ?? MorphologyStorage()
        var parts = morphologyFeatures.map { feature -> String in
            let value = storage.features[feature.key] ?? 0
            return "\(feature.label) = \(value >= 0 && value < feature.names.count ? feature.names[value] : String(value))"
        }
        if storage.customPronouns.isEmpty {
            parts.append("customPronouns = (null)")
        } else {
            let entries = storage.customPronouns.map { (key: Strings.autoreleased($0.key), value: $0.value.id) }
            parts.append("customPronouns = " + (Strings.value(of: ObjC.send(Dictionaries.autoreleased(entries), ObjC.selector("description"))) ?? ""))
        }
        return "<\(ObjC.className(object)): \(object)> { " + parts.joined(separator: ", ") + " }"
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSMorphology.morphologyClass)
    }
}

// MARK: - Custom pronouns

final class CustomPronounStorage {
    var forms: [String: String] = [:]
}

/// Pronouns a person chose, by grammatical form: English only, as on Darwin.
@ObjCClass("NSMorphologyCustomPronoun")
open class NSMorphologyCustomPronoun: NSObject {
    nonisolated(unsafe) static var pronounClass: Class!

    static let forms = ["subjectForm", "objectForm", "possessiveForm", "possessiveAdjectiveForm", "reflexiveForm"]

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        pronounClass = cls.storage
    }

    static func supported(_ language: String) -> Bool { languageCode(language) == "en" }
    static func requiredKeys(_ language: String) -> [String] { supported(language) ? forms : [] }

    var storage: CustomPronounStorage {
        if let storage = Storage.get(objcObject, as: CustomPronounStorage.self) { return storage }
        let storage = CustomPronounStorage()
        Storage.set(objcObject, storage)
        return storage
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = storage
        return self
    }

    @ObjCClassMethod("isSupportedForLanguage:")
    static func isSupported(_ cls: ObjCClass, forLanguage language: String?) -> Bool { language.map { supported($0) } ?? false }

    @ObjCClassMethod("requiredKeysForLanguage:")
    static func requiredKeys(_ cls: ObjCClass, forLanguage language: String?) -> UnsafeMutableRawPointer? {
        let keys: [String] = language.map { requiredKeys($0) } ?? []
        return Arrays.autoreleased(keys.map { Strings.autoreleased($0) })
    }

    @ObjCMethod("subjectForm") func subjectForm() -> String? { storage.forms["subjectForm"] }
    @ObjCMethod("setSubjectForm:") func setSubjectForm(_ form: String?) { storage.forms["subjectForm"] = form }
    @ObjCMethod("objectForm") func objectForm() -> String? { storage.forms["objectForm"] }
    @ObjCMethod("setObjectForm:") func setObjectForm(_ form: String?) { storage.forms["objectForm"] = form }
    @ObjCMethod("possessiveForm") func possessiveForm() -> String? { storage.forms["possessiveForm"] }
    @ObjCMethod("setPossessiveForm:") func setPossessiveForm(_ form: String?) { storage.forms["possessiveForm"] = form }
    @ObjCMethod("possessiveAdjectiveForm") func possessiveAdjectiveForm() -> String? { storage.forms["possessiveAdjectiveForm"] }
    @ObjCMethod("setPossessiveAdjectiveForm:")
    func setPossessiveAdjectiveForm(_ form: String?) { storage.forms["possessiveAdjectiveForm"] = form }
    @ObjCMethod("reflexiveForm") func reflexiveForm() -> String? { storage.forms["reflexiveForm"] }
    @ObjCMethod("setReflexiveForm:") func setReflexiveForm(_ form: String?) { storage.forms["reflexiveForm"] = form }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        guard let copy = Storage.allocate(ObjC.objectGetClass(objcObject).map { UnsafeMutableRawPointer($0) }) else { return nil }
        let storage = CustomPronounStorage()
        storage.forms = self.storage.forms
        Storage.set(copy, storage)
        return copy
    }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: UnsafeMutableRawPointer?) -> Bool {
        guard let other else { return false }
        return other == objcObject || Storage.get(other, as: CustomPronounStorage.self)?.forms == storage.forms
    }

    @ObjCMethod("hash") func hash() -> UInt { UInt(bitPattern: storage.forms["subjectForm"]?.hashValue ?? 0) }

    @ObjCClassMethod("supportsSecureCoding") static func supportsSecureCoding(_ cls: ObjCClass) -> Bool { true }

    @ObjCMethod("encodeWithCoder:")
    func encode(coder: UnsafeMutableRawPointer?) {
        for (form, value) in storage.forms { grammarEncode(coder, object: Strings.autoreleased(value), "NS." + form) }
    }

    @ObjCMethod("initWithCoder:")
    func initialize(coder: UnsafeMutableRawPointer?) -> Self {
        let storage = CustomPronounStorage()
        for form in Self.forms {
            if let value = Strings.value(of: grammarDecodeObject(coder, "NS." + form)) { storage.forms[form] = value }
        }
        Storage.set(objcObject, storage)
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSMorphologyCustomPronoun.pronounClass)
    }
}

// MARK: - Pronouns

final class MorphologyPronounStorage {
    let pronoun: String
    let morphology: ObjCObject?
    let dependentMorphology: ObjCObject?

    init(pronoun: String, morphology: ObjCObject?, dependentMorphology: ObjCObject?) {
        self.pronoun = pronoun
        self.morphology = morphology
        self.dependentMorphology = dependentMorphology
    }
}

/// A pronoun and the morphology it has (and that of what depends on it).
@ObjCClass("NSMorphologyPronoun")
open class NSMorphologyPronoun: NSObject {
    nonisolated(unsafe) static var pronounClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        pronounClass = cls.storage
    }

    var storage: MorphologyPronounStorage? { Storage.get(objcObject, as: MorphologyPronounStorage.self) }

    @ObjCMethod("initWithPronoun:morphology:dependentMorphology:")
    func initialize(pronoun: String?, morphology: UnsafeMutableRawPointer?, dependentMorphology: UnsafeMutableRawPointer?) -> Self {
        Storage.set(objcObject, MorphologyPronounStorage(pronoun: pronoun ?? "", morphology: copyOf(morphology),
                                                         dependentMorphology: copyOf(dependentMorphology)))
        return self
    }

    @ObjCMethod("pronoun") func pronoun() -> String { storage?.pronoun ?? "" }
    @ObjCMethod("morphology") func morphology() -> UnsafeMutableRawPointer? { storage?.morphology?.id }
    @ObjCMethod("dependentMorphology") func dependentMorphology() -> UnsafeMutableRawPointer? { storage?.dependentMorphology?.id }

    /// Immutable: the copy is the pronoun.
    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { ObjC.retain(objcObject) }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: UnsafeMutableRawPointer?) -> Bool {
        guard let other else { return false }
        if other == objcObject { return true }
        guard let theirs = Storage.get(other, as: MorphologyPronounStorage.self), let ours = storage else { return false }
        return ours.pronoun == theirs.pronoun && equal(ours.morphology?.id, theirs.morphology?.id)
            && equal(ours.dependentMorphology?.id, theirs.dependentMorphology?.id)
    }

    @ObjCMethod("hash") func hash() -> UInt { UInt(bitPattern: storage?.pronoun.hashValue ?? 0) }

    @ObjCClassMethod("supportsSecureCoding") static func supportsSecureCoding(_ cls: ObjCClass) -> Bool { true }

    @ObjCMethod("encodeWithCoder:")
    func encode(coder: UnsafeMutableRawPointer?) {
        grammarEncode(coder, object: Strings.autoreleased(storage?.pronoun ?? ""), "NS.pronoun")
        grammarEncode(coder, object: storage?.morphology?.id, "NS.morphology")
        grammarEncode(coder, object: storage?.dependentMorphology?.id, "NS.dependentMorphology")
    }

    @ObjCMethod("initWithCoder:")
    func initialize(coder: UnsafeMutableRawPointer?) -> Self {
        Storage.set(objcObject, MorphologyPronounStorage(pronoun: Strings.value(of: grammarDecodeObject(coder, "NS.pronoun")) ?? "",
                                                         morphology: grammarDecodeObject(coder, "NS.morphology").map { ObjCObject($0) },
                                                         dependentMorphology: grammarDecodeObject(coder, "NS.dependentMorphology").map { ObjCObject($0) }))
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSMorphologyPronoun.pronounClass)
    }
}

// MARK: - Terms of address

final class TermOfAddressStorage {
    /// 1 neutral, 2 feminine, 3 masculine, 4 localized; 0 the user's,
    /// which is unspecified here.
    let kind: Int
    let languageIdentifier: String?
    let pronouns: ObjCObject?

    init(kind: Int, languageIdentifier: String? = nil, pronouns: ObjCObject? = nil) {
        self.kind = kind
        self.languageIdentifier = languageIdentifier
        self.pronouns = pronouns
    }
}

/// How to address a person: neutrally, as a woman, as a man, or with the
/// pronouns of a language.
@ObjCClass("NSTermOfAddress")
open class NSTermOfAddress: NSObject {
    nonisolated(unsafe) static var termClass: Class!
    nonisolated(unsafe) static var shared: [Int: id] = [:]

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        termClass = cls.storage
    }

    var storage: TermOfAddressStorage? { Storage.get(objcObject, as: TermOfAddressStorage.self) }

    /// One instance of each of the three, kept for good.
    private static func sharedTerm(_ kind: Int) -> UnsafeMutableRawPointer? {
        if let term = shared[kind] { return term }
        guard let object = Storage.allocate(UnsafeMutableRawPointer(termClass)) else { return nil }
        Storage.set(object, TermOfAddressStorage(kind: kind))
        shared[kind] = object
        return object
    }

    @ObjCClassMethod("neutral") static func neutral(_ cls: ObjCClass) -> UnsafeMutableRawPointer? { sharedTerm(1) }
    @ObjCClassMethod("feminine") static func feminine(_ cls: ObjCClass) -> UnsafeMutableRawPointer? { sharedTerm(2) }
    @ObjCClassMethod("masculine") static func masculine(_ cls: ObjCClass) -> UnsafeMutableRawPointer? { sharedTerm(3) }

    /// The user's, which no settings here specify.
    @ObjCClassMethod("currentUser")
    static func currentUser(_ cls: ObjCClass) -> UnsafeMutableRawPointer? {
        makeGrammar(UnsafeMutableRawPointer(termClass), TermOfAddressStorage(kind: 0))
    }

    @ObjCClassMethod("localizedForLanguageIdentifier:withPronouns:")
    static func localized(_ cls: ObjCClass, languageIdentifier: String?, pronouns: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        makeGrammar(UnsafeMutableRawPointer(termClass),
                    TermOfAddressStorage(kind: 4, languageIdentifier: languageIdentifier, pronouns: copyOf(pronouns)))
    }

    @ObjCMethod("languageIdentifier") func languageIdentifier() -> String? { storage?.languageIdentifier }
    @ObjCMethod("pronouns") func pronouns() -> UnsafeMutableRawPointer? { storage?.pronouns?.id }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { ObjC.retain(objcObject) }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: UnsafeMutableRawPointer?) -> Bool {
        guard let other else { return false }
        if other == objcObject { return true }
        guard let theirs = Storage.get(other, as: TermOfAddressStorage.self), let ours = storage else { return false }
        return ours.kind == theirs.kind && ours.languageIdentifier == theirs.languageIdentifier
            && equal(ours.pronouns?.id, theirs.pronouns?.id)
    }

    @ObjCMethod("hash") func hash() -> UInt { UInt(storage?.kind ?? 0) }

    @ObjCClassMethod("supportsSecureCoding") static func supportsSecureCoding(_ cls: ObjCClass) -> Bool { true }

    @ObjCMethod("encodeWithCoder:")
    func encode(coder: UnsafeMutableRawPointer?) {
        grammarEncode(coder, integer: storage?.kind ?? 0, "NS.kind")
        grammarEncode(coder, object: storage?.languageIdentifier.map { Strings.autoreleased($0) }, "NS.languageIdentifier")
        grammarEncode(coder, object: storage?.pronouns?.id, "NS.pronouns")
    }

    @ObjCMethod("initWithCoder:")
    func initialize(coder: UnsafeMutableRawPointer?) -> Self {
        Storage.set(objcObject, TermOfAddressStorage(kind: grammarDecodeInteger(coder, "NS.kind"),
                                                     languageIdentifier: Strings.value(of: grammarDecodeObject(coder, "NS.languageIdentifier")),
                                                     pronouns: grammarDecodeObject(coder, "NS.pronouns").map { ObjCObject($0) }))
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSTermOfAddress.termClass)
    }
}

// MARK: - Inflection rules

/// How a localized string is inflected: automatically, or by an explicit
/// morphology. Abstract, as on Darwin.
@ObjCClass("NSInflectionRule")
open class NSInflectionRule: NSObject {
    /// The languages Darwin inflects.
    static let inflectedLanguages: Set<String> = ["en", "es", "fr", "de", "it", "pt", "ko", "nl", "hi"]

    @ObjCClassMethod("automaticRule")
    static func automaticRule(_ cls: ObjCClass) -> UnsafeMutableRawPointer? { NSInflectionRuleAutomatic.shared() }

    @ObjCClassMethod("canInflectLanguage:")
    static func canInflect(_ cls: ObjCClass, language: String?) -> Bool {
        language.map { inflectedLanguages.contains(languageCode($0)) } ?? false
    }

    /// Whether the app's first preferred localization is inflected.
    @ObjCClassMethod("canInflectPreferredLocalization")
    static func canInflectPreferredLocalization(_ cls: ObjCClass) -> Bool {
        let main = ObjC.send(grammarClass("NSBundle"), ObjC.selector("mainBundle"))
        let preferred = Arrays.elements(ObjC.send(main, ObjC.selector("preferredLocalizations"))).first.flatMap { Strings.value(of: $0) }
        return inflectedLanguages.contains(languageCode(preferred ?? "en"))
    }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { ObjC.retain(objcObject) }

    @ObjCClassMethod("supportsSecureCoding") static func supportsSecureCoding(_ cls: ObjCClass) -> Bool { true }

    @ObjCMethod("encodeWithCoder:") func encode(coder: UnsafeMutableRawPointer?) {}
    @ObjCMethod("initWithCoder:") func initialize(coder: UnsafeMutableRawPointer?) -> Self { self }
}

/// +automaticRule's class.
@ObjCClass("_NSInflectionRuleAutomatic")
public final class NSInflectionRuleAutomatic: NSInflectionRule {
    nonisolated(unsafe) static var automaticClass: Class!
    nonisolated(unsafe) static var instance: id?

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        automaticClass = cls.storage
    }

    /// The one instance, kept for good.
    static func shared() -> UnsafeMutableRawPointer? {
        if let instance { return instance }
        instance = ObjC.send(ObjC.send(UnsafeMutableRawPointer(automaticClass), ObjC.selector("alloc")), ObjC.selector("init"))
        return instance
    }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: UnsafeMutableRawPointer?) -> Bool {
        guard let other, let cls = NSInflectionRuleAutomatic.automaticClass else { return false }
        return ObjC.isKind(other, of: cls)
    }

    @ObjCMethod("hash") func hash() -> UInt { 1 }

    @ObjCMethod("description")
    func description() -> String { "<\(ObjC.className(objcObject)): \(objcObject)> (automatic inflection rule)" }
}

final class InflectionRuleStorage {
    let morphology: ObjCObject?

    init(morphology: ObjCObject?) { self.morphology = morphology }
}

@ObjCClass("NSInflectionRuleExplicit")
open class NSInflectionRuleExplicit: NSInflectionRule {
    nonisolated(unsafe) static var explicitClass: Class!

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        explicitClass = cls.storage
    }

    var storage: InflectionRuleStorage? { Storage.get(objcObject, as: InflectionRuleStorage.self) }

    /// A copy of the morphology.
    @ObjCMethod("initWithMorphology:")
    func initialize(morphology: UnsafeMutableRawPointer?) -> Self {
        Storage.set(objcObject, InflectionRuleStorage(morphology: copyOf(morphology)))
        return self
    }

    @ObjCMethod("morphology") func morphology() -> UnsafeMutableRawPointer? { storage?.morphology?.id }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: UnsafeMutableRawPointer?) -> Bool {
        guard let other else { return false }
        if other == objcObject { return true }
        guard let theirs = Storage.get(other, as: InflectionRuleStorage.self) else { return false }
        return equal(storage?.morphology?.id, theirs.morphology?.id)
    }

    @ObjCMethod("hash")
    func hash() -> UInt { storage?.morphology.map { ObjC.sendUInt($0.id, Selectors.hash) } ?? 0 }

    @ObjCMethod("encodeWithCoder:")
    func encodeExplicit(coder: UnsafeMutableRawPointer?) { grammarEncode(coder, object: storage?.morphology?.id, "NS.morphology") }

    @ObjCMethod("initWithCoder:")
    func initializeExplicit(coder: UnsafeMutableRawPointer?) -> Self {
        Storage.set(objcObject, InflectionRuleStorage(morphology: grammarDecodeObject(coder, "NS.morphology").map { ObjCObject($0) }))
        return self
    }

    @ObjCMethod("description")
    func description() -> String {
        let morphology = storage?.morphology.map { NSMorphology.describe($0.id) } ?? "(null)"
        return "<\(ObjC.className(objcObject)): \(objcObject)> { morphology = \(morphology) }"
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: NSInflectionRuleExplicit.explicitClass)
    }
}

// MARK: - Number format rules

/// How numbers in a localized string are formatted. Abstract, as on Darwin.
@ObjCClass("NSLocalizedNumberFormatRule")
open class NSLocalizedNumberFormatRule: NSObject {
    @ObjCClassMethod("automatic")
    static func automatic(_ cls: ObjCClass) -> UnsafeMutableRawPointer? { NSLocalizedNumberFormatRuleAutomatic.shared() }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { ObjC.retain(objcObject) }

    @ObjCClassMethod("supportsSecureCoding") static func supportsSecureCoding(_ cls: ObjCClass) -> Bool { true }

    @ObjCMethod("encodeWithCoder:") func encode(coder: UnsafeMutableRawPointer?) {}
    @ObjCMethod("initWithCoder:") func initialize(coder: UnsafeMutableRawPointer?) -> Self { self }
}

/// +automatic's class.
@ObjCClass("_NSLocalizedNumberFormatRuleAutomatic")
public final class NSLocalizedNumberFormatRuleAutomatic: NSLocalizedNumberFormatRule {
    nonisolated(unsafe) static var automaticClass: Class!
    nonisolated(unsafe) static var instance: id?

    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        automaticClass = cls.storage
    }

    static func shared() -> UnsafeMutableRawPointer? {
        if let instance { return instance }
        instance = ObjC.send(ObjC.send(UnsafeMutableRawPointer(automaticClass), ObjC.selector("alloc")), ObjC.selector("init"))
        return instance
    }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: UnsafeMutableRawPointer?) -> Bool {
        guard let other, let cls = NSLocalizedNumberFormatRuleAutomatic.automaticClass else { return false }
        return ObjC.isKind(other, of: cls)
    }

    @ObjCMethod("hash") func hash() -> UInt { 1 }

    @ObjCMethod("description")
    func description() -> String { "<\(ObjC.className(objcObject)): \(objcObject)> (format number rule)" }
}
