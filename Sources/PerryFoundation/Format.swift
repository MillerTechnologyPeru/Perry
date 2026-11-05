import Glibc
import PerryObjCInterop

/// Variadic arguments as Darwin lays them out, the memory a Darwin va_list
/// points to. On arm64 each takes an 8-byte stack slot. On armv7 they are
/// contiguous words, with 64-bit integers and doubles in two words at any
/// 4-byte boundary.
struct DarwinArguments {
    private var cursor: UnsafeRawPointer

    init(_ pointer: UnsafeRawPointer) {
        cursor = pointer
    }

    /// A word: an int or smaller integer (promoted), a long, a pointer.
    mutating func next() -> UInt64 {
        let value = UInt64(cursor.loadUnaligned(as: UInt.self))
        cursor += MemoryLayout<UInt>.size
        return value
    }

    /// A long long or a double (a float, promoted).
    mutating func next64() -> UInt64 {
        let value = cursor.loadUnaligned(as: UInt64.self)
        cursor += 8
        return value
    }

    mutating func nextPointer() -> UnsafeMutableRawPointer? {
        UnsafeMutableRawPointer(bitPattern: UInt(next()))
    }
}

/// printf-style formatting with Foundation's %@, which inserts an object's
/// -description. Other conversions are formatted by glibc one at a time.
enum Format {
    static func string(_ format: String, _ arguments: inout DarwinArguments) -> String {
        let bytes = Array(format.utf8)
        var output = ""
        var literal: [UInt8] = []
        var index = 0

        func flushLiteral() {
            if !literal.isEmpty {
                output += String(decoding: literal, as: UTF8.self)
                literal.removeAll(keepingCapacity: true)
            }
        }

        while index < bytes.count {
            let byte = bytes[index]
            guard byte == UInt8(ascii: "%") else {
                literal.append(byte)
                index += 1
                continue
            }
            flushLiteral()
            index += 1

            // %[flags][width][.precision][length]conversion
            var spec = "%"
            while index < bytes.count, "-+ #0'".utf8.contains(bytes[index]) {
                spec.append(Character(UnicodeScalar(bytes[index])))
                index += 1
            }
            func number() {
                if index < bytes.count, bytes[index] == UInt8(ascii: "*") {
                    spec += String(Int32(truncatingIfNeeded: arguments.next()))
                    index += 1
                    return
                }
                while index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) {
                    spec.append(Character(UnicodeScalar(bytes[index])))
                    index += 1
                }
            }
            number()
            if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
                spec += "."
                index += 1
                number()
            }
            var length = ""
            while index < bytes.count, "hlqLzjt".utf8.contains(bytes[index]) {
                length.append(Character(UnicodeScalar(bytes[index])))
                index += 1
            }
            guard index < bytes.count else { break }
            let conversion = Character(UnicodeScalar(bytes[index]))
            index += 1

            // 64-bit integers, and word-sized ones (long, size_t, ptrdiff_t),
            // which are 64-bit too on arm64.
            let wordSized = ["l", "z", "t"].contains(length)
            let wide = ["ll", "q", "j"].contains(length) || (wordSized && MemoryLayout<Int>.size == 8)
            let cLength = length == "q" ? "ll" : (length == "L" ? "" : length)
            let raw: UInt64
            switch conversion {
            case "%":
                output += "%"
            case "@":
                output += describe(arguments.nextPointer())
            case "d", "i":
                raw = wide ? arguments.next64() : arguments.next()
                output += wide ? c(spec + cLength + String(conversion), Int64(bitPattern: raw))
                    : wordSized ? c(spec + cLength + String(conversion), Int(truncatingIfNeeded: raw))
                    : c(spec + String(conversion), Int32(truncatingIfNeeded: raw))
            case "u", "o", "x", "X":
                raw = wide ? arguments.next64() : arguments.next()
                output += wide ? c(spec + cLength + String(conversion), raw)
                    : wordSized ? c(spec + cLength + String(conversion), UInt(truncatingIfNeeded: raw))
                    : c(spec + String(conversion), UInt32(truncatingIfNeeded: raw))
            case "c":
                output += c(spec + "c", Int32(truncatingIfNeeded: arguments.next()), encoding: .macOSRoman)
            case "C":
                let unit = UInt16(truncatingIfNeeded: arguments.next())
                output += String(decoding: [unit], as: UTF16.self)
            case "s":
                if let string = UnsafePointer<CChar>(bitPattern: UInt(arguments.next())) {
                    output += c(spec + "s", string, encoding: .macOSRoman)
                } else {
                    output += "(null)"
                }
            case "S":
                if var unit = UnsafePointer<UInt16>(bitPattern: UInt(arguments.next())) {
                    var units: [UInt16] = []
                    while unit.pointee != 0 {
                        units.append(unit.pointee)
                        unit += 1
                    }
                    output += String(decoding: units, as: UTF16.self)
                } else {
                    output += "(null)"
                }
            case "p":
                // Darwin prints a null pointer as 0x0; glibc prints (nil).
                if let pointer = OpaquePointer(bitPattern: UInt(arguments.next())) {
                    output += c(spec + "p", pointer)
                } else {
                    output += "0x0"
                }
            case "f", "F", "e", "E", "g", "G", "a", "A":
                output += c(spec + String(conversion), Double(bitPattern: arguments.next64()))
            default:
                // Unknown conversion: keep it as written.
                output += spec + length + String(conversion)
            }
        }
        flushLiteral()
        return output
    }

    /// The text for %@: the object's description, or "(null)".
    static func describe(_ object: id?) -> String {
        guard let object else { return "(null)" }
        return ObjCObject(object).describedByObject() ?? "(null)"
    }

    /// Formats one value with glibc.
    private static func c(_ spec: String, _ value: CVarArg, encoding: CStringEncoding = .utf8) -> String {
        var buffer = [CChar](repeating: 0, count: 64)
        let needed = withVaList([value]) { vsnprintf(&buffer, buffer.count, spec, $0) }
        if needed >= buffer.count {
            buffer = [CChar](repeating: 0, count: Int(needed) + 1)
            _ = withVaList([value]) { vsnprintf(&buffer, buffer.count, spec, $0) }
        }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        switch encoding {
        case .utf8: return String(decoding: bytes, as: UTF8.self)
        case .macOSRoman: return MacOSRoman.decode(bytes)
        }
    }

    enum CStringEncoding { case utf8, macOSRoman }
}

/// Mac OS Roman, Darwin's default C string encoding, which %s and %c
/// read bytes in: "ł" in UTF-8 (C5 82) formats as "≈Ç".
enum MacOSRoman {
    /// 0x80 through 0xFF; 0x00 through 0x7F are ASCII.
    private static let high: [Unicode.Scalar] = Array((
        "ÄÅÇÉÑÖÜáàâäãåçéèêëíìîïñóòôöõúùûü†°¢£§•¶ß®©™´¨≠ÆØ∞±≤≥¥µ∂∑∏π∫ªºΩæø"
        + "¿¡¬√ƒ≈∆«»…\u{A0}ÀÃÕŒœ–—“”‘’÷◊ÿŸ⁄€‹›ﬁﬂ‡·‚„‰ÂÊÁËÈÍÎÏÌÓÔ\u{F8FF}ÒÚÛÙıˆ˜¯˘˙˚¸˝˛ˇ").unicodeScalars)

    static func decode(_ bytes: [UInt8]) -> String {
        var text = String.UnicodeScalarView()
        for byte in bytes {
            text.append(byte < 0x80 ? Unicode.Scalar(byte) : high[Int(byte) - 0x80])
        }
        return String(text)
    }
}
