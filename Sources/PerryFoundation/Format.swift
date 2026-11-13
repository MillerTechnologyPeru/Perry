import Glibc
import PerryObjCInterop

/// Variadic arguments as Darwin lays them out, the memory a Darwin va_list
/// points to. On arm64 each takes an 8-byte stack slot. On armv7 they are
/// contiguous words, with 64-bit integers and doubles in two words at any
/// 4-byte boundary. On x86_64 a va_list is a structure over the saved
/// registers, one pointer to which is passed, and integers and floating point
/// are taken from separate registers until those run out.
#if arch(x86_64)
struct DarwinArguments {
    private var gpOffset: UInt32, fpOffset: UInt32
    private var overflow: UnsafeRawPointer
    private let registers: UnsafeRawPointer
    private let startGPOffset: UInt32, startOverflow: UnsafeRawPointer

    init(_ pointer: UnsafeRawPointer) {
        gpOffset = pointer.load(as: UInt32.self)
        fpOffset = pointer.load(fromByteOffset: 4, as: UInt32.self)
        overflow = pointer.load(fromByteOffset: 8, as: UnsafeRawPointer.self)
        registers = pointer.load(fromByteOffset: 16, as: UnsafeRawPointer.self)
        startGPOffset = gpOffset
        startOverflow = overflow
    }

    /// The arguments from the `position`th, counted from 1. Positions count
    /// integers and pointers, as a format's positional arguments almost
    /// always are.
    func at(_ position: Int) -> DarwinArguments {
        var arguments = self
        arguments.gpOffset = startGPOffset
        arguments.overflow = startOverflow
        for _ in 1..<max(position, 1) { _ = arguments.next() }
        return arguments
    }

    private mutating func nextOverflow() -> UInt64 {
        let value = overflow.loadUnaligned(as: UInt64.self)
        overflow += 8
        return value
    }

    /// An int or smaller integer (promoted), a long, a pointer.
    mutating func next() -> UInt64 {
        guard gpOffset < 48 else { return nextOverflow() }
        defer { gpOffset += 8 }
        return (registers + Int(gpOffset)).loadUnaligned(as: UInt64.self)
    }

    /// A long long.
    mutating func next64() -> UInt64 { next() }

    /// A double (a float, promoted), as its bits.
    mutating func nextDouble() -> UInt64 {
        guard fpOffset < 176 else { return nextOverflow() }
        defer { fpOffset += 16 }
        return (registers + Int(fpOffset)).loadUnaligned(as: UInt64.self)
    }

    mutating func nextPointer() -> UnsafeMutableRawPointer? {
        UnsafeMutableRawPointer(bitPattern: UInt(next()))
    }
}
#else
struct DarwinArguments {
    private var cursor: UnsafeRawPointer
    /// The first argument's slot, from which positional arguments (%2$@)
    /// are counted.
    private let start: UnsafeRawPointer

    init(_ pointer: UnsafeRawPointer) {
        cursor = pointer
        start = pointer
    }

    /// The arguments from the `position`th, counted from 1.
    func at(_ position: Int) -> DarwinArguments {
        var arguments = self
        arguments.cursor = start + (max(position, 1) - 1) * 8
        return arguments
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

    /// A double (a float, promoted), as its bits.
    mutating func nextDouble() -> UInt64 { next64() }

    mutating func nextPointer() -> UnsafeMutableRawPointer? {
        UnsafeMutableRawPointer(bitPattern: UInt(next()))
    }
}
#endif

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

            // %[position$][flags][width][.precision][length]conversion: a
            // positional conversion takes its argument by number, leaving
            // the next one to the next conversion without a position.
            var digits = index
            while digits < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[digits]) { digits += 1 }
            let sequential = arguments
            var positional = false
            if digits > index, digits < bytes.count, bytes[digits] == UInt8(ascii: "$"),
               let position = Int(String(decoding: bytes[index..<digits], as: UTF8.self)) {
                arguments = arguments.at(position)
                positional = true
                index = digits + 1
            }
            defer { if positional { arguments = sequential } }

            func number(into text: inout String) {
                if index < bytes.count, bytes[index] == UInt8(ascii: "*") {
                    text += String(Int32(truncatingIfNeeded: arguments.next()))
                    index += 1
                    return
                }
                while index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) {
                    text.append(Character(UnicodeScalar(bytes[index])))
                    index += 1
                }
            }
            // Flags may come after the width too, as BSD's printf takes
            // them ("%10#llx"): gathered, and put first for the C library.
            var flags = "", width = ""
            while index < bytes.count {
                let byte = bytes[index]
                if "-+ #'".utf8.contains(byte) || (byte == UInt8(ascii: "0") && width.isEmpty) {
                    flags.append(Character(UnicodeScalar(byte)))
                    index += 1
                } else if width.isEmpty, byte == UInt8(ascii: "*") || (UInt8(ascii: "1")...UInt8(ascii: "9")).contains(byte) {
                    number(into: &width)
                } else {
                    break
                }
            }
            var spec = "%" + flags + width
            if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
                spec += "."
                index += 1
                number(into: &spec)
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
                output += c(spec + String(conversion), Double(bitPattern: arguments.nextDouble()))
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
