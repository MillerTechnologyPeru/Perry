import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

// NSString's encodings, paths and searching. Ranges and indexes count
// UTF-16 code units, as NSString does.

/// NSStringEncoding values.
enum StringEncoding {
    static let ascii: UInt = 1
    static let utf8: UInt = 4
    static let isoLatin1: UInt = 5
    static let unicode: UInt = 10                   // UTF-16 with a byte order mark
    static let utf16BigEndian: UInt = 0x9000_0100
    static let utf16LittleEndian: UInt = 0x9400_0100
    static let utf32: UInt = 0x8c00_0100              // with a byte order mark
    static let utf32BigEndian: UInt = 0x9800_0100
    static let utf32LittleEndian: UInt = 0x9c00_0100

    /// The size of one code unit, and so of a C string's terminator.
    static func unitSize(_ encoding: UInt) -> Int {
        switch encoding {
        case unicode, utf16BigEndian, utf16LittleEndian: return 2
        case utf32, utf32BigEndian, utf32LittleEndian: return 4
        default: return 1
        }
    }

    static func encode(_ string: String, _ encoding: UInt, lossy: Bool = false) -> [UInt8]? {
        switch encoding {
        case utf8:
            return Array(string.utf8)
        case ascii, isoLatin1:
            let limit: UInt32 = encoding == ascii ? 0x7f : 0xff
            var bytes: [UInt8] = []
            for scalar in string.unicodeScalars {
                if scalar.value <= limit {
                    bytes.append(UInt8(scalar.value))
                } else if lossy {
                    bytes.append(UInt8(ascii: "?"))
                } else {
                    return nil
                }
            }
            return bytes
        case unicode, utf16LittleEndian:
            var bytes: [UInt8] = encoding == unicode ? [0xff, 0xfe] : []
            for unit in string.utf16 { bytes += [UInt8(unit & 0xff), UInt8(unit >> 8)] }
            return bytes
        case utf16BigEndian:
            return string.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xff)] }
        case utf32, utf32LittleEndian:
            var bytes: [UInt8] = encoding == utf32 ? [0xff, 0xfe, 0, 0] : []
            for scalar in string.unicodeScalars {
                let v = scalar.value
                bytes += [UInt8(v & 0xff), UInt8(v >> 8 & 0xff), UInt8(v >> 16 & 0xff), UInt8(v >> 24)]
            }
            return bytes
        case utf32BigEndian:
            return string.unicodeScalars.flatMap { scalar -> [UInt8] in
                let v = scalar.value
                return [UInt8(v >> 24), UInt8(v >> 16 & 0xff), UInt8(v >> 8 & 0xff), UInt8(v & 0xff)]
            }
        default:
            return nil
        }
    }

    static func decode(_ bytes: UnsafeRawBufferPointer, _ encoding: UInt) -> String? {
        switch encoding {
        case utf8:
            guard let string = String(validating: bytes, as: UTF8.self) else { return nil }
            return string
        case ascii:
            guard bytes.allSatisfy({ $0 < 0x80 }) else { return nil }
            return String(decoding: bytes, as: UTF8.self)
        case isoLatin1:
            return String(String.UnicodeScalarView(bytes.map { Unicode.Scalar($0) }))
        case unicode, utf16LittleEndian, utf16BigEndian:
            var start = 0
            var bigEndian = encoding == utf16BigEndian
            if encoding == unicode && bytes.count >= 2 {
                if bytes[0] == 0xfe && bytes[1] == 0xff { bigEndian = true; start = 2 }
                if bytes[0] == 0xff && bytes[1] == 0xfe { start = 2 }
            }
            var units: [UInt16] = []
            var index = start
            while index + 1 < bytes.count {
                let a = UInt16(bytes[index]), b = UInt16(bytes[index + 1])
                units.append(bigEndian ? a << 8 | b : b << 8 | a)
                index += 2
            }
            return String(decoding: units, as: UTF16.self)
        case utf32, utf32LittleEndian, utf32BigEndian:
            var start = 0
            var bigEndian = encoding == utf32BigEndian
            if encoding == utf32 && bytes.count >= 4 {
                if bytes[0] == 0 && bytes[1] == 0 && bytes[2] == 0xfe && bytes[3] == 0xff { bigEndian = true; start = 4 }
                if bytes[0] == 0xff && bytes[1] == 0xfe && bytes[2] == 0 && bytes[3] == 0 { start = 4 }
            }
            var scalars = String.UnicodeScalarView()
            var index = start
            while index + 3 < bytes.count {
                let b = (0..<4).map { UInt32(bytes[index + $0]) }
                let value = bigEndian ? b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3] : b[3] << 24 | b[2] << 16 | b[1] << 8 | b[0]
                guard let scalar = Unicode.Scalar(value) else { return nil }
                scalars.append(scalar)
                index += 4
            }
            return String(scalars)
        default:
            return nil
        }
    }
}

/// NSString's path rules: repeated slashes collapse, a trailing slash is
/// dropped, and "/" stays "/".
enum Paths {
    static func normalized(_ path: String) -> String {
        var result = ""
        var lastWasSlash = false
        for character in path {
            if character == "/" {
                if lastWasSlash { continue }
                lastWasSlash = true
            } else {
                lastWasSlash = false
            }
            result.append(character)
        }
        if result.count > 1 && result.hasSuffix("/") { result.removeLast() }
        return result
    }

    static func lastComponent(_ path: String) -> String {
        let path = normalized(path)
        if path == "/" { return "/" }
        return path.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? ""
    }

    static func deletingLastComponent(_ path: String) -> String {
        let path = normalized(path)
        guard let slash = path.lastIndex(of: "/") else { return "" }
        if slash == path.startIndex { return "/" }
        return String(path[..<slash])
    }

    static func pathExtension(_ path: String) -> String {
        let last = lastComponent(path)
        guard let dot = last.lastIndex(of: "."), dot != last.startIndex else { return "" }
        return String(last[last.index(after: dot)...])
    }

    static func deletingPathExtension(_ path: String) -> String {
        let path = normalized(path)
        let ext = pathExtension(path)
        return ext.isEmpty ? path : String(path.dropLast(ext.count + 1))
    }

    static func appending(_ path: String, _ component: String) -> String {
        if path.isEmpty { return normalized(component) }
        if component.isEmpty { return normalized(path) }
        return normalized(path + "/" + component)
    }

    static func components(_ path: String) -> [String] {
        guard !path.isEmpty else { return [] }
        var parts: [String] = path.hasPrefix("/") ? ["/"] : []
        parts += path.split(separator: "/").map(String.init)
        if path.count > 1 && path.hasSuffix("/") { parts.append("/") }
        return parts
    }
}

/// NSStringCompareOptions.
private let caseInsensitive: UInt = 1
private let backwards: UInt = 4
private let anchored: UInt = 8

/// NSNotFound.
let notFound = UInt(Int.max)

/// The range of `needle` in `haystack`, in UTF-16 units.
func range(of needle: String, in haystack: String, options: UInt) -> NSRange {
    // NSRegularExpressionSearch: the needle is a pattern.
    if options & 1024 != 0 { return Regexes.search(needle, in: haystack, options: options) }
    let fold: (String) -> [UInt16] = { options & caseInsensitive != 0 ? Array($0.lowercased().utf16) : Array($0.utf16) }
    let text = fold(haystack), pattern = fold(needle)
    guard !pattern.isEmpty, pattern.count <= text.count else { return NSRange(location: notFound, length: 0) }
    var starts = Array(0...(text.count - pattern.count))
    if options & backwards != 0 { starts.reverse() }
    if options & anchored != 0 { starts = [starts[0]] }
    for start in starts where Array(text[start..<start + pattern.count]) == pattern {
        return NSRange(location: UInt(start), length: UInt(pattern.count))
    }
    return NSRange(location: notFound, length: 0)
}

/// NSString's encodings, paths and searching.
@ObjCCategory("Additions")
extension NSString {
    private var units: [UInt16] { Array(value.utf16) }

    private static func decoded(_ units: ArraySlice<UInt16>) -> String { String(decoding: units, as: UTF16.self) }

    private func check(_ range: NSRange, _ method: String) -> [UInt16] {
        let all = units
        if Int(range.location) > all.count || Int(range.length) > all.count - Int(range.location) {
            foundationFatal("-[NSString \(method)]: Range {\(range.location), \(range.length)} out of bounds; string length \(all.count)")
        }
        return all
    }

    // MARK: Encodings

    @ObjCMethod("dataUsingEncoding:")
    func data(encoding: UInt) -> NSData? {
        StringEncoding.encode(value, encoding).map { DataObjects.owned(DataStorage(Data($0))) }
    }

    @ObjCMethod("dataUsingEncoding:allowLossyConversion:")
    func data(encoding: UInt, lossy: Bool) -> NSData? {
        StringEncoding.encode(value, encoding, lossy: lossy).map { DataObjects.owned(DataStorage(Data($0))) }
    }

    /// The string as a property list in the old-style text format, or the
    /// strings file format; nil when it is neither.
    @ObjCMethod("propertyList")
    func propertyList() -> UnsafeMutableRawPointer? {
        PropertyLists.parse(Array(value.utf8)).flatMap { PropertyLists.object($0.0, mutability: 0) }
    }

    /// The string as a strings file: a dictionary of strings.
    @ObjCMethod("propertyListFromStringsFileFormat")
    func propertyListFromStringsFileFormat() -> UnsafeMutableRawPointer? {
        var parser = OpenStepParser(Array(value.unicodeScalars))
        return parser.stringsDocument().flatMap { PropertyLists.object($0, mutability: 0) }
    }

    @ObjCMethod("canBeConvertedToEncoding:")
    func canConvert(to encoding: UInt) -> Bool { StringEncoding.encode(value, encoding) != nil }

    @ObjCMethod("lengthOfBytesUsingEncoding:")
    func byteLength(encoding: UInt) -> UInt { UInt(StringEncoding.encode(value, encoding)?.count ?? 0) }

    /// Valid until the current autorelease pool drains, like Foundation's.
    @ObjCMethod("cStringUsingEncoding:")
    func cString(encoding: UInt) -> UnsafePointer<CChar>? {
        guard var bytes = StringEncoding.encode(value, encoding) else { return nil }
        bytes += repeatElement(0, count: StringEncoding.unitSize(encoding))
        let data = DataObjects.autoreleased(Data(bytes))
        return UnsafePointer(DataObjects.storage(data)?.bytes?.assumingMemoryBound(to: CChar.self))
    }

    @ObjCClassMethod("stringWithCString:encoding:")
    static func string(cString: UnsafePointer<CChar>?, encoding: UInt) -> String? {
        guard let cString else { return nil }
        return StringEncoding.decode(UnsafeRawBufferPointer(start: cString, count: strlen(cString)), encoding)
    }

    @ObjCMethod("initWithCString:encoding:")
    func initialize(cString: UnsafePointer<CChar>?, encoding: UInt) -> Self? {
        guard let cString, let decoded = StringEncoding.decode(UnsafeRawBufferPointer(start: cString, count: strlen(cString)), encoding) else {
            return nil
        }
        Storage.set(objcObject, StringStorage(decoded))
        return self
    }

    /// The deprecated C string methods, in the default C string encoding:
    /// UTF-8, or Latin-1 for bytes that are not.
    static func decodeDefault(_ cString: UnsafePointer<CChar>) -> String {
        let bytes = UnsafeRawBufferPointer(start: cString, count: strlen(cString))
        return StringEncoding.decode(bytes, 4) ?? StringEncoding.decode(bytes, 5) ?? ""
    }

    @ObjCClassMethod("stringWithCString:")
    static func string(cString: UnsafePointer<CChar>?) -> String? { cString.map(decodeDefault) }

    @ObjCMethod("initWithCString:")
    func initialize(cString: UnsafePointer<CChar>?) -> Self? {
        guard let cString else { return nil }
        Storage.set(objcObject, StringStorage(NSString.decodeDefault(cString)))
        return self
    }

    @ObjCClassMethod("defaultCStringEncoding") static func defaultCStringEncoding() -> UInt { 4 }

    @ObjCClassMethod("stringWithCharacters:length:")
    static func string(characters: UnsafePointer<UInt16>?, length: UInt) -> String {
        guard let characters else { return "" }
        return String(decoding: UnsafeBufferPointer(start: characters, count: Int(length)), as: UTF16.self)
    }

    @ObjCMethod("initWithCharacters:length:")
    func initialize(characters: UnsafePointer<UInt16>?, length: UInt) -> Self {
        Storage.set(objcObject, StringStorage(NSString.string(characters: characters, length: length)))
        return self
    }

    @ObjCMethod("getCharacters:range:")
    func getCharacters(_ buffer: UnsafeMutablePointer<UInt16>?, range: NSRange) {
        let units = Array(value.utf16), location = Int(range.location), length = Int(range.length)
        guard let buffer, location + length <= units.count else {
            foundationFatal("-[NSString getCharacters:range:]: Range \(location),\(length) out of bounds")
        }
        for index in 0..<length { buffer[index] = units[location + index] }
    }

    @ObjCMethod("getCharacters:")
    func getCharacters(_ buffer: UnsafeMutablePointer<UInt16>?) {
        guard let buffer else { return }
        for (index, unit) in value.utf16.enumerated() { buffer[index] = unit }
    }

    /// Escapes what may not appear in a URL, keeping what may, '%' among it.
    @ObjCMethod("stringByAddingPercentEscapesUsingEncoding:")
    func addingPercentEscapes(encoding: UInt) -> String? {
        let legal = Set("!$&'()*+,-./:;=?@_~#[]%".utf8)
        var escaped = ""
        for byte in value.utf8 {
            if (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || legal.contains(byte) {
                escaped.unicodeScalars.append(Unicode.Scalar(byte))
            } else {
                escaped += "%" + String(byte, radix: 16, uppercase: true).leftPadded(to: 2)
            }
        }
        return escaped
    }

    @ObjCMethod("stringByReplacingPercentEscapesUsingEncoding:")
    func replacingPercentEscapes(encoding: UInt) -> String? {
        var bytes: [UInt8] = []
        var utf8 = Array(value.utf8)[...]
        while let byte = utf8.popFirst() {
            if byte == 0x25 {
                guard utf8.count >= 2, let decoded = UInt8(String(decoding: utf8.prefix(2), as: UTF8.self), radix: 16) else { return nil }
                bytes.append(decoded)
                utf8 = utf8.dropFirst(2)
            } else {
                bytes.append(byte)
            }
        }
        return bytes.withUnsafeBytes { StringEncoding.decode($0, encoding) }
    }

    /// Escapes, as %XX of its UTF-8 bytes, each character not in `allowed`.
    @ObjCMethod("stringByAddingPercentEncodingWithAllowedCharacters:")
    func addingPercentEncoding(allowed: ObjCObject?) -> String? {
        guard let contains = CharacterSets.storage(allowed?.id)?.contains else { return nil }
        var escaped = ""
        for scalar in value.unicodeScalars {
            if contains(scalar) {
                escaped.unicodeScalars.append(scalar)
            } else {
                for byte in String(scalar).utf8 {
                    escaped += "%" + String(byte, radix: 16, uppercase: true).leftPadded(to: 2)
                }
            }
        }
        return escaped
    }

    /// Unescapes %XX sequences as UTF-8; nil if one is malformed or the
    /// result isn't UTF-8.
    @ObjCMethod("stringByRemovingPercentEncoding")
    func removingPercentEncoding() -> String? { replacingPercentEscapes(encoding: StringEncoding.utf8) }

    /// The string in `encoding` and a terminating zero, when that fits in
    /// `maxLength` bytes.
    @ObjCMethod("getCString:maxLength:encoding:")
    func getCString(_ buffer: UnsafeMutablePointer<CChar>?, maxLength: UInt, encoding: UInt) -> Bool {
        guard let buffer, let bytes = StringEncoding.encode(value, encoding), bytes.count < Int(maxLength) else { return false }
        for (index, byte) in bytes.enumerated() { buffer[index] = CChar(bitPattern: byte) }
        buffer[bytes.count] = 0
        return true
    }

    /// Converts the characters in `range` to `encoding`, as many whole
    /// characters as fit in `maxLength` bytes (any number, without a
    /// buffer), stopping at one the encoding lacks unless lossy conversion
    /// (option 1) is allowed. Swift reads NSStrings' contents this way.
    @ObjCMethod("getBytes:maxLength:usedLength:encoding:options:range:remainingRange:")
    func getBytes(_ buffer: UnsafeMutableRawPointer?, maxLength: UInt, usedLength: UnsafeMutablePointer<UInt>?, encoding: UInt,
                  options: UInt, range: NSRange, remainingRange: UnsafeMutablePointer<NSRange>?) -> Bool {
        let all = check(range, "getBytes:maxLength:usedLength:encoding:options:range:remainingRange:")
        let start = Int(range.location), end = start + Int(range.length)
        var used = 0, index = start
        while index < end {
            let width = UTF16.isLeadSurrogate(all[index]) && index + 1 < end && UTF16.isTrailSurrogate(all[index + 1]) ? 2 : 1
            guard let bytes = StringEncoding.encode(NSString.decoded(all[index..<index + width]), encoding, lossy: options & 1 != 0) else {
                break
            }
            if let buffer {
                guard used + bytes.count <= Int(maxLength) else { break }
                bytes.withUnsafeBytes { (buffer + used).copyMemory(from: $0.baseAddress!, byteCount: bytes.count) }
            }
            used += bytes.count
            index += width
        }
        usedLength?.pointee = UInt(used)
        remainingRange?.pointee = NSRange(location: UInt(index), length: UInt(end - index))
        return index > start
    }

    /// The encoding the contents convert to fastest: they are Unicode.
    @ObjCMethod("fastestEncoding")
    func fastestEncoding() -> UInt { StringEncoding.unicode }

    /// Pointers straight to the contents, which Swift tries before copying
    /// them out. Strings here keep neither form, so there are none.
    @ObjCMethod("_fastCStringContents:")
    func fastCStringContents(_ nullTerminated: Bool) -> UnsafePointer<CChar>? { nil }

    @ObjCMethod("_fastCharacterContents")
    func fastCharacterContents() -> UnsafePointer<UInt16>? { nil }

    /// No data makes an empty string, as it does on Darwin.
    @ObjCMethod("initWithData:encoding:")
    func initialize(data: NSData?, encoding: UInt) -> Self? {
        (data?.data ?? Data()).withUnsafeBytes { StringEncoding.decode($0, encoding) }.map { decoded in
            Storage.set(objcObject, StringStorage(decoded))
            return self
        }
    }

    @ObjCClassMethod("stringWithContentsOfFile:encoding:error:")
    static func string(contentsOfFile path: String, encoding: UInt, error: UnsafeMutablePointer<id?>?) -> String? {
        let decoded = (try? Data(contentsOf: URL(filePath: path))).flatMap { $0.withUnsafeBytes { StringEncoding.decode($0, encoding) } }
        if decoded == nil {
            error?.pointee = Errors.autoreleased(domain: Errors.cocoaDomain, code: 260, description: "The file couldn’t be opened.")
        }
        return decoded
    }

    /// A file's contents, or what NSURLConnection loads for other schemes.
    @ObjCMethod("initWithContentsOfFile:encoding:error:")
    func initialize(contentsOfFile path: String?, encoding: UInt, error: UnsafeMutablePointer<id?>?) -> Self? {
        guard let path, let decoded = Self.string(contentsOfFile: path, encoding: encoding, error: error) else { return nil }
        Storage.set(objcObject, StringStorage(decoded))
        return self
    }

    @ObjCMethod("initWithContentsOfURL:encoding:error:")
    func initialize(contentsOfURL url: NSURL?, encoding: UInt, error: UnsafeMutablePointer<id?>?) -> Self? {
        guard let decoded = Self.string(contentsOfURL: url, encoding: encoding, error: error) else { return nil }
        Storage.set(objcObject, StringStorage(decoded))
        return self
    }

    @ObjCClassMethod("stringWithContentsOfURL:encoding:error:")
    static func string(contentsOfURL url: NSURL?, encoding: UInt, error: UnsafeMutablePointer<id?>?) -> String? {
        let decoded = url.flatMap(NSData.contents).flatMap { $0.withUnsafeBytes { StringEncoding.decode($0, encoding) } }
        if decoded == nil {
            error?.pointee = Errors.autoreleased(domain: Errors.cocoaDomain, code: 260, description: "The file couldn’t be opened.")
        }
        return decoded
    }

    @ObjCMethod("writeToFile:atomically:encoding:error:")
    func write(toFile path: String, atomically: Bool, encoding: UInt, error: UnsafeMutablePointer<id?>?) -> Bool {
        guard let bytes = StringEncoding.encode(value, encoding),
              (try? Data(bytes).write(to: URL(filePath: path), options: atomically ? .atomic : [])) != nil else {
            error?.pointee = Errors.autoreleased(domain: Errors.cocoaDomain, code: 512, description: "The file couldn’t be saved.")
            return false
        }
        return true
    }

    /// Only file URLs can be written.
    @ObjCMethod("writeToURL:atomically:encoding:error:")
    func write(to url: NSURL, atomically: Bool, encoding: UInt, error: UnsafeMutablePointer<id?>?) -> Bool {
        guard url.url.isFileURL else {
            error?.pointee = Errors.autoreleased(domain: Errors.cocoaDomain, code: 518, description: "The file couldn’t be saved.")
            return false
        }
        return write(toFile: url.url.path(percentEncoded: false), atomically: atomically, encoding: encoding, error: error)
    }

    // MARK: Paths

    @ObjCMethod("lastPathComponent") func lastPathComponent() -> String { Paths.lastComponent(value) }
    @ObjCMethod("pathExtension") func pathExtension() -> String { Paths.pathExtension(value) }
    @ObjCMethod("stringByDeletingLastPathComponent") func deletingLastPathComponent() -> String { Paths.deletingLastComponent(value) }
    @ObjCMethod("stringByDeletingPathExtension") func deletingPathExtension() -> String { Paths.deletingPathExtension(value) }

    @ObjCMethod("stringByAppendingPathComponent:")
    func appending(pathComponent component: String) -> String { Paths.appending(value, component) }

    @ObjCMethod("stringByAppendingPathExtension:")
    func appending(pathExtension: String) -> String { Paths.normalized(value) + "." + pathExtension }

    /// The path the components make, as -pathComponents gives them: "/"
    /// first for an absolute path.
    @ObjCClassMethod("pathWithComponents:")
    static func path(components: NSArray) -> String {
        components.elements.compactMap { Strings.value(of: $0) }.reduce("") { Paths.appending($0, $1) }
    }

    @ObjCMethod("pathComponents")
    func pathComponents() -> NSArray { Arrays.owned(Paths.components(value).map { Strings.autoreleased($0) }) }

    @ObjCMethod("isAbsolutePath")
    func isAbsolutePath() -> Bool { value.hasPrefix("/") || value.hasPrefix("~") }

    @ObjCMethod("stringByExpandingTildeInPath")
    func expandingTilde() -> String {
        guard value == "~" || value.hasPrefix("~/"), let home = getenv("HOME") else { return value }
        return String(cString: home) + value.dropFirst()
    }

    /// The tilde expanded, and "." components, empty components and a
    /// trailing slash removed; ".." resolved where a component precedes it
    /// (never above the root of an absolute path).
    @ObjCMethod("stringByStandardizingPath")
    func standardizingPath() -> String {
        let path = expandingTilde()
        guard !path.isEmpty else { return path }
        let absolute = path.hasPrefix("/")
        var components: [Substring] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true) where component != "." {
            if component == "..", let last = components.last, last != ".." {
                components.removeLast()
            } else if component == "..", absolute {
                continue
            } else {
                components.append(component)
            }
        }
        let joined = components.joined(separator: "/")
        return absolute ? "/" + joined : (joined.isEmpty ? "." : joined)
    }

    /// Symbolic links resolved when the path exists; standardized otherwise.
    @ObjCMethod("stringByResolvingSymlinksInPath")
    func resolvingSymlinks() -> String {
        let standardized = standardizingPath()
        guard let resolved = realpath(standardized, nil) else { return standardized }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    // MARK: Searching

    @ObjCMethod("rangeOfString:")
    func range(of other: String) -> NSRange { PerryFoundation.range(of: other, in: value, options: 0) }

    @ObjCMethod("rangeOfString:options:")
    func range(of other: String, options: UInt) -> NSRange { PerryFoundation.range(of: other, in: value, options: options) }

    @ObjCMethod("stringByReplacingCharactersInRange:withString:")
    func replacingCharacters(in range: NSRange, with replacement: String) -> String {
        var units = Array(value.utf16)
        let start = Int(range.location), end = Int(range.location + range.length)
        guard start <= end, end <= units.count else {
            foundationFatal("-[NSString stringByReplacingCharactersInRange:withString:]: Range {\(range.location), \(range.length)} out of bounds; string length \(units.count)")
        }
        units.replaceSubrange(start..<end, with: replacement.utf16)
        return String(decoding: units, as: UTF16.self)
    }

    /// The search confined to `scope`, in UTF-16 units; the result counts
    /// from the start of the string.
    @ObjCMethod("rangeOfString:options:range:")
    func range(of other: String, options: UInt, range scope: NSRange) -> NSRange {
        let units = Array(value.utf16)
        let start = Int(scope.location), end = Int(scope.location + scope.length)
        guard start <= end, end <= units.count else {
            foundationFatal("-[NSString rangeOfString:options:range:]: Range {\(scope.location), \(scope.length)} out of bounds; string length \(units.count)")
        }
        let found = PerryFoundation.range(of: other, in: String(decoding: units[start..<end], as: UTF16.self), options: options)
        guard found.location != notFound else { return found }
        return NSRange(location: found.location + scope.location, length: found.length)
    }

    @ObjCMethod("containsString:")
    func contains(_ other: String) -> Bool { range(of: other).location != notFound }

    @ObjCMethod("componentsSeparatedByString:")
    func components(separatedBy separator: String) -> NSArray {
        let parts = separator.isEmpty ? [value] : value.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
        return Arrays.owned(parts.map { Strings.autoreleased($0) })
    }

    @ObjCMethod("stringByReplacingOccurrencesOfString:withString:")
    func replacing(_ target: String, with replacement: String) -> String {
        target.isEmpty ? value : value.replacing(target, with: replacement)
    }

    /// Replaces matches within `scope`, found as -rangeOfString:options:range:
    /// finds them: each in turn, or only one when searching backwards (4) or
    /// anchored (8). A regular expression's replacement is taken literally.
    @ObjCMethod("stringByReplacingOccurrencesOfString:withString:options:range:")
    func replacing(_ target: String, with replacement: String, options: UInt, range scope: NSRange) -> String {
        let all = check(scope, "stringByReplacingOccurrencesOfString:withString:options:range:")
        guard !target.isEmpty else { return value }
        let end = Int(scope.location + scope.length)
        var result = Array(all[..<Int(scope.location)]), position = Int(scope.location)
        while position <= end {
            let found = self.range(of: target, options: options, range: NSRange(location: position, length: end - position))
            guard found.location != notFound, found.length > 0 else { break }
            result += all[position..<Int(found.location)]
            result += replacement.utf16
            position = Int(found.location + found.length)
            if options & 0xC != 0 { break }
        }
        result += all[position...]
        return String(decoding: result, as: UTF16.self)
    }

    // MARK: Composed characters

    /// The UTF-16 offsets where grapheme clusters begin, and the end.
    private var clusterBoundaries: [Int] {
        var offsets = [0], offset = 0
        for character in value {
            offset += character.utf16.count
            offsets.append(offset)
        }
        return offsets
    }

    /// The cluster around the character at `index`, as a user sees it.
    @ObjCMethod("rangeOfComposedCharacterSequenceAtIndex:")
    func rangeOfComposedCharacterSequence(at index: UInt) -> NSRange {
        let boundaries = clusterBoundaries
        guard Int(index) < boundaries.last! else {
            foundationFatal("-[NSString rangeOfComposedCharacterSequenceAtIndex:]: Index \(index) out of bounds; string length \(boundaries.last!)")
        }
        let end = boundaries.first { $0 > Int(index) }!, start = boundaries.last { $0 <= Int(index) }!
        return NSRange(location: UInt(start), length: UInt(end - start))
    }

    /// `range` grown to whole clusters at both ends.
    @ObjCMethod("rangeOfComposedCharacterSequencesForRange:")
    func rangeOfComposedCharacterSequences(for range: NSRange) -> NSRange {
        _ = check(range, "rangeOfComposedCharacterSequencesForRange:")
        let boundaries = clusterBoundaries
        let location = Int(range.location), last = location + max(Int(range.length), 1)
        let start = boundaries.last { $0 <= location }!
        let end = boundaries.first { $0 >= last } ?? boundaries.last!
        return NSRange(location: UInt(start), length: UInt(end - start))
    }

    @ObjCMethod("substringFromIndex:")
    func substring(from index: UInt) -> String {
        Self.decoded(check(NSRange(location: index, length: 0), "substringFromIndex:")[Int(index)...])
    }

    @ObjCMethod("substringToIndex:")
    func substring(to index: UInt) -> String {
        Self.decoded(check(NSRange(location: 0, length: index), "substringToIndex:")[..<Int(index)])
    }

    @ObjCMethod("substringWithRange:")
    func substring(range: NSRange) -> String {
        Self.decoded(check(range, "substringWithRange:")[Int(range.location)..<Int(range.location + range.length)])
    }

    @ObjCMethod("caseInsensitiveCompare:")
    func caseInsensitiveCompare(_ other: String) -> Int { Strings.compare(value.lowercased(), other.lowercased()) }

    /// NSStringCompareOptions: case insensitive 1, numeric 64 (digit runs
    /// compare as numbers); others compare literally.
    @ObjCMethod("compare:options:")
    func compare(_ other: String, options: UInt) -> Int {
        let a = options & 1 != 0 ? value.lowercased() : value, b = options & 1 != 0 ? other.lowercased() : other
        return options & 64 != 0 ? Strings.numericCompare(a, b) : Strings.compare(a, b)
    }

    @ObjCMethod("compare:options:range:")
    func compare(_ other: String, options: UInt, range: NSRange) -> Int {
        let part = substring(range: range)
        let a = options & 1 != 0 ? part.lowercased() : part, b = options & 1 != 0 ? other.lowercased() : other
        return options & 64 != 0 ? Strings.numericCompare(a, b) : Strings.compare(a, b)
    }

    /// The locale changes nothing: comparisons are not localized here.
    @ObjCMethod("compare:options:range:locale:")
    func compare(_ other: String, options: UInt, range: NSRange, locale: ObjCObject?) -> Int {
        compare(other, options: options, range: range)
    }

    /// Not localized, as the other comparisons here.
    @ObjCMethod("localizedCompare:")
    func localizedCompare(_ other: String) -> Int { Strings.compare(value, other) }

    @ObjCMethod("localizedCaseInsensitiveCompare:")
    func localizedCaseInsensitiveCompare(_ other: String) -> Int { Strings.compare(value.lowercased(), other.lowercased()) }

    @ObjCMethod("localizedStandardCompare:")
    func localizedStandardCompare(_ other: String) -> Int { Strings.numericCompare(value.lowercased(), other.lowercased()) }

    /// A letter starts a word unless a letter precedes it, so digits split
    /// words too ("br0wn" becomes "Br0Wn"), as in Foundation.
    @ObjCMethod("capitalizedString")
    func capitalized() -> String {
        var result = ""
        var startOfWord = true
        for character in value {
            result += startOfWord ? character.uppercased() : character.lowercased()
            startOfWord = !character.isLetter
        }
        return result
    }

    // Case mapping for a locale: Swift's mapping is the root locale's, which
    // differs only for a few languages (Turkish dotted i among them).
    @ObjCMethod("uppercaseStringWithLocale:")
    func uppercased(locale: ObjCObject?) -> String { value.uppercased() }

    @ObjCMethod("lowercaseStringWithLocale:")
    func lowercased(locale: ObjCObject?) -> String { value.lowercased() }

    @ObjCMethod("capitalizedStringWithLocale:")
    func capitalized(locale: ObjCObject?) -> String { capitalized() }

    @ObjCMethod("localizedUppercaseString")
    func localizedUppercase() -> String { value.uppercased() }

    @ObjCMethod("localizedLowercaseString")
    func localizedLowercase() -> String { value.lowercased() }

    @ObjCMethod("localizedCapitalizedString")
    func localizedCapitalized() -> String { capitalized() }

    @ObjCMethod("boolValue")
    func boolValue() -> Bool {
        let trimmed = value.drop { $0.isWhitespace }
        guard let first = trimmed.first else { return false }
        return "YyTt".contains(first)
            || (trimmed.drop { $0 == "0" || $0 == "+" || $0 == "-" }.first?.isNumber ?? false)
    }

    @ObjCMethod("longLongValue") func longLongValue() -> Int64 { Int64(Strings.integerPrefix(value)) }
    @ObjCMethod("floatValue") func floatValue() -> Float { value.withCString { strtof($0, nil) } }
}

extension String {
    func leftPadded(to length: Int) -> String { String(repeating: "0", count: max(0, length - count)) + self }
}
