// vDSP: filters. Cascaded biquads (single and multichannel), the two-pole
// two-zero difference equation, decimation and two-dimensional FIRs.

#include "PerryAccelerate.h"

#include <stdlib.h>
#include <string.h>

#define EXPORT(ret, name, params) ret name params DARWIN_SYMBOL(name); ret name params

// MARK: - Biquads

// M sections of five coefficients each: b0, b1, b2, a1, a2, so that
// y[n] = b0 x[n] + b1 x[n-1] + b2 x[n-2] - a1 y[n-1] - a2 y[n-2].
// The caller's delay array holds 2 M + 2 values: x[n-2], x[n-1] of the
// first section's input, then y[n-2], y[n-1] of each section's output
// (which is the next section's input).
typedef struct biquad_setup { vDSP_Length sections; double coefficients[]; } biquad_setup;

static biquad_setup *biquad_create(const double *coefficients, vDSP_Length sections) {
    biquad_setup *setup = malloc(sizeof(biquad_setup) + sections * 5 * sizeof(double));
    if (!setup) return NULL;
    setup->sections = sections;
    memcpy(setup->coefficients, coefficients, sections * 5 * sizeof(double));
    return setup;
}

#define BIQUAD(type, suffix) \
    static void biquad_run##suffix(const double *coefficients, vDSP_Length sections, type *delay, const type *X, \
                                   vDSP_Stride IX, type *Y, vDSP_Stride IY, vDSP_Length N) { \
        for (vDSP_Length n = 0; n < N; n++) { \
            type x = X[n * IX], i0 = delay[1], i1 = delay[0]; \
            delay[0] = i0; delay[1] = x; \
            for (vDSP_Length m = 0; m < sections; m++) { \
                const double *c = coefficients + 5 * m; \
                type o0 = delay[2 * m + 3], o1 = delay[2 * m + 2]; \
                type y = (type)(c[0] * x + c[1] * i0 + c[2] * i1 - c[3] * o0 - c[4] * o1); \
                delay[2 * m + 2] = o0; delay[2 * m + 3] = y; \
                i0 = o0; i1 = o1; x = y; \
            } \
            Y[n * IY] = x; \
        } \
    } \
    EXPORT(void *, vDSP_biquad_CreateSetup##suffix, (const double *Coefficients, vDSP_Length M)) { \
        return biquad_create(Coefficients, M); \
    } \
    EXPORT(void, vDSP_biquad_DestroySetup##suffix, (void *setup)) { free(setup); } \
    EXPORT(void, vDSP_biquad##suffix, (const void *Setup, type *Delay, const type *X, vDSP_Stride IX, type *Y, \
                                       vDSP_Stride IY, vDSP_Length N)) { \
        const biquad_setup *setup = Setup; \
        biquad_run##suffix(setup->coefficients, setup->sections, Delay, X, IX, Y, IY, N); \
    }

BIQUAD(float, )
BIQUAD(double, D)

// Multichannel: M sections of N channels, coefficients section by section
// and, within one, channel by channel; the delays live in the setup.
typedef struct biquadm_setup {
    vDSP_Length sections, channels;
    double *coefficients; // [section][channel][5], as given
    double *gathered;     // [channel][section][5]
    void *delays;         // [channel][2 * sections + 2]
} biquadm_setup;

#define BIQUADM(type, suffix) \
    EXPORT(void *, vDSP_biquadm_CreateSetup##suffix, (const double *coeffs, vDSP_Length M, vDSP_Length N)) { \
        biquadm_setup *setup = calloc(1, sizeof(biquadm_setup)); \
        if (!setup) return NULL; \
        setup->sections = M; setup->channels = N; \
        setup->coefficients = malloc(M * N * 5 * sizeof(double)); \
        setup->gathered = malloc(M * N * 5 * sizeof(double)); \
        setup->delays = calloc(N * (2 * M + 2), sizeof(type)); \
        if (!setup->coefficients || !setup->gathered || !setup->delays) { \
            free(setup->coefficients); free(setup->gathered); free(setup->delays); free(setup); \
            return NULL; \
        } \
        memcpy(setup->coefficients, coeffs, M * N * 5 * sizeof(double)); \
        for (vDSP_Length c = 0; c < N; c++) \
            for (vDSP_Length m = 0; m < M; m++) \
                memcpy(setup->gathered + (c * M + m) * 5, coeffs + (m * N + c) * 5, 5 * sizeof(double)); \
        return setup; \
    } \
    EXPORT(void, vDSP_biquadm_DestroySetup##suffix, (void *Setup)) { \
        biquadm_setup *setup = Setup; \
        if (!setup) return; \
        free(setup->coefficients); free(setup->gathered); free(setup->delays); free(setup); \
    } \
    EXPORT(void, vDSP_biquadm##suffix, (void *Setup, const type **X, vDSP_Stride IX, type **Y, vDSP_Stride IY, \
                                        vDSP_Length N)) { \
        biquadm_setup *setup = Setup; \
        vDSP_Length M = setup->sections; \
        for (vDSP_Length c = 0; c < setup->channels; c++) \
            biquad_run##suffix(setup->gathered + c * M * 5, M, (type *)setup->delays + c * (2 * M + 2), X[c], IX, Y[c], IY, N); \
    }

BIQUADM(float, )
BIQUADM(double, D)

// MARK: - Difference equation, decimation, image filters

#define FILTERS(type, suffix) \
    /* C[0] and C[1] are given; C[n] = A[n] B0 + A[n-1] B1 + A[n-2] B2 - C[n-1] B3 - C[n-2] B4 for the next N. */ \
    EXPORT(void, vDSP_deq22##suffix, (const type *A, vDSP_Stride IA, const type *B, type *C, vDSP_Stride IC, vDSP_Length N)) { \
        for (vDSP_Length n = 2; n < N + 2; n++) \
            C[n * IC] = A[n * IA] * B[0] + A[(n - 1) * IA] * B[1] + A[(n - 2) * IA] * B[2] \
                      - C[(n - 1) * IC] * B[3] - C[(n - 2) * IC] * B[4]; \
    } \
    EXPORT(void, vDSP_desamp##suffix, (const type *A, vDSP_Stride DF, const type *F, type *C, vDSP_Length N, vDSP_Length P)) { \
        for (vDSP_Length n = 0; n < N; n++) { \
            type sum = 0; \
            for (vDSP_Length p = 0; p < P; p++) sum += A[n * DF + p] * F[p]; \
            C[n] = sum; \
        } \
    } \
    /* A P x Q filter over an NR x NC image; the border it cannot reach is zero. */ \
    EXPORT(void, vDSP_imgfir##suffix, (const type *A, vDSP_Length NR, vDSP_Length NC, const type *F, type *C, vDSP_Length P, \
                                       vDSP_Length Q)) { \
        vDSP_Length hp = P / 2, hq = Q / 2; \
        for (vDSP_Length r = 0; r < NR; r++) \
            for (vDSP_Length c = 0; c < NC; c++) { \
                if (r < hp || r + hp >= NR || c < hq || c + hq >= NC) { C[r * NC + c] = 0; continue; } \
                type sum = 0; \
                for (vDSP_Length i = 0; i < P; i++) \
                    for (vDSP_Length j = 0; j < Q; j++) sum += A[(r + i - hp) * NC + (c + j - hq)] * F[i * Q + j]; \
                C[r * NC + c] = sum; \
            } \
    } \
    EXPORT(void, vDSP_f3x3##suffix, (const type *A, vDSP_Length NR, vDSP_Length NC, const type *F, type *C)) { \
        vDSP_imgfir##suffix(A, NR, NC, F, C, 3, 3); \
    } \
    EXPORT(void, vDSP_f5x5##suffix, (const type *A, vDSP_Length NR, vDSP_Length NC, const type *F, type *C)) { \
        vDSP_imgfir##suffix(A, NR, NC, F, C, 5, 5); \
    }

FILTERS(float, )
FILTERS(double, D)
