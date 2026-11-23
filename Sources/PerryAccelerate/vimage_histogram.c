// vImage histograms: counting, equalization, specification (matching a
// desired histogram) and contrast stretching for Planar8, PlanarF, ARGB8888
// and ARGBFFFF, plus the 8-bit table lookups Histogram.h declares.
//
// 8-bit histograms have 256 bins. Float ones have histogram_entries bins
// spread over [minVal, maxVal]: a value v falls in bin
// histogram_entries * (v - minVal) / (maxVal - minVal), clipped to the bins.

#include "vimage.h"

#include <math.h>

static vImage_Error same_size(const vImage_Buffer *src, const vImage_Buffer *dest) {
    if (!src || !dest || !src->data || !dest->data) return kvImageNullPointerArgument;
    if (src->width != dest->width || src->height != dest->height) return kvImageBufferSizeMismatch;
    return kvImageNoError;
}

static const uint8_t *row8(const vImage_Buffer *b, vImagePixelCount y) { return (const uint8_t *)b->data + y * b->rowBytes; }
static const float *rowF(const vImage_Buffer *b, vImagePixelCount y) { return (const float *)((const uint8_t *)b->data + y * b->rowBytes); }

static unsigned bin_of(float v, unsigned entries, float minVal, float maxVal) {
    float f = (float)entries * (v - minVal) / (maxVal - minVal);
    if (!(f >= 0)) return 0;  // and NaN
    if (f >= (float)(entries - 1)) return entries - 1;
    return (unsigned)f;
}

/// Counts channel c of `channels`-channel 8-bit pixels.
static void count8(const vImage_Buffer *src, int channels, int c, vImagePixelCount *histogram) {
    memset(histogram, 0, 256 * sizeof(vImagePixelCount));
    for (vImagePixelCount y = 0; y < src->height; y++) {
        const uint8_t *s = row8(src, y);
        for (vImagePixelCount x = 0; x < src->width; x++) histogram[s[x * channels + c]]++;
    }
}

static void countF(const vImage_Buffer *src, int channels, int c, vImagePixelCount *histogram, unsigned entries, float minVal, float maxVal) {
    memset(histogram, 0, entries * sizeof(vImagePixelCount));
    for (vImagePixelCount y = 0; y < src->height; y++) {
        const float *s = rowF(src, y);
        for (vImagePixelCount x = 0; x < src->width; x++) histogram[bin_of(s[x * channels + c], entries, minVal, maxVal)]++;
    }
}

/// Maps channel c through a 256-entry table.
static void apply8(const vImage_Buffer *src, const vImage_Buffer *dest, int channels, int c, const uint8_t *table) {
    for (vImagePixelCount y = 0; y < dest->height; y++) {
        const uint8_t *s = row8(src, y);
        uint8_t *d = (uint8_t *)row8(dest, y);
        for (vImagePixelCount x = 0; x < dest->width; x++) d[x * channels + c] = table ? table[s[x * channels + c]] : s[x * channels + c];
    }
}

/// Maps channel c through a table of float results, one per bin.
static void applyF(const vImage_Buffer *src, const vImage_Buffer *dest, int channels, int c, const float *table, unsigned entries, float minVal,
                   float maxVal) {
    for (vImagePixelCount y = 0; y < dest->height; y++) {
        const float *s = rowF(src, y);
        float *d = (float *)rowF(dest, y);
        for (vImagePixelCount x = 0; x < dest->width; x++)
            d[x * channels + c] = table ? table[bin_of(s[x * channels + c], entries, minVal, maxVal)] : s[x * channels + c];
    }
}

// MARK: - Calculation

vImage_Error vImageHistogramCalculation_Planar8(const vImage_Buffer *src, vImagePixelCount *histogram, vImage_Flags flags)
    DARWIN_SYMBOL(vImageHistogramCalculation_Planar8);
vImage_Error vImageHistogramCalculation_Planar8(const vImage_Buffer *src, vImagePixelCount *histogram, vImage_Flags flags) {
    if (!src || !src->data || !histogram) return kvImageNullPointerArgument;
    count8(src, 1, 0, histogram);
    return kvImageNoError;
}

vImage_Error vImageHistogramCalculation_ARGB8888(const vImage_Buffer *src, vImagePixelCount *histogram[4], vImage_Flags flags)
    DARWIN_SYMBOL(vImageHistogramCalculation_ARGB8888);
vImage_Error vImageHistogramCalculation_ARGB8888(const vImage_Buffer *src, vImagePixelCount *histogram[4], vImage_Flags flags) {
    if (!src || !src->data || !histogram) return kvImageNullPointerArgument;
    for (int c = 0; c < 4; c++) {  // vImage counts alpha even with kvImageLeaveAlphaUnchanged here
        if (!histogram[c]) return kvImageNullPointerArgument;
        count8(src, 4, c, histogram[c]);
    }
    return kvImageNoError;
}

vImage_Error vImageHistogramCalculation_PlanarF(const vImage_Buffer *src, vImagePixelCount *histogram, unsigned int histogram_entries,
                                                Pixel_F minVal, Pixel_F maxVal, vImage_Flags flags)
    DARWIN_SYMBOL(vImageHistogramCalculation_PlanarF);
vImage_Error vImageHistogramCalculation_PlanarF(const vImage_Buffer *src, vImagePixelCount *histogram, unsigned int histogram_entries,
                                                Pixel_F minVal, Pixel_F maxVal, vImage_Flags flags) {
    if (!src || !src->data || !histogram) return kvImageNullPointerArgument;
    if (!histogram_entries || !(maxVal > minVal)) return kvImageInvalidParameter;
    countF(src, 1, 0, histogram, histogram_entries, minVal, maxVal);
    return kvImageNoError;
}

vImage_Error vImageHistogramCalculation_ARGBFFFF(const vImage_Buffer *src, vImagePixelCount *histogram[4], unsigned int histogram_entries,
                                                 Pixel_F minVal, Pixel_F maxVal, vImage_Flags flags)
    DARWIN_SYMBOL(vImageHistogramCalculation_ARGBFFFF);
vImage_Error vImageHistogramCalculation_ARGBFFFF(const vImage_Buffer *src, vImagePixelCount *histogram[4], unsigned int histogram_entries,
                                                 Pixel_F minVal, Pixel_F maxVal, vImage_Flags flags) {
    if (!src || !src->data || !histogram) return kvImageNullPointerArgument;
    if (!histogram_entries || !(maxVal > minVal)) return kvImageInvalidParameter;
    for (int c = (flags & kvImageLeaveAlphaUnchanged) ? 1 : 0; c < 4; c++) {
        if (!histogram[c]) return kvImageNullPointerArgument;
        countF(src, 4, c, histogram[c], histogram_entries, minVal, maxVal);
    }
    return kvImageNoError;
}

// MARK: - Equalization

/// The equalizing table for one 8-bit channel: each level goes to its share
/// of the pixels at or below it, scaled to 0...255 and rounded.
static void equalize8(const vImage_Buffer *src, const vImage_Buffer *dest, int channels, int c) {
    vImagePixelCount histogram[256], total = src->width * src->height, sum = 0;
    uint8_t table[256];
    count8(src, channels, c, histogram);
    for (int v = 0; v < 256; v++) {
        sum += histogram[v];
        table[v] = total ? (uint8_t)((sum * 255 + total / 2) / total) : (uint8_t)v;
    }
    apply8(src, dest, channels, c, table);
}

static vImage_Error equalizeF(const vImage_Buffer *src, const vImage_Buffer *dest, int channels, int c, unsigned entries, float minVal,
                              float maxVal) {
    vImagePixelCount *histogram = malloc(entries * sizeof(vImagePixelCount)), total = src->width * src->height, sum = 0;
    float *table = malloc(entries * sizeof(float));
    if (!histogram || !table) { free(histogram); free(table); return kvImageMemoryAllocationError; }
    countF(src, channels, c, histogram, entries, minVal, maxVal);
    for (unsigned i = 0; i < entries; i++) {
        sum += histogram[i];
        table[i] = minVal + (maxVal - minVal) * (total ? (float)sum / (float)total : 0);
    }
    applyF(src, dest, channels, c, table, entries, minVal, maxVal);
    free(histogram);
    free(table);
    return kvImageNoError;
}

vImage_Error vImageEqualization_Planar8(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags)
    DARWIN_SYMBOL(vImageEqualization_Planar8);
vImage_Error vImageEqualization_Planar8(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags) {
    vImage_Error error = same_size(src, dest);
    if (error) return error;
    if (flags & kvImageLeaveAlphaUnchanged) return kvImageNoError;  // vImage takes the plane for alpha and leaves it
    equalize8(src, dest, 1, 0);
    return kvImageNoError;
}

vImage_Error vImageEqualization_ARGB8888(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags)
    DARWIN_SYMBOL(vImageEqualization_ARGB8888);
vImage_Error vImageEqualization_ARGB8888(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags) {
    vImage_Error error = same_size(src, dest);
    if (error) return error;
    for (int c = 0; c < 4; c++) {
        if (c == 0 && (flags & kvImageLeaveAlphaUnchanged)) apply8(src, dest, 4, 0, NULL);
        else equalize8(src, dest, 4, c);
    }
    return kvImageNoError;
}

#define FLOAT_HISTOGRAM_ARGS \
    const vImage_Buffer *src, const vImage_Buffer *dest, void *tempBuffer, unsigned int histogram_entries, Pixel_F minVal, Pixel_F maxVal, \
        vImage_Flags flags

static vImage_Error float_check(const vImage_Buffer *src, const vImage_Buffer *dest, unsigned entries, float minVal, float maxVal) {
    vImage_Error error = same_size(src, dest);
    if (error) return error;
    if (!entries || !(maxVal > minVal)) return kvImageInvalidParameter;
    return kvImageNoError;
}

vImage_Error vImageEqualization_PlanarF(FLOAT_HISTOGRAM_ARGS) DARWIN_SYMBOL(vImageEqualization_PlanarF);
vImage_Error vImageEqualization_PlanarF(FLOAT_HISTOGRAM_ARGS) {
    if (flags & kvImageGetTempBufferSize) return 0;
    vImage_Error error = float_check(src, dest, histogram_entries, minVal, maxVal);
    if (error) return error;
    return equalizeF(src, dest, 1, 0, histogram_entries, minVal, maxVal);
}

vImage_Error vImageEqualization_ARGBFFFF(FLOAT_HISTOGRAM_ARGS) DARWIN_SYMBOL(vImageEqualization_ARGBFFFF);
vImage_Error vImageEqualization_ARGBFFFF(FLOAT_HISTOGRAM_ARGS) {
    if (flags & kvImageGetTempBufferSize) return 0;
    vImage_Error error = float_check(src, dest, histogram_entries, minVal, maxVal);
    if (error) return error;
    for (int c = 0; c < 4 && !error; c++) {
        if (c == 0 && (flags & kvImageLeaveAlphaUnchanged)) applyF(src, dest, 4, 0, NULL, 0, 0, 0);
        else error = equalizeF(src, dest, 4, c, histogram_entries, minVal, maxVal);
    }
    return error;
}

// MARK: - Specification

/// For each level, the level of `desired` whose cumulative share is nearest
/// the share of source pixels at or below it, the lowest one on a tie. This
/// is what vImage's planar functions do; its four-channel ones sometimes pick
/// a neighboring level.
static void specification_table(const vImagePixelCount *have, const vImagePixelCount *desired, unsigned entries, unsigned *table,
                                double *cumulative) {
    double haveTotal = 0, desiredTotal = 0, sum = 0;
    for (unsigned i = 0; i < entries; i++) { haveTotal += (double)have[i]; desiredTotal += (double)desired[i]; }
    if (desiredTotal == 0) desiredTotal = 1;
    for (unsigned w = 0; w < entries; w++) {
        sum += (double)desired[w];
        cumulative[w] = sum * haveTotal / desiredTotal;  // in source pixels
    }
    double haveSum = 0;
    for (unsigned i = 0; i < entries; i++) {
        haveSum += (double)have[i];
        unsigned lo = 0, hi = entries;  // the first level with cumulative >= haveSum
        while (lo < hi) {
            unsigned mid = (lo + hi) / 2;
            if (cumulative[mid] < haveSum) lo = mid + 1;
            else hi = mid;
        }
        if (lo == entries || (lo > 0 && haveSum - cumulative[lo - 1] <= cumulative[lo] - haveSum)) {
            unsigned below = lo - 1;
            while (below > 0 && cumulative[below - 1] == cumulative[below]) below--;
            lo = below;
        }
        table[i] = lo;
    }
}

static vImage_Error specify8(const vImage_Buffer *src, const vImage_Buffer *dest, int channels, int c, const vImagePixelCount *desired) {
    if (!desired) return kvImageNullPointerArgument;
    vImagePixelCount histogram[256];
    unsigned levels[256];
    double cumulative[256];
    uint8_t table[256];
    count8(src, channels, c, histogram);
    specification_table(histogram, desired, 256, levels, cumulative);
    for (int i = 0; i < 256; i++) table[i] = (uint8_t)levels[i];
    apply8(src, dest, channels, c, table);
    return kvImageNoError;
}

static vImage_Error specifyF(const vImage_Buffer *src, const vImage_Buffer *dest, int channels, int c, const vImagePixelCount *desired,
                             unsigned entries, float minVal, float maxVal) {
    if (!desired) return kvImageNullPointerArgument;
    vImagePixelCount *histogram = malloc(entries * sizeof(vImagePixelCount));
    unsigned *levels = malloc(entries * sizeof(unsigned));
    float *table = malloc(entries * sizeof(float));
    double *cumulative = malloc(entries * sizeof(double));
    if (!histogram || !levels || !table || !cumulative) {
        free(histogram); free(levels); free(table); free(cumulative);
        return kvImageMemoryAllocationError;
    }
    countF(src, channels, c, histogram, entries, minVal, maxVal);
    specification_table(histogram, desired, entries, levels, cumulative);
    for (unsigned i = 0; i < entries; i++)
        table[i] = entries > 1 ? minVal + (maxVal - minVal) * (float)levels[i] / (float)(entries - 1) : minVal;
    applyF(src, dest, channels, c, table, entries, minVal, maxVal);
    free(histogram);
    free(levels);
    free(table);
    free(cumulative);
    return kvImageNoError;
}

vImage_Error vImageHistogramSpecification_Planar8(const vImage_Buffer *src, const vImage_Buffer *dest, const vImagePixelCount *desired_histogram,
                                                  vImage_Flags flags) DARWIN_SYMBOL(vImageHistogramSpecification_Planar8);
vImage_Error vImageHistogramSpecification_Planar8(const vImage_Buffer *src, const vImage_Buffer *dest, const vImagePixelCount *desired_histogram,
                                                  vImage_Flags flags) {
    if (flags & kvImageLeaveAlphaUnchanged) return kvImageUnknownFlagsBit;
    vImage_Error error = same_size(src, dest);
    if (error) return error;
    return specify8(src, dest, 1, 0, desired_histogram);
}

vImage_Error vImageHistogramSpecification_ARGB8888(const vImage_Buffer *src, const vImage_Buffer *dest,
                                                   const vImagePixelCount *desired_histogram[4], vImage_Flags flags)
    DARWIN_SYMBOL(vImageHistogramSpecification_ARGB8888);
vImage_Error vImageHistogramSpecification_ARGB8888(const vImage_Buffer *src, const vImage_Buffer *dest,
                                                   const vImagePixelCount *desired_histogram[4], vImage_Flags flags) {
    vImage_Error error = same_size(src, dest);
    if (error) return error;
    if (!desired_histogram) return kvImageNullPointerArgument;
    for (int c = 0; c < 4 && !error; c++) {
        if (c == 0 && (flags & kvImageLeaveAlphaUnchanged)) apply8(src, dest, 4, 0, NULL);
        else error = specify8(src, dest, 4, c, desired_histogram[c]);
    }
    return error;
}

vImage_Error vImageHistogramSpecification_PlanarF(const vImage_Buffer *src, const vImage_Buffer *dest, void *tempBuffer,
                                                  const vImagePixelCount *desired_histogram, unsigned int histogram_entries, Pixel_F minVal,
                                                  Pixel_F maxVal, vImage_Flags flags) DARWIN_SYMBOL(vImageHistogramSpecification_PlanarF);
vImage_Error vImageHistogramSpecification_PlanarF(const vImage_Buffer *src, const vImage_Buffer *dest, void *tempBuffer,
                                                  const vImagePixelCount *desired_histogram, unsigned int histogram_entries, Pixel_F minVal,
                                                  Pixel_F maxVal, vImage_Flags flags) {
    if (flags & kvImageGetTempBufferSize) return 0;
    vImage_Error error = float_check(src, dest, histogram_entries, minVal, maxVal);
    if (error) return error;
    return specifyF(src, dest, 1, 0, desired_histogram, histogram_entries, minVal, maxVal);
}

vImage_Error vImageHistogramSpecification_ARGBFFFF(const vImage_Buffer *src, const vImage_Buffer *dest, void *tempBuffer,
                                                   const vImagePixelCount *desired_histogram[4], unsigned int histogram_entries,
                                                   Pixel_F minVal, Pixel_F maxVal, vImage_Flags flags)
    DARWIN_SYMBOL(vImageHistogramSpecification_ARGBFFFF);
vImage_Error vImageHistogramSpecification_ARGBFFFF(const vImage_Buffer *src, const vImage_Buffer *dest, void *tempBuffer,
                                                   const vImagePixelCount *desired_histogram[4], unsigned int histogram_entries,
                                                   Pixel_F minVal, Pixel_F maxVal, vImage_Flags flags) {
    if (flags & kvImageGetTempBufferSize) return 0;
    vImage_Error error = float_check(src, dest, histogram_entries, minVal, maxVal);
    if (error) return error;
    if (!desired_histogram) return kvImageNullPointerArgument;
    for (int c = 0; c < 4 && !error; c++) {
        if (c == 0 && (flags & kvImageLeaveAlphaUnchanged)) applyF(src, dest, 4, 0, NULL, 0, 0, 0);
        else error = specifyF(src, dest, 4, c, desired_histogram[c], histogram_entries, minVal, maxVal);
    }
    return error;
}

// MARK: - Contrast stretch

/// Stretches the levels an 8-bit channel uses to 0...255, rounding.
static void stretch8(const vImage_Buffer *src, const vImage_Buffer *dest, int channels, int c) {
    vImagePixelCount histogram[256];
    uint8_t table[256];
    count8(src, channels, c, histogram);
    int lo = 0, hi = 255;
    while (lo < 255 && !histogram[lo]) lo++;
    while (hi > 0 && !histogram[hi]) hi--;
    for (int v = 0; v < 256; v++) {
        if (hi <= lo) table[v] = (uint8_t)v;
        else {
            int t = v < lo ? 0 : v > hi ? hi - lo : v - lo;
            table[v] = (uint8_t)(t * 255 / (hi - lo));  // rounded down, as vImage does
        }
    }
    apply8(src, dest, channels, c, table);
}

/// Stretches the values a float channel holds, from its smallest to its
/// largest, linearly over [minVal, maxVal].
static vImage_Error stretchF(const vImage_Buffer *src, const vImage_Buffer *dest, int channels, int c, unsigned entries, float minVal,
                             float maxVal) {
    float lo = INFINITY, hi = -INFINITY;
    for (vImagePixelCount y = 0; y < src->height; y++) {
        const float *s = rowF(src, y);
        for (vImagePixelCount x = 0; x < src->width; x++) {
            float v = s[x * channels + c];
            if (v < lo) lo = v;
            if (v > hi) hi = v;
        }
    }
    float scale = hi > lo ? (maxVal - minVal) / (hi - lo) : 0;
    for (vImagePixelCount y = 0; y < dest->height; y++) {
        const float *s = rowF(src, y);
        float *d = (float *)rowF(dest, y);
        for (vImagePixelCount x = 0; x < dest->width; x++) d[x * channels + c] = (s[x * channels + c] - lo) * scale + minVal;
    }
    return kvImageNoError;
}

vImage_Error vImageContrastStretch_Planar8(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags)
    DARWIN_SYMBOL(vImageContrastStretch_Planar8);
vImage_Error vImageContrastStretch_Planar8(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags) {
    if (flags & kvImageLeaveAlphaUnchanged) return kvImageUnknownFlagsBit;
    vImage_Error error = same_size(src, dest);
    if (error) return error;
    stretch8(src, dest, 1, 0);
    return kvImageNoError;
}

vImage_Error vImageContrastStretch_ARGB8888(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags)
    DARWIN_SYMBOL(vImageContrastStretch_ARGB8888);
vImage_Error vImageContrastStretch_ARGB8888(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags) {
    vImage_Error error = same_size(src, dest);
    if (error) return error;
    for (int c = 0; c < 4; c++) {
        if (c == 0 && (flags & kvImageLeaveAlphaUnchanged)) apply8(src, dest, 4, 0, NULL);
        else stretch8(src, dest, 4, c);
    }
    return kvImageNoError;
}

vImage_Error vImageContrastStretch_PlanarF(FLOAT_HISTOGRAM_ARGS) DARWIN_SYMBOL(vImageContrastStretch_PlanarF);
vImage_Error vImageContrastStretch_PlanarF(FLOAT_HISTOGRAM_ARGS) {
    if (flags & kvImageGetTempBufferSize) return 0;
    vImage_Error error = float_check(src, dest, histogram_entries, minVal, maxVal);
    if (error) return error;
    return stretchF(src, dest, 1, 0, histogram_entries, minVal, maxVal);
}

vImage_Error vImageContrastStretch_ARGBFFFF(FLOAT_HISTOGRAM_ARGS) DARWIN_SYMBOL(vImageContrastStretch_ARGBFFFF);
vImage_Error vImageContrastStretch_ARGBFFFF(FLOAT_HISTOGRAM_ARGS) {
    if (flags & kvImageGetTempBufferSize) return 0;
    vImage_Error error = float_check(src, dest, histogram_entries, minVal, maxVal);
    if (error) return error;
    for (int c = 0; c < 4 && !error; c++) {
        if (c == 0 && (flags & kvImageLeaveAlphaUnchanged)) applyF(src, dest, 4, 0, NULL, 0, 0, 0);
        else error = stretchF(src, dest, 4, c, histogram_entries, minVal, maxVal);
    }
    return error;
}

// MARK: - Table lookups

vImage_Error vImageTableLookUp_Planar8(const vImage_Buffer *src, const vImage_Buffer *dest, const Pixel_8 table[256], vImage_Flags flags)
    DARWIN_SYMBOL(vImageTableLookUp_Planar8);
vImage_Error vImageTableLookUp_Planar8(const vImage_Buffer *src, const vImage_Buffer *dest, const Pixel_8 table[256], vImage_Flags flags) {
    if (flags & kvImageLeaveAlphaUnchanged) return kvImageUnknownFlagsBit;
    vImage_Error error = same_size(src, dest);
    if (error) return error;
    if (!table) return kvImageNullPointerArgument;
    apply8(src, dest, 1, 0, table);
    return kvImageNoError;
}

/// A NULL table leaves its channel as it was.
vImage_Error vImageTableLookUp_ARGB8888(const vImage_Buffer *src, const vImage_Buffer *dest, const Pixel_8 alphaTable[256],
                                        const Pixel_8 redTable[256], const Pixel_8 greenTable[256], const Pixel_8 blueTable[256],
                                        vImage_Flags flags) DARWIN_SYMBOL(vImageTableLookUp_ARGB8888);
vImage_Error vImageTableLookUp_ARGB8888(const vImage_Buffer *src, const vImage_Buffer *dest, const Pixel_8 alphaTable[256],
                                        const Pixel_8 redTable[256], const Pixel_8 greenTable[256], const Pixel_8 blueTable[256],
                                        vImage_Flags flags) {
    if (flags & kvImageLeaveAlphaUnchanged) return kvImageUnknownFlagsBit;
    vImage_Error error = same_size(src, dest);
    if (error) return error;
    const Pixel_8 *tables[4] = {alphaTable, redTable, greenTable, blueTable};
    for (int c = 0; c < 4; c++) apply8(src, dest, 4, c, tables[c]);
    return kvImageNoError;
}

vImage_Error vImageInterpolatedLookupTable_PlanarF(const vImage_Buffer *src, const vImage_Buffer *dest, const Pixel_F *table,
                                                   vImagePixelCount tableEntries, float maxFloat, float minFloat, vImage_Flags flags)
    DARWIN_SYMBOL(vImageInterpolatedLookupTable_PlanarF);
vImage_Error vImageInterpolatedLookupTable_PlanarF(const vImage_Buffer *src, const vImage_Buffer *dest, const Pixel_F *table,
                                                   vImagePixelCount tableEntries, float maxFloat, float minFloat, vImage_Flags flags) {
    if (flags & kvImageLeaveAlphaUnchanged) return kvImageUnknownFlagsBit;
    vImage_Error error = same_size(src, dest);
    if (error) return error;
    if (!table) return kvImageNullPointerArgument;
    if (!tableEntries || !(maxFloat > minFloat)) return kvImageInvalidParameter;
    float scale = (float)(tableEntries - 1) / (maxFloat - minFloat);
    for (vImagePixelCount y = 0; y < dest->height; y++) {
        const float *s = rowF(src, y);
        float *d = (float *)rowF(dest, y);
        for (vImagePixelCount x = 0; x < dest->width; x++) {
            float v = s[x];
            if (v != v) { d[x] = v; continue; }
            v = v > maxFloat ? maxFloat : v < minFloat ? minFloat : v;
            float f = (v - minFloat) * scale;
            vImagePixelCount i = (vImagePixelCount)f;
            float fraction = f - (float)i;
            // The table holds tableEntries + 1 values, so i + 1 is always there.
            d[x] = table[i] * (1.0f - fraction) + table[i + 1] * fraction;
        }
    }
    return kvImageNoError;
}
