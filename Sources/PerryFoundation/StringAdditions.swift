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

/// NSString's encodings, paths and searching, installed into NSString like
/// a category.
@ObjCClass("NSString")
final class NSStringAdditions: NSString {
    private var units: [UInt16] { Array(value.utf16) }

    private static func string(_ units: ArraySlice<UInt16>) -> String { String(decoding: units, as: UTF16.self) }

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

    @ObjCMethod("canBeConvertedToEncoding:")
    func canConvert(to encoding: UInt) -> Bool { StringEncoding.encode(value, encoding) != nil }

    @ObjCMethod("lengthOfBytesUsingEncoding:")
    func byteLength(encoding: UInt) -> UInt { UInt(StringEncoding.encode(value, encoding)?.count ?? 0) }

    /// Valid until the current autorelease pool drains, like Foundation's.
    @ObjCMethod("cStringUsingEncoding:")
    func cString(encoding: UInt) -> UnsafePointer<CChar>? {
        guard var bytes = StringEncoding.encode(value, encoding) else { return nil }
        bytes.append(0)
        let data = DataObjects.autoreleased(Data(bytes))
        return UnsafePointer(DataObjects.storage(data)?.bytes?.assumingMemoryBound(to: CChar.self))
    }

    @ObjCMethod("initWithData:encoding:")
    func initialize(data: NSData, encoding: UInt) -> Self? {
        data.data.withUnsafeBytes { StringEncoding.decode($0, encoding) }.map { decoded in
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

    @ObjCMethod("writeToFile:atomically:encoding:error:")
    func write(toFile path: String, atomically: Bool, encoding: UInt, error: UnsafeMutablePointer<id?>?) -> Bool {
        guard let bytes = StringEncoding.encode(value, encoding),
              (try? Data(bytes).write(to: URL(filePath: path), options: atomically ? .atomic : [])) != nil else {
            error?.pointee = Errors.autoreleased(domain: Errors.cocoaDomain, code: 512, description: "The file couldn’t be saved.")
            return false
        }
        return true
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

    @ObjCMethod("pathComponents")
    func pathComponents() -> NSArray { Arrays.owned(Paths.components(value).map { Strings.autoreleased($0) }) }

    @ObjCMethod("isAbsolutePath")
    func isAbsolutePath() -> Bool { value.hasPrefix("/") || value.hasPrefix("~") }

    @ObjCMethod("stringByExpandingTildeInPath")
    func expandingTilde() -> String {
        guard value == "~" || value.hasPrefix("~/"), let home = getenv("HOME") else { return value }
        return String(cString: home) + value.dropFirst()
    }

    // MARK: Searching

    @ObjCMethod("rangeOfString:")
    func range(of other: String) -> NSRange { PerryFoundation.range(of: other, in: value, options: 0) }

    @ObjCMethod("rangeOfString:options:")
    func range(of other: String, options: UInt) -> NSRange { PerryFoundation.range(of: other, in: value, options: options) }

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

    @ObjCMethod("substringFromIndex:")
    func substring(from index: UInt) -> String {
        Self.string(check(NSRange(location: index, length: 0), "substringFromIndex:")[Int(index)...])
    }

    @ObjCMethod("substringToIndex:")
    func substring(to index: UInt) -> String {
        Self.string(check(NSRange(location: 0, length: index), "substringToIndex:")[..<Int(index)])
    }

    @ObjCMethod("substringWithRange:")
    func substring(range: NSRange) -> String {
        Self.string(check(range, "substringWithRange:")[Int(range.location)..<Int(range.location + range.length)])
    }

    @ObjCMethod("caseInsensitiveCompare:")
    func caseInsensitiveCompare(_ other: String) -> Int { Strings.compare(value.lowercased(), other.lowercased()) }

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
