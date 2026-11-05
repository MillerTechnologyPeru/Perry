// Grammatical agreement: a word's morphology, which automatic grammar
// agreement inflects text to, and the attributed string attributes that
// carry it and inline presentation (emphasis, code, strikethrough).

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
public struct Morphology: Sendable, Hashable {
    public init() {}

    public enum GrammaticalGender: Int, Hashable, Sendable, Codable, CaseIterable {
        case feminine, masculine, neuter
    }
    public var grammaticalGender: GrammaticalGender?

    public enum PartOfSpeech: Int, Hashable, Sendable, Codable, CaseIterable {
        case determiner, pronoun, letter, adverb, particle, adjective, adposition, verb, noun, conjunction,
             numeral, interjection, preposition, abbreviation
    }
    public var partOfSpeech: PartOfSpeech?

    public enum GrammaticalNumber: Int, Hashable, Sendable, Codable, CaseIterable {
        case singular, zero, plural, pluralTwo, pluralFew, pluralMany
    }
    public var number: GrammaticalNumber?

    public enum GrammaticalCase: Int, Hashable, Sendable, Codable, CaseIterable {
        case nominative, accusative, dative, genitive, prepositional, ablative, adessive, allative, elative,
             illative, essive, inessive, locative, translative
    }
    public var grammaticalCase: GrammaticalCase?

    public enum GrammaticalPerson: Int, Hashable, Sendable, Codable, CaseIterable {
        case first, second, third
    }
    public var grammaticalPerson: GrammaticalPerson?

    public enum PronounType: Int, Hashable, Sendable, Codable, CaseIterable {
        case personal, reflexive, possessive
    }
    public var pronounType: PronounType?

    public enum Determination: Int, Hashable, Sendable, Codable, CaseIterable {
        case independent, dependent
    }
    public var determination: Determination?

    public enum Definiteness: Int, Hashable, Sendable, Codable, CaseIterable {
        case indefinite, definite
    }
    public var definiteness: Definiteness?
}

/// How text is inflected: by the grammar around it, or to a morphology.
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
public enum InflectionRule: Sendable, Hashable {
    case automatic
    case explicit(Morphology)

    public init(morphology: Morphology) {
        self = .explicit(morphology)
    }
}

// Foundation's coding, which Markdown's ^[…](morphology: {…}, inflect: …)
// attributes are read with: each value by its case's name, a grammatical
// number by its CLDR plural category ("one", "other"…), and an inflection
// rule as true when automatic.

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension Morphology: Codable {
    enum CodingKeys: String, CodingKey {
        case grammaticalGender, partOfSpeech, number, grammaticalCase, grammaticalPerson, pronounType, determination,
             definiteness
    }

    static let numberNames: [GrammaticalNumber: String] = [
        .singular: "one", .zero: "zero", .plural: "other", .pluralTwo: "two", .pluralFew: "few", .pluralMany: "many",
    ]

    private static func name<T: CaseIterable>(_ value: T) -> String { String(describing: value) }

    private static func decode<T: CaseIterable>(_ type: T.Type, _ container: KeyedDecodingContainer<CodingKeys>,
                                                _ key: CodingKeys, names: (T) -> String = name) throws -> T? {
        guard let text = try container.decodeIfPresent(String.self, forKey: key) else { return nil }
        guard let value = T.allCases.first(where: { names($0) == text }) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Unknown \(key.stringValue) \(text)")
        }
        return value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        grammaticalGender = try Self.decode(GrammaticalGender.self, container, .grammaticalGender)
        partOfSpeech = try Self.decode(PartOfSpeech.self, container, .partOfSpeech)
        number = try Self.decode(GrammaticalNumber.self, container, .number) { Self.numberNames[$0] ?? "" }
        grammaticalCase = try Self.decode(GrammaticalCase.self, container, .grammaticalCase)
        grammaticalPerson = try Self.decode(GrammaticalPerson.self, container, .grammaticalPerson)
        pronounType = try Self.decode(PronounType.self, container, .pronounType)
        determination = try Self.decode(Determination.self, container, .determination)
        definiteness = try Self.decode(Definiteness.self, container, .definiteness)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(grammaticalGender.map(Self.name), forKey: .grammaticalGender)
        try container.encodeIfPresent(partOfSpeech.map(Self.name), forKey: .partOfSpeech)
        try container.encodeIfPresent(number.flatMap { Self.numberNames[$0] }, forKey: .number)
        try container.encodeIfPresent(grammaticalCase.map(Self.name), forKey: .grammaticalCase)
        try container.encodeIfPresent(grammaticalPerson.map(Self.name), forKey: .grammaticalPerson)
        try container.encodeIfPresent(pronounType.map(Self.name), forKey: .pronounType)
        try container.encodeIfPresent(determination.map(Self.name), forKey: .determination)
        try container.encodeIfPresent(definiteness.map(Self.name), forKey: .definiteness)
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension InflectionRule: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let automatic = try? container.decode(Bool.self) {
            guard automatic else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "An inflection rule is true or a morphology")
            }
            self = .automatic
        } else {
            self = .explicit(try container.decode(Morphology.self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .automatic: try container.encode(true)
        case .explicit(let morphology): try container.encode(morphology)
        }
    }
}

/// An attribute whose value converts to and from an Objective-C object,
/// for NSAttributedString.
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
public protocol ObjectiveCConvertibleAttributedStringKey: AttributedStringKey {
    associatedtype ObjectiveCValue: NSObject
    static func objectiveCValue(for value: Value) throws -> ObjectiveCValue
    static func value(for object: ObjectiveCValue) throws -> Value
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension ObjectiveCConvertibleAttributedStringKey
    where ObjectiveCValue == NSNumber, Value: RawRepresentable, Value.RawValue == Int {
    public static func objectiveCValue(for value: Value) throws -> NSNumber {
        NSNumber(value: value.rawValue)
    }

    public static func value(for object: NSNumber) throws -> Value {
        guard let value = Value(rawValue: object.intValue) else { throw _InvalidObjectiveCValue() }
        return value
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension AttributeScopes.FoundationAttributes {
    @frozen public enum MorphologyAttribute: CodableAttributedStringKey, MarkdownDecodableAttributedStringKey {
        public typealias Value = Morphology
        public static let name = "NSMorphology"
        public static let markdownName = "morphology"
    }

    @frozen public enum InflectionRuleAttribute: CodableAttributedStringKey, MarkdownDecodableAttributedStringKey {
        public typealias Value = InflectionRule
        public static let name = "NSInflect"
        public static let markdownName = "inflect"
    }

    @frozen public enum InlinePresentationIntentAttribute: CodableAttributedStringKey, ObjectiveCConvertibleAttributedStringKey {
        public typealias Value = InlinePresentationIntent
        public typealias ObjectiveCValue = NSNumber
        public static let name = "NSInlinePresentationIntent"

        public static func objectiveCValue(for value: InlinePresentationIntent) throws -> NSNumber {
            NSNumber(value: value.rawValue)
        }

        public static func value(for object: NSNumber) throws -> InlinePresentationIntent {
            InlinePresentationIntent(rawValue: object.uintValue)
        }
    }

    // Typed as the attributes, as Foundation's stored ones are, so key paths
    // to them bind by the names apps and SwiftUI use (run.inlinePresentation-
    // Intent); only their types are ever used.
    public var morphology: MorphologyAttribute { fatalError("attribute keys have no values") }
    public var inflect: InflectionRuleAttribute { fatalError("attribute keys have no values") }
    public var inlinePresentationIntent: InlinePresentationIntentAttribute { fatalError("attribute keys have no values") }
}

/// An Objective-C value that is not one of the attribute's values.
struct _InvalidObjectiveCValue: Error {}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension InlinePresentationIntent: @retroactive @unchecked Sendable, @retroactive Hashable {}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension InlinePresentationIntent: @retroactive Codable {
    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(UInt.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
