// vImage convolution: general kernels (integer with a divisor, or float, with
// or without a bias), one kernel per channel, separable kernels, and the box
// and tent blurs, for 8-bit, float and half-float pixels.
//
// Kernels are applied as a correlation: kernel[i][j] weighs the source pixel
// i - height/2 rows and j - width/2 columns from the one under the kernel's
// center. Where the kernel hangs off the source image, the edge mode decides:
// kvImageCopyInPlace copies the source pixel, kvImageBackgroundColorFill reads
// the background color outside, kvImageEdgeExtend repeats the nearest edge
// pixel and kvImageTruncateKernel drops the outside weights and scales the sum
// back up by total weight / weight used.
//
// Integer kernels give (sum + bias) / divisor, rounded down, where the plain
// (bias-less) functions use divisor / 2 as the bias so the result rounds to
// nearest. Float kernels on 8-bit pixels round sum + bias to nearest.

#include "vimage.h"

#include <math.h>

enum { PIX8, PIXF, PIX16F };
enum { EDGE_COPY, EDGE_BACKGROUND, EDGE_EXTEND, EDGE_TRUNCATE };

typedef struct {
    int type, channels;
    int leaveAlpha;
    int edge;
    long kh, kw;
    const double *kernel[4];      // kh * kw weights per channel (general kernels)
    const double *kx, *ky;        // or a separable kernel shared by all channels
    double total[4];              // the sum of each channel's weights
    double bias[4];
    double divisor[4];            // 0 for float kernels
    double background[4];
} Convolution;

static double load(const vImage_Buffer *b, int type, int channels, long x, long y, int c) {
    const uint8_t *row = (const uint8_t *)b->data + y * b->rowBytes;
    switch (type) {
    case PIX8: return row[x * channels + c];
    case PIXF: return ((const float *)row)[x * channels + c];
    default: return vimage_half_to_float(((const uint16_t *)row)[x * channels + c]);
    }
}

static void store(const vImage_Buffer *b, int type, int channels, long x, long y, int c, double v) {
    uint8_t *row = (uint8_t *)b->data + y * b->rowBytes;
    switch (type) {
    case PIX8: row[x * channels + c] = (uint8_t)(v <= 0 ? 0 : v >= 255 ? 255 : v); break;
    case PIXF: ((float *)row)[x * channels + c] = (float)v; break;
    default: ((uint16_t *)row)[x * channels + c] = vimage_float_to_half((float)v); break;
    }
}

/// The finished value of one channel from its weighted sum.
static double finish(const Convolution *job, int c, double sum) {
    if (job->divisor[c] != 0) return floor((sum + job->bias[c]) / job->divisor[c]);
    if (job->type == PIX8) return floor(sum + job->bias[c] + 0.5);
    return sum + job->bias[c];
}

static vImage_Error edge_mode(vImage_Flags flags, int *edge) {
    int count = 0;
    if (flags & kvImageCopyInPlace) { *edge = EDGE_COPY; count++; }
    if (flags & kvImageBackgroundColorFill) { *edge = EDGE_BACKGROUND; count++; }
    if (flags & kvImageEdgeExtend) { *edge = EDGE_EXTEND; count++; }
    if (flags & kvImageTruncateKernel) { *edge = EDGE_TRUNCATE; count++; }
    return count == 1 ? kvImageNoError : kvImageInvalidEdgeStyle;
}

static vImage_Error convolution_check(const vImage_Buffer *src, const vImage_Buffer *dest, vImagePixelCount ox, vImagePixelCount oy,
                                      long kh, long kw) {
    if (!src || !dest || !src->data || !dest->data) return kvImageNullPointerArgument;
    if (ox > src->width) return kvImageInvalidOffset_X;
    if (oy > src->height) return kvImageInvalidOffset_Y;
    if (ox + dest->width > src->width || oy + dest->height > src->height) return kvImageRoiLargerThanInputBuffer;
    if (kh < 1 || kw < 1 || !(kh & 1) || !(kw & 1)) return kvImageInvalidKernelSize;
    return kvImageNoError;
}

static long clampl(long v, long limit) { return v < 0 ? 0 : v >= limit ? limit - 1 : v; }

/// Copies the source pixel under the kernel's center, for kvImageCopyInPlace
/// and the alpha of kvImageLeaveAlphaUnchanged.
static void copy_channel(const Convolution *job, const vImage_Buffer *src, const vImage_Buffer *dest, long x, long y, long sx, long sy, int c) {
    store(dest, job->type, job->channels, x, y, c, load(src, job->type, job->channels, sx, sy, c));
}

/// A general kernel per channel.
static vImage_Error convolve_general(const Convolution *job, const vImage_Buffer *src, const vImage_Buffer *dest, vImagePixelCount ox,
                                     vImagePixelCount oy) {
    long W = (long)src->width, H = (long)src->height, rx = job->kw / 2, ry = job->kh / 2;
    for (long y = 0; y < (long)dest->height; y++)
        for (long x = 0; x < (long)dest->width; x++) {
            long cx = x + (long)ox, cy = y + (long)oy;
            int inside = cx - rx >= 0 && cx + rx < W && cy - ry >= 0 && cy + ry < H;
            for (int c = 0; c < job->channels; c++) {
                if ((c == 0 && job->leaveAlpha) || (!inside && job->edge == EDGE_COPY)) {
                    copy_channel(job, src, dest, x, y, cx, cy, c);
                    continue;
                }
                const double *k = job->kernel[c];
                double sum = 0, used = 0;
                float sumF = 0;     // float kernels on 8-bit pixels add up in single precision, as vImage does
                for (long i = 0; i < job->kh; i++) {
                    long sy = cy + i - ry;
                    for (long j = 0; j < job->kw; j++) {
                        long sx = cx + j - rx;
                        double w = k[i * job->kw + j], v;
                        if (inside || (sx >= 0 && sx < W && sy >= 0 && sy < H)) v = load(src, job->type, job->channels, sx, sy, c);
                        else if (job->edge == EDGE_EXTEND) v = load(src, job->type, job->channels, clampl(sx, W), clampl(sy, H), c);
                        else if (job->edge == EDGE_BACKGROUND) v = job->background[c];
                        else continue;
                        sum += w * v;
                        sumF += (float)w * (float)v;
                        used += w;
                    }
                }
                if (job->type == PIX8 && job->divisor[c] == 0) sum = sumF;
                if (!inside && job->edge == EDGE_TRUNCATE && used != 0) sum = sum * job->total[c] / used;
                store(dest, job->type, job->channels, x, y, c, finish(job, c, sum));
            }
        }
    return kvImageNoError;
}

/// A separable kernel: a horizontal pass over every source row the result
/// needs, then a vertical pass over those rows.
static vImage_Error convolve_separable(const Convolution *job, const vImage_Buffer *src, const vImage_Buffer *dest, vImagePixelCount ox,
                                       vImagePixelCount oy) {
    long W = (long)src->width, H = (long)src->height, rx = job->kw / 2, ry = job->kh / 2;
    long dw = (long)dest->width, dh = (long)dest->height, ch = job->channels;
    if (!dw || !dh) return kvImageNoError;
    long first = (long)oy - ry, rows = dh + 2 * ry;     // source rows first ... first + rows - 1, some outside
    double sumX = 0, sumY = 0;
    for (long j = 0; j < job->kw; j++) sumX += job->kx[j];
    for (long i = 0; i < job->kh; i++) sumY += job->ky[i];
    double *across = malloc(sizeof(double) * (size_t)(rows * dw * ch)), *usedX = malloc(sizeof(double) * (size_t)dw);
    if (!across || !usedX) { free(across); free(usedX); return kvImageMemoryAllocationError; }
    for (long x = 0; x < dw; x++) {
        long cx = x + (long)ox;
        double used = 0;
        for (long j = 0; j < job->kw; j++) {
            long sx = cx + j - rx;
            if (sx >= 0 && sx < W) used += job->kx[j];
        }
        usedX[x] = used;
    }
    for (long r = 0; r < rows; r++) {
        long sy = first + r;
        double *out = across + r * dw * ch;
        if (sy < 0 || sy >= H) {
            if (job->edge == EDGE_EXTEND) sy = clampl(sy, H);
            else {
                // Only the background mode reads these rows.
                for (long x = 0; x < dw; x++)
                    for (long c = 0; c < ch; c++) out[x * ch + c] = job->background[c] * sumX;
                continue;
            }
        }
        for (long x = 0; x < dw; x++) {
            long cx = x + (long)ox;
            int inside = cx - rx >= 0 && cx + rx < W;
            for (long c = 0; c < ch; c++) {
                double sum = 0;
                for (long j = 0; j < job->kw; j++) {
                    long sx = cx + j - rx;
                    double v;
                    if (inside || (sx >= 0 && sx < W)) v = load(src, job->type, (int)ch, sx, sy, (int)c);
                    else if (job->edge == EDGE_EXTEND) v = load(src, job->type, (int)ch, clampl(sx, W), sy, (int)c);
                    else if (job->edge == EDGE_BACKGROUND) v = job->background[c];
                    else continue;
                    sum += job->kx[j] * v;
                }
                out[x * ch + c] = sum;
            }
        }
    }
    for (long y = 0; y < dh; y++) {
        long cy = y + (long)oy;
        int insideY = cy - ry >= 0 && cy + ry < H;
        double usedY = 0;
        for (long i = 0; i < job->kh; i++) {
            long sy = cy + i - ry;
            if (sy >= 0 && sy < H) usedY += job->ky[i];
        }
        for (long x = 0; x < dw; x++) {
            long cx = x + (long)ox;
            int inside = insideY && cx - rx >= 0 && cx + rx < W;
            for (long c = 0; c < ch; c++) {
                if ((c == 0 && job->leaveAlpha) || (!inside && job->edge == EDGE_COPY)) {
                    copy_channel(job, src, dest, x, y, cx, cy, (int)c);
                    continue;
                }
                double sum = 0;
                for (long i = 0; i < job->kh; i++) {
                    long sy = cy + i - ry;
                    if (job->edge == EDGE_TRUNCATE && (sy < 0 || sy >= H)) continue;
                    sum += job->ky[i] * across[((y + i) * dw + x) * ch + c];
                }
                if (!inside && job->edge == EDGE_TRUNCATE) {
                    double used = usedX[x] * usedY;
                    if (used != 0) sum = sum * (sumX * sumY) / used;
                }
                store(dest, job->type, (int)ch, x, y, (int)c, finish(job, (int)c, sum));
            }
        }
    }
    free(across);
    free(usedX);
    return kvImageNoError;
}

/// Sets up the parts of a job every function shares and runs it.
static vImage_Error run(Convolution *job, const vImage_Buffer *src, const vImage_Buffer *dest, vImagePixelCount ox, vImagePixelCount oy,
                        vImage_Flags flags) {
    vImage_Error error = convolution_check(src, dest, ox, oy, job->kh, job->kw);
    if (error) return error;
    if ((error = edge_mode(flags, &job->edge))) return error;
    if (flags & kvImageGetTempBufferSize) return 0;
    job->leaveAlpha = job->channels == 4 && (flags & kvImageLeaveAlphaUnchanged);
    return job->kx ? convolve_separable(job, src, dest, ox, oy) : convolve_general(job, src, dest, ox, oy);
}

static void set_background8(Convolution *job, const uint8_t *bg, int channels) {
    for (int c = 0; c < channels; c++) job->background[c] = bg ? bg[c] : 0;
}

static void set_backgroundF(Convolution *job, const float *bg, int channels) {
    for (int c = 0; c < channels; c++) job->background[c] = bg ? bg[c] : 0;
}

static void set_background16F(Convolution *job, const uint16_t *bg, int channels) {
    for (int c = 0; c < channels; c++) job->background[c] = bg ? vimage_half_to_float(bg[c]) : 0;
}

/// Integer kernels: one per channel (the same one, except for the
/// multi-kernel function), with a divisor and bias each.
static vImage_Error convolve_integer(const vImage_Buffer *src, const vImage_Buffer *dest, vImagePixelCount ox, vImagePixelCount oy,
                                     const int16_t *const kernels[4], uint32_t kh, uint32_t kw, const int32_t divisors[4],
                                     const int32_t biases[4], const uint8_t *bg, int channels, vImage_Flags flags) {
    Convolution job = {.type = PIX8, .channels = channels, .kh = kh, .kw = kw};
    for (int c = 0; c < channels; c++)
        if (!kernels[c]) return kvImageNullPointerArgument;
    size_t n = (size_t)kh * kw;
    double *weights = malloc(sizeof(double) * (n * (size_t)channels + 1));
    if (!weights) return kvImageMemoryAllocationError;
    for (int c = 0; c < channels; c++) {
        double *k = weights + n * (size_t)c, total = 0;
        for (size_t i = 0; i < n; i++) total += k[i] = kernels[c][i];
        job.kernel[c] = k;
        job.total[c] = total;
        job.divisor[c] = divisors[c] ? divisors[c] : 1;
        job.bias[c] = biases[c];
    }
    set_background8(&job, bg, channels);
    vImage_Error error = run(&job, src, dest, ox, oy, flags);
    free(weights);
    return error;
}

/// One float kernel for every channel.
static vImage_Error convolve_float(const vImage_Buffer *src, const vImage_Buffer *dest, vImagePixelCount ox, vImagePixelCount oy,
                                   const float *kernel, uint32_t kh, uint32_t kw, float bias, int type, int channels, Convolution *job,
                                   vImage_Flags flags) {
    if (!kernel) return kvImageNullPointerArgument;
    size_t n = (size_t)kh * kw;
    double *weights = malloc(sizeof(double) * (n + 1)), total = 0;
    if (!weights) return kvImageMemoryAllocationError;
    for (size_t i = 0; i < n; i++) total += weights[i] = kernel[i];
    job->type = type;
    job->channels = channels;
    job->kh = kh;
    job->kw = kw;
    for (int c = 0; c < channels; c++) {
        job->kernel[c] = weights;
        job->total[c] = total;
        job->bias[c] = bias;
    }
    vImage_Error error = run(job, src, dest, ox, oy, flags);
    free(weights);
    return error;
}

#define CONVOLUTION_ARGS \
    const vImage_Buffer *src, const vImage_Buffer *dest, void *tempBuffer, vImagePixelCount srcOffsetToROI_X, vImagePixelCount srcOffsetToROI_Y

vImage_Error vImageConvolve_Planar8(CONVOLUTION_ARGS, const int16_t *kernel, uint32_t kernel_height, uint32_t kernel_width, int32_t divisor,
                                    Pixel_8 backgroundColor, vImage_Flags flags) DARWIN_SYMBOL(vImageConvolve_Planar8);
vImage_Error vImageConvolve_Planar8(CONVOLUTION_ARGS, const int16_t *kernel, uint32_t kernel_height, uint32_t kernel_width, int32_t divisor,
                                    Pixel_8 backgroundColor, vImage_Flags flags) {
    const int16_t *kernels[4] = {kernel};
    int32_t divisors[4] = {divisor}, biases[4] = {divisor / 2};
    return convolve_integer(src, dest, srcOffsetToROI_X, srcOffsetToROI_Y, kernels, kernel_height, kernel_width, divisors, biases,
                            &backgroundColor, 1, flags);
}

vImage_Error vImageConvolveWithBias_Planar8(CONVOLUTION_ARGS, const int16_t *kernel, uint32_t kernel_height, uint32_t kernel_width,
                                            int32_t divisor, int32_t bias, Pixel_8 backgroundColor, vImage_Flags flags)
    DARWIN_SYMBOL(vImageConvolveWithBias_Planar8);
vImage_Error vImageConvolveWithBias_Planar8(CONVOLUTION_ARGS, const int16_t *kernel, uint32_t kernel_height, uint32_t kernel_width,
                                            int32_t divisor, int32_t bias, Pixel_8 backgroundColor, vImage_Flags flags) {
    const int16_t *kernels[4] = {kernel};
    int32_t divisors[4] = {divisor}, biases[4] = {bias};
    return convolve_integer(src, dest, srcOffsetToROI_X, srcOffsetToROI_Y, kernels, kernel_height, kernel_width, divisors, biases,
                            &backgroundColor, 1, flags);
}

vImage_Error vImageConvolve_ARGB8888(CONVOLUTION_ARGS, const int16_t *kernel, uint32_t kernel_height, uint32_t kernel_width, int32_t divisor,
                                     const Pixel_8888 backgroundColor, vImage_Flags flags) DARWIN_SYMBOL(vImageConvolve_ARGB8888);
vImage_Error vImageConvolve_ARGB8888(CONVOLUTION_ARGS, const int16_t *kernel, uint32_t kernel_height, uint32_t kernel_width, int32_t divisor,
                                     const Pixel_8888 backgroundColor, vImage_Flags flags) {
    const int16_t *kernels[4] = {kernel, kernel, kernel, kernel};
    int32_t divisors[4] = {divisor, divisor, divisor, divisor}, b = divisor / 2, biases[4] = {b, b, b, b};
    return convolve_integer(src, dest, srcOffsetToROI_X, srcOffsetToROI_Y, kernels, kernel_height, kernel_width, divisors, biases,
                            backgroundColor, 4, flags);
}

vImage_Error vImageConvolveWithBias_ARGB8888(CONVOLUTION_ARGS, const int16_t *kernel, uint32_t kernel_height, uint32_t kernel_width,
                                             int32_t divisor, int32_t bias, const Pixel_8888 backgroundColor, vImage_Flags flags)
    DARWIN_SYMBOL(vImageConvolveWithBias_ARGB8888);
vImage_Error vImageConvolveWithBias_ARGB8888(CONVOLUTION_ARGS, const int16_t *kernel, uint32_t kernel_height, uint32_t kernel_width,
                                             int32_t divisor, int32_t bias, const Pixel_8888 backgroundColor, vImage_Flags flags) {
    const int16_t *kernels[4] = {kernel, kernel, kernel, kernel};
    int32_t divisors[4] = {divisor, divisor, divisor, divisor}, biases[4] = {bias, bias, bias, bias};
    return convolve_integer(src, dest, srcOffsetToROI_X, srcOffsetToROI_Y, kernels, kernel_height, kernel_width, divisors, biases,
                            backgroundColor, 4, flags);
}

vImage_Error vImageConvolveMultiKernel_ARGB8888(CONVOLUTION_ARGS, const int16_t *kernels[4], uint32_t kernel_height, uint32_t kernel_width,
                                                const int32_t divisors[4], const int32_t biases[4], const Pixel_8888 backgroundColor,
                                                vImage_Flags flags) DARWIN_SYMBOL(vImageConvolveMultiKernel_ARGB8888);
vImage_Error vImageConvolveMultiKernel_ARGB8888(CONVOLUTION_ARGS, const int16_t *kernels[4], uint32_t kernel_height, uint32_t kernel_width,
                                                const int32_t divisors[4], const int32_t biases[4], const Pixel_8888 backgroundColor,
                                                vImage_Flags flags) {
    if (!kernels || !divisors || !biases) return kvImageNullPointerArgument;
    return convolve_integer(src, dest, srcOffsetToROI_X, srcOffsetToROI_Y, (const int16_t *const *)kernels, kernel_height, kernel_width,
                            divisors, biases, backgroundColor, 4, flags);
}

vImage_Error vImageConvolveFloatKernel_ARGB8888(CONVOLUTION_ARGS, const float *kernel, uint32_t kernelHeight, uint32_t kernelWidth,
                                                float bias, const Pixel_8888 backgroundColor, vImage_Flags flags)
    DARWIN_SYMBOL(vImageConvolveFloatKernel_ARGB8888);
vImage_Error vImageConvolveFloatKernel_ARGB8888(CONVOLUTION_ARGS, const float *kernel, uint32_t kernelHeight, uint32_t kernelWidth,
                                                float bias, const Pixel_8888 backgroundColor, vImage_Flags flags) {
    if (flags & kvImageLeaveAlphaUnchanged) return kvImageUnknownFlagsBit;  // as vImage: this one filters alpha always
    Convolution job = {0};
    set_background8(&job, backgroundColor, 4);
    return convolve_float(src, dest, srcOffsetToROI_X, srcOffsetToROI_Y, kernel, kernelHeight, kernelWidth, bias, PIX8, 4, &job, flags);
}

/// The float-kernel functions for float and half-float pixels: with a bias
/// argument (name##WithBias) and without.
#define FLOAT_CONVOLVE(format, type, channels, bgType, setBackground, bgPointer) \
    vImage_Error vImageConvolve_##format(CONVOLUTION_ARGS, const float *kernel, uint32_t kernel_height, uint32_t kernel_width, \
                                         bgType backgroundColor, vImage_Flags flags) DARWIN_SYMBOL(vImageConvolve_##format); \
    vImage_Error vImageConvolve_##format(CONVOLUTION_ARGS, const float *kernel, uint32_t kernel_height, uint32_t kernel_width, \
                                         bgType backgroundColor, vImage_Flags flags) { \
        Convolution job = {0}; \
        setBackground(&job, bgPointer, channels); \
        return convolve_float(src, dest, srcOffsetToROI_X, srcOffsetToROI_Y, kernel, kernel_height, kernel_width, 0, type, channels, &job, \
                              flags); \
    } \
    vImage_Error vImageConvolveWithBias_##format(CONVOLUTION_ARGS, const float *kernel, uint32_t kernel_height, uint32_t kernel_width, \
                                                 float bias, bgType backgroundColor, vImage_Flags flags) \
        DARWIN_SYMBOL(vImageConvolveWithBias_##format); \
    vImage_Error vImageConvolveWithBias_##format(CONVOLUTION_ARGS, const float *kernel, uint32_t kernel_height, uint32_t kernel_width, \
                                                 float bias, bgType backgroundColor, vImage_Flags flags) { \
        Convolution job = {0}; \
        setBackground(&job, bgPointer, channels); \
        return convolve_float(src, dest, srcOffsetToROI_X, srcOffsetToROI_Y, kernel, kernel_height, kernel_width, bias, type, channels, \
                              &job, flags); \
    }

FLOAT_CONVOLVE(PlanarF, PIXF, 1, Pixel_F, set_backgroundF, &backgroundColor)
FLOAT_CONVOLVE(ARGBFFFF, PIXF, 4, const Pixel_FFFF, set_backgroundF, backgroundColor)
FLOAT_CONVOLVE(Planar16F, PIX16F, 1, Pixel_16F, set_background16F, &backgroundColor)
FLOAT_CONVOLVE(ARGB16F, PIX16F, 4, const Pixel_ARGB_16F, set_background16F, backgroundColor)

/// A separable float kernel: kernelX across, kernelY down.
static vImage_Error convolve_separable_float(const vImage_Buffer *src, const vImage_Buffer *dest, vImagePixelCount ox, vImagePixelCount oy,
                                             const float *kernelX, uint32_t kxw, const float *kernelY, uint32_t kyw, float bias, int type,
                                             int channels, Convolution *job, vImage_Flags flags) {
    if (!kernelX || !kernelY) return kvImageNullPointerArgument;
    double *weights = malloc(sizeof(double) * ((size_t)kxw + kyw + 1));
    if (!weights) return kvImageMemoryAllocationError;
    for (uint32_t i = 0; i < kxw; i++) weights[i] = kernelX[i];
    for (uint32_t i = 0; i < kyw; i++) weights[kxw + i] = kernelY[i];
    job->type = type;
    job->channels = channels;
    job->kw = kxw;
    job->kh = kyw;
    job->kx = weights;
    job->ky = weights + kxw;
    for (int c = 0; c < channels; c++) job->bias[c] = bias;
    vImage_Error error = run(job, src, dest, ox, oy, flags);
    free(weights);
    return error;
}

#define SEPARABLE_ARGS \
    CONVOLUTION_ARGS, const float *kernelX, uint32_t kernelX_width, const float *kernelY, uint32_t kernelY_width, float bias

vImage_Error vImageSepConvolve_Planar8(SEPARABLE_ARGS, Pixel_16U backgroundColor, vImage_Flags flags) DARWIN_SYMBOL(vImageSepConvolve_Planar8);
vImage_Error vImageSepConvolve_Planar8(SEPARABLE_ARGS, Pixel_16U backgroundColor, vImage_Flags flags) {
    Convolution job = {0};
    job.background[0] = backgroundColor;
    return convolve_separable_float(src, dest, srcOffsetToROI_X, srcOffsetToROI_Y, kernelX, kernelX_width, kernelY, kernelY_width, bias,
                                    PIX8, 1, &job, flags);
}

vImage_Error vImageSepConvolve_ARGB8888(SEPARABLE_ARGS, const Pixel_8888 backgroundColor, vImage_Flags flags)
    DARWIN_SYMBOL(vImageSepConvolve_ARGB8888);
vImage_Error vImageSepConvolve_ARGB8888(SEPARABLE_ARGS, const Pixel_8888 backgroundColor, vImage_Flags flags) {
    // vImage refuses a truncated kernel here and filters alpha whatever the flags say.
    if (flags & kvImageTruncateKernel) return kvImageUnknownFlagsBit;
    flags &= ~(vImage_Flags)kvImageLeaveAlphaUnchanged;
    Convolution job = {0};
    set_background8(&job, backgroundColor, 4);
    return convolve_separable_float(src, dest, srcOffsetToROI_X, srcOffsetToROI_Y, kernelX, kernelX_width, kernelY, kernelY_width, bias,
                                    PIX8, 4, &job, flags);
}

vImage_Error vImageSepConvolve_PlanarF(SEPARABLE_ARGS, Pixel_F backgroundColor, vImage_Flags flags) DARWIN_SYMBOL(vImageSepConvolve_PlanarF);
vImage_Error vImageSepConvolve_PlanarF(SEPARABLE_ARGS, Pixel_F backgroundColor, vImage_Flags flags) {
    Convolution job = {0};
    job.background[0] = backgroundColor;
    return convolve_separable_float(src, dest, srcOffsetToROI_X, srcOffsetToROI_Y, kernelX, kernelX_width, kernelY, kernelY_width, bias,
                                    PIXF, 1, &job, flags);
}

vImage_Error vImageSepConvolve_Planar16F(SEPARABLE_ARGS, Pixel_16F backgroundColor, vImage_Flags flags)
    DARWIN_SYMBOL(vImageSepConvolve_Planar16F);
vImage_Error vImageSepConvolve_Planar16F(SEPARABLE_ARGS, Pixel_16F backgroundColor, vImage_Flags flags) {
    Convolution job = {0};
    job.background[0] = vimage_half_to_float(backgroundColor);
    return convolve_separable_float(src, dest, srcOffsetToROI_X, srcOffsetToROI_Y, kernelX, kernelX_width, kernelY, kernelY_width, bias,
                                    PIX16F, 1, &job, flags);
}

/// Box (every weight 1) and tent (weights rising to the center and falling
/// again, across and down) blurs, divided by the total weight and rounded.
static vImage_Error convolve_blur(const vImage_Buffer *src, const vImage_Buffer *dest, vImagePixelCount ox, vImagePixelCount oy, uint32_t kh,
                                  uint32_t kw, const uint8_t *bg, int channels, int tent, vImage_Flags flags) {
    if (!(kh & 1) || !(kw & 1)) return kvImageInvalidKernelSize;
    double *weights = malloc(sizeof(double) * ((size_t)kw + kh + 1)), sumX = 0, sumY = 0;
    if (!weights) return kvImageMemoryAllocationError;
    for (uint32_t i = 0; i < kw; i++) sumX += weights[i] = tent ? (double)(kw / 2 + 1) - fabs((double)i - kw / 2) : 1;
    for (uint32_t i = 0; i < kh; i++) sumY += weights[kw + i] = tent ? (double)(kh / 2 + 1) - fabs((double)i - kh / 2) : 1;
    Convolution job = {.type = PIX8, .channels = channels, .kw = kw, .kh = kh, .kx = weights, .ky = weights + kw};
    for (int c = 0; c < channels; c++) {
        job.divisor[c] = sumX * sumY;
        job.bias[c] = sumX * sumY / 2;  // exactly half, so truncated kernels round to nearest too
    }
    set_background8(&job, bg, channels);
    vImage_Error error = run(&job, src, dest, ox, oy, flags);
    free(weights);
    return error;
}

#define BLUR(name, tent) \
    vImage_Error name##_Planar8(CONVOLUTION_ARGS, uint32_t kernel_height, uint32_t kernel_width, Pixel_8 backgroundColor, vImage_Flags flags) \
        DARWIN_SYMBOL(name##_Planar8); \
    vImage_Error name##_Planar8(CONVOLUTION_ARGS, uint32_t kernel_height, uint32_t kernel_width, Pixel_8 backgroundColor, vImage_Flags flags) { \
        return convolve_blur(src, dest, srcOffsetToROI_X, srcOffsetToROI_Y, kernel_height, kernel_width, &backgroundColor, 1, tent, flags); \
    } \
    vImage_Error name##_ARGB8888(CONVOLUTION_ARGS, uint32_t kernel_height, uint32_t kernel_width, const Pixel_8888 backgroundColor, \
                                 vImage_Flags flags) DARWIN_SYMBOL(name##_ARGB8888); \
    vImage_Error name##_ARGB8888(CONVOLUTION_ARGS, uint32_t kernel_height, uint32_t kernel_width, const Pixel_8888 backgroundColor, \
                                 vImage_Flags flags) { \
        return convolve_blur(src, dest, srcOffsetToROI_X, srcOffsetToROI_Y, kernel_height, kernel_width, backgroundColor, 4, tent, flags); \
    }

BLUR(vImageBoxConvolve, 0)
BLUR(vImageTentConvolve, 1)
