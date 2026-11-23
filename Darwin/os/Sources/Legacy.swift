// The argument buffer of os_log(_:_:...) and os_signpost's format
// variant, which take a printf format string and C variadic arguments:
// the format is read for each argument's kind, size and privacy, and the
// argument's words are written as os_log's buffer holds them (the same
// layout OSLogMessage writes).

/// An argument buffer made from a format string and arguments, valid while
/// the instance lives.
internal struct LegacyArguments {
    private(set) var bytes: [UInt8] = [0, 0]

    init(format: UnsafePointer<CChar>, arguments: [any CVarArg]) {
        var remaining = arguments[...]
        var summary: UInt8 = 0
        var count: UInt8 = 0

        func add(_ descriptor: UInt8, _ value: [UInt8]) {
            guard count < maxOSLogArgumentCount else { return }
            bytes.append(descriptor)
            bytes.append(UInt8(value.count))
            bytes.append(contentsOf: value)
            if descriptor & 0x1 != 0 || descriptor & 0xf == 0x5 { summary |= 0x1 }
            if descriptor >> 4 != 0 && descriptor >> 4 != 1 { summary |= 0x2 }
            count += 1
        }

        func next() -> Int {
            guard let argument = remaining.popFirst() else { return 0 }
            return argument._cVarArgEncoding.first ?? 0
        }

        func little<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
            withUnsafeBytes(of: value.littleEndian) { Array($0) }
        }

        var cursor = format
        while cursor.pointee != 0 {
            guard cursor.pointee == CChar(UInt8(ascii: "%")) else {
                cursor += 1
                continue
            }
            cursor += 1
            if cursor.pointee == CChar(UInt8(ascii: "%")) {
                cursor += 1
                continue
            }
            var spec = Specifier()
            cursor = spec.parse(cursor)
            if spec.widthFromArgument { add(0x00 | 0, little(Int32(truncatingIfNeeded: next()))) }
            if spec.precisionFromArgument { add(0x10, little(Int32(truncatingIfNeeded: next()))) }
            let flag = spec.privacyFlag
            switch spec.conversion {
            case "d", "i", "o", "u", "x", "X", "c", "C":
                let word = next()
                if spec.isWide {
                    add(flag, little(Int64(word)))
                } else {
                    add(flag, little(Int32(truncatingIfNeeded: word)))
                }
            case "f", "F", "e", "E", "g", "G", "a", "A":
                add(flag, little(Int64(next())))
            case "p":
                add(flag, little(Int64(next())))
            case "s", "S":
                add(0x20 | flag, little(Int64(next())))
            case "@":
                add(0x40 | flag, little(Int64(next())))
            case "P":
                add(0x30 | flag, little(Int64(next())))
            case "n":
                _ = next()
            default:
                // %m and unknown conversions take no argument.
                break
            }
        }
        bytes[0] = summary
        bytes[1] = count
    }

    /// Calls `body` with the buffer and its size.
    func withBuffer<R>(_ body: (UnsafeMutablePointer<UInt8>, UInt32) throws -> R) rethrows -> R {
        var copy = bytes
        return try copy.withUnsafeMutableBufferPointer { try body($0.baseAddress!, UInt32($0.count)) }
    }
}

/// One conversion of a printf format string.
private struct Specifier {
    var conversion: Character = "\0"
    var isWide = false
    var widthFromArgument = false
    var precisionFromArgument = false
    var privacyFlag: UInt8 = 0

    /// Reads the specifier after its %, returning where the format goes on.
    mutating func parse(_ start: UnsafePointer<CChar>) -> UnsafePointer<CChar> {
        var cursor = start
        func current() -> UInt8 { UInt8(bitPattern: cursor.pointee) }

        // {public}, {private}, {sensitive} and other annotations.
        if current() == UInt8(ascii: "{") {
            var annotation = ""
            cursor += 1
            while current() != 0, current() != UInt8(ascii: "}") {
                annotation.append(Character(Unicode.Scalar(current())))
                cursor += 1
            }
            if current() == UInt8(ascii: "}") { cursor += 1 }
            for word in annotation.split(separator: ",") {
                switch word.trimmingSpaces {
                case "public": privacyFlag = 0x2
                case "private": privacyFlag = 0x1
                case "sensitive": privacyFlag = 0x5
                default: break
                }
            }
        }
        while let flag = Optional(current()), "-+ #0'".utf8.contains(flag), flag != 0 { cursor += 1 }
        if current() == UInt8(ascii: "*") {
            widthFromArgument = true
            cursor += 1
        }
        while (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(current()) { cursor += 1 }
        if current() == UInt8(ascii: ".") {
            cursor += 1
            if current() == UInt8(ascii: "*") {
                precisionFromArgument = true
                cursor += 1
            }
            while (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(current()) { cursor += 1 }
        }
        while let length = Optional(current()), "hlqjztL".utf8.contains(length), length != 0 {
            if "lqjzt".utf8.contains(length) { isWide = true }
            cursor += 1
        }
        if current() != 0 {
            conversion = Character(Unicode.Scalar(current()))
            cursor += 1
        }
        return cursor
    }
}

extension Substring {
    fileprivate var trimmingSpaces: Substring {
        var text = self
        while text.first == " " { text.removeFirst() }
        while text.last == " " { text.removeLast() }
        return text
    }
}

/// A static string's characters as a C string: its own null-terminated
/// storage when it has one.
internal func withCString<R>(_ string: StaticString, _ body: (UnsafePointer<CChar>) throws -> R) rethrows -> R {
    if string.hasPointerRepresentation {
        return try string.utf8Start.withMemoryRebound(to: CChar.self, capacity: string.utf8CodeUnitCount + 1, body)
    }
    return try String(describing: string).withCString(body)
}
