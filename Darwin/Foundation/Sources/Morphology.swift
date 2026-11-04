// Grammatical agreement: a word's morphology, which automatic grammar
// agreement inflects text to, and the attributed string attributes that
// carry it and inline presentation (emphasis, code, strikethrough).

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
public struct Morphology: Sendable, Hashable, Codable {
    public init() {}

    public enum GrammaticalGender: Int, Hashable, Sendable, Codable {
        case feminine, masculine, neuter
    }
    public var grammaticalGender: GrammaticalGender?

    public enum PartOfSpeech: Int, Hashable, Sendable, Codable {
        case determiner, pronoun, letter, adverb, particle, adjective, adposition, verb, noun, conjunction,
             numeral, interjection, preposition, abbreviation
    }
    public var partOfSpeech: PartOfSpeech?

    public enum GrammaticalNumber: Int, Hashable, Sendable, Codable {
        case singular, zero, plural, pluralTwo, pluralFew, pluralMany
    }
    public var number: GrammaticalNumber?

    public enum GrammaticalCase: Int, Hashable, Sendable, Codable {
        case nominative, accusative, dative, genitive, prepositional, ablative, adessive, allative, elative,
             illative, essive, inessive, locative, translative
    }
    public var grammaticalCase: GrammaticalCase?

    public enum GrammaticalPerson: Int, Hashable, Sendable, Codable {
        case first, second, third
    }
    public var grammaticalPerson: GrammaticalPerson?

    public enum PronounType: Int, Hashable, Sendable, Codable {
        case personal, reflexive, possessive
    }
    public var pronounType: PronounType?

    public enum Determination: Int, Hashable, Sendable, Codable {
        case independent, dependent
    }
    public var determination: Determination?

    public enum Definiteness: Int, Hashable, Sendable, Codable {
        case indefinite, definite
    }
    public var definiteness: Definiteness?
}

/// How text is inflected: by the grammar around it, or to a morphology.
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
public enum InflectionRule: Sendable, Hashable, Codable {
    case automatic
    case explicit(Morphology)

    public init(morphology: Morphology) {
        self = .explicit(morphology)
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

    public var morphology: MorphologyAttribute.Type { MorphologyAttribute.self }
    public var inflect: InflectionRuleAttribute.Type { InflectionRuleAttribute.self }
    public var inlinePresentationIntent: InlinePresentationIntentAttribute.Type { InlinePresentationIntentAttribute.self }
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
