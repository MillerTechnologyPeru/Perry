// Reads the symbol graphs that `clang -extract-api` writes for headers and
// `swift-symbolgraph-extract` for a Swift module, into the manifest's
// declarations. Only the parts the manifest keeps are decoded.

import Foundation

struct SymbolGraph: Decodable {
    struct Symbol: Decodable {
        struct Kind: Decodable { let identifier: String }
        struct Identifier: Decodable { let precise: String }
        struct Fragment: Decodable {
            let kind: String
            let spelling: String
        }
        struct Location: Decodable {
            struct Position: Decodable { let line: Int }
            let uri: String
            let position: Position?
        }
        struct Version: Decodable {
            let major: Int
            let minor: Int?
            let patch: Int?

            var text: String {
                var parts = [major, minor ?? 0]
                if let patch, patch != 0 { parts.append(patch) }
                return parts.map(String.init).joined(separator: ".")
            }
        }
        struct AvailabilityItem: Decodable {
            let domain: String?
            let introduced: Version?
            let deprecated: Version?
            let obsoleted: Version?
            let isUnconditionallyUnavailable: Bool?
        }
        struct Signature: Decodable {
            struct Parameter: Decodable {
                let name: String
                let declarationFragments: [Fragment]?
            }
            let parameters: [Parameter]?
            let returns: [Fragment]?
        }
        struct Extension: Decodable { let extendedModule: String? }

        let kind: Kind
        let identifier: Identifier
        let pathComponents: [String]
        let declarationFragments: [Fragment]?
        let location: Location?
        let availability: [AvailabilityItem]?
        let functionSignature: Signature?
        let swiftExtension: Extension?
        let spi: Bool?
    }
    struct Relationship: Decodable {
        let kind: String
        let source: String
        let target: String
        let targetFallback: String?
    }

    let symbols: [Symbol]
    let relationships: [Relationship]
}

extension SymbolGraph.Symbol {
    var declarationText: String { Self.text(declarationFragments ?? []) }

    var availabilityItems: [Availability]? {
        let items = (availability ?? []).compactMap { item -> Availability? in
            guard let domain = item.domain else { return nil }
            return Availability(domain: domain, introduced: item.introduced?.text, deprecated: item.deprecated?.text,
                                obsoleted: item.obsoleted?.text,
                                unavailable: item.isUnconditionallyUnavailable == true ? true : nil)
        }
        return items.isEmpty ? nil : items
    }

    static func text(_ fragments: [Fragment]) -> String {
        fragments.map(\.spelling).joined()
            .split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
    }

    /// A parameter's type: its fragments without its own name and the
    /// parentheses a method parameter is written in.
    static func parameterType(_ fragments: [Fragment]) -> String {
        var text = text(fragments.filter { $0.kind != "internalParam" }).trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("("), text.hasSuffix(")") { text = String(text.dropFirst().dropLast()) }
        return text.trimmingCharacters(in: .whitespaces)
    }
}

enum Headers {
    /// The manifest's declarations from clang's symbol graphs of a
    /// framework's headers. `headersDirectory` is the framework's Headers,
    /// which header paths are made relative to.
    static func declarations(_ graphs: [SymbolGraph], headersDirectory: String) -> [Declaration] {
        var superclasses: [String: String] = [:]
        var protocols: [String: [String]] = [:]
        for graph in graphs {
            for relationship in graph.relationships {
                let target = relationship.targetFallback ?? name(fromUSR: relationship.target)
                switch relationship.kind {
                case "inheritsFrom": superclasses[relationship.source] = target
                case "conformsTo": protocols[relationship.source, default: []].append(target)
                default: break
                }
            }
        }
        let prefix = headersDirectory.hasSuffix("/") ? headersDirectory : headersDirectory + "/"
        var seen: Set<String> = []
        var result: [Declaration] = []
        for graph in graphs {
            for symbol in graph.symbols where seen.insert(symbol.identifier.precise).inserted {
                let usr = symbol.identifier.precise
                let kind = symbol.kind.identifier.split(separator: ".", maxSplits: 1).last.map(String.init) ?? symbol.kind.identifier
                var header = symbol.location.map { location -> String in
                    let path = location.uri.hasPrefix("file://") ? String(location.uri.dropFirst(7)) : location.uri
                    let decoded = path.removingPercentEncoding ?? path
                    return decoded.hasPrefix(prefix) ? String(decoded.dropFirst(prefix.count)) : decoded
                } ?? ""
                if header.isEmpty { header = "?" }
                var declaration = Declaration(kind: kind, name: symbol.pathComponents.last ?? "", usr: usr,
                                              declaration: symbol.declarationText, header: header)
                declaration.line = symbol.location?.position.map { $0.line + 1 }
                if symbol.pathComponents.count > 1 {
                    declaration.container = symbol.pathComponents[symbol.pathComponents.count - 2]
                    declaration.containerKind = containerKind(usr)
                }
                declaration.superclass = superclasses[usr]
                declaration.protocols = protocols[usr]
                declaration.availability = symbol.availabilityItems
                if let signature = symbol.functionSignature {
                    declaration.returns = signature.returns.map(SymbolGraph.Symbol.text)
                    let parameters = (signature.parameters ?? []).map {
                        Parameter(name: $0.name, type: SymbolGraph.Symbol.parameterType($0.declarationFragments ?? []))
                    }
                    declaration.parameters = parameters.isEmpty ? nil : parameters
                }
                if kind == "property" || kind == "type.property" {
                    applyPropertyAttributes(&declaration, symbol.declarationFragments ?? [])
                }
                result.append(declaration)
            }
        }
        return result
    }

    /// A property's attributes and accessor names, from the `@property (…)`
    /// list: the getter is its name and the setter `set<Name>:` unless the
    /// list names them; a readonly property has no setter.
    static func applyPropertyAttributes(_ declaration: inout Declaration, _ fragments: [SymbolGraph.Symbol.Fragment]) {
        let text = SymbolGraph.Symbol.text(fragments)
        var attributes: [String] = []
        if let open = text.firstIndex(of: "("), let close = text[open...].firstIndex(of: ")"),
           text[..<open].trimmingCharacters(in: .whitespaces) == "@property" {
            attributes = text[text.index(after: open)..<close].split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        var getter = declaration.name
        var setter: String?
        if !declaration.name.isEmpty {
            setter = "set" + declaration.name.prefix(1).uppercased() + declaration.name.dropFirst() + ":"
        }
        for attribute in attributes {
            let parts = attribute.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0] == "getter" { getter = parts[1] }
            if parts.count == 2, parts[0] == "setter" { setter = parts[1] }
        }
        if attributes.contains("readonly") { setter = nil }
        declaration.getter = getter
        declaration.setter = setter
        declaration.attributes = attributes.isEmpty ? nil : attributes
    }

    /// The kind of container a member's USR names.
    static func containerKind(_ usr: String) -> String? {
        if usr.hasPrefix("c:objc(cs)") { return "class" }
        if usr.hasPrefix("c:objc(pl)") { return "protocol" }
        if usr.hasPrefix("c:@E@") || usr.hasPrefix("c:@EA@") { return "enum" }
        if usr.hasPrefix("c:@S@") || usr.hasPrefix("c:@SA@") { return "struct" }
        if usr.hasPrefix("c:@U@") || usr.hasPrefix("c:@UA@") { return "union" }
        return nil
    }

    /// A class's or protocol's name from its USR, for relationships to a
    /// declaration outside the graph that carry no fallback name.
    static func name(fromUSR usr: String) -> String {
        for marker in ["(cs)", "(pl)"] {
            if let range = usr.range(of: marker, options: .backwards) { return String(usr[range.upperBound...]) }
        }
        return usr
    }
}

enum SwiftAPI {
    /// The module's own Swift declarations from the graphs
    /// `swift-symbolgraph-extract` writes (the module's file and one per
    /// module it extends): those with Swift USRs, without the
    /// Objective-C API it imports (which the headers give) and without the
    /// protocols' default implementations it inherits.
    static func declarations(_ graphs: [(extendedModule: String?, graph: SymbolGraph)], module: String) -> [SwiftDeclaration] {
        var seen: Set<String> = []
        var result: [SwiftDeclaration] = []
        for (extendedModule, graph) in graphs {
            for symbol in graph.symbols {
                let usr = symbol.identifier.precise
                guard usr.hasPrefix("s:"), !usr.contains("::SYNTHESIZED::"), symbol.spi != true,
                      seen.insert(usr).inserted else { continue }
                let kind = symbol.kind.identifier.hasPrefix("swift.")
                    ? String(symbol.kind.identifier.dropFirst(6)) : symbol.kind.identifier
                var declaration = SwiftDeclaration(kind: kind, path: symbol.pathComponents.joined(separator: "."), usr: usr,
                                                   declaration: symbol.declarationText)
                let extended = symbol.swiftExtension?.extendedModule ?? extendedModule
                declaration.extendedModule = extended == module ? nil : extended
                declaration.availability = symbol.availabilityItems
                result.append(declaration)
            }
        }
        return result
    }
}
