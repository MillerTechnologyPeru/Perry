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

    @ObjCMethod("initWithString:")
    func initialize(string: String?) -> UnsafeMutableRawPointer? { setValue(NSDecimalNumber.parse(string)) }

    @ObjCMethod("initWithString:locale:")
    func initialize(string: String?, locale: NSObject?) -> UnsafeMutableRawPointer? { setValue(NSDecimalNumber.parse(string)) }

    @ObjCMethod("initWithMantissa:exponent:isNegative:")
    func initialize(mantissa: UInt64, exponent: Int16, isNegative: Bool) -> UnsafeMutableRawPointer? {
        var value = Double(mantissa)
        for _ in 0 ..< abs(Int(exponent)) { value = exponent > 0 ? value * 10 : value / 10 }
        return setValue(isNegative ? -value : value)
    }

    /// An -init…'s result, +1, as the receiver is released when the method
    /// returns.
    private func setValue(_ value: Double) -> UnsafeMutableRawPointer? {
        ObjC.retain(Numbers.initialize(objcObject, .double(value)))
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

    /// The value rounded to `scale` places by an NSRoundingMode: plain 0,
    /// down 1, up 2, bankers 3; NSDecimalNoScale (Int16.max) leaves it.
    private func rounded(mode: UInt, scale: Int16) -> NSDecimalNumber {
        guard scale != Int16.max, value.isFinite else { return number(value) }
        var factor = 1.0
        for _ in 0 ..< abs(Int(scale)) { factor *= 10 }
        let scaled = scale >= 0 ? value * factor : value / factor
        let whole: Double
        switch mode {
        case 1: whole = scaled.rounded(.down)
        case 2: whole = scaled.rounded(.up)
        case 3: whole = scaled.rounded(.toNearestOrEven)
        default: whole = scaled.rounded(.toNearestOrAwayFromZero)
        }
        return number(scale >= 0 ? whole / factor : whole * factor)
    }

    private func rounded(by behavior: NSObject?) -> NSDecimalNumber {
        guard let behavior else { return self }
        let object = behavior.unsafeCast(to: DecimalBehaviorObject.self)
        return rounded(mode: object.roundingMode(), scale: object.scale())
    }

    @ObjCMethod("decimalNumberByRoundingAccordingToBehavior:")
    func rounding(accordingTo behavior: NSObject?) -> NSDecimalNumber { rounded(by: behavior) }

    @ObjCMethod("decimalNumberByAdding:withBehavior:")
    func adding(_ other: NSNumber, withBehavior behavior: NSObject?) -> NSDecimalNumber { adding(other).rounded(by: behavior) }

    @ObjCMethod("decimalNumberBySubtracting:withBehavior:")
    func subtracting(_ other: NSNumber, withBehavior behavior: NSObject?) -> NSDecimalNumber { subtracting(other).rounded(by: behavior) }

    @ObjCMethod("decimalNumberByMultiplyingBy:withBehavior:")
    func multiplying(by other: NSNumber, withBehavior behavior: NSObject?) -> NSDecimalNumber { multiplying(by: other).rounded(by: behavior) }

    @ObjCMethod("decimalNumberByDividingBy:withBehavior:")
    func dividing(by other: NSNumber, withBehavior behavior: NSObject?) -> NSDecimalNumber { dividing(by: other).rounded(by: behavior) }

    @ObjCMethod("decimalNumberByMultiplyingByPowerOf10:")
    func multiplying(byPowerOf10 power: Int16) -> NSDecimalNumber {
        var result = value
        for _ in 0 ..< abs(Int(power)) { result = power > 0 ? result * 10 : result / 10 }
        return number(result)
    }
}

/// What an NSDecimalNumberBehaviors object answers.
@ObjCWrapper("NSObject")
final class DecimalBehaviorObject: NSObject {
    @ObjCMethod("roundingMode") func roundingMode() -> UInt
    @ObjCMethod("scale") func scale() -> Int16
}

final class DecimalHandlerStorage {
    var mode: UInt = 0
    var scale: Int16 = Int16.max
}

/// NSDecimalNumberHandler: a rounding mode and a scale, the behavior a
/// decimal number rounds by. The raise-on flags are kept out: arithmetic
/// here does not raise.
@ObjCClass("NSDecimalNumberHandler")
public final class NSDecimalNumberHandler: NSObject {
    override public class func didDefineObjCClass(_ cls: ObjCClass) {
        NSObject.registerObjCCategoryStorageAllocated(cls)
    }

    private var storage: DecimalHandlerStorage {
        if let storage = Storage.get(objcObject, as: DecimalHandlerStorage.self) { return storage }
        let storage = DecimalHandlerStorage()
        Storage.set(objcObject, storage)
        return storage
    }

    private static func make(_ cls: ObjCClass) -> NSDecimalNumberHandler? {
        Storage.allocate(cls.pointer).map { NSDecimalNumberHandler(objCOwned: $0) }
    }

    @ObjCClassMethod("defaultDecimalNumberHandler")
    static func defaultHandler(_ cls: ObjCClass) -> NSDecimalNumberHandler? { make(cls) }

    @ObjCClassMethod("decimalNumberHandlerWithRoundingMode:scale:raiseOnExactness:raiseOnOverflow:raiseOnUnderflow:raiseOnDivideByZero:")
    static func handler(_ cls: ObjCClass, roundingMode: UInt, scale: Int16, raiseOnExactness: Bool, raiseOnOverflow: Bool,
                        raiseOnUnderflow: Bool, raiseOnDivideByZero: Bool) -> NSDecimalNumberHandler? {
        let handler = make(cls)
        handler?.storage.mode = roundingMode
        handler?.storage.scale = scale
        return handler
    }

    @ObjCMethod("init") func initialize() -> Self { self }

    @ObjCMethod("initWithRoundingMode:scale:raiseOnExactness:raiseOnOverflow:raiseOnUnderflow:raiseOnDivideByZero:")
    func initialize(roundingMode: UInt, scale: Int16, raiseOnExactness: Bool, raiseOnOverflow: Bool, raiseOnUnderflow: Bool,
                    raiseOnDivideByZero: Bool) -> Self {
        storage.mode = roundingMode
        storage.scale = scale
        return self
    }

    @ObjCMethod("roundingMode") func roundingMode() -> UInt { storage.mode }
    @ObjCMethod("scale") func scale() -> Int16 { storage.scale }
    @ObjCMethod("exceptionDuringOperation:error:leftOperand:rightOperand:")
    func exception(_ operation: UnsafeRawPointer?, error: Int, left: NSObject?, right: NSObject?) -> NSObject? { nil }
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
