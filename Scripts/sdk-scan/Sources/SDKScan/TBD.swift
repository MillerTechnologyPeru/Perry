// Reads the SDK's text stubs (`.tbd`, TAPI's YAML), versions 2 to 4: each
// document's install name, the libraries it re-exports and the names it
// exports per target. Every .tbd in the macOS and iOS 27 SDKs is version 4;
// versions 2 and 3 (`archs:` and `platform:` instead of `targets:`) are for
// the older SDKs the 32-bit loaders use.
//
// Only the YAML that TAPI writes is understood: block mappings, block
// sequences of mappings, flow sequences of scalars (over several lines),
// and plain or quoted scalars.

public enum TBDError: Error, CustomStringConvertible {
    case noDocument
    case unsupportedVersion(String)
    case malformed(line: Int, String)

    public var description: String {
        switch self {
        case .noDocument: "no TAPI document"
        case .unsupportedVersion(let version): "unsupported .tbd version \(version)"
        case .malformed(let line, let text): "line \(line): can't read \(text)"
        }
    }
}

public enum TBD {
    /// Every document of a `.tbd`, in file order: the library the file is
    /// for first, then those inlined after it.
    public static func parse(_ text: String) throws -> [Library] {
        let documents = try YAML.documents(text)
        guard !documents.isEmpty else { throw TBDError.noDocument }
        return try documents.map(library)
    }

    /// The file's own library and, following its re-exports through the
    /// documents inlined in the same file, the ones it passes on.
    public static func reexportClosure(_ libraries: [Library]) -> [Library] {
        guard let first = libraries.first else { return [] }
        let byName = Dictionary(libraries.map { ($0.installName, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [Library] = []
        var seen: Set<String> = []
        var queue = [first]
        while !queue.isEmpty {
            let library = queue.removeFirst()
            guard seen.insert(library.installName).inserted else { continue }
            result.append(library)
            queue += library.reexportedLibraries.compactMap { byName[$0] }
        }
        return result
    }

    static func library(_ document: YAML.Node) throws -> Library {
        guard case .mapping(let entries) = document else { throw TBDError.noDocument }
        let fields = Dictionary(entries, uniquingKeysWith: { first, _ in first })
        let version = fields["tbd-version"]?.scalar ?? "2"
        guard ["1", "2", "3", "4"].contains(version) else { throw TBDError.unsupportedVersion(version) }
        // Versions 2 and 3 name architectures and one platform instead of
        // targets; they become targets the same shape as version 4's.
        let platform = fields["platform"]?.scalar
        func targets(_ section: [String: YAML.Node]) -> [String] {
            if let targets = section["targets"]?.list { return targets }
            let archs = section["archs"]?.list ?? []
            return archs.map { arch in platform.map { "\(arch)-\($0)" } ?? arch }
        }

        var library = Library(installName: fields["install-name"]?.scalar ?? "",
                              currentVersion: fields["current-version"]?.scalar)
        // Version 4's re-exported libraries are their own key; earlier
        // versions list them in each export section as `re-exports`.
        for entry in fields["reexported-libraries"]?.sequence ?? [] {
            library.reexportedLibraries += entry.fields["libraries"]?.list ?? []
        }
        var directives: Set<String> = []
        // `reexports` (version 4) are names of other libraries' this one
        // exports as its own: as reachable through it as its own exports.
        for key in ["exports", "reexports"] {
            for entry in fields[key]?.sequence ?? [] {
                let section = entry.fields
                library.reexportedLibraries += section["re-exports"]?.list ?? []
                var exports = ExportSection(targets: targets(section))
                for symbol in section["symbols"]?.list ?? [] {
                    if symbol.hasPrefix("$ld$") {
                        directives.insert(symbol)
                    } else if symbol.hasPrefix("_$s") {
                        exports.swiftSymbols.append(symbol)
                    } else {
                        exports.symbols.append(symbol)
                    }
                }
                exports.objcClasses = section["objc-classes"]?.list ?? []
                exports.objcEHTypes = section["objc-eh-types"]?.list ?? []
                exports.objcIvars = section["objc-ivars"]?.list ?? []
                exports.weakSymbols = section["weak-symbols"]?.list ?? section["weak-def-symbols"]?.list ?? []
                exports.threadLocalSymbols = section["thread-local-symbols"]?.list ?? []
                if !exports.isEmpty { library.exports.append(exports) }
            }
        }
        var seen: Set<String> = []
        library.reexportedLibraries = library.reexportedLibraries.filter { seen.insert($0).inserted }
        library.directives = directives.sorted()
        return library
    }
}

// MARK: - YAML

/// The subset of YAML TAPI writes.
enum YAML {
    indirect enum Node: Equatable {
        case scalar(String)
        case sequence([Node])
        case mapping([(String, Node)])

        static func == (lhs: Node, rhs: Node) -> Bool {
            switch (lhs, rhs) {
            case (.scalar(let a), .scalar(let b)): a == b
            case (.sequence(let a), .sequence(let b)): a == b
            case (.mapping(let a), .mapping(let b)): a.count == b.count && zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
            default: false
            }
        }

        var scalar: String? {
            if case .scalar(let value) = self { return value }
            return nil
        }

        var sequence: [Node]? {
            if case .sequence(let items) = self { return items }
            return nil
        }

        /// A sequence's scalars; a lone scalar as a list of one.
        var list: [String]? {
            switch self {
            case .scalar(let value): [value]
            case .sequence(let items): items.compactMap(\.scalar)
            case .mapping: nil
            }
        }

        var fields: [String: Node] {
            if case .mapping(let entries) = self { return Dictionary(entries, uniquingKeysWith: { first, _ in first }) }
            return [:]
        }
    }

    struct Line {
        let number: Int
        let indent: Int
        var text: Substring
    }

    /// Each `---` document's top-level mapping.
    static func documents(_ text: String) throws -> [Node] {
        var documents: [[Line]] = []
        var current: [Line]?
        var pending: (number: Int, text: String, depth: Int)?
        for (index, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = raw.hasSuffix("\r") ? raw.dropLast() : raw
            if var open = pending {
                // A flow sequence continued from an earlier line.
                open.text += " " + line.trimmingSpaces
                open.depth += flowDepthChange(line)
                if open.depth <= 0 {
                    current?.append(makeLine(number: open.number, open.text))
                    pending = nil
                } else {
                    pending = open
                }
                continue
            }
            if line.hasPrefix("---") {
                if let finished = current { documents.append(finished) }
                current = []
                continue
            }
            if line == "..." {
                if let finished = current { documents.append(finished) }
                current = nil
                continue
            }
            let trimmed = line.trimmingSpaces
            guard current != nil, !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let depth = flowDepthChange(line)
            if depth > 0 {
                pending = (index + 1, String(line), depth)
            } else {
                current?.append(makeLine(number: index + 1, String(line)))
            }
        }
        if let finished = current { documents.append(finished) }
        return try documents.filter { !$0.isEmpty }.map { lines in
            var position = 0
            return try mapping(lines, &position, indent: lines[0].indent)
        }
    }

    static func makeLine(number: Int, _ text: String) -> Line {
        let indent = text.prefix(while: { $0 == " " }).count
        return Line(number: number, indent: indent, text: Substring(text.dropFirst(indent)))
    }

    /// How many more `[` than `]` a line opens, outside quotes.
    static func flowDepthChange(_ line: Substring) -> Int {
        var depth = 0
        var quote: Character?
        for character in line {
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "'" || character == "\"" {
                quote = character
            } else if character == "[" {
                depth += 1
            } else if character == "]" {
                depth -= 1
            }
        }
        return depth
    }

    static func mapping(_ lines: [Line], _ position: inout Int, indent: Int) throws -> Node {
        var entries: [(String, Node)] = []
        while position < lines.count, lines[position].indent == indent, !lines[position].text.hasPrefix("- ") {
            let line = lines[position]
            guard let colon = keyColon(line.text) else { throw TBDError.malformed(line: line.number, String(line.text)) }
            let key = unquote(line.text[..<colon].trimmingSpaces)
            let rest = line.text[line.text.index(after: colon)...].trimmingSpaces
            position += 1
            if !rest.isEmpty {
                entries.append((key, scalarOrFlow(rest)))
            } else if position < lines.count, lines[position].text.hasPrefix("- "), lines[position].indent >= indent {
                entries.append((key, try sequence(lines, &position, indent: lines[position].indent)))
            } else if position < lines.count, lines[position].indent > indent {
                entries.append((key, try mapping(lines, &position, indent: lines[position].indent)))
            } else {
                entries.append((key, .scalar("")))
            }
        }
        return .mapping(entries)
    }

    static func sequence(_ lines: [Line], _ position: inout Int, indent: Int) throws -> Node {
        var lines = lines
        var items: [Node] = []
        while position < lines.count, lines[position].indent == indent, lines[position].text.hasPrefix("- ") {
            let line = lines[position]
            let item = line.text.dropFirst(2)
            if keyColon(item) != nil {
                // A mapping whose first key is on the dash's line: read it
                // as though the key were indented under the dash.
                lines[position] = Line(number: line.number, indent: indent + 2, text: item)
                items.append(try mapping(lines, &position, indent: indent + 2))
            } else {
                items.append(scalarOrFlow(item.trimmingSpaces))
                position += 1
            }
        }
        return .sequence(items)
    }

    /// The colon ending a mapping key, outside quotes and followed by a
    /// space or the end of the line.
    static func keyColon(_ text: Substring) -> Substring.Index? {
        var quote: Character?
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "'" || character == "\"" {
                quote = character
            } else if character == "[" || character == "{" {
                return nil
            } else if character == ":" {
                let next = text.index(after: index)
                if next == text.endIndex || text[next] == " " { return index }
            }
            index = text.index(after: index)
        }
        return nil
    }

    static func scalarOrFlow(_ text: Substring) -> Node {
        guard text.hasPrefix("["), text.hasSuffix("]") else { return .scalar(unquote(text)) }
        var items: [Node] = []
        var item = ""
        var quote: Character?
        for character in text.dropFirst().dropLast() {
            if let open = quote {
                item.append(character)
                if character == open { quote = nil }
            } else if character == "'" || character == "\"" {
                quote = character
                item.append(character)
            } else if character == "," {
                let trimmed = Substring(item).trimmingSpaces
                if !trimmed.isEmpty { items.append(.scalar(unquote(trimmed))) }
                item = ""
            } else {
                item.append(character)
            }
        }
        let trimmed = Substring(item).trimmingSpaces
        if !trimmed.isEmpty { items.append(.scalar(unquote(trimmed))) }
        return .sequence(items)
    }

    /// A scalar without its quotes: `'…'` with `''` for a quote, `"…"`
    /// with backslash escapes of quotes and backslashes.
    static func unquote(_ text: Substring) -> String {
        if text.count >= 2, text.hasPrefix("'"), text.hasSuffix("'") {
            return String(text.dropFirst().dropLast()).replacing("''", with: "'")
        }
        if text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") {
            var result = ""
            var escaped = false
            for character in text.dropFirst().dropLast() {
                if escaped {
                    result.append(character)
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else {
                    result.append(character)
                }
            }
            return result
        }
        return String(text)
    }
}

extension Substring {
    var trimmingSpaces: Substring {
        let start = firstIndex(where: { $0 != " " && $0 != "\t" }) ?? endIndex
        let end = lastIndex(where: { $0 != " " && $0 != "\t" }).map { index(after: $0) } ?? start
        return start < end ? self[start..<end] : self[start..<start]
    }
}
