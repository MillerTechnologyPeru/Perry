import Glibc
import PerryObjCInterop

// 64-bit Mac apps' alone, as the rest of the Apple Event Manager here is.
#if arch(x86_64) || arch(arm64)
// AEBuild: descriptors and Apple events from a format string, as TN2045
// describes it. A value is an integer ('long'), a quoted string (“…” or
// "…", 'TEXT'), a type code (an identifier or 'quoted', 'type'), a list
// [a, b], a record {key: value} or type{key: value}, a coercion type(value),
// or @, which takes the next argument: an AEDesc * alone; coerced, a C
// string for the text types, the value itself for numbers and codes, else
// a size and a pointer; @@, coerced, a Handle. Hex data, «…» or $…$, must be
// coerced. The variadic entry points are in CPerryUniformTypeIdentifiers,
// which passes their arguments as a Darwin va_list.

/// Variadic arguments as Darwin lays them out, the memory a Darwin va_list
/// points to: on x86_64 a structure over the saved registers, on arm64
/// 8-byte stack slots.
struct AEArguments {
    #if arch(x86_64)
    private var gpOffset: UInt32, fpOffset: UInt32
    private var overflow: UnsafeRawPointer
    private let registers: UnsafeRawPointer

    init(_ pointer: UnsafeRawPointer) {
        gpOffset = pointer.load(as: UInt32.self)
        fpOffset = pointer.load(fromByteOffset: 4, as: UInt32.self)
        overflow = pointer.load(fromByteOffset: 8, as: UnsafeRawPointer.self)
        registers = pointer.load(fromByteOffset: 16, as: UnsafeRawPointer.self)
    }

    private mutating func nextOverflow() -> UInt64 {
        let value = overflow.loadUnaligned(as: UInt64.self)
        overflow += 8
        return value
    }

    mutating func next() -> UInt64 {
        guard gpOffset < 48 else { return nextOverflow() }
        defer { gpOffset += 8 }
        return (registers + Int(gpOffset)).loadUnaligned(as: UInt64.self)
    }

    mutating func nextDouble() -> Double {
        guard fpOffset < 176 else { return Double(bitPattern: nextOverflow()) }
        defer { fpOffset += 16 }
        return (registers + Int(fpOffset)).loadUnaligned(as: Double.self)
    }
    #else
    private var cursor: UnsafeRawPointer

    init(_ pointer: UnsafeRawPointer) { cursor = pointer }

    mutating func next() -> UInt64 {
        defer { cursor += 8 }
        return cursor.loadUnaligned(as: UInt64.self)
    }

    mutating func nextDouble() -> Double { Double(bitPattern: next()) }
    #endif

    mutating func nextPointer() -> UnsafeRawPointer? { UnsafeRawPointer(bitPattern: UInt(next())) }
}

/// An AEBuild syntax error: aeBuildSyntax* and where it is in the format.
struct AEBuildFailure: Error {
    let code: UInt32
    let position: Int
}

/// The format's parser. Values are AEItems, which the Apple Event Manager's
/// descriptors are made from.
struct AEBuildParser {
    let bytes: [UInt8]
    var at = 0
    var arguments: AEArguments?

    init(_ format: UnsafePointer<CChar>, _ arguments: UnsafeRawPointer?) {
        bytes = Array(UnsafeRawBufferPointer(start: format, count: strlen(format)))
        self.arguments = arguments.map(AEArguments.init)
    }

    func fail(_ code: UInt32) -> AEBuildFailure { AEBuildFailure(code: code, position: at) }

    mutating func skipSpace() {
        while at < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[at]) { at += 1 }
    }

    mutating func peek() -> UInt8? {
        skipSpace()
        return at < bytes.count ? bytes[at] : nil
    }

    mutating func expect(_ byte: UInt8, _ code: UInt32) throws {
        guard peek() == byte else { throw fail(code) }
        at += 1
    }

    /// Whether the input is at one of a two-byte UTF-8 or one-byte Mac OS
    /// Roman quote.
    func matches(_ sequences: [[UInt8]]) -> Int? {
        for sequence in sequences where at + sequence.count <= bytes.count && Array(bytes[at..<(at + sequence.count)]) == sequence {
            return sequence.count
        }
        return nil
    }

    static let openQuotes: [[UInt8]] = [[0xE2, 0x80, 0x9C], [0xD2], [0x22]]       // “ (UTF-8, Mac OS Roman), "
    static let closeQuotes: [[UInt8]] = [[0xE2, 0x80, 0x9D], [0xD3], [0x22]]      // ”, "
    static let openHex: [[UInt8]] = [[0xC2, 0xAB], [0xC7], [0x24]]                // « (UTF-8, Mac OS Roman), $
    static let closeHex: [[UInt8]] = [[0xC2, 0xBB], [0xC8], [0x24]]               // », $

    static func isIdentifier(_ byte: UInt8) -> Bool {
        (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || (byte >= 0x30 && byte <= 0x39) || byte == 0x5F || byte == 0x2D
    }

    /// A four-character code: 'quoted' (up to four, padded with spaces) or
    /// a bare identifier, or nil if the input isn't at one.
    mutating func code() throws -> UInt32? {
        guard let first = peek() else { return nil }
        var characters: [UInt8] = []
        if first == 0x27 {   // '
            at += 1
            while at < bytes.count, bytes[at] != 0x27 { characters.append(bytes[at]); at += 1 }
            guard at < bytes.count else { throw fail(5) }   // aeBuildSyntaxMissingQuote
            at += 1
        } else if Self.isIdentifier(first), !(first >= 0x30 && first <= 0x39), first != 0x2D {
            while at < bytes.count, Self.isIdentifier(bytes[at]), characters.count < 4 { characters.append(bytes[at]); at += 1 }
        } else {
            return nil
        }
        guard characters.count <= 4 else { throw fail(1) }
        while characters.count < 4 { characters.append(0x20) }
        return characters.reduce(0) { $0 << 8 | UInt32($1) }
    }

    /// A value, with an optional leading coercion.
    mutating func value() throws -> AEItem {
        guard let next = peek() else { throw fail(2) }   // aeBuildSyntaxBadEOF
        if next == 0x5B { return try list() }
        if next == 0x7B { return try record(AE.typeAERecord) }
        if next == 0x40 { return try substitution(coercedTo: nil) }
        if next == 0x2D || (next >= 0x30 && next <= 0x39) { return try integer() }
        if matches(Self.openQuotes) != nil { return try string() }
        if matches(Self.openHex) != nil { throw fail(9) }   // aeBuildSyntaxUncoercedHex
        guard let type = try code() else { throw fail(1) }   // aeBuildSyntaxBadToken
        switch peek() {
        case 0x28:   // type(data)
            at += 1
            let item = try data(type)
            try expect(0x29, 13)   // aeBuildSyntaxNoCloseParen
            return item
        case 0x7B:   // type{...}
            return try record(type)
        case 0x5B:
            throw fail(18)   // aeBuildSyntaxCoercedList
        default:
            // A bare code is a type, except null.
            if type == AE.typeNull { return AEItem(keyword: 0, type: AE.typeNull, value: AEValue()) }
            return AEItem(keyword: 0, type: AE.typeType, value: AEValue(bytes: AE.number(type)))
        }
    }

    /// The data inside type(...), as that type.
    mutating func data(_ type: UInt32) throws -> AEItem {
        guard let next = peek() else { throw fail(2) }
        if next == 0x29 { return AEItem(keyword: 0, type: type, value: AEValue()) }   // type()
        if next == 0x40 { return try substitution(coercedTo: type) }
        if let open = matches(Self.openHex) {
            at += open
            var digits: [UInt8] = []
            while true {
                guard at < bytes.count else { throw fail(8) }   // aeBuildSyntaxNoCloseHex
                if let close = matches(Self.closeHex) {
                    at += close
                    break
                }
                let byte = bytes[at]
                at += 1
                if [0x20, 0x09, 0x0A, 0x0D].contains(byte) { continue }
                guard let digit = UInt8(String(UnicodeScalar(byte)), radix: 16) else { throw fail(6) }   // aeBuildSyntaxBadHex
                digits.append(digit)
            }
            guard digits.count % 2 == 0 else { throw fail(7) }   // aeBuildSyntaxOddHex
            let data = stride(from: 0, to: digits.count, by: 2).map { digits[$0] << 4 | digits[$0 + 1] }
            return AEItem(keyword: 0, type: type, value: AEValue(bytes: data))
        }
        let item: AEItem
        if next == 0x2D || (next >= 0x30 && next <= 0x39) { item = try integer() }
        else if matches(Self.openQuotes) != nil { item = try string() }
        else if let code = try code() { item = AEItem(keyword: 0, type: AE.typeType, value: AEValue(bytes: AE.number(code))) }
        else { throw fail(12) }   // aeBuildSyntaxBadData
        // A code as an enumeration or another code type keeps its bytes.
        if AE.codeTypes.contains(item.type), AE.codeTypes.contains(type) { return AEItem(keyword: 0, type: type, value: item.value) }
        guard let coerced = AE.coerce(item, to: type) else {
            // Data that doesn't coerce keeps its bytes under the type, as AEBuild does.
            return AEItem(keyword: 0, type: type, value: item.value)
        }
        return coerced
    }

    mutating func integer() throws -> AEItem {
        _ = peek()
        let start = at
        if bytes[at] == 0x2D { at += 1 }
        let digitsStart = at
        while at < bytes.count, bytes[at] >= 0x30, bytes[at] <= 0x39 { at += 1 }
        guard at > digitsStart else { throw fail(4) }   // aeBuildSyntaxBadNegative
        let text = String(decoding: bytes[start..<at], as: UTF8.self)
        if let value = Int32(text) { return AEItem(keyword: 0, type: AE.typeSInt32, value: AEValue(bytes: AE.number(value))) }
        guard let value = Int64(text) else { throw fail(12) }
        return AEItem(keyword: 0, type: AE.typeSInt64, value: AEValue(bytes: AE.number(value)))
    }

    /// A quoted string, as 'TEXT' (UTF-8 in the format becomes Mac OS Roman).
    mutating func string() throws -> AEItem {
        _ = peek()
        guard let open = matches(Self.openQuotes) else { throw fail(1) }
        let straight = bytes[at] == 0x22
        at += open
        var text: [UInt8] = []
        while true {
            guard at < bytes.count else { throw fail(10) }   // aeBuildSyntaxNoCloseString
            if let close = matches(Self.closeQuotes), straight == (bytes[at] == 0x22) {
                at += close
                break
            }
            text.append(bytes[at])
            at += 1
        }
        let string = String(decoding: text, as: UTF8.self)
        return AEItem(keyword: 0, type: AE.typeChar, value: AEValue(bytes: AE.textBytes(string, as: AE.typeChar) ?? text))
    }

    mutating func list() throws -> AEItem {
        try expect(0x5B, 1)
        var items: [AEItem] = []
        if peek() == 0x5D {
            at += 1
            return AEItem(keyword: 0, type: AE.typeAEList, value: AEValue(items: items))
        }
        while true {
            items.append(try value())
            guard let next = peek() else { throw fail(14) }   // aeBuildSyntaxNoCloseBracket
            at += 1
            if next == 0x5D { break }
            guard next == 0x2C else { throw fail(14) }
        }
        return AEItem(keyword: 0, type: AE.typeAEList, value: AEValue(items: items))
    }

    /// Keyword: value pairs, as a record's items or an event's parameters.
    mutating func pairs(until end: UInt8?) throws -> [AEItem] {
        var items: [AEItem] = []
        if let end, peek() == end {
            at += 1
            return items
        }
        if end == nil, peek() == nil { return items }
        while true {
            if peek() == 0x7E { at += 1 }   // ~key: an optional parameter
            guard let key = try code() else { throw fail(16) }   // aeBuildSyntaxNoKey
            try expect(0x3A, 17)   // aeBuildSyntaxNoColon
            var item = try value()
            item.keyword = key
            items.removeAll { $0.keyword == key }
            items.append(item)
            let next = peek()
            if let end, next == end {
                at += 1
                break
            }
            if end == nil, next == nil { break }
            guard next == 0x2C else { throw fail(end == nil ? 3 : 15) }   // aeBuildSyntaxNoEOF, NoCloseBrace
            at += 1
        }
        return items
    }

    mutating func record(_ type: UInt32) throws -> AEItem {
        try expect(0x7B, 1)
        return AEItem(keyword: 0, type: type, value: AEValue(items: try pairs(until: 0x7D), keyed: true))
    }

    /// @ and @@: the next argument.
    mutating func substitution(coercedTo type: UInt32?) throws -> AEItem {
        _ = peek()
        at += 1
        let double = at < bytes.count && bytes[at] == 0x40
        if double { at += 1 }
        guard var arguments else { throw fail(12) }
        defer { self.arguments = arguments }
        guard let type else {
            guard !double else { throw fail(19) }   // aeBuildSyntaxUncoercedDoubleAt
            guard let desc = arguments.nextPointer() else { return AEItem(keyword: 0, type: AE.typeNull, value: AEValue()) }
            return AE.item(desc)
        }
        if double {
            let handle = arguments.nextPointer().map { UnsafeMutableRawPointer(mutating: $0) }
            let size = GetHandleSize(handle)
            let block = handle?.load(as: UnsafeRawPointer?.self)
            return AEItem(keyword: 0, type: type, value: AEValue(bytes: AE.bytes(block, size)))
        }
        switch type {
        case AE.typeChar, AE.typeUTF8Text, AE.code("cstr"):
            guard let text = arguments.nextPointer() else { return AEItem(keyword: 0, type: type, value: AEValue()) }
            let bytes = AE.bytes(text, strlen(text.assumingMemoryBound(to: CChar.self)))
            // A C string in UTF-8; 'TEXT' is Mac OS Roman.
            if type == AE.typeChar, let string = String(validating: bytes, as: UTF8.self), let roman = AE.textBytes(string, as: AE.typeChar) {
                return AEItem(keyword: 0, type: type, value: AEValue(bytes: roman))
            }
            return AEItem(keyword: 0, type: type, value: AEValue(bytes: bytes))
        case AE.typeSInt16:
            return AEItem(keyword: 0, type: type, value: AEValue(bytes: AE.number(Int16(truncatingIfNeeded: arguments.next()))))
        case AE.typeSInt32, AE.typeUInt32, AE.typeType, AE.typeEnumerated, AE.typeKeyword, AE.typeProperty:
            return AEItem(keyword: 0, type: type, value: AEValue(bytes: AE.number(UInt32(truncatingIfNeeded: arguments.next()))))
        case AE.typeSInt64:
            return AEItem(keyword: 0, type: type, value: AEValue(bytes: AE.number(Int64(bitPattern: arguments.next()))))
        case AE.typeBoolean:
            return AEItem(keyword: 0, type: type, value: AEValue(bytes: [arguments.next() & 0xFF != 0 ? 1 : 0]))
        case AE.typeFloat:
            return AEItem(keyword: 0, type: type, value: AEValue(bytes: AE.number(Float(arguments.nextDouble()))))
        case AE.typeDouble:
            return AEItem(keyword: 0, type: type, value: AEValue(bytes: AE.number(arguments.nextDouble())))
        default:
            let size = Int(bitPattern: UInt(arguments.next()))
            let data = arguments.nextPointer()
            return AEItem(keyword: 0, type: type, value: AEValue(bytes: AE.bytes(data, max(0, size))))
        }
    }

    /// The whole format as one value, with nothing after it.
    mutating func single() throws -> AEItem {
        let item = try value()
        guard peek() == nil else { throw fail(3) }   // aeBuildSyntaxNoEOF
        return item
    }
}

private let buildSyntaxError: Int32 = -1740   // errAEBuildSyntaxError

private func report(_ failure: AEBuildFailure, _ error: UnsafeMutableRawPointer?) -> Int32 {
    error?.storeBytes(of: failure.code, as: UInt32.self)
    error?.storeBytes(of: UInt32(failure.position), toByteOffset: 4, as: UInt32.self)
    return buildSyntaxError
}

private func succeeded(_ error: UnsafeMutableRawPointer?) -> Int32 {
    error?.storeBytes(of: UInt32(0), as: UInt32.self)
    error?.storeBytes(of: UInt32(0), toByteOffset: 4, as: UInt32.self)
    return 0
}

/// OSStatus vAEBuildDesc(AEDesc *, AEBuildError *, const char *, va_list).
@c(_vAEBuildDesc)
public func vAEBuildDesc(_ result: UnsafeMutableRawPointer?, _ error: UnsafeMutableRawPointer?, _ format: UnsafePointer<CChar>?,
                         _ arguments: UnsafeRawPointer?) -> Int32 {
    guard let result, let format else { return Int32(AE.paramErr) }
    AE.set(result, AE.typeNull, AEValue())
    var parser = AEBuildParser(format, arguments)
    do {
        let item = try parser.single()
        AE.set(result, item.type, item.value)
        return succeeded(error)
    } catch let failure as AEBuildFailure {
        return report(failure, error)
    } catch {
        return buildSyntaxError
    }
}

/// OSStatus vAEBuildParameters(AppleEvent *, AEBuildError *, const char *, va_list):
/// the format's keyword: value pairs join the event's parameters.
@c(_vAEBuildParameters)
public func vAEBuildParameters(_ event: UnsafeMutableRawPointer?, _ error: UnsafeMutableRawPointer?, _ format: UnsafePointer<CChar>?,
                               _ arguments: UnsafeRawPointer?) -> Int32 {
    guard let event, let format, let storage = AE.storage(event) else { return Int32(AE.paramErr) }
    var parser = AEBuildParser(format, arguments)
    do {
        for item in try parser.pairs(until: nil) {
            storage.value.items.removeAll { $0.keyword == item.keyword }
            storage.value.items.append(item)
        }
        return succeeded(error)
    } catch let failure as AEBuildFailure {
        return report(failure, error)
    } catch {
        return buildSyntaxError
    }
}

/// OSStatus vAEBuildAppleEvent(AEEventClass, AEEventID, DescType addressType,
/// const void *addressData, Size, SInt16 returnID, SInt32 transactionID,
/// AppleEvent *, AEBuildError *, const char *, va_list).
@c(_vAEBuildAppleEvent)
public func vAEBuildAppleEvent(_ eventClass: UInt32, _ eventID: UInt32, _ addressType: UInt32, _ addressData: UnsafeRawPointer?,
                               _ addressLength: Int, _ returnID: Int16, _ transactionID: Int32, _ result: UnsafeMutableRawPointer?,
                               _ error: UnsafeMutableRawPointer?, _ format: UnsafePointer<CChar>?, _ arguments: UnsafeRawPointer?) -> Int32 {
    guard let result else { return Int32(AE.paramErr) }
    var address = (UInt32(0), UInt16(0), UInt16(0), UInt16(0), UInt16(0))   // a 12-byte AEDesc
    let created = withUnsafeMutableBytes(of: &address) { buffer -> Int16 in
        AE.set(buffer.baseAddress!, addressType, AEValue(bytes: AE.bytes(addressData, addressLength)))
        defer { AE.dispose(buffer.baseAddress!) }
        return AECreateAppleEvent(eventClass, eventID, buffer.baseAddress, returnID, transactionID, result)
    }
    guard created == AE.noErr else { return Int32(created) }
    guard let format else { return succeeded(error) }
    let status = vAEBuildParameters(result, error, format, arguments)
    if status != 0 { AE.dispose(result) }
    return status
}

// The variadic entry points' targets: CPerryUniformTypeIdentifiers saves the
// arguments and calls these with a va_list after the fixed ones.

@c public func perry_ae_build_desc(_ result: UnsafeMutableRawPointer?, _ error: UnsafeMutableRawPointer?, _ format: UnsafePointer<CChar>?,
                                   _ arguments: UnsafeRawPointer?) -> Int32 {
    vAEBuildDesc(result, error, format, arguments)
}

@c public func perry_ae_build_parameters(_ event: UnsafeMutableRawPointer?, _ error: UnsafeMutableRawPointer?, _ format: UnsafePointer<CChar>?,
                                         _ arguments: UnsafeRawPointer?) -> Int32 {
    vAEBuildParameters(event, error, format, arguments)
}
#endif
