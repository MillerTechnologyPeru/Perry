// vImage geometry for the formats vimage.c does not cover: reflection,
// quarter turns, rotation by any angle, scaling, shears, and affine and
// perspective warps, for 8-bit, 16-bit, half-float and float pixels with one,
// two (CbCr) or four channels.
//
// Coordinates follow vImage: the origin is the bottom left corner of the
// image, y grows upward, and pixel (x, row) has its center at
// (x + 0.5, height - row - 0.5). Transforms map source to destination
// positions; each destination pixel center is mapped back into the source
// and resampled there with a Lanczos kernel (3 lobes, or 5 with
// kvImageHighQualityResampling), widened when the image shrinks. Perspective
// warps use the nearest pixel or bilinear interpolation, as asked.

#include "vimage.h"

#include <math.h>

enum { T8, T16U, T16F, TF };

typedef struct {
    int type, channels;
} Format;

static const Format Planar8 = {T8, 1}, Planar16U = {T16U, 1}, Planar16F = {T16F, 1}, PlanarF = {TF, 1};
static const Format CbCr8 = {T8, 2}, CbCr16U = {T16U, 2}, CbCr16F = {T16F, 2};
static const Format ARGB8888 = {T8, 4}, ARGB16U = {T16U, 4}, ARGB16F = {T16F, 4}, ARGBFFFF = {TF, 4};

static size_t pixel_bytes(Format f) { return (size_t)f.channels * (f.type == T8 ? 1 : f.type == TF ? 4 : 2); }

static float load(const vImage_Buffer *b, Format f, long x, long y, int c) {
    const uint8_t *row = (const uint8_t *)b->data + (size_t)y * b->rowBytes;
    long i = x * f.channels + c;
    switch (f.type) {
    case T8: return row[i];
    case T16U: return ((const uint16_t *)row)[i];
    case T16F: return vimage_half_to_float(((const uint16_t *)row)[i]);
    default: return ((const float *)row)[i];
    }
}

static void store(const vImage_Buffer *b, Format f, long x, long y, int c, float v) {
    uint8_t *row = (uint8_t *)b->data + (size_t)y * b->rowBytes;
    long i = x * f.channels + c;
    switch (f.type) {
    case T8: row[i] = vimage_clamp8(v); break;
    case T16U: ((uint16_t *)row)[i] = vimage_clamp16(v); break;
    case T16F: ((uint16_t *)row)[i] = vimage_float_to_half(v); break;
    default: ((float *)row)[i] = v; break;
    }
}

/// A background color as floats, from the format's own pixel.
static void background(Format f, const void *color, float out[4]) {
    for (int c = 0; c < 4; c++) out[c] = 0;
    if (!color) return;
    for (int c = 0; c < f.channels; c++) {
        switch (f.type) {
        case T8: out[c] = ((const uint8_t *)color)[c]; break;
        case T16U: out[c] = ((const uint16_t *)color)[c]; break;
        case T16F: out[c] = vimage_half_to_float(((const uint16_t *)color)[c]); break;
        default: out[c] = ((const float *)color)[c]; break;
        }
    }
}

static vImage_Error buffers_check(const vImage_Buffer *src, const vImage_Buffer *dest) {
    if (!src || !dest || !src->data || !dest->data) return kvImageNullPointerArgument;
    return kvImageNoError;
}

// MARK: - Reflection

static vImage_Error reflect(const vImage_Buffer *src, const vImage_Buffer *dest, Format f, int horizontal) {
    vImage_Error error = buffers_check(src, dest);
    if (error) return error;
    if (src->width != dest->width || src->height != dest->height) return kvImageBufferSizeMismatch;
    size_t bytes = pixel_bytes(f), rowLength = bytes * dest->width;
    uint8_t *line = malloc(rowLength ? rowLength : 1), *other = malloc(rowLength ? rowLength : 1);
    if (!line || !other) { free(line); free(other); return kvImageMemoryAllocationError; }
    if (horizontal) {
        for (vImagePixelCount y = 0; y < dest->height; y++) {
            memcpy(line, vimage_pixel(src, 0, y, bytes), rowLength);  // copied first, so it works in place
            for (vImagePixelCount x = 0; x < dest->width; x++)
                memcpy(vimage_pixel(dest, x, y, bytes), line + (dest->width - 1 - x) * bytes, bytes);
        }
    } else {
        for (vImagePixelCount y = 0; y < (dest->height + 1) / 2; y++) {
            vImagePixelCount z = dest->height - 1 - y;
            memcpy(line, vimage_pixel(src, 0, y, bytes), rowLength);
            memcpy(other, vimage_pixel(src, 0, z, bytes), rowLength);
            memcpy(vimage_pixel(dest, 0, y, bytes), other, rowLength);
            memcpy(vimage_pixel(dest, 0, z, bytes), line, rowLength);
        }
    }
    free(line);
    free(other);
    return kvImageNoError;
}

#define REFLECT(format) \
    vImage_Error vImageHorizontalReflect_##format(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags) \
        DARWIN_SYMBOL(vImageHorizontalReflect_##format); \
    vImage_Error vImageHorizontalReflect_##format(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags) { \
        return reflect(src, dest, format, 1); \
    } \
    vImage_Error vImageVerticalReflect_##format(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags) \
        DARWIN_SYMBOL(vImageVerticalReflect_##format); \
    vImage_Error vImageVerticalReflect_##format(const vImage_Buffer *src, const vImage_Buffer *dest, vImage_Flags flags) { \
        return reflect(src, dest, format, 0); \
    }

REFLECT(Planar8)
REFLECT(PlanarF)
REFLECT(Planar16F)
REFLECT(CbCr16F)
REFLECT(ARGB16U)
REFLECT(ARGB16F)
REFLECT(ARGBFFFF)

// MARK: - Quarter turns

/// 0, 90, 180 or 270 degrees counterclockwise, the turned image centered in
/// the destination and the rest filled with the background.
static vImage_Error rotate90(const vImage_Buffer *src, const vImage_Buffer *dest, uint8_t rotation, Format f, const void *color) {
    vImage_Error error = buffers_check(src, dest);
    if (error) return error;
    size_t bytes = pixel_bytes(f);
    uint8_t fill[16] = {0};
    if (color) memcpy(fill, color, bytes);
    rotation &= 3;
    long W = (long)src->width, H = (long)src->height;
    long turnedW = rotation & 1 ? H : W, turnedH = rotation & 1 ? W : H;
    // Half the difference in size, rounded up when it is odd, as vImage places it.
    long offsetX = ((long)dest->width - turnedW + 1) >> 1, offsetY = ((long)dest->height - turnedH + 1) >> 1;
    for (long y = 0; y < (long)dest->height; y++)
        for (long x = 0; x < (long)dest->width; x++) {
            long lx = x - offsetX, ly = y - offsetY, sx, sy;
            uint8_t *d = vimage_pixel(dest, (vImagePixelCount)x, (vImagePixelCount)y, bytes);
            if (lx < 0 || ly < 0 || lx >= turnedW || ly >= turnedH) { memcpy(d, fill, bytes); continue; }
            switch (rotation) {
            case 0: sx = lx; sy = ly; break;
            case 1: sx = W - 1 - ly; sy = lx; break;
            case 2: sx = W - 1 - lx; sy = H - 1 - ly; break;
            default: sx = ly; sy = H - 1 - lx; break;
            }
            memcpy(d, vimage_pixel(src, (vImagePixelCount)sx, (vImagePixelCount)sy, bytes), bytes);
        }
    return kvImageNoError;
}

#define ROTATE90(format, bgType, bgPointer) \
    vImage_Error vImageRotate90_##format(const vImage_Buffer *src, const vImage_Buffer *dest, uint8_t rotationConstant, bgType backColor, \
                                         vImage_Flags flags) DARWIN_SYMBOL(vImageRotate90_##format); \
    vImage_Error vImageRotate90_##format(const vImage_Buffer *src, const vImage_Buffer *dest, uint8_t rotationConstant, bgType backColor, \
                                         vImage_Flags flags) { \
        return rotate90(src, dest, rotationConstant, format, bgPointer); \
    }

ROTATE90(Planar8, Pixel_8, &backColor)
ROTATE90(PlanarF, Pixel_F, &backColor)
ROTATE90(Planar16F, const Pixel_16F, &backColor)
ROTATE90(CbCr16F, const Pixel_16F16F, backColor)
ROTATE90(ARGB16U, const Pixel_ARGB_16U, backColor)
ROTATE90(ARGB16F, const Pixel_ARGB_16F, backColor)
ROTATE90(ARGBFFFF, const Pixel_FFFF, backColor)

// MARK: - Resampling

static double lanczos(double t, double lobes) {
    t = fabs(t);
    if (t >= lobes) return 0;
    if (t < 1e-9) return 1;
    double p = 3.14159265358979323846 * t;
    return lobes * sin(p) * sin(p / lobes) / (p * p);
}

/// Normalized kernel weights for sampling at source index `center` (pixel
/// centers at whole numbers), the kernel widened by `stretch` >= 1.
typedef struct {
    long first;
    int count;
    float weights[64];
} Taps;

static void taps_at(double center, double lobes, double stretch, Taps *taps) {
    double support = lobes * stretch;
    if (support > 31) { stretch = 31 / lobes; support = 31; }
    long first = (long)ceil(center - support), last = (long)floor(center + support);
    if (last - first + 1 > 64) last = first + 63;
    double sum = 0, w[64];
    int n = 0;
    for (long i = first; i <= last; i++, n++) sum += w[n] = lanczos(((double)i - center) / stretch, lobes);
    taps->first = first;
    taps->count = n;
    for (int k = 0; k < n; k++) taps->weights[k] = (float)(sum != 0 ? w[k] / sum : 0);
}

enum { OUTSIDE_BACKGROUND, OUTSIDE_EXTEND };

/// Source channel c at (x, y), or what lies outside.
static float sample_at(const vImage_Buffer *src, Format f, long x, long y, int c, int outside, const float *bg) {
    long W = (long)src->width, H = (long)src->height;
    if (x < 0 || y < 0 || x >= W || y >= H) {
        if (outside == OUTSIDE_BACKGROUND) return bg[c];
        x = x < 0 ? 0 : x >= W ? W - 1 : x;
        y = y < 0 ? 0 : y >= H ? H - 1 : y;
    }
    return load(src, f, x, y, c);
}

static int outside_mode(vImage_Flags flags) { return (flags & kvImageEdgeExtend) ? OUTSIDE_EXTEND : OUTSIDE_BACKGROUND; }

static double lobes_for(vImage_Flags flags) { return (flags & kvImageHighQualityResampling) ? 5 : 3; }

// MARK: - Scaling

/// Separable resampling to the destination's size: across every source row
/// into floats, then down.
static vImage_Error scale(const vImage_Buffer *src, const vImage_Buffer *dest, Format f, vImage_Flags flags) {
    vImage_Error error = buffers_check(src, dest);
    if (error) return error;
    if (flags & kvImageGetTempBufferSize) return 0;
    if (!src->width || !src->height) return kvImageInvalidParameter;
    long sw = (long)src->width, sh = (long)src->height, dw = (long)dest->width, dh = (long)dest->height, ch = f.channels;
    if (!dw || !dh) return kvImageNoError;
    double lobes = lobes_for(flags), sx = (double)sw / dw, sy = (double)sh / dh;
    Taps *across = malloc(sizeof(Taps) * (size_t)dw), *down = malloc(sizeof(Taps));
    float *middle = malloc(sizeof(float) * (size_t)(sh * dw * ch));
    if (!across || !down || !middle) { free(across); free(down); free(middle); return kvImageMemoryAllocationError; }
    for (long x = 0; x < dw; x++) taps_at((x + 0.5) * sx - 0.5, lobes, sx > 1 ? sx : 1, &across[x]);
    for (long y = 0; y < sh; y++)
        for (long x = 0; x < dw; x++)
            for (long c = 0; c < ch; c++) {
                const Taps *t = &across[x];
                float sum = 0;
                for (int k = 0; k < t->count; k++) {
                    long i = t->first + k;
                    i = i < 0 ? 0 : i >= sw ? sw - 1 : i;
                    sum += t->weights[k] * load(src, f, i, y, (int)c);
                }
                middle[(y * dw + x) * ch + c] = sum;
            }
    for (long y = 0; y < dh; y++) {
        taps_at((y + 0.5) * sy - 0.5, lobes, sy > 1 ? sy : 1, down);
        for (long x = 0; x < dw; x++)
            for (long c = 0; c < ch; c++) {
                float sum = 0;
                for (int k = 0; k < down->count; k++) {
                    long i = down->first + k;
                    i = i < 0 ? 0 : i >= sh ? sh - 1 : i;
                    sum += down->weights[k] * middle[(i * dw + x) * ch + c];
                }
                store(dest, f, x, y, (int)c, sum);
            }
    }
    free(across);
    free(down);
    free(middle);
    return kvImageNoError;
}

#define SCALE(format) \
    vImage_Error vImageScale_##format(const vImage_Buffer *src, const vImage_Buffer *dest, void *tempBuffer, vImage_Flags flags) \
        DARWIN_SYMBOL(vImageScale_##format); \
    vImage_Error vImageScale_##format(const vImage_Buffer *src, const vImage_Buffer *dest, void *tempBuffer, vImage_Flags flags) { \
        return scale(src, dest, format, flags); \
    }

SCALE(PlanarF)
SCALE(Planar16U)
SCALE(Planar16F)
SCALE(CbCr8)
SCALE(CbCr16U)
SCALE(CbCr16F)
SCALE(ARGB16U)
SCALE(ARGB16F)
SCALE(ARGBFFFF)

// MARK: - Affine warps, rotation and shears

/// Destination position (X', Y') = (a X + c Y + tx, b X + d Y + ty), the
/// source position X, Y in vImage's bottom-left coordinates.
typedef struct {
    double a, b, c, d, tx, ty;
} Affine;

/// Resamples the source at the inverse of `transform` for every destination
/// pixel. The kernel is widened along each source axis by how far one
/// destination pixel steps along it, so shrinking does not alias.
static vImage_Error warp_affine(const vImage_Buffer *src, const vImage_Buffer *dest, Format f, Affine m, const void *color,
                                vImage_Flags flags) {
    vImage_Error error = buffers_check(src, dest);
    if (error) return error;
    if (flags & kvImageGetTempBufferSize) return 0;
    double det = m.a * m.d - m.b * m.c;
    if (det == 0 || det != det) return kvImageInvalidParameter;
    // The inverse: X = ia X' + ic Y' + itx, Y = ib X' + id Y' + ity.
    double ia = m.d / det, ib = -m.b / det, ic = -m.c / det, id = m.a / det;
    double itx = -(ia * m.tx + ic * m.ty), ity = -(ib * m.tx + id * m.ty);
    // Widen only for shrinking: rotations and shears keep the kernel as it is.
    double stretchX = fmax(1, fmax(fabs(ia), fabs(ic))), stretchY = fmax(1, fmax(fabs(ib), fabs(id)));
    double lobes = lobes_for(flags);
    long sh = (long)src->height, dh = (long)dest->height;
    int outside = outside_mode(flags);
    float bg[4];
    background(f, color, bg);
    Taps tx, ty;
    for (long y = 0; y < dh; y++)
        for (long x = 0; x < (long)dest->width; x++) {
            double X1 = x + 0.5, Y1 = (double)dh - y - 0.5;
            double X = ia * X1 + ic * Y1 + itx, Y = ib * X1 + id * Y1 + ity;
            double col = X - 0.5, row = (double)sh - Y - 0.5;  // source indices
            if (col < -lobes * stretchX - 1 || col > (double)src->width + lobes * stretchX || row < -lobes * stretchY - 1 ||
                row > (double)sh + lobes * stretchY) {
                if (outside == OUTSIDE_BACKGROUND) {
                    for (int c = 0; c < f.channels; c++) store(dest, f, x, y, c, bg[c]);
                    continue;
                }
            }
            taps_at(col, lobes, stretchX, &tx);
            taps_at(row, lobes, stretchY, &ty);
            for (int c = 0; c < f.channels; c++) {
                float sum = 0;
                for (int j = 0; j < ty.count; j++) {
                    float across = 0;
                    for (int i = 0; i < tx.count; i++) across += tx.weights[i] * sample_at(src, f, tx.first + i, ty.first + j, c, outside, bg);
                    sum += ty.weights[j] * across;
                }
                store(dest, f, x, y, c, sum);
            }
        }
    return kvImageNoError;
}

#define AFFINE_CG(format, bgType, bgPointer) \
    vImage_Error vImageAffineWarpCG_##format(const vImage_Buffer *src, const vImage_Buffer *dest, void *tempBuffer, \
                                             const vImage_CGAffineTransform *transform, bgType backColor, vImage_Flags flags) \
        DARWIN_SYMBOL(vImageAffineWarpCG_##format); \
    vImage_Error vImageAffineWarpCG_##format(const vImage_Buffer *src, const vImage_Buffer *dest, void *tempBuffer, \
                                             const vImage_CGAffineTransform *transform, bgType backColor, vImage_Flags flags) { \
        if (!transform) return kvImageNullPointerArgument; \
        Affine m = {transform->a, transform->b, transform->c, transform->d, transform->tx, transform->ty}; \
        return warp_affine(src, dest, format, m, bgPointer, flags); \
    }

AFFINE_CG(Planar8, Pixel_8, &backColor)
AFFINE_CG(PlanarF, Pixel_F, &backColor)
AFFINE_CG(ARGB8888, const Pixel_8888, backColor)
AFFINE_CG(ARGB16U, const Pixel_ARGB_16U, backColor)
AFFINE_CG(ARGBFFFF, const Pixel_FFFF, backColor)

#define AFFINE_D(format, bgType, bgPointer) \
    vImage_Error vImageAffineWarpD_##format(const vImage_Buffer *src, const vImage_Buffer *dest, void *tempBuffer, \
                                            const vImage_AffineTransform_Double *transform, bgType backColor, vImage_Flags flags) \
        DARWIN_SYMBOL(vImageAffineWarpD_##format); \
    vImage_Error vImageAffineWarpD_##format(const vImage_Buffer *src, const vImage_Buffer *dest, void *tempBuffer, \
                                            const vImage_AffineTransform_Double *transform, bgType backColor, vImage_Flags flags) { \
        if (!transform) return kvImageNullPointerArgument; \
        Affine m = {transform->a, transform->b, transform->c, transform->d, transform->tx, transform->ty}; \
        return warp_affine(src, dest, format, m, bgPointer, flags); \
    }

AFFINE_D(Planar16F, const Pixel_16F, &backColor)
AFFINE_D(CbCr16F, const Pixel_16F16F, backColor)
AFFINE_D(ARGB16F, const Pixel_ARGB_16F, backColor)

/// Counterclockwise by `angle` about the centers of both images.
static vImage_Error rotate(const vImage_Buffer *src, const vImage_Buffer *dest, float angle, Format f, const void *color, vImage_Flags flags) {
    vImage_Error error = buffers_check(src, dest);
    if (error) return error;
    double cs = cos(angle), sn = sin(angle);
    double scx = src->width / 2.0, scy = src->height / 2.0, dcx = dest->width / 2.0, dcy = dest->height / 2.0;
    Affine m = {cs, sn, -sn, cs, dcx - (cs * scx - sn * scy), dcy - (sn * scx + cs * scy)};
    return warp_affine(src, dest, f, m, color, flags);
}

#define ROTATE(format, bgType, bgPointer) \
    vImage_Error vImageRotate_##format(const vImage_Buffer *src, const vImage_Buffer *dest, void *tempBuffer, float angleInRadians, \
                                       bgType backColor, vImage_Flags flags) DARWIN_SYMBOL(vImageRotate_##format); \
    vImage_Error vImageRotate_##format(const vImage_Buffer *src, const vImage_Buffer *dest, void *tempBuffer, float angleInRadians, \
                                       bgType backColor, vImage_Flags flags) { \
        return rotate(src, dest, angleInRadians, format, bgPointer, flags); \
    }

ROTATE(Planar8, Pixel_8, &backColor)
ROTATE(PlanarF, Pixel_F, &backColor)
ROTATE(Planar16F, const Pixel_16F, &backColor)
ROTATE(CbCr16F, const Pixel_16F16F, backColor)
ROTATE(ARGB8888, const Pixel_8888, backColor)
ROTATE(ARGB16U, const Pixel_ARGB_16U, backColor)
ROTATE(ARGB16F, const Pixel_ARGB_16F, backColor)
ROTATE(ARGBFFFF, const Pixel_FFFF, backColor)

/// One-dimensional resampling along rows (horizontal) or columns. Destination
/// pixel (x, y) is the source region's (x + offsetX, y + offsetY); along a
/// row, the source position is X' - translate - slope * Y (and the same with
/// the axes swapped for a vertical shear), in bottom-left coordinates of the
/// destination-sized region. The filter is taken to be vImage's default, Lanczos 3 at scale 1.
static vImage_Error shear(const vImage_Buffer *src, const vImage_Buffer *dest, vImagePixelCount offsetX, vImagePixelCount offsetY,
                          double translate, double slope, ResamplingFilter filter, Format f, const void *color, vImage_Flags flags,
                          int horizontal) {
    vImage_Error error = buffers_check(src, dest);
    if (error) return error;
    if (!filter) return kvImageNullPointerArgument;
    if (offsetX + dest->width > src->width || offsetY + dest->height > src->height) return kvImageRoiLargerThanInputBuffer;
    if (flags & kvImageGetTempBufferSize) return 0;
    int outside = outside_mode(flags);
    float bg[4];
    background(f, color, bg);
    Taps t;
    for (long y = 0; y < (long)dest->height; y++)
        for (long x = 0; x < (long)dest->width; x++) {
            // Positions are in the destination's (the region's) own bottom-left coordinates.
            long sx = x + (long)offsetX, sy = y + (long)offsetY;
            double X = x + 0.5, Y = (double)dest->height - y - 0.5;
            if (horizontal) taps_at((double)offsetX + (X - translate - slope * Y) - 0.5, 3, 1, &t);
            else taps_at((double)offsetY + (double)dest->height - (Y - translate - slope * X) - 0.5, 3, 1, &t);
            for (int c = 0; c < f.channels; c++) {
                float sum = 0;
                for (int k = 0; k < t.count; k++)
                    sum += t.weights[k] * (horizontal ? sample_at(src, f, t.first + k, sy, c, outside, bg)
                                                      : sample_at(src, f, sx, t.first + k, c, outside, bg));
                store(dest, f, x, y, c, sum);
            }
        }
    return kvImageNoError;
}

#define SHEAR(name, format, realType, bgType, bgPointer, horizontal) \
    vImage_Error name##_##format(const vImage_Buffer *src, const vImage_Buffer *dest, vImagePixelCount srcOffsetToROI_X, \
                                 vImagePixelCount srcOffsetToROI_Y, realType translate, realType shearSlope, ResamplingFilter filter, \
                                 bgType backColor, vImage_Flags flags) DARWIN_SYMBOL(name##_##format); \
    vImage_Error name##_##format(const vImage_Buffer *src, const vImage_Buffer *dest, vImagePixelCount srcOffsetToROI_X, \
                                 vImagePixelCount srcOffsetToROI_Y, realType translate, realType shearSlope, ResamplingFilter filter, \
                                 bgType backColor, vImage_Flags flags) { \
        return shear(src, dest, srcOffsetToROI_X, srcOffsetToROI_Y, translate, shearSlope, filter, format, bgPointer, flags, horizontal); \
    }

#define SHEAR_D(format, bgType, bgPointer) \
    SHEAR(vImageHorizontalShearD, format, double, bgType, bgPointer, 1) \
    SHEAR(vImageVerticalShearD, format, double, bgType, bgPointer, 0)

SHEAR_D(Planar8, Pixel_8, &backColor)
SHEAR_D(PlanarF, Pixel_F, &backColor)
SHEAR_D(Planar16F, const Pixel_16F, &backColor)
SHEAR_D(CbCr16F, const Pixel_16F16F, backColor)
SHEAR_D(CbCr16U, const Pixel_16U16U, backColor)
SHEAR_D(ARGB8888, const Pixel_8888, backColor)
SHEAR_D(ARGB16U, const Pixel_ARGB_16U, backColor)
SHEAR_D(ARGB16F, const Pixel_ARGB_16F, backColor)
SHEAR_D(ARGBFFFF, const Pixel_FFFF, backColor)

SHEAR(vImageHorizontalShear, CbCr8, float, const Pixel_88, backColor, 1)
SHEAR(vImageVerticalShear, CbCr8, float, const Pixel_88, backColor, 0)
SHEAR(vImageHorizontalShear, Planar16U, float, Pixel_16U, &backColor, 1)
SHEAR(vImageVerticalShear, Planar16U, float, Pixel_16U, &backColor, 0)

// MARK: - Perspective warps

/// Solves the 8 x 8 system for the projective map taking each source point
/// to its destination point, with v = 1.
vImage_Error vImageGetPerspectiveWarp(const float srcPoints[4][2], const float destPoints[4][2], vImage_PerpsectiveTransform *transform,
                                      vImage_Flags flags) DARWIN_SYMBOL(vImageGetPerspectiveWarp);
vImage_Error vImageGetPerspectiveWarp(const float srcPoints[4][2], const float destPoints[4][2], vImage_PerpsectiveTransform *transform,
                                      vImage_Flags flags) {
    if (!srcPoints || !destPoints || !transform) return kvImageNullPointerArgument;
    // Unknowns a, c, tx, b, d, ty, vx, vy: x' (vx x + vy y + 1) = a x + c y + tx, and the same for y'.
    double m[8][9];
    for (int i = 0; i < 4; i++) {
        double x = srcPoints[i][0], y = srcPoints[i][1], u = destPoints[i][0], v = destPoints[i][1];
        double r0[9] = {x, y, 1, 0, 0, 0, -u * x, -u * y, u}, r1[9] = {0, 0, 0, x, y, 1, -v * x, -v * y, v};
        memcpy(m[2 * i], r0, sizeof r0);
        memcpy(m[2 * i + 1], r1, sizeof r1);
    }
    for (int col = 0; col < 8; col++) {
        int pivot = col;
        for (int r = col + 1; r < 8; r++)
            if (fabs(m[r][col]) > fabs(m[pivot][col])) pivot = r;
        if (fabs(m[pivot][col]) < 1e-12) return kvImageInvalidParameter;
        if (pivot != col)
            for (int k = 0; k < 9; k++) { double t = m[col][k]; m[col][k] = m[pivot][k]; m[pivot][k] = t; }
        for (int r = 0; r < 8; r++) {
            if (r == col) continue;
            double factor = m[r][col] / m[col][col];
            for (int k = col; k < 9; k++) m[r][k] -= factor * m[col][k];
        }
    }
    double h[8];
    for (int i = 0; i < 8; i++) h[i] = m[i][8] / m[i][i];
    transform->a = (float)h[0];
    transform->c = (float)h[1];
    transform->tx = (float)h[2];
    transform->b = (float)h[3];
    transform->d = (float)h[4];
    transform->ty = (float)h[5];
    transform->vx = (float)h[6];
    transform->vy = (float)h[7];
    transform->v = 1;
    return kvImageNoError;
}

/// (x', y', w') = (x, y, 1) * | a b vx ; c d vy ; tx ty v |, inverted for each
/// destination pixel center.
static vImage_Error warp_perspective(const vImage_Buffer *src, const vImage_Buffer *dest, const vImage_PerpsectiveTransform *p,
                                     vImage_WarpInterpolation interpolation, Format f, const void *color, vImage_Flags flags) {
    vImage_Error error = buffers_check(src, dest);
    if (error) return error;
    if (!p) return kvImageNullPointerArgument;
    if (interpolation != kvImageInterpolationNearest && interpolation != kvImageInterpolationLinear) return kvImageInvalidParameter;
    if (flags & kvImageGetTempBufferSize) return 0;
    // Row-vector form: [x y 1] M = [x' y' w']. Invert M.
    double M[3][3] = {{p->a, p->b, p->vx}, {p->c, p->d, p->vy}, {p->tx, p->ty, p->v}}, I[3][3];
    double det = M[0][0] * (M[1][1] * M[2][2] - M[1][2] * M[2][1]) - M[0][1] * (M[1][0] * M[2][2] - M[1][2] * M[2][0]) +
                 M[0][2] * (M[1][0] * M[2][1] - M[1][1] * M[2][0]);
    if (det == 0 || det != det) return kvImageInvalidParameter;
    for (int r = 0; r < 3; r++)
        for (int c = 0; c < 3; c++) {
            int r1 = (c + 1) % 3, r2 = (c + 2) % 3, c1 = (r + 1) % 3, c2 = (r + 2) % 3;
            I[r][c] = (M[r1][c1] * M[r2][c2] - M[r1][c2] * M[r2][c1]) / det;
        }
    long sw = (long)src->width, sh = (long)src->height, dh = (long)dest->height;
    int outside = outside_mode(flags);
    float bg[4];
    background(f, color, bg);
    for (long y = 0; y < dh; y++)
        for (long x = 0; x < (long)dest->width; x++) {
            // Unlike the affine warps, vImage puts pixel centers at whole numbers here: the
            // bottom left pixel's center is the origin.
            double X1 = (double)x, Y1 = (double)(dh - 1 - y);
            double u = X1 * I[0][0] + Y1 * I[1][0] + I[2][0], v = X1 * I[0][1] + Y1 * I[1][1] + I[2][1],
                   w = X1 * I[0][2] + Y1 * I[1][2] + I[2][2];
            if (w == 0) {
                for (int c = 0; c < f.channels; c++) store(dest, f, x, y, c, bg[c]);
                continue;
            }
            double col = u / w, row = (double)(sh - 1) - v / w;
            if (interpolation == kvImageInterpolationNearest) {
                long ix = (long)floor(col + 0.5), iy = (long)floor(row + 0.5);
                int in = ix >= 0 && iy >= 0 && ix < sw && iy < sh;
                for (int c = 0; c < f.channels; c++)
                    store(dest, f, x, y, c, in || outside == OUTSIDE_EXTEND ? sample_at(src, f, ix, iy, c, outside, bg) : bg[c]);
                continue;
            }
            if (col < -1 || row < -1 || col > sw || row > sh) {
                if (outside == OUTSIDE_BACKGROUND) {
                    for (int c = 0; c < f.channels; c++) store(dest, f, x, y, c, bg[c]);
                    continue;
                }
            }
            long x0 = (long)floor(col), y0 = (long)floor(row);
            float fx = (float)(col - x0), fy = (float)(row - y0);
            for (int c = 0; c < f.channels; c++) {
                float top = sample_at(src, f, x0, y0, c, outside, bg) * (1 - fx) + sample_at(src, f, x0 + 1, y0, c, outside, bg) * fx;
                float bottom = sample_at(src, f, x0, y0 + 1, c, outside, bg) * (1 - fx) + sample_at(src, f, x0 + 1, y0 + 1, c, outside, bg) * fx;
                store(dest, f, x, y, c, top * (1 - fy) + bottom * fy);
            }
        }
    return kvImageNoError;
}

#define PERSPECTIVE(format, bgType, bgPointer) \
    vImage_Error vImagePerspectiveWarp_##format(const vImage_Buffer *src, const vImage_Buffer *dest, void *tempBuffer, \
                                                const vImage_PerpsectiveTransform *transform, vImage_WarpInterpolation interpolation, \
                                                bgType backColor, vImage_Flags flags) DARWIN_SYMBOL(vImagePerspectiveWarp_##format); \
    vImage_Error vImagePerspectiveWarp_##format(const vImage_Buffer *src, const vImage_Buffer *dest, void *tempBuffer, \
                                                const vImage_PerpsectiveTransform *transform, vImage_WarpInterpolation interpolation, \
                                                bgType backColor, vImage_Flags flags) { \
        return warp_perspective(src, dest, transform, interpolation, format, bgPointer, flags); \
    }

PERSPECTIVE(Planar8, Pixel_8, &backColor)
PERSPECTIVE(Planar16U, Pixel_16U, &backColor)
PERSPECTIVE(Planar16F, Pixel_16F, &backColor)
PERSPECTIVE(ARGB8888, const Pixel_8888, backColor)
PERSPECTIVE(ARGB16U, const Pixel_ARGB_16U, backColor)
PERSPECTIVE(ARGB16F, const Pixel_ARGB_16F, backColor)
