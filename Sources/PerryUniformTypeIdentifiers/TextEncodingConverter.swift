import Glibc
import PerryObjCInterop

// Mac apps' alone: armv7 runs only iOS apps, so it has none of this.
#if !arch(arm)
// CarbonCore's Text Encoding Converter and Unicode Converter, which text
// editors such as BBEdit read and write files with. A TextEncoding is a
// CFStringEncoding (base in the low 16 bits, variant above, format in the
// top 6), so CoreFoundation's provider converts between the bytes of a
// non-Unicode encoding and text; the Unicode forms are converted here. The
// encodings there are are CoreFoundation's.

/// TextEncoding's fields and the encodings this file converts itself.
enum TextEncodings {
    static let unicodeBase: UInt32 = 0x0100
    static let utf16Format: UInt32 = 0, utf8Format: UInt32 = 2, utf32Format: UInt32 = 3
    static let utf16BEFormat: UInt32 = 4, utf16LEFormat: UInt32 = 5, utf32BEFormat: UInt32 = 6, utf32LEFormat: UInt32 = 7

    static func base(_ encoding: UInt32) -> UInt32 { encoding & 0xFFFF }
    static func variant(_ encoding: UInt32) -> UInt32 { (encoding >> 16) & 0x3FF }
    static func format(_ encoding: UInt32) -> UInt32 { (encoding >> 26) & 0x3F }

    /// Whether Unicode's plain forms are little-endian, as this machine is.
    static let nativeLittleEndian = UInt16(1).littleEndian == 1

    /// Unicode's versions (kTextEncodingUnicodeV2_0 and on) are all one here.
    static func isUnicode(_ encoding: UInt32) -> Bool { base(encoding) & 0xFF00 == unicodeBase }

    /// The text of bytes in an encoding, or nil when they aren't valid in it.
    static func decode(_ bytes: UnsafeRawBufferPointer, _ encoding: UInt32) -> String? {
        guard isUnicode(encoding) else { return CoreFoundation.decode(bytes, encoding) }
        switch format(encoding) {
        case utf8Format:
            return String(validating: bytes, as: UTF8.self)
        case utf16Format, utf16BEFormat, utf16LEFormat:
            guard bytes.count % 2 == 0 else { return nil }
            let big = format(encoding) == utf16BEFormat
            let little = format(encoding) == utf16LEFormat || (!big && nativeLittleEndian)
            let units = stride(from: 0, to: bytes.count, by: 2).map { at -> UInt16 in
                little ? UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8 : UInt16(bytes[at]) << 8 | UInt16(bytes[at + 1])
            }
            return String(validating: units, as: UTF16.self)
        case utf32Format, utf32BEFormat, utf32LEFormat:
            guard bytes.count % 4 == 0 else { return nil }
            let big = format(encoding) == utf32BEFormat
            let little = format(encoding) == utf32LEFormat || (!big && nativeLittleEndian)
            var scalars = String.UnicodeScalarView()
            for at in stride(from: 0, to: bytes.count, by: 4) {
                let parts = (0..<4).map { UInt32(bytes[at + $0]) }
                let value = little ? parts[0] | parts[1] << 8 | parts[2] << 16 | parts[3] << 24
                                   : parts[0] << 24 | parts[1] << 16 | parts[2] << 8 | parts[3]
                guard let scalar = Unicode.Scalar(value) else { return nil }
                scalars.append(scalar)
            }
            return String(scalars)
        default:
            return nil
        }
    }

    /// Text's bytes in an encoding, or nil when a character has none in it
    /// and there is no loss byte to put in its place.
    static func encode(_ text: Substring, _ encoding: UInt32, lossByte: UInt8? = nil) -> [UInt8]? {
        guard isUnicode(encoding) else { return CoreFoundation.encode(String(text), encoding, lossByte: lossByte) }
        switch format(encoding) {
        case utf8Format:
            return Array(text.utf8)
        case utf16Format, utf16BEFormat, utf16LEFormat:
            let big = format(encoding) == utf16BEFormat || (format(encoding) == utf16Format && !nativeLittleEndian)
            return text.utf16.flatMap { unit -> [UInt8] in
                big ? [UInt8(unit >> 8), UInt8(unit & 0xFF)] : [UInt8(unit & 0xFF), UInt8(unit >> 8)]
            }
        case utf32Format, utf32BEFormat, utf32LEFormat:
            let big = format(encoding) == utf32BEFormat || (format(encoding) == utf32Format && !nativeLittleEndian)
            return text.unicodeScalars.flatMap { scalar -> [UInt8] in
                let v = scalar.value
                let bytes = [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
                return big ? bytes : bytes.reversed()
            }
        default:
            return nil
        }
    }

    /// Whether text in the encoding can be converted.
    static func isAvailable(_ encoding: UInt32) -> Bool {
        isUnicode(encoding) ? [utf16Format, utf8Format, utf32Format, utf16BEFormat, utf16LEFormat, utf32BEFormat, utf32LEFormat]
            .contains(format(encoding)) : CoreFoundation.isAvailable(encoding)
    }

    /// Decodes as much of the bytes as is whole characters: a multibyte
    /// character the input ends in the middle of is left over.
    static func decodePrefix(_ bytes: [UInt8], _ encoding: UInt32) -> (text: String, used: Int)? {
        for cut in 0...min(3, bytes.count) {
            let used = bytes.count - cut
            if let text = bytes[..<used].withUnsafeBytes({ decode($0, encoding) }) { return (text, used) }
        }
        return nil
    }

    /// Encodes as many whole characters as fit in `capacity` bytes. Returns
    /// the bytes, how many characters went in, and whether a character had
    /// no bytes in the encoding (then encoding stops before it, unless
    /// `lossByte` stands in for it).
    static func encodePrefix(_ text: String, _ encoding: UInt32, capacity: Int, lossByte: UInt8?)
        -> (bytes: [UInt8], characters: Int, unmappable: Bool, usedFallback: Bool) {
        if let all = encode(text[...], encoding), all.count <= capacity { return (all, text.count, false, false) }
        var bytes: [UInt8] = [], characters = 0, usedFallback = false
        for character in text {
            var piece = encode(String(character)[...], encoding)
            if piece == nil, let lossByte {
                piece = [lossByte]
                usedFallback = true
            }
            guard let piece else { return (bytes, characters, true, usedFallback) }
            guard bytes.count + piece.count <= capacity else { break }
            bytes += piece
            characters += 1
        }
        return (bytes, characters, false, usedFallback)
    }
}

/// CoreFoundation's string encodings, through its provider.
private enum CoreFoundation {
    static let library = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"

    static func function<T>(_ name: String, as type: T.Type) -> T? {
        guard let lookup = providerSymbolLookup,
              let symbol = library.withCString({ library in name.withCString { lookup(library, $0) } }) else { return nil }
        return unsafeBitCast(symbol, to: type)
    }

    static func decode(_ bytes: UnsafeRawBufferPointer, _ encoding: UInt32) -> String? {
        typealias Create = @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?, Int, UInt32, Bool) -> UnsafeMutableRawPointer?
        guard let create = function("_CFStringCreateWithBytes", as: Create.self) else { return nil }
        let base = bytes.baseAddress ?? UnsafeRawPointer(bitPattern: 1)
        guard let string = create(nil, base, bytes.count, encoding, false) else { return nil }
        return String(objCOwned: string)
    }

    static func encode(_ text: String, _ encoding: UInt32, lossByte: UInt8?) -> [UInt8]? {
        typealias Represent = @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?, UInt32, UInt8) -> UnsafeMutableRawPointer?
        typealias Length = @convention(c) (UnsafeMutableRawPointer?) -> Int
        typealias Bytes = @convention(c) (UnsafeMutableRawPointer?) -> UnsafePointer<UInt8>?
        guard !text.isEmpty else { return [] }
        guard let represent = function("_CFStringCreateExternalRepresentation", as: Represent.self),
              let length = function("_CFDataGetLength", as: Length.self),
              let bytes = function("_CFDataGetBytePtr", as: Bytes.self),
              let string = text.objCOwnedReturnValue() else { return nil }
        defer { ObjCRuntime.release(string) }
        guard let data = represent(nil, string, encoding, lossByte ?? 0) else { return nil }
        defer { ObjCRuntime.release(data) }
        let count = length(data)
        guard count > 0, let start = bytes(data) else { return [] }
        return Array(UnsafeBufferPointer(start: start, count: count))
    }

    static func isAvailable(_ encoding: UInt32) -> Bool {
        typealias Available = @convention(c) (UInt32) -> Bool
        return function("_CFStringIsEncodingAvailable", as: Available.self)?(encoding) ?? false
    }

    /// The encoding's IANA name, or nil.
    static func ianaName(_ encoding: UInt32) -> String? {
        typealias Name = @convention(c) (UInt32) -> UnsafeMutableRawPointer?
        guard let name = function("_CFStringConvertEncodingToIANACharSetName", as: Name.self)?(encoding) else { return nil }
        return String(objCArgument: name)
    }

    /// The encoding an IANA name is, or nil.
    static func encoding(ianaName name: UnsafeMutableRawPointer) -> UInt32? {
        typealias Encoding = @convention(c) (UnsafeMutableRawPointer?) -> UInt32
        guard let encoding = function("_CFStringConvertIANACharSetNameToEncoding", as: Encoding.self)?(name),
              encoding != 0xFFFF_FFFF else { return nil }
        return encoding
    }
}

private enum TECStatus {
    static let paramErr: Int32 = -50
    static let unsupportedEncoding: Int32 = -8738
    static let malformedInput: Int32 = -8739
    static let bufferBelowMinimumSize: Int32 = -8750
    static let partialChar: Int32 = -8753
    static let unmappableElement: Int32 = -8754
    static let usedFallbacks: Int32 = -8783
    static let outputBufferFull: Int32 = -8785
}

// MARK: - TextEncoding

/// TextEncoding CreateTextEncoding(TextEncodingBase, TextEncodingVariant,
/// TextEncodingFormat).
@c(_CreateTextEncoding)
public func CreateTextEncoding(_ base: UInt32, _ variant: UInt32, _ format: UInt32) -> UInt32 {
    (base & 0xFFFF) | (variant & 0x3FF) << 16 | (format & 0x3F) << 26
}

@c(_GetTextEncodingBase) public func GetTextEncodingBase(_ encoding: UInt32) -> UInt32 { TextEncodings.base(encoding) }
@c(_GetTextEncodingVariant) public func GetTextEncodingVariant(_ encoding: UInt32) -> UInt32 { TextEncodings.variant(encoding) }
@c(_GetTextEncodingFormat) public func GetTextEncodingFormat(_ encoding: UInt32) -> UInt32 { TextEncodings.format(encoding) }

/// OSStatus UpgradeScriptInfoToTextEncoding(ScriptCode, LangCode, RegionCode,
/// ConstStr255Param fontName, TextEncoding *): a script's encoding is its
/// Mac OS encoding, whose base is the script code (0 Roman to 32
/// Uninterpreted). With no script (kTextScriptDontCare, -128) it is the
/// system script's, Roman. The language, region and font only pick variants,
/// which are left at their defaults.
@c(_UpgradeScriptInfoToTextEncoding)
public func UpgradeScriptInfoToTextEncoding(_ script: Int16, _ language: Int16, _ region: Int16, _ fontName: UnsafeRawPointer?,
                                            _ encoding: UnsafeMutablePointer<UInt32>?) -> Int32 {
    guard let encoding else { return TECStatus.paramErr }
    if script == -128 {
        encoding.pointee = 0   // kTextEncodingMacRoman
        return 0
    }
    guard (0...32).contains(script) else { return TECStatus.paramErr }
    encoding.pointee = UInt32(script)
    return 0
}

// MARK: - Unicode Converter

/// A TextToUnicodeInfo or UnicodeToTextInfo: the other encoding, and the
/// Unicode form text is converted to or from.
final class UnicodeConversion {
    let unicode: UInt32
    let other: UInt32

    init(unicode: UInt32, other: UInt32) {
        self.unicode = unicode
        self.other = other
    }

    var reference: UnsafeMutableRawPointer { Unmanaged.passRetained(self).toOpaque() }

    static func of(_ reference: UnsafeMutableRawPointer?) -> UnicodeConversion? {
        reference.map { Unmanaged<UnicodeConversion>.fromOpaque($0).takeUnretainedValue() }
    }

    /// UnicodeMapping: { unicodeEncoding, otherEncoding, mappingVersion }.
    static func create(_ mapping: UnsafeRawPointer?, _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
        guard let mapping, let out else { return TECStatus.paramErr }
        let unicode = mapping.loadUnaligned(as: UInt32.self), other = mapping.loadUnaligned(fromByteOffset: 4, as: UInt32.self)
        return create(unicode: unicode, other: other, out)
    }

    static func create(unicode: UInt32, other: UInt32, _ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
        guard let out else { return TECStatus.paramErr }
        // Unicode's own form, UTF-16 when the mapping names Unicode's base.
        let form = TextEncodings.isUnicode(unicode) ? unicode : TextEncodings.unicodeBase
        guard TextEncodings.isAvailable(other), TextEncodings.isAvailable(form) else {
            out.pointee = nil
            return TECStatus.unsupportedEncoding
        }
        out.pointee = UnicodeConversion(unicode: form, other: other).reference
        return 0
    }

    static func dispose(_ info: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
        guard let info, let reference = info.pointee else { return TECStatus.paramErr }
        Unmanaged<UnicodeConversion>.fromOpaque(reference).release()
        info.pointee = nil
        return 0
    }

    /// Converts from `from` to `to`: whole characters, as many as fit.
    /// Returns the status, the input bytes read and the output bytes
    /// written.
    func convert(_ input: UnsafeRawPointer?, _ inputLength: Int, from: UInt32, to: UInt32, flags: UInt32,
                 _ output: UnsafeMutableRawPointer?, _ outputLength: Int) -> (status: Int32, read: Int, written: Int) {
        guard inputLength >= 0, outputLength >= 0, inputLength == 0 || input != nil, outputLength == 0 || output != nil else {
            return (TECStatus.paramErr, 0, 0)
        }
        let bytes = inputLength > 0 ? Array(UnsafeRawBufferPointer(start: input, count: inputLength)) : []
        guard let (text, used) = TextEncodings.decodePrefix(bytes, from) else { return (TECStatus.malformedInput, 0, 0) }
        let fallbacks = flags & 1 != 0   // kUnicodeUseFallbacksMask
        let encoded = TextEncodings.encodePrefix(text, to, capacity: outputLength, lossByte: fallbacks ? UInt8(ascii: "?") : nil)
        if let output, !encoded.bytes.isEmpty { encoded.bytes.withUnsafeBytes { output.copyMemory(from: $0.baseAddress!, byteCount: $0.count) } }
        // The input the characters converted came from.
        let read = encoded.characters == text.count ? used
            : TextEncodings.encode(text.prefix(encoded.characters), from)?.count ?? 0
        let status: Int32
        if encoded.unmappable { status = TECStatus.unmappableElement }
        else if encoded.characters < text.count { status = encoded.characters == 0 ? TECStatus.bufferBelowMinimumSize : TECStatus.outputBufferFull }
        else if used < bytes.count { status = TECStatus.partialChar }
        else if encoded.usedFallback { status = TECStatus.usedFallbacks }
        else { status = 0 }
        return (status, read, encoded.bytes.count)
    }
}

@c(_CreateTextToUnicodeInfo)
public func CreateTextToUnicodeInfo(_ mapping: UnsafeRawPointer?, _ info: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    UnicodeConversion.create(mapping, info)
}

@c(_CreateTextToUnicodeInfoByEncoding)
public func CreateTextToUnicodeInfoByEncoding(_ encoding: UInt32, _ info: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    UnicodeConversion.create(unicode: TextEncodings.unicodeBase, other: encoding, info)
}

@c(_CreateUnicodeToTextInfo)
public func CreateUnicodeToTextInfo(_ mapping: UnsafeRawPointer?, _ info: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    UnicodeConversion.create(mapping, info)
}

@c(_CreateUnicodeToTextInfoByEncoding)
public func CreateUnicodeToTextInfoByEncoding(_ encoding: UInt32, _ info: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 {
    UnicodeConversion.create(unicode: TextEncodings.unicodeBase, other: encoding, info)
}

@c(_DisposeTextToUnicodeInfo)
public func DisposeTextToUnicodeInfo(_ info: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 { UnicodeConversion.dispose(info) }

@c(_DisposeUnicodeToTextInfo)
public func DisposeUnicodeToTextInfo(_ info: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32 { UnicodeConversion.dispose(info) }

/// OSStatus ConvertFromTextToUnicode(TextToUnicodeInfo, ByteCount, ConstLogicalAddress,
/// OptionBits, ItemCount, ByteOffset[], ItemCount *, ByteOffset[], ByteCount,
/// ByteCount *sourceRead, ByteCount *unicodeLength, UniChar[]). Offsets
/// aren't kept: none come back.
@c(_ConvertFromTextToUnicode)
public func ConvertFromTextToUnicode(_ info: UnsafeMutableRawPointer?, _ sourceLength: Int, _ source: UnsafeRawPointer?, _ flags: UInt32,
                                     _ offsetCount: Int, _ offsets: UnsafeRawPointer?, _ offsetCountOut: UnsafeMutablePointer<Int>?,
                                     _ offsetsOut: UnsafeMutableRawPointer?, _ outputLength: Int, _ sourceRead: UnsafeMutablePointer<Int>?,
                                     _ unicodeLength: UnsafeMutablePointer<Int>?, _ unicode: UnsafeMutableRawPointer?) -> Int32 {
    offsetCountOut?.pointee = 0
    guard let conversion = UnicodeConversion.of(info) else { return TECStatus.paramErr }
    let result = conversion.convert(source, sourceLength, from: conversion.other, to: conversion.unicode, flags: flags,
                                    unicode, outputLength)
    sourceRead?.pointee = result.read
    unicodeLength?.pointee = result.written
    return result.status
}

/// OSStatus ConvertFromUnicodeToText(UnicodeToTextInfo, ByteCount, const UniChar[],
/// OptionBits, ItemCount, ByteOffset[], ItemCount *, ByteOffset[], ByteCount,
/// ByteCount *inputRead, ByteCount *outputLength, LogicalAddress).
@c(_ConvertFromUnicodeToText)
public func ConvertFromUnicodeToText(_ info: UnsafeMutableRawPointer?, _ unicodeLength: Int, _ unicode: UnsafeRawPointer?, _ flags: UInt32,
                                     _ offsetCount: Int, _ offsets: UnsafeRawPointer?, _ offsetCountOut: UnsafeMutablePointer<Int>?,
                                     _ offsetsOut: UnsafeMutableRawPointer?, _ outputLength: Int, _ inputRead: UnsafeMutablePointer<Int>?,
                                     _ outputWritten: UnsafeMutablePointer<Int>?, _ output: UnsafeMutableRawPointer?) -> Int32 {
    offsetCountOut?.pointee = 0
    guard let conversion = UnicodeConversion.of(info) else { return TECStatus.paramErr }
    let result = conversion.convert(unicode, unicodeLength, from: conversion.unicode, to: conversion.other, flags: flags,
                                    output, outputLength)
    inputRead?.pointee = result.read
    outputWritten?.pointee = result.written
    return result.status
}

// MARK: - Text Encoding Converter

/// A TECObjectRef: a converter between two encodings, which keeps the end
/// of a multibyte character that one call's input ends in for the next.
final class EncodingConverter {
    let input: UInt32
    let output: UInt32
    var pending: [UInt8] = []

    init(input: UInt32, output: UInt32) {
        self.input = input
        self.output = output
    }

    static func of(_ reference: UnsafeMutableRawPointer?) -> EncodingConverter? {
        reference.map { Unmanaged<EncodingConverter>.fromOpaque($0).takeUnretainedValue() }
    }
}

/// OSStatus TECCreateConverter(TECObjectRef *, TextEncoding input, TextEncoding output).
@c(_TECCreateConverter)
public func TECCreateConverter(_ out: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, _ input: UInt32, _ output: UInt32) -> Int32 {
    guard let out else { return TECStatus.paramErr }
    guard TextEncodings.isAvailable(input), TextEncodings.isAvailable(output) else {
        out.pointee = nil
        return -8749   // kTECNoConversionPathErr
    }
    out.pointee = Unmanaged.passRetained(EncodingConverter(input: input, output: output)).toOpaque()
    return 0
}

@c(_TECDisposeConverter)
public func TECDisposeConverter(_ converter: UnsafeMutableRawPointer?) -> Int32 {
    guard let converter else { return TECStatus.paramErr }
    Unmanaged<EncodingConverter>.fromOpaque(converter).release()
    return 0
}

/// Forgets the partial character kept from the last call.
@c(_TECClearConverterContextInfo)
public func TECClearConverterContextInfo(_ converter: UnsafeMutableRawPointer?) -> Int32 {
    guard let converter = EncodingConverter.of(converter) else { return TECStatus.paramErr }
    converter.pending = []
    return 0
}

/// OSStatus TECConvertText(TECObjectRef, ConstTextPtr, ByteCount, ByteCount *read,
/// TextPtr, ByteCount, ByteCount *written). A multibyte character the input
/// ends in the middle of is read and kept for the next call.
@c(_TECConvertText)
public func TECConvertText(_ reference: UnsafeMutableRawPointer?, _ input: UnsafeRawPointer?, _ inputLength: Int,
                           _ read: UnsafeMutablePointer<Int>?, _ output: UnsafeMutableRawPointer?, _ outputLength: Int,
                           _ written: UnsafeMutablePointer<Int>?) -> Int32 {
    read?.pointee = 0
    written?.pointee = 0
    guard let converter = EncodingConverter.of(reference), inputLength >= 0, inputLength == 0 || input != nil else { return TECStatus.paramErr }
    let pending = converter.pending
    let bytes = pending + (inputLength > 0 ? Array(UnsafeRawBufferPointer(start: input, count: inputLength)) : [])
    guard let (text, used) = TextEncodings.decodePrefix(bytes, converter.input) else { return TECStatus.malformedInput }
    let encoded = TextEncodings.encodePrefix(text, converter.output, capacity: outputLength, lossByte: nil)
    if let output, !encoded.bytes.isEmpty { encoded.bytes.withUnsafeBytes { output.copyMemory(from: $0.baseAddress!, byteCount: $0.count) } }
    written?.pointee = encoded.bytes.count
    if encoded.characters == text.count {
        // All of it, with the end of a partial character kept.
        converter.pending = Array(bytes[used...])
        read?.pointee = inputLength
    } else {
        let consumed = TextEncodings.encode(text.prefix(encoded.characters), converter.input)?.count ?? 0
        converter.pending = []
        read?.pointee = max(0, consumed - pending.count)
        if consumed < pending.count { converter.pending = Array(pending[consumed...]) }
    }
    if encoded.unmappable { return TECStatus.unmappableElement }
    return encoded.characters < text.count ? TECStatus.outputBufferFull : 0
}

/// Writes out what the converter keeps: a partial character, which has
/// no output, so it is dropped.
@c(_TECFlushText)
public func TECFlushText(_ reference: UnsafeMutableRawPointer?, _ output: UnsafeMutableRawPointer?, _ outputLength: Int,
                         _ written: UnsafeMutablePointer<Int>?) -> Int32 {
    guard let converter = EncodingConverter.of(reference) else { return TECStatus.paramErr }
    converter.pending = []
    written?.pointee = 0
    return 0
}

/// IANA charset registry MIB numbers.
private let mibs: [UInt32: Int32] = [
    0x0600: 3,             // US-ASCII
    0x0201: 4,             // ISO-8859-1
    0x0800_0100: 106,      // UTF-8
    0x1000_0100: 1013,     // UTF-16BE
    0x1400_0100: 1014,     // UTF-16LE
    0x0100: 1015,          // UTF-16
    0x0C00_0100: 1017,     // UTF-32
    0x1800_0100: 1018,     // UTF-32BE
    0x1C00_0100: 1019,     // UTF-32LE
    0x0000: 2027,          // macintosh
    0x0500: 2252,          // windows-1252
]

/// OSStatus TECGetTextEncodingFromInternetNameOrMIB(TextEncoding *,
/// TECInternetNameUsageMask, CFStringRef name, SInt32 mib): by name, or by
/// MIB when the name is NULL.
@c(_TECGetTextEncodingFromInternetNameOrMIB)
public func TECGetTextEncodingFromInternetNameOrMIB(_ encoding: UnsafeMutablePointer<UInt32>?, _ usage: UInt32,
                                                     _ name: UnsafeMutableRawPointer?, _ mib: Int32) -> Int32 {
    guard let encoding else { return TECStatus.paramErr }
    if let name {
        guard let found = CoreFoundation.encoding(ianaName: name) else { return TECStatus.unsupportedEncoding }
        encoding.pointee = found
        return 0
    }
    guard let found = mibs.first(where: { $0.value == mib })?.key else { return TECStatus.unsupportedEncoding }
    encoding.pointee = found
    return 0
}

/// OSStatus TECCopyTextEncodingInternetNameAndMIB(TextEncoding,
/// TECInternetNameUsageMask, CFStringRef *name, SInt32 *mib).
@c(_TECCopyTextEncodingInternetNameAndMIB)
public func TECCopyTextEncodingInternetNameAndMIB(_ encoding: UInt32, _ usage: UInt32, _ name: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                                                  _ mib: UnsafeMutablePointer<Int32>?) -> Int32 {
    guard name != nil || mib != nil else { return TECStatus.paramErr }
    guard let ianaName = CoreFoundation.ianaName(encoding) else { return TECStatus.unsupportedEncoding }
    name?.pointee = ianaName.objCOwnedReturnValue()
    mib?.pointee = mibs[encoding] ?? -1   // kTEC_MIBEnumDontCare
    return 0
}
#endif
