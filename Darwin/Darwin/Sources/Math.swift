import _DarwinFoundation1._math

// The rest of the <math.h> overlay: the functions that return two values
// as a tuple, the ones taking a String or an Int, the generic ones over
// FloatingPoint, and the constants.

// MARK: Generic functions

@inlinable
public func fabs<T: FloatingPoint>(_ x: T) -> T {
    x.magnitude
}

@inlinable
public func sqrt<T: FloatingPoint>(_ x: T) -> T {
    x.squareRoot()
}

/// x * y + z, rounded once.
@inlinable
public func fma<T: FloatingPoint>(_ x: T, _ y: T, _ z: T) -> T {
    z.addingProduct(x, y)
}

@inlinable
public func remainder<T: FloatingPoint>(_ x: T, _ y: T) -> T {
    x.remainder(dividingBy: y)
}

@inlinable
public func fmod<T: FloatingPoint>(_ x: T, _ y: T) -> T {
    x.truncatingRemainder(dividingBy: y)
}

@inlinable
public func ceil<T: FloatingPoint>(_ x: T) -> T {
    x.rounded(.up)
}

@inlinable
public func floor<T: FloatingPoint>(_ x: T) -> T {
    x.rounded(.down)
}

/// Rounded to the nearest whole number, halves away from zero.
@inlinable
public func round<T: FloatingPoint>(_ x: T) -> T {
    x.rounded(.toNearestOrAwayFromZero)
}

@inlinable
public func trunc<T: FloatingPoint>(_ x: T) -> T {
    x.rounded(.towardZero)
}

/// x times the radix to the power n.
@inlinable
public func scalbn<T: FloatingPoint>(_ x: T, _ n: Int) -> T {
    T(sign: .plus, exponent: T.Exponent(n), significand: x)
}

/// The whole and fractional parts of x, both with x's sign.
@inlinable
public func modf<T: FloatingPoint>(_ x: T) -> (T, T) {
    if x.isNaN { return (x, x) }
    if x.isInfinite { return (x, T(signOf: x, magnitudeOf: 0)) }
    let whole = x.rounded(.towardZero)
    return (whole, T(signOf: x, magnitudeOf: x - whole))
}

/// x as a significand in [0.5, 1) and a power of two.
@inlinable
public func frexp<T: BinaryFloatingPoint>(_ x: T) -> (T, Int) {
    guard x.isFinite, !x.isZero else { return (x, 0) }
    return (x.significand / 2, Int(x.exponent) + 1)
}

public func ldexp(_ x: Float, _ n: Int) -> Float {
    Float(sign: .plus, exponent: n, significand: x)
}

public func ldexp(_ x: Double, _ n: Int) -> Double {
    Double(sign: .plus, exponent: n, significand: x)
}

/// FP_NAN, FP_INFINITE, FP_ZERO, FP_NORMAL or FP_SUBNORMAL.
public func fpclassify<T: FloatingPoint>(_ value: T) -> Int {
    switch value.floatingPointClass {
    case .signalingNaN, .quietNaN: return 1
    case .negativeInfinity, .positiveInfinity: return 2
    case .negativeZero, .positiveZero: return 3
    case .negativeNormal, .positiveNormal: return 4
    case .negativeSubnormal, .positiveSubnormal: return 5
    }
}

public func isnormal<T: FloatingPoint>(_ value: T) -> Bool {
    value.isNormal
}

public func isfinite<T: FloatingPoint>(_ value: T) -> Bool {
    value.isFinite
}

public func isinf<T: FloatingPoint>(_ value: T) -> Bool {
    value.isInfinite
}

public func isnan<T: FloatingPoint>(_ value: T) -> Bool {
    value.isNaN
}

public func signbit<T: FloatingPoint>(_ value: T) -> Int {
    value.sign == .minus ? 1 : 0
}

/// The binary exponent of x; FP_ILOGB0 or FP_ILOGBNAN (INT_MIN) for zero
/// and NaN, INT_MAX for infinity, as the C function answers.
public func ilogb<T: BinaryFloatingPoint>(_ x: T) -> Int {
    if x.isZero || x.isNaN { return Int(Int32.min) }
    if x.isInfinite { return Int(Int32.max) }
    return Int(x.exponent)
}

// MARK: Two results

/// The logarithm of |Γ(x)| and the sign of Γ(x).
public func lgamma(_ x: Float) -> (Float, Int) {
    var sign: Int32 = 0
    let value = lgammaf_r(x, &sign)
    return (value, Int(sign))
}

public func lgamma(_ x: Double) -> (Double, Int) {
    var sign: Int32 = 0
    let value = lgamma_r(x, &sign)
    return (value, Int(sign))
}

#if arch(x86_64) || arch(i386)
public func lgamma(_ x: Float80) -> (Float80, Int) {
    var sign: Int32 = 0
    let value = lgammal_r(x, &sign)
    return (value, Int(sign))
}
#endif

/// The remainder of x / y and some low bits of the quotient.
public func remquo(_ x: Float, _ y: Float) -> (Float, Int) {
    var quotient: Int32 = 0
    let value = remquof(x, y, &quotient)
    return (value, Int(quotient))
}

@_silgen_name("remquo")
private func c_remquo(_ x: Double, _ y: Double, _ quotient: UnsafeMutablePointer<Int32>) -> Double

public func remquo(_ x: Double, _ y: Double) -> (Double, Int) {
    var quotient: Int32 = 0
    let value = c_remquo(x, y, &quotient)
    return (value, Int(quotient))
}

#if arch(x86_64) || arch(i386)
public func remquo(_ x: Float80, _ y: Float80) -> (Float80, Int) {
    var quotient: Int32 = 0
    let value = remquol(x, y, &quotient)
    return (value, Int(quotient))
}
#endif

// MARK: Other arguments

/// A quiet NaN whose payload `tag` names.
public func nan(_ tag: String) -> Float {
    nanf(tag)
}

#if arch(x86_64) || arch(i386)
public func nan(_ tag: String) -> Float80 {
    nanl(tag)
}
#endif

@_silgen_name("jn")
private func c_jn(_ n: Int32, _ x: Double) -> Double

@_silgen_name("yn")
private func c_yn(_ n: Int32, _ x: Double) -> Double

/// The Bessel functions of the first and second kinds, of order n.
public func jn(_ n: Int, _ x: Double) -> Double {
    c_jn(Int32(n), x)
}

public func yn(_ n: Int, _ x: Double) -> Double {
    c_yn(Int32(n), x)
}

// MARK: Constants

public var M_PI: Double { Double.pi }
public var M_PI_2: Double { Double.pi / 2 }
public var M_PI_4: Double { Double.pi / 4 }
public var M_SQRT2: Double { 2.0.squareRoot() }
public var M_SQRT1_2: Double { 0.5.squareRoot() }

// <float.h>, which the standard library's types answer.
@available(swift, deprecated: 3.0, message: "Please use 'T.radix' to get the radix of a FloatingPoint type 'T'.")
public var FLT_RADIX: Int { Double.radix }

public var FLT_MANT_DIG: Int { Float.significandBitCount + 1 }
public var FLT_MAX_EXP: Int { Int(Float.greatestFiniteMagnitude.exponent) + 1 }
public var FLT_MIN_EXP: Int { Int(Float.leastNormalMagnitude.exponent) + 1 }
public var FLT_MAX: Float { Float.greatestFiniteMagnitude }
public var FLT_EPSILON: Float { Float.ulpOfOne }
public var FLT_MIN: Float { Float.leastNormalMagnitude }
public var FLT_TRUE_MIN: Float { Float.leastNonzeroMagnitude }

public var DBL_MANT_DIG: Int { Double.significandBitCount + 1 }
public var DBL_MAX_EXP: Int { Int(Double.greatestFiniteMagnitude.exponent) + 1 }
public var DBL_MIN_EXP: Int { Int(Double.leastNormalMagnitude.exponent) + 1 }
public var DBL_MAX: Double { Double.greatestFiniteMagnitude }
public var DBL_EPSILON: Double { Double.ulpOfOne }
public var DBL_MIN: Double { Double.leastNormalMagnitude }
public var DBL_TRUE_MIN: Double { Double.leastNonzeroMagnitude }

#if arch(x86_64) || arch(i386)
public var LDBL_MANT_DIG: Int { Float80.significandBitCount + 1 }
public var LDBL_MAX_EXP: Int { Int(Float80.greatestFiniteMagnitude.exponent) + 1 }
public var LDBL_MIN_EXP: Int { Int(Float80.leastNormalMagnitude.exponent) + 1 }
public var LDBL_MAX: Float80 { Float80.greatestFiniteMagnitude }
public var LDBL_EPSILON: Float80 { Float80.ulpOfOne }
public var LDBL_MIN: Float80 { Float80.leastNormalMagnitude }
public var LDBL_TRUE_MIN: Float80 { Float80.leastNonzeroMagnitude }
#endif
