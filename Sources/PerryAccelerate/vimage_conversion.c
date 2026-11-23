// vImage conversions between depths (8-bit, 16-bit, half and single
// float), channel extraction, overwriting and selection, flattening against
// a background, lookup tables, Y'CbCr 4:2:0 to ARGB, and the standard
// Y'CbCr matrices.

#include "vimage.h"

#include <math.h>
#include <stdbool.h>

// MARK: - Half floats

/// IEEE half to float.
__attribute__((visibility("hidden"))) float perry_vimage_half_to_float(uint16_t h) {
    uint32_t sign = (uint32_t)(h & 0x8000) << 16, exponent = (h >> 10) & 0x1f, mantissa = h & 0x3ff, bits;
    if (exponent == 0) {
        if (mantissa == 0) bits = sign;
        else {
            // Subnormal: normalise it.
            int shift = 0;
            while (!(mantissa & 0x400)) { mantissa <<= 1; shift++; }
            mantissa &= 0x3ff;
            bits = sign | ((uint32_t)(113 - shift) << 23) | (mantissa << 13);
        }
    } else if (exponent == 31) bits = sign | 0x7f800000 | (mantissa << 13);
    else bits = sign | ((exponent + 112) << 23) | (mantissa << 13);
    float f;
    memcpy(&f, &bits, 4);
    return f;
}

/// Float to IEEE half, rounding to nearest even.
__attribute__((visibility("hidden"))) uint16_t perry_vimage_float_to_half(float f) {
    uint32_t bits;
    memcpy(&bits, &f, 4);
    uint16_t sign = (bits >> 16) & 0x8000;
    uint32_t magnitude = bits & 0x7fffffff;
    if (magnitude >= 0x7f800000) return sign | 0x7c00 | (magnitude > 0x7f800000 ? 0x200 | ((magnitude >> 13) & 0x3ff) : 0);
    if (magnitude >= 0x477ff000) return sign | 0x7c00; // rounds past the largest half
    if (magnitude < 0x38800000) {
        // Subnormal half (or zero): scale so the units are 2^-24.
        if (magnitude < 0x33000000) return sign;
        uint32_t mantissa = (magnitude & 0x7fffff) | 0x800000;
        int shift = 126 - (int)(magnitude >> 23) ; // 113 + 13 - exponent
        uint32_t value = mantissa >> shift, rest = mantissa & ((1u << shift) - 1), half = 1u << (shift - 1);
        if (rest > half || (rest == half && (value & 1))) value++;
        return sign | (uint16_t)value;
    }
    uint32_t value = ((magnitude >> 13) - (112 << 10)), rest = magnitude & 0x1fff;
    if (rest > 0x1000 || (rest == 0x1000 && (value & 1))) value++;
    return sign | (uint16_t)value;
}

#define H2F perry_vimage_half_to_float
#define F2H perry_vimage_float_to_half

// MARK: - Helpers

#define EXPORT(ret, name, args) ret name args DARWIN_SYMBOL(name); ret name args

/// Runs the body (the last argument) over dest's pixels with `s` and `d` the source and dest pixel addresses.
#define EACH(src, dest, sbytes, dbytes, ...) \
    do { \
        vImage_Error error_ = vimage_check(src, dest); \
        if (error_) return error_; \
        for (vImagePixelCount y = 0; y < (dest)->height; y++) { \
            const uint8_t *srow_ = vimage_pixel(src, 0, y, 0); \
            uint8_t *drow_ = vimage_pixel(dest, 0, y, 0); \
            for (vImagePixelCount x = 0; x < (dest)->width; x++) { \
                const uint8_t *s = srow_ + x * (sbytes); \
                uint8_t *d = drow_ + x * (dbytes); \
                __VA_ARGS__; \
            } \
        } \
    } while (0)

static inline uint8_t clamp8_round(float v) {
    if (!(v > 0)) return 0;
    if (v >= 255) return 255;
    return (uint8_t)(v + 0.5f);
}

static inline uint16_t clamp16_round(float v) {
    if (!(v > 0)) return 0;
    if (v >= 65535) return 65535;
    return (uint16_t)nearbyintf(v); // ties to even, as vImage rounds
}

static inline float load_f(const uint8_t *p) { float f; memcpy(&f, p, 4); return f; }
static inline void store_f(uint8_t *p, float f) { memcpy(p, &f, 4); }
static inline uint16_t load_16(const uint8_t *p) { uint16_t v; memcpy(&v, p, 2); return v; }
static inline void store_16(uint8_t *p, uint16_t v) { memcpy(p, &v, 2); }

// MARK: - Depth conversions

EXPORT(vImage_Error, vImageConvert_Planar8toPlanarF, (const vImage_Buffer *src, const vImage_Buffer *dest, Pixel_F maxFloat,
                                                      Pixel_F minFloat, vImage_Flags flags)) {
    float step = (maxFloat - minFloat) / 255.0f;
    EACH(src, dest, 1, 4, store_f(d, minFloat + (float)s[0] * step));
    return kvImageNoError;
}

EXPORT(vImage_Error, vImageConvert_PlanarFtoPlanar8, (const vImage_Buffer *src, const vImage_Buffer *dest, Pixel_F maxFloat,
                                                      Pixel_F minFloat, vImage_Flags flags)) {
    float scale = 255.0f / (maxFloat - minFloat);
    EACH(src, dest, 4, 1, d[0] = clamp8_round((load_f(s) - minFloat) * scale));
    return kvImageNoError;
}

EXPORT(vImage_Error, vImageConvert_Planar8To16U, (const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags)) {
    EACH(src, dest, 1, 2, store_16(d, (uint16_t)(s[0] * 257u)));
    return kvImageNoError;
}

EXPORT(vImage_Error, vImageConvert_16UToPlanar8, (const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags)) {
    EACH(src, dest, 2, 1, d[0] = (uint8_t)((load_16(s) * 255u + 32767u) / 65535u));
    return kvImageNoError;
}

EXPORT(vImage_Error, vImageConvert_16UToF, (const vImage_Buffer *src, const vImage_Buffer *dest, float offset, float scale,
                                            vImage_Flags flags)) {
    EACH(src, dest, 2, 4, store_f(d, offset + scale * (float)load_16(s)));
    return kvImageNoError;
}

EXPORT(vImage_Error, vImageConvert_FTo16U, (const vImage_Buffer *src, const vImage_Buffer *dest, float offset, float scale,
                                            vImage_Flags flags)) {
    float inverse = 1.0f / scale;
    EACH(src, dest, 4, 2, store_16(d, clamp16_round((load_f(s) - offset) * inverse)));
    return kvImageNoError;
}

EXPORT(vImage_Error, vImageConvert_Planar16FtoPlanarF, (const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags)) {
    EACH(src, dest, 2, 4, store_f(d, H2F(load_16(s))));
    return kvImageNoError;
}

EXPORT(vImage_Error, vImageConvert_PlanarFtoPlanar16F, (const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags)) {
    EACH(src, dest, 4, 2, store_16(d, F2H(load_f(s))));
    return kvImageNoError;
}

EXPORT(vImage_Error, vImageConvert_Planar16FtoPlanar8, (const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags)) {
    EACH(src, dest, 2, 1, d[0] = clamp8_round(H2F(load_16(s)) * 255.0f));
    return kvImageNoError;
}

EXPORT(vImage_Error, vImageConvert_Planar8toPlanar16F, (const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags)) {
    EACH(src, dest, 1, 2, store_16(d, F2H((float)s[0] / 255.0f)));
    return kvImageNoError;
}

EXPORT(vImage_Error, vImageConvert_16Fto16U, (const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags)) {
    EACH(src, dest, 2, 2, store_16(d, clamp16_round(H2F(load_16(s)) * 65535.0f)));
    return kvImageNoError;
}

EXPORT(vImage_Error, vImageConvert_16Uto16F, (const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags)) {
    EACH(src, dest, 2, 2, store_16(d, F2H((float)load_16(s) / 65535.0f)));
    return kvImageNoError;
}

EXPORT(vImage_Error, vImageClip_PlanarF, (const vImage_Buffer *src, const vImage_Buffer *dest, Pixel_F maxFloat, Pixel_F minFloat,
                                          vImage_Flags flags)) {
    EACH(src, dest, 4, 4, {
        float v = load_f(s);
        store_f(d, v > maxFloat ? maxFloat : v < minFloat ? minFloat : v);
    });
    return kvImageNoError;
}

// MARK: - Dropping alpha from float pixels

EXPORT(vImage_Error, vImageConvert_ARGBFFFFtoRGBFFF, (const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags)) {
    EACH(src, dest, 16, 12, memmove(d, s + 4, 12));
    return kvImageNoError;
}

EXPORT(vImage_Error, vImageConvert_RGBAFFFFtoRGBFFF, (const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags)) {
    EACH(src, dest, 16, 12, memmove(d, s, 12));
    return kvImageNoError;
}

// MARK: - Channels

EXPORT(vImage_Error, vImageExtractChannel_ARGB8888, (const vImage_Buffer *src, const vImage_Buffer *dest, long channelIndex,
                                                     vImage_Flags flags)) {
    if (channelIndex < 0 || channelIndex > 3) return kvImageInvalidParameter;
    EACH(src, dest, 4, 1, d[0] = s[channelIndex]);
    return kvImageNoError;
}

EXPORT(vImage_Error, vImageExtractChannel_ARGB16U, (const vImage_Buffer *src, const vImage_Buffer *dest, long channelIndex,
                                                    vImage_Flags flags)) {
    if (channelIndex < 0 || channelIndex > 3) return kvImageInvalidParameter;
    EACH(src, dest, 8, 2, memcpy(d, s + 2 * channelIndex, 2));
    return kvImageNoError;
}

EXPORT(vImage_Error, vImageExtractChannel_ARGBFFFF, (const vImage_Buffer *src, const vImage_Buffer *dest, long channelIndex,
                                                     vImage_Flags flags)) {
    if (channelIndex < 0 || channelIndex > 3) return kvImageInvalidParameter;
    EACH(src, dest, 16, 4, memcpy(d, s + 4 * channelIndex, 4));
    return kvImageNoError;
}

/// copyMask bit 3 is channel 0 (alpha in ARGB), bit 0 channel 3.
static inline int masked(uint8_t mask, int channel) { return mask & (8 >> channel); }

EXPORT(vImage_Error, vImageOverwriteChannelsWithPixel_ARGB8888, (const Pixel_8888 the_pixel, const vImage_Buffer *src,
                                                                 const vImage_Buffer *dest, uint8_t copyMask, vImage_Flags flags)) {
    EACH(src, dest, 4, 4, {
        uint8_t p[4];
        for (int c = 0; c < 4; c++) p[c] = masked(copyMask, c) ? the_pixel[c] : s[c];
        memcpy(d, p, 4);
    });
    return kvImageNoError;
}

EXPORT(vImage_Error, vImageOverwriteChannelsWithPixel_ARGB16U, (const Pixel_ARGB_16U the_pixel, const vImage_Buffer *src,
                                                                const vImage_Buffer *dest, uint8_t copyMask, vImage_Flags flags)) {
    EACH(src, dest, 8, 8, {
        uint8_t p[8];
        for (int c = 0; c < 4; c++) {
            if (masked(copyMask, c)) memcpy(p + 2 * c, &the_pixel[c], 2);
            else memcpy(p + 2 * c, s + 2 * c, 2);
        }
        memcpy(d, p, 8);
    });
    return kvImageNoError;
}

EXPORT(vImage_Error, vImageOverwriteChannelsWithPixel_ARGBFFFF, (const Pixel_FFFF the_pixel, const vImage_Buffer *src,
                                                                 const vImage_Buffer *dest, uint8_t copyMask, vImage_Flags flags)) {
    EACH(src, dest, 16, 16, {
        uint8_t p[16];
        for (int c = 0; c < 4; c++) {
            if (masked(copyMask, c)) memcpy(p + 4 * c, &the_pixel[c], 4);
            else memcpy(p + 4 * c, s + 4 * c, 4);
        }
        memcpy(d, p, 16);
    });
    return kvImageNoError;
}

EXPORT(vImage_Error, vImageOverwriteChannelsWithScalar_ARGBFFFF, (Pixel_F scalar, const vImage_Buffer *src, const vImage_Buffer *dest,
                                                                  uint8_t copyMask, vImage_Flags flags)) {
    Pixel_FFFF pixel = {scalar, scalar, scalar, scalar};
    return vImageOverwriteChannelsWithPixel_ARGBFFFF(pixel, src, dest, copyMask, flags);
}

/// Fills dest with one `bytes`-byte value.
static vImage_Error fill(const vImage_Buffer *dest, const void *value, size_t bytes) {
    if (!dest || !dest->data) return kvImageNullPointerArgument;
    for (vImagePixelCount y = 0; y < dest->height; y++) {
        uint8_t *row = vimage_pixel(dest, 0, y, 0);
        if (bytes == 1) memset(row, *(const uint8_t *)value, dest->width);
        else
            for (vImagePixelCount x = 0; x < dest->width; x++) memcpy(row + x * bytes, value, bytes);
    }
    return kvImageNoError;
}

EXPORT(vImage_Error, vImageOverwriteChannelsWithScalar_Planar8, (Pixel_8 scalar, const vImage_Buffer *dest, vImage_Flags flags)) {
    return fill(dest, &scalar, 1);
}

EXPORT(vImage_Error, vImageOverwriteChannelsWithScalar_Planar16F, (Pixel_16F scalar, const vImage_Buffer *dest, vImage_Flags flags)) {
    return fill(dest, &scalar, 2);
}

EXPORT(vImage_Error, vImageOverwriteChannelsWithScalar_PlanarF, (Pixel_F scalar, const vImage_Buffer *dest, vImage_Flags flags)) {
    return fill(dest, &scalar, 4);
}

/// Masked channels of dest from the planar newSrc, the rest from origSrc.
static vImage_Error overwrite(const vImage_Buffer *newSrc, const vImage_Buffer *origSrc, const vImage_Buffer *dest, uint8_t copyMask,
                              size_t size) {
    vImage_Error error = vimage_check(origSrc, dest);
    if (error) return error;
    error = vimage_check(newSrc, dest);
    if (error) return error;
    for (vImagePixelCount y = 0; y < dest->height; y++)
        for (vImagePixelCount x = 0; x < dest->width; x++) {
            const uint8_t *n = vimage_pixel(newSrc, x, y, size), *o = vimage_pixel(origSrc, x, y, 4 * size);
            uint8_t p[16];
            for (int c = 0; c < 4; c++) memcpy(p + c * size, masked(copyMask, c) ? n : o + c * size, size);
            memcpy(vimage_pixel(dest, x, y, 4 * size), p, 4 * size);
        }
    return kvImageNoError;
}

EXPORT(vImage_Error, vImageOverwriteChannels_ARGB8888, (const vImage_Buffer *newSrc, const vImage_Buffer *origSrc,
                                                        const vImage_Buffer *dest, uint8_t copyMask, vImage_Flags flags)) {
    return overwrite(newSrc, origSrc, dest, copyMask, 1);
}

EXPORT(vImage_Error, vImageOverwriteChannels_ARGBFFFF, (const vImage_Buffer *newSrc, const vImage_Buffer *origSrc,
                                                        const vImage_Buffer *dest, uint8_t copyMask, vImage_Flags flags)) {
    return overwrite(newSrc, origSrc, dest, copyMask, 4);
}

/// Masked channels of dest from the four-channel newSrc, the rest from origSrc.
static vImage_Error select_channels(const vImage_Buffer *newSrc, const vImage_Buffer *origSrc, const vImage_Buffer *dest,
                                    uint8_t copyMask, size_t size) {
    vImage_Error error = vimage_check(origSrc, dest);
    if (error) return error;
    error = vimage_check(newSrc, dest);
    if (error) return error;
    for (vImagePixelCount y = 0; y < dest->height; y++)
        for (vImagePixelCount x = 0; x < dest->width; x++) {
            const uint8_t *n = vimage_pixel(newSrc, x, y, 4 * size), *o = vimage_pixel(origSrc, x, y, 4 * size);
            uint8_t p[16];
            for (int c = 0; c < 4; c++) memcpy(p + c * size, (masked(copyMask, c) ? n : o) + c * size, size);
            memcpy(vimage_pixel(dest, x, y, 4 * size), p, 4 * size);
        }
    return kvImageNoError;
}

EXPORT(vImage_Error, vImageSelectChannels_ARGB8888, (const vImage_Buffer *newSrc, const vImage_Buffer *origSrc,
                                                     const vImage_Buffer *dest, uint8_t copyMask, vImage_Flags flags)) {
    return select_channels(newSrc, origSrc, dest, copyMask, 1);
}

EXPORT(vImage_Error, vImageSelectChannels_ARGBFFFF, (const vImage_Buffer *newSrc, const vImage_Buffer *origSrc,
                                                     const vImage_Buffer *dest, uint8_t copyMask, vImage_Flags flags)) {
    return select_channels(newSrc, origSrc, dest, copyMask, 4);
}

/// dest channel i takes source channel map[i], channels `size` bytes.
static vImage_Error permute(const vImage_Buffer *src, const vImage_Buffer *dest, const uint8_t map[4], size_t size) {
    for (int c = 0; c < 4; c++)
        if (map[c] > 3) return kvImageInvalidParameter;
    EACH(src, dest, 4 * size, 4 * size, {
        uint8_t p[16];
        for (int c = 0; c < 4; c++) memcpy(p + c * size, s + map[c] * size, size);
        memcpy(d, p, 4 * size);
    });
    return kvImageNoError;
}

EXPORT(vImage_Error, vImagePermuteChannels_ARGB16U, (const vImage_Buffer *src, const vImage_Buffer *dest, const uint8_t permuteMap[4],
                                                     vImage_Flags flags)) {
    return permute(src, dest, permuteMap, 2);
}

EXPORT(vImage_Error, vImagePermuteChannels_ARGB16F, (const vImage_Buffer *src, const vImage_Buffer *dest, const uint8_t permuteMap[4],
                                                     vImage_Flags flags)) {
    return permute(src, dest, permuteMap, 2);
}

EXPORT(vImage_Error, vImagePermuteChannels_ARGBFFFF, (const vImage_Buffer *src, const vImage_Buffer *dest, const uint8_t permuteMap[4],
                                                      vImage_Flags flags)) {
    return permute(src, dest, permuteMap, 4);
}

// MARK: - Flattening

/// Composites four-channel 8-bit pixels with alpha at `alpha` (0 or 3) over
/// the background (in the source's channel order), dropping alpha.
static vImage_Error flatten8(const vImage_Buffer *src, const vImage_Buffer *dest, const Pixel_8888 background, int premultiplied,
                             int alpha) {
    int first = alpha == 0 ? 1 : 0;
    EACH(src, dest, 4, 3, {
        unsigned a = s[alpha], rest = 255 - a;
        uint8_t p[3];
        for (int c = 0; c < 3; c++) {
            unsigned color = s[first + c], back = background[first + c];
            if (premultiplied) {
                // Premultiplied color is at most alpha.
                if (color > a) color = a;
                unsigned v = color + (rest * back + 127) / 255;
                p[c] = v > 255 ? 255 : (uint8_t)v;
            } else p[c] = (uint8_t)((color * a + rest * back + 127) / 255);
        }
        memcpy(d, p, 3);
    });
    return kvImageNoError;
}

static vImage_Error flattenF(const vImage_Buffer *src, const vImage_Buffer *dest, const Pixel_FFFF background, int premultiplied,
                             int alpha) {
    int first = alpha == 0 ? 1 : 0;
    EACH(src, dest, 16, 12, {
        float pixel[4], p[3];
        memcpy(pixel, s, 16);
        float a = pixel[alpha], rest = 1.0f - a;
        for (int c = 0; c < 3; c++) {
            float color = pixel[first + c], back = background[first + c];
            if (premultiplied && color > a) color = a; // premultiplied color is at most alpha
            p[c] = premultiplied ? color + rest * back : color * a + rest * back;
        }
        memcpy(d, p, 12);
    });
    return kvImageNoError;
}

EXPORT(vImage_Error, vImageFlatten_ARGB8888ToRGB888, (const vImage_Buffer *argb8888Src, const vImage_Buffer *rgb888dest,
                                                      const Pixel_8888 backgroundColor, bool isImagePremultiplied, vImage_Flags flags)) {
    return flatten8(argb8888Src, rgb888dest, backgroundColor, isImagePremultiplied, 0);
}

EXPORT(vImage_Error, vImageFlatten_RGBA8888ToRGB888, (const vImage_Buffer *rgba8888Src, const vImage_Buffer *rgb888dest,
                                                      const Pixel_8888 backgroundColor, bool isImagePremultiplied, vImage_Flags flags)) {
    return flatten8(rgba8888Src, rgb888dest, backgroundColor, isImagePremultiplied, 3);
}

EXPORT(vImage_Error, vImageFlatten_ARGBFFFFToRGBFFF, (const vImage_Buffer *argbFFFFSrc, const vImage_Buffer *rgbFFFdest,
                                                      const Pixel_FFFF backgroundColor, bool isImagePremultiplied, vImage_Flags flags)) {
    return flattenF(argbFFFFSrc, rgbFFFdest, backgroundColor, isImagePremultiplied, 0);
}

EXPORT(vImage_Error, vImageFlatten_RGBAFFFFToRGBFFF, (const vImage_Buffer *rgbaFFFFSrc, const vImage_Buffer *rgbFFFdest,
                                                      const Pixel_FFFF backgroundColor, bool isImagePremultiplied, vImage_Flags flags)) {
    return flattenF(rgbaFFFFSrc, rgbFFFdest, backgroundColor, isImagePremultiplied, 3);
}

// MARK: - Lookup tables

EXPORT(vImage_Error, vImageLookupTable_Planar8toPlanar16, (const vImage_Buffer *src, const vImage_Buffer *dest, const Pixel_16U table[256],
                                                           vImage_Flags flags)) {
    if (!table) return kvImageNullPointerArgument;
    EACH(src, dest, 1, 2, store_16(d, table[s[0]]));
    return kvImageNoError;
}

EXPORT(vImage_Error, vImageLookupTable_Planar8toPlanarF, (const vImage_Buffer *src, const vImage_Buffer *dest, const Pixel_F table[256],
                                                          vImage_Flags flags)) {
    if (!table) return kvImageNullPointerArgument;
    EACH(src, dest, 1, 4, store_f(d, table[s[0]]));
    return kvImageNoError;
}

// MARK: - Y'CbCr

typedef struct vImage_YpCbCrPixelRange {
    int32_t Yp_bias, CbCr_bias, YpRangeMax, CbCrRangeMax, YpMax, YpMin, CbCrMax, CbCrMin;
} vImage_YpCbCrPixelRange;
typedef struct vImage_YpCbCrToARGB { uint8_t opaque[128]; } vImage_YpCbCrToARGB;
typedef struct vImage_ARGBToYpCbCrMatrix { float R_Yp, G_Yp, B_Yp, R_Cb, G_Cb, B_Cb_R_Cr, G_Cr, B_Cr; } vImage_ARGBToYpCbCrMatrix;
typedef struct vImage_YpCbCrToARGBMatrix { float Yp, Cr_R, Cr_G, Cb_G, Cb_B; } vImage_YpCbCrToARGBMatrix;

// The ITU-R matrices, from each standard's red and blue luma weights.
#define ARGB_TO_YCBCR(kr, kb) \
    { (kr), 1.0f - (kr) - (kb), (kb), -0.5f * (kr) / (1.0f - (kb)), -0.5f * (1.0f - (kr) - (kb)) / (1.0f - (kb)), 0.5f, \
      -0.5f * (1.0f - (kr) - (kb)) / (1.0f - (kr)), -0.5f * (kb) / (1.0f - (kr)) }
#define YCBCR_TO_ARGB(kr, kb) \
    { 1.0f, 2.0f * (1.0f - (kr)), -2.0f * (kr) * (1.0f - (kr)) / (1.0f - (kr) - (kb)), \
      -2.0f * (kb) * (1.0f - (kb)) / (1.0f - (kr) - (kb)), 2.0f * (1.0f - (kb)) }

static const vImage_ARGBToYpCbCrMatrix argb_to_ycbcr_601 = ARGB_TO_YCBCR(0.299f, 0.114f);
static const vImage_ARGBToYpCbCrMatrix argb_to_ycbcr_709 = ARGB_TO_YCBCR(0.2126f, 0.0722f);
static const vImage_YpCbCrToARGBMatrix ycbcr_to_argb_601 = YCBCR_TO_ARGB(0.299f, 0.114f);
static const vImage_YpCbCrToARGBMatrix ycbcr_to_argb_709 = YCBCR_TO_ARGB(0.2126f, 0.0722f);

const vImage_ARGBToYpCbCrMatrix *const darwin_kvImage_ARGBToYpCbCrMatrix_ITU_R_601_4
    DARWIN_SYMBOL(kvImage_ARGBToYpCbCrMatrix_ITU_R_601_4) = &argb_to_ycbcr_601;
const vImage_ARGBToYpCbCrMatrix *const darwin_kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2
    DARWIN_SYMBOL(kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2) = &argb_to_ycbcr_709;
const vImage_YpCbCrToARGBMatrix *const darwin_kvImage_YpCbCrToARGBMatrix_ITU_R_601_4
    DARWIN_SYMBOL(kvImage_YpCbCrToARGBMatrix_ITU_R_601_4) = &ycbcr_to_argb_601;
const vImage_YpCbCrToARGBMatrix *const darwin_kvImage_YpCbCrToARGBMatrix_ITU_R_709_2
    DARWIN_SYMBOL(kvImage_YpCbCrToARGBMatrix_ITU_R_709_2) = &ycbcr_to_argb_709;

__attribute__((visibility("hidden"))) const vImage_ARGBToYpCbCrMatrix *perry_vimage_matrix_601 = &argb_to_ycbcr_601;
__attribute__((visibility("hidden"))) const vImage_ARGBToYpCbCrMatrix *perry_vimage_matrix_709 = &argb_to_ycbcr_709;

/// Our layout of vImage_YpCbCrToARGB's 128 opaque bytes.
struct ycbcr_info {
    uint32_t magic;
    int32_t yBias, cBias, yMin, yMax, cMin, cMax;
    float yScale, cScale; // per code value, to 0...1 luma and -0.5...0.5 chroma
    float yp, crR, crG, cbG, cbB;
    int32_t ycbcrType, argbType;
};
_Static_assert(sizeof(struct ycbcr_info) <= 128, "fits vImage_YpCbCrToARGB");
#define YCBCR_MAGIC 0x50594343u

EXPORT(vImage_Error, vImageConvert_YpCbCrToARGB_GenerateConversion, (const vImage_YpCbCrToARGBMatrix *matrix,
                                                                     const vImage_YpCbCrPixelRange *pixelRange,
                                                                     vImage_YpCbCrToARGB *outInfo, int32_t inYpCbCrType,
                                                                     int32_t outARGBType, vImage_Flags flags)) {
    if (!matrix || !pixelRange || !outInfo) return kvImageNullPointerArgument;
    if (outARGBType != 0 /* kvImageARGB8888 */) return kvImageInvalidParameter;
    struct ycbcr_info info = {
        .magic = YCBCR_MAGIC,
        .yBias = pixelRange->Yp_bias, .cBias = pixelRange->CbCr_bias,
        .yMin = pixelRange->YpMin, .yMax = pixelRange->YpMax, .cMin = pixelRange->CbCrMin, .cMax = pixelRange->CbCrMax,
        .yScale = 1.0f / (float)(pixelRange->YpRangeMax - pixelRange->Yp_bias),
        .cScale = 0.5f / (float)(pixelRange->CbCrRangeMax - pixelRange->CbCr_bias),
        .yp = matrix->Yp, .crR = matrix->Cr_R, .crG = matrix->Cr_G, .cbG = matrix->Cb_G, .cbB = matrix->Cb_B,
        .ycbcrType = inYpCbCrType, .argbType = outARGBType,
    };
    memset(outInfo, 0, sizeof *outInfo);
    memcpy(outInfo, &info, sizeof info);
    return kvImageNoError;
}

/// One Y'CbCr sample to R, G, B bytes.
static inline void ycbcr_to_rgb(const struct ycbcr_info *info, int yp, int cb, int cr, uint8_t rgb[3]) {
    float y = info->yp * (float)(yp - info->yBias) * info->yScale;
    float b = (float)(cb - info->cBias) * info->cScale, r = (float)(cr - info->cBias) * info->cScale;
    rgb[0] = clamp8_round((y + info->crR * r) * 255.0f);
    rgb[1] = clamp8_round((y + info->crG * r + info->cbG * b) * 255.0f);
    rgb[2] = clamp8_round((y + info->cbB * b) * 255.0f);
}

EXPORT(vImage_Error, vImageConvert_420Yp8_CbCr8ToARGB8888, (const vImage_Buffer *srcYp, const vImage_Buffer *srcCbCr,
                                                            const vImage_Buffer *dest, const vImage_YpCbCrToARGB *info,
                                                            const uint8_t permuteMap[4], const uint8_t alpha, vImage_Flags flags)) {
    if (!srcYp || !srcCbCr || !dest || !info || !srcYp->data || !srcCbCr->data || !dest->data) return kvImageNullPointerArgument;
    struct ycbcr_info conversion;
    memcpy(&conversion, info, sizeof conversion);
    if (conversion.magic != YCBCR_MAGIC) return kvImageInvalidParameter;
    if (dest->width > srcYp->width || dest->height > srcYp->height || (dest->width + 1) / 2 > srcCbCr->width
        || (dest->height + 1) / 2 > srcCbCr->height)
        return kvImageRoiLargerThanInputBuffer;
    static const uint8_t identity[4] = {0, 1, 2, 3};
    const uint8_t *map = permuteMap ? permuteMap : identity;
    for (vImagePixelCount y = 0; y < dest->height; y++)
        for (vImagePixelCount x = 0; x < dest->width; x++) {
            const uint8_t *c = vimage_pixel(srcCbCr, x / 2, y / 2, 2);
            uint8_t argb[4] = {alpha};
            ycbcr_to_rgb(&conversion, *vimage_pixel(srcYp, x, y, 1), c[0], c[1], argb + 1);
            uint8_t *d = vimage_pixel(dest, x, y, 4);
            for (int i = 0; i < 4; i++) d[i] = argb[map[i] & 3];
        }
    return kvImageNoError;
}
