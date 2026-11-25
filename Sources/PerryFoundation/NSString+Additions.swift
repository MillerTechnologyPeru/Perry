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
            guard let name = iconvName(encoding) else { return nil }
            return convert(Array(string.utf8), from: "UTF-8", to: lossy ? name + "//TRANSLIT" : name)
        }
    }

    /// glibc's iconv name for the other encodings Darwin has: its legacy
    /// NSStringEncodings, and CFStringEncodings with the high bit set.
    static func iconvName(_ encoding: UInt) -> String? {
        let low = encoding & 0xFFFF_FFFF
        switch low {
        case 2: return "NEXTSTEP"
        case 3: return "EUC-JP"
        case 8: return "CP932"                      // Shift JIS, as Darwin's
        case 9: return "ISO-8859-2"
        case 11: return "CP1251"
        case 12: return "CP1252"
        case 13: return "CP1253"
        case 14: return "CP1254"
        case 15: return "CP1250"
        case 21: return "ISO-2022-JP"
        case 30: return "MACINTOSH"
        default: break
        }
        guard low & 0x8000_0000 != 0 else { return nil }
        switch low & 0x7FFF_FFFF {
        case 0x0001, 0x0A01, 0x0628: return "CP932"      // Mac Japanese, Shift JIS, DOS Japanese
        case 0x0002, 0x0A03: return "BIG5"               // Mac Chinese (Traditional), Big5
        case 0x0003, 0x0422, 0x0940: return "CP949"      // Mac Korean, DOS Korean, EUC-KR
        case 0x0019, 0x0421, 0x0930: return "GBK"        // Mac Chinese (Simplified), DOS Chinese, GB 2312
        case 0x0632: return "GB18030"
        case 0x0920: return "EUC-JP"
        case 0x0201...0x0210: return "ISO-8859-\((low & 0x7FFF_FFFF) - 0x0200)"
        case 0x0500: return "CP1252"
        case 0x0501: return "CP1250"
        case 0x0502: return "CP1251"
        case 0x0503: return "CP1253"
        case 0x0504: return "CP1254"
        default: return nil
        }
    }

    /// Bytes converted by glibc's iconv; nil if a byte or character can't be.
    static func convert(_ input: [UInt8], from: String, to: String) -> [UInt8]? {
        let descriptor = iconv_open(to, from)
        guard let descriptor, Int(bitPattern: descriptor) != -1 else { return nil }
        defer { iconv_close(descriptor) }
        var source = input.map { CChar(bitPattern: $0) }
        var output = [CChar](repeating: 0, count: input.count * 4 + 16)
        let written: Int? = source.withUnsafeMutableBufferPointer { inBuffer in
            output.withUnsafeMutableBufferPointer { outBuffer in
                var inPointer = inBuffer.baseAddress, outPointer = outBuffer.baseAddress
                var inLeft = inBuffer.count, outLeft = outBuffer.count
                guard iconv(descriptor, &inPointer, &inLeft, &outPointer, &outLeft) != -1 || inLeft == 0 else { return nil }
                return outBuffer.count - outLeft
            }
        }
        guard let written else { return nil }
        return output[..<written].map { UInt8(bitPattern: $0) }
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
            guard let name = iconvName(encoding), let utf8 = convert(Array(bytes), from: name, to: "UTF-8") else { return nil }
            return String(decoding: utf8, as: UTF8.self)
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

    /// The most bytes the string could take in the encoding, without
    /// encoding it: per UTF-16 unit, three in UTF-8, the unit's size in
    /// UTF-16 and UTF-32, else one.
    @ObjCMethod("maximumLengthOfBytesUsingEncoding:")
    func maximumByteLength(encoding: UInt) -> UInt {
        let units = UInt(value.utf16.count)
        switch encoding {
        case 4: return units * 3
        case 10, 0x9000_0100, 0x9400_0100: return units * 2
        case 0x8c00_0100, 0x9800_0100, 0x9c00_0100: return units * 4
        default: return units
        }
    }

    /// Valid until the current autorelease pool drains, like Foundation's.
    @ObjCMethod("cStringUsingEncoding:")
    func cString(encoding: UInt) -> UnsafePointer<CChar>? {
        guard var bytes = StringEncoding.encode(value, encoding) else { return nil }
        bytes += repeatElement(0, count: StringEncoding.unitSize(encoding))
        let data = DataObjects.autoreleased(Data(bytes))
        return UnsafePointer(DataObjects.storage(data)?.bytes?.assumingMemoryBound(to: CChar.self))
    }

    @ObjCClassMethod("stringWithCString:encoding:")
    static func string(_ cls: ObjCClass, cString: UnsafePointer<CChar>?, encoding: UInt) -> ObjCObject? {
        guard let cString,
              let decoded = StringEncoding.decode(UnsafeRawBufferPointer(start: cString, count: strlen(cString)), encoding) else { return nil }
        return ObjCObject(Strings.autoreleased(decoded, of: cls.pointer))
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
    static func string(_ cls: ObjCClass, cString: UnsafePointer<CChar>?) -> ObjCObject? {
        cString.map { ObjCObject(Strings.autoreleased(decodeDefault($0), of: cls.pointer)) }
    }

    @ObjCMethod("initWithCString:")
    func initialize(cString: UnsafePointer<CChar>?) -> Self? {
        guard let cString else { return nil }
        Storage.set(objcObject, StringStorage(NSString.decodeDefault(cString)))
        return self
    }

    @ObjCClassMethod("defaultCStringEncoding") static func defaultCStringEncoding() -> UInt { 4 }

    /// An encoding's name as Foundation shows it (Xcode lists them in its
    /// file inspector); an encoding it doesn't know has none.
    @ObjCClassMethod("localizedNameOfStringEncoding:")
    static func localizedName(ofStringEncoding encoding: UInt) -> ObjCObject {
        ObjCObject(Strings.autoreleased(encodingNames[encoding] ?? ""))
    }

    /// The encodings Foundation names, ended by 0, as
    /// +availableStringEncodings answers them.
    @ObjCClassMethod("availableStringEncodings")
    static func availableStringEncodings() -> UnsafePointer<UInt> { UnsafePointer(availableEncodings) }

    static let encodingNames: [UInt: String] = [
        1: "Western (ASCII)", 2: "Japanese (EUC)", 3: "Japanese (Shift JIS)", 4: "Unicode (UTF-8)",
        5: "Western (ISO Latin 1)", 6: "Symbol (Mac OS)", 7: "Non-lossy ASCII", 8: "Japanese (Shift JIS)",
        9: "Central European (ISO Latin 2)", 10: "Unicode (UTF-16)", 11: "Cyrillic (Windows)",
        12: "Western (Windows Latin 1)", 13: "Greek (Windows)", 14: "Turkish (Windows Latin 5)",
        15: "Central European (Windows Latin 2)", 21: "Japanese (ISO 2022-JP)", 30: "Western (Mac OS Roman)",
        0x9000_0100: "Unicode (UTF-16BE)", 0x9400_0100: "Unicode (UTF-16LE)",
        0x8C00_0100: "Unicode (UTF-32)", 0x9800_0100: "Unicode (UTF-32BE)", 0x9C00_0100: "Unicode (UTF-32LE)",
    ]

    nonisolated(unsafe) static let availableEncodings: UnsafeMutablePointer<UInt> = {
        let list = encodingNames.keys.sorted() + [0]
        let pointer = UnsafeMutablePointer<UInt>.allocate(capacity: list.count)
        pointer.initialize(from: list, count: list.count)
        return pointer
    }()

    @ObjCClassMethod("stringWithCharacters:length:")
    static func string(_ cls: ObjCClass, characters: UnsafePointer<UInt16>?, length: UInt) -> ObjCObject {
        let text = characters.map { String(decoding: UnsafeBufferPointer(start: $0, count: Int(length)), as: UTF16.self) } ?? ""
        return ObjCObject(Strings.autoreleased(text, of: cls.pointer))
    }

    @ObjCMethod("initWithCharacters:length:")
    func initialize(characters: UnsafePointer<UInt16>?, length: UInt) -> Self {
        let text = characters.map { String(decoding: UnsafeBufferPointer(start: $0, count: Int(length)), as: UTF16.self) } ?? ""
        Storage.set(objcObject, StringStorage(text))
        return self
    }

    /// The characters copied (the string keeps its own), then freed if the
    /// string was to own them.
    @ObjCMethod("initWithCharactersNoCopy:length:freeWhenDone:")
    func initialize(charactersNoCopy characters: UnsafeMutablePointer<UInt16>?, length: UInt, freeWhenDone: Bool) -> Self {
        let string = initialize(characters: characters.map { UnsafePointer($0) }, length: length)
        if freeWhenDone { free(characters) }
        return string
    }

    @ObjCMethod("getCharacters:range:")
    func getCharacters(_ buffer: UnsafeMutablePointer<UInt16>?, range: NSRange) {
        let units = value.utf16, location = Int(range.location), length = Int(range.length)
        guard let buffer, location >= 0, length >= 0, location + length <= units.count else {
            foundationFatal("-[NSString getCharacters:range:]: Range \(location),\(length) out of bounds")
        }
        // Along the string from the start of the range, not a copy of it.
        var index = units.index(units.startIndex, offsetBy: location)
        for offset in 0..<length {
            buffer[offset] = units[index]
            index = units.index(after: index)
        }
    }

    // MARK: Lines and paragraphs

    /// The bounds of the lines (or paragraphs) a range touches: where the
    /// first starts, where the last ends after its terminator, and where its
    /// contents end before it. Lines end at LF, CR, CRLF, NEL, LS and PS;
    /// paragraphs at the same but LS.
    private func lineBounds(_ range: NSRange, paragraphs: Bool, _ method: String) -> (start: Int, end: Int, contentsEnd: Int) {
        let all = check(range, method)
        func isTerminator(_ unit: UInt16) -> Bool {
            switch unit {
            case 0x0A, 0x0D, 0x85, 0x2029: return true
            case 0x2028: return !paragraphs
            default: return false
            }
        }
        let count = all.count
        /// Whether `index` is the LF of a CR LF pair, which is one terminator.
        func isPairedLF(_ index: Int) -> Bool { index > 0 && index < count && all[index - 1] == 0x0D && all[index] == 0x0A }
        var start = Int(range.location)
        if isPairedLF(start) { start -= 1 }
        while start > 0, !isTerminator(all[start - 1]) { start -= 1 }
        // A range ending just after a terminator ends on that line.
        var index = Int(range.location + range.length)
        if range.length > 0, isTerminator(all[index - 1]),
           !(all[index - 1] == 0x0D && index < count && all[index] == 0x0A) {
            index -= 1
        }
        if isPairedLF(index) { index -= 1 }
        while index < count, !isTerminator(all[index]) { index += 1 }
        let contentsEnd = index
        var end = index
        if end < count {
            end += (all[end] == 0x0D && end + 1 < count && all[end + 1] == 0x0A) ? 2 : 1
        }
        return (start, end, contentsEnd)
    }

    @ObjCMethod("lineRangeForRange:")
    func lineRange(for range: NSRange) -> NSRange {
        let bounds = lineBounds(range, paragraphs: false, "lineRangeForRange:")
        return NSRange(location: UInt(bounds.start), length: UInt(bounds.end - bounds.start))
    }

    @ObjCMethod("paragraphRangeForRange:")
    func paragraphRange(for range: NSRange) -> NSRange {
        let bounds = lineBounds(range, paragraphs: true, "paragraphRangeForRange:")
        return NSRange(location: UInt(bounds.start), length: UInt(bounds.end - bounds.start))
    }

    @ObjCMethod("getLineStart:end:contentsEnd:forRange:")
    func getLineStart(_ start: UnsafeMutablePointer<UInt>?, end: UnsafeMutablePointer<UInt>?,
                      contentsEnd: UnsafeMutablePointer<UInt>?, for range: NSRange) {
        let bounds = lineBounds(range, paragraphs: false, "getLineStart:end:contentsEnd:forRange:")
        start?.pointee = UInt(bounds.start)
        end?.pointee = UInt(bounds.end)
        contentsEnd?.pointee = UInt(bounds.contentsEnd)
    }

    @ObjCMethod("getParagraphStart:end:contentsEnd:forRange:")
    func getParagraphStart(_ start: UnsafeMutablePointer<UInt>?, end: UnsafeMutablePointer<UInt>?,
                           contentsEnd: UnsafeMutablePointer<UInt>?, for range: NSRange) {
        let bounds = lineBounds(range, paragraphs: true, "getParagraphStart:end:contentsEnd:forRange:")
        start?.pointee = UInt(bounds.start)
        end?.pointee = UInt(bounds.end)
        contentsEnd?.pointee = UInt(bounds.contentsEnd)
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

    /// The deprecated ones, in the default C string encoding: the whole
    /// string and a terminating zero into a buffer taken to be big enough,
    /// or as much as fits in `maxLength` bytes, which leave room for the
    /// zero.
    @ObjCMethod("getCString:")
    func getCString(_ buffer: UnsafeMutablePointer<CChar>?) {
        getCString(buffer, maxLength: UInt(Int.max - 1))
    }

    @ObjCMethod("getCString:maxLength:")
    func getCString(_ buffer: UnsafeMutablePointer<CChar>?, maxLength: UInt) {
        guard let buffer else { return }
        let bytes = Array(value.utf8).prefix(Int(min(maxLength, UInt(Int.max))))
        for (index, byte) in bytes.enumerated() { buffer[index] = CChar(bitPattern: byte) }
        buffer[bytes.count] = 0
    }

    /// The bytes of the string in the default C string encoding.
    @ObjCMethod("cStringLength") func cStringLength() -> UInt { UInt(value.utf8.count) }

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

    /// The encoding the contents convert to fastest: ASCII for ASCII
    /// text, as on Darwin, otherwise Unicode.
    @ObjCMethod("fastestEncoding")
    func fastestEncoding() -> UInt { value.utf16.allSatisfy { $0 < 0x80 } ? StringEncoding.ascii : StringEncoding.unicode }

    /// A pointer straight to the contents, which Swift tries before reading
    /// them a character at a time: an immutable string's own NUL-terminated
    /// bytes when it is all ASCII, kept as long as it is.
    @ObjCMethod("_fastCStringContents:")
    func fastCStringContents(_ nullTerminated: Bool) -> UnsafePointer<CChar>? { Strings.asciiPointer(objcObject) }

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

    /// A file's text in the encoding it is found to be in, which is given
    /// back: UTF-16 with a byte order mark, else UTF-8 if it is that, else
    /// ISO Latin 1, which any bytes are.
    static func string(contentsOfFile path: String, usedEncoding: UnsafeMutablePointer<UInt>?, error: UnsafeMutablePointer<id?>?) -> String? {
        guard let data = try? Data(contentsOf: URL(filePath: path)) else {
            error?.pointee = Errors.autoreleased(domain: Errors.cocoaDomain, code: 260, description: "The file couldn’t be opened.")
            return nil
        }
        let marked = data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff])
        for encoding: UInt in marked ? [10, 4, 5] : [4, 5] {
            guard let decoded = data.withUnsafeBytes({ StringEncoding.decode($0, encoding) }) else { continue }
            usedEncoding?.pointee = encoding
            return decoded
        }
        error?.pointee = Errors.autoreleased(domain: Errors.cocoaDomain, code: 264, description: "The file couldn’t be opened because its text encoding couldn’t be determined.")
        return nil
    }

    /// The forms from before Mac OS X 10.4, with no encoding: it is found
    /// as for usedEncoding.
    @ObjCClassMethod("stringWithContentsOfFile:")
    static func string(contentsOfFile path: String?) -> String? {
        path.flatMap { string(contentsOfFile: $0, usedEncoding: nil, error: nil) }
    }

    @ObjCMethod("initWithContentsOfFile:")
    func initialize(contentsOfFile path: String?) -> Self? {
        guard let path, let decoded = Self.string(contentsOfFile: path, usedEncoding: nil, error: nil) else { return nil }
        Storage.set(objcObject, StringStorage(decoded))
        return self
    }

    @ObjCClassMethod("stringWithContentsOfFile:usedEncoding:error:")
    static func string(contentsOfFile path: String?, used encoding: UnsafeMutablePointer<UInt>?, error: UnsafeMutablePointer<id?>?) -> String? {
        path.flatMap { string(contentsOfFile: $0, usedEncoding: encoding, error: error) }
    }

    @ObjCMethod("initWithContentsOfFile:usedEncoding:error:")
    func initialize(contentsOfFile path: String?, usedEncoding: UnsafeMutablePointer<UInt>?, error: UnsafeMutablePointer<id?>?) -> Self? {
        guard let path, let decoded = Self.string(contentsOfFile: path, usedEncoding: usedEncoding, error: error) else { return nil }
        Storage.set(objcObject, StringStorage(decoded))
        return self
    }

    @ObjCClassMethod("stringWithContentsOfURL:usedEncoding:error:")
    static func string(contentsOfURL url: NSURL?, used encoding: UnsafeMutablePointer<UInt>?, error: UnsafeMutablePointer<id?>?) -> String? {
        guard let url, url.url.isFileURL else {
            error?.pointee = Errors.autoreleased(domain: Errors.cocoaDomain, code: 260, description: "The file couldn’t be opened.")
            return nil
        }
        return string(contentsOfFile: FileManagers.path(url.url), usedEncoding: encoding, error: error)
    }

    @ObjCMethod("initWithContentsOfURL:usedEncoding:error:")
    func initialize(contentsOfURL url: NSURL?, usedEncoding: UnsafeMutablePointer<UInt>?, error: UnsafeMutablePointer<id?>?) -> Self? {
        guard let decoded = Self.string(contentsOfURL: url, used: usedEncoding, error: error) else { return nil }
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

    /// Before Mac OS X 10.5's encodings: written as UTF-8.
    @ObjCMethod("writeToFile:atomically:")
    func write(toFile path: String?, atomically: Bool) -> Bool {
        guard let path else { return false }
        return write(toFile: path, atomically: atomically, encoding: 4, error: nil)
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

    /// A nil component appends nothing.
    @ObjCMethod("stringByAppendingPathComponent:")
    func appending(pathComponent component: String?) -> String {
        guard let component, !component.isEmpty else { return value }
        return Paths.appending(value, component)
    }

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

    /// The home folder at the start of the path as "~".
    @ObjCMethod("stringByAbbreviatingWithTildeInPath")
    func abbreviatingWithTilde() -> String {
        guard let home = getenv("HOME").map({ String(cString: $0) }), !home.isEmpty, home != "/" else { return value }
        let trimmed = home.hasSuffix("/") ? String(home.dropLast()) : home
        if value == trimmed { return "~" }
        return value.hasPrefix(trimmed + "/") ? "~" + value.dropFirst(trimmed.count) : value
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

    /// The search within `scope`, as the locale compares: the locale is
    /// not consulted here.
    @ObjCMethod("rangeOfString:options:range:locale:")
    func range(of other: String, options: UInt, range scope: NSRange, locale: ObjCObject?) -> NSRange {
        range(of: other, options: options, range: scope)
    }

    @ObjCMethod("containsString:")
    func contains(_ other: String) -> Bool { range(of: other).location != notFound }

    /// Whether the string contains `other`, ignoring case, as the user's
    /// locale compares: case is folded here, whatever the locale.
    @ObjCMethod("localizedCaseInsensitiveContainsString:")
    func localizedCaseInsensitiveContains(_ other: String) -> Bool { value.lowercased().contains(other.lowercased()) }

    /// Whether the string contains `other` as a search in Finder finds it:
    /// ignoring case here.
    @ObjCMethod("localizedStandardContainsString:")
    func localizedStandardContains(_ other: String) -> Bool { localizedCaseInsensitiveContains(other) }

    @ObjCMethod("componentsSeparatedByString:")
    func components(separatedBy separator: String) -> NSArray {
        Arrays.owned(Self.components(of: value, separatedBy: separator).map { Strings.autoreleased($0) })
    }

    /// The parts between each separator, matched by UTF-16 units as
    /// NSString matches: Swift's own split matches whole characters, and
    /// "\r\n" is one, so "\n" would not split CRLF lines.
    static func components(of string: String, separatedBy separator: String) -> [String] {
        let text = Array(string.utf16), mark = Array(separator.utf16)
        guard !mark.isEmpty, text.count >= mark.count else { return [string] }
        var parts: [String] = [], start = 0, index = 0
        while index + mark.count <= text.count {
            if text[index] == mark[0], text[index..<index + mark.count].elementsEqual(mark) {
                parts.append(String(decoding: text[start..<index], as: UTF16.self))
                index += mark.count
                start = index
            } else {
                index += 1
            }
        }
        parts.append(String(decoding: text[start...], as: UTF16.self))
        return parts
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

    // MARK: Enumerating substrings

    /// The pieces of `range` an enumeration option names, each as its own
    /// range and its enclosing range (with the line terminator, or the
    /// space and punctuation up to the next word). Words are runs of
    /// letters, digits and apostrophes; sentences end at ., ! or ? and the
    /// spaces after them.
    private func substrings(in range: NSRange, kind: UInt) -> [(range: Range<Int>, enclosing: Range<Int>)] {
        let units = Array(value.utf16)
        let start = Int(range.location), end = min(units.count, start + Int(range.length))
        guard start < end else { return [] }
        var pieces: [(Range<Int>, Range<Int>)] = []
        func isLineBreak(_ unit: UInt16, paragraphs: Bool) -> Bool {
            unit == 10 || unit == 13 || unit == 0x2029 || (!paragraphs && (unit == 0x2028 || unit == 0x85))
        }
        switch kind {
        case 0, 1:      // lines, paragraphs
            var lineStart = start, index = start
            while index < end {
                if isLineBreak(units[index], paragraphs: kind == 1) {
                    var after = index + 1
                    if units[index] == 13, after < end, units[after] == 10 { after += 1 }
                    pieces.append((lineStart..<index, lineStart..<after))
                    lineStart = after
                    index = after
                } else {
                    index += 1
                }
            }
            if lineStart < end { pieces.append((lineStart..<end, lineStart..<end)) }
        case 2:         // composed character sequences
            var offset = 0
            for character in value {
                let length = character.utf16.count
                if offset + length > start && offset < end { pieces.append((offset..<offset + length, offset..<offset + length)) }
                offset += length
            }
        case 3, 4:      // words, sentences
            let characters = Array(String(decoding: units[start..<end], as: UTF16.self))
            var offsets = [start]
            for character in characters { offsets.append(offsets.last! + character.utf16.count) }
            func isWordCharacter(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "'" || c == "’" }
            var index = 0
            while index < characters.count {
                if kind == 3 {
                    guard isWordCharacter(characters[index]) else { index += 1; continue }
                    let first = index
                    while index < characters.count, isWordCharacter(characters[index]) { index += 1 }
                    var enclosing = index
                    while enclosing < characters.count, !isWordCharacter(characters[enclosing]) { enclosing += 1 }
                    pieces.append((offsets[first]..<offsets[index], offsets[first]..<offsets[enclosing]))
                } else {
                    let first = index
                    while index < characters.count, !".!?".contains(characters[index]) { index += 1 }
                    while index < characters.count, ".!?".contains(characters[index]) { index += 1 }
                    let last = index
                    while index < characters.count, characters[index].isWhitespace { index += 1 }
                    pieces.append((offsets[first]..<offsets[last], offsets[first]..<offsets[index]))
                }
            }
        default:
            break
        }
        return pieces
    }

    /// NSStringEnumerationOptions: the kind in the low byte, reverse 1 << 8,
    /// substring not required 1 << 9. The block takes the substring, its
    /// range and enclosing range, and a stop flag.
    @ObjCMethod("enumerateSubstringsInRange:options:usingBlock:")
    func enumerateSubstrings(in range: NSRange, options: UInt, using block: ObjCBlock) {
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UInt, UInt, UInt, UInt,
                                          UnsafeMutablePointer<Bool>) -> Void
        let invoke = block.function(as: Invoke.self)
        var pieces = substrings(in: range, kind: options & 0xff)
        if options & (1 << 8) != 0 { pieces.reverse() }
        let units = Array(value.utf16)
        var stop = false
        for piece in pieces {
            let substring = options & (1 << 9) != 0 ? nil
                : Strings.autoreleased(String(decoding: units[piece.range], as: UTF16.self))
            invoke(block.object, substring, UInt(piece.range.lowerBound), UInt(piece.range.count),
                   UInt(piece.enclosing.lowerBound), UInt(piece.enclosing.count), &stop)
            if stop { break }
        }
    }

    /// The block takes each line, without its terminator, and a stop flag.
    @ObjCMethod("enumerateLinesUsingBlock:")
    func enumerateLines(using block: ObjCBlock) {
        typealias Invoke = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutablePointer<Bool>) -> Void
        let invoke = block.function(as: Invoke.self)
        let units = Array(value.utf16)
        var stop = false
        for piece in substrings(in: NSRange(location: 0, length: UInt(units.count)), kind: 0) {
            invoke(block.object, Strings.autoreleased(String(decoding: units[piece.range], as: UTF16.self)), &stop)
            if stop { break }
        }
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

    /// The range's characters, through the string's UTF-16 view, which
    /// Swift indexes from breadcrumbs: no copy of the whole string, as a
    /// parser taking a substring at a time from a long one would make.
    @ObjCMethod("substringWithRange:")
    func substring(range: NSRange) -> String {
        let units = value.utf16
        let count = units.count
        if Int(range.location) > count || Int(range.length) > count - Int(range.location) {
            foundationFatal("-[NSString substringWithRange:]: Range {\(range.location), \(range.length)} out of bounds; string length \(count)")
        }
        let start = units.index(units.startIndex, offsetBy: Int(range.location))
        let end = units.index(start, offsetBy: Int(range.length))
        return String(decoding: units[start..<end], as: UTF16.self)
    }

    @ObjCMethod("caseInsensitiveCompare:")
    func caseInsensitiveCompare(_ other: String?) -> Int { Strings.compare(value.lowercased(), (other ?? "").lowercased()) }

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
    func localizedCompare(_ other: String?) -> Int { Strings.compare(value, other ?? "") }

    @ObjCMethod("localizedCaseInsensitiveCompare:")
    func localizedCaseInsensitiveCompare(_ other: String?) -> Int { Strings.compare(value.lowercased(), (other ?? "").lowercased()) }

    @ObjCMethod("localizedStandardCompare:")
    func localizedStandardCompare(_ other: String?) -> Int { Strings.numericCompare(value.lowercased(), (other ?? "").lowercased()) }

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

    // Unicode's normalization forms, by ICU: composed or decomposed, with
    // canonical or compatibility mappings. A string ICU can't normalize is
    // given back as it is.
    private func normalized(_ normalizer: (UnsafeMutablePointer<Int32>?) -> UnsafeRawPointer?) -> String {
        var status: Int32 = 0
        guard let form = normalizer(&status), status <= 0 else { return value }
        let units = Array(value.utf16)
        var result = [UInt16](repeating: 0, count: units.count * 2 + 16)
        var length = swift_unorm2_normalize(form, units, Int32(units.count), &result, Int32(result.count), &status)
        if status == 15 {   // U_BUFFER_OVERFLOW_ERROR: it says how long
            status = 0
            result = [UInt16](repeating: 0, count: Int(length) + 1)
            length = swift_unorm2_normalize(form, units, Int32(units.count), &result, Int32(result.count), &status)
        }
        guard status <= 0, length >= 0 else { return value }
        return String(decoding: result.prefix(Int(length)), as: UTF16.self)
    }

    @ObjCMethod("precomposedStringWithCanonicalMapping")
    func precomposedStringWithCanonicalMapping() -> String { normalized(swift_unorm2_getNFCInstance) }

    @ObjCMethod("decomposedStringWithCanonicalMapping")
    func decomposedStringWithCanonicalMapping() -> String { normalized(swift_unorm2_getNFDInstance) }

    @ObjCMethod("precomposedStringWithCompatibilityMapping")
    func precomposedStringWithCompatibilityMapping() -> String { normalized(swift_unorm2_getNFKCInstance) }

    @ObjCMethod("decomposedStringWithCompatibilityMapping")
    func decomposedStringWithCompatibilityMapping() -> String { normalized(swift_unorm2_getNFKDInstance) }

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

// MARK: - Encoding detection

/// +stringEncodingForData:encodingOptions:convertedString:usedLossyConversion:
/// as Darwin answers it: a byte order mark's encoding, then the suggested
/// encodings in order, then ASCII, UTF-8 and, for other bytes, Windows
/// Latin 1 or ISO Latin 1; the first that converts the bytes. With
/// NSStringEncodingDetectionUseOnlySuggestedEncodingsKey only the suggested
/// ones are tried. Encodings in the disallowed list are skipped. When none
/// converts, lossy conversion (allowed unless the options say not) gives
/// UTF-8 with the substitution string for what doesn't convert. ASCII, as
/// CoreFoundation converts it, takes bytes above 127 as ISO Latin 1.
enum StringEncodingDetection {
    static let suggestedKey = "NSStringEncodingDetectionSuggestedEncodingsKey"
    static let disallowedKey = "NSStringEncodingDetectionDisallowedEncodingsKey"
    static let onlySuggestedKey = "NSStringEncodingDetectionUseOnlySuggestedEncodingsKey"
    static let allowLossyKey = "NSStringEncodingDetectionAllowLossyKey"
    static let fromWindowsKey = "NSStringEncodingDetectionFromWindowsKey"
    static let substitutionKey = "NSStringEncodingDetectionLossySubstitutionKey"

    struct Result {
        var encoding: UInt
        var string: String?
        var lossy = false
    }

    private static func option(_ options: id?, _ key: String) -> id? {
        Dictionaries.value(options, for: Strings.autoreleased(key))
    }

    private static func flag(_ options: id?, _ key: String) -> Bool? {
        option(options, key).map { ObjC.sendBool($0, ObjC.selector("boolValue"), nil) }
    }

    private static func encodings(_ options: id?, _ key: String) -> [UInt] {
        Arrays.elements(option(options, key)).map { ObjC.sendUInt($0, ObjC.selector("unsignedIntegerValue")) }
    }

    /// The bytes in an encoding, as detection converts them.
    static func decode(_ bytes: [UInt8], _ encoding: UInt) -> String? {
        switch encoding {
        case StringEncoding.ascii:
            return bytes.withUnsafeBytes { StringEncoding.decode($0, StringEncoding.isoLatin1) }
        case StringEncoding.utf8:
            let body = bytes.starts(with: [0xef, 0xbb, 0xbf]) ? Array(bytes.dropFirst(3)) : bytes
            return body.withUnsafeBytes { StringEncoding.decode($0, StringEncoding.utf8) }
        case StringEncoding.unicode:
            guard bytes.count % 2 == 0 else { return nil }
            return bytes.withUnsafeBytes { StringEncoding.decode($0, StringEncoding.unicode) }
        case 12:
            // Windows Latin 1 leaves five bytes undefined.
            guard !bytes.contains(where: { [0x81, 0x8d, 0x8f, 0x90, 0x9d].contains($0) }) else { return nil }
            return bytes.withUnsafeBytes { StringEncoding.decode($0, 12) }
        default:
            return bytes.withUnsafeBytes { StringEncoding.decode($0, encoding) }
        }
    }

    static func detect(_ bytes: [UInt8], options: id?) -> Result {
        let suggested = encodings(options, suggestedKey), disallowed = Set(encodings(options, disallowedKey))
        let onlySuggested = flag(options, onlySuggestedKey) ?? false
        let allowLossy = flag(options, allowLossyKey) ?? true
        var candidates: [UInt] = []
        func add(_ encoding: UInt) {
            if !disallowed.contains(encoding), !candidates.contains(encoding) { candidates.append(encoding) }
        }
        if !onlySuggested {
            if bytes.starts(with: [0xef, 0xbb, 0xbf]) { add(StringEncoding.utf8) }
            if bytes.starts(with: [0xff, 0xfe, 0, 0]) || bytes.starts(with: [0, 0, 0xfe, 0xff]) { add(StringEncoding.utf32) }
            if bytes.starts(with: [0xff, 0xfe]) || bytes.starts(with: [0xfe, 0xff]) { add(StringEncoding.unicode) }
        }
        suggested.forEach(add)
        if !onlySuggested {
            if bytes.isEmpty || bytes.contains(where: { $0 >= 0x80 }) {
                add(StringEncoding.utf8)
            } else {
                add(StringEncoding.ascii)
            }
            add(StringEncoding.utf8)
            if flag(options, fromWindowsKey) ?? false || bytes.contains(where: { (0x80...0x9f).contains($0) }) { add(12) }
            add(StringEncoding.isoLatin1)
        }
        for encoding in candidates {
            if let string = decode(bytes, encoding) { return Result(encoding: encoding, string: string) }
        }
        guard allowLossy, let first = candidates.first else {
            // Darwin names the first encoding it tried, with no string.
            return Result(encoding: onlySuggested ? (candidates.first ?? 0) : 0, string: nil)
        }
        let substitution = Strings.value(of: option(options, substitutionKey)) ?? "\u{FFFD}"
        let encoding = candidates.contains(StringEncoding.utf8) ? StringEncoding.utf8 : first
        guard encoding == StringEncoding.utf8 else { return Result(encoding: encoding, string: nil) }
        return Result(encoding: encoding, string: lossyUTF8(bytes, substitution), lossy: true)
    }

    /// UTF-8, each ill-formed sequence replaced by `substitution`.
    private static func lossyUTF8(_ bytes: [UInt8], _ substitution: String) -> String {
        var result = ""
        var iterator = bytes.makeIterator()
        var decoder = UTF8()
        loop: while true {
            switch decoder.decode(&iterator) {
            case .scalarValue(let scalar): result.unicodeScalars.append(scalar)
            case .error: result += substitution
            case .emptyInput: break loop
            }
        }
        return result
    }
}

// MARK: - Transforms

// The transforms' and the detection options' names are in
// FoundationConstantsMore.swift.

/// Folding and comparing as NSString's options say.
enum StringFolding {
    static let caseInsensitive: UInt = 1, diacriticInsensitive: UInt = 128, widthInsensitive: UInt = 256

    /// Canonically decomposed, by ICU.
    static func decomposed(_ text: String) -> String {
        var status: Int32 = 0
        guard let form = swift_unorm2_getNFDInstance(&status), status <= 0 else { return text }
        let units = Array(text.utf16)
        var result = [UInt16](repeating: 0, count: units.count * 4 + 16)
        let length = swift_unorm2_normalize(form, units, Int32(units.count), &result, Int32(result.count), &status)
        guard status <= 0, length >= 0 else { return text }
        return String(decoding: result.prefix(Int(length)), as: UTF16.self)
    }

    /// The text folded: case to lower case, diacritics removed (combining
    /// marks after canonical decomposition), full-width forms to their
    /// ASCII and space.
    static func fold(_ text: String, _ options: UInt) -> String {
        var result = text
        if options & diacriticInsensitive != 0 {
            let marks = decomposed(result).unicodeScalars.filter { $0.properties.generalCategory != .nonspacingMark }
            result = String(String.UnicodeScalarView(marks)).precomposedNFC
        }
        if options & widthInsensitive != 0 {
            result = String(String.UnicodeScalarView(result.unicodeScalars.map { scalar -> Unicode.Scalar in
                switch scalar.value {
                case 0xFF01...0xFF5E: return Unicode.Scalar(scalar.value - 0xFEE0)!
                case 0x3000: return " "
                default: return scalar
                }
            }))
        }
        if options & caseInsensitive != 0 { result = result.lowercased() }
        return result
    }
}

private extension String {
    /// Canonically composed, by ICU.
    var precomposedNFC: String {
        var status: Int32 = 0
        guard let form = swift_unorm2_getNFCInstance(&status), status <= 0 else { return self }
        let units = Array(utf16)
        var result = [UInt16](repeating: 0, count: units.count * 2 + 16)
        let length = swift_unorm2_normalize(form, units, Int32(units.count), &result, Int32(result.count), &status)
        guard status <= 0, length >= 0 else { return self }
        return String(decoding: result.prefix(Int(length)), as: UTF16.self)
    }
}

/// NSString's encoding detection, folding, transforms and the C string
/// methods from before encodings.
@ObjCCategory("StringConversions")
extension NSString {
    /// The encoding the data is most likely in, or 0; the string it makes
    /// and whether that was lossy. See StringEncodingDetection.
    @ObjCClassMethod("stringEncodingForData:encodingOptions:convertedString:usedLossyConversion:")
    static func stringEncoding(forData data: NSData?, encodingOptions options: UnsafeMutableRawPointer?,
                               convertedString: UnsafeMutablePointer<id?>?, usedLossyConversion: UnsafeMutablePointer<Bool>?) -> UInt {
        let result = StringEncodingDetection.detect(Array(data?.data ?? Data()), options: options)
        convertedString?.pointee = result.string.map { Strings.autoreleased($0) }
        usedLossyConversion?.pointee = result.lossy
        return result.encoding
    }

    // MARK: C strings before encodings

    /// `length` bytes in the default C string encoding.
    private static func decodeDefault(_ bytes: UnsafeRawPointer?, length: UInt) -> String {
        guard let bytes else { return "" }
        let buffer = UnsafeRawBufferPointer(start: bytes, count: Int(length))
        return StringEncoding.decode(buffer, StringEncoding.utf8) ?? StringEncoding.decode(buffer, StringEncoding.isoLatin1) ?? ""
    }

    @ObjCClassMethod("stringWithCString:length:")
    static func string(_ cls: ObjCClass, cString: UnsafePointer<CChar>?, length: UInt) -> ObjCObject? {
        cString.map { ObjCObject(Strings.autoreleased(decodeDefault($0, length: length), of: cls.pointer)) }
    }

    @ObjCMethod("initWithCString:length:")
    func initialize(cString: UnsafePointer<CChar>?, length: UInt) -> Self? {
        guard let cString else { return nil }
        Storage.set(objcObject, StringStorage(NSString.decodeDefault(cString, length: length)))
        return self
    }

    /// The bytes are copied, then freed if the string was to own them.
    @ObjCMethod("initWithCStringNoCopy:length:freeWhenDone:")
    func initialize(cStringNoCopy bytes: UnsafeMutablePointer<CChar>?, length: UInt, freeWhenDone: Bool) -> Self? {
        guard let bytes else { return nil }
        Storage.set(objcObject, StringStorage(NSString.decodeDefault(bytes, length: length)))
        if freeWhenDone { free(bytes) }
        return self
    }

    /// In the default C string encoding, UTF-8, which loses nothing.
    @ObjCMethod("lossyCString")
    func lossyCString() -> UnsafePointer<CChar>? { Strings.utf8(objcObject) }

    /// The characters of `range` in the default C string encoding, as many
    /// whole characters as fit in `maxLength` bytes, then a zero; the rest
    /// of the range is given back.
    @ObjCMethod("getCString:maxLength:range:remainingRange:")
    func getCString(_ buffer: UnsafeMutablePointer<CChar>?, maxLength: UInt, range: NSRange, remainingRange: UnsafeMutablePointer<NSRange>?) {
        guard let buffer else { return }
        let units = Array(value.utf16)
        let start = min(Int(range.location), units.count), end = min(start + Int(range.length), units.count)
        var used = 0, index = start
        while index < end {
            let width = UTF16.isLeadSurrogate(units[index]) && index + 1 < end ? 2 : 1
            let bytes = Array(String(decoding: units[index..<index + width], as: UTF16.self).utf8)
            guard used + bytes.count <= Int(maxLength) else { break }
            for byte in bytes {
                buffer[used] = CChar(bitPattern: byte)
                used += 1
            }
            index += width
        }
        buffer[used] = 0
        remainingRange?.pointee = NSRange(location: UInt(index), length: UInt(end - index))
    }

    /// The smallest encoding that holds the string without loss: ASCII,
    /// else Mac OS Roman, else Unicode.
    @ObjCMethod("smallestEncoding")
    func smallestEncoding() -> UInt {
        if value.unicodeScalars.allSatisfy(\.isASCII) { return StringEncoding.ascii }
        if StringEncoding.encode(value, 30) != nil { return 30 }
        return StringEncoding.unicode
    }

    // MARK: No-copy strings with deallocators

    /// The bytes are copied, so the deallocator is called with them at
    /// once rather than when the string goes; a string that can't be made
    /// leaves them to the caller.
    @ObjCMethod("initWithBytesNoCopy:length:encoding:deallocator:")
    func initialize(bytesNoCopy bytes: UnsafeMutableRawPointer?, length: UInt, encoding: UInt, deallocator: UnsafeMutableRawPointer?) -> Self? {
        guard let decoded = StringEncoding.decode(UnsafeRawBufferPointer(start: bytes, count: Int(length)), encoding) else { return nil }
        Storage.set(objcObject, StringStorage(decoded))
        if let deallocator {
            Blocks.invoke(deallocator, as: (@convention(c) (id, UnsafeMutableRawPointer?, UInt) -> Void).self)(deallocator, bytes, length)
        }
        return self
    }

    @ObjCMethod("initWithCharactersNoCopy:length:deallocator:")
    func initialize(charactersNoCopy characters: UnsafeMutablePointer<UInt16>?, length: UInt, deallocator: UnsafeMutableRawPointer?) -> Self {
        let text = characters.map { String(decoding: UnsafeBufferPointer(start: $0, count: Int(length)), as: UTF16.self) } ?? ""
        Storage.set(objcObject, StringStorage(text))
        if let deallocator {
            Blocks.invoke(deallocator, as: (@convention(c) (id, UnsafeMutablePointer<UInt16>?, UInt) -> Void).self)(deallocator, characters, length)
        }
        return self
    }

    // MARK: Folding and comparing

    /// The longest prefix both strings share, in whole characters compared
    /// as the options fold them (canonically equivalent ones match); the
    /// receiver's own characters.
    @ObjCMethod("commonPrefixWithString:options:")
    func commonPrefix(with other: String?, options: UInt) -> String {
        var prefix = ""
        for (mine, theirs) in zip(value, other ?? "") {
            guard mine == theirs || StringFolding.fold(String(mine), options) == StringFolding.fold(String(theirs), options) else { break }
            prefix.append(mine)
        }
        return prefix
    }

    @ObjCMethod("stringByFoldingWithOptions:locale:")
    func folding(options: UInt, locale: ObjCObject?) -> String { StringFolding.fold(value, options) }

    /// The range of `other` as a search in Finder finds it: ignoring case,
    /// diacritics and width, on whole characters.
    @ObjCMethod("localizedStandardRangeOfString:")
    func localizedStandardRange(of other: String?) -> NSRange {
        let options = StringFolding.caseInsensitive | StringFolding.diacriticInsensitive | StringFolding.widthInsensitive
        let needle = Array(StringFolding.fold(other ?? "", options).utf16)
        guard !needle.isEmpty else { return NSRange(location: notFound, length: 0) }
        // Each character folded, where it starts in the string, and where
        // it starts in the folded text.
        var folded: [UInt16] = [], starts: [(original: Int, folded: Int, length: Int)] = []
        var offset = 0
        for character in value {
            let units = String(character).utf16.count
            starts.append((offset, folded.count, units))
            folded += StringFolding.fold(String(character), options).utf16
            offset += units
        }
        guard needle.count <= folded.count else { return NSRange(location: notFound, length: 0) }
        for (index, start) in starts.enumerated() where folded.count - start.folded >= needle.count {
            guard Array(folded[start.folded..<start.folded + needle.count]) == needle else { continue }
            // The match must end where a character's folding ends.
            let end = start.folded + needle.count
            var last: Int?
            for candidate in index..<starts.count {
                let foldedEnd = candidate + 1 < starts.count ? starts[candidate + 1].folded : folded.count
                if foldedEnd == end { last = candidate }
                if foldedEnd >= end { break }
            }
            guard let last else { continue }
            let tail = starts[last]
            return NSRange(location: UInt(start.original), length: UInt(tail.original + tail.length - start.original))
        }
        return NSRange(location: notFound, length: 0)
    }

    // MARK: Transforms

    /// The string through an ICU transform (NSStringTransform's names
    /// are ICU's IDs), or nil for one ICU doesn't know.
    @ObjCMethod("stringByApplyingTransform:reverse:")
    func applyingTransform(_ transform: String?, reverse: Bool) -> String? {
        guard let transform else { return nil }
        return ICUTransforms.apply(transform, to: value, reverse: reverse)
    }

    // MARK: Paths

    @ObjCMethod("stringsByAppendingPaths:")
    func appendingPaths(_ paths: NSArray?) -> NSArray {
        let paths = Arrays.elements(paths?.objcObject).compactMap { Strings.value(of: $0) }
        return Arrays.owned(paths.map { Strings.autoreleased(Paths.appending(value, $0)) })
    }

    /// The paths in the receiver's directory that begin with its last
    /// component (and have one of the extensions, when there are some):
    /// the longest prefix they share, the matches sorted, and their count.
    @ObjCMethod("completePathIntoString:caseSensitive:matchesIntoArray:filterTypes:")
    func completePath(into outputName: UnsafeMutablePointer<id?>?, caseSensitive: Bool, matchesInto matches: UnsafeMutablePointer<id?>?,
                      filterTypes: NSArray?) -> UInt {
        let path = expandingTilde()
        guard !path.isEmpty else { return 0 }
        let directory = path.hasSuffix("/") ? path : Paths.deletingLastComponent(path)
        let partial = path.hasSuffix("/") ? "" : Paths.lastComponent(path)
        let types = Set(Arrays.elements(filterTypes?.objcObject).compactMap { Strings.value(of: $0) })
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.isEmpty ? "." : directory)) ?? []
        let fold: (String) -> String = { caseSensitive ? $0 : $0.lowercased() }
        let found = names.filter { name in
            fold(name).hasPrefix(fold(partial)) && (types.isEmpty || types.contains(Paths.pathExtension(name)))
        }.sorted().map { directory.isEmpty ? $0 : Paths.appending(directory, $0) }
        guard !found.isEmpty else { return 0 }
        if let outputName {
            var common = Array(found[0])
            for candidate in found.dropFirst() {
                let other = Array(candidate)
                var length = 0
                while length < common.count, length < other.count, fold(String(common[length])) == fold(String(other[length])) { length += 1 }
                common = Array(common.prefix(length))
            }
            outputName.pointee = Strings.autoreleased(String(common))
        }
        matches?.pointee = Arrays.autoreleased(found.map { Strings.autoreleased($0) })
        return UInt(found.count)
    }

    // MARK: Contents of URLs

    /// A file URL's text in the encoding it is found to be in.
    @ObjCClassMethod("stringWithContentsOfURL:")
    static func string(_ cls: ObjCClass, contentsOfURL url: NSURL?) -> ObjCObject? {
        string(contentsOfURL: url, used: nil, error: nil).map { ObjCObject(Strings.autoreleased($0, of: cls.pointer)) }
    }

    @ObjCMethod("initWithContentsOfURL:")
    func initialize(contentsOfURL url: NSURL?) -> Self? {
        guard let decoded = Self.string(contentsOfURL: url, used: nil, error: nil) else { return nil }
        Storage.set(objcObject, StringStorage(decoded))
        return self
    }

    /// Written as UTF-8, to file URLs only.
    @ObjCMethod("writeToURL:atomically:")
    func write(to url: NSURL?, atomically: Bool) -> Bool {
        guard let url else { return false }
        return write(to: url, atomically: atomically, encoding: StringEncoding.utf8, error: nil)
    }

    // MARK: Variants and linguistic tags

    /// A string with no width variants (only stringsdict files make them)
    /// is its own.
    @ObjCMethod("variantFittingPresentationWidth:")
    func variantFitting(presentationWidth width: Int) -> NSString { self }

    /// A tagger of the one scheme over the string, autoreleased.
    private func tagger(_ scheme: id?, orthography: id?) -> id? {
        guard let cls = "NSLinguisticTagger".withCString({ ObjC.getClass($0) }),
              let allocated = ObjC.send(UnsafeMutableRawPointer(cls), ObjC.selector("alloc")) else { return nil }
        typealias Initialize = @convention(c) (id?, SEL, id?, UInt) -> id?
        let schemes = Arrays.autoreleased(scheme.map { [$0] } ?? [])
        let tagger = unsafeBitCast(ObjC.msgSend, to: Initialize.self)(allocated, ObjC.selector("initWithTagSchemes:options:"), schemes, 0)
        _ = ObjC.send(tagger, ObjC.selector("setString:"), objcObject)
        if let orthography {
            typealias SetOrthography = @convention(c) (id?, SEL, id?, NSRange) -> Void
            unsafeBitCast(ObjC.msgSend, to: SetOrthography.self)(tagger, ObjC.selector("setOrthography:range:"), orthography,
                                                                  NSRange(location: 0, length: UInt(value.utf16.count)))
        }
        return ObjC.autorelease(tagger)
    }

    /// NSLinguisticTagger's tags of the range, by word, as it gives them.
    @ObjCMethod("enumerateLinguisticTagsInRange:scheme:options:orthography:usingBlock:")
    func enumerateLinguisticTags(in range: NSRange, scheme: UnsafeMutableRawPointer?, options: UInt, orthography: UnsafeMutableRawPointer?,
                                 using block: UnsafeMutableRawPointer?) {
        guard let tagger = tagger(scheme, orthography: orthography) else { return }
        typealias Enumerate = @convention(c) (id?, SEL, NSRange, id?, UInt, id?) -> Void
        unsafeBitCast(ObjC.msgSend, to: Enumerate.self)(tagger, ObjC.selector("enumerateTagsInRange:scheme:options:usingBlock:"), range,
                                                        scheme, options, block)
    }

    @ObjCMethod("linguisticTagsInRange:scheme:options:orthography:tokenRanges:")
    func linguisticTags(in range: NSRange, scheme: UnsafeMutableRawPointer?, options: UInt, orthography: UnsafeMutableRawPointer?,
                        tokenRanges: UnsafeMutablePointer<id?>?) -> UnsafeMutableRawPointer? {
        guard let tagger = tagger(scheme, orthography: orthography) else { return Arrays.autoreleased([]) }
        typealias Tags = @convention(c) (id?, SEL, NSRange, id?, UInt, UnsafeMutablePointer<id?>?) -> id?
        return unsafeBitCast(ObjC.msgSend, to: Tags.self)(tagger, ObjC.selector("tagsInRange:scheme:options:tokenRanges:"), range, scheme,
                                                          options, tokenRanges)
    }
}
