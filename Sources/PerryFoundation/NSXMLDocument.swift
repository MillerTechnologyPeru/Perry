import CLibXML2
import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

// NSXMLNode, NSXMLElement, NSXMLDocument and NSXMLDTD: Foundation's XML tree
// on macOS. Each node is an object holding its kind, name, value, children,
// attributes and namespaces, and its parent, unretained: nodes keep their
// identity as they move about the tree. Documents are parsed with libxml2 and
// written out here; XPath queries take the location paths programs use
// (child and descendant steps, names, *, @attributes, text(), node(), and
// position and value predicates).

/// NSXMLNodeKind.
enum XMLKind: UInt {
    case invalid = 0, document, element, attribute, namespace, processingInstruction, comment, text, dtd
    case entityDeclaration, attributeDeclaration, elementDeclaration, notationDeclaration
}

/// The options NSXMLNode's methods take.
enum XMLOptions {
    static let isCDATA: UInt = 1 << 0
    static let expandEmptyElement: UInt = 1 << 1
    static let compactEmptyElement: UInt = 1 << 2
    static let useSingleQuotes: UInt = 1 << 3
    static let prettyPrint: UInt = 1 << 17
    static let preserveCDATA: UInt = 1 << 24
    static let preserveWhitespace: UInt = 1 << 25
}

final class XMLNodeState {
    var kind: XMLKind
    var name: String?
    /// A text, comment, attribute, namespace or processing instruction's.
    var value = ""
    var uri: String?
    var isCDATA = false
    /// Element written as <name/> when it is empty.
    var compact = false
    /// Retained.
    var children: [id] = []
    var attributes: [id] = []
    var namespaces: [id] = []
    /// Not retained.
    var parent: id?
    // A document's.
    var version: String?
    var characterEncoding: String?
    var standalone = false
    var contentKind: UInt = 0
    var mimeType: String?
    /// Retained.
    var dtd: id?
    // A DTD's.
    var publicID: String?
    var systemID: String?

    init(_ kind: XMLKind) { self.kind = kind }
}

enum XMLNodes {
    nonisolated(unsafe) static var nodeClass: Class!
    nonisolated(unsafe) static var elementClass: Class!
    nonisolated(unsafe) static var documentClass: Class!
    nonisolated(unsafe) static var dtdClass: Class!

    /// The node's state, made for its class's kind when it was made without
    /// one ([[NSXMLElement alloc] init] and subclasses' own initializers).
    static func state(_ node: id) -> XMLNodeState {
        if let state = Storage.get(node, as: XMLNodeState.self) { return state }
        let kind: XMLKind
        if ObjC.isKind(node, of: elementClass) { kind = .element }
        else if ObjC.isKind(node, of: documentClass) { kind = .document }
        else if ObjC.isKind(node, of: dtdClass) { kind = .dtd }
        else { kind = .invalid }
        let state = XMLNodeState(kind)
        Storage.set(node, state)
        return state
    }

    static func cls(for kind: XMLKind) -> Class {
        switch kind {
        case .element: elementClass
        case .document: documentClass
        case .dtd: dtdClass
        default: nodeClass
        }
    }

    /// A new node, retained.
    static func make(_ kind: XMLKind, name: String? = nil, value: String = "") -> id {
        let node = Storage.allocate(UnsafeMutableRawPointer(cls(for: kind)))!
        let state = XMLNodeState(kind)
        state.name = name
        state.value = value
        Storage.set(node, state)
        return node
    }

    static func autoreleased(_ kind: XMLKind, name: String? = nil, value: String = "") -> id {
        ObjC.autorelease(make(kind, name: name, value: value))!
    }

    // MARK: The tree

    /// Takes a node out of its parent's children, attributes or namespaces.
    static func detach(_ node: id) {
        guard let parent = state(node).parent else { return }
        let parentState = state(parent)
        state(node).parent = nil
        if let index = parentState.children.firstIndex(of: node) {
            parentState.children.remove(at: index)
        } else if let index = parentState.attributes.firstIndex(of: node) {
            parentState.attributes.remove(at: index)
        } else if let index = parentState.namespaces.firstIndex(of: node) {
            parentState.namespaces.remove(at: index)
        } else {
            return
        }
        ObjC.release(node)
    }

    static func insertChild(_ child: id?, into parent: id, at index: Int) {
        guard let child else { return }
        ObjC.retain(child)
        detach(child)
        let parentState = state(parent)
        parentState.children.insert(child, at: max(0, min(index, parentState.children.count)))
        state(child).parent = parent
    }

    static func removeChild(of parent: id, at index: Int) {
        let parentState = state(parent)
        guard parentState.children.indices.contains(index) else { return }
        let child = parentState.children.remove(at: index)
        state(child).parent = nil
        ObjC.release(child)
    }

    static func removeAllChildren(of parent: id) {
        let parentState = state(parent)
        let children = parentState.children
        parentState.children.removeAll()
        for child in children {
            state(child).parent = nil
            ObjC.release(child)
        }
    }

    static func addAttribute(_ attribute: id?, to element: id) {
        guard let attribute else { return }
        let elementState = state(element)
        if let name = state(attribute).name, let old = elementState.attributes.first(where: { state($0).name == name }), old != attribute {
            detach(old)
        }
        ObjC.retain(attribute)
        detach(attribute)
        elementState.attributes.append(attribute)
        state(attribute).parent = element
    }

    static func addNamespace(_ namespace: id?, to element: id) {
        guard let namespace else { return }
        let elementState = state(element)
        let name = state(namespace).name ?? ""
        if let old = elementState.namespaces.first(where: { (state($0).name ?? "") == name }), old != namespace { detach(old) }
        ObjC.retain(namespace)
        detach(namespace)
        elementState.namespaces.append(namespace)
        state(namespace).parent = element
    }

    /// Lets go of a node's children, attributes, namespaces and DTD.
    static func release(_ node: id) {
        guard let state = Storage.get(node, as: XMLNodeState.self) else { return }
        for child in state.children + state.attributes + state.namespaces {
            self.state(child).parent = nil
            ObjC.release(child)
        }
        state.children.removeAll()
        state.attributes.removeAll()
        state.namespaces.removeAll()
        if let dtd = state.dtd {
            self.state(dtd).parent = nil
            ObjC.release(dtd)
            state.dtd = nil
        }
    }

    /// A copy of a node and everything under it, in no tree, retained.
    static func copy(_ node: id) -> id {
        let original = state(node)
        let copy = Storage.allocate(UnsafeMutableRawPointer(ObjC.objectGetClass(node)))!
        let made = XMLNodeState(original.kind)
        made.name = original.name
        made.value = original.value
        made.uri = original.uri
        made.isCDATA = original.isCDATA
        made.compact = original.compact
        made.version = original.version
        made.characterEncoding = original.characterEncoding
        made.standalone = original.standalone
        made.contentKind = original.contentKind
        made.mimeType = original.mimeType
        made.publicID = original.publicID
        made.systemID = original.systemID
        Storage.set(copy, made)
        for child in original.children {
            let childCopy = self.copy(child)
            made.children.append(childCopy)
            state(childCopy).parent = copy
        }
        for attribute in original.attributes {
            let attributeCopy = self.copy(attribute)
            made.attributes.append(attributeCopy)
            state(attributeCopy).parent = copy
        }
        for namespace in original.namespaces {
            let namespaceCopy = self.copy(namespace)
            made.namespaces.append(namespaceCopy)
            state(namespaceCopy).parent = copy
        }
        if let dtd = original.dtd {
            let dtdCopy = self.copy(dtd)
            made.dtd = dtdCopy
            state(dtdCopy).parent = copy
        }
        return copy
    }

    // MARK: Values

    /// An element or document's text, its text nodes' in order; another
    /// node's own value.
    static func stringValue(_ node: id) -> String {
        let nodeState = state(node)
        switch nodeState.kind {
        case .element, .document:
            return nodeState.children.map { child -> String in
                let kind = state(child).kind
                return kind == .text || kind == .element ? stringValue(child) : ""
            }.joined()
        default:
            return nodeState.value
        }
    }

    static func setStringValue(_ node: id, _ value: String) {
        let nodeState = state(node)
        switch nodeState.kind {
        case .element, .document:
            removeAllChildren(of: node)
            if !value.isEmpty {
                let text = make(.text, value: value)
                insertChild(text, into: node, at: 0)
                ObjC.release(text)
            }
        default:
            nodeState.value = value
        }
    }

    static func localName(_ name: String?) -> String? {
        guard let name else { return nil }
        return name.firstIndex(of: ":").map { String(name[name.index(after: $0)...]) } ?? name
    }

    static func prefix(_ name: String?) -> String {
        guard let name, let colon = name.firstIndex(of: ":") else { return "" }
        return String(name[..<colon])
    }

    static func document(of node: id) -> id? {
        var current: id? = node
        while let each = current {
            if state(each).kind == .document { return each }
            current = state(each).parent
        }
        return nil
    }

    /// The topmost node above this one.
    static func top(of node: id) -> id {
        var current = node
        while let parent = state(current).parent { current = parent }
        return current
    }

    // MARK: Writing

    static func escaped(_ text: String, attribute: Bool, quote: Character = "\"") -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"" where attribute && quote == "\"": out += "&quot;"
            case "'" where attribute && quote == "'": out += "&apos;"
            case "\r" where attribute: out += "&#xD;"
            case "\n" where attribute: out += "&#xA;"
            case "\t" where attribute: out += "&#x9;"
            default: out.append(character)
            }
        }
        return out
    }

    static func xml(_ node: id, options: UInt, level: Int = 0) -> String {
        let nodeState = state(node)
        let pretty = options & XMLOptions.prettyPrint != 0
        let indent = pretty ? String(repeating: " ", count: 4 * level) : ""
        let quote: Character = options & XMLOptions.useSingleQuotes != 0 ? "'" : "\""
        switch nodeState.kind {
        case .document:
            var out = "<?xml version=\"\(nodeState.version ?? "1.0")\""
            if let encoding = nodeState.characterEncoding { out += " encoding=\"\(encoding)\"" }
            if nodeState.standalone { out += " standalone=\"yes\"" }
            out += "?>"
            var parts: [String] = []
            if let dtd = nodeState.dtd { parts.append(xml(dtd, options: options, level: 0)) }
            parts += nodeState.children.map { xml($0, options: options, level: 0) }
            out += (pretty ? "\n" : "") + parts.joined(separator: pretty ? "\n" : "")
            return out
        case .element:
            let name = nodeState.name ?? ""
            var out = indent + "<" + name
            for namespace in nodeState.namespaces { out += " " + xml(namespace, options: options) }
            for attribute in nodeState.attributes { out += " " + xml(attribute, options: options) }
            if nodeState.children.isEmpty {
                let compact = options & XMLOptions.compactEmptyElement != 0
                    || (nodeState.compact && options & XMLOptions.expandEmptyElement == 0)
                return out + (compact ? "/>" : "></" + name + ">")
            }
            out += ">"
            let onlyText = nodeState.children.allSatisfy { state($0).kind == .text }
            if pretty && !onlyText {
                for child in nodeState.children {
                    let childText = xml(child, options: options, level: level + 1)
                    let childIndent = String(repeating: " ", count: 4 * (level + 1))
                    out += "\n" + (state(child).kind == .element ? childText : childIndent + childText)
                }
                out += "\n" + indent
            } else {
                for child in nodeState.children { out += xml(child, options: options & ~XMLOptions.prettyPrint, level: 0) }
            }
            return out + "</" + name + ">"
        case .attribute:
            return (nodeState.name ?? "") + "=" + String(quote) + escaped(nodeState.value, attribute: true, quote: quote) + String(quote)
        case .namespace:
            let name = nodeState.name ?? ""
            return (name.isEmpty ? "xmlns" : "xmlns:" + name) + "=" + String(quote) + escaped(nodeState.value, attribute: true, quote: quote) + String(quote)
        case .text:
            if nodeState.isCDATA || options & XMLOptions.isCDATA != 0 { return "<![CDATA[" + nodeState.value + "]]>" }
            return escaped(nodeState.value, attribute: false)
        case .comment:
            return indent + "<!--" + nodeState.value + "-->"
        case .processingInstruction:
            return indent + "<?" + (nodeState.name ?? "") + (nodeState.value.isEmpty ? "" : " " + nodeState.value) + "?>"
        case .dtd:
            var out = "<!DOCTYPE " + (nodeState.name ?? "")
            if let publicID = nodeState.publicID {
                out += " PUBLIC \"" + publicID + "\""
                if let systemID = nodeState.systemID { out += " \"" + systemID + "\"" }
            } else if let systemID = nodeState.systemID {
                out += " SYSTEM \"" + systemID + "\""
            }
            if !nodeState.children.isEmpty {
                out += " [" + nodeState.children.map { xml($0, options: options) }.joined(separator: pretty ? "\n" : "") + "]"
            }
            return out + ">"
        default:
            return nodeState.value
        }
    }

    // MARK: Reading

    /// A document of XML data, retained, or the parser's error.
    static func parse(_ data: Data, options: UInt) -> Result<id, XMLParseError> {
        var flags = Int32(XML_PARSE_NONET.rawValue) | Int32(XML_PARSE_NOENT.rawValue) | Int32(XML_PARSE_HUGE.rawValue)
        if options & XMLOptions.preserveCDATA == 0 { flags |= Int32(XML_PARSE_NOCDATA.rawValue) }
        if options & XMLOptions.preserveWhitespace == 0 { flags |= Int32(XML_PARSE_NOBLANKS.rawValue) }
        xmlResetLastError()
        let parsed = data.withUnsafeBytes { bytes -> xmlDocPtr? in
            guard let base = bytes.baseAddress?.assumingMemoryBound(to: CChar.self) else { return nil }
            return xmlReadMemory(base, Int32(bytes.count), nil, nil, flags)
        }
        guard let parsed else {
            let error = xmlGetLastError()
            let message = error?.pointee.message.map { String(cString: $0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? "The XML couldn’t be read."
            return .failure(XMLParseError(code: Int(error?.pointee.code ?? 1), line: Int(error?.pointee.line ?? 0), message: message))
        }
        defer { xmlFreeDoc(parsed) }
        let document = make(.document)
        let documentState = state(document)
        documentState.version = parsed.pointee.version.map { String(cString: $0) }
        documentState.characterEncoding = parsed.pointee.encoding.map { String(cString: $0) }
        documentState.standalone = parsed.pointee.standalone == 1
        let keepWhitespace = options & XMLOptions.preserveWhitespace != 0
        var child = parsed.pointee.children
        while let each = child {
            if each.pointee.type == XML_DTD_NODE {
                let dtd = make(.dtd, name: each.pointee.name.map { String(cString: $0) })
                let dtdPointer = UnsafeMutableRawPointer(each).assumingMemoryBound(to: xmlDtd.self)
                state(dtd).publicID = dtdPointer.pointee.ExternalID.map { String(cString: $0) }
                state(dtd).systemID = dtdPointer.pointee.SystemID.map { String(cString: $0) }
                documentState.dtd = dtd
                state(dtd).parent = document
            } else if let node = convert(each, keepWhitespace: keepWhitespace) {
                documentState.children.append(node)
                state(node).parent = document
            }
            child = each.pointee.next
        }
        return .success(document)
    }

    private static func qualifiedName(_ name: UnsafePointer<xmlChar>?, _ namespace: xmlNsPtr?) -> String {
        let local = name.map { String(cString: $0) } ?? ""
        guard let prefix = namespace?.pointee.prefix else { return local }
        return String(cString: prefix) + ":" + local
    }

    /// A libxml2 node as a node here, retained; nil for what isn't kept.
    private static func convert(_ node: xmlNodePtr, keepWhitespace: Bool) -> id? {
        switch node.pointee.type {
        case XML_ELEMENT_NODE:
            let element = make(.element, name: qualifiedName(node.pointee.name, node.pointee.ns))
            let elementState = state(element)
            elementState.uri = node.pointee.ns?.pointee.href.map { String(cString: $0) }
            var namespace = node.pointee.nsDef
            while let each = namespace {
                let made = make(.namespace, name: each.pointee.prefix.map { String(cString: $0) } ?? "",
                                value: each.pointee.href.map { String(cString: $0) } ?? "")
                elementState.namespaces.append(made)
                state(made).parent = element
                namespace = each.pointee.next
            }
            var attribute = node.pointee.properties
            while let each = attribute {
                let value = xmlNodeListGetString(node.pointee.doc, each.pointee.children, 1)
                let made = make(.attribute, name: qualifiedName(each.pointee.name, each.pointee.ns),
                                value: value.map { String(cString: $0) } ?? "")
                if let value { free(value) }   // xmlFree is free in libxml2's default allocator
                state(made).uri = each.pointee.ns?.pointee.href.map { String(cString: $0) }
                elementState.attributes.append(made)
                state(made).parent = element
                attribute = each.pointee.next
            }
            var child = node.pointee.children
            while let each = child {
                if let made = convert(each, keepWhitespace: keepWhitespace) {
                    elementState.children.append(made)
                    state(made).parent = element
                }
                child = each.pointee.next
            }
            elementState.compact = elementState.children.isEmpty
            return element
        case XML_TEXT_NODE, XML_CDATA_SECTION_NODE:
            let text = node.pointee.content.map { String(cString: $0) } ?? ""
            if !keepWhitespace && text.allSatisfy(\.isWhitespace) { return nil }
            let made = make(.text, value: text)
            state(made).isCDATA = node.pointee.type == XML_CDATA_SECTION_NODE
            return made
        case XML_COMMENT_NODE:
            return make(.comment, value: node.pointee.content.map { String(cString: $0) } ?? "")
        case XML_PI_NODE:
            return make(.processingInstruction, name: node.pointee.name.map { String(cString: $0) },
                        value: node.pointee.content.map { String(cString: $0) } ?? "")
        default:
            return nil
        }
    }

    // MARK: XPath

    /// The nodes a location path finds from a node: steps parted by / (//
    /// for descendants), each ., .., *, a name, @name, @*, text(), node()
    /// or comment(), with [n], [last()], [@name], [@name='value'] and
    /// [name='value'] predicates; | joins paths. Nil for what isn't that.
    static func evaluate(_ path: String, from context: id) -> [id]? {
        var results: [id] = []
        for part in splitOutside(path, on: "|") {
            guard let found = evaluatePath(part.trimmingCharacters(in: .whitespaces), from: context) else { return nil }
            for node in found where !results.contains(node) { results.append(node) }
        }
        return results
    }

    private static func evaluatePath(_ path: String, from context: id) -> [id]? {
        var rest = Substring(path)
        var current: [id]
        if rest.hasPrefix("/") {
            current = [document(of: context) ?? top(of: context)]
        } else {
            current = [context]
        }
        if rest == "/" { return current }
        while !rest.isEmpty {
            var descendant = false
            if rest.hasPrefix("//") {
                descendant = true
                rest = rest.dropFirst(2)
            } else if rest.hasPrefix("/") {
                rest = rest.dropFirst()
            }
            let step = takeStep(&rest)
            guard !step.isEmpty, let (test, predicates) = parseStep(step) else { return nil }
            var next: [id] = []
            for node in current {
                let candidates = descendant ? descendantsOrSelf(node) : [node]
                for candidate in candidates {
                    guard var matched = apply(test, to: candidate) else { return nil }
                    for predicate in predicates {
                        guard let filtered = filter(matched, by: predicate) else { return nil }
                        matched = filtered
                    }
                    for each in matched where !next.contains(each) { next.append(each) }
                }
            }
            current = next
        }
        return current
    }

    private static func splitOutside(_ text: String, on separator: Character) -> [String] {
        var parts: [String] = []
        var depth = 0
        var quote: Character?
        var current = ""
        for character in text {
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "'" || character == "\"" {
                quote = character
            } else if character == "[" {
                depth += 1
            } else if character == "]" {
                depth -= 1
            } else if character == separator && depth == 0 {
                parts.append(current)
                current = ""
                continue
            }
            current.append(character)
        }
        parts.append(current)
        return parts
    }

    /// The next step, up to a / outside brackets and quotes.
    private static func takeStep(_ rest: inout Substring) -> String {
        var depth = 0
        var quote: Character?
        var index = rest.startIndex
        while index < rest.endIndex {
            let character = rest[index]
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "'" || character == "\"" {
                quote = character
            } else if character == "[" {
                depth += 1
            } else if character == "]" {
                depth -= 1
            } else if character == "/" && depth == 0 {
                break
            }
            index = rest.index(after: index)
        }
        let step = String(rest[..<index])
        rest = rest[index...]
        return step
    }

    private static func parseStep(_ step: String) -> (String, [String])? {
        guard let open = step.firstIndex(of: "[") else { return (step.trimmingCharacters(in: .whitespaces), []) }
        let test = String(step[..<open]).trimmingCharacters(in: .whitespaces)
        var predicates: [String] = []
        var rest = Substring(step[open...])
        while rest.hasPrefix("[") {
            var depth = 0
            var quote: Character?
            var end: Substring.Index?
            var index = rest.startIndex
            while index < rest.endIndex {
                let character = rest[index]
                if let open = quote {
                    if character == open { quote = nil }
                } else if character == "'" || character == "\"" {
                    quote = character
                } else if character == "[" {
                    depth += 1
                } else if character == "]" {
                    depth -= 1
                    if depth == 0 { end = index; break }
                }
                index = rest.index(after: index)
            }
            guard let end else { return nil }
            predicates.append(String(rest[rest.index(after: rest.startIndex)..<end]).trimmingCharacters(in: .whitespaces))
            rest = rest[rest.index(after: end)...].drop { $0 == " " }
        }
        return rest.isEmpty ? (test, predicates) : nil
    }

    private static func descendantsOrSelf(_ node: id) -> [id] {
        var nodes = [node]
        for child in state(node).children { nodes += descendantsOrSelf(child) }
        return nodes
    }

    private static func nameMatches(_ name: String?, _ test: String) -> Bool {
        guard let name else { return false }
        return name == test || (!test.contains(":") && localName(name) == test)
    }

    /// The nodes one step's test finds from a node.
    private static func apply(_ test: String, to node: id) -> [id]? {
        let nodeState = state(node)
        switch test {
        case ".", "self::node()": return [node]
        case "..", "parent::node()": return nodeState.parent.map { [$0] } ?? []
        case "*": return nodeState.children.filter { state($0).kind == .element }
        case "node()": return nodeState.children
        case "text()": return nodeState.children.filter { state($0).kind == .text }
        case "comment()": return nodeState.children.filter { state($0).kind == .comment }
        case "@*", "attribute::*": return nodeState.attributes
        default:
            var test = test
            if test.hasPrefix("child::") { test.removeFirst(7) }
            if test.hasPrefix("attribute::") { test = "@" + test.dropFirst(11) }
            if test.hasPrefix("@") {
                let name = String(test.dropFirst())
                return nodeState.attributes.filter { nameMatches(state($0).name, name) }
            }
            guard !test.isEmpty, !test.contains("(") else { return nil }
            return nodeState.children.filter { state($0).kind == .element && nameMatches(state($0).name, test) }
        }
    }

    private static func unquoted(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2, let first = trimmed.first, first == "'" || first == "\"", trimmed.last == first else { return nil }
        return String(trimmed.dropFirst().dropLast())
    }

    private static func filter(_ nodes: [id], by predicate: String) -> [id]? {
        if let position = Int(predicate) {
            return nodes.indices.contains(position - 1) ? [nodes[position - 1]] : []
        }
        if predicate == "last()" { return nodes.last.map { [$0] } ?? [] }
        if let equals = predicate.firstIndex(of: "=") {
            let left = predicate[..<equals].trimmingCharacters(in: .whitespaces)
            guard let value = unquoted(String(predicate[predicate.index(after: equals)...])) else { return nil }
            return nodes.filter { node in
                guard let found = evaluatePath(left, from: node) else { return false }
                return found.contains { stringValue($0) == value }
            }
        }
        return nodes.filter { node in !(evaluatePath(predicate, from: node) ?? []).isEmpty }
    }
}

struct XMLParseError: Error {
    let code: Int
    let line: Int
    let message: String

    /// An NSXMLParserErrorDomain error, autoreleased.
    var object: id? {
        Errors.autoreleased(domain: Strings.autoreleased("NSXMLParserErrorDomain"), code: code,
                            description: line > 0 ? "Line \(line): \(message)" : message)
    }
}

// MARK: - NSXMLNode

@ObjCClass("NSXMLNode")
public class NSXMLNode: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        XMLNodes.nodeClass = cls.storage
    }

    var node: XMLNodeState { XMLNodes.state(objcObject) }

    @ObjCMethod("init")
    func initialize() -> Self {
        _ = node
        return self
    }

    @ObjCMethod("initWithKind:")
    func initialize(kind: UInt) -> Self { initialize(kind: kind, options: 0) }

    @ObjCMethod("initWithKind:options:")
    func initialize(kind: UInt, options: UInt) -> Self {
        let state = XMLNodeState(XMLKind(rawValue: kind) ?? .invalid)
        state.isCDATA = options & XMLOptions.isCDATA != 0
        Storage.set(objcObject, state)
        return self
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        XMLNodes.release(objcObject)
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: XMLNodes.nodeClass)
    }

    @ObjCMethod("copyWithZone:")
    func copy(zone: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer { XMLNodes.copy(objcObject) }

    // Made nodes.

    @ObjCClassMethod("document")
    static func document() -> UnsafeMutableRawPointer? { XMLNodes.autoreleased(.document) }

    @ObjCClassMethod("documentWithRootElement:")
    static func document(rootElement: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        let document = XMLNodes.autoreleased(.document)
        XMLNodes.insertChild(rootElement, into: document, at: 0)
        return document
    }

    @ObjCClassMethod("elementWithName:")
    static func element(name: String?) -> UnsafeMutableRawPointer? { XMLNodes.autoreleased(.element, name: name) }

    @ObjCClassMethod("elementWithName:URI:")
    static func element(name: String?, uri: String?) -> UnsafeMutableRawPointer? {
        let element = XMLNodes.autoreleased(.element, name: name)
        XMLNodes.state(element).uri = uri
        return element
    }

    @ObjCClassMethod("elementWithName:stringValue:")
    static func element(name: String?, stringValue: String?) -> UnsafeMutableRawPointer? {
        let element = XMLNodes.autoreleased(.element, name: name)
        XMLNodes.setStringValue(element, stringValue ?? "")
        return element
    }

    @ObjCClassMethod("elementWithName:children:attributes:")
    static func element(name: String?, children: UnsafeMutableRawPointer?, attributes: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        let element = XMLNodes.autoreleased(.element, name: name)
        for child in Arrays.elements(children) { XMLNodes.insertChild(child, into: element, at: Int.max) }
        for attribute in Arrays.elements(attributes) { XMLNodes.addAttribute(attribute, to: element) }
        return element
    }

    @ObjCClassMethod("attributeWithName:stringValue:")
    static func attribute(name: String?, stringValue: String?) -> UnsafeMutableRawPointer? {
        XMLNodes.autoreleased(.attribute, name: name, value: stringValue ?? "")
    }

    @ObjCClassMethod("attributeWithName:URI:stringValue:")
    static func attribute(name: String?, uri: String?, stringValue: String?) -> UnsafeMutableRawPointer? {
        let attribute = XMLNodes.autoreleased(.attribute, name: name, value: stringValue ?? "")
        XMLNodes.state(attribute).uri = uri
        return attribute
    }

    @ObjCClassMethod("namespaceWithName:stringValue:")
    static func namespace(name: String?, stringValue: String?) -> UnsafeMutableRawPointer? {
        XMLNodes.autoreleased(.namespace, name: name ?? "", value: stringValue ?? "")
    }

    @ObjCClassMethod("textWithStringValue:")
    static func text(stringValue: String?) -> UnsafeMutableRawPointer? { XMLNodes.autoreleased(.text, value: stringValue ?? "") }

    @ObjCClassMethod("commentWithStringValue:")
    static func comment(stringValue: String?) -> UnsafeMutableRawPointer? { XMLNodes.autoreleased(.comment, value: stringValue ?? "") }

    @ObjCClassMethod("processingInstructionWithName:stringValue:")
    static func processingInstruction(name: String?, stringValue: String?) -> UnsafeMutableRawPointer? {
        XMLNodes.autoreleased(.processingInstruction, name: name, value: stringValue ?? "")
    }

    @ObjCClassMethod("DTDNodeWithXMLString:")
    static func dtdNode(xmlString: String?) -> UnsafeMutableRawPointer? { nil }

    @ObjCClassMethod("localNameForName:")
    static func localName(forName name: String?) -> String? { XMLNodes.localName(name) }

    @ObjCClassMethod("prefixForName:")
    static func prefix(forName name: String?) -> String? { XMLNodes.prefix(name) }

    // The node.

    @ObjCMethod("kind") func kind() -> UInt { node.kind.rawValue }
    @ObjCMethod("name") func name() -> String? { node.name }
    @ObjCMethod("setName:") func setName(_ name: String?) { node.name = name }
    @ObjCMethod("localName") func localName() -> String? { XMLNodes.localName(node.name) }
    @ObjCMethod("prefix") func prefix() -> String? { node.name == nil ? nil : XMLNodes.prefix(node.name) }
    @ObjCMethod("URI") func uri() -> String? { node.uri }
    @ObjCMethod("setURI:") func setURI(_ uri: String?) { node.uri = uri }

    @ObjCMethod("stringValue") func stringValue() -> String? { XMLNodes.stringValue(objcObject) }
    @ObjCMethod("setStringValue:") func setStringValue(_ value: String?) { XMLNodes.setStringValue(objcObject, value ?? "") }
    @ObjCMethod("setStringValue:resolvingEntities:")
    func setStringValue(_ value: String?, resolvingEntities: Bool) { XMLNodes.setStringValue(objcObject, value ?? "") }
    @ObjCMethod("objectValue") func objectValue() -> String? { XMLNodes.stringValue(objcObject) }
    @ObjCMethod("setObjectValue:")
    func setObjectValue(_ value: UnsafeMutableRawPointer?) {
        let text = value.flatMap { Strings.value(of: $0) } ?? value.map { Format.describe($0) } ?? ""
        XMLNodes.setStringValue(objcObject, text)
    }

    // The tree.

    @ObjCMethod("parent") func parent() -> UnsafeMutableRawPointer? { node.parent }
    @ObjCMethod("rootDocument") func rootDocument() -> UnsafeMutableRawPointer? { XMLNodes.document(of: objcObject) }
    @ObjCMethod("childCount") func childCount() -> UInt { UInt(node.children.count) }

    /// Nil for a node that can't have children.
    @ObjCMethod("children")
    func children() -> UnsafeMutableRawPointer? {
        switch node.kind {
        case .element, .document, .dtd: Arrays.autoreleased(node.children)
        default: nil
        }
    }

    @ObjCMethod("childAtIndex:")
    func child(at index: UInt) -> UnsafeMutableRawPointer? {
        node.children.indices.contains(Int(index)) ? node.children[Int(index)] : nil
    }

    @ObjCMethod("index")
    func index() -> UInt {
        guard let parent = node.parent else { return 0 }
        let parentState = XMLNodes.state(parent)
        return UInt(parentState.children.firstIndex(of: objcObject) ?? parentState.attributes.firstIndex(of: objcObject)
            ?? parentState.namespaces.firstIndex(of: objcObject) ?? 0)
    }

    @ObjCMethod("level")
    func level() -> UInt {
        var level: UInt = 0
        var current = node.parent
        while let each = current {
            level += 1
            current = XMLNodes.state(each).parent
        }
        return level
    }

    @ObjCMethod("previousSibling")
    func previousSibling() -> UnsafeMutableRawPointer? {
        guard let parent = node.parent else { return nil }
        let siblings = XMLNodes.state(parent).children
        guard let index = siblings.firstIndex(of: objcObject), index > 0 else { return nil }
        return siblings[index - 1]
    }

    @ObjCMethod("nextSibling")
    func nextSibling() -> UnsafeMutableRawPointer? {
        guard let parent = node.parent else { return nil }
        let siblings = XMLNodes.state(parent).children
        guard let index = siblings.firstIndex(of: objcObject), index + 1 < siblings.count else { return nil }
        return siblings[index + 1]
    }

    /// The node after this one in document order: its first child, else
    /// the next sibling of it or of the nearest node above that has one.
    @ObjCMethod("nextNode")
    func nextNode() -> UnsafeMutableRawPointer? {
        if let first = node.children.first { return first }
        var current: id? = objcObject
        while let each = current {
            if let parent = XMLNodes.state(each).parent {
                let siblings = XMLNodes.state(parent).children
                if let index = siblings.firstIndex(of: each), index + 1 < siblings.count { return siblings[index + 1] }
            }
            current = XMLNodes.state(each).parent
        }
        return nil
    }

    @ObjCMethod("previousNode")
    func previousNode() -> UnsafeMutableRawPointer? {
        guard let parent = node.parent else { return nil }
        let siblings = XMLNodes.state(parent).children
        guard let index = siblings.firstIndex(of: objcObject) else { return nil }
        guard index > 0 else { return parent }
        var current = siblings[index - 1]
        while let last = XMLNodes.state(current).children.last { current = last }
        return current
    }

    @ObjCMethod("detach") func detach() { XMLNodes.detach(objcObject) }

    // Children: NSXMLElement's and NSXMLDocument's.

    @ObjCMethod("addChild:")
    func addChild(_ child: UnsafeMutableRawPointer?) { XMLNodes.insertChild(child, into: objcObject, at: node.children.count) }

    @ObjCMethod("insertChild:atIndex:")
    func insertChild(_ child: UnsafeMutableRawPointer?, at index: UInt) { XMLNodes.insertChild(child, into: objcObject, at: Int(index)) }

    @ObjCMethod("insertChildren:atIndex:")
    func insertChildren(_ children: UnsafeMutableRawPointer?, at index: UInt) {
        for (offset, child) in Arrays.elements(children).enumerated() {
            XMLNodes.insertChild(child, into: objcObject, at: Int(index) + offset)
        }
    }

    @ObjCMethod("removeChildAtIndex:")
    func removeChild(at index: UInt) { XMLNodes.removeChild(of: objcObject, at: Int(index)) }

    @ObjCMethod("setChildren:")
    func setChildren(_ children: UnsafeMutableRawPointer?) {
        XMLNodes.removeAllChildren(of: objcObject)
        for child in Arrays.elements(children) { XMLNodes.insertChild(child, into: objcObject, at: Int.max) }
    }

    @ObjCMethod("replaceChildAtIndex:withNode:")
    func replaceChild(at index: UInt, with child: UnsafeMutableRawPointer?) {
        XMLNodes.removeChild(of: objcObject, at: Int(index))
        XMLNodes.insertChild(child, into: objcObject, at: Int(index))
    }

    // Writing.

    @ObjCMethod("XMLString") func xmlString() -> String { XMLNodes.xml(objcObject, options: 0) }
    @ObjCMethod("XMLStringWithOptions:") func xmlString(options: UInt) -> String { XMLNodes.xml(objcObject, options: options) }
    @ObjCMethod("canonicalXMLStringPreservingComments:")
    func canonicalXMLString(preservingComments: Bool) -> String { XMLNodes.xml(objcObject, options: XMLOptions.expandEmptyElement) }
    @ObjCMethod("description") func description() -> String { XMLNodes.xml(objcObject, options: 0) }

    /// The node's path from its document's root, as XPath.
    @ObjCMethod("XPath")
    func xPath() -> String? {
        var parts: [String] = []
        var current: id? = objcObject
        while let each = current, let parent = XMLNodes.state(each).parent {
            let eachState = XMLNodes.state(each)
            switch eachState.kind {
            case .attribute: parts.append("@" + (eachState.name ?? ""))
            case .text: parts.append("text()")
            default:
                let same = XMLNodes.state(parent).children.filter { XMLNodes.state($0).name == eachState.name && XMLNodes.state($0).kind == eachState.kind }
                let position = (same.firstIndex(of: each) ?? 0) + 1
                parts.append((eachState.name ?? "node()") + "[\(position)]")
            }
            current = parent
        }
        return "/" + parts.reversed().joined(separator: "/")
    }

    @ObjCMethod("nodesForXPath:error:")
    func nodes(forXPath path: String?, error: UnsafeMutablePointer<id?>?) -> UnsafeMutableRawPointer? {
        guard let path, let found = XMLNodes.evaluate(path, from: objcObject) else {
            error?.pointee = Errors.autoreleased(domain: Strings.autoreleased("NSXMLParserErrorDomain"), code: 1,
                                                 description: "The XPath \(path ?? "") isn’t one this can evaluate.")
            return nil
        }
        return Arrays.autoreleased(found)
    }
}

// MARK: - NSXMLElement

@ObjCClass("NSXMLElement")
public class NSXMLElement: NSXMLNode {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        XMLNodes.elementClass = cls.storage
    }

    @ObjCMethod("initWithName:")
    func initialize(name: String?) -> Self {
        let state = XMLNodeState(.element)
        state.name = name
        Storage.set(objcObject, state)
        return self
    }

    @ObjCMethod("initWithName:URI:")
    func initialize(name: String?, uri: String?) -> Self {
        _ = initialize(name: name)
        node.uri = uri
        return self
    }

    @ObjCMethod("initWithName:stringValue:")
    func initialize(name: String?, stringValue: String?) -> Self {
        _ = initialize(name: name)
        XMLNodes.setStringValue(objcObject, stringValue ?? "")
        return self
    }

    /// The element of a string of XML: its document's root element, taken
    /// over by this object.
    @ObjCMethod("initWithXMLString:error:")
    func initialize(xmlString: String?, error: UnsafeMutablePointer<id?>?) -> Self? {
        switch XMLNodes.parse(Data((xmlString ?? "").utf8), options: 0) {
        case .failure(let failure):
            error?.pointee = failure.object
            return nil
        case .success(let document):
            defer { ObjC.release(document) }
            guard let root = XMLNodes.state(document).children.first(where: { XMLNodes.state($0).kind == .element }) else { return nil }
            let rootState = XMLNodes.state(root)
            let state = XMLNodeState(.element)
            state.name = rootState.name
            state.uri = rootState.uri
            state.compact = rootState.compact
            Storage.set(objcObject, state)
            for child in rootState.children { XMLNodes.insertChild(child, into: objcObject, at: Int.max) }
            for attribute in rootState.attributes { XMLNodes.addAttribute(attribute, to: objcObject) }
            for namespace in rootState.namespaces { XMLNodes.addNamespace(namespace, to: objcObject) }
            return self
        }
    }

    @ObjCMethod("elementsForName:")
    func elements(forName name: String?) -> UnsafeMutableRawPointer? {
        Arrays.autoreleased(node.children.filter { child in
            let childState = XMLNodes.state(child)
            return childState.kind == .element && childState.name == name
        })
    }

    @ObjCMethod("elementsForLocalName:URI:")
    func elements(forLocalName name: String?, uri: String?) -> UnsafeMutableRawPointer? {
        Arrays.autoreleased(node.children.filter { child in
            let childState = XMLNodes.state(child)
            return childState.kind == .element && XMLNodes.localName(childState.name) == name && childState.uri == uri
        })
    }

    /// Nil when there are none, as Foundation's.
    @ObjCMethod("attributes")
    func attributes() -> UnsafeMutableRawPointer? { node.attributes.isEmpty ? nil : Arrays.autoreleased(node.attributes) }

    @ObjCMethod("attributeForName:")
    func attribute(forName name: String?) -> UnsafeMutableRawPointer? {
        node.attributes.first { XMLNodes.state($0).name == name }
    }

    @ObjCMethod("attributeForLocalName:URI:")
    func attribute(forLocalName name: String?, uri: String?) -> UnsafeMutableRawPointer? {
        node.attributes.first { XMLNodes.localName(XMLNodes.state($0).name) == name && XMLNodes.state($0).uri == uri }
    }

    @ObjCMethod("addAttribute:") func addAttribute(_ attribute: UnsafeMutableRawPointer?) { XMLNodes.addAttribute(attribute, to: objcObject) }

    @ObjCMethod("removeAttributeForName:")
    func removeAttribute(forName name: String?) {
        if let attribute = node.attributes.first(where: { XMLNodes.state($0).name == name }) { XMLNodes.detach(attribute) }
    }

    @ObjCMethod("setAttributes:")
    func setAttributes(_ attributes: UnsafeMutableRawPointer?) {
        for attribute in node.attributes { XMLNodes.detach(attribute) }
        for attribute in Arrays.elements(attributes) { XMLNodes.addAttribute(attribute, to: objcObject) }
    }

    @ObjCMethod("setAttributesWithDictionary:")
    func setAttributes(dictionary: UnsafeMutableRawPointer?) {
        for attribute in node.attributes { XMLNodes.detach(attribute) }
        for (key, value) in Dictionaries.entries(dictionary) {
            let attribute = XMLNodes.make(.attribute, name: Strings.value(of: key), value: Strings.value(of: value) ?? "")
            XMLNodes.addAttribute(attribute, to: objcObject)
            ObjC.release(attribute)
        }
    }

    @ObjCMethod("setAttributesAsDictionary:")
    func setAttributesAsDictionary(_ dictionary: UnsafeMutableRawPointer?) { setAttributes(dictionary: dictionary) }

    @ObjCMethod("namespaces")
    func namespaces() -> UnsafeMutableRawPointer? { node.namespaces.isEmpty ? nil : Arrays.autoreleased(node.namespaces) }

    @ObjCMethod("setNamespaces:")
    func setNamespaces(_ namespaces: UnsafeMutableRawPointer?) {
        for namespace in node.namespaces { XMLNodes.detach(namespace) }
        for namespace in Arrays.elements(namespaces) { XMLNodes.addNamespace(namespace, to: objcObject) }
    }

    @ObjCMethod("addNamespace:") func addNamespace(_ namespace: UnsafeMutableRawPointer?) { XMLNodes.addNamespace(namespace, to: objcObject) }

    @ObjCMethod("removeNamespaceForPrefix:")
    func removeNamespace(forPrefix prefix: String?) {
        if let namespace = node.namespaces.first(where: { (XMLNodes.state($0).name ?? "") == (prefix ?? "") }) { XMLNodes.detach(namespace) }
    }

    /// The namespace declared for a prefix here or above.
    @ObjCMethod("namespaceForPrefix:")
    func namespace(forPrefix prefix: String?) -> UnsafeMutableRawPointer? {
        var current: id? = objcObject
        while let each = current {
            let eachState = XMLNodes.state(each)
            if let found = eachState.namespaces.first(where: { (XMLNodes.state($0).name ?? "") == (prefix ?? "") }) { return found }
            current = eachState.parent
        }
        return nil
    }

    @ObjCMethod("resolveNamespaceForName:")
    func resolveNamespace(forName name: String?) -> UnsafeMutableRawPointer? { namespace(forPrefix: XMLNodes.prefix(name)) }

    @ObjCMethod("resolvePrefixForNamespaceURI:")
    func resolvePrefix(forNamespaceURI uri: String?) -> String? {
        var current: id? = objcObject
        while let each = current {
            let eachState = XMLNodes.state(each)
            if let found = eachState.namespaces.first(where: { XMLNodes.state($0).value == uri }) { return XMLNodes.state(found).name }
            current = eachState.parent
        }
        return nil
    }

    /// Joins neighboring text nodes into one, keeping CDATA ones apart
    /// when asked.
    @ObjCMethod("normalizeAdjacentTextNodesPreservingCDATA:")
    func normalizeAdjacentTextNodes(preservingCDATA: Bool) {
        var index = 0
        while index + 1 < node.children.count {
            let first = XMLNodes.state(node.children[index]), second = XMLNodes.state(node.children[index + 1])
            if first.kind == .text, second.kind == .text, !(preservingCDATA && (first.isCDATA || second.isCDATA)) {
                first.value += second.value
                XMLNodes.removeChild(of: objcObject, at: index + 1)
            } else {
                if first.kind == .element { NSXMLElement.objCInstance(node.children[index], ownership: .retain).normalizeAdjacentTextNodes(preservingCDATA: preservingCDATA) }
                index += 1
            }
        }
    }
}

// MARK: - NSXMLDocument

@ObjCClass("NSXMLDocument")
public class NSXMLDocument: NSXMLNode {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        XMLNodes.documentClass = cls.storage
    }

    /// Takes over a parsed document's state.
    private func adopt(_ result: Result<id, XMLParseError>, error: UnsafeMutablePointer<id?>?) -> Self? {
        switch result {
        case .failure(let failure):
            error?.pointee = failure.object
            return nil
        case .success(let document):
            defer { ObjC.release(document) }
            let parsed = XMLNodes.state(document)
            let state = XMLNodeState(.document)
            state.version = parsed.version
            state.characterEncoding = parsed.characterEncoding
            state.standalone = parsed.standalone
            Storage.set(objcObject, state)
            for child in parsed.children { XMLNodes.insertChild(child, into: objcObject, at: Int.max) }
            if let dtd = parsed.dtd {
                ObjC.retain(dtd)
                parsed.dtd = nil
                state.dtd = dtd
                XMLNodes.state(dtd).parent = objcObject
            }
            return self
        }
    }

    @ObjCMethod("initWithXMLString:options:error:")
    func initialize(xmlString: String?, options: UInt, error: UnsafeMutablePointer<id?>?) -> Self? {
        adopt(XMLNodes.parse(Data((xmlString ?? "").utf8), options: options), error: error)
    }

    @ObjCMethod("initWithData:options:error:")
    func initialize(data: UnsafeMutableRawPointer?, options: UInt, error: UnsafeMutablePointer<id?>?) -> Self? {
        adopt(XMLNodes.parse(DataObjects.data(data), options: options), error: error)
    }

    /// File URLs, read whole.
    @ObjCMethod("initWithContentsOfURL:options:error:")
    func initialize(contentsOf url: UnsafeMutableRawPointer?, options: UInt, error: UnsafeMutablePointer<id?>?) -> Self? {
        guard let location = URLs.url(url), location.isFileURL, let data = try? Data(contentsOf: location) else {
            error?.pointee = Errors.autoreleased(domain: Errors.cocoaDomain, code: 260, description: "The file couldn’t be opened because there is no such file.")
            return nil
        }
        return adopt(XMLNodes.parse(data, options: options), error: error)
    }

    @ObjCMethod("initWithRootElement:")
    func initialize(rootElement: UnsafeMutableRawPointer?) -> Self {
        Storage.set(objcObject, XMLNodeState(.document))
        XMLNodes.insertChild(rootElement, into: objcObject, at: 0)
        return self
    }

    @ObjCMethod("rootElement")
    func rootElement() -> UnsafeMutableRawPointer? { node.children.first { XMLNodes.state($0).kind == .element } }

    @ObjCMethod("setRootElement:")
    func setRootElement(_ element: UnsafeMutableRawPointer?) {
        XMLNodes.removeAllChildren(of: objcObject)
        XMLNodes.insertChild(element, into: objcObject, at: 0)
    }

    @ObjCMethod("version") func version() -> String? { node.version }
    @ObjCMethod("setVersion:") func setVersion(_ version: String?) { node.version = version }
    @ObjCMethod("characterEncoding") func characterEncoding() -> String? { node.characterEncoding }
    @ObjCMethod("setCharacterEncoding:") func setCharacterEncoding(_ encoding: String?) { node.characterEncoding = encoding }
    @ObjCMethod("isStandalone") func isStandalone() -> Bool { node.standalone }
    @ObjCMethod("setStandalone:") func setStandalone(_ standalone: Bool) { node.standalone = standalone }
    @ObjCMethod("documentContentKind") func documentContentKind() -> UInt { node.contentKind }
    @ObjCMethod("setDocumentContentKind:") func setDocumentContentKind(_ kind: UInt) { node.contentKind = kind }
    @ObjCMethod("MIMEType") func mimeType() -> String? { node.mimeType }
    @ObjCMethod("setMIMEType:") func setMIMEType(_ type: String?) { node.mimeType = type }

    @ObjCMethod("DTD") func dtd() -> UnsafeMutableRawPointer? { node.dtd }
    @ObjCMethod("setDTD:")
    func setDTD(_ dtd: UnsafeMutableRawPointer?) {
        if let old = node.dtd {
            XMLNodes.state(old).parent = nil
            ObjC.release(old)
        }
        node.dtd = dtd.map { ObjC.retain($0)! }
        if let dtd { XMLNodes.state(dtd).parent = objcObject }
    }

    @ObjCMethod("XMLData") func xmlData() -> UnsafeMutableRawPointer? { DataObjects.autoreleased(Data(XMLNodes.xml(objcObject, options: 0).utf8)) }
    @ObjCMethod("XMLDataWithOptions:")
    func xmlData(options: UInt) -> UnsafeMutableRawPointer? { DataObjects.autoreleased(Data(XMLNodes.xml(objcObject, options: options).utf8)) }

    @ObjCMethod("validateAndReturnError:") func validate(error: UnsafeMutablePointer<id?>?) -> Bool { true }
}

// MARK: - NSXMLDTD

@ObjCClass("NSXMLDTD")
public class NSXMLDTD: NSXMLNode {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        XMLNodes.dtdClass = cls.storage
    }

    @ObjCMethod("publicID") func publicID() -> String? { node.publicID }
    @ObjCMethod("setPublicID:") func setPublicID(_ id: String?) { node.publicID = id }
    @ObjCMethod("systemID") func systemID() -> String? { node.systemID }
    @ObjCMethod("setSystemID:") func setSystemID(_ id: String?) { node.systemID = id }
}
