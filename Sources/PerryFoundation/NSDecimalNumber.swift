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
