// Apple's math additions to libm, which Darwin's compilers call for sin
// and cos of one value together (returning both in registers, as a struct
// of two) and for sine, cosine and tangent of π times a value. On armv7, also
// libm's own functions, which take and return floating point in core
// registers there (DARWIN_FLOAT_ABI) and so cannot be glibc's.

#define _GNU_SOURCE
#include "PerrySystem.h"

#include <complex.h>
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

struct darwin_float2 { float sinval, cosval; };
struct darwin_double2 { double sinval, cosval; };

DARWIN_FLOAT_ABI struct darwin_float2 darwin___sincosf_stret(float x) DARWIN_SYMBOL(__sincosf_stret);
DARWIN_FLOAT_ABI struct darwin_float2 darwin___sincosf_stret(float x) {
    struct darwin_float2 result;
    sincosf(x, &result.sinval, &result.cosval);
    return result;
}

DARWIN_FLOAT_ABI struct darwin_double2 darwin___sincos_stret(double x) DARWIN_SYMBOL(__sincos_stret);
DARWIN_FLOAT_ABI struct darwin_double2 darwin___sincos_stret(double x) {
    struct darwin_double2 result;
    sincos(x, &result.sinval, &result.cosval);
    return result;
}

// π times x, reduced to a turn either way first.
static double pi_times(double x) { return remainder(x, 2.0) * M_PI; }

DARWIN_FLOAT_ABI double darwin___sinpi(double x) DARWIN_SYMBOL(__sinpi);
DARWIN_FLOAT_ABI double darwin___sinpi(double x) {
    double r = remainder(x, 2.0);
    if (r == 0 || r == 1 || r == -1) return copysign(0.0, x);
    if (r == 0.5) return 1;
    if (r == -0.5) return -1;
    return sin(pi_times(x));
}

DARWIN_FLOAT_ABI double darwin___cospi(double x) DARWIN_SYMBOL(__cospi);
DARWIN_FLOAT_ABI double darwin___cospi(double x) {
    double r = fabs(remainder(x, 2.0));
    if (r == 0.5) return 0;
    if (r == 0) return 1;
    if (r == 1) return -1;
    return cos(pi_times(x));
}

DARWIN_FLOAT_ABI double darwin___tanpi(double x) DARWIN_SYMBOL(__tanpi);
DARWIN_FLOAT_ABI double darwin___tanpi(double x) { return darwin___sinpi(x) / darwin___cospi(x); }

DARWIN_FLOAT_ABI float darwin___sinpif(float x) DARWIN_SYMBOL(__sinpif);
DARWIN_FLOAT_ABI float darwin___sinpif(float x) { return (float)darwin___sinpi(x); }

DARWIN_FLOAT_ABI float darwin___cospif(float x) DARWIN_SYMBOL(__cospif);
DARWIN_FLOAT_ABI float darwin___cospif(float x) { return (float)darwin___cospi(x); }

DARWIN_FLOAT_ABI float darwin___tanpif(float x) DARWIN_SYMBOL(__tanpif);
DARWIN_FLOAT_ABI float darwin___tanpif(float x) { return (float)darwin___tanpi(x); }

DARWIN_FLOAT_ABI struct darwin_float2 darwin___sincospif_stret(float x) DARWIN_SYMBOL(__sincospif_stret);
DARWIN_FLOAT_ABI struct darwin_float2 darwin___sincospif_stret(float x) {
    struct darwin_float2 result = { darwin___sinpif(x), darwin___cospif(x) };
    return result;
}

DARWIN_FLOAT_ABI struct darwin_double2 darwin___sincospi_stret(double x) DARWIN_SYMBOL(__sincospi_stret);
DARWIN_FLOAT_ABI struct darwin_double2 darwin___sincospi_stret(double x) {
    struct darwin_double2 result = { darwin___sinpi(x), darwin___cospi(x) };
    return result;
}

#if defined(__arm__)
// MARK: - libm and the rest of libc's floating point on armv7

#define F1(name, type)                                                       \
    DARWIN_FLOAT_ABI type darwin_##name(type x) DARWIN_SYMBOL(name);         \
    DARWIN_FLOAT_ABI type darwin_##name(type x) { return name(x); }
#define F2(name, type)                                                       \
    DARWIN_FLOAT_ABI type darwin_##name(type x, type y) DARWIN_SYMBOL(name); \
    DARWIN_FLOAT_ABI type darwin_##name(type x, type y) { return name(x, y); }
#define F_ARG(name, type, arg)                                               \
    DARWIN_FLOAT_ABI type darwin_##name(type x, arg a) DARWIN_SYMBOL(name);  \
    DARWIN_FLOAT_ABI type darwin_##name(type x, arg a) { return name(x, a); }

F1(acos, double) F1(asin, double) F1(atan, double) F1(cbrt, double) F1(ceil, double) F1(cos, double)
F1(cosh, double) F1(exp, double) F1(exp2, double) F1(expm1, double) F1(fabs, double) F1(floor, double)
F1(log, double) F1(log10, double) F1(log1p, double) F1(log2, double) F1(logb, double) F1(rint, double)
F1(round, double) F1(sin, double) F1(sinh, double) F1(sqrt, double) F1(tan, double) F1(tanh, double)
F1(trunc, double) F1(acosh, double) F1(asinh, double) F1(atanh, double) F1(erf, double) F1(erfc, double)
F1(tgamma, double) F1(lgamma, double) F1(nearbyint, double)
F1(acosf, float) F1(acoshf, float) F1(asinf, float) F1(asinhf, float) F1(atanf, float) F1(atanhf, float)
F1(cbrtf, float) F1(ceilf, float) F1(cosf, float) F1(coshf, float) F1(erfcf, float) F1(erff, float)
F1(exp2f, float) F1(expf, float) F1(expm1f, float) F1(fabsf, float) F1(floorf, float) F1(log10f, float)
F1(log1pf, float) F1(log2f, float) F1(logbf, float) F1(logf, float) F1(rintf, float) F1(roundf, float)
F1(sinf, float) F1(sinhf, float) F1(sqrtf, float) F1(tanf, float) F1(tanhf, float) F1(tgammaf, float)
F1(truncf, float) F1(lgammaf, float) F1(nearbyintf, float)
F2(atan2, double) F2(copysign, double) F2(fdim, double) F2(fmax, double) F2(fmin, double) F2(fmod, double)
F2(hypot, double) F2(nextafter, double) F2(pow, double) F2(remainder, double)
F2(atan2f, float) F2(copysignf, float) F2(fdimf, float) F2(fmaxf, float) F2(fminf, float) F2(fmodf, float)
F2(hypotf, float) F2(nextafterf, float) F2(powf, float) F2(remainderf, float)
F_ARG(ldexp, double, int) F_ARG(scalbn, double, int) F_ARG(frexp, double, int *) F_ARG(modf, double, double *)
F_ARG(lgamma_r, double, int *) F_ARG(ldexpf, float, int) F_ARG(scalbnf, float, int) F_ARG(frexpf, float, int *)
F_ARG(modff, float, float *) F_ARG(lgammaf_r, float, int *)

// long double is double on both.
F2(fmodl, double) F_ARG(lgammal_r, double, int *)

DARWIN_FLOAT_ABI double darwin___exp10(double x) DARWIN_SYMBOL(__exp10);
DARWIN_FLOAT_ABI double darwin___exp10(double x) { return exp10(x); }
DARWIN_FLOAT_ABI float darwin___exp10f(float x) DARWIN_SYMBOL(__exp10f);
DARWIN_FLOAT_ABI float darwin___exp10f(float x) { return exp10f(x); }

DARWIN_FLOAT_ABI double darwin_fma(double x, double y, double z) DARWIN_SYMBOL(fma);
DARWIN_FLOAT_ABI double darwin_fma(double x, double y, double z) { return fma(x, y, z); }
DARWIN_FLOAT_ABI float darwin_fmaf(float x, float y, float z) DARWIN_SYMBOL(fmaf);
DARWIN_FLOAT_ABI float darwin_fmaf(float x, float y, float z) { return fmaf(x, y, z); }
DARWIN_FLOAT_ABI double darwin_remquo(double x, double y, int *q) DARWIN_SYMBOL(remquo);
DARWIN_FLOAT_ABI double darwin_remquo(double x, double y, int *q) { return remquo(x, y, q); }
DARWIN_FLOAT_ABI float darwin_remquof(float x, float y, int *q) DARWIN_SYMBOL(remquof);
DARWIN_FLOAT_ABI float darwin_remquof(float x, float y, int *q) { return remquof(x, y, q); }
DARWIN_FLOAT_ABI long darwin_lround(double x) DARWIN_SYMBOL(lround);
DARWIN_FLOAT_ABI long darwin_lround(double x) { return lround(x); }
DARWIN_FLOAT_ABI long darwin_lroundf(float x) DARWIN_SYMBOL(lroundf);
DARWIN_FLOAT_ABI long darwin_lroundf(float x) { return lroundf(x); }
DARWIN_FLOAT_ABI long long darwin_llround(double x) DARWIN_SYMBOL(llround);
DARWIN_FLOAT_ABI long long darwin_llround(double x) { return llround(x); }
DARWIN_FLOAT_ABI long darwin_lrint(double x) DARWIN_SYMBOL(lrint);
DARWIN_FLOAT_ABI long darwin_lrint(double x) { return lrint(x); }
DARWIN_FLOAT_ABI float darwin_nanf(const char *tag) DARWIN_SYMBOL(nanf);
DARWIN_FLOAT_ABI float darwin_nanf(const char *tag) { return nanf(tag); }
DARWIN_FLOAT_ABI double darwin_nan(const char *tag) DARWIN_SYMBOL(nan);
DARWIN_FLOAT_ABI double darwin_nan(const char *tag) { return nan(tag); }
DARWIN_FLOAT_ABI double darwin_cabs(double complex z) DARWIN_SYMBOL(cabs);
DARWIN_FLOAT_ABI double darwin_cabs(double complex z) { return cabs(z); }

// jn and yn take the int first, which puts the double in r1 and r2 on
// Darwin, where AAPCS would skip to r2 and r3: they take its words.
static double from_words(uint32_t low, uint32_t high) {
    uint64_t bits = (uint64_t)high << 32 | low;
    double value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}

DARWIN_FLOAT_ABI double darwin_jn(int n, uint32_t low, uint32_t high) DARWIN_SYMBOL(jn);
DARWIN_FLOAT_ABI double darwin_jn(int n, uint32_t low, uint32_t high) { return jn(n, from_words(low, high)); }
DARWIN_FLOAT_ABI double darwin_yn(int n, uint32_t low, uint32_t high) DARWIN_SYMBOL(yn);
DARWIN_FLOAT_ABI double darwin_yn(int n, uint32_t low, uint32_t high) { return yn(n, from_words(low, high)); }

// Conversions and the rest of libc's floating point. The _l forms format in
// the C locale, as on arm64.
DARWIN_FLOAT_ABI double darwin_atof(const char *s) DARWIN_SYMBOL(atof);
DARWIN_FLOAT_ABI double darwin_atof(const char *s) { return atof(s); }
DARWIN_FLOAT_ABI double darwin_strtod(const char *s, char **end) DARWIN_SYMBOL(strtod);
DARWIN_FLOAT_ABI double darwin_strtod(const char *s, char **end) { return strtod(s, end); }
DARWIN_FLOAT_ABI float darwin_strtof(const char *s, char **end) DARWIN_SYMBOL(strtof);
DARWIN_FLOAT_ABI float darwin_strtof(const char *s, char **end) { return strtof(s, end); }
DARWIN_FLOAT_ABI double darwin_strtod_l(const char *s, char **end, void *locale) DARWIN_SYMBOL(strtod_l);
DARWIN_FLOAT_ABI double darwin_strtod_l(const char *s, char **end, void *locale) { (void)locale; return strtod(s, end); }
DARWIN_FLOAT_ABI float darwin_strtof_l(const char *s, char **end, void *locale) DARWIN_SYMBOL(strtof_l);
DARWIN_FLOAT_ABI float darwin_strtof_l(const char *s, char **end, void *locale) { (void)locale; return strtof(s, end); }
DARWIN_FLOAT_ABI double darwin_strtold_l(const char *s, char **end, void *locale) DARWIN_SYMBOL(strtold_l);
DARWIN_FLOAT_ABI double darwin_strtold_l(const char *s, char **end, void *locale) { (void)locale; return strtod(s, end); }
DARWIN_FLOAT_ABI double darwin_difftime(time_t end, time_t start) DARWIN_SYMBOL(difftime);
DARWIN_FLOAT_ABI double darwin_difftime(time_t end, time_t start) { return difftime(end, start); }
DARWIN_FLOAT_ABI double darwin_drand48(void) DARWIN_SYMBOL(drand48);
DARWIN_FLOAT_ABI double darwin_drand48(void) { return drand48(); }
#endif
