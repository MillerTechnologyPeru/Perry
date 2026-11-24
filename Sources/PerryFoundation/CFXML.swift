import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

// CFXMLNode, CFXMLParser and CFXMLTree, the Mac's XML from before
// NSXMLParser, as Carbon-era programs use it. The parser is CoreFoundation's
// kind: non-validating, reading the document into nodes as Darwin's does
// (the XML declaration a processing instruction, whitespace and entity
// references nodes of their own, a DTD's declarations children of its
// document type), and telling the program of each through its callbacks.
// A tree is a CFTree whose context info is its node.

// MARK: - Nodes

/// What a node's info pointer points at, as CFXMLNode.h lays it out.
enum XMLNodeInfo: Equatable {
    case none
    case element(attributes: [(String, String)], isEmpty: Bool)
    case processingInstruction(data: String?)
    case document(url: String?, encoding: UInt32)
    case externalID(system: String?, public: String?)
    case elementDeclaration(content: String?)
    case attributeList([(name: String, type: String, value: String)])
    case entity(type: Int32, replacement: String?, system: String?, public: String?, notation: String?)
    case entityReference(type: Int32)

    static func == (a: XMLNodeInfo, b: XMLNodeInfo) -> Bool {
        switch (a, b) {
        case (.none, .none): true
        case let (.element(x, e), .element(y, f)): e == f && x.map { [$0.0, $0.1] } == y.map { [$0.0, $0.1] }
        case let (.processingInstruction(x), .processingInstruction(y)): x == y
        case let (.document(u, e), .document(v, f)): u == v && e == f
        case let (.externalID(s, p), .externalID(t, q)): s == t && p == q
        case let (.elementDeclaration(x), .elementDeclaration(y)): x == y
        case let (.attributeList(x), .attributeList(y)): x.map { [$0.name, $0.type, $0.value] } == y.map { [$0.name, $0.type, $0.value] }
        case let (.entity(t, r, s, p, n), .entity(u, q, v, w, m)): t == u && r == q && s == v && p == w && n == m
        case let (.entityReference(x), .entityReference(y)): x == y
        default: false
        }
    }
}

enum XMLNodeType {
    static let document = 1, element = 2, attribute = 3, processingInstruction = 4, comment = 5, text = 6
    static let cdata = 7, fragment = 8, entity = 9, entityReference = 10, documentType = 11, whitespace = 12
    static let notation = 13, elementDeclaration = 14, attributeListDeclaration = 15
}

final class XMLNodeStorage {
    let type: Int
    let string: String?
    let info: XMLNodeInfo
    let version: Int
    /// The info as C structs, and the objects they hold, retained.
    private(set) var infoPointer: UnsafeMutableRawPointer?
    private var held: [id] = []
    private var buffers: [UnsafeMutableRawPointer] = []
    /// The string as a CFString, for CFXMLNodeGetString.
    private(set) var stringObject: id?

    init(type: Int, string: String?, info: XMLNodeInfo, version: Int) {
        (self.type, self.string, self.info, self.version) = (type, string, info, version)
        stringObject = string.map(Strings.make)
        infoPointer = makeInfo()
    }

    deinit {
        held.forEach { ObjC.release($0) }
        if let stringObject { ObjC.release(stringObject) }
        buffers.forEach { $0.deallocate() }
    }

    private func buffer(words: Int) -> UnsafeMutableRawPointer {
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: max(words, 1) * DarwinLayout.word, alignment: 16)
        pointer.initializeMemory(as: UInt8.self, repeating: 0, count: max(words, 1) * DarwinLayout.word)
        buffers.append(pointer)
        return pointer
    }

    private func object(_ made: id?) -> id? {
        if let made { held.append(made) }
        return made
    }

    private func string(_ value: String?) -> id? { object(value.map(Strings.make)) }

    private func url(_ value: String?) -> id? {
        guard let value else { return nil }
        let text = Strings.make(value)
        defer { ObjC.release(text) }
        return object(CFURLCreateWithString(nil, text, nil))
    }

    private func store(_ value: id?, _ pointer: UnsafeMutableRawPointer, word: Int) {
        pointer.storeBytes(of: value, toByteOffset: word * DarwinLayout.word, as: id?.self)
    }

    private func makeInfo() -> UnsafeMutableRawPointer? {
        switch info {
        case .none:
            return nil
        case .element(let attributes, let isEmpty):
            // { attributes, attributeOrder, isEmpty, reserved[3] }
            let pointer = buffer(words: 3)
            let keys = attributes.map { Strings.autoreleased($0.0) }
            let entries = attributes.enumerated().map { (key: keys[$0.offset], value: Strings.autoreleased($0.element.1)) }
            store(object(Dictionaries.make(entries)), pointer, word: 0)
            store(object(Arrays.make(keys)), pointer, word: 1)
            pointer.storeBytes(of: isEmpty ? 1 : 0, toByteOffset: 2 * DarwinLayout.word, as: UInt8.self)
            return pointer
        case .processingInstruction(let data):
            let pointer = buffer(words: 1)
            store(string(data), pointer, word: 0)
            return pointer
        case .document(let source, let encoding):
            // { sourceURL, encoding }
            let pointer = buffer(words: 2)
            store(url(source), pointer, word: 0)
            pointer.storeBytes(of: encoding, toByteOffset: DarwinLayout.word, as: UInt32.self)
            return pointer
        case .externalID(let system, let publicID):
            let pointer = buffer(words: 2)
            store(url(system), pointer, word: 0)
            store(string(publicID), pointer, word: 1)
            return pointer
        case .elementDeclaration(let content):
            let pointer = buffer(words: 1)
            store(string(content), pointer, word: 0)
            return pointer
        case .attributeList(let attributes):
            // { numberOfAttributes, attributes }, each { name, type, default }.
            let pointer = buffer(words: 2)
            let list = buffer(words: 3 * attributes.count)
            for (index, attribute) in attributes.enumerated() {
                store(string(attribute.name), list, word: 3 * index)
                store(string(attribute.type), list, word: 3 * index + 1)
                store(string(attribute.value), list, word: 3 * index + 2)
            }
            pointer.storeBytes(of: attributes.count, as: Int.self)
            pointer.storeBytes(of: list, toByteOffset: DarwinLayout.word, as: UnsafeMutableRawPointer.self)
            return pointer
        case .entity(let type, let replacement, let system, let publicID, let notation):
            // { entityType, replacementText, entityID { systemID, publicID }, notationName }
            let pointer = buffer(words: 5)
            pointer.storeBytes(of: type, as: Int32.self)
            store(string(replacement), pointer, word: 1)
            store(url(system), pointer, word: 2)
            store(string(publicID), pointer, word: 3)
            store(string(notation), pointer, word: 4)
            return pointer
        case .entityReference(let type):
            let pointer = buffer(words: 1)
            pointer.storeBytes(of: type, as: Int32.self)
            return pointer
        }
    }

    /// A node's info from the program's C struct of its type.
    static func info(type: Int, from pointer: UnsafeRawPointer?) -> XMLNodeInfo {
        guard let pointer else {
            return type == XMLNodeType.element ? .element(attributes: [], isEmpty: false) : .none
        }
        func object(_ word: Int) -> id? { pointer.load(fromByteOffset: word * DarwinLayout.word, as: id?.self) }
        func text(_ word: Int) -> String? { Strings.value(of: object(word)) }
        func url(_ word: Int) -> String? { object(word).flatMap { CFURLGetString($0) }.flatMap { Strings.value(of: $0) } }
        switch type {
        case XMLNodeType.element:
            let order = Arrays.elements(object(1))
            let attributes = object(0)
            let pairs = order.map { key -> (String, String) in
                let value = ObjC.send(attributes, ObjC.selector("objectForKey:"), key)
                return (Strings.value(of: key) ?? "", Strings.value(of: value) ?? "")
            }
            return .element(attributes: pairs, isEmpty: pointer.load(fromByteOffset: 2 * DarwinLayout.word, as: UInt8.self) != 0)
        case XMLNodeType.processingInstruction: return .processingInstruction(data: text(0))
        case XMLNodeType.document: return .document(url: url(0), encoding: pointer.load(fromByteOffset: DarwinLayout.word, as: UInt32.self))
        case XMLNodeType.documentType, XMLNodeType.notation: return .externalID(system: url(0), public: text(1))
        case XMLNodeType.elementDeclaration: return .elementDeclaration(content: text(0))
        case XMLNodeType.attributeListDeclaration:
            let count = pointer.load(as: Int.self)
            guard count > 0, let list = pointer.load(fromByteOffset: DarwinLayout.word, as: UnsafeRawPointer?.self) else { return .attributeList([]) }
            return .attributeList((0..<count).map { index in
                func field(_ offset: Int) -> String {
                    Strings.value(of: list.load(fromByteOffset: (3 * index + offset) * DarwinLayout.word, as: id?.self)) ?? ""
                }
                return (field(0), field(1), field(2))
            })
        case XMLNodeType.entity:
            return .entity(type: pointer.load(as: Int32.self), replacement: text(1), system: url(2), public: text(3), notation: text(4))
        case XMLNodeType.entityReference: return .entityReference(type: pointer.load(as: Int32.self))
        default: return .none
        }
    }
}

enum CFXMLNodes {
    nonisolated(unsafe) static var nodeClass: Class!

    static func storage(_ node: id?) -> XMLNodeStorage? { Storage.get(node, as: XMLNodeStorage.self) }

    /// A new node (+1).
    static func make(_ storage: XMLNodeStorage) -> id? {
        guard let object = Storage.allocate(UnsafeMutableRawPointer(nodeClass)) else { return nil }
        Storage.set(object, storage)
        return object
    }
}

@ObjCClass("__NSCFXMLNode")
final class NSCFXMLNode: NSObject {
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        CFXMLNodes.nodeClass = cls.storage
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: CFXMLNodes.nodeClass)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { 59 }

    @ObjCMethod("isEqual:")
    func isEqual(_ other: UnsafeMutableRawPointer?) -> Bool {
        guard let mine = CFXMLNodes.storage(objcObject), let theirs = CFXMLNodes.storage(other) else { return false }
        return mine.type == theirs.type && mine.string == theirs.string && mine.info == theirs.info
    }

    @ObjCMethod("hash") func hash() -> UInt { UInt(bitPattern: (CFXMLNodes.storage(objcObject)?.string ?? "").hashValue) }
}

@c(_CFXMLNodeGetTypeID) public func CFXMLNodeGetTypeID() -> UInt { 59 }

@c(_CFXMLNodeCreate)
public func CFXMLNodeCreate(_ allocator: UnsafeRawPointer?, _ type: Int, _ string: id?, _ info: UnsafeRawPointer?, _ version: Int) -> id? {
    CFXMLNodes.make(XMLNodeStorage(type: type, string: Strings.value(of: string), info: XMLNodeStorage.info(type: type, from: info),
                                 version: version))
}

@c(_CFXMLNodeCreateCopy)
public func CFXMLNodeCreateCopy(_ allocator: UnsafeRawPointer?, _ node: id?) -> id? {
    guard let storage = CFXMLNodes.storage(node) else { return nil }
    return CFXMLNodes.make(XMLNodeStorage(type: storage.type, string: storage.string, info: storage.info, version: storage.version))
}

@c(_CFXMLNodeGetTypeCode) public func CFXMLNodeGetTypeCode(_ node: id?) -> Int { CFXMLNodes.storage(node)?.type ?? 0 }
@c(_CFXMLNodeGetString) public func CFXMLNodeGetString(_ node: id?) -> id? { CFXMLNodes.storage(node)?.stringObject }
@c(_CFXMLNodeGetInfoPtr) public func CFXMLNodeGetInfoPtr(_ node: id?) -> UnsafeMutableRawPointer? { CFXMLNodes.storage(node)?.infoPointer }
@c(_CFXMLNodeGetVersion) public func CFXMLNodeGetVersion(_ node: id?) -> Int { CFXMLNodes.storage(node)?.version ?? 0 }

// MARK: - Parsing

/// What the parser tells of the document as it reads it: a structure made
/// for each node (nil to skip the node and what's in it), a child added to
/// its parent's, a structure ended once its children are read, and an
/// error, which ends the parse.
struct XMLHandlers {
    var create: (id) -> UnsafeMutableRawPointer?
    var add: (UnsafeMutableRawPointer, UnsafeMutableRawPointer) -> Void
    var end: (UnsafeMutableRawPointer) -> Void
    var error: (Int) -> Void
}

/// kCFXMLParser's options, its status codes, and kCFStringEncodingUTF8.
enum XMLParsing {
    static let skipMetaData: UInt = 2, skipWhitespace: UInt = 8
    static let inProgress = -1, unexpectedEOF = 1, malformedProcessingInstruction = 4, malformedDTD = 5, malformedName = 6
    static let malformedCDATA = 7, malformedCloseTag = 8, malformedStartTag = 9, malformedDocument = 10, elementless = 11
    static let malformedComment = 12, malformedCharacterReference = 13, noData = 15
    static let utf8Encoding: UInt32 = 0x0800_0100
    static let parsedInternal: Int32 = 1, parsedExternal: Int32 = 2, unparsed: Int32 = 3, character: Int32 = 4, parameter: Int32 = 0
}

/// A non-validating XML reader, over the document's UTF-16, telling its
/// handlers of each node as CoreFoundation's parser does.
final class XMLReader {
    let units: [UInt16]
    let options: UInt
    let version: Int
    let sourceURL: String?
    var handlers: XMLHandlers
    var index = 0
    /// Where the last node told of ends: a location of the UTF-16 offset
    /// after it, plus one, and its line.
    var location = 1
    var line = 1
    var status = -2
    var errorDescription: String?
    var document: UnsafeMutableRawPointer?
    var aborted = false
    private var newlines: [Int] = []

    init(data: [UInt8], url: String?, options: UInt, version: Int, handlers: XMLHandlers) {
        if data.count >= 2, data[0] == 0xFE, data[1] == 0xFF {
            units = stride(from: 2, to: data.count - 1, by: 2).map { UInt16(data[$0]) << 8 | UInt16(data[$0 + 1]) }
        } else if data.count >= 2, data[0] == 0xFF, data[1] == 0xFE {
            units = stride(from: 2, to: data.count - 1, by: 2).map { UInt16(data[$0 + 1]) << 8 | UInt16(data[$0]) }
        } else {
            let bytes = data.starts(with: [0xEF, 0xBB, 0xBF]) ? Array(data.dropFirst(3)) : data
            units = Array(String(decoding: bytes, as: UTF8.self).utf16)
        }
        (self.sourceURL, self.options, self.version, self.handlers) = (url, options, version, handlers)
        newlines = units.indices.filter { units[$0] == 0x0A }
    }

    struct Failure: Error {
        let code: Int
        let description: String
    }

    // MARK: Reading

    private var atEnd: Bool { index >= units.count }
    private func peek(_ offset: Int = 0) -> UInt16? { index + offset < units.count ? units[index + offset] : nil }

    private func starts(with text: String) -> Bool {
        let pattern = Array(text.utf16)
        guard index + pattern.count <= units.count else { return false }
        return Array(units[index..<(index + pattern.count)]) == pattern
    }

    private static func isSpace(_ unit: UInt16) -> Bool { unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D }

    private static func isNameUnit(_ unit: UInt16) -> Bool {
        !(isSpace(unit) || [0x3C, 0x3E, 0x2F, 0x3D, 0x22, 0x27, 0x3B, 0x26, 0x3F, 0x21, 0x5B, 0x5D, 0x28, 0x29, 0x7C, 0x2C, 0x25].contains(unit))
    }

    private func skipSpace() { while let unit = peek(), Self.isSpace(unit) { index += 1 } }

    private func text(_ range: Range<Int>) -> String { String(decoding: units[range], as: UTF16.self) }

    private func name() throws -> String {
        let start = index
        while let unit = peek(), Self.isNameUnit(unit) { index += 1 }
        guard index > start else {
            throw atEnd ? Failure(code: XMLParsing.unexpectedEOF, description: "Encountered unexpected EOF while parsing name")
                : Failure(code: XMLParsing.malformedName, description: "Encountered malformed name")
        }
        return text(start..<index)
    }

    /// Text up to `terminator`, which is consumed.
    private func until(_ terminator: String, failure: Failure) throws -> String {
        let start = index
        while !atEnd, !starts(with: terminator) { index += 1 }
        guard !atEnd else { throw Failure(code: XMLParsing.unexpectedEOF, description: failure.description) }
        let found = text(start..<index)
        index += terminator.utf16.count
        return found
    }

    private func quoted() throws -> String {
        guard let quote = peek(), quote == 0x22 || quote == 0x27 else {
            throw Failure(code: XMLParsing.malformedDTD, description: "Encountered malformed quoted string")
        }
        index += 1
        let start = index
        while let unit = peek(), unit != quote { index += 1 }
        guard !atEnd else { throw Failure(code: XMLParsing.unexpectedEOF, description: "Encountered unexpected EOF while parsing a quoted string") }
        let value = text(start..<index)
        index += 1
        return value
    }

    /// The position, for a node ending here.
    private func mark() {
        location = index + 1
        var low = 0, high = newlines.count
        while low < high {
            let middle = (low + high) / 2
            if newlines[middle] < index { low = middle + 1 } else { high = middle }
        }
        line = low + 1
    }

    // MARK: Telling

    /// Tells of a node, under `parent`: its structure, nil when the program
    /// skips it.
    private func tell(_ type: Int, _ string: String?, _ info: XMLNodeInfo = .none,
                      under parent: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
        mark()
        guard let node = CFXMLNodes.make(XMLNodeStorage(type: type, string: string, info: info, version: version)) else { return nil }
        defer { ObjC.release(node) }
        guard let structure = handlers.create(node) else { return nil }
        if let parent { handlers.add(parent, structure) }
        return structure
    }

    /// A node with no children: told and ended.
    private func leaf(_ type: Int, _ string: String?, _ info: XMLNodeInfo = .none, under parent: UnsafeMutableRawPointer?) {
        if let structure = tell(type, string, info, under: parent) { handlers.end(structure) }
    }

    /// Whether this kind of node is to be told, by the options; the
    /// parent's structure is nil when it was skipped, and so are its
    /// children.
    private func telling(_ parent: UnsafeMutableRawPointer?, meta: Bool = false, whitespace: Bool = false) -> Bool {
        guard parent != nil, !aborted else { return false }
        if meta, options & XMLParsing.skipMetaData != 0 { return false }
        if whitespace, options & XMLParsing.skipWhitespace != 0 { return false }
        return true
    }

    // MARK: Parsing

    func parse() -> Bool {
        status = XMLParsing.inProgress
        guard !units.isEmpty else { return fail(Failure(code: XMLParsing.noData, description: "No data")) }
        mark()
        guard let node = CFXMLNodes.make(XMLNodeStorage(type: XMLNodeType.document, string: "",
                                                       info: .document(url: sourceURL, encoding: XMLParsing.utf8Encoding), version: version)) else { return false }
        document = handlers.create(node)
        ObjC.release(node)
        do {
            var sawElement = false
            while !atEnd, !aborted {
                if starts(with: "<?") {
                    try processingInstruction(under: document)
                } else if starts(with: "<!--") {
                    try comment(under: document)
                } else if starts(with: "<!DOCTYPE") {
                    try documentType(under: document)
                } else if starts(with: "<") {
                    guard !sawElement else { throw Failure(code: XMLParsing.malformedDocument, description: "Encountered a second root element") }
                    sawElement = true
                    try element(under: document)
                } else {
                    try characters(under: document, topLevel: true)
                }
            }
            if aborted { return false }
            guard sawElement else { throw Failure(code: XMLParsing.elementless, description: "Document has no root element") }
        } catch let failure as Failure {
            return fail(failure)
        } catch {
            return false
        }
        mark()
        return true
    }

    private func fail(_ failure: Failure) -> Bool {
        location = index + 1
        mark()
        status = failure.code
        errorDescription = failure.description
        handlers.error(failure.code)
        return false
    }

    private func processingInstruction(under parent: UnsafeMutableRawPointer?) throws {
        index += 2
        let target = try name()
        skipSpace()
        let data = try until("?>", failure: Failure(code: XMLParsing.malformedProcessingInstruction,
                                                    description: "Encountered unexpected EOF while parsing a processing instruction"))
        if telling(parent) { leaf(XMLNodeType.processingInstruction, target, .processingInstruction(data: data), under: parent) }
    }

    private func comment(under parent: UnsafeMutableRawPointer?) throws {
        index += 4
        let content = try until("-->", failure: Failure(code: XMLParsing.malformedComment, description: "Encountered unexpected EOF while parsing a comment"))
        if telling(parent, meta: true) { leaf(XMLNodeType.comment, content, under: parent) }
    }

    /// SYSTEM "uri", or PUBLIC "id" "uri".
    private func externalID() throws -> (system: String?, public: String?) {
        skipSpace()
        if starts(with: "SYSTEM") {
            index += 6
            skipSpace()
            return (try quoted(), nil)
        }
        if starts(with: "PUBLIC") {
            index += 6
            skipSpace()
            let publicID = try quoted()
            skipSpace()
            let system = peek() == 0x22 || peek() == 0x27 ? try quoted() : nil
            return (system, publicID)
        }
        return (nil, nil)
    }

    private func documentType(under parent: UnsafeMutableRawPointer?) throws {
        index += 9
        skipSpace()
        let root = try name()
        let id = try externalID()
        skipSpace()
        let hasSubset = peek() == 0x5B
        // Told where its internal subset, or its end, begins, as on Darwin.
        let structure = telling(parent, meta: true) ? tell(XMLNodeType.documentType, root, .externalID(system: id.system, public: id.public), under: parent) : nil
        if hasSubset { index += 1 }
        if hasSubset {
            while true {
                guard !atEnd else { throw Failure(code: XMLParsing.unexpectedEOF, description: "Encountered unexpected EOF while parsing DTD") }
                if peek() == 0x5D {
                    index += 1
                    break
                }
                try declaration(under: structure)
            }
            skipSpace()
        }
        guard peek() == 0x3E else { throw Failure(code: XMLParsing.malformedDTD, description: "Encountered malformed DTD") }
        index += 1
        if let structure { handlers.end(structure) }
    }

    /// A DTD's declaration, or the whitespace between them.
    private func declaration(under parent: UnsafeMutableRawPointer?) throws {
        if let unit = peek(), Self.isSpace(unit) {
            let start = index
            skipSpace()
            if telling(parent, whitespace: true) { leaf(XMLNodeType.whitespace, text(start..<index), under: parent) }
            return
        }
        if starts(with: "<!--") { return try comment(under: parent) }
        if starts(with: "<?") { return try processingInstruction(under: parent) }
        if starts(with: "<!ELEMENT") {
            index += 9
            skipSpace()
            let element = try name()
            skipSpace()
            let content = try until(">", failure: Failure(code: XMLParsing.malformedDTD, description: "Encountered malformed DTD"))
            if telling(parent) {
                leaf(XMLNodeType.elementDeclaration, element, .elementDeclaration(content: content.trimmingCharacters(in: .whitespacesAndNewlines)),
                     under: parent)
            }
            return
        }
        if starts(with: "<!ATTLIST") {
            index += 9
            skipSpace()
            let element = try name()
            var attributes: [(name: String, type: String, value: String)] = []
            while true {
                skipSpace()
                guard !atEnd else { throw Failure(code: XMLParsing.unexpectedEOF, description: "Encountered unexpected EOF while parsing DTD") }
                if peek() == 0x3E {
                    index += 1
                    break
                }
                let attribute = try name()
                skipSpace()
                let type: String
                if peek() == 0x28 {
                    let start = index
                    _ = try until(")", failure: Failure(code: XMLParsing.malformedDTD, description: "Encountered malformed DTD"))
                    type = text(start..<index)
                } else {
                    type = try name()
                }
                skipSpace()
                var value: String
                if peek() == 0x23 {
                    index += 1
                    value = "#" + (try name())
                    if value == "#FIXED" {
                        skipSpace()
                        value += " \"" + (try quoted()) + "\""
                    }
                } else {
                    value = "\"" + (try quoted()) + "\""
                }
                attributes.append((attribute, type, value))
            }
            if telling(parent) { leaf(XMLNodeType.attributeListDeclaration, element, .attributeList(attributes), under: parent) }
            return
        }
        if starts(with: "<!ENTITY") {
            index += 8
            skipSpace()
            var type = XMLParsing.parsedInternal
            if peek() == 0x25 {
                index += 1
                skipSpace()
                type = XMLParsing.parameter
            }
            let entity = try name()
            skipSpace()
            var replacement: String?, id: (system: String?, public: String?) = (nil, nil), notation: String?
            if peek() == 0x22 || peek() == 0x27 {
                replacement = try quoted()
            } else {
                id = try externalID()
                if type != XMLParsing.parameter { type = XMLParsing.parsedExternal }
                skipSpace()
                if starts(with: "NDATA") {
                    index += 5
                    skipSpace()
                    notation = try name()
                    type = XMLParsing.unparsed
                }
            }
            skipSpace()
            guard peek() == 0x3E else { throw Failure(code: XMLParsing.malformedDTD, description: "Encountered malformed DTD") }
            index += 1
            if telling(parent) {
                leaf(XMLNodeType.entity, entity, .entity(type: type, replacement: replacement, system: id.system, public: id.public, notation: notation),
                     under: parent)
            }
            return
        }
        if starts(with: "<!NOTATION") {
            index += 10
            skipSpace()
            let notation = try name()
            let id = try externalID()
            skipSpace()
            guard peek() == 0x3E else { throw Failure(code: XMLParsing.malformedDTD, description: "Encountered malformed DTD") }
            index += 1
            if telling(parent) { leaf(XMLNodeType.notation, notation, .externalID(system: id.system, public: id.public), under: parent) }
            return
        }
        throw Failure(code: XMLParsing.malformedDTD, description: "Encountered malformed DTD")
    }

    private func element(under parent: UnsafeMutableRawPointer?) throws {
        index += 1
        let tag = try name()
        var attributes: [(String, String)] = []
        var isEmpty = false
        while true {
            skipSpace()
            guard let unit = peek() else { throw Failure(code: XMLParsing.unexpectedEOF, description: "Encountered unexpected EOF while parsing start tag") }
            if unit == 0x3E {
                index += 1
                break
            }
            if unit == 0x2F, peek(1) == 0x3E {
                index += 2
                isEmpty = true
                break
            }
            let attribute = try name()
            skipSpace()
            guard peek() == 0x3D else { throw Failure(code: XMLParsing.malformedStartTag, description: "Encountered malformed start tag") }
            index += 1
            skipSpace()
            attributes.append((attribute, XMLEntities.unescape(try quoted(), entities: [:])))
        }
        let structure = telling(parent) ? tell(XMLNodeType.element, tag, .element(attributes: attributes, isEmpty: isEmpty), under: parent) : nil
        if !isEmpty {
            while true {
                guard !atEnd else { throw Failure(code: XMLParsing.unexpectedEOF, description: "Encountered unexpected EOF while parsing tag content") }
                if aborted { return }
                if starts(with: "</") {
                    index += 2
                    let closing = try name()
                    guard closing == tag else {
                        location = index + 1
                        throw Failure(code: XMLParsing.malformedCloseTag, description: "Encountered malformed close tag for <\(tag)>")
                    }
                    skipSpace()
                    guard peek() == 0x3E else { throw Failure(code: XMLParsing.malformedCloseTag, description: "Encountered malformed close tag for <\(tag)>") }
                    index += 1
                    break
                }
                if starts(with: "<!--") {
                    try comment(under: structure)
                } else if starts(with: "<![CDATA[") {
                    index += 9
                    let content = try until("]]>", failure: Failure(code: XMLParsing.malformedCDATA, description: "Encountered unexpected EOF while parsing CDATA section"))
                    if telling(structure) { leaf(XMLNodeType.cdata, content, under: structure) }
                } else if starts(with: "<?") {
                    try processingInstruction(under: structure)
                } else if starts(with: "<") {
                    try element(under: structure)
                } else {
                    try characters(under: structure, topLevel: false)
                }
            }
        }
        if let structure { handlers.end(structure) }
    }

    /// Text up to the next markup or entity reference, or an entity
    /// reference: a whitespace node when it's only whitespace.
    private func characters(under parent: UnsafeMutableRawPointer?, topLevel: Bool) throws {
        if peek() == 0x26 {
            index += 1
            let start = index
            while let unit = peek(), unit != 0x3B, Self.isNameUnit(unit) || unit == 0x23 { index += 1 }
            guard peek() == 0x3B, index > start else {
                throw Failure(code: XMLParsing.malformedCharacterReference, description: "Encountered malformed entity reference")
            }
            let reference = text(start..<index)
            index += 1
            let type = reference.hasPrefix("#") ? XMLParsing.character : XMLParsing.parsedInternal
            if telling(parent) { leaf(XMLNodeType.entityReference, reference, .entityReference(type: type), under: parent) }
            return
        }
        let start = index
        while let unit = peek(), unit != 0x3C, unit != 0x26 { index += 1 }
        let content = units[start..<index]
        if content.allSatisfy(Self.isSpace) {
            if telling(parent, whitespace: true) { leaf(XMLNodeType.whitespace, text(start..<index), under: parent) }
        } else if topLevel {
            throw Failure(code: XMLParsing.malformedDocument, description: "Encountered character data outside the root element")
        } else if telling(parent) {
            leaf(XMLNodeType.text, text(start..<index), under: parent)
        }
    }
}

// MARK: - The parser object

/// CFXMLParserCallBacks: { version, createXMLStructure, addChild,
/// endXMLStructure, resolveExternalEntity, handleError }.
struct XMLParserCallbacks {
    typealias Create = @convention(c) (id?, id?, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    typealias Add = @convention(c) (id?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
    typealias End = @convention(c) (id?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void
    typealias Resolve = @convention(c) (id?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> id?
    typealias HandleError = @convention(c) (id?, Int, UnsafeMutableRawPointer?) -> UInt8

    var version = 0
    var create: Create?
    var add: Add?
    var end: End?
    var resolve: Resolve?
    var handleError: HandleError?

    init(_ pointer: UnsafeRawPointer?) {
        guard let pointer else { return }
        version = pointer.load(as: Int.self)
        create = pointer.load(fromByteOffset: DarwinLayout.word, as: Create?.self)
        add = pointer.load(fromByteOffset: 2 * DarwinLayout.word, as: Add?.self)
        end = pointer.load(fromByteOffset: 3 * DarwinLayout.word, as: End?.self)
        resolve = pointer.load(fromByteOffset: 4 * DarwinLayout.word, as: Resolve?.self)
        handleError = pointer.load(fromByteOffset: 5 * DarwinLayout.word, as: HandleError?.self)
    }

    func store(to pointer: UnsafeMutableRawPointer?) {
        guard let pointer else { return }
        pointer.storeBytes(of: version, as: Int.self)
        pointer.storeBytes(of: create, toByteOffset: DarwinLayout.word, as: Create?.self)
        pointer.storeBytes(of: add, toByteOffset: 2 * DarwinLayout.word, as: Add?.self)
        pointer.storeBytes(of: end, toByteOffset: 3 * DarwinLayout.word, as: End?.self)
        pointer.storeBytes(of: resolve, toByteOffset: 4 * DarwinLayout.word, as: Resolve?.self)
        pointer.storeBytes(of: handleError, toByteOffset: 5 * DarwinLayout.word, as: HandleError?.self)
    }
}

final class XMLParserStorage {
    let reader: XMLReader
    let callbacks: XMLParserCallbacks
    let context: InfoContext
    let sourceURL: id?

    init(reader: XMLReader, callbacks: XMLParserCallbacks, context: InfoContext, sourceURL: id?) {
        (self.reader, self.callbacks, self.context) = (reader, callbacks, context)
        self.sourceURL = sourceURL.flatMap { ObjC.retain($0) }
    }

    deinit {
        context.released()
        if let sourceURL { ObjC.release(sourceURL) }
    }
}

enum CFXMLParsers {
    nonisolated(unsafe) static var parserClass: Class!

    static func storage(_ parser: id?) -> XMLParserStorage? { Storage.get(parser, as: XMLParserStorage.self) }

    static func bytes(_ data: id?) -> [UInt8] {
        guard let data, let pointer = CFDataGetBytePtr(data) else { return [] }
        return Array(UnsafeRawBufferPointer(start: pointer, count: CFDataGetLength(data)))
    }

    static func urlString(_ url: id?) -> String? { url.flatMap { CFURLGetString($0) }.flatMap { Strings.value(of: $0) } }

    /// A file URL's contents.
    static func contents(of url: id?) -> id? {
        var data: id?
        guard CFURLCreateDataAndPropertiesFromResource(nil, url, &data, nil, nil, nil) else { return nil }
        return data
    }
}

@ObjCClass("__NSCFXMLParser")
final class NSCFXMLParser: NSObject {
    override class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        CFXMLParsers.parserClass = cls.storage
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: CFXMLParsers.parserClass)
    }

    @ObjCMethod("_cfTypeID") func cfTypeID() -> UInt { 58 }
}

@c(_CFXMLParserGetTypeID) public func CFXMLParserGetTypeID() -> UInt { 58 }

@c(_CFXMLParserCreate)
public func CFXMLParserCreate(_ allocator: UnsafeRawPointer?, _ data: id?, _ url: id?, _ options: UInt, _ version: Int,
                              _ callbacks: UnsafeRawPointer?, _ context: UnsafeRawPointer?) -> id? {
    guard let data, let object = Storage.allocate(UnsafeMutableRawPointer(CFXMLParsers.parserClass)) else { return nil }
    let calls = XMLParserCallbacks(callbacks)
    let info = InfoContext(retaining: context)
    // The handlers call the program's callbacks with the parser and info.
    let parser = UInt(bitPattern: object)
    let handlers = XMLHandlers(
        create: { node in calls.create?(UnsafeMutableRawPointer(bitPattern: parser), node, info.info) },
        add: { parent, child in calls.add?(UnsafeMutableRawPointer(bitPattern: parser), parent, child, info.info) },
        end: { structure in calls.end?(UnsafeMutableRawPointer(bitPattern: parser), structure, info.info) },
        error: { code in _ = calls.handleError?(UnsafeMutableRawPointer(bitPattern: parser), code, info.info) }
    )
    let reader = XMLReader(data: CFXMLParsers.bytes(data), url: CFXMLParsers.urlString(url), options: options, version: version, handlers: handlers)
    Storage.set(object, XMLParserStorage(reader: reader, callbacks: calls, context: info, sourceURL: url))
    return object
}

@c(_CFXMLParserCreateWithDataFromURL)
public func CFXMLParserCreateWithDataFromURL(_ allocator: UnsafeRawPointer?, _ url: id?, _ options: UInt, _ version: Int,
                                             _ callbacks: UnsafeRawPointer?, _ context: UnsafeRawPointer?) -> id? {
    guard let data = CFXMLParsers.contents(of: url) else { return nil }
    defer { ObjC.release(data) }
    return CFXMLParserCreate(allocator, data, url, options, version, callbacks, context)
}

@c(_CFXMLParserGetContext)
public func CFXMLParserGetContext(_ parser: id?, _ context: UnsafeMutableRawPointer?) {
    CFXMLParsers.storage(parser)?.context.store(to: context)
}

@c(_CFXMLParserGetCallBacks)
public func CFXMLParserGetCallBacks(_ parser: id?, _ callbacks: UnsafeMutableRawPointer?) {
    CFXMLParsers.storage(parser)?.callbacks.store(to: callbacks)
}

@c(_CFXMLParserGetSourceURL) public func CFXMLParserGetSourceURL(_ parser: id?) -> id? { CFXMLParsers.storage(parser)?.sourceURL }
@c(_CFXMLParserGetLocation) public func CFXMLParserGetLocation(_ parser: id?) -> Int { CFXMLParsers.storage(parser)?.reader.location ?? 0 }
@c(_CFXMLParserGetLineNumber) public func CFXMLParserGetLineNumber(_ parser: id?) -> Int { CFXMLParsers.storage(parser)?.reader.line ?? 0 }
@c(_CFXMLParserGetDocument) public func CFXMLParserGetDocument(_ parser: id?) -> UnsafeMutableRawPointer? { CFXMLParsers.storage(parser)?.reader.document }

/// -2 before parsing, -1 while and, as on Darwin, after a parse that
/// succeeded, or the error.
@c(_CFXMLParserGetStatusCode) public func CFXMLParserGetStatusCode(_ parser: id?) -> Int { CFXMLParsers.storage(parser)?.reader.status ?? -2 }

@c(_CFXMLParserCopyErrorDescription)
public func CFXMLParserCopyErrorDescription(_ parser: id?) -> id? { CFXMLParsers.storage(parser)?.reader.errorDescription.map(Strings.make) }

@c(_CFXMLParserAbortParsing)
public func CFXMLParserAbortParsing(_ parser: id?) {
    guard let reader = CFXMLParsers.storage(parser)?.reader else { return }
    reader.aborted = true
    reader.errorDescription = reader.errorDescription ?? "Parsing aborted"
}

@c(_CFXMLParserParse) public func CFXMLParserParse(_ parser: id?) -> Bool { CFXMLParsers.storage(parser)?.reader.parse() ?? false }

// MARK: - Trees

enum XMLTrees {
    static let retain: InfoContext.Retain = { info in UnsafeRawPointer(ObjC.retain(UnsafeMutableRawPointer(mutating: info))) }
    static let release: InfoContext.Release = { info in ObjC.release(UnsafeMutableRawPointer(mutating: info)) }

    /// A tree (+1) whose context info is the node, retained.
    static func make(_ node: id?) -> id? {
        guard let node else { return nil }
        let context = UnsafeMutableRawPointer.allocate(byteCount: 5 * DarwinLayout.word, alignment: 16)
        defer { context.deallocate() }
        var info = InfoContext()
        (info.info, info.retain, info.release) = (node, retain, release)
        info.store(to: context)
        return CFTreeCreate(nil, context)
    }

    static func node(_ tree: id?) -> id? {
        let context = UnsafeMutableRawPointer.allocate(byteCount: 5 * DarwinLayout.word, alignment: 16)
        defer { context.deallocate() }
        context.initializeMemory(as: UInt8.self, repeating: 0, count: 5 * DarwinLayout.word)
        CFTreeGetContext(tree, context)
        return context.load(fromByteOffset: DarwinLayout.contextInfo, as: id?.self)
    }

    /// The document's tree (+1), or the failure.
    static func parse(_ data: id?, url: id?, options: UInt, version: Int) -> (tree: id?, reader: XMLReader) {
        var trees: [id] = []
        let handlers = XMLHandlers(
            create: { node in
                guard let tree = make(node) else { return nil }
                trees.append(tree)
                return tree
            },
            add: { parent, child in CFTreeAppendChild(parent, child) },
            end: { _ in },
            error: { _ in }
        )
        let reader = XMLReader(data: CFXMLParsers.bytes(data), url: CFXMLParsers.urlString(url), options: options, version: version, handlers: handlers)
        let parsed = reader.parse()
        // Each tree but the document's is kept by its parent now.
        let document = reader.document
        if parsed, let document { _ = ObjC.retain(document) }
        trees.forEach { ObjC.release($0) }
        return (parsed ? document : nil, reader)
    }

    // MARK: Writing

    static func write(_ tree: id?, into text: inout String) {
        guard let storage = CFXMLNodes.storage(node(tree)) else { return }
        var children: [id] = []
        for index in 0..<CFTreeGetChildCount(tree) { CFTreeGetChildAtIndex(tree, index).map { children.append($0) } }
        let name = storage.string ?? ""
        func writeChildren() { children.forEach { write($0, into: &text) } }
        func quoted(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: "\"", with: "&quot;") + "\"" }
        func external(_ system: String?, _ publicID: String?) -> String {
            if let publicID { return " PUBLIC \"\(publicID)\"" + (system.map { " \"\($0)\"" } ?? "") }
            return system.map { " SYSTEM \"\($0)\"" } ?? ""
        }
        switch (storage.type, storage.info) {
        case (XMLNodeType.document, _):
            writeChildren()
        case (XMLNodeType.element, .element(let attributes, let isEmpty)):
            text += "<" + name + attributes.map { " \($0.0)=" + quoted($0.1) }.joined()
            if isEmpty {
                // As on Darwin, an empty element's children follow it.
                text += "/>"
                writeChildren()
            } else {
                text += ">"
                writeChildren()
                text += "</\(name)>"
            }
        case (XMLNodeType.processingInstruction, .processingInstruction(let data)):
            text += "<?\(name)" + (data.map { $0.isEmpty ? "" : " " + $0 } ?? "") + "?>"
        case (XMLNodeType.comment, _): text += "<!--\(name)-->"
        case (XMLNodeType.text, _), (XMLNodeType.whitespace, _): text += name
        case (XMLNodeType.cdata, _): text += "<![CDATA[\(name)]]>"
        case (XMLNodeType.entityReference, _): text += "&\(name);"
        case (XMLNodeType.documentType, .externalID(let system, let publicID)):
            text += "<!DOCTYPE \(name)" + external(system, publicID)
            if !children.isEmpty {
                text += " ["
                writeChildren()
                text += "]"
            }
            text += ">"
        case (XMLNodeType.elementDeclaration, .elementDeclaration(let content)): text += "<!ELEMENT \(name) \(content ?? "ANY")>"
        case (XMLNodeType.attributeListDeclaration, .attributeList(let attributes)):
            text += "<!ATTLIST \(name)" + attributes.map { " \($0.name) \($0.type) \($0.value)" }.joined() + ">"
        case (XMLNodeType.entity, .entity(let type, let replacement, let system, let publicID, let notation)):
            text += "<!ENTITY " + (type == XMLParsing.parameter ? "% " : "") + name
            text += replacement.map { " \"\($0)\"" } ?? external(system, publicID)
            text += (notation.map { " NDATA \($0)" } ?? "") + ">"
        case (XMLNodeType.notation, .externalID(let system, let publicID)): text += "<!NOTATION \(name)" + external(system, publicID) + ">"
        default: writeChildren()
        }
    }
}

@c(_CFXMLTreeCreateWithNode) public func CFXMLTreeCreateWithNode(_ allocator: UnsafeRawPointer?, _ node: id?) -> id? { XMLTrees.make(node) }

@c(_CFXMLTreeGetNode) public func CFXMLTreeGetNode(_ tree: id?) -> id? { XMLTrees.node(tree) }

@c(_CFXMLTreeCreateFromData)
public func CFXMLTreeCreateFromData(_ allocator: UnsafeRawPointer?, _ data: id?, _ url: id?, _ options: UInt, _ version: Int) -> id? {
    XMLTrees.parse(data, url: url, options: options, version: version).tree
}

/// As CFXMLTreeCreateFromData, the failure described in a new dictionary
/// of the kCFXMLTreeError keys.
@c(_CFXMLTreeCreateFromDataWithError)
public func CFXMLTreeCreateFromDataWithError(_ allocator: UnsafeRawPointer?, _ data: id?, _ url: id?, _ options: UInt, _ version: Int,
                                             _ error: UnsafeMutablePointer<id?>?) -> id? {
    let (tree, reader) = XMLTrees.parse(data, url: url, options: options, version: version)
    if tree == nil, let error {
        let entries: [(key: id, value: id)] = [
            (Strings.autoreleased("kCFXMLTreeErrorDescription"), Strings.autoreleased(reader.errorDescription ?? "")),
            (Strings.autoreleased("kCFXMLTreeErrorLineNumber"), Numbers.make(nil, .signed(Int64(reader.line)))!),
            (Strings.autoreleased("kCFXMLTreeErrorLocation"), Numbers.make(nil, .signed(Int64(reader.location)))!),
            (Strings.autoreleased("kCFXMLTreeErrorStatusCode"), Numbers.make(nil, .signed(Int64(reader.status)))!),
        ]
        error.pointee = Dictionaries.make(entries)
    }
    return tree
}

@c(_CFXMLTreeCreateWithDataFromURL)
public func CFXMLTreeCreateWithDataFromURL(_ allocator: UnsafeRawPointer?, _ url: id?, _ options: UInt, _ version: Int) -> id? {
    guard let data = CFXMLParsers.contents(of: url) else { return nil }
    defer { ObjC.release(data) }
    return CFXMLTreeCreateFromData(allocator, data, url, options, version)
}

/// The tree written as XML, in UTF-8 (+1).
@c(_CFXMLTreeCreateXMLData)
public func CFXMLTreeCreateXMLData(_ allocator: UnsafeRawPointer?, _ tree: id?) -> id? {
    var text = ""
    XMLTrees.write(tree, into: &text)
    return ObjC.retain(DataObjects.autoreleased(Data(text.utf8)))
}

/// The keys of CFXMLTreeCreateFromDataWithError's dictionary.
@ObjCConstants
enum XMLTreeErrorKeys {
    static let kCFXMLTreeErrorDescription = "kCFXMLTreeErrorDescription"
    static let kCFXMLTreeErrorLineNumber = "kCFXMLTreeErrorLineNumber"
    static let kCFXMLTreeErrorLocation = "kCFXMLTreeErrorLocation"
    static let kCFXMLTreeErrorStatusCode = "kCFXMLTreeErrorStatusCode"
}

// MARK: - Entities

enum XMLEntities {
    static let predefined: [(String, String)] = [("&", "amp"), ("<", "lt"), (">", "gt"), ("\"", "quot"), ("'", "apos")]

    /// Predefined entities, character references, and the entities given,
    /// replaced; an unknown one is left as it is.
    static func unescape(_ text: String, entities: [String: String]) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var rest = Substring(text)
        while let ampersand = rest.firstIndex(of: "&") {
            result += rest[..<ampersand]
            guard let semicolon = rest[ampersand...].firstIndex(of: ";") else {
                result += rest[ampersand...]
                return result
            }
            let name = String(rest[rest.index(after: ampersand)..<semicolon])
            var replacement: String?
            if name.hasPrefix("#x") || name.hasPrefix("#X") {
                replacement = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else if name.hasPrefix("#") {
                replacement = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                replacement = predefined.first { $0.1 == name }?.0 ?? entities[name]
            }
            result += replacement ?? String(rest[ampersand...semicolon])
            rest = rest[rest.index(after: semicolon)...]
        }
        return result + rest
    }

    static func escape(_ text: String, entities: [String: String]) -> String {
        var result = ""
        for character in text {
            if let entity = predefined.first(where: { $0.0 == String(character) }) {
                result += "&\(entity.1);"
            } else {
                result.append(character)
            }
        }
        for (name, value) in entities where !value.isEmpty {
            result = result.replacingOccurrences(of: value, with: "&\(name);")
        }
        return result
    }

    static func dictionary(_ object: id?) -> [String: String] {
        var entities: [String: String] = [:]
        for (key, value) in Dictionaries.entries(object) {
            if let name = Strings.value(of: key), let text = Strings.value(of: value) { entities[name] = text }
        }
        return entities
    }
}

@c(_CFXMLCreateStringByEscapingEntities)
public func CFXMLCreateStringByEscapingEntities(_ allocator: UnsafeRawPointer?, _ string: id?, _ entities: id?) -> id? {
    guard let text = Strings.value(of: string) else { return nil }
    return Strings.make(XMLEntities.escape(text, entities: XMLEntities.dictionary(entities)))
}

@c(_CFXMLCreateStringByUnescapingEntities)
public func CFXMLCreateStringByUnescapingEntities(_ allocator: UnsafeRawPointer?, _ string: id?, _ entities: id?) -> id? {
    guard let text = Strings.value(of: string) else { return nil }
    return Strings.make(XMLEntities.unescape(text, entities: XMLEntities.dictionary(entities)))
}
