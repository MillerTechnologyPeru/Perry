import PerryObjCInterop

/// NSDecimalNumber, as an NSNumber holding a double: decimal numbers'
/// arithmetic and parsing, without their 38 digits of precision. Apps name
/// the class among those a property list or JSON value may be, and keep
/// prices in it.
@ObjCClass("NSDecimalNumber")
public class NSDecimalNumber: NSNumber {
    private var value: Double { Numbers.storage(objcObject).double }

    private static func number(_ cls: ObjCClass, _ value: Double) -> NSDecimalNumber {
        Numbers.wrapped(cls, .double(value)).unsafeCast(to: NSDecimalNumber.self)
    }

    private func number(_ value: Double) -> NSDecimalNumber {
        NSDecimalNumber.number(ObjCClass(ObjC.getClass("NSDecimalNumber")!), value)
    }

    /// Not a number when the string isn't one.
    private static func parse(_ string: String?) -> Double {
        string.flatMap { Double($0.filter { !$0.isWhitespace }) } ?? .nan
    }

    @ObjCClassMethod("zero") static func zero(_ cls: ObjCClass) -> NSDecimalNumber { number(cls, 0) }
    @ObjCClassMethod("one") static func one(_ cls: ObjCClass) -> NSDecimalNumber { number(cls, 1) }
    @ObjCClassMethod("notANumber") static func notANumber(_ cls: ObjCClass) -> NSDecimalNumber { number(cls, .nan) }
    @ObjCClassMethod("minimumDecimalNumber")
    static func minimum(_ cls: ObjCClass) -> NSDecimalNumber { number(cls, -.greatestFiniteMagnitude) }
    @ObjCClassMethod("maximumDecimalNumber")
    static func maximum(_ cls: ObjCClass) -> NSDecimalNumber { number(cls, .greatestFiniteMagnitude) }

    @ObjCClassMethod("decimalNumberWithString:")
    static func decimalNumber(_ cls: ObjCClass, string: String?) -> NSDecimalNumber { number(cls, parse(string)) }

    @ObjCClassMethod("decimalNumberWithString:locale:")
    static func decimalNumber(_ cls: ObjCClass, string: String?, locale: NSObject?) -> NSDecimalNumber { number(cls, parse(string)) }

    @ObjCClassMethod("decimalNumberWithMantissa:exponent:isNegative:")
    static func decimalNumber(_ cls: ObjCClass, mantissa: UInt64, exponent: Int16, isNegative: Bool) -> NSDecimalNumber {
        var value = Double(mantissa)
        for _ in 0 ..< abs(Int(exponent)) { value = exponent > 0 ? value * 10 : value / 10 }
        return number(cls, isNegative ? -value : value)
    }

    @ObjCMethod("decimalNumberByAdding:")
    func adding(_ other: NSNumber) -> NSDecimalNumber { number(value + Numbers.storage(other.objcObject).double) }

    @ObjCMethod("decimalNumberBySubtracting:")
    func subtracting(_ other: NSNumber) -> NSDecimalNumber { number(value - Numbers.storage(other.objcObject).double) }

    @ObjCMethod("decimalNumberByMultiplyingBy:")
    func multiplying(by other: NSNumber) -> NSDecimalNumber { number(value * Numbers.storage(other.objcObject).double) }

    /// Dividing by zero gives not a number, as with the default behavior's
    /// exception caught.
    @ObjCMethod("decimalNumberByDividingBy:")
    func dividing(by other: NSNumber) -> NSDecimalNumber {
        let divisor = Numbers.storage(other.objcObject).double
        return number(divisor == 0 ? .nan : value / divisor)
    }

    @ObjCMethod("decimalNumberByMultiplyingByPowerOf10:")
    func multiplying(byPowerOf10 power: Int16) -> NSDecimalNumber {
        var result = value
        for _ in 0 ..< abs(Int(power)) { result = power > 0 ? result * 10 : result / 10 }
        return number(result)
    }
}

/// NSDecimalRound: the number rounded to `scale` places after the point
/// (NSDecimalNoScale, Int16.max, leaves it as it is), by an
/// NSRoundingMode: plain 0 (halves away from zero), down 1 (toward
/// negative infinity), up 2 (toward positive infinity), bankers 3 (halves
/// to even). An NSDecimal is a word of bit fields (the exponent in its low
/// byte, the mantissa's length in the next four bits, then the sign and
/// compact bits) and a mantissa of eight 16-bit digits, least first.
@c(_NSDecimalRound)
public func perryDecimalRound(_ result: UnsafeMutableRawPointer?, _ number: UnsafeRawPointer?, _ scale: Int, _ mode: UInt) {
    guard let result, let number else { return }
    if result != UnsafeMutableRawPointer(mutating: number) { result.copyMemory(from: number, byteCount: 20) }
    let flags = result.load(as: UInt32.self)
    let exponent = Int(Int8(truncatingIfNeeded: flags & 0xff)), length = Int(flags >> 8 & 0xf)
    let negative = flags & 0x1000 != 0
    // Not a number (no digits, negative), no scale, or nothing past it.
    guard scale != Int(Int16.max), length > 0, exponent < -scale else { return }
    var digits = (0..<8).map { $0 < length ? result.load(fromByteOffset: 4 + 2 * $0, as: UInt16.self) : 0 }
    var last = 0, rest = false
    // Drops a decimal digit: the mantissa over ten, the remainder kept.
    for _ in 0..<(-scale - exponent) {
        if last != 0 { rest = true }
        var carry: UInt32 = 0
        for index in stride(from: 7, through: 0, by: -1) {
            let value = carry << 16 | UInt32(digits[index])
            digits[index] = UInt16(value / 10)
            carry = value % 10
        }
        last = Int(carry)
        if digits.allSatisfy({ $0 == 0 }) && last == 0 && !rest { break }
    }
    let inexact = last != 0 || rest
    let up: Bool
    switch mode {
    case 1: up = negative && inexact
    case 2: up = !negative && inexact
    case 3: up = last > 5 || (last == 5 && (rest || digits[0] & 1 == 1))
    default: up = last >= 5
    }
    if up {
        for index in 0..<8 {
            digits[index] &+= 1
            if digits[index] != 0 { break }
        }
    }
    let newLength = (digits.lastIndex { $0 != 0 }).map { $0 + 1 } ?? 0
    for index in 0..<8 { result.storeBytes(of: digits[index], toByteOffset: 4 + 2 * index, as: UInt16.self) }
    // Zero is no digits, no sign and no exponent.
    var newFlags = flags & ~UInt32(0x3fff)
    if newLength > 0 {
        newFlags |= UInt32(UInt8(bitPattern: Int8(clamping: -scale))) | UInt32(newLength) << 8 | (negative ? 0x1000 : 0)
    }
    result.storeBytes(of: newFlags, as: UInt32.self)
}
