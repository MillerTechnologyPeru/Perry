import CPerryFoundation
import FoundationEssentials
import Glibc
import PerryObjCInterop

// CFString over NSString and NSMutableString: creation from C strings,
// bytes and formats, comparing and searching, mutation, and conversion
// between CFStringEncodings and the bytes they stand for.

enum CFStringEncodings {
    static let macRoman: UInt32 = 0, windowsLatin1: UInt32 = 0x0500, isoLatin1: UInt32 = 0x0201, ascii: UInt32 = 0x0600
    static let utf8: UInt32 = 0x0800_0100, utf16: UInt32 = 0x0100, utf16BE: UInt32 = 0x1000_0100, utf16LE: UInt32 = 0x1400_0100
    static let utf32: UInt32 = 0x0C00_0100, utf32BE: UInt32 = 0x1800_0100, utf32LE: UInt32 = 0x1C00_0100
    static let nonLossyASCII: UInt32 = 0x0BFF

    private static let toNS: [UInt32: UInt] = [
        macRoman: 30, windowsLatin1: 12, isoLatin1: 5, ascii: 1, utf8: 4, utf16: 10, nonLossyASCII: 7,
        utf16BE: 0x9000_0100, utf16LE: 0x9400_0100, utf32: 0x8C00_0100, utf32BE: 0x9800_0100, utf32LE: 0x9C00_0100,
    ]

    static func nsEncoding(_ encoding: UInt32) -> UInt { toNS[encoding] ?? (0x8000_0000 | UInt(encoding)) }

    static func cfEncoding(_ encoding: UInt) -> UInt32 {
        if let match = toNS.first(where: { $0.value == encoding }) { return match.key }
        return encoding & 0x8000_0000 != 0 ? UInt32(encoding & 0x7FFF_FFFF) : 0xFFFF_FFFF
    }

    static let names: [UInt32: String] = [
        macRoman: "Western (Mac OS Roman)", windowsLatin1: "Western (Windows Latin 1)", isoLatin1: "Western (ISO Latin 1)",
        ascii: "Western (ASCII)", utf8: "Unicode (UTF-8)", utf16: "Unicode (UTF-16)", utf16BE: "Unicode (UTF-16BE)",
        utf16LE: "Unicode (UTF-16LE)", utf32: "Unicode (UTF-32)", utf32BE: "Unicode (UTF-32BE)", utf32LE: "Unicode (UTF-32LE)",
        nonLossyASCII: "Non-lossy ASCII",
    ]

    static func decode(_ bytes: UnsafeRawBufferPointer, _ encoding: UInt32) -> String? {
        switch encoding {
        case macRoman: return MacOSRoman.decode(Array(bytes))
        case windowsLatin1: return StringEncoding.decode(bytes, StringEncoding.isoLatin1)
        case utf32, utf32BE, utf32LE:
            var big = encoding == utf32BE
            var start = 0
            if encoding == utf32, bytes.count >= 4, bytes[0] == 0, bytes[1] == 0, bytes[2] == 0xfe, bytes[3] == 0xff {
                big = true
                start = 4
            } else if encoding == utf32, bytes.count >= 4, bytes[0] == 0xff, bytes[1] == 0xfe { start = 4 }
            var text = String.UnicodeScalarView()
            var index = start
            while index + 3 < bytes.count {
                let word = (0..<4).reduce(UInt32(0)) { value, offset in
                    value | UInt32(bytes[index + offset]) << (big ? 8 * (3 - offset) : 8 * offset)
                }
                guard let scalar = Unicode.Scalar(word) else { return nil }
                text.append(scalar)
                index += 4
            }
            return String(text)
        default: return StringEncoding.decode(bytes, nsEncoding(encoding))
        }
    }

    /// The bytes of `text`; with `lossByte`, characters the encoding lacks
    /// become it, else the conversion fails.
    static func encode(_ text: String, _ encoding: UInt32, lossByte: UInt8? = nil) -> [UInt8]? {
        switch encoding {
        case macRoman:
            var bytes: [UInt8] = []
            for scalar in text.unicodeScalars {
                if scalar.value < 0x80 { bytes.append(UInt8(scalar.value)) }
                else if let byte = MacOSRoman.byte(for: scalar) { bytes.append(byte) }
                else if let lossByte { bytes.append(lossByte) }
                else { return nil }
            }
            return bytes
        case ascii, isoLatin1, windowsLatin1:
            let limit: UInt32 = encoding == ascii ? 0x7f : 0xff
            var bytes: [UInt8] = []
            for scalar in text.unicodeScalars {
                if scalar.value <= limit { bytes.append(UInt8(scalar.value)) }
                else if let lossByte { bytes.append(lossByte) }
                else { return nil }
            }
            return bytes
        case utf16: return text.utf16.flatMap { [UInt8($0 & 0xff), UInt8($0 >> 8)] }
        case utf32, utf32LE: return text.unicodeScalars.flatMap { s in (0..<4).map { UInt8(truncatingIfNeeded: s.value >> (8 * $0)) } }
        case utf32BE: return text.unicodeScalars.flatMap { s in (0..<4).reversed().map { UInt8(truncatingIfNeeded: s.value >> (8 * $0)) } }
        default: return StringEncoding.encode(text, nsEncoding(encoding), lossy: lossByte != nil)
        }
    }
}

extension MacOSRoman {
    static func byte(for scalar: Unicode.Scalar) -> UInt8? {
        let high = Array(decode((0x80...0xFF).map { UInt8($0) }).unicodeScalars)
        return high.firstIndex(of: scalar).map { UInt8(0x80 + $0) }
    }
}

enum CFStrings {
    static func value(_ string: id?) -> String { Strings.value(of: string) ?? "" }
    static func units(_ string: id?) -> [UInt16] { Array(value(string).utf16) }
    static func string(_ units: some Collection<UInt16>) -> String { String(decoding: units, as: UTF16.self) }

    /// The text of a mutable string, changed in place.
    static func mutate(_ string: id?, _ change: (inout String) -> Void) {
        var text = value(string)
        change(&text)
        _ = ObjC.send(string, ObjC.selector("setString:"), Strings.autoreleased(text))
    }

    /// CFStringCompareFlags: case insensitive 1, backwards 4, anchored 8,
    /// nonliteral 16, localized 32, numerically 64.
    static func compare(_ a: String, _ b: String, _ flags: UInt) -> Int {
        let options = UInt(flags & ~(4 | 8))
        return unsafeBitCast(ObjC.msgSend, to: (@convention(c) (id?, SEL, id?, UInt) -> Int).self)(
            Strings.autoreleased(a), ObjC.selector("compare:options:"), Strings.autoreleased(b), options)
    }

    static func find(_ string: id?, _ target: id?, _ range: CFRange, _ flags: UInt) -> CFRange {
        let found = unsafeBitCast(ObjC.msgSend, to: (@convention(c) (id?, SEL, id?, UInt, NSRange) -> NSRange).self)(
            string, ObjC.selector("rangeOfString:options:range:"), target, flags & (1 | 4 | 8 | 64),
            NSRange(location: UInt(range.location), length: UInt(range.length)))
        return found.location == UInt(Int.max) ? CFRange(location: -1, length: 0)
                                               : CFRange(location: Int(found.location), length: Int(found.length))
    }

    static func whole(_ string: id?) -> CFRange { CFRange(location: 0, length: units(string).count) }
}

@c(_CFStringGetTypeID) public func CFStringGetTypeID() -> UInt { CFTypeIDs.string }

@c(_CFStringCreateWithCString)
public func CFStringCreateWithCString(_ allocator: UnsafeRawPointer?, _ cString: UnsafePointer<CChar>?, _ encoding: UInt32) -> id? {
    guard let cString else { return nil }
    return CFStringEncodings.decode(UnsafeRawBufferPointer(start: cString, count: strlen(cString)), encoding).map(Strings.make)
}

@c(_CFStringCreateWithCStringNoCopy)
public func CFStringCreateWithCStringNoCopy(_ allocator: UnsafeRawPointer?, _ cString: UnsafePointer<CChar>?, _ encoding: UInt32,
                                            _ deallocator: UnsafeRawPointer?) -> id? {
    CFStringCreateWithCString(allocator, cString, encoding)
}

@c(_CFStringCreateWithBytes)
public func CFStringCreateWithBytes(_ allocator: UnsafeRawPointer?, _ bytes: UnsafePointer<UInt8>?, _ length: Int, _ encoding: UInt32,
                                    _ externalRepresentation: Bool) -> id? {
    CFStringEncodings.decode(UnsafeRawBufferPointer(start: bytes, count: length), encoding).map(Strings.make)
}

@c(_CFStringCreateWithBytesNoCopy)
public func CFStringCreateWithBytesNoCopy(_ allocator: UnsafeRawPointer?, _ bytes: UnsafePointer<UInt8>?, _ length: Int,
                                          _ encoding: UInt32, _ externalRepresentation: Bool, _ deallocator: UnsafeRawPointer?) -> id? {
    CFStringCreateWithBytes(allocator, bytes, length, encoding, externalRepresentation)
}

@c(_CFStringCreateWithCharacters)
public func CFStringCreateWithCharacters(_ allocator: UnsafeRawPointer?, _ characters: UnsafePointer<UInt16>?, _ count: Int) -> id? {
    Strings.make(CFStrings.string(UnsafeBufferPointer(start: characters, count: count)))
}

@c(_CFStringCreateWithCharactersNoCopy)
public func CFStringCreateWithCharactersNoCopy(_ allocator: UnsafeRawPointer?, _ characters: UnsafePointer<UInt16>?, _ count: Int,
                                               _ deallocator: UnsafeRawPointer?) -> id? {
    CFStringCreateWithCharacters(allocator, characters, count)
}

@c(_CFStringCreateCopy)
public func CFStringCreateCopy(_ allocator: UnsafeRawPointer?, _ string: id?) -> id? { Strings.make(CFStrings.value(string)) }

@c(_CFStringCreateWithSubstring)
public func CFStringCreateWithSubstring(_ allocator: UnsafeRawPointer?, _ string: id?, _ range: CFRange) -> id? {
    Strings.make(CFStrings.string(CFStrings.units(string)[CFArrays.range(range)]))
}

@c(_CFStringCreateMutable)
public func CFStringCreateMutable(_ allocator: UnsafeRawPointer?, _ capacity: Int) -> id? { MutableStrings.make("") }

@c(_CFStringCreateMutableCopy)
public func CFStringCreateMutableCopy(_ allocator: UnsafeRawPointer?, _ capacity: Int, _ string: id?) -> id? {
    MutableStrings.make(CFStrings.value(string))
}

/// The variadic CFStringCreateWithFormat (variadic.S); a Darwin va_list is
/// a pointer to the argument slots, as for CFStringCreateWithFormatAndArguments.
@c
public func perry_foundation_cf_create_with_format(_ allocator: UnsafeRawPointer?, _ options: id?, _ format: id?,
                                                   _ arguments: UnsafeRawPointer?) -> id? {
    CFStringCreateWithFormatAndArguments(allocator, options, format, arguments)
}

@c(_CFStringCreateWithFormatAndArguments)
public func CFStringCreateWithFormatAndArguments(_ allocator: UnsafeRawPointer?, _ options: id?, _ format: id?,
                                                 _ arguments: UnsafeRawPointer?) -> id? {
    guard let arguments else { return Strings.make(CFStrings.value(format)) }
    var darwin = DarwinArguments(arguments)
    return Strings.make(Format.string(CFStrings.value(format), &darwin))
}

@c
public func perry_foundation_cf_append_format(_ string: id?, _ options: id?, _ format: id?, _ arguments: UnsafeRawPointer?) {
    CFStringAppendFormatAndArguments(string, options, format, arguments)
}

@c(_CFStringAppendFormatAndArguments)
public func CFStringAppendFormatAndArguments(_ string: id?, _ options: id?, _ format: id?, _ arguments: UnsafeRawPointer?) {
    guard let arguments else { return }
    var darwin = DarwinArguments(arguments)
    let text = Format.string(CFStrings.value(format), &darwin)
    CFStrings.mutate(string) { $0 += text }
}

/// Copies the string into the buffer with a terminating zero; false if it
/// does not fit or cannot be converted.
@c(_CFStringGetCString)
public func CFStringGetCString(_ string: id?, _ buffer: UnsafeMutablePointer<CChar>?, _ size: Int, _ encoding: UInt32) -> Bool {
    guard let buffer, let bytes = CFStringEncodings.encode(CFStrings.value(string), encoding), bytes.count < size else { return false }
    bytes.withUnsafeBytes { UnsafeMutableRawPointer(buffer).copyMemory(from: $0.baseAddress!, byteCount: bytes.count) }
    buffer[bytes.count] = 0
    return true
}

/// The string's own UTF-8 for that encoding; NULL for others, which
/// callers then copy with CFStringGetCString.
/// The string's UTF-8 bytes: for UTF-8, and for an ASCII string in any of
/// the 8-bit encodings ASCII is the start of, MacRoman among them, which
/// is what CoreFoundation keeps such a string in and names as its fastest.
@c(_CFStringGetCStringPtr)
public func CFStringGetCStringPtr(_ string: id?, _ encoding: UInt32) -> UnsafePointer<CChar>? {
    guard let string else { return nil }
    let eightBit = [CFStringEncodings.ascii, CFStringEncodings.macRoman, CFStringEncodings.isoLatin1, CFStringEncodings.windowsLatin1]
    guard encoding == CFStringEncodings.utf8 || eightBit.contains(encoding) && CFStrings.value(string).allSatisfy(\.isASCII)
    else { return nil }
    return Strings.utf8(string)
}

@c(_CFStringGetCharacterAtIndex)
public func CFStringGetCharacterAtIndex(_ string: id?, _ index: Int) -> UInt16 { CFStrings.units(string)[index] }

@c(_CFStringGetCharacters)
public func CFStringGetCharacters(_ string: id?, _ range: CFRange, _ buffer: UnsafeMutablePointer<UInt16>?) {
    let units = CFStrings.units(string)
    for (offset, index) in CFArrays.range(range).enumerated() { buffer?[offset] = units[index] }
}

@c(_CFStringGetCharactersPtr) public func CFStringGetCharactersPtr(_ string: id?) -> UnsafePointer<UInt16>? { nil }

/// Converts the range's characters, stopping where one cannot be converted
/// without `lossByte` or the buffer is full; the characters converted.
@c(_CFStringGetBytes)
public func CFStringGetBytes(_ string: id?, _ range: CFRange, _ encoding: UInt32, _ lossByte: UInt8, _ externalRepresentation: Bool,
                             _ buffer: UnsafeMutablePointer<UInt8>?, _ maxLength: Int, _ usedLength: UnsafeMutablePointer<Int>?) -> Int {
    let units = Array(CFStrings.units(string)[CFArrays.range(range)])
    var used = 0, converted = 0
    var index = 0
    while index < units.count {
        // One character: a surrogate pair stays together.
        let width = UTF16.isLeadSurrogate(units[index]) && index + 1 < units.count ? 2 : 1
        let piece = CFStrings.string(units[index..<index + width])
        guard let bytes = CFStringEncodings.encode(piece, encoding, lossByte: lossByte == 0 ? nil : lossByte) else { break }
        if buffer != nil {
            guard used + bytes.count <= maxLength else { break }
            for (offset, byte) in bytes.enumerated() { buffer![used + offset] = byte }
        }
        used += bytes.count
        converted += width
        index += width
    }
    usedLength?.pointee = used
    return converted
}

@c(_CFStringGetMaximumSizeForEncoding)
public func CFStringGetMaximumSizeForEncoding(_ length: Int, _ encoding: UInt32) -> Int {
    switch encoding {
    case CFStringEncodings.utf8: return length * 3
    case CFStringEncodings.utf16, CFStringEncodings.utf16BE, CFStringEncodings.utf16LE: return length * 2
    case CFStringEncodings.utf32, CFStringEncodings.utf32BE, CFStringEncodings.utf32LE: return length * 4
    default: return length
    }
}

@c(_CFStringGetMaximumSizeOfFileSystemRepresentation)
public func CFStringGetMaximumSizeOfFileSystemRepresentation(_ string: id?) -> Int { CFStrings.units(string).count * 9 + 1 }

@c(_CFStringGetFileSystemRepresentation)
public func CFStringGetFileSystemRepresentation(_ string: id?, _ buffer: UnsafeMutablePointer<CChar>?, _ size: Int) -> Bool {
    CFStringGetCString(string, buffer, size, CFStringEncodings.utf8)
}

/// Bytes with a byte order mark for UTF-16 and UTF-32.
@c(_CFStringCreateExternalRepresentation)
public func CFStringCreateExternalRepresentation(_ allocator: UnsafeRawPointer?, _ string: id?, _ encoding: UInt32, _ lossByte: UInt8) -> id? {
    guard var bytes = CFStringEncodings.encode(CFStrings.value(string), encoding, lossByte: lossByte == 0 ? nil : lossByte) else { return nil }
    if encoding == CFStringEncodings.utf16 { bytes = [0xff, 0xfe] + bytes }
    if encoding == CFStringEncodings.utf32 { bytes = [0xff, 0xfe, 0, 0] + bytes }
    return ObjC.retain(DataObjects.autoreleased(Data(bytes)))
}

@c(_CFStringCreateFromExternalRepresentation)
public func CFStringCreateFromExternalRepresentation(_ allocator: UnsafeRawPointer?, _ data: id?, _ encoding: UInt32) -> id? {
    let bytes = DataObjects.data(data)
    return bytes.withUnsafeBytes { CFStringEncodings.decode($0, encoding) }.map(Strings.make)
}

@c(_CFStringGetSystemEncoding) public func CFStringGetSystemEncoding() -> UInt32 { CFStringEncodings.macRoman }
/// MacRoman, the system encoding, for a string of ASCII, as CoreFoundation
/// answers for the strings it keeps in 8 bits (apps go on to ask for the C
/// string in it); else UTF-16.
@c(_CFStringGetFastestEncoding) public func CFStringGetFastestEncoding(_ string: id?) -> UInt32 {
    CFStrings.value(string).allSatisfy(\.isASCII) ? CFStringEncodings.macRoman : CFStringEncodings.utf16
}
@c(_CFStringGetSmallestEncoding) public func CFStringGetSmallestEncoding(_ string: id?) -> UInt32 {
    CFStrings.value(string).allSatisfy(\.isASCII) ? CFStringEncodings.ascii : CFStringEncodings.utf8
}

@c(_CFStringGetNameOfEncoding)
public func CFStringGetNameOfEncoding(_ encoding: UInt32) -> id? {
    CFStringEncodings.names[encoding].map { name in ObjC.autorelease(Strings.make(name)) } ?? nil
}

@c(_CFStringIsEncodingAvailable)
public func CFStringIsEncodingAvailable(_ encoding: UInt32) -> Bool { CFStringEncodings.names[encoding] != nil }

@c(_CFStringConvertEncodingToNSStringEncoding)
public func CFStringConvertEncodingToNSStringEncoding(_ encoding: UInt32) -> UInt { CFStringEncodings.nsEncoding(encoding) }

@c(_CFStringConvertNSStringEncodingToEncoding)
public func CFStringConvertNSStringEncodingToEncoding(_ encoding: UInt) -> UInt32 { CFStringEncodings.cfEncoding(encoding) }

@c(_CFStringConvertEncodingToIANACharSetName)
public func CFStringConvertEncodingToIANACharSetName(_ encoding: UInt32) -> id? {
    let names: [UInt32: String] = [CFStringEncodings.utf8: "UTF-8", CFStringEncodings.ascii: "US-ASCII",
                                   CFStringEncodings.isoLatin1: "ISO-8859-1", CFStringEncodings.macRoman: "macintosh",
                                   CFStringEncodings.windowsLatin1: "windows-1252", CFStringEncodings.utf16: "UTF-16",
                                   CFStringEncodings.utf16BE: "UTF-16BE", CFStringEncodings.utf16LE: "UTF-16LE"]
    return names[encoding].map { ObjC.autorelease(Strings.make($0))! }
}

@c(_CFStringConvertIANACharSetNameToEncoding)
public func CFStringConvertIANACharSetNameToEncoding(_ name: id?) -> UInt32 {
    switch CFStrings.value(name).lowercased() {
    case "utf-8", "utf8": return CFStringEncodings.utf8
    case "us-ascii", "ascii": return CFStringEncodings.ascii
    case "iso-8859-1", "latin1": return CFStringEncodings.isoLatin1
    case "macintosh", "macroman": return CFStringEncodings.macRoman
    case "windows-1252", "cp1252": return CFStringEncodings.windowsLatin1
    case "utf-16": return CFStringEncodings.utf16
    case "utf-16be": return CFStringEncodings.utf16BE
    case "utf-16le": return CFStringEncodings.utf16LE
    default: return 0xFFFF_FFFF
    }
}

// MARK: Comparing and searching

@c(_CFStringCompare)
public func CFStringCompare(_ string: id?, _ other: id?, _ flags: UInt) -> Int {
    CFStrings.compare(CFStrings.value(string), CFStrings.value(other), flags)
}

@c(_CFStringCompareWithOptions)
public func CFStringCompareWithOptions(_ string: id?, _ other: id?, _ range: CFRange, _ flags: UInt) -> Int {
    let part = CFStrings.string(CFStrings.units(string)[CFArrays.range(range)])
    return CFStrings.compare(part, CFStrings.value(other), flags)
}

@c(_CFStringCompareWithOptionsAndLocale)
public func CFStringCompareWithOptionsAndLocale(_ string: id?, _ other: id?, _ range: CFRange, _ flags: UInt, _ locale: id?) -> Int {
    CFStringCompareWithOptions(string, other, range, flags)
}

@c(_CFStringFind)
public func CFStringFind(_ string: id?, _ target: id?, _ flags: UInt) -> CFRange {
    CFStrings.find(string, target, CFStrings.whole(string), flags)
}

@c(_CFStringFindWithOptions)
public func CFStringFindWithOptions(_ string: id?, _ target: id?, _ range: CFRange, _ flags: UInt,
                                    _ result: UnsafeMutablePointer<CFRange>?) -> Bool {
    let found = CFStrings.find(string, target, range, flags)
    guard found.location != -1 else { return false }
    result?.pointee = found
    return true
}

@c(_CFStringHasPrefix)
public func CFStringHasPrefix(_ string: id?, _ prefix: id?) -> Bool { CFStrings.units(string).starts(with: CFStrings.units(prefix)) }

@c(_CFStringHasSuffix)
public func CFStringHasSuffix(_ string: id?, _ suffix: id?) -> Bool {
    let units = CFStrings.units(string), end = CFStrings.units(suffix)
    return units.count >= end.count && Array(units.suffix(end.count)) == end
}

@c(_CFStringGetIntValue)
public func CFStringGetIntValue(_ string: id?) -> Int32 { Int32(truncatingIfNeeded: Strings.integerPrefix(CFStrings.value(string))) }

@c(_CFStringGetDoubleValue)
public func CFStringGetDoubleValue(_ string: id?) -> Double {
    CFStrings.value(string).withCString { strtod($0, nil) }
}

@c(_CFStringCreateArrayBySeparatingStrings)
public func CFStringCreateArrayBySeparatingStrings(_ allocator: UnsafeRawPointer?, _ string: id?, _ separator: id?) -> id? {
    ObjC.retain(ObjC.send(string, ObjC.selector("componentsSeparatedByString:"), separator))
}

@c(_CFStringCreateByCombiningStrings)
public func CFStringCreateByCombiningStrings(_ allocator: UnsafeRawPointer?, _ array: id?, _ separator: id?) -> id? {
    let parts = CFArrays.values(array).map { CFStrings.value(CFCollections.object($0)) }
    return Strings.make(parts.joined(separator: CFStrings.value(separator)))
}

// MARK: Mutation

@c(_CFStringAppend)
public func CFStringAppend(_ string: id?, _ other: id?) { CFStrings.mutate(string) { $0 += CFStrings.value(other) } }

@c(_CFStringAppendCString)
public func CFStringAppendCString(_ string: id?, _ cString: UnsafePointer<CChar>?, _ encoding: UInt32) {
    guard let cString, let text = CFStringEncodings.decode(UnsafeRawBufferPointer(start: cString, count: strlen(cString)), encoding)
    else { return }
    CFStrings.mutate(string) { $0 += text }
}

@c(_CFStringAppendCharacters)
public func CFStringAppendCharacters(_ string: id?, _ characters: UnsafePointer<UInt16>?, _ count: Int) {
    let text = CFStrings.string(UnsafeBufferPointer(start: characters, count: count))
    CFStrings.mutate(string) { $0 += text }
}

@c(_CFStringReplace)
public func CFStringReplace(_ string: id?, _ range: CFRange, _ replacement: id?) {
    var units = CFStrings.units(string)
    units.replaceSubrange(CFArrays.range(range), with: CFStrings.units(replacement))
    _ = ObjC.send(string, ObjC.selector("setString:"), Strings.autoreleased(CFStrings.string(units)))
}

@c(_CFStringInsert)
public func CFStringInsert(_ string: id?, _ index: Int, _ inserted: id?) { CFStringReplace(string, CFRange(location: index, length: 0), inserted) }

@c(_CFStringDelete)
public func CFStringDelete(_ string: id?, _ range: CFRange) { CFStringReplace(string, range, Strings.autoreleased("")) }

@c(_CFStringReplaceAll)
public func CFStringReplaceAll(_ string: id?, _ replacement: id?) {
    _ = ObjC.send(string, ObjC.selector("setString:"), Strings.autoreleased(CFStrings.value(replacement)))
}

@c(_CFStringFindAndReplace)
public func CFStringFindAndReplace(_ string: id?, _ target: id?, _ replacement: id?, _ range: CFRange, _ flags: UInt) -> Int {
    Int(unsafeBitCast(ObjC.msgSend, to: (@convention(c) (id?, SEL, id?, id?, UInt, NSRange) -> UInt).self)(
        string, ObjC.selector("replaceOccurrencesOfString:withString:options:range:"), target, replacement, flags & (1 | 4 | 8 | 64),
        NSRange(location: UInt(range.location), length: UInt(range.length))))
}

@c(_CFStringUppercase)
public func CFStringUppercase(_ string: id?, _ locale: UnsafeRawPointer?) { CFStrings.mutate(string) { $0 = $0.uppercased() } }

@c(_CFStringLowercase)
public func CFStringLowercase(_ string: id?, _ locale: UnsafeRawPointer?) { CFStrings.mutate(string) { $0 = $0.lowercased() } }

@c(_CFStringCapitalize)
public func CFStringCapitalize(_ string: id?, _ locale: UnsafeRawPointer?) {
    let capitalized = Strings.value(of: ObjC.send(string, ObjC.selector("capitalizedString"))) ?? ""
    CFStrings.mutate(string) { $0 = capitalized }
}

@c(_CFStringTrim)
public func CFStringTrim(_ string: id?, _ trim: id?) {
    let piece = CFStrings.value(trim)
    guard !piece.isEmpty else { return }
    CFStrings.mutate(string) { text in
        while text.hasPrefix(piece) { text.removeFirst(piece.count) }
        while text.hasSuffix(piece) { text.removeLast(piece.count) }
    }
}

@c(_CFStringPad)
public func CFStringPad(_ string: id?, _ pad: id?, _ length: Int, _ index: Int) {
    var units = CFStrings.units(string)
    let padding = CFStrings.units(pad)
    if units.count > length { units.removeLast(units.count - length) }
    var offset = index
    while units.count < length, !padding.isEmpty {
        units.append(padding[offset % padding.count])
        offset += 1
    }
    _ = ObjC.send(string, ObjC.selector("setString:"), Strings.autoreleased(CFStrings.string(units)))
}

/// Prints the object's description to stderr, as Darwin does.
@c(_CFShow)
public func CFShow(_ object: id?) {
    let line = Format.describe(object) + "\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
}
