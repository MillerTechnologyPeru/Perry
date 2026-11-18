import Glibc

// NeXTSTEP's typedstream: NSArchiver's format, which Interface Builder
// wrote nibs in ("objects.nib") before keyed archives. A stream is a
// header, then groups of values, each group led by its Objective-C type
// encoding ("i", "@@", "{_NSPoint=ff}", "[36c]"). An object is its class
// chain (each class with the version it was archived at, leaf first), then
// the groups its -encodeWithCoder: wrote, superclass first, then an end
// marker. Objects, classes and C strings are numbered as they first appear,
// in one table, and later appear by number; strings (type encodings, class
// names, selectors) are shared through a table of their own.
//
// The stream is self-describing: it reads without knowing the classes.
// What the values of each class mean is LegacyNib's business.

enum TypedStream {
    /// An archived object: its classes, leaf first, with their versions,
    /// and every value its classes wrote, in order.
    final class Object {
        let number: Int
        var classes: [(name: String, version: Int)] = []
        var values: [Value] = []

        init(number: Int) { self.number = number }

        var className: String { classes.first?.name ?? "" }
    }

    indirect enum Value {
        case integer(Int64)
        case real(Double)
        /// Raw bytes: an unshared string ("+"), or an array of chars.
        case bytes([UInt8])
        /// A C string, selector or atom.
        case string(String?)
        case object(Object?)
        case objectClass(String?)
        case array([Value])
        case structure([Value])
        case none

        var integer: Int64? {
            switch self {
            case .integer(let value): value
            case .real(let value): Int64(value)
            default: nil
            }
        }

        var real: Double? {
            switch self {
            case .integer(let value): Double(value)
            case .real(let value): value
            default: nil
            }
        }

        var object: Object? {
            if case .object(let object) = self { return object }
            return nil
        }
    }

    /// Whether the bytes are a typedstream.
    static func matches(_ bytes: [UInt8]) -> Bool {
        guard bytes.count > 13, bytes[0] == 4, bytes[1] == 11 else { return false }
        let signature = String(decoding: bytes[2..<13], as: UTF8.self)
        return signature == "typedstream" || signature == "streamtyped"
    }

    /// The stream's top-level values, in order; nil if it isn't one or is
    /// cut short.
    static func values(_ bytes: [UInt8]) -> [Value]? {
        guard matches(bytes) else { return nil }
        let reader = Reader(bytes)
        return reader.top()
    }
}

/// Reads a typedstream: the header, then values until the end.
private final class Reader {
    // Tags: the head bytes that aren't small integers.
    static let integer2: Int8 = -127, integer4: Int8 = -126, floating: Int8 = -125
    static let new: Int8 = -124, null: Int8 = -123, endOfObject: Int8 = -122
    /// References are numbered from here, just above the tags.
    static let firstReference = -110

    enum Shared {
        case object(TypedStream.Object)
        case classChain([(name: String, version: Int)])
        case cString(String)
    }

    let bytes: [UInt8]
    var position: Int
    let bigEndian: Bool
    var strings: [[UInt8]] = []
    var shared: [Shared] = []
    var failed = false

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
        bigEndian = String(decoding: bytes[2..<13], as: UTF8.self) == "typedstream"
        position = 13
    }

    func top() -> [TypedStream.Value]? {
        // The system version the stream was written on.
        guard let versionHead = head(), integer(versionHead, signed: false) != nil else { return nil }
        var values: [TypedStream.Value] = []
        while position < bytes.count, !failed {
            guard let groupHead = head(), let group = group(groupHead) else { return nil }
            values += group
        }
        return failed ? nil : values
    }

    // MARK: Bytes

    func take(_ count: Int) -> ArraySlice<UInt8>? {
        guard count >= 0, position + count <= bytes.count else {
            failed = true
            return nil
        }
        defer { position += count }
        return bytes[position..<position + count]
    }

    func head() -> Int8? { take(1).map { Int8(bitPattern: $0.first!) } }

    func word(_ count: Int) -> UInt64? {
        guard let raw = take(count) else { return nil }
        let ordered = bigEndian ? Array(raw) : raw.reversed()
        return ordered.reduce(0) { $0 << 8 | UInt64($1) }
    }

    // MARK: Primitives

    func integer(_ head: Int8, signed: Bool) -> Int64? {
        switch head {
        case Self.integer2:
            guard let raw = word(2) else { return nil }
            return signed ? Int64(Int16(truncatingIfNeeded: raw)) : Int64(raw)
        case Self.integer4:
            guard let raw = word(4) else { return nil }
            return signed ? Int64(Int32(truncatingIfNeeded: raw)) : Int64(raw)
        case -128 ... -111:
            failed = true
            return nil
        default:
            return signed ? Int64(head) : Int64(UInt8(bitPattern: head))
        }
    }

    func real(_ head: Int8, double: Bool) -> Double? {
        guard head == Self.floating else { return integer(head, signed: true).map(Double.init) }
        guard let raw = word(double ? 8 : 4) else { return nil }
        return double ? Double(bitPattern: raw) : Double(Float(bitPattern: UInt32(raw)))
    }

    func unshared(_ head: Int8) -> [UInt8]?? {
        if head == Self.null { return .some(nil) }
        guard let count = integer(head, signed: false), let raw = take(Int(count)) else { return nil }
        return .some(Array(raw))
    }

    /// A string from the shared table: new, or by number.
    func sharedString(_ head: Int8) -> [UInt8]?? {
        switch head {
        case Self.null:
            return .some(nil)
        case Self.new:
            guard let next = self.head(), case .some(let string?) = unshared(next) else {
                failed = true
                return nil
            }
            strings.append(string)
            return .some(string)
        default:
            guard let number = integer(head, signed: true) else { return nil }
            let index = Int(number) - Self.firstReference
            guard strings.indices.contains(index) else {
                failed = true
                return nil
            }
            return .some(strings[index])
        }
    }

    func reference(_ head: Int8) -> Shared? {
        guard let number = integer(head, signed: true) else { return nil }
        let index = Int(number) - Self.firstReference
        guard shared.indices.contains(index) else {
            failed = true
            return nil
        }
        return shared[index]
    }

    /// A class chain, leaf first: new classes with their versions, ended
    /// by nil or by a class read before.
    func classChain(_ first: Int8) -> [(name: String, version: Int)]? {
        var head = first
        var literal: [(name: String, version: Int)] = []
        while head == Self.new {
            guard let nameHead = self.head(), case .some(let name?) = sharedString(nameHead),
                  let versionHead = self.head(), let version = integer(versionHead, signed: true), let next = self.head() else {
                failed = true
                return nil
            }
            literal.append((String(decoding: name, as: UTF8.self), Int(version)))
            head = next
        }
        var rest: [(name: String, version: Int)] = []
        if head != Self.null {
            guard case .classChain(let chain)? = reference(head) else {
                failed = true
                return nil
            }
            rest = chain
        }
        let full = literal + rest
        for index in literal.indices { shared.append(.classChain(Array(full[index...]))) }
        return full
    }

    func object(_ head: Int8) -> TypedStream.Value? {
        switch head {
        case Self.null:
            return .object(nil)
        case Self.new:
            let object = TypedStream.Object(number: shared.count)
            shared.append(.object(object))
            guard let classHead = self.head(), let chain = classChain(classHead) else { return nil }
            object.classes = chain
            while true {
                guard let next = self.head() else { return nil }
                if next == Self.endOfObject { break }
                guard let group = group(next) else { return nil }
                object.values += group
            }
            return .object(object)
        default:
            guard case .object(let object)? = reference(head) else {
                failed = true
                return nil
            }
            return .object(object)
        }
    }

    // MARK: Typed values

    /// A group: its type encoding, then a value of each type in it.
    func group(_ head: Int8) -> [TypedStream.Value]? {
        guard case .some(let encoding?) = sharedString(head), !encoding.isEmpty else {
            failed = true
            return nil
        }
        var values: [TypedStream.Value] = []
        for type in TypeEncoding.split(String(decoding: encoding, as: UTF8.self)) {
            guard let value = value(type) else { return nil }
            values.append(value)
        }
        return values
    }

    func value(_ type: Substring) -> TypedStream.Value? {
        guard let kind = type.first else { return nil }
        switch kind {
        case "B", "c":
            return take(1).map { .integer(Int64(Int8(bitPattern: $0.first!))) }
        case "C":
            return take(1).map { .integer(Int64($0.first!)) }
        case "S", "I", "L", "Q":
            return head().flatMap { integer($0, signed: false) }.map { .integer($0) }
        case "s", "i", "l", "q":
            return head().flatMap { integer($0, signed: true) }.map { .integer($0) }
        case "f", "d":
            return head().flatMap { real($0, double: kind == "d") }.map { .real($0) }
        case "*":
            guard let head = head() else { return nil }
            switch head {
            case Self.null:
                return .string(nil)
            case Self.new:
                guard let next = self.head(), case .some(let raw?) = sharedString(next) else { return nil }
                let string = String(decoding: raw, as: UTF8.self)
                shared.append(.cString(string))
                return .string(string)
            default:
                guard case .cString(let string)? = reference(head) else {
                    failed = true
                    return nil
                }
                return .string(string)
            }
        case "%", ":":
            guard let head = head(), case .some(let raw) = sharedString(head) else { return nil }
            return .string(raw.map { String(decoding: $0, as: UTF8.self) })
        case "+":
            guard let head = head(), case .some(let raw) = unshared(head) else { return nil }
            return .bytes(raw ?? [])
        case "#":
            guard let head = head() else { return nil }
            if head == Self.null { return .objectClass(nil) }
            if head == Self.new { return classChain(head).map { .objectClass($0.first?.name) } }
            guard case .classChain(let chain)? = reference(head) else {
                failed = true
                return nil
            }
            return .objectClass(chain.first?.name)
        case "@":
            return head().flatMap(object)
        case "!":
            return TypedStream.Value.none
        case "[":
            guard let (count, element) = TypeEncoding.array(type) else {
                failed = true
                return nil
            }
            if element == "c" || element == "C" { return take(count).map { .bytes(Array($0)) } }
            var elements: [TypedStream.Value] = []
            for _ in 0..<count {
                guard let item = value(element) else { return nil }
                elements.append(item)
            }
            return .array(elements)
        case "{":
            var fields: [TypedStream.Value] = []
            for field in TypeEncoding.fields(type) {
                guard let item = value(field) else { return nil }
                fields.append(item)
            }
            return .structure(fields)
        default:
            failed = true
            return nil
        }
    }
}

/// Objective-C type encodings, as typedstream groups give them.
enum TypeEncoding {
    /// The end of the type that starts at `start`.
    static func end(_ encoding: Substring, from start: Substring.Index) -> Substring.Index {
        var index = start
        guard index < encoding.endIndex else { return index }
        switch encoding[index] {
        case "[":
            index = encoding.index(after: index)
            while index < encoding.endIndex, encoding[index].isNumber { index = encoding.index(after: index) }
            index = end(encoding, from: index)
            return index < encoding.endIndex ? encoding.index(after: index) : index
        case "{", "(":
            var depth = 0
            while index < encoding.endIndex {
                let character = encoding[index]
                if character == "{" || character == "(" { depth += 1 }
                if character == "}" || character == ")" {
                    depth -= 1
                    if depth == 0 { return encoding.index(after: index) }
                }
                index = encoding.index(after: index)
            }
            return index
        case "^":
            return end(encoding, from: encoding.index(after: index))
        default:
            return encoding.index(after: index)
        }
    }

    static func split(_ encoding: String) -> [Substring] { split(Substring(encoding)) }

    static func split(_ encoding: Substring) -> [Substring] {
        var types: [Substring] = []
        var index = encoding.startIndex
        while index < encoding.endIndex {
            let next = end(encoding, from: index)
            guard next > index else { break }
            types.append(encoding[index..<next])
            index = next
        }
        return types
    }

    /// An array type's count and element type: "[36c]" is 36 and "c".
    static func array(_ type: Substring) -> (Int, Substring)? {
        let body = type.dropFirst().dropLast()
        let digits = body.prefix { $0.isNumber }
        guard let count = Int(digits) else { return nil }
        return (count, body.dropFirst(digits.count))
    }

    /// A structure's field types: "{_NSPoint=ff}" has "f" and "f".
    static func fields(_ type: Substring) -> [Substring] {
        var body = type.dropFirst().dropLast()
        if let equals = body.firstIndex(of: "=") { body = body[body.index(after: equals)...] }
        return split(body)
    }
}
