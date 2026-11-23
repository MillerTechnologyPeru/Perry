// vImage per-pixel transforms: color matrices, gamma curves (simple and
// piecewise), piecewise polynomials, lookup tables (one- and
// multi-dimensional) and flood fill.

#include "vimage.h"

#include <math.h>

static vImage_Error same_size(const vImage_Buffer *src, const vImage_Buffer *dest) {
    if (!src || !dest || !src->data || !dest->data) return kvImageNullPointerArgument;
    if (dest->width > src->width || dest->height > src->height) return kvImageBufferSizeMismatch;
    return kvImageNoError;
}

static const void *row(const vImage_Buffer *b, vImagePixelCount y) { return (const uint8_t *)b->data + y * b->rowBytes; }
static void *mrow(const vImage_Buffer *b, vImagePixelCount y) { return (uint8_t *)b->data + y * b->rowBytes; }

static uint8_t clamp_int8(int64_t v) { return v < 0 ? 0 : v > 255 ? 255 : (uint8_t)v; }

// MARK: - Matrix multiply

/// (sum of (src[k] + preBias[k]) * matrix[k][c] + postBias[c]) / divisor per
/// destination channel c, where the post bias defaults to divisor / 2.
static uint8_t matrix8(const uint8_t *in, int inCount, const int16_t *matrix, int outCount, int c, int32_t divisor, const int16_t *preBias,
                       const int32_t *postBias) {
    int64_t sum = 0;
    for (int k = 0; k < inCount; k++) sum += (int64_t)(in[k] + (preBias ? preBias[k] : 0)) * matrix[k * outCount + c];
    sum += postBias ? postBias[c] : divisor / 2;
    return clamp_int8(divisor ? sum / divisor : sum);
}

/// `biasRows` is the row length vImage uses when it weighs the pre bias,
/// which for the planar function is the number of source planes rather than
/// destination planes; it is matched here as long as it stays in the matrix.
static float matrixF(const float *in, int inCount, const float *matrix, int outCount, int c, const float *preBias, const float *postBias,
                     int biasRows) {
    float sum = 0;
    for (int k = 0; k < inCount; k++) {
        sum += in[k] * matrix[k * outCount + c];
        if (preBias) {
            int at = k * biasRows + c;
            sum += preBias[k] * matrix[at < inCount * outCount ? at : k * outCount + c];
        }
    }
    return sum + (postBias ? postBias[c] : 0);
}

vImage_Error vImageMatrixMultiply_ARGB8888(const vImage_Buffer *src, const vImage_Buffer *dest, const int16_t matrix[4 * 4], int32_t divisor,
                                           const int16_t *pre_bias, const int32_t *post_bias, vImage_Flags flags)
    DARWIN_SYMBOL(vImageMatrixMultiply_ARGB8888);
vImage_Error vImageMatrixMultiply_ARGB8888(const vImage_Buffer *src, const vImage_Buffer *dest, const int16_t matrix[4 * 4], int32_t divisor,
                                           const int16_t *pre_bias, const int32_t *post_bias, vImage_Flags flags) {
    vImage_Error error = same_size(src, dest);
    if (error) return error;
    if (!matrix) return kvImageNullPointerArgument;
    for (vImagePixelCount y = 0; y < dest->height; y++) {
        const uint8_t *s = row(src, y);
        uint8_t *d = mrow(dest, y);
        for (vImagePixelCount x = 0; x < dest->width; x++) {
            uint8_t in[4] = {s[x * 4], s[x * 4 + 1], s[x * 4 + 2], s[x * 4 + 3]};
            for (int c = 0; c < 4; c++) d[x * 4 + c] = matrix8(in, 4, matrix, 4, c, divisor, pre_bias, post_bias);
        }
    }
    return kvImageNoError;
}

vImage_Error vImageMatrixMultiply_ARGB8888ToPlanar8(const vImage_Buffer *src, const vImage_Buffer *dest, const int16_t matrix[4],
                                                    int32_t divisor, const int16_t pre_bias[4], int32_t post_bias, vImage_Flags flags)
    DARWIN_SYMBOL(vImageMatrixMultiply_ARGB8888ToPlanar8);
vImage_Error vImageMatrixMultiply_ARGB8888ToPlanar8(const vImage_Buffer *src, const vImage_Buffer *dest, const int16_t matrix[4],
                                                    int32_t divisor, const int16_t pre_bias[4], int32_t post_bias, vImage_Flags flags) {
    vImage_Error error = same_size(src, dest);
    if (error) return error;
    if (!matrix) return kvImageNullPointerArgument;
    for (vImagePixelCount y = 0; y < dest->height; y++) {
        const uint8_t *s = row(src, y);
        uint8_t *d = mrow(dest, y);
        for (vImagePixelCount x = 0; x < dest->width; x++) d[x] = matrix8(s + x * 4, 4, matrix, 1, 0, divisor, pre_bias, &post_bias);
    }
    return kvImageNoError;
}

vImage_Error vImageMatrixMultiply_ARGBFFFF(const vImage_Buffer *src, const vImage_Buffer *dest, const float matrix[4 * 4],
                                           const float *pre_bias, const float *post_bias, vImage_Flags flags)
    DARWIN_SYMBOL(vImageMatrixMultiply_ARGBFFFF);
vImage_Error vImageMatrixMultiply_ARGBFFFF(const vImage_Buffer *src, const vImage_Buffer *dest, const float matrix[4 * 4],
                                           const float *pre_bias, const float *post_bias, vImage_Flags flags) {
    vImage_Error error = same_size(src, dest);
    if (error) return error;
    if (!matrix) return kvImageNullPointerArgument;
    for (vImagePixelCount y = 0; y < dest->height; y++) {
        const float *s = row(src, y);
        float *d = mrow(dest, y);
        for (vImagePixelCount x = 0; x < dest->width; x++) {
            float in[4] = {s[x * 4], s[x * 4 + 1], s[x * 4 + 2], s[x * 4 + 3]};
            for (int c = 0; c < 4; c++) d[x * 4 + c] = matrixF(in, 4, matrix, 4, c, pre_bias, post_bias, 4);
        }
    }
    return kvImageNoError;
}

vImage_Error vImageMatrixMultiply_ARGBFFFFToPlanarF(const vImage_Buffer *src, const vImage_Buffer *dest, const float matrix[4],
                                                    const float pre_bias[4], float post_bias, vImage_Flags flags)
    DARWIN_SYMBOL(vImageMatrixMultiply_ARGBFFFFToPlanarF);
vImage_Error vImageMatrixMultiply_ARGBFFFFToPlanarF(const vImage_Buffer *src, const vImage_Buffer *dest, const float matrix[4],
                                                    const float pre_bias[4], float post_bias, vImage_Flags flags) {
    vImage_Error error = same_size(src, dest);
    if (error) return error;
    if (!matrix) return kvImageNullPointerArgument;
    for (vImagePixelCount y = 0; y < dest->height; y++) {
        const float *s = row(src, y);
        float *d = mrow(dest, y);
        for (vImagePixelCount x = 0; x < dest->width; x++) d[x] = matrixF(s + x * 4, 4, matrix, 1, 0, pre_bias, &post_bias, 1);
    }
    return kvImageNoError;
}

/// The planes must all match the first destination's size, within the
/// first source's.
static vImage_Error planes_check(const vImage_Buffer *srcs[], const vImage_Buffer *dests[], uint32_t srcPlanes, uint32_t destPlanes) {
    if (!srcs || !dests || !srcPlanes || !destPlanes) return srcs && dests ? kvImageInvalidParameter : kvImageNullPointerArgument;
    for (uint32_t i = 0; i < srcPlanes; i++)
        if (!srcs[i] || !srcs[i]->data) return kvImageNullPointerArgument;
    for (uint32_t i = 0; i < destPlanes; i++) {
        if (!dests[i] || !dests[i]->data) return kvImageNullPointerArgument;
        if (dests[i]->width != dests[0]->width || dests[i]->height != dests[0]->height) return kvImageBufferSizeMismatch;
    }
    for (uint32_t i = 0; i < srcPlanes; i++)
        if (srcs[i]->width < dests[0]->width || srcs[i]->height < dests[0]->height) return kvImageBufferSizeMismatch;
    return kvImageNoError;
}

vImage_Error vImageMatrixMultiply_Planar8(const vImage_Buffer *srcs[], const vImage_Buffer *dests[], uint32_t src_planes, uint32_t dest_planes,
                                          const int16_t matrix[], int32_t divisor, const int16_t *pre_bias, const int32_t *post_bias,
                                          vImage_Flags flags) DARWIN_SYMBOL(vImageMatrixMultiply_Planar8);
vImage_Error vImageMatrixMultiply_Planar8(const vImage_Buffer *srcs[], const vImage_Buffer *dests[], uint32_t src_planes, uint32_t dest_planes,
                                          const int16_t matrix[], int32_t divisor, const int16_t *pre_bias, const int32_t *post_bias,
                                          vImage_Flags flags) {
    vImage_Error error = planes_check(srcs, dests, src_planes, dest_planes);
    if (error) return error;
    if (!matrix) return kvImageNullPointerArgument;
    uint8_t *in = malloc(src_planes), *out = malloc(dest_planes);
    if (!in || !out) { free(in); free(out); return kvImageMemoryAllocationError; }
    for (vImagePixelCount y = 0; y < dests[0]->height; y++)
        for (vImagePixelCount x = 0; x < dests[0]->width; x++) {
            for (uint32_t k = 0; k < src_planes; k++) in[k] = ((const uint8_t *)row(srcs[k], y))[x];
            // Every output first, so a destination plane may also be a source plane.
            for (uint32_t c = 0; c < dest_planes; c++) out[c] = matrix8(in, (int)src_planes, matrix, (int)dest_planes, (int)c, divisor, pre_bias, post_bias);
            for (uint32_t c = 0; c < dest_planes; c++) ((uint8_t *)mrow(dests[c], y))[x] = out[c];
        }
    free(in);
    free(out);
    return kvImageNoError;
}

vImage_Error vImageMatrixMultiply_PlanarF(const vImage_Buffer *srcs[], const vImage_Buffer *dests[], uint32_t src_planes, uint32_t dest_planes,
                                          const float matrix[], const float *pre_bias, const float *post_bias, vImage_Flags flags)
    DARWIN_SYMBOL(vImageMatrixMultiply_PlanarF);
vImage_Error vImageMatrixMultiply_PlanarF(const vImage_Buffer *srcs[], const vImage_Buffer *dests[], uint32_t src_planes, uint32_t dest_planes,
                                          const float matrix[], const float *pre_bias, const float *post_bias, vImage_Flags flags) {
    vImage_Error error = planes_check(srcs, dests, src_planes, dest_planes);
    if (error) return error;
    if (!matrix) return kvImageNullPointerArgument;
    float *in = malloc(sizeof(float) * src_planes), *out = malloc(sizeof(float) * dest_planes);
    if (!in || !out) { free(in); free(out); return kvImageMemoryAllocationError; }
    for (vImagePixelCount y = 0; y < dests[0]->height; y++)
        for (vImagePixelCount x = 0; x < dests[0]->width; x++) {
            for (uint32_t k = 0; k < src_planes; k++) in[k] = ((const float *)row(srcs[k], y))[x];
            for (uint32_t c = 0; c < dest_planes; c++) out[c] = matrixF(in, (int)src_planes, matrix, (int)dest_planes, (int)c, pre_bias, post_bias,
                                                                    (int)src_planes);
            for (uint32_t c = 0; c < dest_planes; c++) ((float *)mrow(dests[c], y))[x] = out[c];
        }
    free(in);
    free(out);
    return kvImageNoError;
}

// MARK: - Gamma

enum {
    kvImageGamma_UseGammaValue = 0,
    kvImageGamma_UseGammaValue_half_precision = 1,
    kvImageGamma_5_over_9_half_precision = 2,
    kvImageGamma_9_over_5_half_precision = 3,
    kvImageGamma_5_over_11_half_precision = 4,
    kvImageGamma_11_over_5_half_precision = 5,
    kvImageGamma_sRGB_forward_half_precision = 6,
    kvImageGamma_sRGB_reverse_half_precision = 7,
    kvImageGamma_11_over_9_half_precision = 8,
    kvImageGamma_9_over_11_half_precision = 9,
    kvImageGamma_BT709_forward_half_precision = 10,
    kvImageGamma_BT709_reverse_half_precision = 11,
};

/// A GammaFunction is one of these, malloc'd.
typedef struct GammaState {
    int type;
    float gamma;
} GammaState;

GammaFunction vImageCreateGammaFunction(float gamma, int gamma_type, vImage_Flags flags) DARWIN_SYMBOL(vImageCreateGammaFunction);
GammaFunction vImageCreateGammaFunction(float gamma, int gamma_type, vImage_Flags flags) {
    static const float fixed[] = {0, 0, 5.0f / 9, 9.0f / 5, 5.0f / 11, 11.0f / 5, 0, 0, 11.0f / 9, 9.0f / 11, 0, 0};
    if (gamma_type < 0 || gamma_type > kvImageGamma_BT709_reverse_half_precision) return NULL;
    GammaState *state = malloc(sizeof(GammaState));
    if (!state) return NULL;
    state->type = gamma_type;
    state->gamma = fixed[gamma_type] != 0 ? fixed[gamma_type] : gamma;
    return state;
}

void vImageDestroyGammaFunction(GammaFunction f) DARWIN_SYMBOL(vImageDestroyGammaFunction);
void vImageDestroyGammaFunction(GammaFunction f) { free(f); }

static float apply_gamma(const GammaState *g, float x) {
    switch (g->type) {
    case kvImageGamma_UseGammaValue:
    case kvImageGamma_UseGammaValue_half_precision: {
        float m = powf(fabsf(x), g->gamma);
        return x < 0 ? -m : m;
    }
    case kvImageGamma_sRGB_forward_half_precision:
    case kvImageGamma_sRGB_reverse_half_precision:
    case kvImageGamma_BT709_forward_half_precision:
    case kvImageGamma_BT709_reverse_half_precision:
        x = x < 0 ? 0 : x > 1 ? 1 : x;
        switch (g->type) {
        case kvImageGamma_sRGB_forward_half_precision: return x <= 0.04045f ? x / 12.92f : powf((x + 0.055f) / 1.055f, 2.4f);
        case kvImageGamma_sRGB_reverse_half_precision: return x <= 0.0031308f ? x * 12.92f : 1.055f * powf(x, 1 / 2.4f) - 0.055f;
        case kvImageGamma_BT709_forward_half_precision: return x < 0.081f ? x / 4.5f : powf((x + 0.099f) / 1.099f, 1 / 0.45f);
        default: return x < 0.018f ? x * 4.5f : 1.099f * powf(x, 0.45f) - 0.099f;
        }
    default:
        // The half-precision curves clamp to [0, 1] first.
        x = x < 0 ? 0 : x > 1 ? 1 : x;
        return powf(x, g->gamma);
    }
}

vImage_Error vImageGamma_PlanarF(const vImage_Buffer *src, const vImage_Buffer *dest, const GammaFunction gamma, vImage_Flags flags)
    DARWIN_SYMBOL(vImageGamma_PlanarF);
vImage_Error vImageGamma_PlanarF(const vImage_Buffer *src, const vImage_Buffer *dest, const GammaFunction gamma, vImage_Flags flags) {
    vImage_Error error = same_size(src, dest);
    if (error) return error;
    if (!gamma) return kvImageNullPointerArgument;
    for (vImagePixelCount y = 0; y < dest->height; y++) {
        const float *s = row(src, y);
        float *d = mrow(dest, y);
        for (vImagePixelCount x = 0; x < dest->width; x++) d[x] = apply_gamma(gamma, s[x]);
    }
    return kvImageNoError;
}

vImage_Error vImageGamma_Planar8toPlanarF(const vImage_Buffer *src, const vImage_Buffer *dest, const GammaFunction gamma, vImage_Flags flags)
    DARWIN_SYMBOL(vImageGamma_Planar8toPlanarF);
vImage_Error vImageGamma_Planar8toPlanarF(const vImage_Buffer *src, const vImage_Buffer *dest, const GammaFunction gamma, vImage_Flags flags) {
    vImage_Error error = same_size(src, dest);
    if (error) return error;
    if (!gamma) return kvImageNullPointerArgument;
    float table[256];
    for (int i = 0; i < 256; i++) table[i] = apply_gamma(gamma, (float)i / 255.0f);
    for (vImagePixelCount y = 0; y < dest->height; y++) {
        const uint8_t *s = row(src, y);
        float *d = mrow(dest, y);
        for (vImagePixelCount x = 0; x < dest->width; x++) d[x] = table[s[x]];
    }
    return kvImageNoError;
}

static float piecewise_gamma(float x, const float exponential[3], float gamma, const float linear[2], float boundary) {
    if (x < boundary) return linear[0] * x + linear[1];
    return powf(exponential[0] * x + exponential[1], gamma) + exponential[2];
}

vImage_Error vImagePiecewiseGamma_Planar8(const vImage_Buffer *src, const vImage_Buffer *dest, const float exponentialCoeffs[3],
                                          const float gamma, const float linearCoeffs[2], const Pixel_8 boundary, vImage_Flags flags)
    DARWIN_SYMBOL(vImagePiecewiseGamma_Planar8);
vImage_Error vImagePiecewiseGamma_Planar8(const vImage_Buffer *src, const vImage_Buffer *dest, const float exponentialCoeffs[3],
                                          const float gamma, const float linearCoeffs[2], const Pixel_8 boundary, vImage_Flags flags) {
    if (flags & kvImageGetTempBufferSize) return 0;
    vImage_Error error = same_size(src, dest);
    if (error) return error;
    if (!exponentialCoeffs || !linearCoeffs) return kvImageNullPointerArgument;
    uint8_t table[256];
    for (int i = 0; i < 256; i++) {
        float r = i < boundary ? linearCoeffs[0] * (i / 255.0f) + linearCoeffs[1]
                               : powf(exponentialCoeffs[0] * (i / 255.0f) + exponentialCoeffs[1], gamma) + exponentialCoeffs[2];
        r = r != r ? 0 : r < 0 ? 0 : r > 1 ? 1 : r;
        table[i] = (uint8_t)lrintf(r * 255.0f);
    }
    for (vImagePixelCount y = 0; y < dest->height; y++) {
        const uint8_t *s = row(src, y);
        uint8_t *d = mrow(dest, y);
        for (vImagePixelCount x = 0; x < dest->width; x++) d[x] = table[s[x]];
    }
    return kvImageNoError;
}

vImage_Error vImagePiecewiseGamma_PlanarF(const vImage_Buffer *src, const vImage_Buffer *dest, const float exponentialCoeffs[3],
                                          const float gamma, const float linearCoeffs[2], const float boundary, vImage_Flags flags)
    DARWIN_SYMBOL(vImagePiecewiseGamma_PlanarF);
vImage_Error vImagePiecewiseGamma_PlanarF(const vImage_Buffer *src, const vImage_Buffer *dest, const float exponentialCoeffs[3],
                                          const float gamma, const float linearCoeffs[2], const float boundary, vImage_Flags flags) {
    if (flags & kvImageGetTempBufferSize) return 0;
    vImage_Error error = same_size(src, dest);
    if (error) return error;
    if (!exponentialCoeffs || !linearCoeffs) return kvImageNullPointerArgument;
    for (vImagePixelCount y = 0; y < dest->height; y++) {
        const float *s = row(src, y);
        float *d = mrow(dest, y);
        for (vImagePixelCount x = 0; x < dest->width; x++) d[x] = piecewise_gamma(s[x], exponentialCoeffs, gamma, linearCoeffs, boundary);
    }
    return kvImageNoError;
}

// MARK: - Piecewise polynomials

/// 2^log2segments polynomials of order + 1 coefficients (lowest power
/// first), the ith covering boundaries[i] <= x < boundaries[i + 1]; x is
/// clamped to [boundaries[0], boundaries[N]] first.
static float polynomial(float x, const float **coefficients, const float *boundaries, uint32_t order, uint32_t segments) {
    if (x != x) return x;
    if (x < boundaries[0]) x = boundaries[0];
    if (x > boundaries[segments]) x = boundaries[segments];
    uint32_t lo = 0, hi = segments - 1;  // the last segment whose start is <= x
    while (lo < hi) {
        uint32_t mid = (lo + hi + 1) / 2;
        if (boundaries[mid] <= x) lo = mid;
        else hi = mid - 1;
    }
    const float *c = coefficients[lo];
    float r = c[order];
    for (uint32_t k = order; k-- > 0;) r = r * x + c[k];
    return r;
}

static vImage_Error polynomial_check(const vImage_Buffer *src, const vImage_Buffer *dest, const float **coefficients, const float *boundaries,
                                     uint32_t log2segments) {
    vImage_Error error = same_size(src, dest);
    if (error) return error;
    if (!coefficients || !boundaries) return kvImageNullPointerArgument;
    if (log2segments > 16) return kvImageInvalidParameter;
    for (uint32_t i = 0; i < (1u << log2segments); i++)
        if (!coefficients[i]) return kvImageNullPointerArgument;
    return kvImageNoError;
}

#define POLYNOMIAL_ARGS \
    const vImage_Buffer *src, const vImage_Buffer *dest, const float **coefficients, const float *boundaries, uint32_t order, \
        uint32_t log2segments, vImage_Flags flags

vImage_Error vImagePiecewisePolynomial_PlanarF(POLYNOMIAL_ARGS) DARWIN_SYMBOL(vImagePiecewisePolynomial_PlanarF);
vImage_Error vImagePiecewisePolynomial_PlanarF(POLYNOMIAL_ARGS) {
    vImage_Error error = polynomial_check(src, dest, coefficients, boundaries, log2segments);
    if (error) return error;
    for (vImagePixelCount y = 0; y < dest->height; y++) {
        const float *s = row(src, y);
        float *d = mrow(dest, y);
        for (vImagePixelCount x = 0; x < dest->width; x++) d[x] = polynomial(s[x], coefficients, boundaries, order, 1u << log2segments);
    }
    return kvImageNoError;
}

vImage_Error vImagePiecewisePolynomial_Planar8toPlanarF(POLYNOMIAL_ARGS) DARWIN_SYMBOL(vImagePiecewisePolynomial_Planar8toPlanarF);
vImage_Error vImagePiecewisePolynomial_Planar8toPlanarF(POLYNOMIAL_ARGS) {
    vImage_Error error = polynomial_check(src, dest, coefficients, boundaries, log2segments);
    if (error) return error;
    float table[256];
    // vImage feeds the polynomials i / 255.
    for (int i = 0; i < 256; i++) table[i] = polynomial((float)i / 255.0f, coefficients, boundaries, order, 1u << log2segments);
    for (vImagePixelCount y = 0; y < dest->height; y++) {
        const uint8_t *s = row(src, y);
        float *d = mrow(dest, y);
        for (vImagePixelCount x = 0; x < dest->width; x++) d[x] = table[s[x]];
    }
    return kvImageNoError;
}

vImage_Error vImagePiecewisePolynomial_PlanarFtoPlanar8(POLYNOMIAL_ARGS) DARWIN_SYMBOL(vImagePiecewisePolynomial_PlanarFtoPlanar8);
vImage_Error vImagePiecewisePolynomial_PlanarFtoPlanar8(POLYNOMIAL_ARGS) {
    vImage_Error error = polynomial_check(src, dest, coefficients, boundaries, log2segments);
    if (error) return error;
    for (vImagePixelCount y = 0; y < dest->height; y++) {
        const float *s = row(src, y);
        uint8_t *d = mrow(dest, y);
        for (vImagePixelCount x = 0; x < dest->width; x++) {
            float r = polynomial(s[x], coefficients, boundaries, order, 1u << log2segments);
            d[x] = r != r ? 0 : r <= 0 ? 0 : r >= 255 ? 255 : (uint8_t)r;  // truncated, as vImage does
        }
    }
    return kvImageNoError;
}

// MARK: - Lookup tables

static vImage_Error lookup_check(const vImage_Buffer *src, const vImage_Buffer *dest, const void *table) {
    if (!src || !dest || !src->data || !dest->data || !table) return kvImageNullPointerArgument;
    if (src->width != dest->width || src->height != dest->height) return kvImageBufferSizeMismatch;
    return kvImageNoError;
}

vImage_Error vImageLookupTable_Planar16(const vImage_Buffer *src, const vImage_Buffer *dest, const Pixel_16U table[0x10000], vImage_Flags flags)
    DARWIN_SYMBOL(vImageLookupTable_Planar16);
vImage_Error vImageLookupTable_Planar16(const vImage_Buffer *src, const vImage_Buffer *dest, const Pixel_16U table[0x10000], vImage_Flags flags) {
    vImage_Error error = lookup_check(src, dest, table);
    if (error) return error;
    for (vImagePixelCount y = 0; y < dest->height; y++) {
        const uint16_t *s = row(src, y);
        uint16_t *d = mrow(dest, y);
        for (vImagePixelCount x = 0; x < dest->width; x++) d[x] = table[s[x]];
    }
    return kvImageNoError;
}

/// Bytes 1, 2 and 3 of each 32-bit entry, as laid out in memory.
vImage_Error vImageLookupTable_Planar8toPlanar24(const vImage_Buffer *src, const vImage_Buffer *dest, const uint32_t table[256], vImage_Flags flags)
    DARWIN_SYMBOL(vImageLookupTable_Planar8toPlanar24);
vImage_Error vImageLookupTable_Planar8toPlanar24(const vImage_Buffer *src, const vImage_Buffer *dest, const uint32_t table[256], vImage_Flags flags) {
    vImage_Error error = lookup_check(src, dest, table);
    if (error) return error;
    for (vImagePixelCount y = 0; y < dest->height; y++) {
        const uint8_t *s = row(src, y);
        uint8_t *d = mrow(dest, y);
        for (vImagePixelCount x = 0; x < dest->width; x++) memcpy(d + x * 3, (const uint8_t *)(table + s[x]) + 1, 3);
    }
    return kvImageNoError;
}

/// Elements 1, 2 and 3 of each four-float entry.
vImage_Error vImageLookupTable_Planar8toPlanar96(const vImage_Buffer *src, const vImage_Buffer *dest, const Pixel_FFFF table[256], vImage_Flags flags)
    DARWIN_SYMBOL(vImageLookupTable_Planar8toPlanar96);
vImage_Error vImageLookupTable_Planar8toPlanar96(const vImage_Buffer *src, const vImage_Buffer *dest, const Pixel_FFFF table[256], vImage_Flags flags) {
    vImage_Error error = lookup_check(src, dest, table);
    if (error) return error;
    for (vImagePixelCount y = 0; y < dest->height; y++) {
        const uint8_t *s = row(src, y);
        uint8_t *d = mrow(dest, y);
        for (vImagePixelCount x = 0; x < dest->width; x++) memcpy(d + x * 12, &table[s[x]][1], 12);
    }
    return kvImageNoError;
}

/// Index min(max(x * 4096, 0), 4095), truncated.
vImage_Error vImageLookupTable_PlanarFtoPlanar8(const vImage_Buffer *src, const vImage_Buffer *dest, const Pixel_8 table[4096], vImage_Flags flags)
    DARWIN_SYMBOL(vImageLookupTable_PlanarFtoPlanar8);
vImage_Error vImageLookupTable_PlanarFtoPlanar8(const vImage_Buffer *src, const vImage_Buffer *dest, const Pixel_8 table[4096], vImage_Flags flags) {
    vImage_Error error = lookup_check(src, dest, table);
    if (error) return error;
    for (vImagePixelCount y = 0; y < dest->height; y++) {
        const float *s = row(src, y);
        uint8_t *d = mrow(dest, y);
        for (vImagePixelCount x = 0; x < dest->width; x++) {
            float f = s[x] * 4096.0f;
            d[x] = table[f >= 4095.0f ? 4095 : f > 0 ? (uint32_t)f : 0];
        }
    }
    return kvImageNoError;
}

// MARK: - Multidimensional tables

/// A vImage_MultidimensionalTable: a copy of the grid, as floats in [0, 1].
typedef struct MultidimensionalTable {
    unsigned retainCount;
    uint32_t inputs, outputs;
    uint32_t entries[16];
    size_t strides[16];  // in grid points
    float values[];
} MultidimensionalTable;

typedef uint32_t vImageMDTableUsageHint;
typedef uint32_t vImage_InterpolationMethod;
enum { kvImageMDTableHint_16Q12 = 1, kvImageMDTableHint_Float = 2 };
enum { kvImageNoInterpolation = 0, kvImageFullInterpolation = 1, kvImageHalfInterpolation = 2 };

MultidimensionalTable *vImageMultidimensionalTable_Create(const uint16_t *tableData, uint32_t numSrcChannels, uint32_t numDestChannels,
                                                          const uint8_t table_entries_per_dimension[], vImageMDTableUsageHint hint,
                                                          vImage_Flags flags, vImage_Error *err) DARWIN_SYMBOL(vImageMultidimensionalTable_Create);
MultidimensionalTable *vImageMultidimensionalTable_Create(const uint16_t *tableData, uint32_t numSrcChannels, uint32_t numDestChannels,
                                                          const uint8_t table_entries_per_dimension[], vImageMDTableUsageHint hint,
                                                          vImage_Flags flags, vImage_Error *err) {
    vImage_Error error = kvImageNoError;
    MultidimensionalTable *table = NULL;
    size_t points = 1;
    if (!tableData || !table_entries_per_dimension) error = kvImageNullPointerArgument;
    else if (!numSrcChannels || !numDestChannels || numSrcChannels > 16 || !(hint & (kvImageMDTableHint_16Q12 | kvImageMDTableHint_Float)) ||
             (hint & ~(vImageMDTableUsageHint)(kvImageMDTableHint_16Q12 | kvImageMDTableHint_Float)))
        error = kvImageInvalidParameter;
    else {
        for (uint32_t i = 0; i < numSrcChannels; i++) {
            if (table_entries_per_dimension[i] < 2) error = kvImageInvalidParameter;
            points *= table_entries_per_dimension[i];
        }
    }
    if (!error) {
        table = malloc(sizeof(MultidimensionalTable) + sizeof(float) * points * numDestChannels);
        if (!table) error = kvImageMemoryAllocationError;
    }
    if (!error) {
        table->retainCount = 1;
        table->inputs = numSrcChannels;
        table->outputs = numDestChannels;
        size_t stride = 1;
        // The last channel varies fastest. vImage pairs the entry counts with the channels the other way
        // around (channel i has table_entries_per_dimension[N - 1 - i] entries); that is matched here.
        for (uint32_t i = numSrcChannels; i-- > 0;) {
            table->entries[i] = table_entries_per_dimension[numSrcChannels - 1 - i];
            table->strides[i] = stride;
            stride *= table->entries[i];
        }
        for (size_t i = 0; i < points * numDestChannels; i++) table->values[i] = tableData[i] / 65535.0f;
    }
    if (err) *err = error;
    return table;
}

vImage_Error vImageMultidimensionalTable_Release(MultidimensionalTable *table) DARWIN_SYMBOL(vImageMultidimensionalTable_Release);
vImage_Error vImageMultidimensionalTable_Release(MultidimensionalTable *table) {
    if (!table) return kvImageNullPointerArgument;
    if (__atomic_sub_fetch(&table->retainCount, 1, __ATOMIC_ACQ_REL) == 0) free(table);
    return kvImageNoError;
}

/// Looks up one pixel, blending all 2^N corners of its grid cell. vImage
/// does this for every interpolation method, so this does too.
static void md_lookup(const MultidimensionalTable *t, const float *in, float *out) {
    size_t base = 0;
    float fraction[16];
    for (uint32_t i = 0; i < t->inputs; i++) {
        // Below 0 clamps; past 1 extrapolates from the last cell, as vImage does.
        float v = in[i] != in[i] ? 0 : in[i] < 0 ? 0 : in[i];
        float position = v * (float)(t->entries[i] - 1);
        uint32_t cell = position >= (float)(t->entries[i] - 2) ? t->entries[i] - 2 : (uint32_t)position;
        fraction[i] = position - (float)cell;
        base += cell * t->strides[i];
    }
    for (uint32_t c = 0; c < t->outputs; c++) out[c] = 0;
    for (uint32_t corner = 0; corner < (1u << t->inputs); corner++) {
        float w = 1;
        size_t at = base;
        for (uint32_t i = 0; i < t->inputs; i++) {
            if (corner & (1u << i)) { w *= fraction[i]; at += t->strides[i]; }
            else w *= 1 - fraction[i];
        }
        if (w == 0) continue;
        for (uint32_t c = 0; c < t->outputs; c++) out[c] += w * t->values[at * t->outputs + c];
    }
}

vImage_Error vImageMultiDimensionalInterpolatedLookupTable_PlanarF(const vImage_Buffer srcs[], const vImage_Buffer dests[], void *tempBuffer,
                                                                   MultidimensionalTable *table, vImage_InterpolationMethod method,
                                                                   vImage_Flags flags)
    DARWIN_SYMBOL(vImageMultiDimensionalInterpolatedLookupTable_PlanarF);
vImage_Error vImageMultiDimensionalInterpolatedLookupTable_PlanarF(const vImage_Buffer srcs[], const vImage_Buffer dests[], void *tempBuffer,
                                                                   MultidimensionalTable *table, vImage_InterpolationMethod method,
                                                                   vImage_Flags flags) {
    if (!srcs || !dests || !table) return kvImageNullPointerArgument;
    if (method > kvImageHalfInterpolation) return kvImageInvalidParameter;
    if (flags & kvImageGetTempBufferSize) return 0;
    for (uint32_t i = 0; i < table->inputs; i++)
        if (srcs[i].width != srcs[0].width || srcs[i].height != srcs[0].height) return kvImageBufferSizeMismatch;
    for (uint32_t i = 0; i < table->outputs; i++)
        if (dests[i].width != dests[0].width || dests[i].height != dests[0].height) return kvImageBufferSizeMismatch;
    if (dests[0].width > srcs[0].width || dests[0].height > srcs[0].height) return kvImageBufferSizeMismatch;
    float in[16], *out = malloc(sizeof(float) * table->outputs);
    if (!out) return kvImageMemoryAllocationError;
    for (vImagePixelCount y = 0; y < dests[0].height; y++)
        for (vImagePixelCount x = 0; x < dests[0].width; x++) {
            for (uint32_t i = 0; i < table->inputs; i++) in[i] = ((const float *)row(&srcs[i], y))[x];
            md_lookup(table, in, out);
            for (uint32_t c = 0; c < table->outputs; c++) ((float *)mrow(&dests[c], y))[x] = out[c];
        }
    free(out);
    return kvImageNoError;
}

// MARK: - Flood fill

/// Fills the 4- or 8-connected region of pixels equal to the seed with
/// `value`, scanline by scanline from a stack of runs.
static vImage_Error flood_fill(const vImage_Buffer *image, vImagePixelCount seedX, vImagePixelCount seedY, const void *value, size_t bytes,
                               int connectivity, vImage_Flags flags) {
    if (!image || !image->data || !value) return kvImageNullPointerArgument;
    if (connectivity != 4 && connectivity != 8) return kvImageInvalidParameter;
    if (seedX >= image->width) return kvImageInvalidOffset_X;
    if (seedY >= image->height) return kvImageInvalidOffset_Y;
    if (flags & kvImageGetTempBufferSize) return 0;
    uint8_t target[16];
    memcpy(target, vimage_pixel(image, seedX, seedY, bytes), bytes);
    if (!memcmp(target, value, bytes)) return kvImageNoError;
    long W = (long)image->width, H = (long)image->height, reach = connectivity == 8 ? 1 : 0;
    size_t capacity = 256, count = 0;
    long *stack = malloc(sizeof(long) * 2 * capacity);
    if (!stack) return kvImageMemoryAllocationError;
    stack[count * 2] = (long)seedX;
    stack[count * 2 + 1] = (long)seedY;
    count++;
#define MATCHES(px, py) (!memcmp(vimage_pixel(image, (vImagePixelCount)(px), (vImagePixelCount)(py), bytes), target, bytes))
    while (count) {
        count--;
        long x = stack[count * 2], y = stack[count * 2 + 1];
        if (!MATCHES(x, y)) continue;
        long left = x, right = x;
        while (left > 0 && MATCHES(left - 1, y)) left--;
        while (right + 1 < W && MATCHES(right + 1, y)) right++;
        for (long i = left; i <= right; i++) memcpy(vimage_pixel(image, (vImagePixelCount)i, (vImagePixelCount)y, bytes), value, bytes);
        for (int dy = -1; dy <= 1; dy += 2) {
            long ny = y + dy;
            if (ny < 0 || ny >= H) continue;
            long from = left - reach < 0 ? 0 : left - reach, to = right + reach >= W ? W - 1 : right + reach;
            for (long i = from; i <= to; i++) {
                if (!MATCHES(i, ny)) continue;
                if (count == capacity) {
                    long *grown = realloc(stack, sizeof(long) * 4 * capacity);
                    if (!grown) { free(stack); return kvImageMemoryAllocationError; }
                    stack = grown;
                    capacity *= 2;
                }
                stack[count * 2] = i;
                stack[count * 2 + 1] = ny;
                count++;
                while (i + 1 <= to && MATCHES(i + 1, ny)) i++;  // one seed per run
            }
        }
    }
#undef MATCHES
    free(stack);
    return kvImageNoError;
}

vImage_Error vImageFloodFill_Planar8(const vImage_Buffer *srcDest, void *tempBuffer, vImagePixelCount seedX, vImagePixelCount seedY,
                                     Pixel_8 newValue, int connectivity, vImage_Flags flags) DARWIN_SYMBOL(vImageFloodFill_Planar8);
vImage_Error vImageFloodFill_Planar8(const vImage_Buffer *srcDest, void *tempBuffer, vImagePixelCount seedX, vImagePixelCount seedY,
                                     Pixel_8 newValue, int connectivity, vImage_Flags flags) {
    return flood_fill(srcDest, seedX, seedY, &newValue, 1, connectivity, flags);
}

vImage_Error vImageFloodFill_Planar16U(const vImage_Buffer *srcDest, void *tempBuffer, vImagePixelCount seedX, vImagePixelCount seedY,
                                       Pixel_16U newValue, int connectivity, vImage_Flags flags) DARWIN_SYMBOL(vImageFloodFill_Planar16U);
vImage_Error vImageFloodFill_Planar16U(const vImage_Buffer *srcDest, void *tempBuffer, vImagePixelCount seedX, vImagePixelCount seedY,
                                       Pixel_16U newValue, int connectivity, vImage_Flags flags) {
    return flood_fill(srcDest, seedX, seedY, &newValue, 2, connectivity, flags);
}

vImage_Error vImageFloodFill_ARGB8888(const vImage_Buffer *srcDest, void *tempBuffer, vImagePixelCount seedX, vImagePixelCount seedY,
                                      const Pixel_8888 newValue, int connectivity, vImage_Flags flags) DARWIN_SYMBOL(vImageFloodFill_ARGB8888);
vImage_Error vImageFloodFill_ARGB8888(const vImage_Buffer *srcDest, void *tempBuffer, vImagePixelCount seedX, vImagePixelCount seedY,
                                      const Pixel_8888 newValue, int connectivity, vImage_Flags flags) {
    return flood_fill(srcDest, seedX, seedY, newValue, 4, connectivity, flags);
}

vImage_Error vImageFloodFill_ARGB16U(const vImage_Buffer *srcDest, void *tempBuffer, vImagePixelCount seedX, vImagePixelCount seedY,
                                     const Pixel_ARGB_16U newValue, int connectivity, vImage_Flags flags) DARWIN_SYMBOL(vImageFloodFill_ARGB16U);
vImage_Error vImageFloodFill_ARGB16U(const vImage_Buffer *srcDest, void *tempBuffer, vImagePixelCount seedX, vImagePixelCount seedY,
                                     const Pixel_ARGB_16U newValue, int connectivity, vImage_Flags flags) {
    return flood_fill(srcDest, seedX, seedY, newValue, 8, connectivity, flags);
}
