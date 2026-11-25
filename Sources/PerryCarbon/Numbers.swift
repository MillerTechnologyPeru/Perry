import GraphiteBase
import PerryObjCInterop
import Synchronization

// SANE's decimal records and 80-bit extended numbers, fixed-point rounding
// and QuickDraw's random numbers, over Graphite's.

/// decimal: sgn and an unused byte, exp, then sig, a Pascal string of up to
/// 36 digits in a 37-byte field and a pad byte: 42 bytes.
private enum DecimalRecord {
    static let size = 42
    static let digits = 5
}

/// void num2dec(const decform *f, double x, decimal *d): decform is style
/// (FLOATDECIMAL 0, FIXEDDECIMAL 1), a pad byte, and digits. A double's
/// argument is where Darwin's ppc ABI leaves it (@DarwinC).
@DarwinC("_num2dec")
public func num2dec(_ form: UnsafeRawPointer?, _ x: Double, _ record: UnsafeMutableRawPointer?) {
    guard let record else { return }
    var decimalForm = DecimalForm.floating(digits: 1)
    if let form {
        let digits = Int(form.loadUnaligned(fromByteOffset: 2, as: Int16.self))
        decimalForm = form.load(as: Int8.self) == 1 ? .fixed(digits: digits) : .floating(digits: digits)
    }
    let decimal = SANEDecimal(x, form: decimalForm)
    record.initializeMemory(as: UInt8.self, repeating: 0, count: DecimalRecord.size)
    record.storeBytes(of: decimal.isNegative ? 1 : 0, as: Int8.self)
    record.storeBytes(of: decimal.exponent, toByteOffset: 2, as: Int16.self)
    record.storeBytes(of: UInt8(decimal.digits.count), toByteOffset: 4, as: UInt8.self)
    for (index, digit) in decimal.digits.enumerated() {
        record.storeBytes(of: digit, toByteOffset: DecimalRecord.digits + index, as: UInt8.self)
    }
}

/// double dec2num(const decimal *d).
@c(_dec2num)
public func dec2num(_ record: UnsafeRawPointer?) -> Double {
    guard let record else { return 0 }
    let count = min(Int(record.load(fromByteOffset: 4, as: UInt8.self)), SANEDecimal.maximumDigits)
    let digits = (0 ..< count).map { record.load(fromByteOffset: DecimalRecord.digits + $0, as: UInt8.self) }
    return SANEDecimal(isNegative: record.load(as: Int8.self) != 0,
                       exponent: record.loadUnaligned(fromByteOffset: 2, as: Int16.self),
                       digits: digits).doubleValue
}

/// void dtox80(const double *x, extended80 *x80): extended80 is the word of
/// sign and exponent, then four words of mantissa, most significant first.
@c(_dtox80)
public func dtox80(_ value: UnsafeRawPointer?, _ extended: UnsafeMutableRawPointer?) {
    guard let value, let extended else { return }
    let result = Extended80(value.loadUnaligned(as: Double.self))
    extended.storeBytes(of: result.signAndExponent, as: UInt16.self)
    for word in 0 ..< 4 {
        extended.storeBytes(of: UInt16(truncatingIfNeeded: result.mantissa >> UInt64(48 - 16 * word)),
                            toByteOffset: 2 + 2 * word, as: UInt16.self)
    }
}

/// double x80tod(const extended80 *x80).
@c(_x80tod)
public func x80tod(_ extended: UnsafeRawPointer?) -> Double {
    guard let extended else { return 0 }
    var mantissa: UInt64 = 0
    for word in 0 ..< 4 {
        mantissa = mantissa << 16 | UInt64(extended.loadUnaligned(fromByteOffset: 2 + 2 * word, as: UInt16.self))
    }
    return Extended80(signAndExponent: extended.loadUnaligned(as: UInt16.self), mantissa: mantissa).doubleValue
}

/// long Fix2Long(Fixed x): the nearest integer.
@c(_Fix2Long)
public func Fix2Long(_ value: Int32) -> Int32 {
    Fixed(rawValue: value).roundedInteger
}

// MARK: - QuickDraw's random numbers

/// randSeed, which QuickDraw starts at 1.
private let random = Mutex(QuickDrawRandom())

/// void SetQDGlobalsRandomSeed(long).
@c(_SetQDGlobalsRandomSeed)
public func SetQDGlobalsRandomSeed(_ seed: Int32) {
    random.withLock { $0.seed = UInt32(bitPattern: seed) }
}

/// short Random(void).
@c(_Random)
public func Random() -> Int16 {
    random.withLock { $0.next() }
}
