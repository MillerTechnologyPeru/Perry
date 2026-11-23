import _DarwinFoundation1._math

// The <math.h> overloads of the Swift overlay: each C function for Float
// and Float80 as well as Double, the generic ones written over the
// standard library's FloatingPoint, and the constants of <float.h> and
// <math.h>. The overloads call the C library's own f- and l-suffixed
// functions.

// MARK: One argument


public func acos(_ x: Float) -> Float {
    acosf(x)
}

#if arch(x86_64) || arch(i386)
public func acos(_ x: Float80) -> Float80 {
    acosl(x)
}
#endif

public func asin(_ x: Float) -> Float {
    asinf(x)
}

#if arch(x86_64) || arch(i386)
public func asin(_ x: Float80) -> Float80 {
    asinl(x)
}
#endif

public func atan(_ x: Float) -> Float {
    atanf(x)
}

#if arch(x86_64) || arch(i386)
public func atan(_ x: Float80) -> Float80 {
    atanl(x)
}
#endif

public func tan(_ x: Float) -> Float {
    tanf(x)
}

#if arch(x86_64) || arch(i386)
public func tan(_ x: Float80) -> Float80 {
    tanl(x)
}
#endif

public func acosh(_ x: Float) -> Float {
    acoshf(x)
}

#if arch(x86_64) || arch(i386)
public func acosh(_ x: Float80) -> Float80 {
    acoshl(x)
}
#endif

public func asinh(_ x: Float) -> Float {
    asinhf(x)
}

#if arch(x86_64) || arch(i386)
public func asinh(_ x: Float80) -> Float80 {
    asinhl(x)
}
#endif

public func atanh(_ x: Float) -> Float {
    atanhf(x)
}

#if arch(x86_64) || arch(i386)
public func atanh(_ x: Float80) -> Float80 {
    atanhl(x)
}
#endif

public func cosh(_ x: Float) -> Float {
    coshf(x)
}

#if arch(x86_64) || arch(i386)
public func cosh(_ x: Float80) -> Float80 {
    coshl(x)
}
#endif

public func sinh(_ x: Float) -> Float {
    sinhf(x)
}

#if arch(x86_64) || arch(i386)
public func sinh(_ x: Float80) -> Float80 {
    sinhl(x)
}
#endif

public func tanh(_ x: Float) -> Float {
    tanhf(x)
}

#if arch(x86_64) || arch(i386)
public func tanh(_ x: Float80) -> Float80 {
    tanhl(x)
}
#endif

public func expm1(_ x: Float) -> Float {
    expm1f(x)
}

#if arch(x86_64) || arch(i386)
public func expm1(_ x: Float80) -> Float80 {
    expm1l(x)
}
#endif

public func log1p(_ x: Float) -> Float {
    log1pf(x)
}

#if arch(x86_64) || arch(i386)
public func log1p(_ x: Float80) -> Float80 {
    log1pl(x)
}
#endif

public func logb(_ x: Float) -> Float {
    logbf(x)
}

#if arch(x86_64) || arch(i386)
public func logb(_ x: Float80) -> Float80 {
    logbl(x)
}
#endif

public func cbrt(_ x: Float) -> Float {
    cbrtf(x)
}

#if arch(x86_64) || arch(i386)
public func cbrt(_ x: Float80) -> Float80 {
    cbrtl(x)
}
#endif

public func erf(_ x: Float) -> Float {
    erff(x)
}

#if arch(x86_64) || arch(i386)
public func erf(_ x: Float80) -> Float80 {
    erfl(x)
}
#endif

public func erfc(_ x: Float) -> Float {
    erfcf(x)
}

#if arch(x86_64) || arch(i386)
public func erfc(_ x: Float80) -> Float80 {
    erfcl(x)
}
#endif

public func tgamma(_ x: Float) -> Float {
    tgammaf(x)
}

#if arch(x86_64) || arch(i386)
public func tgamma(_ x: Float80) -> Float80 {
    tgammal(x)
}
#endif

public func cos(_ x: Float) -> Float {
    cosf(x)
}

#if arch(x86_64) || arch(i386)
public func cos(_ x: Float80) -> Float80 {
    cosl(x)
}
#endif

public func sin(_ x: Float) -> Float {
    sinf(x)
}

#if arch(x86_64) || arch(i386)
public func sin(_ x: Float80) -> Float80 {
    sinl(x)
}
#endif

public func exp(_ x: Float) -> Float {
    expf(x)
}

#if arch(x86_64) || arch(i386)
public func exp(_ x: Float80) -> Float80 {
    expl(x)
}
#endif

public func exp2(_ x: Float) -> Float {
    exp2f(x)
}

#if arch(x86_64) || arch(i386)
public func exp2(_ x: Float80) -> Float80 {
    exp2l(x)
}
#endif

public func log(_ x: Float) -> Float {
    logf(x)
}

#if arch(x86_64) || arch(i386)
public func log(_ x: Float80) -> Float80 {
    logl(x)
}
#endif

public func log10(_ x: Float) -> Float {
    log10f(x)
}

#if arch(x86_64) || arch(i386)
public func log10(_ x: Float80) -> Float80 {
    log10l(x)
}
#endif

public func log2(_ x: Float) -> Float {
    log2f(x)
}

#if arch(x86_64) || arch(i386)
public func log2(_ x: Float80) -> Float80 {
    log2l(x)
}
#endif

public func nearbyint(_ x: Float) -> Float {
    nearbyintf(x)
}

#if arch(x86_64) || arch(i386)
public func nearbyint(_ x: Float80) -> Float80 {
    nearbyintl(x)
}
#endif

public func rint(_ x: Float) -> Float {
    rintf(x)
}

#if arch(x86_64) || arch(i386)
public func rint(_ x: Float80) -> Float80 {
    rintl(x)
}
#endif

// The Double overloads the overlay adds beside the C functions' own
// import, calling the C library's functions by name.

@_silgen_name("cos") private func c_cos(_ x: Double) -> Double

@_silgen_name("sin") private func c_sin(_ x: Double) -> Double

@_silgen_name("exp") private func c_exp(_ x: Double) -> Double

@_silgen_name("exp2") private func c_exp2(_ x: Double) -> Double

@_silgen_name("log") private func c_log(_ x: Double) -> Double

@_silgen_name("log10") private func c_log10(_ x: Double) -> Double

@_silgen_name("log2") private func c_log2(_ x: Double) -> Double

@_silgen_name("nearbyint") private func c_nearbyint(_ x: Double) -> Double

@_silgen_name("rint") private func c_rint(_ x: Double) -> Double


public func cos(_ x: Double) -> Double {
    c_cos(x)
}

public func sin(_ x: Double) -> Double {
    c_sin(x)
}

public func exp(_ x: Double) -> Double {
    c_exp(x)
}

public func exp2(_ x: Double) -> Double {
    c_exp2(x)
}

public func log(_ x: Double) -> Double {
    c_log(x)
}

public func log10(_ x: Double) -> Double {
    c_log10(x)
}

public func log2(_ x: Double) -> Double {
    c_log2(x)
}

public func nearbyint(_ x: Double) -> Double {
    c_nearbyint(x)
}

public func rint(_ x: Double) -> Double {
    c_rint(x)
}

// MARK: Two arguments

public func atan2(_ lhs: Float, _ rhs: Float) -> Float {
    atan2f(lhs, rhs)
}

#if arch(x86_64) || arch(i386)
public func atan2(_ lhs: Float80, _ rhs: Float80) -> Float80 {
    atan2l(lhs, rhs)
}
#endif

public func hypot(_ lhs: Float, _ rhs: Float) -> Float {
    hypotf(lhs, rhs)
}

#if arch(x86_64) || arch(i386)
public func hypot(_ lhs: Float80, _ rhs: Float80) -> Float80 {
    hypotl(lhs, rhs)
}
#endif

public func pow(_ lhs: Float, _ rhs: Float) -> Float {
    powf(lhs, rhs)
}

#if arch(x86_64) || arch(i386)
public func pow(_ lhs: Float80, _ rhs: Float80) -> Float80 {
    powl(lhs, rhs)
}
#endif

public func copysign(_ lhs: Float, _ rhs: Float) -> Float {
    copysignf(lhs, rhs)
}

#if arch(x86_64) || arch(i386)
public func copysign(_ lhs: Float80, _ rhs: Float80) -> Float80 {
    copysignl(lhs, rhs)
}
#endif

public func nextafter(_ lhs: Float, _ rhs: Float) -> Float {
    nextafterf(lhs, rhs)
}

#if arch(x86_64) || arch(i386)
public func nextafter(_ lhs: Float80, _ rhs: Float80) -> Float80 {
    nextafterl(lhs, rhs)
}
#endif

public func fdim(_ lhs: Float, _ rhs: Float) -> Float {
    fdimf(lhs, rhs)
}

#if arch(x86_64) || arch(i386)
public func fdim(_ lhs: Float80, _ rhs: Float80) -> Float80 {
    fdiml(lhs, rhs)
}
#endif

public func fmax(_ lhs: Float, _ rhs: Float) -> Float {
    fmaxf(lhs, rhs)
}

#if arch(x86_64) || arch(i386)
public func fmax(_ lhs: Float80, _ rhs: Float80) -> Float80 {
    fmaxl(lhs, rhs)
}
#endif

public func fmin(_ lhs: Float, _ rhs: Float) -> Float {
    fminf(lhs, rhs)
}

#if arch(x86_64) || arch(i386)
public func fmin(_ lhs: Float80, _ rhs: Float80) -> Float80 {
    fminl(lhs, rhs)
}
#endif
