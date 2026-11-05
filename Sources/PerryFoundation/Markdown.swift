import CCmarkGFM

// Markdown parsed as Foundation imports it: swift-cmark's tree (Swift's
// cmark-gfm, which Foundation is built on), with GitHub's tables,
// strikethrough and autolinks, walked into runs of text and the attributes
// Foundation gives them. Foundation styles nothing: it records what each
// run is (presentation intents for blocks, inline presentation intents,
// links, images) and leaves styling to whoever draws it, as SwiftUI's Text
// and UIKit's labels do.
//
// The walk is a visitor over the tree, in the manner of Markdownosaur and
// MarkdownToAttributedString, which do the same over swift-markdown for
// styled text. This file is plain Swift over the C library, with no
// Objective-C, so it builds and runs anywhere swift-cmark does; NSAttributed-
// String's Markdown initializers turn its runs into objects.

enum Markdown {
    /// NSAttributedStringMarkdownInterpretedSyntax.
    enum Syntax: Int {
        case full = 0
        case inlineOnly = 1
        case inlineOnlyPreservingWhitespace = 2
    }

    struct Options {
        var syntax: Syntax = .full
        /// ^[text](attributes) gives its text the attributes; otherwise only
        /// the text is kept.
        var extendedAttributes = false
        var sourcePositions = false
    }

    /// NSInlinePresentationIntent.
    enum Inline {
        static let emphasized: UInt = 1 << 0
        static let stronglyEmphasized: UInt = 1 << 1
        static let code: UInt = 1 << 2
        static let strikethrough: UInt = 1 << 5
        static let softBreak: UInt = 1 << 6
        static let lineBreak: UInt = 1 << 7
        static let inlineHTML: UInt = 1 << 8
        static let blockHTML: UInt = 1 << 9
    }

    /// A block's presentation intent, NSPresentationIntentKind's cases.
    enum Kind: Equatable {
        case paragraph
        case header(level: Int)
        case orderedList
        case unorderedList
        case listItem(ordinal: Int)
        case codeBlock(languageHint: String?)
        case blockQuote
        case thematicBreak
        /// Each column's alignment: 0 left (or none given), 1 center, 2 right.
        case table(alignments: [Int])
        case tableHeaderRow
        case tableRow(row: Int)
        case tableCell(column: Int)

        var rawValue: Int {
            switch self {
            case .paragraph: 0
            case .header: 1
            case .orderedList: 2
            case .unorderedList: 3
            case .listItem: 4
            case .codeBlock: 5
            case .blockQuote: 6
            case .thematicBreak: 7
            case .table: 8
            case .tableHeaderRow: 9
            case .tableRow: 10
            case .tableCell: 11
            }
        }
    }

    /// A block and the blocks it is nested in. Identities count the
    /// document's blocks from 1 in the order they open.
    final class Block {
        let kind: Kind
        let identity: Int
        let parent: Block?

        init(_ kind: Kind, identity: Int, parent: Block?) {
            self.kind = kind
            self.identity = identity
            self.parent = parent
        }

        var indentationLevel: Int { Markdown.indentationLevel(of: kind, inside: parent?.indentationLevel) }
    }

    /// NSPresentationIntent's indentationLevel, as Foundation gives it to
    /// each intent: list items and block quotes are one deeper than the
    /// intent they are in (0 at the top); headers, code blocks and lists are
    /// as deep as theirs; paragraphs, thematic breaks and tables' parts are
    /// 0.
    static func indentationLevel(of kind: Kind, inside parent: Int?) -> Int {
        switch kind {
        case .listItem, .blockQuote: parent.map { $0 + 1 } ?? 0
        case .header, .codeBlock, .orderedList, .unorderedList: parent ?? 0
        case .paragraph, .thematicBreak, .table, .tableHeaderRow, .tableRow, .tableCell: 0
        }
    }

    /// NSAttributedStringMarkdownSourcePosition's values: 1-based lines,
    /// and 1-based UTF-8 columns with the end inclusive.
    struct Position: Equatable {
        var startLine, startColumn, endLine, endColumn: Int
    }

    struct Attributes: Equatable {
        var inline: UInt = 0
        var link: String?
        var imageURL: String?
        /// A link's or image's title.
        var alternateDescription: String?
        /// The innermost list item's marker: "-", "+", "*", "." or ")".
        var listItemDelimiter: String?
        var block: Block?
        var position: Position?
        /// The ^[…](…) attribute sources around the text, outermost first,
        /// as written between the parentheses.
        var extended: [String] = []

        static func == (a: Attributes, b: Attributes) -> Bool {
            a.inline == b.inline && a.link == b.link && a.imageURL == b.imageURL
                && a.alternateDescription == b.alternateDescription && a.listItemDelimiter == b.listItemDelimiter
                && a.block === b.block && a.position == b.position && a.extended == b.extended
        }
    }

    struct Run {
        var text: String
        var attributes: Attributes
    }

    /// GitHub's extensions, registered once for every parser.
    nonisolated(unsafe) private static let extensions: [UnsafeMutablePointer<cmark_syntax_extension>] = {
        cmark_gfm_core_extensions_ensure_registered()
        let names: [String] = ["table", "strikethrough", "autolink"]
        return names.compactMap { cmark_find_syntax_extension($0) }
    }()

    static func parse(_ source: String, _ options: Options) -> [Run] {
        // CMARK_OPT_PRESERVE_WHITESPACE, which includes CMARK_OPT_INLINE_ONLY,
        // for both inline syntaxes: Foundation keeps the source's spaces and
        // line breaks as text in either.
        let flags: Int32 = options.syntax == .full ? 0 : 1 << 19 | 1 << 18
        guard let parser = cmark_parser_new(flags) else { return [] }
        defer { cmark_parser_free(parser) }
        for syntax in extensions { cmark_parser_attach_syntax_extension(parser, syntax) }
        var text = source
        text.withUTF8 { bytes in
            bytes.withMemoryRebound(to: CChar.self) { cmark_parser_feed(parser, $0.baseAddress, $0.count) }
        }
        guard let document = cmark_parser_finish(parser) else { return [] }
        defer { cmark_node_free(document) }
        var walker = Walker(options: options)
        walker.children(of: document, Attributes())
        return walker.runs
    }

    /// The visitor: blocks open intents, inlines add to the attributes their
    /// text is appended with.
    private struct Walker {
        let options: Options
        var runs: [Run] = []
        var identity = 0

        init(options: Options) { self.options = options }

        mutating func append(_ text: String, _ attributes: Attributes, _ node: UnsafeMutablePointer<cmark_node>) {
            append(text, attributes, at: position(of: node))
        }

        mutating func append(_ text: String, _ attributes: Attributes, at position: Position?) {
            guard !text.isEmpty else { return }
            var attributes = attributes
            if options.sourcePositions { attributes.position = position }
            if let last = runs.last, last.attributes == attributes {
                runs[runs.count - 1].text += text
            } else {
                runs.append(Run(text: text, attributes: attributes))
            }
        }

        /// Where cmark found a node; nothing for the nodes it gives no place,
        /// such as line breaks.
        func position(of node: UnsafeMutablePointer<cmark_node>) -> Position? {
            let position = Position(startLine: Int(cmark_node_get_start_line(node)),
                                    startColumn: Int(cmark_node_get_start_column(node)),
                                    endLine: Int(cmark_node_get_end_line(node)),
                                    endColumn: Int(cmark_node_get_end_column(node)))
            return position.startLine > 0 ? position : nil
        }

        /// A link's or image's description as Foundation keeps it: its
        /// text without the inline syntax inside it, from where its first
        /// child starts to where its last ends.
        func flattened(_ node: UnsafeMutablePointer<cmark_node>) -> (text: String, position: Position?) {
            var text = ""
            var first: Position?, last: Position?
            var child = cmark_node_first_child(node)
            while let current = child {
                if let place = position(of: current) {
                    if first == nil { first = place }
                    last = place
                }
                child = cmark_node_next(current)
            }
            func walk(_ node: UnsafeMutablePointer<cmark_node>) {
                var child = cmark_node_first_child(node)
                while let current = child {
                    switch cmark_node_get_type(current) {
                    case CMARK_NODE_TEXT, CMARK_NODE_CODE, CMARK_NODE_HTML_INLINE:
                        text += literal(current)
                    case CMARK_NODE_SOFTBREAK: text += " "
                    case CMARK_NODE_LINEBREAK: text += "\n"
                    default: walk(current)
                    }
                    child = cmark_node_next(current)
                }
            }
            walk(node)
            guard let first, let last else { return (text, nil) }
            return (text, Position(startLine: first.startLine, startColumn: first.startColumn,
                                   endLine: last.endLine, endColumn: last.endColumn))
        }

        /// A new block inside the current one; none when only inline syntax
        /// is interpreted.
        mutating func open(_ kind: Kind, _ attributes: Attributes) -> Attributes {
            guard options.syntax == .full else { return attributes }
            identity += 1
            var inner = attributes
            inner.block = Block(kind, identity: identity, parent: attributes.block)
            return inner
        }

        mutating func children(of node: UnsafeMutablePointer<cmark_node>, _ attributes: Attributes) {
            var child = cmark_node_first_child(node)
            while let current = child {
                visit(current, attributes)
                child = cmark_node_next(current)
            }
        }

        mutating func visit(_ node: UnsafeMutablePointer<cmark_node>, _ attributes: Attributes) {
            let type = cmark_node_get_type(node)
            var attributes = attributes
            switch type {
            case CMARK_NODE_PARAGRAPH:
                children(of: node, open(.paragraph, attributes))
            case CMARK_NODE_HEADING:
                children(of: node, open(.header(level: Int(cmark_node_get_heading_level(node))), attributes))
            case CMARK_NODE_BLOCK_QUOTE:
                children(of: node, open(.blockQuote, attributes))
            case CMARK_NODE_LIST:
                list(node, attributes)
            case CMARK_NODE_CODE_BLOCK:
                let info = string(cmark_node_get_fence_info(node)) ?? ""
                append(literal(node), open(.codeBlock(languageHint: info.isEmpty ? nil : info), attributes), node)
            case CMARK_NODE_HTML_BLOCK:
                attributes.inline |= Inline.blockHTML
                append(literal(node), attributes, node)
            case CMARK_NODE_THEMATIC_BREAK:
                // Foundation gives the break no source position.
                append("\u{2E3B}", open(.thematicBreak, attributes), at: nil)
            case CMARK_NODE_TEXT:
                append(literal(node), attributes, node)
            case CMARK_NODE_SOFTBREAK:
                attributes.inline |= Inline.softBreak
                append(" ", attributes, node)
            case CMARK_NODE_LINEBREAK:
                attributes.inline |= Inline.lineBreak
                append("\n", attributes, node)
            case CMARK_NODE_CODE:
                attributes.inline |= Inline.code
                append(literal(node), attributes, node)
            case CMARK_NODE_HTML_INLINE:
                attributes.inline |= Inline.inlineHTML
                append(literal(node), attributes, node)
            case CMARK_NODE_EMPH:
                attributes.inline |= Inline.emphasized
                children(of: node, attributes)
            case CMARK_NODE_STRONG:
                attributes.inline |= Inline.stronglyEmphasized
                children(of: node, attributes)
            case CMARK_NODE_LINK:
                attributes.link = string(cmark_node_get_url(node))
                if let title = string(cmark_node_get_title(node)), !title.isEmpty { attributes.alternateDescription = title }
                let description = flattened(node)
                append(description.text, attributes, at: description.position)
            case CMARK_NODE_IMAGE:
                attributes.imageURL = string(cmark_node_get_url(node))
                if let title = string(cmark_node_get_title(node)), !title.isEmpty { attributes.alternateDescription = title }
                // An image without a description stands as U+FFFC, the
                // object replacement character.
                let description = flattened(node)
                if description.text.isEmpty {
                    append("\u{FFFC}", attributes, at: nil)
                } else {
                    append(description.text, attributes, at: description.position)
                }
            case CMARK_NODE_ATTRIBUTE:
                if options.extendedAttributes, let source = string(cmark_node_get_attributes(node)) {
                    attributes.extended.append(source)
                }
                children(of: node, attributes)
            default:
                switch string(cmark_node_get_type_string(node)) {
                case "strikethrough":
                    attributes.inline |= Inline.strikethrough
                    children(of: node, attributes)
                case "table":
                    table(node, attributes)
                default:
                    children(of: node, attributes)
                }
            }
        }

        /// A list and its items, each with its ordinal (counted from the
        /// list's start when ordered) and its marker.
        mutating func list(_ node: UnsafeMutablePointer<cmark_node>, _ attributes: Attributes) {
            let ordered = cmark_node_get_list_type(node) == CMARK_ORDERED_LIST
            let list = open(ordered ? .orderedList : .unorderedList, attributes)
            var delimiter: String?
            if ordered {
                delimiter = cmark_node_get_list_delim(node) == CMARK_PAREN_DELIM ? ")" : "."
            } else {
                switch cmark_node_get_list_marker(node) {
                case CMARK_HYPHEN_LIST_MARKER: delimiter = "-"
                case CMARK_PLUS_LIST_MARKER: delimiter = "+"
                case CMARK_ASTERISK_LIST_MARKER: delimiter = "*"
                default: delimiter = nil
                }
            }
            let start = ordered ? Int(cmark_node_get_list_start(node)) : 1
            var ordinal = start
            var item = cmark_node_first_child(node)
            while let current = item {
                var inner = open(.listItem(ordinal: ordinal), list)
                if options.syntax == .full { inner.listItemDelimiter = delimiter }
                children(of: current, inner)
                ordinal += 1
                item = cmark_node_next(current)
            }
        }

        /// A table, its header row, its rows counted from 1, and its cells
        /// by column.
        mutating func table(_ node: UnsafeMutablePointer<cmark_node>, _ attributes: Attributes) {
            let columns = Int(cmark_gfm_extensions_get_table_columns(node))
            let raw = cmark_gfm_extensions_get_table_alignments(node)
            let alignments = (0..<columns).map { column -> Int in
                switch raw.map({ $0[column] }) ?? 0 {
                case UInt8(ascii: "c"): 1
                case UInt8(ascii: "r"): 2
                default: 0
                }
            }
            let table = open(.table(alignments: alignments), attributes)
            var row = 0
            var child = cmark_node_first_child(node)
            while let current = child {
                let header = cmark_gfm_extensions_get_table_row_is_header(current) != 0
                let inner = open(header ? .tableHeaderRow : .tableRow(row: row), table)
                var column = 0
                var cell = cmark_node_first_child(current)
                while let currentCell = cell {
                    children(of: currentCell, open(.tableCell(column: column), inner))
                    column += 1
                    cell = cmark_node_next(currentCell)
                }
                row += 1
                child = cmark_node_next(current)
            }
        }

        func literal(_ node: UnsafeMutablePointer<cmark_node>) -> String {
            string(cmark_node_get_literal(node)) ?? ""
        }

        func string(_ pointer: UnsafePointer<CChar>?) -> String? {
            pointer.map { String(cString: $0) }
        }
    }
}
