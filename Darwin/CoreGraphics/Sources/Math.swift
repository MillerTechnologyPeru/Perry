import Darwin

// The C math library over CGFloat, by way of its native Double (or Float
// on 32-bit targets). The interface makes these transparent, so programs
// mostly carry their own copies; the library keeps them for those that
// call them.

@available(*, unavailable, message: "Use truncatingRemainder instead")
@_transparent public func % (lhs: CGFloat, rhs: CGFloat) -> CGFloat {
    fatalError("% is not available.")
}

@available(*, unavailable, message: "Use formTruncatingRemainder instead")
@_transparent public func %= (lhs: inout CGFloat, rhs: CGFloat) {
    fatalError("%= is not available.")
}

@_transparent public func acos(_ x: CGFloat) -> CGFloat { CGFloat(acos(x.native)) }
@_transparent public func asin(_ x: CGFloat) -> CGFloat { CGFloat(asin(x.native)) }
@_transparent public func atan(_ x: CGFloat) -> CGFloat { CGFloat(atan(x.native)) }
@_transparent public func cos(_ x: CGFloat) -> CGFloat { CGFloat(cos(x.native)) }
@_transparent public func sin(_ x: CGFloat) -> CGFloat { CGFloat(sin(x.native)) }
@_transparent public func tan(_ x: CGFloat) -> CGFloat { CGFloat(tan(x.native)) }
@_transparent public func acosh(_ x: CGFloat) -> CGFloat { CGFloat(acosh(x.native)) }
@_transparent public func asinh(_ x: CGFloat) -> CGFloat { CGFloat(asinh(x.native)) }
@_transparent public func atanh(_ x: CGFloat) -> CGFloat { CGFloat(atanh(x.native)) }
@_transparent public func cosh(_ x: CGFloat) -> CGFloat { CGFloat(cosh(x.native)) }
@_transparent public func sinh(_ x: CGFloat) -> CGFloat { CGFloat(sinh(x.native)) }
@_transparent public func tanh(_ x: CGFloat) -> CGFloat { CGFloat(tanh(x.native)) }
@_transparent public func exp(_ x: CGFloat) -> CGFloat { CGFloat(exp(x.native)) }
@_transparent public func exp2(_ x: CGFloat) -> CGFloat { CGFloat(exp2(x.native)) }
@_transparent public func expm1(_ x: CGFloat) -> CGFloat { CGFloat(expm1(x.native)) }
@_transparent public func log(_ x: CGFloat) -> CGFloat { CGFloat(log(x.native)) }
@_transparent public func log10(_ x: CGFloat) -> CGFloat { CGFloat(log10(x.native)) }
@_transparent public func log1p(_ x: CGFloat) -> CGFloat { CGFloat(log1p(x.native)) }
@_transparent public func log2(_ x: CGFloat) -> CGFloat { CGFloat(log2(x.native)) }
@_transparent public func logb(_ x: CGFloat) -> CGFloat { CGFloat(logb(x.native)) }
@_transparent public func cbrt(_ x: CGFloat) -> CGFloat { CGFloat(cbrt(x.native)) }
@_transparent public func erf(_ x: CGFloat) -> CGFloat { CGFloat(erf(x.native)) }
@_transparent public func erfc(_ x: CGFloat) -> CGFloat { CGFloat(erfc(x.native)) }
@_transparent public func tgamma(_ x: CGFloat) -> CGFloat { CGFloat(tgamma(x.native)) }
@_transparent public func nearbyint(_ x: CGFloat) -> CGFloat { CGFloat(nearbyint(x.native)) }
@_transparent public func rint(_ x: CGFloat) -> CGFloat { CGFloat(rint(x.native)) }

@_transparent public func atan2(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat { CGFloat(atan2(lhs.native, rhs.native)) }
@_transparent public func hypot(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat { CGFloat(hypot(lhs.native, rhs.native)) }
@_transparent public func pow(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat { CGFloat(pow(lhs.native, rhs.native)) }
@_transparent public func copysign(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat { CGFloat(copysign(lhs.native, rhs.native)) }
@_transparent public func nextafter(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat { CGFloat(nextafter(lhs.native, rhs.native)) }
@_transparent public func fdim(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat { CGFloat(fdim(lhs.native, rhs.native)) }
@_transparent public func fmax(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat { CGFloat(fmax(lhs.native, rhs.native)) }
@_transparent public func fmin(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat { CGFloat(fmin(lhs.native, rhs.native)) }

@available(*, unavailable, message: "use the floatingPointClass property.")
@_transparent public func fpclassify(_ x: CGFloat) -> Int {
    fatalError("unavailable")
}

@available(*, unavailable, message: "use the isNormal property.")
public func isnormal(_ value: CGFloat) -> Bool { value.isNormal }

@available(*, unavailable, message: "use the isFinite property.")
public func isfinite(_ value: CGFloat) -> Bool { value.isFinite }

@available(*, unavailable, message: "use the isInfinite property.")
public func isinf(_ value: CGFloat) -> Bool { value.isInfinite }

@available(*, unavailable, message: "use the isNaN property.")
public func isnan(_ value: CGFloat) -> Bool { value.isNaN }

@available(*, unavailable, message: "use the sign property.")
public func signbit(_ value: CGFloat) -> Int { value.sign == .minus ? 1 : 0 }

@available(swift, deprecated: 4.2, renamed: "scalbn")
@_transparent public func ldexp(_ x: CGFloat, _ n: Int) -> CGFloat { CGFloat(ldexp(x.native, n)) }

@available(swift, deprecated: 4.2, message: "use the exponent property.")
@_transparent public func ilogb(_ x: CGFloat) -> Int { Int(x.exponent) }

@_transparent public func lgamma(_ x: CGFloat) -> (CGFloat, Int) {
    let (value, sign) = lgamma(x.native)
    return (CGFloat(value), sign)
}

@_transparent public func remquo(_ x: CGFloat, _ y: CGFloat) -> (CGFloat, Int) {
    let (remainder, quotient) = remquo(x.native, y.native)
    return (CGFloat(remainder), quotient)
}

@available(swift, deprecated: 4.2, message: "use CGFloat(nan: CGFloat.RawSignificand) instead.")
@_transparent public func nan(_ tag: String) -> CGFloat { CGFloat(nan(tag) as CGFloat.NativeType) }

@_transparent public func j0(_ x: CGFloat) -> CGFloat { CGFloat(j0(Double(x.native))) }
@_transparent public func j1(_ x: CGFloat) -> CGFloat { CGFloat(j1(Double(x.native))) }
@_transparent public func jn(_ n: Int, _ x: CGFloat) -> CGFloat { CGFloat(jn(Int32(n), Double(x.native))) }
@_transparent public func y0(_ x: CGFloat) -> CGFloat { CGFloat(y0(Double(x.native))) }
@_transparent public func y1(_ x: CGFloat) -> CGFloat { CGFloat(y1(Double(x.native))) }
@_transparent public func yn(_ n: Int, _ x: CGFloat) -> CGFloat { CGFloat(yn(Int32(n), Double(x.native))) }

extension CGFloat {
    @available(*, unavailable, renamed: "leastNormalMagnitude")
    public static var min: CGFloat { leastNormalMagnitude }

    @available(*, unavailable, renamed: "greatestFiniteMagnitude")
    public static var max: CGFloat { greatestFiniteMagnitude }
}

@available(*, unavailable, renamed: "CGFloat.leastNormalMagnitude")
public var CGFLOAT_MIN: CGFloat { CGFloat.leastNormalMagnitude }

@available(*, unavailable, renamed: "CGFloat.greatestFiniteMagnitude")
public var CGFLOAT_MAX: CGFloat { CGFloat.greatestFiniteMagnitude }

/// The finite CGFloats, for the range checks of the framework's Swift code.
@available(macOS 15.4, iOS 18.4, tvOS 18.4, watchOS 11.4, visionOS 2.4, *)
@usableFromInline
internal let finity: Range<CGFloat> = -CGFloat.greatestFiniteMagnitude ..< CGFloat.infinity

/// The tolerance of the nearly-equal comparisons when none is given: a few
/// units in the last place of numbers around 1.
let defaultNearlyEqualTolerance: CGFloat = CGFloat.ulpOfOne * 16

/// Whether two numbers differ by no more than the tolerance, relative to
/// the larger of them once that is over 1.
func nearlyEqual(_ lhs: CGFloat, _ rhs: CGFloat, _ tolerance: CGFloat) -> Bool {
    if lhs == rhs { return true }
    guard lhs.isFinite, rhs.isFinite else { return false }
    let scale = Swift.max(1, Swift.max(lhs.magnitude, rhs.magnitude))
    return (lhs - rhs).magnitude <= tolerance * scale
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
@_cdecl("CGFloatNearlyEqualToFloat")
@usableFromInline
internal func CGFloatNearlyEqualToFloat(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
    nearlyEqual(lhs, rhs, defaultNearlyEqualTolerance)
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
@_cdecl("CGFloatNearlyEqualToFloatWithTolerance")
@usableFromInline
internal func CGFloatNearlyEqualToFloatWithTolerance(_ lhs: CGFloat, _ rhs: CGFloat, _ tolerance: CGFloat) -> Bool {
    nearlyEqual(lhs, rhs, tolerance)
}
