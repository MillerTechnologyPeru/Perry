// vImage: buffers and 8-bit-per-channel operations: channel permutes and
// conversions between ARGB, RGBA and RGB, copying, reflection, rotation by
// quarter turns, premultiplying, and scaling by area averaging.

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

enum {
    kvImageNoError = 0,
    kvImageRoiLargerThanInputBuffer = -21766,
    kvImageInvalidParameter = -21773,
    kvImageMemoryAllocationError = -21771,
    kvImageBufferSizeMismatch = -21772,
    kvImageNoAllocate = 0x200,
};

static uint8_t *pixel(const vImage_Buffer *b, vImagePixelCount x, vImagePixelCount y, int bytes) {
    return (uint8_t *)b->data + y * b->rowBytes + x * (vImagePixelCount)bytes;
}

static vImage_Error check(const vImage_Buffer *src, const vImage_Buffer *dest) {
    if (!src || !dest || !src->data || !dest->data) return kvImageInvalidParameter;
    if (dest->width > src->width || dest->height > src->height) return kvImageRoiLargerThanInputBuffer;
    return kvImageNoError;
}

/// Rows padded to 16 bytes, as vImage chooses.
vImage_Error vImageBuffer_Init(vImage_Buffer *buffer, vImagePixelCount height, vImagePixelCount width, uint32_t bitsPerPixel,
                               vImage_Flags flags) DARWIN_SYMBOL(vImageBuffer_Init);
vImage_Error vImageBuffer_Init(vImage_Buffer *buffer, vImagePixelCount height, vImagePixelCount width, uint32_t bitsPerPixel,
                               vImage_Flags flags) {
    if (!buffer || bitsPerPixel == 0) return kvImageInvalidParameter;
    size_t row = (width * bitsPerPixel + 7) / 8;
    row = (row + 15) / 16 * 16;
    buffer->height = height;
    buffer->width = width;
    buffer->rowBytes = row;
    if (flags & kvImageNoAllocate) return (vImage_Error)(row * height);
    buffer->data = malloc(row * height ? row * height : 1);
    return buffer->data ? kvImageNoError : kvImageMemoryAllocationError;
}

vImage_Error vImageCopyBuffer(const vImage_Buffer *src, const vImage_Buffer *dest, size_t pixelSize, vImage_Flags flags)
    DARWIN_SYMBOL(vImageCopyBuffer);
vImage_Error vImageCopyBuffer(const vImage_Buffer *src, const vImage_Buffer *dest, size_t pixelSize, vImage_Flags flags) {
    vImage_Error error = check(src, dest);
    if (error) return error;
    for (vImagePixelCount y = 0; y < dest->height; y++)
        memmove(pixel(dest, 0, y, 0), pixel(src, 0, y, 0), dest->width * pixelSize);
    return kvImageNoError;
}

/// dest channel i takes source channel map[i].
static vImage_Error permute(const vImage_Buffer *src, const vImage_Buffer *dest, const uint8_t map[4]) {
    vImage_Error error = check(src, dest);
    if (error) return error;
    for (vImagePixelCount y = 0; y < dest->height; y++)
        for (vImagePixelCount x = 0; x < dest->width; x++) {
            uint8_t *s = pixel(src, x, y, 4), *d = pixel(dest, x, y, 4);
            uint8_t p[4] = {s[map[0]], s[map[1]], s[map[2]], s[map[3]]};
            memcpy(d, p, 4);
        }
    return kvImageNoError;
}

#define PERMUTE(name) \
    vImage_Error vImagePermuteChannels_##name(const vImage_Buffer *src, const vImage_Buffer *dest, const uint8_t map[4], \
                                               vImage_Flags flags) DARWIN_SYMBOL(vImagePermuteChannels_##name); \
    vImage_Error vImagePermuteChannels_##name(const vImage_Buffer *src, const vImage_Buffer *dest, const uint8_t map[4], \
                                               vImage_Flags flags) { return permute(src, dest, map); }

PERMUTE(ARGB8888)
PERMUTE(RGB888)

/// Four channels to three, dropping `skip` (0 or 3).
static vImage_Error drop(const vImage_Buffer *src, const vImage_Buffer *dest, int skip, int reverse) {
    vImage_Error error = check(src, dest);
    if (error) return error;
    for (vImagePixelCount y = 0; y < dest->height; y++)
        for (vImagePixelCount x = 0; x < dest->width; x++) {
            uint8_t *s = pixel(src, x, y, 4), *d = pixel(dest, x, y, 3);
            const uint8_t *c = s + (skip == 0 ? 1 : 0);
            if (reverse) { d[0] = c[2]; d[1] = c[1]; d[2] = c[0]; }
            else { d[0] = c[0]; d[1] = c[1]; d[2] = c[2]; }
        }
    return kvImageNoError;
}

/// Three channels to four, adding alpha at `at` (0 or 3).
static vImage_Error add(const vImage_Buffer *alphaBuffer, uint8_t alpha, const vImage_Buffer *src, const vImage_Buffer *dest, int at) {
    vImage_Error error = check(src, dest);
    if (error) return error;
    for (vImagePixelCount y = 0; y < dest->height; y++)
        for (vImagePixelCount x = 0; x < dest->width; x++) {
            uint8_t *s = pixel(src, x, y, 3), *d = pixel(dest, x, y, 4);
            uint8_t a = alphaBuffer ? *pixel(alphaBuffer, x, y, 1) : alpha;
            uint8_t c[3] = {s[0], s[1], s[2]};
            if (at == 0) { d[0] = a; memcpy(d + 1, c, 3); } else { memcpy(d, c, 3); d[3] = a; }
        }
    return kvImageNoError;
}

vImage_Error vImageConvert_ARGB8888toRGB888(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags)
    DARWIN_SYMBOL(vImageConvert_ARGB8888toRGB888);
vImage_Error vImageConvert_ARGB8888toRGB888(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags) {
    return drop(src, dest, 0, 0);
}

vImage_Error vImageConvert_RGBA8888toRGB888(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags)
    DARWIN_SYMBOL(vImageConvert_RGBA8888toRGB888);
vImage_Error vImageConvert_RGBA8888toRGB888(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags) {
    return drop(src, dest, 3, 0);
}

vImage_Error vImageConvert_BGRA8888toRGB888(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags)
    DARWIN_SYMBOL(vImageConvert_BGRA8888toRGB888);
vImage_Error vImageConvert_BGRA8888toRGB888(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags) {
    return drop(src, dest, 3, 1);
}

vImage_Error vImageConvert_RGB888toARGB8888(const vImage_Buffer *src, const vImage_Buffer *alphaBuffer, uint8_t alpha,
                                            const vImage_Buffer *dest, int premultiply, vImage_Flags flags)
    DARWIN_SYMBOL(vImageConvert_RGB888toARGB8888);
vImage_Error vImageConvert_RGB888toARGB8888(const vImage_Buffer *src, const vImage_Buffer *alphaBuffer, uint8_t alpha,
                                            const vImage_Buffer *dest, int premultiply, vImage_Flags flags) {
    return add(alphaBuffer, alpha, src, dest, 0);
}

vImage_Error vImageConvert_RGB888toRGBA8888(const vImage_Buffer *src, const vImage_Buffer *alphaBuffer, uint8_t alpha,
                                            const vImage_Buffer *dest, int premultiply, vImage_Flags flags)
    DARWIN_SYMBOL(vImageConvert_RGB888toRGBA8888);
vImage_Error vImageConvert_RGB888toRGBA8888(const vImage_Buffer *src, const vImage_Buffer *alphaBuffer, uint8_t alpha,
                                            const vImage_Buffer *dest, int premultiply, vImage_Flags flags) {
    return add(alphaBuffer, alpha, src, dest, 3);
}

vImage_Error vImageOverwriteChannelsWithScalar_ARGB8888(uint8_t scalar, const vImage_Buffer *src, const vImage_Buffer *dest,
                                                        uint8_t copyMask, vImage_Flags flags)
    DARWIN_SYMBOL(vImageOverwriteChannelsWithScalar_ARGB8888);
vImage_Error vImageOverwriteChannelsWithScalar_ARGB8888(uint8_t scalar, const vImage_Buffer *src, const vImage_Buffer *dest,
                                                        uint8_t copyMask, vImage_Flags flags) {
    vImage_Error error = check(src, dest);
    if (error) return error;
    for (vImagePixelCount y = 0; y < dest->height; y++)
        for (vImagePixelCount x = 0; x < dest->width; x++) {
            uint8_t *s = pixel(src, x, y, 4), *d = pixel(dest, x, y, 4);
            for (int c = 0; c < 4; c++) d[c] = (copyMask & (8 >> c)) ? scalar : s[c];
        }
    return kvImageNoError;
}

/// Premultiplies or unpremultiplies with alpha at `alpha` (0 or 3).
static vImage_Error premultiply(const vImage_Buffer *src, const vImage_Buffer *dest, int alpha, int forward) {
    vImage_Error error = check(src, dest);
    if (error) return error;
    for (vImagePixelCount y = 0; y < dest->height; y++)
        for (vImagePixelCount x = 0; x < dest->width; x++) {
            uint8_t *s = pixel(src, x, y, 4), *d = pixel(dest, x, y, 4);
            int a = s[alpha];
            for (int c = 0; c < 4; c++) {
                if (c == alpha) { d[c] = (uint8_t)a; continue; }
                if (forward) d[c] = (uint8_t)((s[c] * a + 127) / 255);
                else d[c] = a ? (uint8_t)((s[c] * 255 + a / 2) / a > 255 ? 255 : (s[c] * 255 + a / 2) / a) : 0;
            }
        }
    return kvImageNoError;
}

#define PREMULTIPLY(format, alpha) \
    vImage_Error vImagePremultiplyData_##format(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags) \
        DARWIN_SYMBOL(vImagePremultiplyData_##format); \
    vImage_Error vImagePremultiplyData_##format(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags) { \
        return premultiply(src, dest, alpha, 1); \
    } \
    vImage_Error vImageUnpremultiplyData_##format(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags) \
        DARWIN_SYMBOL(vImageUnpremultiplyData_##format); \
    vImage_Error vImageUnpremultiplyData_##format(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags) { \
        return premultiply(src, dest, alpha, 0); \
    }

PREMULTIPLY(ARGB8888, 0)
PREMULTIPLY(RGBA8888, 3)
PREMULTIPLY(BGRA8888, 3)

/// Reflections and quarter-turn rotations of four-byte pixels.
static vImage_Error remap(const vImage_Buffer *src, const vImage_Buffer *dest, int mode) {
    if (!src || !dest || !src->data || !dest->data) return kvImageInvalidParameter;
    for (vImagePixelCount y = 0; y < dest->height; y++)
        for (vImagePixelCount x = 0; x < dest->width; x++) {
            vImagePixelCount sx = x, sy = y;
            switch (mode) {
            case 0: sx = src->width - 1 - x; break;                       // horizontal reflection
            case 1: sy = src->height - 1 - y; break;                      // vertical reflection
            case 2: sx = src->width - 1 - y; sy = x; break;               // a quarter turn counterclockwise
            case 3: sx = src->width - 1 - x; sy = src->height - 1 - y; break;
            case 4: sx = y; sy = src->height - 1 - x; break;              // a quarter turn clockwise
            }
            if (sx >= src->width || sy >= src->height) continue;
            memcpy(pixel(dest, x, y, 4), pixel(src, sx, sy, 4), 4);
        }
    return kvImageNoError;
}

vImage_Error vImageHorizontalReflect_ARGB8888(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags)
    DARWIN_SYMBOL(vImageHorizontalReflect_ARGB8888);
vImage_Error vImageHorizontalReflect_ARGB8888(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags) { return remap(src, dest, 0); }

vImage_Error vImageVerticalReflect_ARGB8888(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags)
    DARWIN_SYMBOL(vImageVerticalReflect_ARGB8888);
vImage_Error vImageVerticalReflect_ARGB8888(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags) { return remap(src, dest, 1); }

/// kRotate0DegreesClockwise 0, 90 1, 180 2, 270 3.
vImage_Error vImageRotate90_ARGB8888(const vImage_Buffer *src, const vImage_Buffer *dest, uint8_t rotation, const uint8_t background[4],
                                     vImage_Flags flags) DARWIN_SYMBOL(vImageRotate90_ARGB8888);
vImage_Error vImageRotate90_ARGB8888(const vImage_Buffer *src, const vImage_Buffer *dest, uint8_t rotation, const uint8_t background[4],
                                     vImage_Flags flags) {
    switch (rotation & 3) {
    case 0: return vImageCopyBuffer(src, dest, 4, flags);
    case 1: return remap(src, dest, 4);
    case 2: return remap(src, dest, 3);
    default: return remap(src, dest, 2);
    }
}

/// Area averaging when shrinking, nearest pixel when growing.
static vImage_Error scale(const vImage_Buffer *src, const vImage_Buffer *dest, int channels) {
    if (!src || !dest || !src->data || !dest->data || !src->width || !src->height) return kvImageInvalidParameter;
    double sx = (double)src->width / dest->width, sy = (double)src->height / dest->height;
    for (vImagePixelCount y = 0; y < dest->height; y++)
        for (vImagePixelCount x = 0; x < dest->width; x++) {
            vImagePixelCount x0 = (vImagePixelCount)(x * sx), y0 = (vImagePixelCount)(y * sy);
            vImagePixelCount x1 = (vImagePixelCount)((x + 1) * sx + 0.999999), y1 = (vImagePixelCount)((y + 1) * sy + 0.999999);
            if (x1 <= x0) x1 = x0 + 1;
            if (y1 <= y0) y1 = y0 + 1;
            if (x1 > src->width) x1 = src->width;
            if (y1 > src->height) y1 = src->height;
            unsigned sums[4] = {0}, count = 0;
            for (vImagePixelCount yy = y0; yy < y1; yy++)
                for (vImagePixelCount xx = x0; xx < x1; xx++, count++)
                    for (int c = 0; c < channels; c++) sums[c] += pixel(src, xx, yy, channels)[c];
            uint8_t *d = pixel(dest, x, y, channels);
            for (int c = 0; c < channels; c++) d[c] = (uint8_t)((sums[c] + count / 2) / (count ? count : 1));
        }
    return kvImageNoError;
}

vImage_Error vImageScale_ARGB8888(const vImage_Buffer *src, const vImage_Buffer *dest, void *temp, vImage_Flags flags)
    DARWIN_SYMBOL(vImageScale_ARGB8888);
vImage_Error vImageScale_ARGB8888(const vImage_Buffer *src, const vImage_Buffer *dest, void *temp, vImage_Flags flags) {
    return scale(src, dest, 4);
}

vImage_Error vImageScale_Planar8(const vImage_Buffer *src, const vImage_Buffer *dest, void *temp, vImage_Flags flags)
    DARWIN_SYMBOL(vImageScale_Planar8);
vImage_Error vImageScale_Planar8(const vImage_Buffer *src, const vImage_Buffer *dest, void *temp, vImage_Flags flags) {
    return scale(src, dest, 1);
}

vImage_Error vImageScale_RGB888(const vImage_Buffer *src, const vImage_Buffer *dest, void *temp, vImage_Flags flags)
    DARWIN_SYMBOL(vImageScale_RGB888);
vImage_Error vImageScale_RGB888(const vImage_Buffer *src, const vImage_Buffer *dest, void *temp, vImage_Flags flags) {
    return scale(src, dest, 3);
}
