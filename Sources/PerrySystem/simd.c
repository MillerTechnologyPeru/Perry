// libsystem_m's simd functions: the vector math <simd/math.h> calls for a
// whole simd_float4 or simd_double2 at once, and the matrix inverses
// simd_inverse calls. Each lane is libm's function of that lane.
//
// The vectors are Clang's extended vectors, as Darwin's simd types are, so
// they are passed and returned the way Darwin's compiler passes them: in
// one XMM register each on x86_64 (a matrix, a struct of several, in
// memory), in one V register each on arm64 (a matrix of up to four columns
// in as many). 32-bit Darwin's vector conventions differ from Linux's,
// and no 32-bit program has asked for these, so they are 64-bit only.

#define _GNU_SOURCE
#include "PerrySystem.h"

#include <math.h>

#if defined(__x86_64__) || defined(__aarch64__)

typedef float simd_float2 __attribute__((ext_vector_type(2)));
typedef float simd_float3 __attribute__((ext_vector_type(3)));
typedef float simd_float4 __attribute__((ext_vector_type(4)));
typedef double simd_double2 __attribute__((ext_vector_type(2)));
typedef double simd_double3 __attribute__((ext_vector_type(3)));
typedef double simd_double4 __attribute__((ext_vector_type(4)));

typedef struct { simd_float2 columns[2]; } simd_float2x2;
typedef struct { simd_float3 columns[3]; } simd_float3x3;
typedef struct { simd_float4 columns[4]; } simd_float4x4;
typedef struct { simd_double2 columns[2]; } simd_double2x2;
typedef struct { simd_double3 columns[3]; } simd_double3x3;
typedef struct { simd_double4 columns[4]; } simd_double4x4;

// math.c's sine, cosine and tangent of π times a value, by their Darwin
// names.
extern float darwin___sinpif(float x) __asm__("___sinpif");
extern float darwin___cospif(float x) __asm__("___cospif");
extern float darwin___tanpif(float x) __asm__("___tanpif");
extern double darwin___sinpi(double x) __asm__("___sinpi");
extern double darwin___cospi(double x) __asm__("___cospi");
extern double darwin___tanpi(double x) __asm__("___tanpi");

// MARK: - Lane-wise functions

#define UNARY(name, ffunc, dfunc)                                                          \
    simd_float4 darwin__simd_##name##_f4(simd_float4 x) DARWIN_SYMBOL(_simd_##name##_f4);  \
    simd_float4 darwin__simd_##name##_f4(simd_float4 x) {                                  \
        simd_float4 r;                                                                     \
        for (int i = 0; i < 4; i++) r[i] = ffunc(x[i]);                                    \
        return r;                                                                          \
    }                                                                                      \
    simd_double2 darwin__simd_##name##_d2(simd_double2 x) DARWIN_SYMBOL(_simd_##name##_d2); \
    simd_double2 darwin__simd_##name##_d2(simd_double2 x) {                                \
        simd_double2 r;                                                                    \
        for (int i = 0; i < 2; i++) r[i] = dfunc(x[i]);                                    \
        return r;                                                                          \
    }

#define BINARY(name, ffunc, dfunc)                                                                         \
    simd_float4 darwin__simd_##name##_f4(simd_float4 x, simd_float4 y) DARWIN_SYMBOL(_simd_##name##_f4);   \
    simd_float4 darwin__simd_##name##_f4(simd_float4 x, simd_float4 y) {                                   \
        simd_float4 r;                                                                                     \
        for (int i = 0; i < 4; i++) r[i] = ffunc(x[i], y[i]);                                              \
        return r;                                                                                          \
    }                                                                                                      \
    simd_double2 darwin__simd_##name##_d2(simd_double2 x, simd_double2 y) DARWIN_SYMBOL(_simd_##name##_d2); \
    simd_double2 darwin__simd_##name##_d2(simd_double2 x, simd_double2 y) {                                \
        simd_double2 r;                                                                                    \
        for (int i = 0; i < 2; i++) r[i] = dfunc(x[i], y[i]);                                              \
        return r;                                                                                          \
    }

UNARY(acos, acosf, acos)
UNARY(acosh, acoshf, acosh)
UNARY(asin, asinf, asin)
UNARY(asinh, asinhf, asinh)
UNARY(atan, atanf, atan)
UNARY(atanh, atanhf, atanh)
UNARY(cbrt, cbrtf, cbrt)
UNARY(cos, cosf, cos)
UNARY(cosh, coshf, cosh)
UNARY(cospi, darwin___cospif, darwin___cospi)
UNARY(erf, erff, erf)
UNARY(erfc, erfcf, erfc)
UNARY(exp, expf, exp)
UNARY(exp10, exp10f, exp10)
UNARY(exp2, exp2f, exp2)
UNARY(expm1, expm1f, expm1)
UNARY(lgamma, lgammaf, lgamma)
UNARY(log, logf, log)
UNARY(log10, log10f, log10)
UNARY(log1p, log1pf, log1p)
UNARY(log2, log2f, log2)
UNARY(round, roundf, round)
UNARY(sin, sinf, sin)
UNARY(sinh, sinhf, sinh)
UNARY(sinpi, darwin___sinpif, darwin___sinpi)
UNARY(tan, tanf, tan)
UNARY(tanh, tanhf, tanh)
UNARY(tanpi, darwin___tanpif, darwin___tanpi)
UNARY(tgamma, tgammaf, tgamma)

BINARY(atan2, atan2f, atan2)
BINARY(fmod, fmodf, fmod)
BINARY(hypot, hypotf, hypot)
BINARY(nextafter, nextafterf, nextafter)
BINARY(pow, powf, pow)
BINARY(remainder, remainderf, remainder)

simd_float4 darwin__simd_fma_f4(simd_float4 x, simd_float4 y, simd_float4 z) DARWIN_SYMBOL(_simd_fma_f4);
simd_float4 darwin__simd_fma_f4(simd_float4 x, simd_float4 y, simd_float4 z) {
    simd_float4 r;
    for (int i = 0; i < 4; i++) r[i] = fmaf(x[i], y[i], z[i]);
    return r;
}

simd_double2 darwin__simd_fma_d2(simd_double2 x, simd_double2 y, simd_double2 z) DARWIN_SYMBOL(_simd_fma_d2);
simd_double2 darwin__simd_fma_d2(simd_double2 x, simd_double2 y, simd_double2 z) {
    simd_double2 r;
    for (int i = 0; i < 2; i++) r[i] = fma(x[i], y[i], z[i]);
    return r;
}

// Sine and cosine together, through pointers.
void darwin__simd_sincos_f4(simd_float4 x, simd_float4 *s, simd_float4 *c) DARWIN_SYMBOL(_simd_sincos_f4);
void darwin__simd_sincos_f4(simd_float4 x, simd_float4 *s, simd_float4 *c) {
    simd_float4 rs, rc;
    for (int i = 0; i < 4; i++) {
        float a, b;
        sincosf(x[i], &a, &b);
        rs[i] = a, rc[i] = b;
    }
    *s = rs, *c = rc;
}

void darwin__simd_sincos_d2(simd_double2 x, simd_double2 *s, simd_double2 *c) DARWIN_SYMBOL(_simd_sincos_d2);
void darwin__simd_sincos_d2(simd_double2 x, simd_double2 *s, simd_double2 *c) {
    simd_double2 rs, rc;
    for (int i = 0; i < 2; i++) {
        double a, b;
        sincos(x[i], &a, &b);
        rs[i] = a, rc[i] = b;
    }
    *s = rs, *c = rc;
}

void darwin__simd_sincospi_f4(simd_float4 x, simd_float4 *s, simd_float4 *c) DARWIN_SYMBOL(_simd_sincospi_f4);
void darwin__simd_sincospi_f4(simd_float4 x, simd_float4 *s, simd_float4 *c) {
    simd_float4 rs, rc;
    for (int i = 0; i < 4; i++) rs[i] = darwin___sinpif(x[i]), rc[i] = darwin___cospif(x[i]);
    *s = rs, *c = rc;
}

void darwin__simd_sincospi_d2(simd_double2 x, simd_double2 *s, simd_double2 *c) DARWIN_SYMBOL(_simd_sincospi_d2);
void darwin__simd_sincospi_d2(simd_double2 x, simd_double2 *s, simd_double2 *c) {
    simd_double2 rs, rc;
    for (int i = 0; i < 2; i++) rs[i] = darwin___sinpi(x[i]), rc[i] = darwin___cospi(x[i]);
    *s = rs, *c = rc;
}

// MARK: - Matrix inverses

// The adjugate times the determinant's reciprocal, in the matrix's own
// precision: a singular matrix's reciprocal is infinite, so its inverse
// is infinities (and NaNs where a cofactor is 0), as Darwin's is; a zero
// is +0, as there. Matrices are kept by columns, m[column][row].
#define INVERSE(T, suffix)                                                                  \
    static T det_##suffix(int n, T a[4][4]) {                                               \
        if (n == 1) return a[0][0];                                                         \
        if (n == 2) return a[0][0] * a[1][1] - a[1][0] * a[0][1];                           \
        T sum = 0;                                                                          \
        for (int c = 0; c < n; c++) {                                                       \
            T minor[4][4];                                                                  \
            for (int i = 0, mc = 0; i < n; i++) {                                           \
                if (i == c) continue;                                                       \
                for (int r = 1; r < n; r++) minor[mc][r - 1] = a[i][r];                     \
                mc++;                                                                       \
            }                                                                               \
            T term = a[c][0] * det_##suffix(n - 1, minor);                                  \
            sum += c % 2 ? -term : term;                                                    \
        }                                                                                   \
        return sum;                                                                         \
    }                                                                                       \
    /* The cofactor of row `row`, column `col`. */                                          \
    static T cofactor_##suffix(int n, T a[4][4], int row, int col) {                        \
        T minor[4][4];                                                                      \
        for (int c = 0, mc = 0; c < n; c++) {                                               \
            if (c == col) continue;                                                         \
            for (int r = 0, mr = 0; r < n; r++) {                                           \
                if (r == row) continue;                                                     \
                minor[mc][mr++] = a[c][r];                                                  \
            }                                                                               \
            mc++;                                                                           \
        }                                                                                   \
        T d = det_##suffix(n - 1, minor);                                                   \
        return (row + col) % 2 ? -d : d;                                                    \
    }                                                                                       \
    static void invert_##suffix(int n, T a[4][4], T out[4][4]) {                            \
        T scale = 1 / det_##suffix(n, a);                                                   \
        /* The inverse's row r, column c is the cofactor of row c, column r. */             \
        for (int c = 0; c < n; c++)                                                         \
            for (int r = 0; r < n; r++) out[c][r] = cofactor_##suffix(n, a, c, r) * scale + 0; \
    }

INVERSE(float, f)
INVERSE(double, d)

#define INVERT(name, type, T, suffix, n)                                     \
    type darwin_##name(type x) DARWIN_SYMBOL(name);                          \
    type darwin_##name(type x) {                                             \
        T m[4][4], r[4][4];                                                  \
        for (int c = 0; c < n; c++)                                          \
            for (int k = 0; k < n; k++) m[c][k] = x.columns[c][k];           \
        invert_##suffix(n, m, r);                                            \
        type result = x;                                                     \
        for (int c = 0; c < n; c++)                                          \
            for (int k = 0; k < n; k++) result.columns[c][k] = r[c][k];      \
        return result;                                                       \
    }

INVERT(__invert_f2, simd_float2x2, float, f, 2)
INVERT(__invert_f3, simd_float3x3, float, f, 3)
INVERT(__invert_f4, simd_float4x4, float, f, 4)
INVERT(__invert_d2, simd_double2x2, double, d, 2)
INVERT(__invert_d3, simd_double3x3, double, d, 3)
INVERT(__invert_d4, simd_double4x4, double, d, 4)

#endif
