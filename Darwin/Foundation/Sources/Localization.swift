import CoreFoundation

// Localized strings: a String.LocalizationValue is a key, written as a
// format string with a specifier where each value is interpolated ("Count:
// %lld"), and the values. Resolving one looks the key up in a bundle's
// strings tables and formats the values into what it finds.

// MARK: Format specifiers

/// A value that a localized string interpolates with a printf specifier.
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
@preconcurrency public protocol _FormatSpecifiable: Equatable, Sendable {
    associatedtype _Arg: CVarArg, Sendable
    var _arg: _Arg { get }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension Int: _FormatSpecifiable { public var _arg: Int64 { Int64(self) } }
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension Int8: _FormatSpecifiable { public var _arg: Int32 { Int32(self) } }
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension Int16: _FormatSpecifiable { public var _arg: Int32 { Int32(self) } }
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension Int32: _FormatSpecifiable { public var _arg: Int32 { self } }
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension Int64: _FormatSpecifiable { public var _arg: Int64 { self } }
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension UInt: _FormatSpecifiable { public var _arg: UInt64 { UInt64(self) } }
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension UInt8: _FormatSpecifiable { public var _arg: UInt32 { UInt32(self) } }
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension UInt16: _FormatSpecifiable { public var _arg: UInt32 { UInt32(self) } }
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension UInt32: _FormatSpecifiable { public var _arg: UInt32 { self } }
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension UInt64: _FormatSpecifiable { public var _arg: UInt64 { self } }
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension Float: _FormatSpecifiable { public var _arg: Double { Double(self) } }
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension Double: _FormatSpecifiable { public var _arg: Double { self } }
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension CGFloat: _FormatSpecifiable { public var _arg: CGFloat { self } }

/// An Objective-C object is a variadic argument by its pointer, for "%@";
/// whoever passes it keeps it alive until the call returns.
@available(macOS 10.10, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension NSObject: CVarArg {
    public var _cVarArgEncoding: [Int] {
        [Int(bitPattern: Unmanaged.passUnretained(self).toOpaque())]
    }
}

// MARK: String.LocalizationValue

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
extension String {
    public struct LocalizationOptions {
        public var replacements: [any CVarArg]?
        public init() {}
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension String {
    public struct LocalizationValue: Equatable, ExpressibleByStringInterpolation, @unchecked Sendable {
        @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
        public enum Placeholder: Codable, Hashable, Sendable {
            case int
            case uint
            case float
            case double
            case object
        }

        /// A value interpolated into a localized string.
        enum Argument: Equatable {
            case int(Int64)
            case uint(UInt64)
            case double(Double)
            case object(NSObject)
            case string(String)
            case attributed(AttributedString)
            /// A value to be given when the string is formatted.
            case placeholder(Placeholder)

            var cVarArg: any CVarArg {
                switch self {
                case .int(let value): value
                case .uint(let value): value
                case .double(let value): value
                case .object(let object): object
                case .string(let string): string._bridgeToObjectiveC()
                case .attributed(let string): String(string.characters)._bridgeToObjectiveC()
                case .placeholder: "" as NSString
                }
            }
        }

        /// The key: the string, with a format specifier for each argument.
        var key: String
        var arguments: [Argument]

        public init(_ value: String) {
            key = value
            arguments = []
        }

        public init(stringLiteral value: String) {
            self.init(value)
        }

        public init(stringInterpolation: StringInterpolation) {
            key = stringInterpolation.key
            arguments = stringInterpolation.arguments
        }

        public static func == (a: LocalizationValue, b: LocalizationValue) -> Bool {
            a.key == b.key && a.arguments == b.arguments
        }

        public struct StringInterpolation: StringInterpolationProtocol {
            public typealias StringLiteralType = String

            var key = ""
            var arguments: [Argument] = []

            public init(literalCapacity: Int, interpolationCount: Int) {
                key.reserveCapacity(literalCapacity + 4 * interpolationCount)
                arguments.reserveCapacity(interpolationCount)
            }

            /// Literal text: a percent sign in it is not a specifier.
            public mutating func appendLiteral(_ literal: String) {
                key += (literal._bridgeToObjectiveC()).replacingOccurrences(of: "%", with: "%%")
            }

            mutating func append(_ argument: Argument, specifier: String) {
                key += specifier
                arguments.append(argument)
            }

            public mutating func appendInterpolation(_ string: String) {
                append(.string(string), specifier: "%@")
            }

            public mutating func appendInterpolation<Subject: NSObject>(_ subject: Subject) {
                append(.object(subject), specifier: "%@")
            }

            public mutating func appendInterpolation<T: _FormatSpecifiable>(_ value: T, specifier: String) {
                let argument: Argument = switch value._arg {
                case let value as Int64: .int(value)
                case let value as Int32: .int(Int64(value))
                case let value as UInt64: .uint(value)
                case let value as UInt32: .uint(UInt64(value))
                case let value as Double: .double(value)
                case let value as CGFloat: .double(Double(value))
                default: .string(String(describing: value))
                }
                append(argument, specifier: specifier)
            }

            @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
            public mutating func appendInterpolation(placeholder: Placeholder, specifier: String) {
                append(.placeholder(placeholder), specifier: specifier)
            }

            @preconcurrency
            public mutating func appendInterpolation<T, F>(_ value: T, format: F)
                where T: Sendable, T == F.FormatInput, F: FormatStyle, F: Sendable, F.FormatOutput: StringProtocol {
                append(.string(String(format.format(value))), specifier: "%@")
            }

            @preconcurrency
            public mutating func appendInterpolation<T, F>(_ value: T, format: F)
                where T: Sendable, T == F.FormatInput, F: FormatStyle, F: Sendable, F.FormatOutput: AttributedStringProtocol {
                append(.attributed(AttributedString(format.format(value))), specifier: "%@")
            }

            public mutating func appendInterpolation(_ attrStr: AttributedString, options: AttributedString.InterpolationOptions = []) {
                append(.attributed(attrStr), specifier: "%@")
            }

            @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
            public mutating func appendInterpolation<T: CustomLocalizedStringResourceConvertible>(_ value: T) {
                append(.string(String(localized: value.localizedStringResource)), specifier: "%@")
            }

            @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
            public mutating func appendInterpolation<C>(_ value: C, format: ListFormatStyle<StringStyle, [String]>)
                where C: Collection, C.Element: CustomLocalizedStringResourceConvertible {
                let strings = value.map { String(localized: $0.localizedStringResource) }
                append(.string(format.format(strings)), specifier: "%@")
            }
        }

        /// The key looked up in the bundle's table, with the arguments
        /// formatted into it, or the replacements given for placeholders.
        func resolved(table: String?, bundle: Bundle?, locale: Locale, replacements: [any CVarArg]? = nil) -> String {
            let format = (bundle ?? .main).localizedString(forKey: key, value: key, table: table)
            guard !arguments.isEmpty else { return format }
            var values = arguments.map(\.cVarArg)
            if let replacements {
                var next = replacements.makeIterator()
                for (index, argument) in arguments.enumerated() {
                    if case .placeholder = argument, let replacement = next.next() { values[index] = replacement }
                }
            }
            return withExtendedLifetime(values) {
                withVaList(values) { NSString(format: format, locale: locale, arguments: $0) as String }
            }
        }
    }

    public init(localized keyAndValue: LocalizationValue, table: String? = nil, bundle: Bundle? = nil,
                locale: Locale = .current, comment: StaticString? = nil) {
        self = keyAndValue.resolved(table: table, bundle: bundle, locale: locale)
    }

    public init(localized key: StaticString, defaultValue: LocalizationValue, table: String? = nil, bundle: Bundle? = nil,
                locale: Locale = .current, comment: StaticString? = nil) {
        self = LocalizedStringResource(key, defaultValue: defaultValue, table: table, locale: locale)
            .resolved(bundle: bundle)
    }

    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
    public init(localized keyAndValue: LocalizationValue, options: LocalizationOptions, table: String? = nil,
                bundle: Bundle? = nil, locale: Locale = .current, comment: StaticString? = nil) {
        self = keyAndValue.resolved(table: table, bundle: bundle, locale: locale, replacements: options.replacements)
    }

    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
    public init(localized key: StaticString, defaultValue: LocalizationValue, options: LocalizationOptions,
                table: String? = nil, bundle: Bundle? = nil, locale: Locale = .current, comment: StaticString? = nil) {
        self = LocalizedStringResource(key, defaultValue: defaultValue, table: table, locale: locale)
            .resolved(bundle: bundle, replacements: options.replacements)
    }
}

// MARK: LocalizedStringResource

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
public protocol CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource { get }
}

/// A localized string to look up later: its key, the value to use when no
/// table has the key, and where to look.
@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
public struct LocalizedStringResource: Equatable, Codable, CustomLocalizedStringResourceConvertible,
    ExpressibleByStringInterpolation, @unchecked Sendable {
    public typealias StringInterpolation = String.LocalizationValue.StringInterpolation

    public let key: String
    public let defaultValue: String.LocalizationValue
    public let table: String?
    public var locale: Locale
    public var bundle: BundleDescription { _bundle }
    private var _bundle: BundleDescription

    public enum BundleDescription: @unchecked Sendable {
        case main
        case forClass(AnyClass)
        case atURL(URL)

        var bundle: Bundle {
            switch self {
            case .main: .main
            case .forClass(let type): Bundle(for: type)
            case .atURL(let url): Bundle(url: url) ?? .main
            }
        }
    }

    public init(_ keyAndValue: String.LocalizationValue, table: String? = nil, locale: Locale = .current,
                bundle: BundleDescription = .main, comment: StaticString? = nil) {
        key = keyAndValue.key
        defaultValue = keyAndValue
        self.table = table
        self.locale = locale
        _bundle = bundle
    }

    public init(_ key: StaticString, defaultValue: String.LocalizationValue, table: String? = nil,
                locale: Locale = .current, bundle: BundleDescription = .main, comment: StaticString? = nil) {
        self.key = key.description
        self.defaultValue = defaultValue
        self.table = table
        self.locale = locale
        _bundle = bundle
    }

    public init(stringLiteral value: String) {
        self.init(String.LocalizationValue(value))
    }

    public init(stringInterpolation: String.LocalizationValue.StringInterpolation) {
        self.init(String.LocalizationValue(stringInterpolation: stringInterpolation))
    }

    public var localizedStringResource: LocalizedStringResource { self }

    /// The key looked up in the table, else the default value, formatted.
    func resolved(bundle override: Bundle? = nil, replacements: [any CVarArg]? = nil) -> String {
        var value = defaultValue
        let found = (override ?? bundle.bundle).localizedString(forKey: key, value: "\u{1}", table: table)
        value.key = found == "\u{1}" ? defaultValue.key : found
        return value.resolved(table: nil, bundle: Bundle(for: _LocalizationNoTable.self), locale: locale,
                              replacements: replacements)
    }

    public static func == (lhs: LocalizedStringResource, rhs: LocalizedStringResource) -> Bool {
        lhs.key == rhs.key && lhs.defaultValue == rhs.defaultValue && lhs.table == rhs.table && lhs.locale == rhs.locale
    }

    private enum CodingKeys: String, CodingKey { case key, defaultValue, table, locale }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(resolved(), forKey: .defaultValue)
        try container.encodeIfPresent(table, forKey: .table)
        try container.encode(locale, forKey: .locale)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        defaultValue = String.LocalizationValue(try container.decode(String.self, forKey: .defaultValue))
        table = try container.decodeIfPresent(String.self, forKey: .table)
        locale = try container.decode(Locale.self, forKey: .locale)
        _bundle = .main
    }
}

/// A class in no bundle's tables: a value already looked up is formatted
/// through a bundle that leaves keys as they are.
private final class _LocalizationNoTable {}

@available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
extension String {
    @_disfavoredOverload
    public init(localized resource: LocalizedStringResource) {
        self = resource.resolved()
    }

    @_disfavoredOverload
    public init(localized resource: LocalizedStringResource, options: LocalizationOptions) {
        self = resource.resolved(replacements: options.replacements)
    }
}

// MARK: AttributedString

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension AttributedString {
    public struct InterpolationOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let insertAttributesWithoutMerging = InterpolationOptions(rawValue: 1 << 0)
    }

    /// The localized string's inline Markdown, as strings tables are read:
    /// whitespace kept, and what cannot be parsed left as text.
    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
    public init(localized resource: LocalizedStringResource) {
        self.init(localizedMarkdown: String(localized: resource), including: AttributeScopes.FoundationAttributes.self)
    }

    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
    public init<S: AttributeScope>(localized resource: LocalizedStringResource, including scope: KeyPath<AttributeScopes, S.Type>) {
        self.init(localizedMarkdown: String(localized: resource), including: S.self)
    }

    init(localizedMarkdown string: String, including scope: any AttributeScope.Type) {
        let options = MarkdownParsingOptions(allowsExtendedAttributes: true, interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                             failurePolicy: .returnPartiallyParsedIfPossible)
        let parsed = try? _MarkdownImport.attributedString({
            try NSAttributedString(__markdownString: string, options: $0, baseURL: nil)
        }, scope: scope, options: options)
        self = parsed ?? AttributedString(string)
    }
}
