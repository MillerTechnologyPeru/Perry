// vImage alpha compositing: blending premultiplied and non-premultiplied
// images, the RGBA8888 blend modes, and premultiplying and unpremultiplying
// planar, 16-bit, half and float pixels.

#include "vimage.h"

float perry_vimage_half_to_float(uint16_t h);
uint16_t perry_vimage_float_to_half(float f);

#define EXPORT(ret, name, args) ret name args DARWIN_SYMBOL(name); ret name args

/// Checks three buffers: two sources at least as large as dest.
static vImage_Error check3(const vImage_Buffer *a, const vImage_Buffer *b, const vImage_Buffer *dest) {
    vImage_Error error = vimage_check(a, dest);
    return error ? error : vimage_check(b, dest);
}

/// (a * b + 127) / 255 for products of two bytes.
static inline unsigned mul255(unsigned a, unsigned b) { return (a * b + 127) / 255; }

static inline uint8_t sat8(unsigned v) { return v > 255 ? 255 : (uint8_t)v; }

static inline uint8_t clamp8f(float v) {
    if (!(v > 0)) return 0;
    if (v >= 255) return 255;
    return (uint8_t)(v + 0.5f);
}

/// Walks three buffers of `bytes`-byte pixels: t (top), b (bottom), d (dest).
#define EACH3(top, bottom, dest, bytes, ...) \
    do { \
        vImage_Error error_ = check3(top, bottom, dest); \
        if (error_) return error_; \
        for (vImagePixelCount y = 0; y < (dest)->height; y++) \
            for (vImagePixelCount x = 0; x < (dest)->width; x++) { \
                const uint8_t *t = vimage_pixel(top, x, y, bytes), *b = vimage_pixel(bottom, x, y, bytes); \
                uint8_t *d = vimage_pixel(dest, x, y, bytes); \
                __VA_ARGS__; \
            } \
    } while (0)

// MARK: - Non-premultiplied blends

EXPORT(vImage_Error, vImageAlphaBlend_ARGB8888, (const vImage_Buffer *srcTop, const vImage_Buffer *srcBottom, const vImage_Buffer *dest,
                                                 vImage_Flags flags)) {
    EACH3(srcTop, srcBottom, dest, 4, {
        // Colors in float, as vImage does; alpha in integers.
        unsigned ta = t[0], ba = b[0];
        float top = (float)ta / 255.0f, rest = 1.0f - top, a = top + rest * (float)ba / 255.0f;
        uint8_t p[4] = {sat8(ta + mul255(255 - ta, ba))};
        for (int c = 1; c < 4; c++)
            p[c] = a > 0 ? clamp8f(((float)t[c] * top + rest * (float)ba / 255.0f * (float)b[c]) / a) : 0;
        memcpy(d, p, 4);
    });
    return kvImageNoError;
}

EXPORT(vImage_Error, vImageAlphaBlend_ARGBFFFF, (const vImage_Buffer *srcTop, const vImage_Buffer *srcBottom, const vImage_Buffer *dest,
                                                 vImage_Flags flags)) {
    EACH3(srcTop, srcBottom, dest, 16, {
        float tp[4], bp[4], p[4];
        memcpy(tp, t, 16);
        memcpy(bp, b, 16);
        float rest = 1.0f - tp[0], a = tp[0] + rest * bp[0];
        p[0] = a;
        for (int c = 1; c < 4; c++) p[c] = a == 0 ? 0 : (tp[c] * tp[0] + rest * bp[0] * bp[c]) / a;
        memcpy(d, p, 16);
    });
    return kvImageNoError;
}

EXPORT(vImage_Error, vImageAlphaBlend_NonpremultipliedToPremultiplied_ARGB8888,
       (const vImage_Buffer *srcTop, const vImage_Buffer *srcBottom, const vImage_Buffer *dest, vImage_Flags flags)) {
    EACH3(srcTop, srcBottom, dest, 4, {
        unsigned ta = t[0], rest = 255 - ta;
        uint8_t p[4];
        for (int c = 0; c < 4; c++) p[c] = sat8((t[c] * (c == 0 ? 255 : ta) + rest * b[c] + 127) / 255);
        memcpy(d, p, 4);
    });
    return kvImageNoError;
}

EXPORT(vImage_Error, vImageAlphaBlend_NonpremultipliedToPremultiplied_ARGBFFFF,
       (const vImage_Buffer *srcTop, const vImage_Buffer *srcBottom, const vImage_Buffer *dest, vImage_Flags flags)) {
    EACH3(srcTop, srcBottom, dest, 16, {
        float tp[4], bp[4], p[4];
        memcpy(tp, t, 16);
        memcpy(bp, b, 16);
        float rest = 1.0f - tp[0];
        p[0] = tp[0] + rest * bp[0];
        for (int c = 1; c < 4; c++) p[c] = tp[c] * tp[0] + rest * bp[c];
        memcpy(d, p, 16);
    });
    return kvImageNoError;
}

// MARK: - Premultiplied blends

EXPORT(vImage_Error, vImagePremultipliedAlphaBlend_ARGB8888, (const vImage_Buffer *srcTop, const vImage_Buffer *srcBottom,
                                                              const vImage_Buffer *dest, vImage_Flags flags)) {
    EACH3(srcTop, srcBottom, dest, 4, {
        unsigned rest = 255 - t[0];
        uint8_t p[4];
        for (int c = 0; c < 4; c++) p[c] = sat8(t[c] + mul255(rest, b[c]));
        memcpy(d, p, 4);
    });
    return kvImageNoError;
}

EXPORT(vImage_Error, vImagePremultipliedAlphaBlend_ARGBFFFF, (const vImage_Buffer *srcTop, const vImage_Buffer *srcBottom,
                                                              const vImage_Buffer *dest, vImage_Flags flags)) {
    EACH3(srcTop, srcBottom, dest, 16, {
        float tp[4], bp[4], p[4];
        memcpy(tp, t, 16);
        memcpy(bp, b, 16);
        float rest = 1.0f - tp[0];
        for (int c = 0; c < 4; c++) p[c] = tp[c] + rest * bp[c];
        memcpy(d, p, 16);
    });
    return kvImageNoError;
}

EXPORT(vImage_Error, vImagePremultipliedConstAlphaBlend_ARGB8888, (const vImage_Buffer *srcTop, Pixel_8 constAlpha,
                                                                   const vImage_Buffer *srcBottom, const vImage_Buffer *dest,
                                                                   vImage_Flags flags)) {
    EACH3(srcTop, srcBottom, dest, 4, {
        unsigned rest = 255 * 255 - t[0] * constAlpha;
        uint8_t p[4];
        // Truncated, as vImage does (not rounded).
        for (int c = 0; c < 4; c++) p[c] = sat8((t[c] * constAlpha * 255 + rest * b[c]) / (255 * 255));
        memcpy(d, p, 4);
    });
    return kvImageNoError;
}

EXPORT(vImage_Error, vImagePremultipliedConstAlphaBlend_ARGBFFFF, (const vImage_Buffer *srcTop, Pixel_F constAlpha,
                                                                   const vImage_Buffer *srcBottom, const vImage_Buffer *dest,
                                                                   vImage_Flags flags)) {
    EACH3(srcTop, srcBottom, dest, 16, {
        float tp[4], bp[4], p[4];
        memcpy(tp, t, 16);
        memcpy(bp, b, 16);
        float rest = 1.0f - tp[0] * constAlpha;
        for (int c = 0; c < 4; c++) p[c] = tp[c] * constAlpha + rest * bp[c];
        memcpy(d, p, 16);
    });
    return kvImageNoError;
}

/// The RGBA8888 blend modes: colors by `mode`, alpha as the normal blend.
enum blend_mode { Multiply, Screen, Darken, Lighten };

static vImage_Error blend_rgba(const vImage_Buffer *srcTop, const vImage_Buffer *srcBottom, const vImage_Buffer *dest,
                               enum blend_mode mode) {
    EACH3(srcTop, srcBottom, dest, 4, {
        unsigned ta = t[3], ba = b[3];
        uint8_t p[4];
        for (int c = 0; c < 3; c++) {
            unsigned tc = t[c], bc = b[c];
            int v;
            switch (mode) {
            case Multiply: v = (int)(((255 - ta) * bc + (255 - ba) * tc + tc * bc + 127) / 255); break;
            case Screen: v = (int)(tc + bc) - (int)mul255(tc, bc); break;
            case Darken: {
                unsigned one = tc + mul255(255 - ta, bc), two = bc + mul255(255 - ba, tc);
                v = (int)(one < two ? one : two);
                break;
            }
            default: {
                unsigned one = tc + mul255(255 - ta, bc), two = bc + mul255(255 - ba, tc);
                v = (int)(one > two ? one : two);
                break;
            }
            }
            p[c] = v < 0 ? 0 : v > 255 ? 255 : (uint8_t)v;
        }
        p[3] = sat8(ta + mul255(255 - ta, ba));
        memcpy(d, p, 4);
    });
    return kvImageNoError;
}

#define BLEND_MODE(name, mode) \
    EXPORT(vImage_Error, vImagePremultipliedAlphaBlend##name##_RGBA8888, \
           (const vImage_Buffer *srcTop, const vImage_Buffer *srcBottom, const vImage_Buffer *dest, vImage_Flags flags)) { \
        return blend_rgba(srcTop, srcBottom, dest, mode); \
    }

BLEND_MODE(Multiply, Multiply)
BLEND_MODE(Screen, Screen)
BLEND_MODE(Darken, Darken)
BLEND_MODE(Lighten, Lighten)

// MARK: - Premultiplying

static inline uint8_t unpremultiply8(unsigned color, unsigned alpha) {
    if (alpha == 0) return 0;
    if (color > alpha) color = alpha;
    return (uint8_t)((color * 255 + alpha / 2) / alpha);
}

static inline uint16_t unpremultiply16(uint32_t color, uint32_t alpha) {
    if (alpha == 0) return 0;
    if (color > alpha) color = alpha;
    return (uint16_t)(((uint64_t)color * 65535 + alpha / 2) / alpha);
}

/// Alpha 0 gives 0, as vImage does.
static inline float unpremultiplyF(float color, float alpha) { return alpha == 0 ? 0 : color / alpha; }

EXPORT(vImage_Error, vImagePremultiplyData_Planar8, (const vImage_Buffer *src, const vImage_Buffer *alpha, const vImage_Buffer *dest,
                                                     vImage_Flags flags)) {
    EACH3(src, alpha, dest, 1, d[0] = (uint8_t)mul255(t[0], b[0]));
    return kvImageNoError;
}

EXPORT(vImage_Error, vImageUnpremultiplyData_Planar8, (const vImage_Buffer *src, const vImage_Buffer *alpha, const vImage_Buffer *dest,
                                                       vImage_Flags flags)) {
    EACH3(src, alpha, dest, 1, d[0] = unpremultiply8(t[0], b[0]));
    return kvImageNoError;
}

EXPORT(vImage_Error, vImagePremultiplyData_PlanarF, (const vImage_Buffer *src, const vImage_Buffer *alpha, const vImage_Buffer *dest,
                                                     vImage_Flags flags)) {
    EACH3(src, alpha, dest, 4, {
        float c, a;
        memcpy(&c, t, 4);
        memcpy(&a, b, 4);
        c *= a;
        memcpy(d, &c, 4);
    });
    return kvImageNoError;
}

EXPORT(vImage_Error, vImageUnpremultiplyData_PlanarF, (const vImage_Buffer *src, const vImage_Buffer *alpha, const vImage_Buffer *dest,
                                                       vImage_Flags flags)) {
    EACH3(src, alpha, dest, 4, {
        float c, a;
        memcpy(&c, t, 4);
        memcpy(&a, b, 4);
        c = unpremultiplyF(c, a);
        memcpy(d, &c, 4);
    });
    return kvImageNoError;
}

/// Four-channel pixels with alpha at `at` (0 or 3); `kind` the channel type.
enum channel { U16, F32, F16 };

static vImage_Error premultiply4(const vImage_Buffer *src, const vImage_Buffer *dest, int at, enum channel kind, int forward) {
    vImage_Error error = vimage_check(src, dest);
    if (error) return error;
    size_t size = kind == F32 ? 4 : 2;
    for (vImagePixelCount y = 0; y < dest->height; y++)
        for (vImagePixelCount x = 0; x < dest->width; x++) {
            const uint8_t *s = vimage_pixel(src, x, y, 4 * size);
            uint8_t *d = vimage_pixel(dest, x, y, 4 * size);
            if (kind == U16) {
                uint16_t p[4];
                memcpy(p, s, 8);
                uint32_t a = p[at];
                for (int c = 0; c < 4; c++)
                    if (c != at) p[c] = forward ? (uint16_t)((p[c] * a + 32767) / 65535) : unpremultiply16(p[c], a);
                memcpy(d, p, 8);
            } else if (kind == F32) {
                float p[4];
                memcpy(p, s, 16);
                float a = p[at];
                for (int c = 0; c < 4; c++)
                    if (c != at) p[c] = forward ? p[c] * a : unpremultiplyF(p[c], a);
                memcpy(d, p, 16);
            } else {
                uint16_t p[4];
                memcpy(p, s, 8);
                float a = perry_vimage_half_to_float(p[at]);
                for (int c = 0; c < 4; c++) {
                    if (c == at) continue;
                    float v = perry_vimage_half_to_float(p[c]);
                    p[c] = perry_vimage_float_to_half(forward ? v * a : unpremultiplyF(v, a));
                }
                memcpy(d, p, 8);
            }
        }
    return kvImageNoError;
}

#define PREMULTIPLY(format, at, kind) \
    EXPORT(vImage_Error, vImagePremultiplyData_##format, (const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags)) { \
        return premultiply4(src, dest, at, kind, 1); \
    } \
    EXPORT(vImage_Error, vImageUnpremultiplyData_##format, (const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags)) { \
        return premultiply4(src, dest, at, kind, 0); \
    }

PREMULTIPLY(ARGB16U, 0, U16)
PREMULTIPLY(RGBA16U, 3, U16)
PREMULTIPLY(ARGBFFFF, 0, F32)
PREMULTIPLY(RGBAFFFF, 3, F32)
PREMULTIPLY(RGBA16F, 3, F16)
