// vImage morphology: dilate and erode with a shaped kernel, and the
// rectangular max and min filters, for Planar8, PlanarF, ARGB8888 and
// ARGBFFFF. Only pixels inside the source take part, so there are no edge
// modes.
//
// Dilate and erode measure the kernel against its center: each source pixel
// under the kernel contributes src - kernel[i][j] + kernel[center], and the
// result is the largest (dilate) or smallest (erode) contribution.

#include "vimage.h"

#include <float.h>

static vImage_Error morphology_check(const vImage_Buffer *src, const vImage_Buffer *dest, vImagePixelCount x, vImagePixelCount y) {
    if (!src || !dest || !src->data || !dest->data) return kvImageNullPointerArgument;
    if (x > src->width) return kvImageInvalidOffset_X;
    if (y > src->height) return kvImageInvalidOffset_Y;
    if (x + dest->width > src->width || y + dest->height > src->height) return kvImageRoiLargerThanInputBuffer;
    return kvImageNoError;
}

/// One output channel of dilate (max) or erode (!max). `kernel` is NULL for
/// the plain rectangular max and min.
#define MORPH_PIXEL(T, kernelT, ACC, INIT, CLAMP) \
    static T morph_##T##_##kernelT(const vImage_Buffer *src, long cx, long cy, int channels, int c, const kernelT *kernel, long kh, \
                                   long kw, int max) { \
        long x0 = cx - kw / 2, y0 = cy - kh / 2; \
        ACC best = max ? -(INIT) : (INIT), center = kernel ? (ACC)kernel[(kh / 2) * kw + kw / 2] : 0; \
        for (long i = 0; i < kh; i++) { \
            long sy = y0 + i; \
            if (sy < 0 || sy >= (long)src->height) continue; \
            const T *row = (const T *)((const uint8_t *)src->data + sy * src->rowBytes); \
            for (long j = 0; j < kw; j++) { \
                long sx = x0 + j; \
                if (sx < 0 || sx >= (long)src->width) continue; \
                ACC v = (ACC)row[sx * channels + c]; \
                if (kernel) v = v - (ACC)kernel[i * kw + j] + center; \
                if (max ? v > best : v < best) best = v; \
            } \
        } \
        return CLAMP(best); \
    }

static inline uint8_t clamp_int8(long v) { return v < 0 ? 0 : v > 255 ? 255 : (uint8_t)v; }
static inline float same_float(float v) { return v; }

MORPH_PIXEL(uint8_t, uint8_t, long, 100000, clamp_int8)
MORPH_PIXEL(float, float, float, FLT_MAX, same_float)

#define MORPH(T, kernelT) \
    static vImage_Error morph_##T##_##kernelT##_image(const vImage_Buffer *src, const vImage_Buffer *dest, vImagePixelCount ox, \
                                                      vImagePixelCount oy, const kernelT *kernel, vImagePixelCount kh, \
                                                      vImagePixelCount kw, vImage_Flags flags, int channels, int max) { \
        if (flags & kvImageGetTempBufferSize) return 0; \
        vImage_Error error = morphology_check(src, dest, ox, oy); \
        if (error) return error; \
        if (!(kh & 1) || !(kw & 1)) return kvImageInvalidKernelSize; \
        int leaveAlpha = kernel && channels == 4 && (flags & kvImageLeaveAlphaUnchanged); /* max and min filter alpha too */ \
        for (vImagePixelCount y = 0; y < dest->height; y++) { \
            T *out = (T *)vimage_pixel(dest, 0, y, 0); \
            for (vImagePixelCount x = 0; x < dest->width; x++) \
                for (int c = 0; c < channels; c++) { \
                    if (c == 0 && leaveAlpha) \
                        out[x * channels] = ((const T *)((const uint8_t *)src->data + (y + oy) * src->rowBytes))[(x + ox) * channels]; \
                    else \
                        out[x * channels + c] = morph_##T##_##kernelT(src, (long)(x + ox), (long)(y + oy), channels, c, kernel, (long)kh, \
                                                                     (long)kw, max); \
                } \
        } \
        return kvImageNoError; \
    }

MORPH(uint8_t, uint8_t)
MORPH(float, float)

#define DILATE_ERODE(name, fn, T, channels, max) \
    vImage_Error name(const vImage_Buffer *src, const vImage_Buffer *dest, vImagePixelCount srcOffsetToROI_X, \
                      vImagePixelCount srcOffsetToROI_Y, const T *kernel, vImagePixelCount kernel_height, vImagePixelCount kernel_width, \
                      vImage_Flags flags) DARWIN_SYMBOL(name); \
    vImage_Error name(const vImage_Buffer *src, const vImage_Buffer *dest, vImagePixelCount srcOffsetToROI_X, \
                      vImagePixelCount srcOffsetToROI_Y, const T *kernel, vImagePixelCount kernel_height, vImagePixelCount kernel_width, \
                      vImage_Flags flags) { \
        if (!kernel) return kvImageNullPointerArgument; \
        return fn(src, dest, srcOffsetToROI_X, srcOffsetToROI_Y, kernel, kernel_height, kernel_width, flags, channels, max); \
    }

DILATE_ERODE(vImageDilate_Planar8, morph_uint8_t_uint8_t_image, unsigned char, 1, 1)
DILATE_ERODE(vImageDilate_ARGB8888, morph_uint8_t_uint8_t_image, unsigned char, 4, 1)
DILATE_ERODE(vImageDilate_PlanarF, morph_float_float_image, float, 1, 1)
DILATE_ERODE(vImageDilate_ARGBFFFF, morph_float_float_image, float, 4, 1)
DILATE_ERODE(vImageErode_Planar8, morph_uint8_t_uint8_t_image, unsigned char, 1, 0)
DILATE_ERODE(vImageErode_ARGB8888, morph_uint8_t_uint8_t_image, unsigned char, 4, 0)
DILATE_ERODE(vImageErode_PlanarF, morph_float_float_image, float, 1, 0)
DILATE_ERODE(vImageErode_ARGBFFFF, morph_float_float_image, float, 4, 0)

#define MAX_MIN(name, fn, T, channels, max) \
    vImage_Error name(const vImage_Buffer *src, const vImage_Buffer *dest, void *tempBuffer, vImagePixelCount srcOffsetToROI_X, \
                      vImagePixelCount srcOffsetToROI_Y, vImagePixelCount kernel_height, vImagePixelCount kernel_width, \
                      vImage_Flags flags) DARWIN_SYMBOL(name); \
    vImage_Error name(const vImage_Buffer *src, const vImage_Buffer *dest, void *tempBuffer, vImagePixelCount srcOffsetToROI_X, \
                      vImagePixelCount srcOffsetToROI_Y, vImagePixelCount kernel_height, vImagePixelCount kernel_width, \
                      vImage_Flags flags) { \
        return fn(src, dest, srcOffsetToROI_X, srcOffsetToROI_Y, NULL, kernel_height, kernel_width, flags, channels, max); \
    }

MAX_MIN(vImageMax_Planar8, morph_uint8_t_uint8_t_image, uint8_t, 1, 1)
MAX_MIN(vImageMax_ARGB8888, morph_uint8_t_uint8_t_image, uint8_t, 4, 1)
MAX_MIN(vImageMax_PlanarF, morph_float_float_image, float, 1, 1)
MAX_MIN(vImageMax_ARGBFFFF, morph_float_float_image, float, 4, 1)
MAX_MIN(vImageMin_Planar8, morph_uint8_t_uint8_t_image, uint8_t, 1, 0)
MAX_MIN(vImageMin_ARGB8888, morph_uint8_t_uint8_t_image, uint8_t, 4, 0)
MAX_MIN(vImageMin_PlanarF, morph_float_float_image, float, 1, 0)
MAX_MIN(vImageMin_ARGBFFFF, morph_float_float_image, float, 4, 0)
