// vDSP: the rest of the element-wise vector functions (compound
// multiply-adds, interpolation, tables, thresholds, gathers, integration,
// polar coordinates, split-complex arithmetic and conversions), in single
// and double precision.

#include "PerryAccelerate.h"

#include <math.h>
#include <string.h>

#define EXPORT(ret, name, params) ret name params DARWIN_SYMBOL(name); ret name params

// MARK: - Compound arithmetic

// Four vector operands: E = f(A, B, C, D).
#define QUAD(name, type, expr) \
    EXPORT(void, vDSP_##name, (const type *A, vDSP_Stride IA, const type *B, vDSP_Stride IB, const type *C, vDSP_Stride IC, \
                               const type *D, vDSP_Stride ID, type *E, vDSP_Stride IE, vDSP_Length N)) { \
        for (vDSP_Length n = 0; n < N; n++) { \
            type a = A[n * IA], b = B[n * IB], c = C[n * IC], d = D[n * ID]; \
            E[n * IE] = (expr); \
        } \
    }

// Three vectors: D = f(A, B, C).
#define TRIPLE(name, type, expr) \
    EXPORT(void, vDSP_##name, (const type *A, vDSP_Stride IA, const type *B, vDSP_Stride IB, const type *C, vDSP_Stride IC, \
                               type *D, vDSP_Stride ID, vDSP_Length N)) { \
        for (vDSP_Length n = 0; n < N; n++) { type a = A[n * IA], b = B[n * IB], c = C[n * IC]; D[n * ID] = (expr); } \
    }

// Two vectors and a scalar C: D = f(A, B, c).
#define PAIR_SCALAR(name, type, expr) \
    EXPORT(void, vDSP_##name, (const type *A, vDSP_Stride IA, const type *B, vDSP_Stride IB, const type *C, type *D, \
                               vDSP_Stride ID, vDSP_Length N)) { \
        type c = *C; \
        for (vDSP_Length n = 0; n < N; n++) { type a = A[n * IA], b = B[n * IB]; D[n * ID] = (expr); } \
    }

// A vector, a scalar B and a vector C: D = f(A, b, C).
#define SCALAR_VECTOR(name, type, expr) \
    EXPORT(void, vDSP_##name, (const type *A, vDSP_Stride IA, const type *B, const type *C, vDSP_Stride IC, type *D, \
                               vDSP_Stride ID, vDSP_Length N)) { \
        type b = *B; \
        for (vDSP_Length n = 0; n < N; n++) { type a = A[n * IA], c = C[n * IC]; D[n * ID] = (expr); } \
    }

// A vector and two scalars: D = f(A, b, c).
#define TWO_SCALARS(name, type, expr) \
    EXPORT(void, vDSP_##name, (const type *A, vDSP_Stride IA, const type *B, const type *C, type *D, vDSP_Stride ID, \
                               vDSP_Length N)) { \
        type b = *B, c = *C; \
        for (vDSP_Length n = 0; n < N; n++) { type a = A[n * IA]; D[n * ID] = (expr); } \
    }

#define PAIR(name, type, expr) \
    EXPORT(void, vDSP_##name, (const type *A, vDSP_Stride IA, const type *B, vDSP_Stride IB, type *C, vDSP_Stride IC, \
                               vDSP_Length N)) { \
        for (vDSP_Length n = 0; n < N; n++) { type a = A[n * IA], b = B[n * IB]; C[n * IC] = (expr); } \
    }

#define BOTH(macro, name, expr) macro(name, float, expr) macro(name##D, double, expr)

BOTH(QUAD, vaam, (a + b) * (c + d))
BOTH(QUAD, vasbm, (a + b) * (c - d))
BOTH(QUAD, vmma, a * b + c * d)
BOTH(QUAD, vmmsb, a * b - c * d)
BOTH(QUAD, vsbsbm, (a - b) * (c - d))
BOTH(QUAD, vpythg, sqrt((a - c) * (a - c) + (b - d) * (b - d)))
BOTH(TRIPLE, vmsb, a * b - c)
BOTH(TRIPLE, vsbm, (a - b) * c)
BOTH(PAIR_SCALAR, vasm, (a + b) * c)
BOTH(PAIR_SCALAR, vmsa, a * b + c)
BOTH(PAIR_SCALAR, vsbsm, (a - b) * c)
BOTH(PAIR_SCALAR, vintb, a + (b - a) * c)
BOTH(SCALAR_VECTOR, vsmsb, a * b - c)
BOTH(TWO_SCALARS, vthrsc, a >= b ? c : -c)
BOTH(TWO_SCALARS, viclip, (a <= b || a >= c) ? a : a < 0 ? b : c)
BOTH(PAIR, vdist, sqrt(a * a + b * b))

#define MORE(type, suffix) \
    /* E = A * b + C * d. */ \
    EXPORT(void, vDSP_vsmsma##suffix, (const type *A, vDSP_Stride IA, const type *B, const type *C, vDSP_Stride IC, \
                                       const type *D, type *E, vDSP_Stride IE, vDSP_Length N)) { \
        type b = *B, d = *D; \
        for (vDSP_Length n = 0; n < N; n++) E[n * IE] = A[n * IA] * b + C[n * IC] * d; \
    } \
    EXPORT(void, vDSP_vthres##suffix, (const type *A, vDSP_Stride IA, const type *B, type *C, vDSP_Stride IC, vDSP_Length N)) { \
        type b = *B; \
        for (vDSP_Length n = 0; n < N; n++) { type a = A[n * IA]; C[n * IC] = a >= b ? a : 0; } \
    } \
    EXPORT(void, vDSP_vswap##suffix, (type *A, vDSP_Stride IA, type *B, vDSP_Stride IB, vDSP_Length N)) { \
        for (vDSP_Length n = 0; n < N; n++) { type t = A[n * IA]; A[n * IA] = B[n * IB]; B[n * IB] = t; } \
    } \
    /* The elements of A whose B is not zero, packed. */ \
    EXPORT(void, vDSP_vcmprs##suffix, (const type *A, vDSP_Stride IA, const type *B, vDSP_Stride IB, type *C, vDSP_Stride IC, \
                                       vDSP_Length N)) { \
        vDSP_Length out = 0; \
        for (vDSP_Length n = 0; n < N; n++) if (B[n * IB] != 0) C[out++ * IC] = A[n * IA]; \
    } \
    /* Indices are 1-based. */ \
    EXPORT(void, vDSP_vgathr##suffix, (const type *A, const vDSP_Length *B, vDSP_Stride IB, type *C, vDSP_Stride IC, \
                                       vDSP_Length N)) { \
        for (vDSP_Length n = 0; n < N; n++) C[n * IC] = A[B[n * IB] - 1]; \
    } \
    /* A sampled at the fractional positions B. */ \
    EXPORT(void, vDSP_vlint##suffix, (const type *A, const type *B, vDSP_Stride IB, type *C, vDSP_Stride IC, vDSP_Length N, \
                                      vDSP_Length M)) { \
        for (vDSP_Length n = 0; n < N; n++) { \
            type b = B[n * IB]; \
            vDSP_Length i = (vDSP_Length)b; \
            type f = b - (type)i; \
            C[n * IC] = A[i] + f * (A[i + 1] - A[i]); \
        } \
    } \
    /* Table lookup with interpolation at S1 * A + S2, clamped to the table. */ \
    EXPORT(void, vDSP_vtabi##suffix, (const type *A, vDSP_Stride IA, const type *S1, const type *S2, const type *C, \
                                      vDSP_Length M, type *D, vDSP_Stride ID, vDSP_Length N)) { \
        for (vDSP_Length n = 0; n < N; n++) { \
            type p = *S1 * A[n * IA] + *S2; \
            if (p <= 0) D[n * ID] = C[0]; \
            else if (p >= (type)(M - 1)) D[n * ID] = C[M - 1]; \
            else { vDSP_Length q = (vDSP_Length)p; type r = p - (type)q; D[n * ID] = C[q] + r * (C[q + 1] - C[q]); } \
        } \
    } \
    /* Highest degree first: C = A[0] B^P + ... + A[P]. */ \
    EXPORT(void, vDSP_vpoly##suffix, (const type *A, vDSP_Stride IA, const type *B, vDSP_Stride IB, type *C, vDSP_Stride IC, \
                                      vDSP_Length N, vDSP_Length P)) { \
        for (vDSP_Length n = 0; n < N; n++) { \
            type b = B[n * IB], acc = A[0]; \
            for (vDSP_Length p = 1; p <= P; p++) acc = acc * b + A[p * IA]; \
            C[n * IC] = acc; \
        } \
    } \
    /* A merge from A into B, the weight of B rising linearly. */ \
    EXPORT(void, vDSP_vtmerg##suffix, (const type *A, vDSP_Stride IA, const type *B, vDSP_Stride IB, type *C, vDSP_Stride IC, \
                                       vDSP_Length N)) { \
        for (vDSP_Length n = 0; n < N; n++) { \
            type t = N > 1 ? (type)n / (type)(N - 1) : 0, a = A[n * IA]; \
            C[n * IC] = a + (B[n * IB] - a) * t; \
        } \
    } \
    EXPORT(void, vDSP_vswsum##suffix, (const type *A, vDSP_Stride IA, type *C, vDSP_Stride IC, vDSP_Length N, vDSP_Length P)) { \
        type sum = 0; \
        for (vDSP_Length p = 0; p < P; p++) sum += A[p * IA]; \
        for (vDSP_Length n = 0; n < N; n++) { \
            C[n * IC] = sum; \
            if (n + 1 < N) sum += A[(n + P) * IA] - A[n * IA]; \
        } \
    } \
    /* Integration: running sum, trapezoids and Simpson's rule with step B. */ \
    EXPORT(void, vDSP_vrsum##suffix, (const type *A, vDSP_Stride IA, const type *S, type *C, vDSP_Stride IC, vDSP_Length N)) { \
        type sum = 0; \
        for (vDSP_Length n = 0; n < N; n++) { if (n) sum += A[n * IA] * *S; C[n * IC] = sum; } \
    } \
    EXPORT(void, vDSP_vtrapz##suffix, (const type *A, vDSP_Stride IA, const type *B, type *C, vDSP_Stride IC, vDSP_Length N)) { \
        type sum = 0, half = *B / 2; \
        for (vDSP_Length n = 0; n < N; n++) { if (n) sum += (A[(n - 1) * IA] + A[n * IA]) * half; C[n * IC] = sum; } \
    } \
    EXPORT(void, vDSP_vsimps##suffix, (const type *A, vDSP_Stride IA, const type *B, type *C, vDSP_Stride IC, vDSP_Length N)) { \
        type b = *B; \
        if (N == 0) return; \
        C[0] = 0; \
        if (N == 1) return; \
        C[IC] = (A[0] + A[IA]) * b / 2; \
        for (vDSP_Length n = 2; n < N; n++) \
            C[n * IC] = C[(n - 2) * IC] + (A[(n - 2) * IA] + 4 * A[(n - 1) * IA] + A[n * IA]) * b / 3; \
    } \
    /* Multiplication by a ramp that continues from *Start across calls. */ \
    EXPORT(void, vDSP_vrampmul##suffix, (const type *I, vDSP_Stride IS, type *Start, const type *Step, type *O, \
                                         vDSP_Stride OS, vDSP_Length N)) { \
        type ramp = *Start; \
        for (vDSP_Length n = 0; n < N; n++) { O[n * OS] = ramp * I[n * IS]; ramp += *Step; } \
        *Start = ramp; \
    } \
    EXPORT(void, vDSP_vrampmul2##suffix, (const type *I0, const type *I1, vDSP_Stride IS, type *Start, const type *Step, \
                                          type *O0, type *O1, vDSP_Stride OS, vDSP_Length N)) { \
        type ramp = *Start; \
        for (vDSP_Length n = 0; n < N; n++) { O0[n * OS] = ramp * I0[n * IS]; O1[n * OS] = ramp * I1[n * IS]; ramp += *Step; } \
        *Start = ramp; \
    } \
    EXPORT(void, vDSP_vaddsub##suffix, (const type *I0, vDSP_Stride I0S, const type *I1, vDSP_Stride I1S, type *O0, \
                                        vDSP_Stride O0S, type *O1, vDSP_Stride O1S, vDSP_Length N)) { \
        for (vDSP_Length n = 0; n < N; n++) { \
            type a = I0[n * I0S], b = I1[n * I1S]; \
            O0[n * O0S] = b + a; O1[n * O1S] = b - a; \
        } \
    } \
    EXPORT(void, vDSP_sve_svesq##suffix, (const type *A, vDSP_Stride IA, type *Sum, type *SumOfSquares, vDSP_Length N)) { \
        double sum = 0, squares = 0; \
        for (vDSP_Length n = 0; n < N; n++) { double a = A[n * IA]; sum += a; squares += a * a; } \
        *Sum = (type)sum; *SumOfSquares = (type)squares; \
    } \
    /* (A - mean) / standard deviation, the population's; C may be NULL. */ \
    EXPORT(void, vDSP_normalize##suffix, (const type *A, vDSP_Stride IA, type *C, vDSP_Stride IC, type *Mean, \
                                          type *StandardDeviation, vDSP_Length N)) { \
        double sum = 0, squares = 0; \
        for (vDSP_Length n = 0; n < N; n++) sum += A[n * IA]; \
        double mean = N ? sum / N : 0; \
        for (vDSP_Length n = 0; n < N; n++) { double d = A[n * IA] - mean; squares += d * d; } \
        double deviation = N ? sqrt(squares / N) : 0; \
        *Mean = (type)mean; *StandardDeviation = (type)deviation; \
        if (C) for (vDSP_Length n = 0; n < N; n++) C[n * IC] = (type)((A[n * IA] - mean) / deviation); \
    } \
    /* Up to B zero crossings: D counts them; C is the index (times the stride) of the Bth, or 0. */ \
    EXPORT(void, vDSP_nzcros##suffix, (const type *A, vDSP_Stride IA, vDSP_Length B, vDSP_Length *C, vDSP_Length *D, \
                                       vDSP_Length N)) { \
        vDSP_Length count = 0, last = 0; \
        for (vDSP_Length n = 1; n < N && count < B; n++) \
            if (signbit(A[n * IA]) != signbit(A[(n - 1) * IA])) { count++; last = n * (vDSP_Length)IA; } \
        *C = count == B ? last : 0; *D = count; \
    } \
    /* Interleaved (x, y) pairs to (magnitude, angle) and back. */ \
    EXPORT(void, vDSP_polar##suffix, (const type *A, vDSP_Stride IA, type *C, vDSP_Stride IC, vDSP_Length N)) { \
        for (vDSP_Length n = 0; n < N; n++) { \
            type x = A[n * IA], y = A[n * IA + 1]; \
            C[n * IC] = sqrt(x * x + y * y); C[n * IC + 1] = atan2(y, x); \
        } \
    } \
    EXPORT(void, vDSP_rect##suffix, (const type *A, vDSP_Stride IA, type *C, vDSP_Stride IC, vDSP_Length N)) { \
        for (vDSP_Length n = 0; n < N; n++) { \
            type r = A[n * IA], t = A[n * IA + 1]; \
            C[n * IC] = r * cos(t); C[n * IC + 1] = r * sin(t); \
        } \
    }

MORE(float, )
MORE(double, D)

// MARK: - Split complex

#define SPLIT(type, suffix, split) \
    EXPORT(void, vDSP_zvadd##suffix, (const split *A, vDSP_Stride IA, const split *B, vDSP_Stride IB, const split *C, \
                                      vDSP_Stride IC, vDSP_Length N)) { \
        for (vDSP_Length n = 0; n < N; n++) { \
            type r = A->realp[n * IA] + B->realp[n * IB], i = A->imagp[n * IA] + B->imagp[n * IB]; \
            C->realp[n * IC] = r; C->imagp[n * IC] = i; \
        } \
    } \
    EXPORT(void, vDSP_zvsub##suffix, (const split *A, vDSP_Stride IA, const split *B, vDSP_Stride IB, const split *C, \
                                      vDSP_Stride IC, vDSP_Length N)) { \
        for (vDSP_Length n = 0; n < N; n++) { \
            type r = A->realp[n * IA] - B->realp[n * IB], i = A->imagp[n * IA] - B->imagp[n * IB]; \
            C->realp[n * IC] = r; C->imagp[n * IC] = i; \
        } \
    } \
    /* The first operand is the divisor: C = A / B, with B passed first. */ \
    EXPORT(void, vDSP_zvdiv##suffix, (const split *B, vDSP_Stride IB, const split *A, vDSP_Stride IA, const split *C, \
                                      vDSP_Stride IC, vDSP_Length N)) { \
        for (vDSP_Length n = 0; n < N; n++) { \
            type ar = A->realp[n * IA], ai = A->imagp[n * IA], br = B->realp[n * IB], bi = B->imagp[n * IB]; \
            type d = br * br + bi * bi; \
            C->realp[n * IC] = (ar * br + ai * bi) / d; C->imagp[n * IC] = (ai * br - ar * bi) / d; \
        } \
    } \
    EXPORT(void, vDSP_zvconj##suffix, (const split *A, vDSP_Stride IA, const split *C, vDSP_Stride IC, vDSP_Length N)) { \
        for (vDSP_Length n = 0; n < N; n++) { C->realp[n * IC] = A->realp[n * IA]; C->imagp[n * IC] = -A->imagp[n * IA]; } \
    } \
    EXPORT(void, vDSP_zvmov##suffix, (const split *A, vDSP_Stride IA, const split *C, vDSP_Stride IC, vDSP_Length N)) { \
        for (vDSP_Length n = 0; n < N; n++) { C->realp[n * IC] = A->realp[n * IA]; C->imagp[n * IC] = A->imagp[n * IA]; } \
    } \
    EXPORT(void, vDSP_zrvmul##suffix, (const split *A, vDSP_Stride IA, const type *B, vDSP_Stride IB, const split *C, \
                                       vDSP_Stride IC, vDSP_Length N)) { \
        for (vDSP_Length n = 0; n < N; n++) { \
            type b = B[n * IB]; \
            C->realp[n * IC] = A->realp[n * IA] * b; C->imagp[n * IC] = A->imagp[n * IA] * b; \
        } \
    } \
    EXPORT(void, vDSP_zrvdiv##suffix, (const split *A, vDSP_Stride IA, const type *B, vDSP_Stride IB, const split *C, \
                                       vDSP_Stride IC, vDSP_Length N)) { \
        for (vDSP_Length n = 0; n < N; n++) { \
            type b = B[n * IB]; \
            C->realp[n * IC] = A->realp[n * IA] / b; C->imagp[n * IC] = A->imagp[n * IA] / b; \
        } \
    }

SPLIT(float, , DSPSplitComplex)
SPLIT(double, D, DSPDoubleSplitComplex)

// MARK: - Double to integer conversions

#define CONVERT(name, to, expr) \
    EXPORT(void, vDSP_##name, (const double *A, vDSP_Stride IA, to *C, vDSP_Stride IC, vDSP_Length N)) { \
        for (vDSP_Length n = 0; n < N; n++) { double a = A[n * IA]; C[n * IC] = (to)(expr); } \
    }

CONVERT(vfixu8D, unsigned char, a)
CONVERT(vfixu16D, unsigned short, a)
CONVERT(vfixu32D, unsigned int, a)
CONVERT(vfixr8D, signed char, rint(a))
CONVERT(vfixru8D, unsigned char, rint(a))
CONVERT(vfixru16D, unsigned short, rint(a))
CONVERT(vfixru32D, unsigned int, rint(a))
