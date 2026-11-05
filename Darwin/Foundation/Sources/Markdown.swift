@_spi(Reflection) import Swift

// Markdown in Swift: AttributedString's parsing options and source
// positions, presentation intents and their attributes, which
// swift-foundation leaves to Apple's own build, and the Markdown
// initializers. Those parse with NSAttributedString's importer, Foundation's
// one parser (swift-cmark), and read its runs back into an AttributedString:
// intents, links, images, list delimiters and source positions, and
// ^[…](…) attributes decoded into the scope asked for.

// MARK: PresentationIntent

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
public struct PresentationIntent: Hashable, Codable, CustomDebugStringConvertible, Sendable {
    /// The block's own intent first, then those of the blocks around it.
    public var components: [IntentType]

    public var count: Int { components.count }

    public var debugDescription: String {
        "[" + components.map(\.debugDescription).joined(separator: ", ") + "]"
    }

    public enum Kind: Hashable, Codable, CustomDebugStringConvertible, Sendable {
        case paragraph
        case header(level: Int)
        case orderedList
        case unorderedList
        case listItem(ordinal: Int)
        case codeBlock(languageHint: String?)
        case blockQuote
        case thematicBreak
        case table(columns: [TableColumn])
        case tableHeaderRow
        case tableRow(rowIndex: Int)
        case tableCell(columnIndex: Int)

        public var debugDescription: String {
            switch self {
            case .paragraph: "paragraph"
            case .header(let level): "header \(level)"
            case .orderedList: "orderedList"
            case .unorderedList: "unorderedList"
            case .listItem(let ordinal): "listItem \(ordinal)"
            case .codeBlock(let hint): "codeBlock '\(hint ?? "<none>")'"
            case .blockQuote: "blockQuote"
            case .thematicBreak: "thematicBreak"
            case .table(let columns): "table \(columns)"
            case .tableHeaderRow: "tableHeaderRow"
            case .tableRow(let row): "tableRow \(row)"
            case .tableCell(let column): "tableCell \(column)"
            }
        }

        /// Foundation's form: the case's name, then its value if it has one,
        /// in an array (["listItem", 2], ["paragraph"]).
        public init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            let name = try container.decode(String.self)
            switch name {
            case "paragraph": self = .paragraph
            case "header": self = .header(level: try container.decode(Int.self))
            case "orderedList": self = .orderedList
            case "unorderedList": self = .unorderedList
            case "listItem": self = .listItem(ordinal: try container.decode(Int.self))
            case "codeBlock": self = .codeBlock(languageHint: container.isAtEnd ? nil : try container.decodeNil() ? nil : try container.decode(String.self))
            case "blockQuote": self = .blockQuote
            case "thematicBreak": self = .thematicBreak
            case "table": self = .table(columns: try container.decode([TableColumn].self))
            case "tableHeaderRow": self = .tableHeaderRow
            case "tableRow": self = .tableRow(rowIndex: try container.decode(Int.self))
            case "tableCell": self = .tableCell(columnIndex: try container.decode(Int.self))
            default:
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown presentation intent kind \(name)")
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.unkeyedContainer()
            switch self {
            case .paragraph: try container.encode("paragraph")
            case .header(let level): try container.encode("header"); try container.encode(level)
            case .orderedList: try container.encode("orderedList")
            case .unorderedList: try container.encode("unorderedList")
            case .listItem(let ordinal): try container.encode("listItem"); try container.encode(ordinal)
            case .codeBlock(let hint):
                try container.encode("codeBlock")
                if let hint { try container.encode(hint) }
            case .blockQuote: try container.encode("blockQuote")
            case .thematicBreak: try container.encode("thematicBreak")
            case .table(let columns): try container.encode("table"); try container.encode(columns)
            case .tableHeaderRow: try container.encode("tableHeaderRow")
            case .tableRow(let row): try container.encode("tableRow"); try container.encode(row)
            case .tableCell(let column): try container.encode("tableCell"); try container.encode(column)
            }
        }
    }

    public struct TableColumn: Hashable, Codable, Sendable {
        public enum Alignment: Int, Hashable, Codable, Sendable {
            case left
            case center
            case right
        }

        public var alignment: Alignment

        public init(alignment: Alignment) {
            self.alignment = alignment
        }
    }

    public struct IntentType: Hashable, Codable, CustomDebugStringConvertible, Sendable {
        public var kind: Kind
        /// Which block this is, among the document's blocks.
        public var identity: Int

        public var debugDescription: String { "\(kind.debugDescription) (id \(identity))" }
    }

    public init(_ kind: Kind, identity: Int, parent: PresentationIntent? = nil) {
        components = [IntentType(kind: kind, identity: identity)] + (parent?.components ?? [])
    }

    public init(types: [IntentType]) {
        components = types
    }

    /// Each component is a different block.
    public var isValid: Bool {
        Set(components.map(\.identity)).count == components.count
    }

    /// How many list items and block quotes the block is in.
    public var indentationLevel: Int {
        components.reduce(0) { level, component in
            switch component.kind {
            case .listItem, .blockQuote: level + 1
            default: level
            }
        }
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension PresentationIntent: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = __NSPresentationIntent

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> __NSPresentationIntent {
        var parent: __NSPresentationIntent?
        for component in components.reversed() {
            parent = Self.objectiveC(component, parent: parent)
        }
        return parent ?? __NSPresentationIntent.paragraphIntent(withIdentity: 0, nestedInside: nil)
    }

    static func objectiveC(_ component: IntentType, parent: __NSPresentationIntent?) -> __NSPresentationIntent {
        let identity = component.identity
        switch component.kind {
        case .paragraph: return .paragraphIntent(withIdentity: identity, nestedInside: parent)
        case .header(let level): return .headerIntent(withIdentity: identity, level: level, nestedInside: parent)
        case .orderedList: return .orderedListIntent(withIdentity: identity, nestedInside: parent)
        case .unorderedList: return .unorderedListIntent(withIdentity: identity, nestedInside: parent)
        case .listItem(let ordinal): return .listItemIntent(withIdentity: identity, ordinal: ordinal, nestedInside: parent)
        case .codeBlock(let hint): return .codeBlockIntent(withIdentity: identity, languageHint: hint, nestedInside: parent)
        case .blockQuote: return .blockQuoteIntent(withIdentity: identity, nestedInside: parent)
        case .thematicBreak: return .thematicBreak(withIdentity: identity, nestedInside: parent)
        case .table(let columns):
            return .tableIntent(withIdentity: identity, columnCount: columns.count,
                                alignments: columns.map { NSNumber(value: $0.alignment.rawValue) }, nestedInside: parent)
        case .tableHeaderRow: return .tableHeaderRowIntent(withIdentity: identity, nestedInside: parent)
        case .tableRow(let row): return .tableRowIntent(withIdentity: identity, row: row, nestedInside: parent)
        case .tableCell(let column): return .tableCellIntent(withIdentity: identity, column: column, nestedInside: parent)
        }
    }

    static func kind(of intent: __NSPresentationIntent) -> Kind {
        switch intent.intentKind.rawValue {
        case 1: return .header(level: intent.headerLevel)
        case 2: return .orderedList
        case 3: return .unorderedList
        case 4: return .listItem(ordinal: intent.ordinal)
        case 5: return .codeBlock(languageHint: intent.languageHint)
        case 6: return .blockQuote
        case 7: return .thematicBreak
        case 8:
            let alignments = intent.columnAlignments ?? []
            return .table(columns: (0..<intent.columnCount).map { column in
                let raw = column < alignments.count ? alignments[column].intValue : 0
                return TableColumn(alignment: TableColumn.Alignment(rawValue: raw) ?? .left)
            })
        case 9: return .tableHeaderRow
        case 10: return .tableRow(rowIndex: intent.row)
        case 11: return .tableCell(columnIndex: intent.column)
        default: return .paragraph
        }
    }

    static func bridging(_ source: __NSPresentationIntent) -> PresentationIntent {
        var components: [IntentType] = []
        var current: __NSPresentationIntent? = source
        while let intent = current {
            components.append(IntentType(kind: kind(of: intent), identity: intent.identity))
            current = intent.parent
        }
        return PresentationIntent(types: components)
    }

    public static func _forceBridgeFromObjectiveC(_ source: __NSPresentationIntent, result: inout PresentationIntent?) {
        result = bridging(source)
    }

    @discardableResult
    public static func _conditionallyBridgeFromObjectiveC(_ source: __NSPresentationIntent,
                                                          result: inout PresentationIntent?) -> Bool {
        result = bridging(source)
        return true
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: __NSPresentationIntent?) -> PresentationIntent {
        bridging(source!)
    }
}

// MARK: Parsing options and source positions

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension AttributedString {
    public struct MarkdownParsingOptions: Sendable {
        public enum FailurePolicy: Int, Sendable {
            case throwError
            case returnPartiallyParsedIfPossible
        }

        public enum InterpretedSyntax: Int, Sendable {
            case full
            case inlineOnly
            case inlineOnlyPreservingWhitespace
        }

        public var allowsExtendedAttributes: Bool
        public var interpretedSyntax: InterpretedSyntax
        public var failurePolicy: FailurePolicy
        public var languageCode: String?
        var _appliesSourcePositionAttributes = false

        @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
        public var appliesSourcePositionAttributes: Bool {
            get { _appliesSourcePositionAttributes }
            set { _appliesSourcePositionAttributes = newValue }
        }

        public init(allowsExtendedAttributes: Bool = false, interpretedSyntax: InterpretedSyntax = .full,
                    failurePolicy: FailurePolicy = .throwError, languageCode: String? = nil) {
            self.allowsExtendedAttributes = allowsExtendedAttributes
            self.interpretedSyntax = interpretedSyntax
            self.failurePolicy = failurePolicy
            self.languageCode = languageCode
        }

        @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
        public init(allowsExtendedAttributes: Bool = false, interpretedSyntax: InterpretedSyntax = .full,
                    failurePolicy: FailurePolicy = .throwError, languageCode: String? = nil,
                    appliesSourcePositionAttributes: Bool = false) {
            self.init(allowsExtendedAttributes: allowsExtendedAttributes, interpretedSyntax: interpretedSyntax,
                      failurePolicy: failurePolicy, languageCode: languageCode)
            _appliesSourcePositionAttributes = appliesSourcePositionAttributes
        }
    }

    /// Where text was in its Markdown: 1-based lines, and 1-based UTF-8
    /// columns whose end is inclusive.
    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
    public struct MarkdownSourcePosition: Hashable, Codable, Sendable {
        public let startLine: Int
        public let startColumn: Int
        public let endLine: Int
        public let endColumn: Int

        public init(startLine: Int, startColumn: Int, endLine: Int, endColumn: Int) {
            self.startLine = startLine
            self.startColumn = startColumn
            self.endLine = endLine
            self.endColumn = endColumn
        }
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension AttributedString.MarkdownParsingOptions: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = __NSAttributedStringMarkdownParsingOptions

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> __NSAttributedStringMarkdownParsingOptions {
        let options = __NSAttributedStringMarkdownParsingOptions()
        options.allowsExtendedAttributes = allowsExtendedAttributes
        options.interpretedSyntax = __NSAttributedStringMarkdownInterpretedSyntax(rawValue: interpretedSyntax.rawValue)!
        options.failurePolicy = __NSAttributedStringMarkdownParsingFailurePolicy(rawValue: failurePolicy.rawValue)!
        options.languageCode = languageCode
        options.appliesSourcePositionAttributes = _appliesSourcePositionAttributes
        return options
    }

    static func bridging(_ source: __NSAttributedStringMarkdownParsingOptions) -> Self {
        var options = Self(allowsExtendedAttributes: source.allowsExtendedAttributes,
                           interpretedSyntax: InterpretedSyntax(rawValue: source.interpretedSyntax.rawValue) ?? .full,
                           failurePolicy: FailurePolicy(rawValue: source.failurePolicy.rawValue) ?? .throwError,
                           languageCode: source.languageCode)
        options._appliesSourcePositionAttributes = source.appliesSourcePositionAttributes
        return options
    }

    public static func _forceBridgeFromObjectiveC(_ x: __NSAttributedStringMarkdownParsingOptions, result: inout Self?) {
        result = bridging(x)
    }

    @discardableResult
    public static func _conditionallyBridgeFromObjectiveC(_ x: __NSAttributedStringMarkdownParsingOptions,
                                                          result: inout Self?) -> Bool {
        result = bridging(x)
        return true
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: __NSAttributedStringMarkdownParsingOptions?) -> Self {
        source.map(bridging) ?? Self()
    }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
extension AttributedString.MarkdownSourcePosition: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = __NSAttributedStringMarkdownSourcePosition

    @_semantics("convertToObjectiveC")
    public func _bridgeToObjectiveC() -> __NSAttributedStringMarkdownSourcePosition {
        __NSAttributedStringMarkdownSourcePosition(startLine: startLine, startColumn: startColumn,
                                                   endLine: endLine, endColumn: endColumn)
    }

    static func bridging(_ source: __NSAttributedStringMarkdownSourcePosition) -> Self {
        Self(startLine: source.startLine, startColumn: source.startColumn, endLine: source.endLine, endColumn: source.endColumn)
    }

    public static func _forceBridgeFromObjectiveC(_ x: __NSAttributedStringMarkdownSourcePosition, result: inout Self?) {
        result = bridging(x)
    }

    @discardableResult
    public static func _conditionallyBridgeFromObjectiveC(_ x: __NSAttributedStringMarkdownSourcePosition,
                                                          result: inout Self?) -> Bool {
        result = bridging(x)
        return true
    }

    @_effects(readonly)
    public static func _unconditionallyBridgeFromObjectiveC(_ source: __NSAttributedStringMarkdownSourcePosition?) -> Self {
        bridging(source!)
    }
}

// MARK: Attributes

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension AttributeScopes.FoundationAttributes {
    @frozen public enum PresentationIntentAttribute: CodableAttributedStringKey {
        public typealias Value = PresentationIntent
        public static let name = "NSPresentationIntent"
    }

    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
    @frozen public enum MarkdownSourcePositionAttribute: CodableAttributedStringKey {
        public static let name = "NSMarkdownSourcePosition"
        public typealias Value = AttributedString.MarkdownSourcePosition
    }

    /// The marker of the list item text is in: "-", "+", "*", "." or ")".
    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    @frozen public enum ListItemDelimiterAttribute: CodableAttributedStringKey, ObjectiveCConvertibleAttributedStringKey {
        public typealias Value = Character
        public typealias ObjectiveCValue = NSString
        public static let name = "NSListItemDelimiter"

        public static func objectiveCValue(for value: Character) throws -> NSString {
            String(value)._bridgeToObjectiveC()
        }

        public static func value(for object: NSString) throws -> Character {
            let string = String._unconditionallyBridgeFromObjectiveC(object)
            guard string.count == 1, let character = string.first else { throw _InvalidObjectiveCValue() }
            return character
        }

        public static func encode(_ value: Character, to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(String(value))
        }

        public static func decode(from decoder: any Decoder) throws -> Character {
            let string = try decoder.singleValueContainer().decode(String.self)
            guard string.count == 1, let character = string.first else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath,
                                                                        debugDescription: "Not one character"))
            }
            return character
        }
    }

    // Foundation's scope holds these as stored attributes; here they are
    // only key paths' members, never read.
    public var presentationIntent: PresentationIntentAttribute { fatalError("attribute keys have no values") }

    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
    public var markdownSourcePosition: MarkdownSourcePositionAttribute { fatalError("attribute keys have no values") }

    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    public var listItemDelimiter: ListItemDelimiterAttribute { fatalError("attribute keys have no values") }
}

// MARK: Parsing

/// AttributedString from NSAttributedString's Markdown.
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
enum _MarkdownImport {
    /// The private attribute NSAttributedString keeps ^[…](…) sources in
    /// for Swift, which decodes them into its scopes.
    static let extendedAttributeSources = NSAttributedString.Key("NSMarkdownExtendedAttributeSources")

    static func attributedString(
        _ parse: (__NSAttributedStringMarkdownParsingOptions) throws -> NSAttributedString,
        scope: any AttributeScope.Type, options: AttributedString.MarkdownParsingOptions
    ) throws -> AttributedString {
        let objectiveC = options._bridgeToObjectiveC()
        // Private to Perry's NSAttributedString: extended attributes come
        // back as their sources, and empty Markdown as an empty string.
        _ = objectiveC.perform(Selector(("_perryImportForSwift")))
        let source = try parse(objectiveC)
        let keys = options.allowsExtendedAttributes ? markdownKeys(scope) : [:]
        var result = AttributedString()
        var failure: (any Error)?
        source.enumerateAttributes(in: NSRange(location: 0, length: source.length), options: []) { attributes, range, stop in
            do {
                let container = try self.container(attributes, keys: keys, policy: options.failurePolicy)
                result.append(AttributedString(source.attributedSubstring(from: range).string, attributes: container))
            } catch {
                failure = error
                stop.pointee = true
            }
        }
        if let failure { throw failure }
        return result
    }

    static func container(_ attributes: [NSAttributedString.Key: Any],
                          keys: [String: any MarkdownDecodableAttributedStringKey.Type],
                          policy: AttributedString.MarkdownParsingOptions.FailurePolicy) throws -> AttributeContainer {
        typealias Keys = AttributeScopes.FoundationAttributes
        var container = AttributeContainer()
        if let number = attributes[NSAttributedString.Key("NSInlinePresentationIntent")] as? NSNumber {
            container[Keys.InlinePresentationIntentAttribute.self] = InlinePresentationIntent(rawValue: number.uintValue)
        }
        if let intent = attributes[NSAttributedString.Key("NSPresentationIntent")] as? __NSPresentationIntent {
            container[Keys.PresentationIntentAttribute.self] = PresentationIntent.bridging(intent)
        }
        if let link = attributes[NSAttributedString.Key("NSLink")] as? URL {
            container[Keys.LinkAttribute.self] = link
        }
        if let image = attributes[NSAttributedString.Key("NSImageURL")] as? URL {
            container[Keys.ImageURLAttribute.self] = image
        }
        if let description = attributes[NSAttributedString.Key("NSAlternateDescription")] as? String {
            container[Keys.AlternateDescriptionAttribute.self] = description
        }
        if #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *),
           let delimiter = attributes[NSAttributedString.Key("NSListItemDelimiter")] as? String,
           delimiter.count == 1, let character = delimiter.first {
            container[Keys.ListItemDelimiterAttribute.self] = character
        }
        if let position = attributes[NSAttributedString.Key("NSMarkdownSourcePosition")]
            as? __NSAttributedStringMarkdownSourcePosition {
            container[Keys.MarkdownSourcePositionAttribute.self] = AttributedString.MarkdownSourcePosition.bridging(position)
        }
        for source in attributes[extendedAttributeSources] as? [String] ?? [] {
            do {
                // Inner attributes win over outer ones.
                container.merge(try extendedAttributes(source, keys: keys))
            } catch where policy == .returnPartiallyParsedIfPossible {
                continue
            }
        }
        return container
    }

    /// ^[…](source)'s attributes that the scope has Markdown names for:
    /// the source is a JSON5 object's members without the braces.
    static func extendedAttributes(_ source: String,
                                   keys: [String: any MarkdownDecodableAttributedStringKey.Type]) throws -> AttributeContainer {
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        return try decoder.decode(ExtendedAttributes.self, from: Data("{\(source)}".utf8),
                                  configuration: ExtendedAttributes.Keys(keys)).container
    }

    struct ExtendedAttributes: DecodableWithConfiguration {
        final class Keys: @unchecked Sendable {
            let types: [String: any MarkdownDecodableAttributedStringKey.Type]
            init(_ types: [String: any MarkdownDecodableAttributedStringKey.Type]) { self.types = types }
        }

        struct Name: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }

        var container = AttributeContainer()

        init(from decoder: any Decoder, configuration: Keys) throws {
            let types = configuration.types
            let members = try decoder.container(keyedBy: Name.self)
            for name in members.allKeys {
                guard let key = types[name.stringValue] else { continue }
                try Self.decode(key, from: members.superDecoder(forKey: name), into: &container)
            }
        }

        static func decode<K: MarkdownDecodableAttributedStringKey>(_ key: K.Type, from decoder: any Decoder,
                                                                     into container: inout AttributeContainer) throws {
            container[K.self] = try K.decodeMarkdown(from: decoder)
        }
    }

    /// A scope's attributes by Markdown name, its own and its scopes', read
    /// from its stored properties as Foundation's scope descriptions are;
    /// Foundation's own scope adds those this library declares outside it.
    static func markdownKeys(_ scope: any AttributeScope.Type) -> [String: any MarkdownDecodableAttributedStringKey.Type] {
        var keys: [String: any MarkdownDecodableAttributedStringKey.Type] = [:]
        if scope == AttributeScopes.FoundationAttributes.self {
            let declared: [any MarkdownDecodableAttributedStringKey.Type] = [
                AttributeScopes.FoundationAttributes.MorphologyAttribute.self,
                AttributeScopes.FoundationAttributes.InflectionRuleAttribute.self,
            ]
            for key in declared { keys[key.markdownName] = key }
        }
        _ = _forEachField(of: scope, options: [.ignoreUnknown]) { _, _, type, _ in
            if let key = type as? any MarkdownDecodableAttributedStringKey.Type {
                keys[key.markdownName] = key
            } else if let inner = type as? any AttributeScope.Type {
                keys.merge(markdownKeys(inner)) { current, _ in current }
            }
            return true
        }
        return keys
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension AttributedString {
    public init(markdown: String, options: MarkdownParsingOptions = .init(), baseURL: URL? = nil) throws {
        try self.init(markdown: markdown, including: AttributeScopes.FoundationAttributes.self, options: options, baseURL: baseURL)
    }

    public init<S: AttributeScope>(markdown: String, including scope: KeyPath<AttributeScopes, S.Type>,
                                   options: MarkdownParsingOptions = .init(), baseURL: URL? = nil) throws {
        try self.init(markdown: markdown, including: S.self, options: options, baseURL: baseURL)
    }

    public init<S: AttributeScope>(markdown: String, including scope: S.Type,
                                   options: MarkdownParsingOptions = .init(), baseURL: URL? = nil) throws {
        self = try _MarkdownImport.attributedString({
            try NSAttributedString(__markdownString: markdown, options: $0, baseURL: baseURL)
        }, scope: scope, options: options)
    }

    public init(markdown: Data, options: MarkdownParsingOptions = .init(), baseURL: URL? = nil) throws {
        try self.init(markdown: markdown, including: AttributeScopes.FoundationAttributes.self, options: options, baseURL: baseURL)
    }

    public init<S: AttributeScope>(markdown: Data, including scope: KeyPath<AttributeScopes, S.Type>,
                                   options: MarkdownParsingOptions = .init(), baseURL: URL? = nil) throws {
        try self.init(markdown: markdown, including: S.self, options: options, baseURL: baseURL)
    }

    public init<S: AttributeScope>(markdown: Data, including scope: S.Type,
                                   options: MarkdownParsingOptions = .init(), baseURL: URL? = nil) throws {
        self = try _MarkdownImport.attributedString({
            try NSAttributedString(__markdown: markdown, options: $0, baseURL: baseURL)
        }, scope: scope, options: options)
    }

    public init(contentsOf url: URL, options: MarkdownParsingOptions = .init(), baseURL: URL? = nil) throws {
        try self.init(contentsOf: url, including: AttributeScopes.FoundationAttributes.self, options: options, baseURL: baseURL)
    }

    public init<S: AttributeScope>(contentsOf url: URL, including scope: KeyPath<AttributeScopes, S.Type>,
                                   options: MarkdownParsingOptions = .init(), baseURL: URL? = nil) throws {
        try self.init(contentsOf: url, including: S.self, options: options, baseURL: baseURL)
    }

    public init<S: AttributeScope>(contentsOf url: URL, including scope: S.Type,
                                   options: MarkdownParsingOptions = .init(), baseURL: URL? = nil) throws {
        self = try _MarkdownImport.attributedString({
            try NSAttributedString(__contentsOfMarkdownFileAt: url, options: $0, baseURL: baseURL)
        }, scope: scope, options: options)
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension NSAttributedString {
    public convenience init(contentsOf url: URL, options: AttributedString.MarkdownParsingOptions = .init(),
                            baseURL: URL? = nil) throws {
        try self.init(__contentsOfMarkdownFileAt: url, options: options._bridgeToObjectiveC(), baseURL: baseURL)
    }

    public convenience init(markdown: Data, options: AttributedString.MarkdownParsingOptions = .init(),
                            baseURL: URL? = nil) throws {
        try self.init(__markdown: markdown, options: options._bridgeToObjectiveC(), baseURL: baseURL)
    }

    public convenience init(markdown: String, options: AttributedString.MarkdownParsingOptions = .init(),
                            baseURL: URL? = nil) throws {
        try self.init(__markdownString: markdown, options: options._bridgeToObjectiveC(), baseURL: baseURL)
    }
}
