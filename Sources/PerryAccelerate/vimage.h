#ifndef PERRY_VIMAGE_H
#define PERRY_VIMAGE_H

// vImage's types, error codes and flags, with Darwin's layouts, and the
// helpers the vImage files share.

#include "PerryAccelerate.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef unsigned long vImagePixelCount;
typedef long vImage_Error;
typedef uint32_t vImage_Flags;

typedef struct vImage_Buffer {
    void *data;
    vImagePixelCount height;
    vImagePixelCount width;
    size_t rowBytes;
} vImage_Buffer;

typedef struct vImage_AffineTransform { float a, b, c, d, tx, ty; } vImage_AffineTransform;
typedef struct vImage_AffineTransform_Double { double a, b, c, d, tx, ty; } vImage_AffineTransform_Double;
typedef vImage_AffineTransform_Double vImage_CGAffineTransform;
typedef struct vImage_PerpsectiveTransform { float a, b, c, d, tx, ty, vx, vy, v; } vImage_PerpsectiveTransform;
typedef int32_t vImage_WarpInterpolation;
enum { kvImageInterpolationNearest = 0, kvImageInterpolationLinear = 1 };

typedef uint8_t Pixel_8;
typedef float Pixel_F;
typedef uint8_t Pixel_88[2];
typedef uint8_t Pixel_8888[4];
typedef float Pixel_FFFF[4];
typedef uint16_t Pixel_16U;
typedef int16_t Pixel_16S;
typedef int16_t Pixel_16Q12;
typedef uint16_t Pixel_16U16U[2];
typedef int16_t Pixel_16S16S[2];
typedef uint32_t Pixel_32U;
typedef uint16_t Pixel_ARGB_16U[4];
typedef int16_t Pixel_ARGB_16S[4];
typedef uint16_t Pixel_16F;
typedef uint16_t Pixel_16F16F[2];
typedef uint16_t Pixel_ARGB_16F[4];
typedef float Pixel_FF[2];

typedef void *ResamplingFilter;
typedef void *GammaFunction;

enum {
    kvImageNoError = 0,
    kvImageRoiLargerThanInputBuffer = -21766,
    kvImageInvalidKernelSize = -21767,
    kvImageInvalidEdgeStyle = -21768,
    kvImageInvalidOffset_X = -21769,
    kvImageInvalidOffset_Y = -21770,
    kvImageMemoryAllocationError = -21771,
    kvImageNullPointerArgument = -21772,
    kvImageInvalidParameter = -21773,
    kvImageBufferSizeMismatch = -21774,
    kvImageUnknownFlagsBit = -21775,
    kvImageInternalError = -21776,
    kvImageInvalidRowBytes = -21777,
    kvImageInvalidImageFormat = -21778,
    kvImageColorSyncIsAbsent = -21779,
    kvImageOutOfPlaceOperationRequired = -21780,
    kvImageInvalidImageObject = -21781,
    kvImageInvalidCVImageFormat = -21782,
    kvImageUnsupportedConversion = -21783,
    kvImageCoreVideoIsAbsent = -21784,
};

enum {
    kvImageNoFlags = 0,
    kvImageLeaveAlphaUnchanged = 1,
    kvImageCopyInPlace = 2,
    kvImageBackgroundColorFill = 4,
    kvImageEdgeExtend = 8,
    kvImageDoNotTile = 16,
    kvImageHighQualityResampling = 32,
    kvImageTruncateKernel = 64,
    kvImageGetTempBufferSize = 128,
    kvImagePrintDiagnosticsToConsole = 256,
    kvImageNoAllocate = 512,
    kvImageHDRContent = 1024,
    kvImageDoNotClamp = 2048,
    kvImageUseFP16Accumulator = 4096,
};

/// The byte at pixel (x, y) of `bytes`-byte pixels.
static inline uint8_t *vimage_pixel(const vImage_Buffer *b, vImagePixelCount x, vImagePixelCount y, size_t bytes) {
    return (uint8_t *)b->data + y * b->rowBytes + x * bytes;
}

/// The usual check: both buffers present and dest no larger than src.
static inline vImage_Error vimage_check(const vImage_Buffer *src, const vImage_Buffer *dest) {
    if (!src || !dest || !src->data || !dest->data) return kvImageNullPointerArgument;
    if (dest->width > src->width || dest->height > src->height) return kvImageRoiLargerThanInputBuffer;
    return kvImageNoError;
}

static inline uint8_t vimage_clamp8(float v) { return v <= 0 ? 0 : v >= 255 ? 255 : (uint8_t)(v + 0.5f); }
static inline uint16_t vimage_clamp16(float v) { return v <= 0 ? 0 : v >= 65535 ? 65535 : (uint16_t)(v + 0.5f); }

/// (a * b + 127) / 255, rounded as vImage rounds 8-bit products.
static inline uint8_t vimage_mul8(unsigned a, unsigned b) { unsigned t = a * b + 128; return (uint8_t)((t + (t >> 8)) >> 8); }

/// IEEE half precision to single, for the 16F formats.
static inline float vimage_half_to_float(uint16_t h) {
    uint32_t sign = (uint32_t)(h & 0x8000) << 16, exponent = (h >> 10) & 0x1f, mantissa = h & 0x3ff, bits;
    if (exponent == 0x1f) bits = sign | 0x7f800000 | (mantissa << 13);
    else if (exponent) bits = sign | ((exponent + 112) << 23) | (mantissa << 13);
    else if (!mantissa) bits = sign;
    else {
        exponent = 113;
        while (!(mantissa & 0x400)) { mantissa <<= 1; exponent--; }
        bits = sign | (exponent << 23) | ((mantissa & 0x3ff) << 13);
    }
    float f;
    memcpy(&f, &bits, 4);
    return f;
}

/// Single to IEEE half precision, rounding to nearest even.
static inline uint16_t vimage_float_to_half(float f) {
    uint32_t bits;
    memcpy(&bits, &f, 4);
    uint32_t sign = (bits >> 16) & 0x8000, magnitude = bits & 0x7fffffff;
    if (magnitude >= 0x7f800000) return (uint16_t)(sign | 0x7c00 | (magnitude > 0x7f800000 ? 0x200 | ((magnitude >> 13) & 0x3ff) : 0));
    if (magnitude >= 0x477ff000) return (uint16_t)(sign | 0x7c00);  // rounds past the largest half
    if (magnitude < 0x38800000) {                                    // a subnormal half, or zero
        if (magnitude < 0x33000000) return (uint16_t)sign;
        uint32_t shift = 126 - (magnitude >> 23), mantissa = (magnitude & 0x7fffff) | 0x800000;
        uint32_t half = mantissa >> shift, rest = mantissa & ((1u << shift) - 1), mid = 1u << (shift - 1);
        if (rest > mid || (rest == mid && (half & 1))) half++;
        return (uint16_t)(sign | half);
    }
    uint32_t half = ((magnitude - 0x38000000) >> 13), rest = magnitude & 0x1fff;
    if (rest > 0x1000 || (rest == 0x1000 && (half & 1))) half++;
    return (uint16_t)(sign | half);
}

#endif
