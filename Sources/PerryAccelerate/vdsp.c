// vDSP: vector arithmetic, reductions, conversions, matrices, correlation,
// windows and Fourier transforms, in single and double precision, with
// Apple's conventions: vsub and vdiv compute B - A and B / A; the real FFT
// leaves twice the transform, packed with the Nyquist term's real part in
// imagp[0]; inverse transforms are unnormalized.

#include "PerryAccelerate.h"

#include <complex.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

// complex.h's I would clash with vDSP's index parameters.
#undef I
#define IMAGINARY _Complex_I

// MARK: - Element-wise, in both precisions

#define BINARY(name, type, expr) \
    void vDSP_##name(const type *A, vDSP_Stride IA, const type *B, vDSP_Stride IB, type *C, vDSP_Stride IC, vDSP_Length N) \
        DARWIN_SYMBOL(vDSP_##name); \
    void vDSP_##name(const type *A, vDSP_Stride IA, const type *B, vDSP_Stride IB, type *C, vDSP_Stride IC, vDSP_Length N) { \
        for (vDSP_Length n = 0; n < N; n++) { type a = A[n * IA], b = B[n * IB]; C[n * IC] = (expr); } \
    }

#define SCALAR(name, type, expr) \
    void vDSP_##name(const type *A, vDSP_Stride IA, const type *B, type *C, vDSP_Stride IC, vDSP_Length N) \
        DARWIN_SYMBOL(vDSP_##name); \
    void vDSP_##name(const type *A, vDSP_Stride IA, const type *B, type *C, vDSP_Stride IC, vDSP_Length N) { \
        type b = *B; \
        for (vDSP_Length n = 0; n < N; n++) { type a = A[n * IA]; C[n * IC] = (expr); } \
    }

#define UNARY(name, type, expr) \
    void vDSP_##name(const type *A, vDSP_Stride IA, type *C, vDSP_Stride IC, vDSP_Length N) DARWIN_SYMBOL(vDSP_##name); \
    void vDSP_##name(const type *A, vDSP_Stride IA, type *C, vDSP_Stride IC, vDSP_Length N) { \
        for (vDSP_Length n = 0; n < N; n++) { type a = A[n * IA]; C[n * IC] = (expr); } \
    }

#define BOTH(macro, name, expr) macro(name, float, expr) macro(name##D, double, expr)

BOTH(BINARY, vadd, a + b)
BOTH(BINARY, vsub, b - a)
BOTH(BINARY, vmul, a * b)
BOTH(BINARY, vdiv, b / a)
BOTH(BINARY, vmax, a > b ? a : b)
BOTH(BINARY, vmin, a < b ? a : b)
BOTH(BINARY, vmaxmg, fabs(a) > fabs(b) ? fabs(a) : fabs(b))
BOTH(BINARY, vminmg, fabs(a) < fabs(b) ? fabs(a) : fabs(b))
BOTH(SCALAR, vsadd, a + b)
BOTH(SCALAR, vsmul, a * b)
BOTH(SCALAR, vsdiv, a / b)
BOTH(SCALAR, svdiv, b / a)
BOTH(SCALAR, vthr, a < b ? b : a)
BOTH(UNARY, vabs, fabs(a))
BOTH(UNARY, vneg, -a)
BOTH(UNARY, vsq, a * a)
BOTH(UNARY, vssq, a < 0 ? -a * a : a * a)
BOTH(UNARY, vfrac, a - trunc(a))
BOTH(UNARY, vnabs, -fabs(a))

#define SMA(type, suffix) \
    void vDSP_vsma##suffix(const type *A, vDSP_Stride IA, const type *B, const type *C, vDSP_Stride IC, type *D, vDSP_Stride ID, \
                           vDSP_Length N) DARWIN_SYMBOL(vDSP_vsma##suffix); \
    void vDSP_vsma##suffix(const type *A, vDSP_Stride IA, const type *B, const type *C, vDSP_Stride IC, type *D, vDSP_Stride ID, \
                           vDSP_Length N) { \
        for (vDSP_Length n = 0; n < N; n++) D[n * ID] = A[n * IA] * *B + C[n * IC]; \
    } \
    void vDSP_vma##suffix(const type *A, vDSP_Stride IA, const type *B, vDSP_Stride IB, const type *C, vDSP_Stride IC, type *D, \
                          vDSP_Stride ID, vDSP_Length N) DARWIN_SYMBOL(vDSP_vma##suffix); \
    void vDSP_vma##suffix(const type *A, vDSP_Stride IA, const type *B, vDSP_Stride IB, const type *C, vDSP_Stride IC, type *D, \
                          vDSP_Stride ID, vDSP_Length N) { \
        for (vDSP_Length n = 0; n < N; n++) D[n * ID] = A[n * IA] * B[n * IB] + C[n * IC]; \
    } \
    void vDSP_vam##suffix(const type *A, vDSP_Stride IA, const type *B, vDSP_Stride IB, const type *C, vDSP_Stride IC, type *D, \
                          vDSP_Stride ID, vDSP_Length N) DARWIN_SYMBOL(vDSP_vam##suffix); \
    void vDSP_vam##suffix(const type *A, vDSP_Stride IA, const type *B, vDSP_Stride IB, const type *C, vDSP_Stride IC, type *D, \
                          vDSP_Stride ID, vDSP_Length N) { \
        for (vDSP_Length n = 0; n < N; n++) D[n * ID] = (A[n * IA] + B[n * IB]) * C[n * IC]; \
    } \
    void vDSP_vsmsa##suffix(const type *A, vDSP_Stride IA, const type *B, const type *C, type *D, vDSP_Stride ID, vDSP_Length N) \
        DARWIN_SYMBOL(vDSP_vsmsa##suffix); \
    void vDSP_vsmsa##suffix(const type *A, vDSP_Stride IA, const type *B, const type *C, type *D, vDSP_Stride ID, vDSP_Length N) { \
        for (vDSP_Length n = 0; n < N; n++) D[n * ID] = A[n * IA] * *B + *C; \
    } \
    void vDSP_vclip##suffix(const type *A, vDSP_Stride IA, const type *B, const type *C, type *D, vDSP_Stride ID, vDSP_Length N) \
        DARWIN_SYMBOL(vDSP_vclip##suffix); \
    void vDSP_vclip##suffix(const type *A, vDSP_Stride IA, const type *B, const type *C, type *D, vDSP_Stride ID, vDSP_Length N) { \
        for (vDSP_Length n = 0; n < N; n++) { type a = A[n * IA]; D[n * ID] = a < *B ? *B : a > *C ? *C : a; } \
    } \
    void vDSP_vlim##suffix(const type *A, vDSP_Stride IA, const type *B, const type *C, type *D, vDSP_Stride ID, vDSP_Length N) \
        DARWIN_SYMBOL(vDSP_vlim##suffix); \
    void vDSP_vlim##suffix(const type *A, vDSP_Stride IA, const type *B, const type *C, type *D, vDSP_Stride ID, vDSP_Length N) { \
        for (vDSP_Length n = 0; n < N; n++) D[n * ID] = A[n * IA] >= *B ? *C : -*C; \
    } \
    void vDSP_vramp##suffix(const type *A, const type *B, type *C, vDSP_Stride IC, vDSP_Length N) DARWIN_SYMBOL(vDSP_vramp##suffix); \
    void vDSP_vramp##suffix(const type *A, const type *B, type *C, vDSP_Stride IC, vDSP_Length N) { \
        for (vDSP_Length n = 0; n < N; n++) C[n * IC] = *A + (type)n * *B; \
    } \
    void vDSP_vgen##suffix(const type *A, const type *B, type *C, vDSP_Stride IC, vDSP_Length N) DARWIN_SYMBOL(vDSP_vgen##suffix); \
    void vDSP_vgen##suffix(const type *A, const type *B, type *C, vDSP_Stride IC, vDSP_Length N) { \
        for (vDSP_Length n = 0; n < N; n++) C[n * IC] = N > 1 ? *A + (*B - *A) * (type)n / (type)(N - 1) : *A; \
    } \
    void vDSP_vfill##suffix(const type *A, type *C, vDSP_Stride IC, vDSP_Length N) DARWIN_SYMBOL(vDSP_vfill##suffix); \
    void vDSP_vfill##suffix(const type *A, type *C, vDSP_Stride IC, vDSP_Length N) { \
        for (vDSP_Length n = 0; n < N; n++) C[n * IC] = *A; \
    } \
    void vDSP_vclr##suffix(type *C, vDSP_Stride IC, vDSP_Length N) DARWIN_SYMBOL(vDSP_vclr##suffix); \
    void vDSP_vclr##suffix(type *C, vDSP_Stride IC, vDSP_Length N) { \
        for (vDSP_Length n = 0; n < N; n++) C[n * IC] = 0; \
    } \
    void vDSP_vrvrs##suffix(type *C, vDSP_Stride IC, vDSP_Length N) DARWIN_SYMBOL(vDSP_vrvrs##suffix); \
    void vDSP_vrvrs##suffix(type *C, vDSP_Stride IC, vDSP_Length N) { \
        for (vDSP_Length n = 0; n < N / 2; n++) { type t = C[n * IC]; C[n * IC] = C[(N - 1 - n) * IC]; C[(N - 1 - n) * IC] = t; } \
    } \
    static int ascending##suffix(const void *a, const void *b) { type x = *(const type *)a, y = *(const type *)b; return x < y ? -1 : x > y; } \
    static int descending##suffix(const void *a, const void *b) { return ascending##suffix(b, a); } \
    void vDSP_vsort##suffix(type *C, vDSP_Length N, int order) DARWIN_SYMBOL(vDSP_vsort##suffix); \
    void vDSP_vsort##suffix(type *C, vDSP_Length N, int order) { qsort(C, N, sizeof(type), order < 0 ? descending##suffix : ascending##suffix); } \
    void vDSP_mmov##suffix(const type *A, type *C, vDSP_Length M, vDSP_Length N, vDSP_Length TA, vDSP_Length TC) \
        DARWIN_SYMBOL(vDSP_mmov##suffix); \
    void vDSP_mmov##suffix(const type *A, type *C, vDSP_Length M, vDSP_Length N, vDSP_Length TA, vDSP_Length TC) { \
        for (vDSP_Length row = 0; row < N; row++) memmove(C + row * TC, A + row * TA, M * sizeof(type)); \
    }

SMA(float, )
SMA(double, D)

// MARK: - Reductions

#define REDUCE(name, type, init, step, finish) \
    void vDSP_##name(const type *A, vDSP_Stride IA, type *C, vDSP_Length N) DARWIN_SYMBOL(vDSP_##name); \
    void vDSP_##name(const type *A, vDSP_Stride IA, type *C, vDSP_Length N) { \
        double acc = (init); \
        for (vDSP_Length n = 0; n < N; n++) { double a = A[n * IA]; step; } \
        *C = (type)(finish); \
    }

#define REDUCTIONS(type, suffix) \
    REDUCE(sve##suffix, type, 0, acc += a, acc) \
    REDUCE(svesq##suffix, type, 0, acc += a * a, acc) \
    REDUCE(svemg##suffix, type, 0, acc += fabs(a), acc) \
    REDUCE(svs##suffix, type, 0, acc += a < 0 ? -a * a : a * a, acc) \
    REDUCE(meanv##suffix, type, 0, acc += a, N ? acc / N : 0) \
    REDUCE(measqv##suffix, type, 0, acc += a * a, N ? acc / N : 0) \
    REDUCE(meamgv##suffix, type, 0, acc += fabs(a), N ? acc / N : 0) \
    REDUCE(rmsqv##suffix, type, 0, acc += a * a, N ? sqrt(acc / N) : 0) \
    REDUCE(maxv##suffix, type, -INFINITY, if (a > acc) acc = a, acc) \
    REDUCE(minv##suffix, type, INFINITY, if (a < acc) acc = a, acc) \
    REDUCE(maxmgv##suffix, type, 0, if (fabs(a) > acc) acc = fabs(a), acc) \
    REDUCE(minmgv##suffix, type, INFINITY, if (fabs(a) < acc) acc = fabs(a), acc) \
    void vDSP_maxvi##suffix(const type *A, vDSP_Stride IA, type *C, vDSP_Length *I, vDSP_Length N) DARWIN_SYMBOL(vDSP_maxvi##suffix); \
    void vDSP_maxvi##suffix(const type *A, vDSP_Stride IA, type *C, vDSP_Length *I, vDSP_Length N) { \
        type best = -INFINITY; vDSP_Length at = 0; \
        for (vDSP_Length n = 0; n < N; n++) if (A[n * IA] > best) { best = A[n * IA]; at = n * IA; } \
        *C = best; *I = at; \
    } \
    void vDSP_minvi##suffix(const type *A, vDSP_Stride IA, type *C, vDSP_Length *I, vDSP_Length N) DARWIN_SYMBOL(vDSP_minvi##suffix); \
    void vDSP_minvi##suffix(const type *A, vDSP_Stride IA, type *C, vDSP_Length *I, vDSP_Length N) { \
        type best = INFINITY; vDSP_Length at = 0; \
        for (vDSP_Length n = 0; n < N; n++) if (A[n * IA] < best) { best = A[n * IA]; at = n * IA; } \
        *C = best; *I = at; \
    } \
    void vDSP_maxmgvi##suffix(const type *A, vDSP_Stride IA, type *C, vDSP_Length *I, vDSP_Length N) DARWIN_SYMBOL(vDSP_maxmgvi##suffix); \
    void vDSP_maxmgvi##suffix(const type *A, vDSP_Stride IA, type *C, vDSP_Length *I, vDSP_Length N) { \
        type best = 0; vDSP_Length at = 0; \
        for (vDSP_Length n = 0; n < N; n++) if (fabs(A[n * IA]) > best) { best = fabs(A[n * IA]); at = n * IA; } \
        *C = best; *I = at; \
    } \
    void vDSP_dotpr##suffix(const type *A, vDSP_Stride IA, const type *B, vDSP_Stride IB, type *C, vDSP_Length N) \
        DARWIN_SYMBOL(vDSP_dotpr##suffix); \
    void vDSP_dotpr##suffix(const type *A, vDSP_Stride IA, const type *B, vDSP_Stride IB, type *C, vDSP_Length N) { \
        double acc = 0; \
        for (vDSP_Length n = 0; n < N; n++) acc += (double)A[n * IA] * B[n * IB]; \
        *C = (type)acc; \
    } \
    void vDSP_distancesq##suffix(const type *A, vDSP_Stride IA, const type *B, vDSP_Stride IB, type *C, vDSP_Length N) \
        DARWIN_SYMBOL(vDSP_distancesq##suffix); \
    void vDSP_distancesq##suffix(const type *A, vDSP_Stride IA, const type *B, vDSP_Stride IB, type *C, vDSP_Length N) { \
        double acc = 0; \
        for (vDSP_Length n = 0; n < N; n++) { double d = (double)A[n * IA] - B[n * IB]; acc += d * d; } \
        *C = (type)acc; \
    }

REDUCTIONS(float, )
REDUCTIONS(double, D)

// MARK: - Conversions

#define CONVERT(name, from, to, expr) \
    void vDSP_##name(const from *A, vDSP_Stride IA, to *C, vDSP_Stride IC, vDSP_Length N) DARWIN_SYMBOL(vDSP_##name); \
    void vDSP_##name(const from *A, vDSP_Stride IA, to *C, vDSP_Stride IC, vDSP_Length N) { \
        for (vDSP_Length n = 0; n < N; n++) { from a = A[n * IA]; C[n * IC] = (to)(expr); } \
    }

// Truncation toward zero, and rounding to nearest (half to even).
CONVERT(vfix8, float, signed char, a)
CONVERT(vfix16, float, short, a)
CONVERT(vfix32, float, int, a)
CONVERT(vfixu8, float, unsigned char, a)
CONVERT(vfixu16, float, unsigned short, a)
CONVERT(vfixu32, float, unsigned int, a)
CONVERT(vfixr8, float, signed char, rintf(a))
CONVERT(vfixr16, float, short, rintf(a))
CONVERT(vfixr32, float, int, rintf(a))
CONVERT(vfixru8, float, unsigned char, rintf(a))
CONVERT(vfixru16, float, unsigned short, rintf(a))
CONVERT(vfixru32, float, unsigned int, rintf(a))
CONVERT(vfix8D, double, signed char, a)
CONVERT(vfix16D, double, short, a)
CONVERT(vfix32D, double, int, a)
CONVERT(vfixr16D, double, short, rint(a))
CONVERT(vfixr32D, double, int, rint(a))
CONVERT(vflt8, signed char, float, a)
CONVERT(vflt16, short, float, a)
CONVERT(vflt32, int, float, a)
CONVERT(vfltu8, unsigned char, float, a)
CONVERT(vfltu16, unsigned short, float, a)
CONVERT(vfltu32, unsigned int, float, a)
CONVERT(vflt8D, signed char, double, a)
CONVERT(vflt16D, short, double, a)
CONVERT(vflt32D, int, double, a)
CONVERT(vfltu8D, unsigned char, double, a)
CONVERT(vfltu16D, unsigned short, double, a)
CONVERT(vfltu32D, unsigned int, double, a)
CONVERT(vspdp, float, double, a)
CONVERT(vdpsp, double, float, a)

#define DB(type, suffix, logf) \
    void vDSP_vdbcon##suffix(const type *A, vDSP_Stride IA, const type *B, type *C, vDSP_Stride IC, vDSP_Length N, unsigned int F) \
        DARWIN_SYMBOL(vDSP_vdbcon##suffix); \
    void vDSP_vdbcon##suffix(const type *A, vDSP_Stride IA, const type *B, type *C, vDSP_Stride IC, vDSP_Length N, unsigned int F) { \
        type factor = F ? 20 : 10; \
        for (vDSP_Length n = 0; n < N; n++) C[n * IC] = factor * logf(A[n * IA] / *B); \
    }

DB(float, , log10f)
DB(double, D, log10)

// MARK: - Matrices and correlation

#define MATRICES(type, suffix) \
    void vDSP_mmul##suffix(const type *A, vDSP_Stride IA, const type *B, vDSP_Stride IB, type *C, vDSP_Stride IC, \
                           vDSP_Length M, vDSP_Length N, vDSP_Length P) DARWIN_SYMBOL(vDSP_mmul##suffix); \
    void vDSP_mmul##suffix(const type *A, vDSP_Stride IA, const type *B, vDSP_Stride IB, type *C, vDSP_Stride IC, \
                           vDSP_Length M, vDSP_Length N, vDSP_Length P) { \
        for (vDSP_Length m = 0; m < M; m++) \
            for (vDSP_Length n = 0; n < N; n++) { \
                double acc = 0; \
                for (vDSP_Length p = 0; p < P; p++) acc += (double)A[(m * P + p) * IA] * B[(p * N + n) * IB]; \
                C[(m * N + n) * IC] = (type)acc; \
            } \
    } \
    void vDSP_mtrans##suffix(const type *A, vDSP_Stride IA, type *C, vDSP_Stride IC, vDSP_Length M, vDSP_Length N) \
        DARWIN_SYMBOL(vDSP_mtrans##suffix); \
    void vDSP_mtrans##suffix(const type *A, vDSP_Stride IA, type *C, vDSP_Stride IC, vDSP_Length M, vDSP_Length N) { \
        for (vDSP_Length m = 0; m < M; m++) \
            for (vDSP_Length n = 0; n < N; n++) C[(m * N + n) * IC] = A[(n * M + m) * IA]; \
    } \
    void vDSP_conv##suffix(const type *A, vDSP_Stride IA, const type *F, vDSP_Stride IF, type *C, vDSP_Stride IC, \
                           vDSP_Length N, vDSP_Length P) DARWIN_SYMBOL(vDSP_conv##suffix); \
    void vDSP_conv##suffix(const type *A, vDSP_Stride IA, const type *F, vDSP_Stride IF, type *C, vDSP_Stride IC, \
                           vDSP_Length N, vDSP_Length P) { \
        for (vDSP_Length n = 0; n < N; n++) { \
            double acc = 0; \
            for (vDSP_Length p = 0; p < P; p++) acc += (double)A[(n + p) * IA] * F[(vDSP_Stride)p * IF]; \
            C[n * IC] = (type)acc; \
        } \
    }

MATRICES(float, )
MATRICES(double, D)

// MARK: - Windows

// Flags: half window 1 (only the first (N + 1) / 2 values), normalized 2.
#define WINDOW(name, type, expr) \
    void vDSP_##name(type *C, vDSP_Length N, int flag) DARWIN_SYMBOL(vDSP_##name); \
    void vDSP_##name(type *C, vDSP_Length N, int flag) { \
        vDSP_Length count = (flag & 1) ? (N + 1) / 2 : N; \
        for (vDSP_Length n = 0; n < count; n++) { double x = 2 * M_PI * n / N; C[n] = (type)(expr); } \
    }

WINDOW(hann_window, float, (flag & 2 ? 0.8164965809277260 : 0.5) * (1 - cos(x)))
WINDOW(hann_windowD, double, (flag & 2 ? 0.8164965809277260 : 0.5) * (1 - cos(x)))
WINDOW(hamm_window, float, 0.54 - 0.46 * cos(x))
WINDOW(hamm_windowD, double, 0.54 - 0.46 * cos(x))
WINDOW(blkman_window, float, 0.42 - 0.5 * cos(x) + 0.08 * cos(2 * x))
WINDOW(blkman_windowD, double, 0.42 - 0.5 * cos(x) + 0.08 * cos(2 * x))

// MARK: - Complex vectors

#define COMPLEX(type, suffix, split, interleaved) \
    void vDSP_ctoz##suffix(const interleaved *C, vDSP_Stride IC, const split *Z, vDSP_Stride IZ, vDSP_Length N) \
        DARWIN_SYMBOL(vDSP_ctoz##suffix); \
    void vDSP_ctoz##suffix(const interleaved *C, vDSP_Stride IC, const split *Z, vDSP_Stride IZ, vDSP_Length N) { \
        const type *values = (const type *)C; \
        for (vDSP_Length n = 0; n < N; n++) { Z->realp[n * IZ] = values[n * IC]; Z->imagp[n * IZ] = values[n * IC + 1]; } \
    } \
    void vDSP_ztoc##suffix(const split *Z, vDSP_Stride IZ, interleaved *C, vDSP_Stride IC, vDSP_Length N) \
        DARWIN_SYMBOL(vDSP_ztoc##suffix); \
    void vDSP_ztoc##suffix(const split *Z, vDSP_Stride IZ, interleaved *C, vDSP_Stride IC, vDSP_Length N) { \
        type *values = (type *)C; \
        for (vDSP_Length n = 0; n < N; n++) { values[n * IC] = Z->realp[n * IZ]; values[n * IC + 1] = Z->imagp[n * IZ]; } \
    } \
    void vDSP_zvmags##suffix(const split *A, vDSP_Stride IA, type *C, vDSP_Stride IC, vDSP_Length N) DARWIN_SYMBOL(vDSP_zvmags##suffix); \
    void vDSP_zvmags##suffix(const split *A, vDSP_Stride IA, type *C, vDSP_Stride IC, vDSP_Length N) { \
        for (vDSP_Length n = 0; n < N; n++) { type r = A->realp[n * IA], i = A->imagp[n * IA]; C[n * IC] = r * r + i * i; } \
    } \
    void vDSP_zvabs##suffix(const split *A, vDSP_Stride IA, type *C, vDSP_Stride IC, vDSP_Length N) DARWIN_SYMBOL(vDSP_zvabs##suffix); \
    void vDSP_zvabs##suffix(const split *A, vDSP_Stride IA, type *C, vDSP_Stride IC, vDSP_Length N) { \
        for (vDSP_Length n = 0; n < N; n++) C[n * IC] = hypot(A->realp[n * IA], A->imagp[n * IA]); \
    } \
    void vDSP_zvphas##suffix(const split *A, vDSP_Stride IA, type *C, vDSP_Stride IC, vDSP_Length N) DARWIN_SYMBOL(vDSP_zvphas##suffix); \
    void vDSP_zvphas##suffix(const split *A, vDSP_Stride IA, type *C, vDSP_Stride IC, vDSP_Length N) { \
        for (vDSP_Length n = 0; n < N; n++) C[n * IC] = atan2(A->imagp[n * IA], A->realp[n * IA]); \
    } \
    void vDSP_zvmul##suffix(const split *A, vDSP_Stride IA, const split *B, vDSP_Stride IB, const split *C, vDSP_Stride IC, \
                            vDSP_Length N, int conjugate) DARWIN_SYMBOL(vDSP_zvmul##suffix); \
    void vDSP_zvmul##suffix(const split *A, vDSP_Stride IA, const split *B, vDSP_Stride IB, const split *C, vDSP_Stride IC, \
                            vDSP_Length N, int conjugate) { \
        for (vDSP_Length n = 0; n < N; n++) { \
            type ar = A->realp[n * IA], ai = conjugate == -1 ? -A->imagp[n * IA] : A->imagp[n * IA]; \
            type br = B->realp[n * IB], bi = B->imagp[n * IB]; \
            C->realp[n * IC] = ar * br - ai * bi; C->imagp[n * IC] = ar * bi + ai * br; \
        } \
    }

COMPLEX(float, , DSPSplitComplex, DSPComplex)
COMPLEX(double, D, DSPDoubleSplitComplex, DSPDoubleComplex)

// MARK: - Fourier transforms

typedef struct fft_setup { vDSP_Length log2n; } fft_setup;

static void *create_setup(vDSP_Length log2n) {
    fft_setup *setup = malloc(sizeof(fft_setup));
    if (setup) setup->log2n = log2n;
    return setup;
}

void *vDSP_create_fftsetup(vDSP_Length log2n, int radix) DARWIN_SYMBOL(vDSP_create_fftsetup);
void *vDSP_create_fftsetup(vDSP_Length log2n, int radix) { return create_setup(log2n); }
void *vDSP_create_fftsetupD(vDSP_Length log2n, int radix) DARWIN_SYMBOL(vDSP_create_fftsetupD);
void *vDSP_create_fftsetupD(vDSP_Length log2n, int radix) { return create_setup(log2n); }
void vDSP_destroy_fftsetup(void *setup) DARWIN_SYMBOL(vDSP_destroy_fftsetup);
void vDSP_destroy_fftsetup(void *setup) { free(setup); }
void vDSP_destroy_fftsetupD(void *setup) DARWIN_SYMBOL(vDSP_destroy_fftsetupD);
void vDSP_destroy_fftsetupD(void *setup) { free(setup); }

/// The discrete Fourier transform of n points, in place, unnormalized;
/// sign -1 forward, +1 inverse. Radix 2 when n is a power of two.
static void transform(double complex *x, size_t n, int sign) {
    if (n <= 1) return;
    if ((n & (n - 1)) == 0) {
        for (size_t i = 1, j = 0; i < n; i++) {
            size_t bit = n >> 1;
            for (; j & bit; bit >>= 1) j ^= bit;
            j |= bit;
            if (i < j) { double complex t = x[i]; x[i] = x[j]; x[j] = t; }
        }
        for (size_t length = 2; length <= n; length <<= 1) {
            double angle = sign * 2 * M_PI / length;
            for (size_t i = 0; i < n; i += length)
                for (size_t k = 0; k < length / 2; k++) {
                    double complex w = cexp(IMAGINARY * angle * k);
                    double complex u = x[i + k], v = x[i + k + length / 2] * w;
                    x[i + k] = u + v;
                    x[i + k + length / 2] = u - v;
                }
        }
        return;
    }
    double complex *out = malloc(n * sizeof(double complex));
    for (size_t k = 0; k < n; k++) {
        double complex sum = 0;
        for (size_t j = 0; j < n; j++) sum += x[j] * cexp(IMAGINARY * sign * 2 * M_PI * (double)(k * j % n) / n);
        out[k] = sum;
    }
    memcpy(x, out, n * sizeof(double complex));
    free(out);
}

#define FFT(type, suffix, split) \
    static void complex_fft##suffix(const split *in, vDSP_Stride IA, const split *out, vDSP_Stride IC, size_t n, int direction) { \
        double complex *x = malloc(n * sizeof(double complex)); \
        for (size_t k = 0; k < n; k++) x[k] = in->realp[k * IA] + IMAGINARY * in->imagp[k * IA]; \
        transform(x, n, direction >= 0 ? -1 : 1); \
        for (size_t k = 0; k < n; k++) { out->realp[k * IC] = (type)creal(x[k]); out->imagp[k * IC] = (type)cimag(x[k]); } \
        free(x); \
    } \
    /* Real transforms of n points held as n / 2 complex: forward leaves 2 X, packed. */ \
    static void real_fft##suffix(const split *in, vDSP_Stride IA, const split *out, vDSP_Stride IC, size_t n, int direction) { \
        size_t half = n / 2; \
        double complex *x = malloc(n * sizeof(double complex)); \
        if (direction >= 0) { \
            for (size_t k = 0; k < half; k++) { x[2 * k] = in->realp[k * IA]; x[2 * k + 1] = in->imagp[k * IA]; } \
            transform(x, n, -1); \
            out->realp[0] = (type)(2 * creal(x[0])); \
            out->imagp[0] = (type)(2 * creal(x[half])); \
            for (size_t k = 1; k < half; k++) { out->realp[k * IC] = (type)(2 * creal(x[k])); out->imagp[k * IC] = (type)(2 * cimag(x[k])); } \
        } else { \
            x[0] = in->realp[0]; \
            x[half] = in->imagp[0]; \
            for (size_t k = 1; k < half; k++) { \
                x[k] = in->realp[k * IA] + IMAGINARY * in->imagp[k * IA]; \
                x[n - k] = conj(x[k]); \
            } \
            transform(x, n, 1); \
            for (size_t k = 0; k < half; k++) { out->realp[k * IC] = (type)creal(x[2 * k]); out->imagp[k * IC] = (type)creal(x[2 * k + 1]); } \
        } \
        free(x); \
    } \
    void vDSP_fft_zip##suffix(void *setup, const split *C, vDSP_Stride IC, vDSP_Length log2n, int direction) DARWIN_SYMBOL(vDSP_fft_zip##suffix); \
    void vDSP_fft_zip##suffix(void *setup, const split *C, vDSP_Stride IC, vDSP_Length log2n, int direction) { \
        complex_fft##suffix(C, IC, C, IC, (size_t)1 << log2n, direction); \
    } \
    void vDSP_fft_zop##suffix(void *setup, const split *A, vDSP_Stride IA, const split *C, vDSP_Stride IC, vDSP_Length log2n, int direction) \
        DARWIN_SYMBOL(vDSP_fft_zop##suffix); \
    void vDSP_fft_zop##suffix(void *setup, const split *A, vDSP_Stride IA, const split *C, vDSP_Stride IC, vDSP_Length log2n, int direction) { \
        complex_fft##suffix(A, IA, C, IC, (size_t)1 << log2n, direction); \
    } \
    void vDSP_fft_zrip##suffix(void *setup, const split *C, vDSP_Stride IC, vDSP_Length log2n, int direction) DARWIN_SYMBOL(vDSP_fft_zrip##suffix); \
    void vDSP_fft_zrip##suffix(void *setup, const split *C, vDSP_Stride IC, vDSP_Length log2n, int direction) { \
        real_fft##suffix(C, IC, C, IC, (size_t)1 << log2n, direction); \
    } \
    void vDSP_fft_zrop##suffix(void *setup, const split *A, vDSP_Stride IA, const split *C, vDSP_Stride IC, vDSP_Length log2n, int direction) \
        DARWIN_SYMBOL(vDSP_fft_zrop##suffix); \
    void vDSP_fft_zrop##suffix(void *setup, const split *A, vDSP_Stride IA, const split *C, vDSP_Stride IC, vDSP_Length log2n, int direction) { \
        real_fft##suffix(A, IA, C, IC, (size_t)1 << log2n, direction); \
    }

FFT(float, , DSPSplitComplex)
FFT(double, D, DSPDoubleSplitComplex)

// The DFT interface: setups remember the length, direction and kind.
typedef struct dft_setup { vDSP_Length length; int direction; int real; } dft_setup;

static void *dft_create(vDSP_Length length, int direction, int real) {
    dft_setup *setup = malloc(sizeof(dft_setup));
    if (setup) *setup = (dft_setup){length, direction, real};
    return setup;
}

#define DFT(type, suffix, split) \
    void *vDSP_DFT_zop_CreateSetup##suffix(void *previous, vDSP_Length length, int direction) DARWIN_SYMBOL(vDSP_DFT_zop_CreateSetup##suffix); \
    void *vDSP_DFT_zop_CreateSetup##suffix(void *previous, vDSP_Length length, int direction) { return dft_create(length, direction, 0); } \
    void *vDSP_DFT_zrop_CreateSetup##suffix(void *previous, vDSP_Length length, int direction) DARWIN_SYMBOL(vDSP_DFT_zrop_CreateSetup##suffix); \
    void *vDSP_DFT_zrop_CreateSetup##suffix(void *previous, vDSP_Length length, int direction) { return dft_create(length, direction, 1); } \
    void vDSP_DFT_Execute##suffix(const void *setup, const type *Ir, const type *Ii, type *Or, type *Oi) DARWIN_SYMBOL(vDSP_DFT_Execute##suffix); \
    void vDSP_DFT_Execute##suffix(const void *setup, const type *Ir, const type *Ii, type *Or, type *Oi) { \
        const dft_setup *s = setup; \
        split in = {(type *)Ir, (type *)Ii}, out = {Or, Oi}; \
        if (s->real) real_fft##suffix(&in, 1, &out, 1, s->length, s->direction); \
        else complex_fft##suffix(&in, 1, &out, 1, s->length, s->direction); \
    } \
    void vDSP_DFT_DestroySetup##suffix(void *setup) DARWIN_SYMBOL(vDSP_DFT_DestroySetup##suffix); \
    void vDSP_DFT_DestroySetup##suffix(void *setup) { free(setup); }

DFT(float, , DSPSplitComplex)
DFT(double, D, DSPDoubleSplitComplex)
