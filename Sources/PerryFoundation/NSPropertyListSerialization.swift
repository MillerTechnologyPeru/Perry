import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

// Property lists in CoreFoundation's three formats: XML as CF writes it
// (tab indentation, sorted keys, base64 data in 76-column lines, UTC
// dates), binary (bplist00) and OpenStep, which is read only. Values are
// ArchiveValue trees, which also carry keyed archives' UIDs.

enum PropertyLists {
    enum Kind { case dictionary, array }

    /// The property list in a file, when it is of `kind`; mutable
    /// throughout when `cls` is NSMutableDictionary or NSMutableArray or a
    /// subclass.
    static func contents(of url: URL, _ cls: ObjCClass, expecting kind: Kind) -> UnsafeMutableRawPointer? {
        guard url.isFileURL, let bytes = try? Data(contentsOf: url), let (value, _) = parse(Array(bytes)) else { return nil }
        switch (value, kind) {
        case (.dictionary, .dictionary), (.array, .array): break
        default: return nil
        }
        let mutableName = kind == .dictionary ? "NSMutableDictionary" : "NSMutableArray"
        var mutable = false
        var current: ObjCClass? = cls
        while let candidate = current {
            if candidate.pointer == ObjCClass(named: mutableName).pointer { mutable = true }
            current = candidate.superclass
        }
        return object(value, mutability: mutable ? 1 : 0)
    }

    static let openStep: UInt = 1, xml: UInt = 100, binary: UInt = 200

    /// Writes a collection to a file URL as an XML property list, as
    /// -writeToFile:atomically: does; false if it holds a value a property
    /// list cannot.
    static func write(_ object: id?, to url: URL, atomically: Bool) -> Bool {
        guard url.isFileURL, let value = value(object) else { return false }
        return (try? Data(xml(value).utf8).write(to: url, options: atomically ? .atomic : [])) != nil
    }

    // MARK: Objects

    /// An object as a property list value; nil if it is not one (NSNull,
    /// a non-string key, another class).
    static func value(_ object: id?) -> ArchiveValue? {
        guard let object else { return nil }
        if let string = Strings.value(of: object) { return .string(string) }
        if ObjC.isKind(object, of: Numbers.numberClass) {
            let number = Numbers.storage(object)
            switch number.value {
            case .bool(let flag): return .bool(flag)
            case .double(let real): return .real(real)
            case .signed, .unsigned: return .integer(number.int64)
            }
        }
        if ObjC.isKind(object, of: Dates.dateClass) { return .date(Dates.interval(object)) }
        if ObjC.isKind(object, of: DataObjects.dataClass) { return .data(Array(DataObjects.data(object))) }
        if ObjC.isKind(object, of: Arrays.arrayClass) {
            var values: [ArchiveValue] = []
            for element in Arrays.elements(object) {
                guard let value = value(element) else { return nil }
                values.append(value)
            }
            return .array(values)
        }
        if ObjC.isKind(object, of: Dictionaries.dictionaryClass) {
            var entries: [String: ArchiveValue] = [:]
            for entry in Dictionaries.entries(object) {
                guard let key = Strings.value(of: entry.key), let value = value(entry.value) else { return nil }
                entries[key] = value
            }
            return .dictionary(entries)
        }
        return nil
    }

    /// NSPropertyListMutabilityOptions: mutable containers (1), and leaves (2).
    static func object(_ value: ArchiveValue, mutability: UInt) -> id? {
        let containers = mutability != 0, leaves = mutability == 2
        switch value {
        case .null: return nil
        case .bool(let flag): return perry_foundation_boolean(flag ? 1 : 0)
        case .integer(let number): return Numbers.make(nil, .signed(number))
        case .real(let number): return Numbers.make(nil, .double(number))
        case .date(let seconds): return Dates.autoreleased(seconds)
        case .data(let bytes):
            let data = DataObjects.autoreleased(Data(bytes))
            return leaves ? ObjC.autorelease(ObjC.send(data, ObjC.selector("mutableCopy"))) : data
        case .string(let text): return leaves ? ObjC.autorelease(MutableStrings.make(text)) : Strings.autoreleased(text)
        case .uid(let index):
            return Dictionaries.autoreleased([(key: Strings.autoreleased("CF$UID"), value: Numbers.make(nil, .signed(Int64(index)))!)])
        case .array(let values):
            return Arrays.autoreleased(values.compactMap { object($0, mutability: mutability) },
                                       cls: containers ? UnsafeMutableRawPointer(Arrays.mutableClass) : nil)
        case .dictionary(let entries):
            let pairs = entries.sorted { $0.key < $1.key }.compactMap { key, value in
                object(value, mutability: mutability).map { (key: Strings.autoreleased(key), value: $0) }
            }
            return Dictionaries.autoreleased(pairs, cls: containers ? UnsafeMutableRawPointer(Dictionaries.mutableClass) : nil)
        }
    }

    // MARK: XML

    static func escape(_ text: String) -> String {
        var output = ""
        for character in text {
            switch character {
            case "&": output += "&amp;"
            case "<": output += "&lt;"
            case ">": output += "&gt;"
            default: output.append(character)
            }
        }
        return output
    }

    /// Reals as CF writes them: %.17g, "0.0" for zero.
    static func real(_ value: Double) -> String {
        if value == 0 { return "0.0" }
        if value.isNaN { return "nan" }
        if value.isInfinite { return value < 0 ? "-infinity" : "+infinity" }
        var buffer = [CChar](repeating: 0, count: 64)
        _ = withVaList([value]) { vsnprintf(&buffer, buffer.count, "%.17g", $0) }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    static func iso8601(_ seconds: Double) -> String {
        var time = time_t(seconds + 978307200)
        var parts = tm()
        gmtime_r(&time, &parts)
        func two(_ n: Int32) -> String { n < 10 ? "0\(n)" : "\(n)" }
        return "\(parts.tm_year + 1900)-\(two(parts.tm_mon + 1))-\(two(parts.tm_mday))T"
            + "\(two(parts.tm_hour)):\(two(parts.tm_min)):\(two(parts.tm_sec))Z"
    }

    static func xml(_ value: ArchiveValue) -> String {
        var output = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            + "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
            + "<plist version=\"1.0\">\n"
        append(value, depth: 0, to: &output)
        output += "</plist>\n"
        return output
    }

    private static func append(_ value: ArchiveValue, depth: Int, to output: inout String) {
        let indent = String(repeating: "\t", count: depth)
        switch value {
        case .null: break
        case .bool(let flag): output += indent + (flag ? "<true/>" : "<false/>") + "\n"
        case .integer(let number): output += indent + "<integer>\(number)</integer>\n"
        case .real(let number): output += indent + "<real>\(real(number))</real>\n"
        case .date(let seconds): output += indent + "<date>\(iso8601(seconds))</date>\n"
        case .string(let text): output += indent + "<string>\(escape(text))</string>\n"
        case .data(let bytes):
            output += indent + "<data>\n"
            let encoded = Data(bytes).base64EncodedString()
            var start = encoded.startIndex
            while start < encoded.endIndex {
                let end = encoded.index(start, offsetBy: 76, limitedBy: encoded.endIndex) ?? encoded.endIndex
                output += indent + encoded[start..<end] + "\n"
                start = end
            }
            output += indent + "</data>\n"
        case .uid(let index):
            append(.dictionary(["CF$UID": .integer(Int64(index))]), depth: depth, to: &output)
        case .array(let values):
            guard !values.isEmpty else { return output += indent + "<array/>\n" }
            output += indent + "<array>\n"
            values.forEach { append($0, depth: depth + 1, to: &output) }
            output += indent + "</array>\n"
        case .dictionary(let entries):
            guard !entries.isEmpty else { return output += indent + "<dict/>\n" }
            output += indent + "<dict>\n"
            for (key, entry) in entries.sorted(by: { $0.key < $1.key }) {
                output += indent + "\t<key>\(escape(key))</key>\n"
                append(entry, depth: depth + 1, to: &output)
            }
            output += indent + "</dict>\n"
        }
    }

    /// Reads an XML property list.
    static func parseXML(_ bytes: [UInt8]) -> ArchiveValue? {
        // In UTF-16 after a byte order mark (as Xcode writes some strings
        // files), else UTF-8.
        var parser = XMLPlistParser(Array(PropertyLists.text(bytes).unicodeScalars))
        return parser.document()
    }

    // MARK: Binary

    static func binary(_ value: ArchiveValue) -> [UInt8] {
        var objects: [[UInt8]] = []
        var references: [[Int]] = []
        // Objects in depth-first order, each listing its children.
        func add(_ value: ArchiveValue) -> Int {
            let index = objects.count
            objects.append([])
            references.append([])
            switch value {
            case .array(let values):
                let children = values.map(add)
                references[index] = children
                objects[index] = header(0xA, children.count)
            case .dictionary(let entries):
                let sorted = entries.sorted { $0.key < $1.key }
                let keys = sorted.map { add(.string($0.key)) }
                let values = sorted.map { add($0.value) }
                references[index] = keys + values
                objects[index] = header(0xD, sorted.count)
            default:
                objects[index] = scalar(value)
            }
            return index
        }
        let top = add(value)
        let referenceSize = byteCount(objects.count)
        var output = Array("bplist00".utf8)
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(output.count)
            output += object
            for reference in references[index] { output += bigEndian(reference, referenceSize) }
        }
        let tableOffset = output.count
        let offsetSize = byteCount(tableOffset)
        for offset in offsets { output += bigEndian(offset, offsetSize) }
        output += [0, 0, 0, 0, 0, 0, UInt8(offsetSize), UInt8(referenceSize)]
        output += bigEndian(objects.count, 8) + bigEndian(top, 8) + bigEndian(tableOffset, 8)
        return output
    }

    private static func byteCount(_ value: Int) -> Int { value < 1 << 8 ? 1 : value < 1 << 16 ? 2 : value < 1 << 32 ? 4 : 8 }

    private static func bigEndian(_ value: Int, _ size: Int) -> [UInt8] {
        (0..<size).reversed().map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
    }

    private static func header(_ kind: UInt8, _ count: Int) -> [UInt8] {
        if count < 15 { return [kind << 4 | UInt8(count)] }
        return [kind << 4 | 0x0f] + integer(Int64(count))
    }

    private static func integer(_ value: Int64) -> [UInt8] {
        if value < 0 { return [0x13] + bigEndian(Int(value), 8) }
        let size = value < 1 << 8 ? 0 : value < 1 << 16 ? 1 : value < 1 << 32 ? 2 : 3
        return [0x10 | UInt8(size)] + bigEndian(Int(value), 1 << size)
    }

    private static func scalar(_ value: ArchiveValue) -> [UInt8] {
        switch value {
        case .null: return [0x00]
        case .bool(let flag): return [flag ? 0x09 : 0x08]
        case .integer(let number): return integer(number)
        case .real(let number): return [0x23] + bigEndian(Int(Int64(bitPattern: number.bitPattern)), 8)
        case .date(let seconds): return [0x33] + bigEndian(Int(Int64(bitPattern: seconds.bitPattern)), 8)
        case .data(let bytes): return header(0x4, bytes.count) + bytes
        case .string(let text):
            if text.utf8.allSatisfy({ $0 < 0x80 }) { return header(0x5, text.utf8.count) + Array(text.utf8) }
            let units = Array(text.utf16)
            return header(0x6, units.count) + units.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xff)] }
        case .uid(let index):
            let size = byteCount(index)
            return [0x80 | UInt8(size - 1)] + bigEndian(index, size)
        case .array, .dictionary: return []
        }
    }

    // MARK: Any format

    /// The value and its format.
    static func parse(_ bytes: [UInt8]) -> (ArchiveValue, UInt)? {
        if let list = BinaryPropertyList(bytes) { return (list.value(list.top), binary) }
        let text = PropertyLists.text(bytes)
        let trimmed = text.drop { $0.isWhitespace || $0 == "\u{FEFF}" }
        if trimmed.hasPrefix("<?xml") || trimmed.hasPrefix("<!DOCTYPE") || trimmed.hasPrefix("<plist") {
            return parseXML(bytes).map { ($0, xml) }
        }
        var parser = OpenStepParser(Array(text.unicodeScalars))
        if let value = parser.document() { return (value, openStep) }
        var strings = OpenStepParser(Array(text.unicodeScalars))
        return strings.stringsDocument().map { ($0, openStep) }
    }

    /// Text in a property list's encoding: UTF-16 after its byte order
    /// mark, else UTF-8 (after any mark).
    static func text(_ bytes: [UInt8]) -> String {
        if bytes.count >= 2, (bytes[0], bytes[1]) == (0xFF, 0xFE) || (bytes[0], bytes[1]) == (0xFE, 0xFF) {
            let little = bytes[0] == 0xFF
            let units = stride(from: 2, to: bytes.count - 1, by: 2).map {
                little ? UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8 : UInt16(bytes[$0]) << 8 | UInt16(bytes[$0 + 1])
            }
            return String(decoding: units, as: UTF16.self)
        }
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { return String(decoding: bytes.dropFirst(3), as: UTF8.self) }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// A strings file's table, in any format: binary or XML property lists
    /// as Xcode compiles them, or the text format, `"key" = "value";`.
    static func stringsTable(_ bytes: [UInt8]) -> [String: String]? {
        guard let (value, _) = parse(bytes), case .dictionary(let entries) = value else { return nil }
        return entries.compactMapValues {
            if case .string(let text) = $0 { return text }
            return nil
        }
    }
}

// MARK: - XML reading

struct XMLPlistParser {
    let scalars: [Unicode.Scalar]
    var index = 0

    init(_ scalars: [Unicode.Scalar]) {
        self.scalars = scalars
    }

    private mutating func skipSpace() {
        while index < scalars.count, scalars[index].properties.isWhitespace { index += 1 }
    }

    /// Skips the declaration, doctype and comments.
    private mutating func skipMarkup() {
        while true {
            skipSpace()
            if starts("<?") { skip(past: "?>") } else if starts("<!--") { skip(past: "-->") }
            else if starts("<!") { skip(past: ">") } else { return }
        }
    }

    private func starts(_ text: String) -> Bool {
        let wanted = Array(text.unicodeScalars)
        return index + wanted.count <= scalars.count && Array(scalars[index..<index + wanted.count]) == wanted
    }

    private mutating func skip(past text: String) {
        while index < scalars.count, !starts(text) { index += 1 }
        index = min(scalars.count, index + text.unicodeScalars.count)
    }

    /// The next tag: its name and whether it closes itself ("<true/>").
    private mutating func tag() -> (name: String, closing: Bool, empty: Bool)? {
        skipMarkup()
        guard index < scalars.count, scalars[index] == "<" else { return nil }
        index += 1
        let closing = index < scalars.count && scalars[index] == "/"
        if closing { index += 1 }
        var name = ""
        while index < scalars.count, scalars[index] != ">", scalars[index] != "/", !scalars[index].properties.isWhitespace {
            name.unicodeScalars.append(scalars[index])
            index += 1
        }
        while index < scalars.count, scalars[index] != ">" && scalars[index] != "/" { index += 1 }
        let empty = index < scalars.count && scalars[index] == "/"
        if empty { index += 1 }
        guard index < scalars.count, scalars[index] == ">" else { return nil }
        index += 1
        return (name, closing, empty)
    }

    private mutating func text(until name: String) -> String? {
        var raw = ""
        while index < scalars.count, scalars[index] != "<" {
            raw.unicodeScalars.append(scalars[index])
            index += 1
        }
        guard let close = tag(), close.closing, close.name == name else { return nil }
        return XMLPlistParser.unescape(raw)
    }

    static func unescape(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var output = ""
        var rest = Substring(text)
        while let amp = rest.firstIndex(of: "&") {
            output += rest[..<amp]
            guard let semicolon = rest[amp...].firstIndex(of: ";") else { break }
            let entity = rest[rest.index(after: amp)..<semicolon]
            switch entity {
            case "amp": output += "&"
            case "lt": output += "<"
            case "gt": output += ">"
            case "quot": output += "\""
            case "apos": output += "'"
            default:
                let number = entity.hasPrefix("#x") ? UInt32(entity.dropFirst(2), radix: 16)
                    : entity.hasPrefix("#") ? UInt32(entity.dropFirst()) : nil
                if let scalar = number.flatMap(Unicode.Scalar.init) { output.unicodeScalars.append(scalar) }
            }
            rest = rest[rest.index(after: semicolon)...]
        }
        return output + rest
    }

    mutating func document() -> ArchiveValue? {
        guard let open = tag(), open.name == "plist", !open.closing else { return nil }
        if open.empty { return .dictionary([:]) }
        guard let value = value() else { return nil }
        guard let close = tag(), close.closing, close.name == "plist" else { return nil }
        return value
    }

    private mutating func value() -> ArchiveValue? {
        guard let open = tag(), !open.closing else { return nil }
        switch open.name {
        case "true": return open.empty ? .bool(true) : (text(until: "true") != nil ? .bool(true) : nil)
        case "false": return open.empty ? .bool(false) : (text(until: "false") != nil ? .bool(false) : nil)
        case "string": return open.empty ? .string("") : text(until: "string").map { .string($0) }
        case "integer":
            guard let text = text(until: "integer").map({ String($0.filter { !$0.isWhitespace }) }) else { return nil }
            return Int64(text).map { .integer($0) } ?? UInt64(text).map { .integer(Int64(bitPattern: $0)) }
        case "real":
            guard let text = text(until: "real").map({ String($0.filter { !$0.isWhitespace }) }) else { return nil }
            switch text {
            case "nan": return .real(.nan)
            case "+infinity", "infinity": return .real(.infinity)
            case "-infinity": return .real(-.infinity)
            default: return Double(text).map { .real($0) }
            }
        case "date":
            guard let text = text(until: "date") else { return nil }
            return XMLPlistParser.date(text).map { .date($0) }
        case "data":
            guard let text = open.empty ? "" : text(until: "data") else { return nil }
            let compact = text.filter { !$0.isWhitespace }
            return Data(base64Encoded: compact).map { .data(Array($0)) }
        case "array":
            if open.empty { return .array([]) }
            var values: [ArchiveValue] = []
            while true {
                let mark = index
                if let close = tag(), close.closing, close.name == "array" { return .array(values) }
                index = mark
                guard let value = value() else { return nil }
                values.append(value)
            }
        case "dict":
            if open.empty { return .dictionary([:]) }
            var entries: [String: ArchiveValue] = [:]
            while true {
                guard let key = tag() else { return nil }
                if key.closing && key.name == "dict" { break }
                guard key.name == "key", !key.closing, let name = key.empty ? "" : text(until: "key"),
                      let value = value() else { return nil }
                entries[name] = value
            }
            if entries.count == 1, case .integer(let uid)? = entries["CF$UID"] { return .uid(Int(uid)) }
            return .dictionary(entries)
        default:
            return nil
        }
    }

    /// "2024-03-10T06:30:15Z", as seconds since 2001.
    static func date(_ text: String) -> Double? {
        let digits = text.split { !$0.isNumber }.compactMap { Int32($0) }
        guard digits.count >= 6 else { return nil }
        var parts = tm()
        parts.tm_year = digits[0] - 1900
        parts.tm_mon = digits[1] - 1
        parts.tm_mday = digits[2]
        parts.tm_hour = digits[3]
        parts.tm_min = digits[4]
        parts.tm_sec = digits[5]
        return Double(timegm(&parts)) - 978307200
    }
}

// MARK: - OpenStep reading

struct OpenStepParser {
    let scalars: [Unicode.Scalar]
    var index = 0

    init(_ scalars: [Unicode.Scalar]) {
        self.scalars = scalars
    }

    private mutating func skipSpace() {
        while index < scalars.count {
            if scalars[index].properties.isWhitespace { index += 1; continue }
            if index + 1 < scalars.count, scalars[index] == "/", scalars[index + 1] == "/" {
                while index < scalars.count, scalars[index] != "\n" { index += 1 }
                continue
            }
            if index + 1 < scalars.count, scalars[index] == "/", scalars[index + 1] == "*" {
                index += 2
                while index + 1 < scalars.count, !(scalars[index] == "*" && scalars[index + 1] == "/") { index += 1 }
                index += 2
                continue
            }
            return
        }
    }

    private mutating func expect(_ scalar: Unicode.Scalar) -> Bool {
        skipSpace()
        guard index < scalars.count, scalars[index] == scalar else { return false }
        index += 1
        return true
    }

    mutating func document() -> ArchiveValue? {
        guard let value = value() else { return nil }
        skipSpace()
        return index == scalars.count ? value : nil
    }

    /// The strings file format: a dictionary's entries without its braces,
    /// where `key;` maps the key to itself.
    mutating func stringsDocument() -> ArchiveValue? {
        var entries: [String: ArchiveValue] = [:]
        while true {
            skipSpace()
            if index == scalars.count { return .dictionary(entries) }
            guard case .string(let key)? = value() else { return nil }
            if expect(";") {
                entries[key] = .string(key)
                continue
            }
            guard expect("="), let value = value(), expect(";") else { return nil }
            entries[key] = value
        }
    }

    /// The scalar for a backslash escape's character, the backslash just
    /// read: C's escapes, \Uxxxx (and \uxxxx) in hex, and \ooo in octal.
    private mutating func escape() -> Unicode.Scalar? {
        let scalar = scalars[index]
        func digits(_ limit: Int, radix: UInt32) -> UInt32? {
            var value: UInt32 = 0, count = 0
            while count < limit, index + 1 < scalars.count,
                  let digit = Character(scalars[index + 1]).hexDigitValue, UInt32(digit) < radix {
                value = value * radix + UInt32(digit)
                index += 1
                count += 1
            }
            return count > 0 ? value : nil
        }
        switch scalar {
        case "n": return "\n"
        case "t": return "\t"
        case "r": return "\r"
        case "a": return "\u{07}"
        case "b": return "\u{08}"
        case "f": return "\u{0C}"
        case "v": return "\u{0B}"
        case "U", "u":
            guard let value = digits(4, radix: 16) else { return scalar }
            return Unicode.Scalar(value) ?? "\u{FFFD}"
        case "0"..."7":
            index -= 1
            guard let value = digits(3, radix: 8) else { return scalar }
            return Unicode.Scalar(value) ?? "\u{FFFD}"
        default: return scalar
        }
    }

    private static func isUnquoted(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isAlphabetic || ("0"..."9").contains(scalar) || "_$+/:.-".unicodeScalars.contains(scalar)
    }

    private mutating func value() -> ArchiveValue? {
        skipSpace()
        guard index < scalars.count else { return nil }
        switch scalars[index] {
        case "{":
            index += 1
            var entries: [String: ArchiveValue] = [:]
            while true {
                skipSpace()
                if expect("}") { return .dictionary(entries) }
                guard case .string(let key)? = value(), expect("="), let value = value(), expect(";") else { return nil }
                entries[key] = value
            }
        case "(":
            index += 1
            var values: [ArchiveValue] = []
            if expect(")") { return .array([]) }
            while true {
                guard let value = value() else { return nil }
                values.append(value)
                if expect(")") { return .array(values) }
                guard expect(",") else { return nil }
                if expect(")") { return .array(values) }
            }
        case "<":
            index += 1
            var hex = ""
            while index < scalars.count, scalars[index] != ">" {
                if !scalars[index].properties.isWhitespace { hex.unicodeScalars.append(scalars[index]) }
                index += 1
            }
            guard expect(">"), hex.count % 2 == 0 else { return nil }
            var bytes: [UInt8] = []
            var cursor = hex.startIndex
            while cursor < hex.endIndex {
                let next = hex.index(cursor, offsetBy: 2)
                guard let byte = UInt8(hex[cursor..<next], radix: 16) else { return nil }
                bytes.append(byte)
                cursor = next
            }
            return .data(bytes)
        case "\"":
            index += 1
            var text = ""
            while index < scalars.count, scalars[index] != "\"" {
                if scalars[index] == "\\", index + 1 < scalars.count {
                    index += 1
                    if let scalar = escape() { text.unicodeScalars.append(scalar) }
                } else {
                    text.unicodeScalars.append(scalars[index])
                }
                index += 1
            }
            guard index < scalars.count else { return nil }
            index += 1
            return .string(text)
        default:
            var text = ""
            while index < scalars.count, OpenStepParser.isUnquoted(scalars[index]) {
                text.unicodeScalars.append(scalars[index])
                index += 1
            }
            return text.isEmpty ? nil : .string(text)
        }
    }
}

// MARK: - NSPropertyListSerialization

/// NSPropertyListSerialization.
@ObjCClass("NSPropertyListSerialization")
public final class NSPropertyListSerialization: NSObject {
    static func error(_ code: Int, _ description: String) -> id? {
        ObjC.autorelease(Errors.make(domain: Errors.cocoaDomain, code: code, entries: [
            ("NSDebugDescription", Strings.autoreleased(description))]))
    }

    @ObjCClassMethod("dataWithPropertyList:format:options:error:")
    static func data(with plist: ObjCObject?, format: UInt, options: UInt,
                     error: UnsafeMutablePointer<id?>?) -> UnsafeMutableRawPointer? {
        guard let value = PropertyLists.value(plist?.id), format != PropertyLists.openStep else {
            error?.pointee = Self.error(3851, "Property list invalid for format: \(format)")
            return nil
        }
        let bytes = format == PropertyLists.binary ? PropertyLists.binary(value) : Array(PropertyLists.xml(value).utf8)
        return DataObjects.autoreleased(Data(bytes))
    }

    @ObjCClassMethod("propertyListWithData:options:format:error:")
    static func propertyList(with data: ObjCObject?, options: UInt, format: UnsafeMutablePointer<UInt>?,
                             error: UnsafeMutablePointer<id?>?) -> UnsafeMutableRawPointer? {
        guard let (value, kind) = PropertyLists.parse(Array(DataObjects.data(data?.id))) else {
            error?.pointee = Self.error(3840, "The data couldn’t be read because it isn’t in the correct format.")
            return nil
        }
        format?.pointee = kind
        return PropertyLists.object(value, mutability: options)
    }

    @ObjCClassMethod("propertyList:isValidForFormat:")
    static func isValid(_ plist: ObjCObject?, for format: UInt) -> Bool {
        format != PropertyLists.openStep && PropertyLists.value(plist?.id) != nil
    }

    @ObjCClassMethod("dataFromPropertyList:format:errorDescription:")
    static func data(from plist: ObjCObject?, format: UInt, errorDescription: UnsafeMutablePointer<id?>?) -> UnsafeMutableRawPointer? {
        data(with: plist, format: format, options: 0, error: nil)
    }

    @ObjCClassMethod("propertyListFromData:mutabilityOption:format:errorDescription:")
    static func propertyList(from data: ObjCObject?, mutability: UInt, format: UnsafeMutablePointer<UInt>?,
                             errorDescription: UnsafeMutablePointer<id?>?) -> UnsafeMutableRawPointer? {
        propertyList(with: data, options: mutability, format: format, error: nil)
    }
}

// MARK: - NSKeyedArchiver

final class ArchiverStorage {
    var objects: [ArchiveValue] = [.string("$null")]
    /// The next key for unkeyed coding: "$0", "$1", and so on.
    var unkeyed = 0
    var top: [String: ArchiveValue] = [:]
    /// The fields of the objects being encoded, innermost last.
    var fields: [[String: ArchiveValue]] = []
    var uids: [UnsafeMutableRawPointer: Int] = [:]
    var classUIDs: [[String]: Int] = [:]
    var requiresSecureCoding: Bool
    var format = PropertyLists.binary
    var encoded: id?
    var output: id?     // initForWritingWithMutableData:'s data
    var failure: id?

    init(requiresSecureCoding: Bool) {
        self.requiresSecureCoding = requiresSecureCoding
    }

    deinit {
        ObjC.release(encoded)
        ObjC.release(output)
        ObjC.release(failure)
    }

    func set(_ key: String, _ value: ArchiveValue) {
        if fields.isEmpty { top[key] = value } else { fields[fields.count - 1][key] = value }
    }

    func classUID(_ names: [String]) -> Int {
        if let uid = classUIDs[names] { return uid }
        objects.append(.dictionary(["$classes": .array(names.map { .string($0) }), "$classname": .string(names[0])]))
        classUIDs[names] = objects.count - 1
        return objects.count - 1
    }

    var archive: ArchiveValue {
        .dictionary(["$archiver": .string("NSKeyedArchiver"), "$objects": .array(objects), "$top": .dictionary(top),
                     "$version": .integer(100000)])
    }
}

enum Archivers {
    nonisolated(unsafe) static var archiverClass: Class!

    static func storage(_ object: id?) -> ArchiverStorage? { Storage.get(object, as: ArchiverStorage.self) }

    /// A class and its superclasses' names.
    static func hierarchy(_ cls: Class) -> [String] {
        var names: [String] = []
        var current: Class? = cls
        while let c = current {
            names.append(ObjC.className(UnsafeMutableRawPointer(c)))
            current = c.pointee.superclass
        }
        return names
    }

    /// Encodes an object, returning its UID.
    static func encode(_ object: id?, in archiver: id, storage: ArchiverStorage) -> ArchiveValue {
        guard let object else { return .uid(0) }
        if let uid = storage.uids[object] { return .uid(uid) }
        // Plain values sit in $objects as themselves.
        let plain: ArchiveValue?
        if ObjC.isKind(object, of: Numbers.numberClass) {
            plain = PropertyLists.value(object)
        } else if let text = Strings.value(of: object), !ObjC.isKind(object, of: MutableStrings.mutableClass) {
            plain = .string(text)
        } else if ObjC.isKind(object, of: DataObjects.dataClass), !ObjC.isKind(object, of: DataObjects.mutableClass) {
            plain = .data(Array(DataObjects.data(object)))
        } else {
            plain = nil
        }
        if let plain {
            storage.objects.append(plain)
            storage.uids[object] = storage.objects.count - 1
            return .uid(storage.objects.count - 1)
        }
        let index = storage.objects.count
        storage.objects.append(.null)
        storage.uids[object] = index
        storage.fields.append([:])
        let names = contents(object, in: archiver, storage: storage)
        var fields = storage.fields.removeLast()
        fields["$class"] = .uid(storage.classUID(names))
        storage.objects[index] = .dictionary(fields)
        return .uid(index)
    }

    /// Encodes an object's contents into the current fields; its class
    /// names.
    private static func contents(_ object: id, in archiver: id, storage: ArchiverStorage) -> [String] {
        func references(_ list: [id]) -> ArchiveValue { .array(list.map { encode($0, in: archiver, storage: storage) }) }
        if ObjC.isKind(object, of: MutableStrings.mutableClass) {
            storage.set("NS.string", .string(Strings.value(of: object) ?? ""))
            return ["NSMutableString", "NSString", "NSObject"]
        }
        if ObjC.isKind(object, of: DataObjects.mutableClass) {
            storage.set("NS.data", .data(Array(DataObjects.data(object))))
            return ["NSMutableData", "NSData", "NSObject"]
        }
        if ObjC.isKind(object, of: Arrays.arrayClass) {
            storage.set("NS.objects", references(Arrays.elements(object)))
            return ObjC.isKind(object, of: Arrays.mutableClass) ? ["NSMutableArray", "NSArray", "NSObject"] : ["NSArray", "NSObject"]
        }
        if ObjC.isKind(object, of: Sets.setClass) {
            storage.set("NS.objects", references(Sets.elements(object)))
            return ObjC.isKind(object, of: Sets.mutableClass) ? ["NSMutableSet", "NSSet", "NSObject"] : ["NSSet", "NSObject"]
        }
        if ObjC.isKind(object, of: Dictionaries.dictionaryClass) {
            let entries = Dictionaries.entries(object)
            storage.set("NS.keys", references(entries.map(\.key)))
            storage.set("NS.objects", references(entries.map(\.value)))
            return ObjC.isKind(object, of: Dictionaries.mutableClass)
                ? ["NSMutableDictionary", "NSDictionary", "NSObject"] : ["NSDictionary", "NSObject"]
        }
        if ObjC.isKind(object, of: Dates.dateClass) {
            storage.set("NS.time", .real(Dates.interval(object)))
            return ["NSDate", "NSObject"]
        }
        if ObjC.isKind(object, of: URLs.urlClass) {
            storage.set("NS.base", .uid(0))
            storage.set("NS.relative", encode(Strings.autoreleased(URLs.url(object)?.absoluteString ?? ""), in: archiver, storage: storage))
            return ["NSURL", "NSObject"]
        }
        if ObjC.isKind(object, of: UUIDs.uuidClass), let uuid = UUIDs.uuid(object) {
            storage.set("NS.uuidbytes", .data(withUnsafeBytes(of: uuid.uuid) { Array($0) }))
            return ["NSUUID", "NSObject"]
        }
        if object == Nulls.null { return ["NSNull", "NSObject"] }
        // An app's class encodes itself.
        let cls = ObjC.objectGetClass(object)!
        if storage.requiresSecureCoding,
           !ObjC.sendBool(UnsafeMutableRawPointer(cls), ObjC.selector("respondsToSelector:"),
                          UnsafeMutableRawPointer(mutating: ObjC.selector("supportsSecureCoding")))
            || !ObjC.sendBool(UnsafeMutableRawPointer(cls), ObjC.selector("supportsSecureCoding"), nil) {
            if storage.failure == nil {
                storage.failure = ObjC.retain(Errors.make(domain: Errors.cocoaDomain, code: 4866, entries: [
                    ("NSDebugDescription", Strings.autoreleased("This coder requires that classes conform to NSSecureCoding"))]))
            }
        }
        _ = ObjC.send(object, ObjC.selector("encodeWithCoder:"), archiver)
        return hierarchy(cls)
    }

    /// The archive's bytes in the archiver's format.
    static func finish(_ storage: ArchiverStorage) -> id {
        if let encoded = storage.encoded { return encoded }
        let bytes = storage.format == PropertyLists.xml ? Array(PropertyLists.xml(storage.archive).utf8)
                                                        : PropertyLists.binary(storage.archive)
        let data = DataObjects.autoreleased(Data(bytes))!
        storage.encoded = ObjC.retain(data)
        if let output = storage.output { _ = ObjC.send(output, ObjC.selector("setData:"), data) }
        return data
    }
}

/// NSKeyedArchiver.
@ObjCClass("NSKeyedArchiver")
public class NSKeyedArchiver: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
        Archivers.archiverClass = cls.storage
    }

    var storage: ArchiverStorage {
        if let storage = Archivers.storage(objcObject) { return storage }
        let storage = ArchiverStorage(requiresSecureCoding: true)
        Storage.set(objcObject, storage)
        return storage
    }

    @ObjCMethod("dealloc")
    func dealloc() {
        Storage.set(objcObject, nil)
        ObjC.superDealloc(objcObject, from: Archivers.archiverClass)
    }

    @ObjCMethod("init")
    func initialize() -> Self {
        Storage.set(objcObject, ArchiverStorage(requiresSecureCoding: true))
        return self
    }

    @ObjCMethod("initRequiringSecureCoding:")
    func initialize(requiringSecureCoding secure: Bool) -> Self {
        Storage.set(objcObject, ArchiverStorage(requiresSecureCoding: secure))
        return self
    }

    @ObjCMethod("initForWritingWithMutableData:")
    func initialize(mutableData: ObjCObject) -> Self {
        let storage = ArchiverStorage(requiresSecureCoding: false)
        storage.output = ObjC.retain(mutableData.id)
        Storage.set(objcObject, storage)
        return self
    }

    @ObjCClassMethod("archivedDataWithRootObject:requiringSecureCoding:error:")
    static func archivedData(_ cls: ObjCClass, rootObject: ObjCObject?, requiringSecureCoding secure: Bool,
                             error: UnsafeMutablePointer<id?>?) -> UnsafeMutableRawPointer? {
        guard let archiver = Storage.allocate(cls.pointer) else { return nil }
        defer { ObjC.release(archiver) }
        let storage = ArchiverStorage(requiresSecureCoding: secure)
        Storage.set(archiver, storage)
        storage.top["root"] = Archivers.encode(rootObject?.id, in: archiver, storage: storage)
        if let failure = storage.failure {
            error?.pointee = ObjC.autorelease(ObjC.retain(failure))
            return nil
        }
        return Archivers.finish(storage)
    }

    @ObjCClassMethod("archivedDataWithRootObject:")
    static func archivedData(_ cls: ObjCClass, rootObject: ObjCObject?) -> UnsafeMutableRawPointer? {
        archivedData(cls, rootObject: rootObject, requiringSecureCoding: false, error: nil)
    }

    @ObjCClassMethod("archiveRootObject:toFile:")
    static func archive(_ cls: ObjCClass, rootObject: ObjCObject?, toFile path: String) -> Bool {
        guard let data = archivedData(cls, rootObject: rootObject) else { return false }
        return FileManager.default.createFile(atPath: path, contents: DataObjects.data(data))
    }

    @ObjCMethod("requiresSecureCoding") func requiresSecureCoding() -> Bool { storage.requiresSecureCoding }
    @ObjCMethod("setRequiresSecureCoding:") func setRequiresSecureCoding(_ value: Bool) { storage.requiresSecureCoding = value }
    @ObjCMethod("allowsKeyedCoding") func allowsKeyedCoding() -> Bool { true }
    @ObjCMethod("outputFormat") func outputFormat() -> UInt { storage.format }
    @ObjCMethod("setOutputFormat:") func setOutputFormat(_ format: UInt) { storage.format = format }
    @ObjCMethod("finishEncoding") func finishEncoding() { _ = Archivers.finish(storage) }
    @ObjCMethod("encodedData") func encodedData() -> UnsafeMutableRawPointer { Archivers.finish(storage) }
    @ObjCMethod("error") func error() -> UnsafeMutableRawPointer? { storage.failure }
    @ObjCMethod("setDelegate:") func setDelegate(_ delegate: ObjCObject?) {}
    @ObjCMethod("delegate") func delegate() -> UnsafeMutableRawPointer? { nil }

    @ObjCMethod("encodeObject:forKey:")
    func encode(_ object: ObjCObject?, forKey key: String) {
        storage.set(key, Archivers.encode(object?.id, in: objcObject, storage: storage))
    }

    /// Only an object encoded elsewhere is referred to; otherwise nil.
    @ObjCMethod("encodeConditionalObject:forKey:")
    func encodeConditional(_ object: ObjCObject?, forKey key: String) {
        storage.set(key, .uid(object.flatMap { storage.uids[$0.id] } ?? 0))
    }

    @ObjCMethod("encodeRootObject:")
    func encodeRoot(_ object: ObjCObject?) { encode(object, forKey: "root") }

    // MARK: Unkeyed coding, under generated keys

    private func nextKey() -> String {
        defer { storage.unkeyed += 1 }
        return "$\(storage.unkeyed)"
    }

    @ObjCMethod("encodeObject:") func encode(_ object: ObjCObject?) { encode(object, forKey: nextKey()) }

    /// A value of the scalar types an Objective-C type encoding names, a
    /// C string, or an object.
    @ObjCMethod("encodeValueOfObjCType:at:")
    func encodeValue(ofObjCType type: UnsafePointer<CChar>?, at address: UnsafeRawPointer?) {
        guard let type, let address else { return }
        let key = nextKey()
        switch UInt8(bitPattern: type.pointee) {
        case UInt8(ascii: "c"): storage.set(key, .integer(Int64(address.load(as: Int8.self))))
        case UInt8(ascii: "C"), UInt8(ascii: "B"): storage.set(key, .integer(Int64(address.load(as: UInt8.self))))
        case UInt8(ascii: "s"): storage.set(key, .integer(Int64(address.load(as: Int16.self))))
        case UInt8(ascii: "S"): storage.set(key, .integer(Int64(address.load(as: UInt16.self))))
        case UInt8(ascii: "i"): storage.set(key, .integer(Int64(address.load(as: Int32.self))))
        case UInt8(ascii: "I"): storage.set(key, .integer(Int64(address.load(as: UInt32.self))))
        case UInt8(ascii: "l"), UInt8(ascii: "q"): storage.set(key, .integer(address.load(as: Int64.self)))
        case UInt8(ascii: "L"), UInt8(ascii: "Q"): storage.set(key, .integer(Int64(bitPattern: address.load(as: UInt64.self))))
        case UInt8(ascii: "f"): storage.set(key, .real(Double(address.load(as: Float.self))))
        case UInt8(ascii: "d"): storage.set(key, .real(address.load(as: Double.self)))
        case UInt8(ascii: "@"):
            let object = address.load(as: UnsafeMutableRawPointer?.self)
            storage.set(key, Archivers.encode(object, in: objcObject, storage: storage))
        case UInt8(ascii: "*"):
            let string = address.load(as: UnsafePointer<CChar>?.self).map { String(cString: $0) }
            storage.set(key, Archivers.encode(string.map { Strings.autoreleased($0) }, in: objcObject, storage: storage))
        default:
            foundationFatal("-[NSKeyedArchiver encodeValueOfObjCType:at:]: unsupported type \(String(cString: type))")
        }
    }

    @ObjCMethod("encodeBool:forKey:") func encode(bool value: Bool, forKey key: String) { storage.set(key, .bool(value)) }
    @ObjCMethod("encodeInt:forKey:") func encode(int value: Int32, forKey key: String) { storage.set(key, .integer(Int64(value))) }
    @ObjCMethod("encodeInt32:forKey:") func encode(int32 value: Int32, forKey key: String) { storage.set(key, .integer(Int64(value))) }
    @ObjCMethod("encodeInt64:forKey:") func encode(int64 value: Int64, forKey key: String) { storage.set(key, .integer(value)) }
    @ObjCMethod("encodeInteger:forKey:") func encode(integer value: Int, forKey key: String) { storage.set(key, .integer(Int64(value))) }
    @ObjCMethod("encodeFloat:forKey:") func encode(float value: Float, forKey key: String) { storage.set(key, .real(Double(value))) }
    @ObjCMethod("encodeDouble:forKey:") func encode(double value: Double, forKey key: String) { storage.set(key, .real(value)) }

    @ObjCMethod("encodeBytes:length:forKey:")
    func encode(bytes: UnsafePointer<UInt8>?, length: UInt, forKey key: String) {
        storage.set(key, .data(bytes.map { Array(UnsafeBufferPointer(start: $0, count: Int(length))) } ?? []))
    }
}

/// NSKeyedArchiveRootObjectKey.
@ObjCConstants
enum ArchiveKeys {
    static let NSKeyedArchiveRootObjectKey = "root"
}
