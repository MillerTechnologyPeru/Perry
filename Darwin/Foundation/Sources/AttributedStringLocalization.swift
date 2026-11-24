// Localized attributed strings: the key is looked up as String(localized:)
// looks it up, and what the table has is read as inline Markdown, as
// Apple's Foundation reads it, keeping its whitespace; text that isn't
// Markdown stays as it is.

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension AttributedString {
    public struct FormattingOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        /// Marks each interpolated value with its replacement index; not
        /// applied here.
        public static let applyReplacementIndexAttribute = FormattingOptions(rawValue: 1 << 0)
    }

    public init(localized key: String.LocalizationValue, options: FormattingOptions = [], table: String? = nil,
                bundle: Bundle? = nil, locale: Locale? = nil, comment: StaticString? = nil) {
        self.init(localizedMarkdown: String(localized: key, table: table, bundle: bundle, locale: locale ?? .current))
    }

    public init(localized key: StaticString, defaultValue: String.LocalizationValue, options: FormattingOptions = [],
                table: String? = nil, bundle: Bundle? = nil, locale: Locale? = nil, comment: StaticString? = nil) {
        self.init(localizedMarkdown: String(localized: key, defaultValue: defaultValue, table: table, bundle: bundle,
                                            locale: locale ?? .current))
    }

    private init(localizedMarkdown text: String) {
        let options = MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        self = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
