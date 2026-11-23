// BNNS filters: layer objects created from parameter structures and applied
// to batches. A filter is a plain heap object (not an Objective-C object).
// Without BNNSFlagsUseClientPtr, weights and other constant arrays are copied
// at creation; with it, the caller's arrays are read at every apply.
//
// Images are seen in memory order (width, height, channels); per-sample
// descriptors come with element strides between batch items.

#include "bnns.h"

#include <float.h>
#include <math.h>

enum {
    BNNS_KIND_CONVOLUTION = 1, BNNS_KIND_TRANSPOSED_CONVOLUTION, BNNS_KIND_FULLY_CONNECTED, BNNS_KIND_POOLING,
    BNNS_KIND_ACTIVATION, BNNS_KIND_LOSS, BNNS_KIND_NORMALIZATION, BNNS_KIND_ARITHMETIC, BNNS_KIND_PERMUTE,
    BNNS_KIND_DROPOUT, BNNS_KIND_PADDING, BNNS_KIND_BROADCAST_MATMUL, BNNS_KIND_GRAM, BNNS_KIND_RESIZE,
    BNNS_KIND_REDUCTION, BNNS_KIND_EMBEDDING, BNNS_KIND_FUSED, BNNS_KIND_QUANTIZATION,
};

#define BNNS_FILTER_MAGIC 0x424E4E53u
#define BNNS_MAX_OWNED 8

typedef struct bnns_filter {
    uint32_t magic;
    int kind;
    uint32_t flags;
    BNNSFree free_memory;
    BNNSFilterParameters fp;
    void *owned[BNNS_MAX_OWNED];
    int nowned;
    union {
        BNNSLayerParametersConvolution conv;
        BNNSLayerParametersFullyConnected fc;
        BNNSLayerParametersPooling pool;
        BNNSLayerParametersActivation act;
        BNNSLayerParametersLossYolo loss; // the largest loss structure; others are prefixes
        BNNSLayerParametersNormalization norm;
        BNNSLayerParametersPermute permute;
        BNNSLayerParametersDropout dropout;
        BNNSLayerParametersPadding pad;
        BNNSLayerParametersBroadcastMatMul bmm;
        BNNSLayerParametersGram gram;
        BNNSLayerParametersResize resize;
        BNNSLayerParametersReduction reduce;
        BNNSLayerParametersEmbedding embed;
        BNNSLayerParametersQuantization quant;
    } p;
    // Normalization
    BNNSFilterType norm_type;
    float *cache_x;      // forward input of the last training apply (dense, batch-major)
    size_t cache_batch;
    // Arithmetic
    BNNSArithmeticFunction arith_fn;
    int arith_n;
    BNNSNDArrayDescriptor arith_in[3], arith_out;
    BNNSDescriptorType arith_type[3];
    BNNSActivation arith_act;
    // Dropout
    uint64_t rng[4];
    uint8_t *mask;
    size_t mask_count;
    // Fused
    struct bnns_filter *sub[2];
} bnns_filter;

static bnns_filter *bnns_filter_new(int kind, const BNNSFilterParameters *fp) {
    bnns_filter *f = bnns_alloc(fp, sizeof *f);
    if (!f) return NULL;
    f->magic = BNNS_FILTER_MAGIC;
    f->kind = kind;
    if (fp) { f->fp = *fp; f->flags = fp->flags; }
    f->free_memory = fp && fp->alloc_memory ? fp->free_memory : NULL;
    return f;
}

static bnns_filter *bnns_filter_get(BNNSFilter filter) {
    bnns_filter *f = filter;
    return f && f->magic == BNNS_FILTER_MAGIC ? f : NULL;
}

// Points d at a private copy of its data unless the filter uses client pointers.
static int bnns_own(bnns_filter *f, BNNSNDArrayDescriptor *d) {
    if (!d->data || (f->flags & BNNSFlagsUseClientPtr)) return 0;
    size_t bytes = BNNSNDArrayGetDataSize(d);
    if (!bytes || f->nowned == BNNS_MAX_OWNED) return -1;
    void *copy = bnns_alloc(&f->fp, bytes);
    if (!copy) return -1;
    memcpy(copy, d->data, bytes);
    f->owned[f->nowned++] = copy;
    d->data = copy;
    return 0;
}

void BNNSFilterDestroy(BNNSFilter filter) {
    bnns_filter *f = bnns_filter_get(filter);
    if (!f) return;
    for (int k = 0; k < f->nowned; k++) bnns_release(f->free_memory, f->owned[k]);
    free(f->cache_x);
    free(f->mask);
    for (int k = 0; k < 2; k++) BNNSFilterDestroy(f->sub[k]);
    f->magic = 0;
    bnns_release(f->free_memory, f);
}

static float *bnns_rd(const BNNSNDArrayDescriptor *d, const void *base, size_t b, size_t stride, bool phys) {
    const void *p = bnns_offset(d, base, b, stride);
    return phys ? bnns_read_phys(d, p) : bnns_read(d, p);
}

static void *bnns_zalloc_f(size_t n) { return calloc(n ? n : 1, sizeof(float)); }

static bool bnns_is_identity(const BNNSActivation *a) { return a->function == BNNSActivationFunctionIdentity; }

// Image geometry in memory order: width, height, channels (rank 1: channels only).
typedef struct { size_t w, h, c; } bnns_image;

static int bnns_image_of(const BNNSNDArrayDescriptor *d, bnns_image *im) {
    bnns_shape sh;
    if (bnns_shape_phys(d, &sh)) return -1;
    if (sh.rank == 1) { im->w = 1; im->h = 1; im->c = sh.n[0]; return 0; }
    if (sh.rank == 2) { im->w = sh.n[0]; im->h = 1; im->c = sh.n[1]; return 0; }
    im->w = sh.n[0]; im->h = sh.n[1]; im->c = sh.n[2];
    for (int k = 3; k < sh.rank; k++) im->c *= sh.n[k];
    return 0;
}

static float *bnns_bias_values(const BNNSNDArrayDescriptor *bias, size_t n) {
    float *b = bias && bias->data ? bnns_read_phys(bias, NULL) : NULL;
    if (b && bnns_count(bias) < n) { free(b); return NULL; }
    if (!b) b = bnns_zalloc_f(n);
    return b;
}

// Activation over output samples (dense in o's physical order, batch-major).
static int bnns_out_activate(const BNNSActivation *a, const BNNSNDArrayDescriptor *o, float *y, size_t batch) {
    if (bnns_is_identity(a)) return 0;
    bnns_shape sh;
    if (bnns_shape_phys(o, &sh)) return -1;
    return bnns_activate(a, 0, &sh, y, batch);
}

static int bnns_out_activate_backward(const BNNSActivation *a, const BNNSNDArrayDescriptor *o, const float *pre, const float *y,
                                      float *dy, size_t batch) {
    if (bnns_is_identity(a)) return 0;
    bnns_shape sh;
    if (bnns_shape_phys(o, &sh)) return -1;
    return bnns_activate_backward(a, 0, &sh, pre, y, dy, batch);
}

// Reads batch samples of d (physical order) into one dense batch-major buffer.
static float *bnns_rd_batch(const BNNSNDArrayDescriptor *d, const void *base, size_t batch, size_t stride, size_t *per) {
    size_t n = bnns_count(d);
    if (per) *per = n;
    if (!base) return NULL;
    float *all = malloc((n * batch ? n * batch : 1) * sizeof(float));
    if (!all) return NULL;
    for (size_t b = 0; b < batch; b++) {
        float *t = bnns_rd(d, base, b, stride, true);
        if (!t) { free(all); return NULL; }
        memcpy(all + b * n, t, n * sizeof(float));
        free(t);
    }
    return all;
}

static int bnns_wr_batch(const BNNSNDArrayDescriptor *d, void *base, size_t batch, size_t stride, const float *all, bool delta) {
    size_t n = bnns_count(d);
    if (!base) return -1;
    for (size_t b = 0; b < batch; b++) {
        void *p = bnns_offset(d, base, b, stride);
        int r = delta ? bnns_write_delta_phys(d, p, all + b * n) : bnns_write_phys(d, p, all + b * n, false);
        if (r) return r;
    }
    return 0;
}

// The data a backward call gets for a gradient descriptor.
static void *bnns_delta_base(const BNNSNDArrayDescriptor *d) { return d ? d->data : NULL; }

// MARK: - Convolution

typedef struct {
    size_t kw, kh, ic, oc, groups, sx, sy, dx, dy, pl, pt;
    bnns_image in, out;
} bnns_conv_geom;

static int bnns_conv_geometry(const BNNSLayerParametersConvolution *p, bool transposed, bnns_conv_geom *g) {
    bnns_shape ws;
    if (bnns_image_of(&p->i_desc, &g->in) || bnns_image_of(&p->o_desc, &g->out) || bnns_shape_of(&p->w_desc, &ws) || ws.rank != 4) return -1;
    if (p->w_desc.layout == BNNSDataLayoutConvolutionWeightsOIHW_Pack32) return -1;
    // Apple takes the rotated-kernel layouts (OIHrWr, IOHrWr) only for transposed convolution.
    if (!transposed && (p->w_desc.layout == BNNSDataLayoutConvolutionWeightsOIHrWr ||
                        p->w_desc.layout == BNNSDataLayoutConvolutionWeightsIOHrWr)) return -1;
    g->kw = ws.n[0]; g->kh = ws.n[1];
    g->groups = p->groups > 1 ? p->groups : 1;
    bool io = p->w_desc.layout == BNNSDataLayoutConvolutionWeightsIOHrWr;
    size_t w_in = io ? ws.n[3] : ws.n[2], w_out = io ? ws.n[2] : ws.n[3];
    size_t cin = g->in.c, cout = g->out.c;
    if (cin % g->groups || cout % g->groups) return -1;
    // Weight dimensions: per-group input channels and all output channels (either may be given whole).
    g->ic = cin / g->groups; g->oc = cout;
    if (!((w_in == g->ic || w_in == cin) && (w_out == cout || w_out == cout / g->groups))) return -1;
    g->sx = p->x_stride ? p->x_stride : 1; g->sy = p->y_stride ? p->y_stride : 1;
    g->dx = p->x_dilation_stride > 1 ? p->x_dilation_stride : 1; g->dy = p->y_dilation_stride > 1 ? p->y_dilation_stride : 1;
    if (p->x_padding || p->y_padding) { g->pl = p->x_padding; g->pt = p->y_padding; }
    else { g->pl = p->pad[0]; g->pt = p->pad[2]; }
    (void)transposed;
    return 0;
}

// Dense weights [oc][ic per group][ky][kx] from any supported layout, or back.
static float *bnns_conv_weights(const BNNSNDArrayDescriptor *w, const bnns_conv_geom *g) {
    float *raw = bnns_read(w, NULL);
    if (!raw) return NULL;
    size_t kw = g->kw, kh = g->kh, ic = g->ic, oc = g->oc, n = kw * kh * ic * oc;
    if (bnns_count(w) != n) { free(raw); return NULL; }
    if (w->layout != BNNSDataLayoutConvolutionWeightsOIHrWr && w->layout != BNNSDataLayoutConvolutionWeightsIOHrWr) return raw;
    float *out = malloc(n * sizeof(float));
    if (!out) { free(raw); return NULL; }
    bool io = w->layout == BNNSDataLayoutConvolutionWeightsIOHrWr;
    for (size_t o = 0; o < oc; o++)
        for (size_t i = 0; i < ic; i++)
            for (size_t y = 0; y < kh; y++)
                for (size_t x = 0; x < kw; x++) {
                    size_t src = (kw - 1 - x) + kw * ((kh - 1 - y) + kh * (io ? o + oc * i : i + ic * o));
                    out[((o * ic + i) * kh + y) * kw + x] = raw[src];
                }
    free(raw);
    return out;
}

static int bnns_conv_weights_write(const BNNSNDArrayDescriptor *w, const bnns_conv_geom *g, const float *dense) {
    size_t kw = g->kw, kh = g->kh, ic = g->ic, oc = g->oc, n = kw * kh * ic * oc;
    if (w->layout != BNNSDataLayoutConvolutionWeightsOIHrWr && w->layout != BNNSDataLayoutConvolutionWeightsIOHrWr)
        return bnns_write_delta(w, NULL, dense);
    float *raw = malloc(n * sizeof(float));
    if (!raw) return -1;
    bool io = w->layout == BNNSDataLayoutConvolutionWeightsIOHrWr;
    for (size_t o = 0; o < oc; o++)
        for (size_t i = 0; i < ic; i++)
            for (size_t y = 0; y < kh; y++)
                for (size_t x = 0; x < kw; x++)
                    raw[(kw - 1 - x) + kw * ((kh - 1 - y) + kh * (io ? o + oc * i : i + ic * o))] = dense[((o * ic + i) * kh + y) * kw + x];
    int r = bnns_write_delta(w, NULL, raw);
    free(raw);
    return r;
}

// col[(c, ky, kx)][other pixel] = img[c][oy*sy + ky*dy - pt][ox*sx + kx*dx - pl] for channels c0..c0+nc.
static void bnns_im2col(const float *img, const bnns_image *im, size_t c0, size_t nc, size_t ow, size_t oh,
                        const bnns_conv_geom *g, float *col) {
    size_t np = ow * oh;
    for (size_t c = 0; c < nc; c++)
        for (size_t ky = 0; ky < g->kh; ky++)
            for (size_t kx = 0; kx < g->kw; kx++) {
                float *row = col + ((c * g->kh + ky) * g->kw + kx) * np;
                const float *plane = img + (c0 + c) * im->w * im->h;
                for (size_t oy = 0; oy < oh; oy++) {
                    long y = (long)(oy * g->sy + ky * g->dy) - (long)g->pt;
                    for (size_t ox = 0; ox < ow; ox++) {
                        long x = (long)(ox * g->sx + kx * g->dx) - (long)g->pl;
                        row[oy * ow + ox] = y >= 0 && y < (long)im->h && x >= 0 && x < (long)im->w ? plane[y * (long)im->w + x] : 0;
                    }
                }
            }
}

static void bnns_col2im(const float *col, float *img, const bnns_image *im, size_t c0, size_t nc, size_t ow, size_t oh,
                        const bnns_conv_geom *g) {
    size_t np = ow * oh;
    for (size_t c = 0; c < nc; c++)
        for (size_t ky = 0; ky < g->kh; ky++)
            for (size_t kx = 0; kx < g->kw; kx++) {
                const float *row = col + ((c * g->kh + ky) * g->kw + kx) * np;
                float *plane = img + (c0 + c) * im->w * im->h;
                for (size_t oy = 0; oy < oh; oy++) {
                    long y = (long)(oy * g->sy + ky * g->dy) - (long)g->pt;
                    if (y < 0 || y >= (long)im->h) continue;
                    for (size_t ox = 0; ox < ow; ox++) {
                        long x = (long)(ox * g->sx + kx * g->dx) - (long)g->pl;
                        if (x >= 0 && x < (long)im->w) plane[y * (long)im->w + x] += row[oy * ow + ox];
                    }
                }
            }
}

// Pre-activation output of a (transposed) convolution for one sample.
static int bnns_conv_forward_one(const BNNSLayerParametersConvolution *p, const bnns_conv_geom *g, bool transposed,
                                 const float *W, const float *bias, const float *x, float *y) {
    size_t G = g->groups, icg = g->ic, ocg = g->oc / G, K = g->kh * g->kw;
    if (!transposed) {
        size_t np = g->out.w * g->out.h;
        float *col = malloc((icg * K * np ? icg * K * np : 1) * sizeof(float));
        if (!col) return -1;
        for (size_t gi = 0; gi < G; gi++) {
            bnns_im2col(x, &g->in, gi * icg, icg, g->out.w, g->out.h, g, col);
            bnns_sgemm(false, false, (int)ocg, (int)np, (int)(icg * K), 1, W + gi * ocg * icg * K, (int)(icg * K), col, (int)np,
                       0, y + gi * ocg * np, (int)np);
        }
        free(col);
    } else {
        // The output image plays the input's role in the index mapping.
        size_t np = g->in.w * g->in.h;
        float *col = malloc((ocg * K * np ? ocg * K * np : 1) * sizeof(float));
        float *W2 = malloc((ocg * K * icg ? ocg * K * icg : 1) * sizeof(float));
        if (!col || !W2) { free(col); free(W2); return -1; }
        memset(y, 0, g->out.w * g->out.h * g->out.c * sizeof(float));
        for (size_t gi = 0; gi < G; gi++) {
            for (size_t o = 0; o < ocg; o++)
                for (size_t k = 0; k < K; k++)
                    for (size_t i = 0; i < icg; i++) W2[(o * K + k) * icg + i] = W[(((gi * ocg + o) * icg + i) * K) + k];
            bnns_sgemm(false, false, (int)(ocg * K), (int)np, (int)icg, 1, W2, (int)icg, x + gi * icg * np, (int)np, 0, col, (int)np);
            bnns_col2im(col, y, &g->out, gi * ocg, ocg, g->in.w, g->in.h, g);
        }
        free(col); free(W2);
    }
    size_t np = g->out.w * g->out.h;
    for (size_t c = 0; c < g->out.c; c++)
        for (size_t i = 0; i < np; i++) y[c * np + i] += bias[c];
    (void)p;
    return 0;
}

static int bnns_conv_apply(bnns_filter *f, size_t batch, const void *in, size_t in_stride, void *out, size_t out_stride, float *keep) {
    const BNNSLayerParametersConvolution *p = &f->p.conv;
    bool transposed = f->kind == BNNS_KIND_TRANSPOSED_CONVOLUTION;
    bnns_conv_geom g;
    if (bnns_conv_geometry(p, transposed, &g) || !in) return -1;
    float *W = bnns_conv_weights(&p->w_desc, &g), *bias = bnns_bias_values(&p->bias, g.out.c);
    size_t nin, nout = g.out.w * g.out.h * g.out.c;
    float *x = bnns_rd_batch(&p->i_desc, in, batch, in_stride, &nin), *y = bnns_zalloc_f(nout * batch);
    int r = -1;
    if (W && bias && x && y) {
        r = 0;
        for (size_t b = 0; b < batch && !r; b++) r = bnns_conv_forward_one(p, &g, transposed, W, bias, x + b * nin, y + b * nout);
        if (!r && keep) memcpy(keep, y, nout * batch * sizeof(float));
        if (!r) r = bnns_out_activate(&p->activation, &p->o_desc, y, batch);
        if (!r && out) r = bnns_wr_batch(&p->o_desc, out, batch, out_stride, y, false);
    }
    free(W); free(bias); free(x); free(y);
    return r;
}

// Pre-activation outputs, for backward passes with a fused activation.
static float *bnns_preactivation(bnns_filter *f, size_t batch, const void *in, size_t in_stride, size_t count);

static int bnns_conv_backward(bnns_filter *f, size_t batch, const void *in, size_t in_stride, BNNSNDArrayDescriptor *in_delta,
                              size_t in_delta_stride, const void *out, size_t out_stride, const BNNSNDArrayDescriptor *out_delta,
                              size_t out_delta_stride, BNNSNDArrayDescriptor *weights_delta, BNNSNDArrayDescriptor *bias_delta) {
    const BNNSLayerParametersConvolution *p = &f->p.conv;
    bool transposed = f->kind == BNNS_KIND_TRANSPOSED_CONVOLUTION;
    bnns_conv_geom g;
    if (bnns_conv_geometry(p, transposed, &g) || !out_delta) return -1;
    size_t G = g.groups, icg = g.ic, ocg = g.oc / G, K = g.kh * g.kw;
    size_t nin = g.in.w * g.in.h * g.in.c, nout = g.out.w * g.out.h * g.out.c;
    size_t npi = g.in.w * g.in.h, npo = g.out.w * g.out.h;
    float *dy = bnns_rd_batch(out_delta, bnns_delta_base(out_delta), batch, out_delta_stride, NULL);
    float *W = bnns_conv_weights(&p->w_desc, &g);
    float *x = in ? bnns_rd_batch(&p->i_desc, in, batch, in_stride, NULL) : NULL;
    float *pre = NULL, *y = NULL, *dx = NULL, *dW = NULL, *db = NULL, *col = NULL, *W2 = NULL;
    int r = -1;
    if (!dy || !W) goto done;
    if (!bnns_is_identity(&p->activation)) {
        pre = in ? bnns_preactivation(f, batch, in, in_stride, nout) : NULL;
        y = out ? bnns_rd_batch(&p->o_desc, out, batch, out_stride, NULL) : NULL;
        if (!pre && !y) goto done;
        if (bnns_out_activate_backward(&p->activation, &p->o_desc, pre, y, dy, batch)) goto done;
    }
    if ((weights_delta || (in_delta && transposed)) && !x) goto done;
    size_t colsize = transposed ? ocg * K * npi : icg * K * npo;
    col = bnns_zalloc_f(colsize);
    W2 = bnns_zalloc_f(ocg * K * icg);
    dx = in_delta ? bnns_zalloc_f(nin * batch) : NULL;
    dW = weights_delta ? bnns_zalloc_f(g.oc * icg * K) : NULL;
    db = bias_delta ? bnns_zalloc_f(g.out.c) : NULL;
    if (!col || !W2 || (in_delta && !dx) || (weights_delta && !dW) || (bias_delta && !db)) goto done;
    for (size_t b = 0; b < batch; b++) {
        const float *dyb = dy + b * nout, *xb = x ? x + b * nin : NULL;
        if (db) for (size_t c = 0; c < g.out.c; c++) for (size_t i = 0; i < npo; i++) db[c] += dyb[c * npo + i];
        for (size_t gi = 0; gi < G; gi++) {
            const float *Wg = W + gi * ocg * icg * K;
            if (!transposed) {
                if (dW) {
                    bnns_im2col(xb, &g.in, gi * icg, icg, g.out.w, g.out.h, &g, col);
                    bnns_sgemm(false, true, (int)ocg, (int)(icg * K), (int)npo, 1, dyb + gi * ocg * npo, (int)npo, col, (int)npo,
                               1, dW + gi * ocg * icg * K, (int)(icg * K));
                }
                if (dx) {
                    bnns_sgemm(true, false, (int)(icg * K), (int)npo, (int)ocg, 1, Wg, (int)(icg * K), dyb + gi * ocg * npo, (int)npo,
                               0, col, (int)npo);
                    bnns_col2im(col, dx + b * nin, &g.in, gi * icg, icg, g.out.w, g.out.h, &g);
                }
            } else {
                for (size_t o = 0; o < ocg; o++)
                    for (size_t k = 0; k < K; k++)
                        for (size_t i = 0; i < icg; i++) W2[(o * K + k) * icg + i] = Wg[(o * icg + i) * K + k];
                // dcol = im2col(dy) over the input's pixel grid.
                bnns_im2col(dyb, &g.out, gi * ocg, ocg, g.in.w, g.in.h, &g, col);
                if (dx)
                    bnns_sgemm(true, false, (int)icg, (int)npi, (int)(ocg * K), 1, W2, (int)icg, col, (int)npi,
                               0, dx + b * nin + gi * icg * npi, (int)npi);
                if (dW) {
                    float *dW2 = bnns_zalloc_f(ocg * K * icg);
                    if (!dW2) goto done;
                    bnns_sgemm(false, true, (int)(ocg * K), (int)icg, (int)npi, 1, col, (int)npi, xb + gi * icg * npi, (int)npi,
                               0, dW2, (int)icg);
                    for (size_t o = 0; o < ocg; o++)
                        for (size_t k = 0; k < K; k++)
                            for (size_t i = 0; i < icg; i++) dW[((gi * ocg + o) * icg + i) * K + k] += dW2[(o * K + k) * icg + i];
                    free(dW2);
                }
            }
        }
    }
    r = 0;
    if (dx) r = bnns_wr_batch(in_delta, in_delta->data, batch, in_delta_stride, dx, true);
    if (!r && dW) r = bnns_conv_weights_write(weights_delta, &g, dW);
    if (!r && db) r = bnns_write_delta_phys(bias_delta, NULL, db);
done:
    free(dy); free(W); free(x); free(pre); free(y); free(dx); free(dW); free(db); free(col); free(W2);
    return r;
}

static BNNSFilter bnns_create_conv(const BNNSLayerParametersConvolution *p, const BNNSFilterParameters *fp, bool transposed) {
    if (!p || !bnns_activation_supported(p->activation.function)) return NULL;
    bnns_conv_geom g;
    if (bnns_conv_geometry(p, transposed, &g) || !p->w_desc.data) return NULL;
    bnns_filter *f = bnns_filter_new(transposed ? BNNS_KIND_TRANSPOSED_CONVOLUTION : BNNS_KIND_CONVOLUTION, fp);
    if (!f) return NULL;
    f->p.conv = *p;
    if (bnns_own(f, &f->p.conv.w_desc) || bnns_own(f, &f->p.conv.bias)) { BNNSFilterDestroy(f); return NULL; }
    return f;
}

BNNSFilter BNNSFilterCreateLayerConvolution(const BNNSLayerParametersConvolution *p, const BNNSFilterParameters *fp) {
    return bnns_create_conv(p, fp, false);
}

BNNSFilter BNNSFilterCreateLayerTransposedConvolution(const BNNSLayerParametersConvolution *p, const BNNSFilterParameters *fp) {
    return bnns_create_conv(p, fp, true);
}

// MARK: - Fully connected

// Weights as an out x in row-major dense matrix.
static float *bnns_fc_weights(const BNNSNDArrayDescriptor *w, size_t nin, size_t nout, bool *transposed) {
    bnns_shape ws;
    if (bnns_shape_of(w, &ws) || ws.rank != 2) return NULL;
    size_t rows = ws.n[0], cols = ws.n[1];
    ptrdiff_t rs = ws.s[0], cs = ws.s[1];
    if (w->layout == BNNSDataLayoutRowMajorMatrix) { rows = ws.n[1]; cols = ws.n[0]; rs = ws.s[1]; cs = ws.s[0]; }
    bool t = false;
    if (!(rows == nout && cols == nin)) {
        if (rows == nin && cols == nout) t = true;
        else return NULL;
    }
    if (transposed) *transposed = t;
    float *W = malloc((nin * nout ? nin * nout : 1) * sizeof(float));
    if (!W) return NULL;
    for (size_t o = 0; o < nout; o++)
        for (size_t i = 0; i < nin; i++) {
            ptrdiff_t off = t ? (ptrdiff_t)i * rs + (ptrdiff_t)o * cs : (ptrdiff_t)o * rs + (ptrdiff_t)i * cs;
            W[o * nin + i] = (float)bnns_load(w, w->data, off);
        }
    return W;
}

static int bnns_fc_weights_write(const BNNSNDArrayDescriptor *w, size_t nin, size_t nout, const float *dW) {
    bnns_shape ws;
    if (bnns_shape_of(w, &ws) || ws.rank != 2 || !w->data) return -1;
    size_t rows = ws.n[0], cols = ws.n[1];
    ptrdiff_t rs = ws.s[0], cs = ws.s[1];
    if (w->layout == BNNSDataLayoutRowMajorMatrix) { rows = ws.n[1]; cols = ws.n[0]; rs = ws.s[1]; cs = ws.s[0]; }
    bool t = !(rows == nout && cols == nin);
    bool acc = w->flags == BNNSNDArrayFlagBackpropAccumulate;
    for (size_t o = 0; o < nout; o++)
        for (size_t i = 0; i < nin; i++) {
            ptrdiff_t off = t ? (ptrdiff_t)i * rs + (ptrdiff_t)o * cs : (ptrdiff_t)o * rs + (ptrdiff_t)i * cs;
            double v = dW[o * nin + i];
            if (acc) v += bnns_load(w, w->data, off);
            bnns_store(w, w->data, off, v);
        }
    return 0;
}

// Sizes: the weights' input dimension and how many input vectors a sample holds.
static int bnns_fc_sizes(const BNNSLayerParametersFullyConnected *p, size_t *nin, size_t *nout, size_t *nvec) {
    bnns_shape ws;
    if (bnns_shape_of(&p->w_desc, &ws) || ws.rank != 2) return -1;
    size_t cin = bnns_count(&p->i_desc), cout = bnns_count(&p->o_desc);
    size_t a = ws.n[0], b = ws.n[1];
    // Apple takes only the two matrix layouts here, as out x in: RowMajor sizes { in, out }, ColumnMajor { out, in }.
    // 2DLastMajor/2DFirstMajor weights and transposed sizes make it refuse the layer.
    if (p->w_desc.layout == BNNSDataLayoutRowMajorMatrix) { a = ws.n[1]; b = ws.n[0]; }
    else if (p->w_desc.layout != BNNSDataLayoutColumnMajorMatrix) return -1;
    size_t o = a, i = b;
    if (i && o && cin % i == 0 && cout % o == 0 && cin / i == cout / o) { *nin = i; *nout = o; *nvec = cin / i; return 0; }
    return -1;
}

static int bnns_fc_apply(bnns_filter *f, size_t batch, const void *in, size_t in_stride, void *out, size_t out_stride, float *keep) {
    const BNNSLayerParametersFullyConnected *p = &f->p.fc;
    size_t nin, nout, nvec;
    if (bnns_fc_sizes(p, &nin, &nout, &nvec) || !in) return -1;
    float *W = bnns_fc_weights(&p->w_desc, nin, nout, NULL), *bias = bnns_bias_values(&p->bias, nout);
    float *x = bnns_rd_batch(&p->i_desc, in, batch, in_stride, NULL);
    size_t rows = batch * nvec;
    float *y = bnns_zalloc_f(rows * nout);
    int r = -1;
    if (W && bias && x && y) {
        for (size_t i = 0; i < rows; i++) memcpy(y + i * nout, bias, nout * sizeof(float));
        bnns_sgemm(false, true, (int)rows, (int)nout, (int)nin, 1, x, (int)nin, W, (int)nin, 1, y, (int)nout);
        if (keep) memcpy(keep, y, rows * nout * sizeof(float));
        r = bnns_out_activate(&p->activation, &p->o_desc, y, batch);
        if (!r && out) r = bnns_wr_batch(&p->o_desc, out, batch, out_stride, y, false);
    }
    free(W); free(bias); free(x); free(y);
    return r;
}

static int bnns_fc_backward(bnns_filter *f, size_t batch, const void *in, size_t in_stride, BNNSNDArrayDescriptor *in_delta,
                            size_t in_delta_stride, const void *out, size_t out_stride, const BNNSNDArrayDescriptor *out_delta,
                            size_t out_delta_stride, BNNSNDArrayDescriptor *weights_delta, BNNSNDArrayDescriptor *bias_delta) {
    const BNNSLayerParametersFullyConnected *p = &f->p.fc;
    size_t nin, nout, nvec;
    if (bnns_fc_sizes(p, &nin, &nout, &nvec) || !out_delta) return -1;
    size_t rows = batch * nvec;
    float *dy = bnns_rd_batch(out_delta, bnns_delta_base(out_delta), batch, out_delta_stride, NULL);
    float *W = bnns_fc_weights(&p->w_desc, nin, nout, NULL);
    float *x = in ? bnns_rd_batch(&p->i_desc, in, batch, in_stride, NULL) : NULL;
    float *pre = NULL, *y = NULL, *dx = NULL, *dW = NULL, *db = NULL;
    int r = -1;
    if (!dy || !W) goto done;
    if (!bnns_is_identity(&p->activation)) {
        pre = in ? bnns_preactivation(f, batch, in, in_stride, nvec * nout) : NULL;
        y = out ? bnns_rd_batch(&p->o_desc, out, batch, out_stride, NULL) : NULL;
        if ((!pre && !y) || bnns_out_activate_backward(&p->activation, &p->o_desc, pre, y, dy, batch)) goto done;
    }
    if (in_delta) {
        dx = bnns_zalloc_f(rows * nin);
        if (!dx) goto done;
        bnns_sgemm(false, false, (int)rows, (int)nin, (int)nout, 1, dy, (int)nout, W, (int)nin, 0, dx, (int)nin);
        if (bnns_wr_batch(in_delta, in_delta->data, batch, in_delta_stride, dx, true)) goto done;
    }
    if (weights_delta) {
        if (!x || !(dW = bnns_zalloc_f(nout * nin))) goto done;
        bnns_sgemm(true, false, (int)nout, (int)nin, (int)rows, 1, dy, (int)nout, x, (int)nin, 0, dW, (int)nin);
        if (bnns_fc_weights_write(weights_delta, nin, nout, dW)) goto done;
    }
    if (bias_delta) {
        if (!(db = bnns_zalloc_f(nout))) goto done;
        for (size_t i = 0; i < rows; i++) for (size_t o = 0; o < nout; o++) db[o] += dy[i * nout + o];
        if (bnns_write_delta_phys(bias_delta, NULL, db)) goto done;
    }
    r = 0;
done:
    free(dy); free(W); free(x); free(pre); free(y); free(dx); free(dW); free(db);
    return r;
}

BNNSFilter BNNSFilterCreateLayerFullyConnected(const BNNSLayerParametersFullyConnected *p, const BNNSFilterParameters *fp) {
    size_t nin, nout, nvec;
    if (!p || !p->w_desc.data || !bnns_activation_supported(p->activation.function) || bnns_fc_sizes(p, &nin, &nout, &nvec)) return NULL;
    bnns_filter *f = bnns_filter_new(BNNS_KIND_FULLY_CONNECTED, fp);
    if (!f) return NULL;
    f->p.fc = *p;
    if (bnns_own(f, &f->p.fc.w_desc) || bnns_own(f, &f->p.fc.bias)) { BNNSFilterDestroy(f); return NULL; }
    return f;
}

static float *bnns_preactivation(bnns_filter *f, size_t batch, const void *in, size_t in_stride, size_t count) {
    float *keep = bnns_zalloc_f(count * batch);
    if (!keep) return NULL;
    int r = f->kind == BNNS_KIND_FULLY_CONNECTED ? bnns_fc_apply(f, batch, in, in_stride, NULL, 0, keep)
                                                 : bnns_conv_apply(f, batch, in, in_stride, NULL, 0, keep);
    if (r) { free(keep); return NULL; }
    return keep;
}

// MARK: - Pooling

typedef struct { size_t kw, kh, sx, sy, dx, dy, pl, pt; bnns_image in, out; } bnns_pool_geom;

static int bnns_pool_geometry(const BNNSLayerParametersPooling *p, bnns_pool_geom *g) {
    if (bnns_image_of(&p->i_desc, &g->in) || bnns_image_of(&p->o_desc, &g->out) || g->in.c != g->out.c) return -1;
    g->kw = p->k_width ? p->k_width : 1; g->kh = p->k_height ? p->k_height : 1;
    g->sx = p->x_stride ? p->x_stride : 1; g->sy = p->y_stride ? p->y_stride : 1;
    g->dx = p->x_dilation_stride > 1 ? p->x_dilation_stride : 1; g->dy = p->y_dilation_stride > 1 ? p->y_dilation_stride : 1;
    if (p->x_padding || p->y_padding) { g->pl = p->x_padding; g->pt = p->y_padding; }
    else { g->pl = p->pad[0]; g->pt = p->pad[2]; }
    return 0;
}

// Pools one sample; idx receives the flat input position of each maximum (or -1).
static void bnns_pool_one(BNNSPoolingFunction fn, const bnns_pool_geom *g, const float *x, float *y, long *idx) {
    size_t W = g->in.w, H = g->in.h, npo = g->out.w * g->out.h;
    for (size_t c = 0; c < g->in.c; c++)
        for (size_t oy = 0; oy < g->out.h; oy++)
            for (size_t ox = 0; ox < g->out.w; ox++) {
                double acc = 0, best = -INFINITY;
                long arg = -1;
                size_t inside = 0;
                for (size_t ky = 0; ky < g->kh; ky++) {
                    long iy = (long)(oy * g->sy + ky * g->dy) - (long)g->pt;
                    for (size_t kx = 0; kx < g->kw; kx++) {
                        long ix = (long)(ox * g->sx + kx * g->dx) - (long)g->pl;
                        if (iy < 0 || iy >= (long)H || ix < 0 || ix >= (long)W) continue;
                        long pos = (long)(c * W * H) + iy * (long)W + ix;
                        double v = x[pos];
                        inside++;
                        if (v > best) { best = v; arg = pos; }
                        acc += fn == BNNSPoolingFunctionL2Norm ? v * v : v;
                    }
                }
                double r;
                switch (fn) {
                case BNNSPoolingFunctionMax: r = arg < 0 ? 0 : best; break;
                case BNNSPoolingFunctionAverageCountIncludePadding: r = acc / (double)(g->kw * g->kh); break;
                case BNNSPoolingFunctionAverageCountExcludePadding: r = inside ? acc / (double)inside : 0; break;
                default: r = sqrt(acc);
                }
                size_t o = c * npo + oy * g->out.w + ox;
                y[o] = (float)r;
                if (idx) idx[o] = arg;
            }
}

static int bnns_pool_apply(bnns_filter *f, size_t batch, const void *in, size_t in_stride, void *out, size_t out_stride,
                           BNNSDataType idx_type, void *indices, size_t idx_stride) {
    const BNNSLayerParametersPooling *p = &f->p.pool;
    bnns_pool_geom g;
    if (bnns_pool_geometry(p, &g) || !in || !out) return -1;
    size_t nin = g.in.w * g.in.h * g.in.c, nout = g.out.w * g.out.h * g.out.c, npo = g.out.w * g.out.h;
    float *x = bnns_rd_batch(&p->i_desc, in, batch, in_stride, NULL), *y = bnns_zalloc_f(nout * batch);
    float *bias = bnns_bias_values(&p->bias, g.out.c);
    long *idx = indices ? malloc((nout ? nout : 1) * sizeof(long)) : NULL;
    BNNSNDArrayDescriptor idesc = { .data_type = idx_type, .data_scale = 1 };
    size_t isz = bnns_type_size(idx_type);
    int r = -1;
    if (!x || !y || !bias || (indices && (!idx || !isz))) goto done;
    if (p->pooling_function == BNNSPoolingFunctionUnMax) goto done;
    for (size_t b = 0; b < batch; b++) {
        bnns_pool_one(p->pooling_function, &g, x + b * nin, y + b * nout, idx);
        for (size_t c = 0; c < g.out.c; c++) for (size_t i = 0; i < npo; i++) y[b * nout + c * npo + i] += bias[c];
        if (idx) {
            char *ib = (char *)indices + b * idx_stride * isz;
            // Apple's index is the position within the sample's channel plane: y * W + x.
            size_t plane = g.in.w * g.in.h;
            for (size_t i = 0; i < nout; i++) bnns_store(&idesc, ib, (ptrdiff_t)i, (double)(idx[i] < 0 ? 0 : (size_t)idx[i] % plane));
        }
    }
    r = bnns_out_activate(&p->activation, &p->o_desc, y, batch);
    if (!r) r = bnns_wr_batch(&p->o_desc, out, batch, out_stride, y, false);
done:
    free(x); free(y); free(bias); free(idx);
    return r;
}

static int bnns_pool_backward(bnns_filter *f, size_t batch, const void *in, size_t in_stride, BNNSNDArrayDescriptor *in_delta,
                              size_t in_delta_stride, const void *out, size_t out_stride, const BNNSNDArrayDescriptor *out_delta,
                              size_t out_delta_stride, BNNSNDArrayDescriptor *bias_delta, BNNSDataType idx_type,
                              const void *indices, size_t idx_stride) {
    const BNNSLayerParametersPooling *p = &f->p.pool;
    bnns_pool_geom g;
    if (bnns_pool_geometry(p, &g) || !out_delta) return -1;
    size_t nin = g.in.w * g.in.h * g.in.c, nout = g.out.w * g.out.h * g.out.c, npo = g.out.w * g.out.h;
    float *dy = bnns_rd_batch(out_delta, bnns_delta_base(out_delta), batch, out_delta_stride, NULL);
    float *x = in ? bnns_rd_batch(&p->i_desc, in, batch, in_stride, NULL) : NULL;
    float *y = out ? bnns_rd_batch(&p->o_desc, out, batch, out_stride, NULL) : NULL;
    float *dx = bnns_zalloc_f(nin * batch), *db = bnns_zalloc_f(g.out.c), *py = bnns_zalloc_f(nout);
    long *idx = malloc((nout ? nout : 1) * sizeof(long));
    BNNSNDArrayDescriptor idesc = { .data_type = idx_type, .data_scale = 1 };
    size_t isz = bnns_type_size(idx_type);
    int r = -1;
    if (!dy || !dx || !db || !py || !idx) goto done;
    if (!bnns_is_identity(&p->activation)) {
        if (!y || bnns_out_activate_backward(&p->activation, &p->o_desc, NULL, y, dy, batch)) goto done;
    }
    BNNSPoolingFunction fn = p->pooling_function;
    for (size_t b = 0; b < batch; b++) {
        float *dyb = dy + b * nout, *dxb = dx + b * nin;
        for (size_t c = 0; c < g.out.c; c++) for (size_t i = 0; i < npo; i++) db[c] += dyb[c * npo + i];
        if (fn == BNNSPoolingFunctionMax || fn == BNNSPoolingFunctionL2Norm) {
            if (indices && fn == BNNSPoolingFunctionMax) {
                if (!isz) goto done;
                const char *ib = (const char *)indices + b * idx_stride * isz;
                for (size_t i = 0; i < nout; i++) idx[i] = (long)bnns_load_index(&idesc, ib, (ptrdiff_t)i) + (long)((i / npo) * g.in.w * g.in.h);
            } else {
                if (!x) goto done;
                bnns_pool_one(fn, &g, x + b * nin, py, idx);
            }
            for (size_t c = 0; c < g.out.c; c++)
                for (size_t oy = 0; oy < g.out.h; oy++)
                    for (size_t ox = 0; ox < g.out.w; ox++) {
                        size_t o = c * npo + oy * g.out.w + ox;
                        if (fn == BNNSPoolingFunctionMax) {
                            if (idx[o] >= 0 && (size_t)idx[o] < nin) dxb[idx[o]] += dyb[o];
                            continue;
                        }
                        if (py[o] == 0) continue;
                        for (size_t ky = 0; ky < g.kh; ky++) {
                            long iy = (long)(oy * g.sy + ky * g.dy) - (long)g.pt;
                            for (size_t kx = 0; kx < g.kw; kx++) {
                                long ix = (long)(ox * g.sx + kx * g.dx) - (long)g.pl;
                                if (iy < 0 || iy >= (long)g.in.h || ix < 0 || ix >= (long)g.in.w) continue;
                                long pos = (long)(c * g.in.w * g.in.h) + iy * (long)g.in.w + ix;
                                dxb[pos] += dyb[o] * x[b * nin + pos] / py[o];
                            }
                        }
                    }
        } else if (fn == BNNSPoolingFunctionAverageCountIncludePadding || fn == BNNSPoolingFunctionAverageCountExcludePadding) {
            for (size_t c = 0; c < g.out.c; c++)
                for (size_t oy = 0; oy < g.out.h; oy++)
                    for (size_t ox = 0; ox < g.out.w; ox++) {
                        size_t inside = 0;
                        for (int pass = 0; pass < 2; pass++)
                            for (size_t ky = 0; ky < g.kh; ky++) {
                                long iy = (long)(oy * g.sy + ky * g.dy) - (long)g.pt;
                                for (size_t kx = 0; kx < g.kw; kx++) {
                                    long ix = (long)(ox * g.sx + kx * g.dx) - (long)g.pl;
                                    if (iy < 0 || iy >= (long)g.in.h || ix < 0 || ix >= (long)g.in.w) continue;
                                    if (!pass) { inside++; continue; }
                                    double count = fn == BNNSPoolingFunctionAverageCountIncludePadding ? (double)(g.kw * g.kh) : (double)inside;
                                    dxb[(long)(c * g.in.w * g.in.h) + iy * (long)g.in.w + ix] += (float)(dyb[c * npo + oy * g.out.w + ox] / count);
                                }
                            }
                    }
        } else goto done;
    }
    r = 0;
    if (in_delta) r = bnns_wr_batch(in_delta, in_delta->data, batch, in_delta_stride, dx, true);
    if (!r && bias_delta) r = bnns_write_delta_phys(bias_delta, NULL, db);
done:
    free(dy); free(x); free(y); free(dx); free(db); free(py); free(idx);
    return r;
}

BNNSFilter BNNSFilterCreateLayerPooling(const BNNSLayerParametersPooling *p, const BNNSFilterParameters *fp) {
    bnns_pool_geom g;
    if (!p || bnns_pool_geometry(p, &g) || !bnns_activation_supported(p->activation.function)) return NULL;
    if (p->pooling_function > BNNSPoolingFunctionL2Norm || p->pooling_function == BNNSPoolingFunctionUnMax) return NULL;
    bnns_filter *f = bnns_filter_new(BNNS_KIND_POOLING, fp);
    if (!f) return NULL;
    f->p.pool = *p;
    if (bnns_own(f, &f->p.pool.bias)) { BNNSFilterDestroy(f); return NULL; }
    return f;
}

int BNNSPoolingFilterApplyBatch(BNNSFilter filter, size_t batch_size, const void *in, size_t in_stride, void *out, size_t out_stride,
                                size_t *indices, size_t idx_stride) {
    bnns_filter *f = bnns_filter_get(filter);
    if (!f || f->kind != BNNS_KIND_POOLING) return -1;
    return bnns_pool_apply(f, batch_size, in, in_stride, out, out_stride, BNNSDataTypeUInt64, indices, idx_stride);
}

int BNNSPoolingFilterApplyBatchEx(BNNSFilter filter, size_t batch_size, const void *in, size_t in_stride, void *out, size_t out_stride,
                                  BNNSDataType indices_data_type, void *indices, size_t idx_stride) {
    bnns_filter *f = bnns_filter_get(filter);
    if (!f || f->kind != BNNS_KIND_POOLING) return -1;
    return bnns_pool_apply(f, batch_size, in, in_stride, out, out_stride, indices_data_type, indices, idx_stride);
}

int BNNSPoolingFilterApplyBackwardBatch(BNNSFilter filter, size_t batch_size, const void *in, size_t in_stride,
                                        BNNSNDArrayDescriptor *in_delta, size_t in_delta_stride, const void *out, size_t out_stride,
                                        BNNSNDArrayDescriptor *out_delta, size_t out_delta_stride, BNNSNDArrayDescriptor *bias_delta,
                                        const size_t *indices, size_t idx_stride) {
    bnns_filter *f = bnns_filter_get(filter);
    if (!f || f->kind != BNNS_KIND_POOLING) return -1;
    return bnns_pool_backward(f, batch_size, in, in_stride, in_delta, in_delta_stride, out, out_stride, out_delta, out_delta_stride,
                              bias_delta, BNNSDataTypeUInt64, indices, idx_stride);
}

int BNNSPoolingFilterApplyBackwardBatchEx(BNNSFilter filter, size_t batch_size, const void *in, size_t in_stride,
                                          BNNSNDArrayDescriptor *in_delta, size_t in_delta_stride, const void *out, size_t out_stride,
                                          BNNSNDArrayDescriptor *out_delta, size_t out_delta_stride, BNNSNDArrayDescriptor *bias_delta,
                                          BNNSDataType indices_data_type, const void *indices, size_t idx_stride) {
    bnns_filter *f = bnns_filter_get(filter);
    if (!f || f->kind != BNNS_KIND_POOLING) return -1;
    return bnns_pool_backward(f, batch_size, in, in_stride, in_delta, in_delta_stride, out, out_stride, out_delta, out_delta_stride,
                              bias_delta, indices_data_type, indices, idx_stride);
}

// MARK: - Activation

BNNSFilter BNNSFilterCreateLayerActivation(const BNNSLayerParametersActivation *p, const BNNSFilterParameters *fp) {
    if (!p || !bnns_activation_supported(p->activation.function)) return NULL;
    bnns_shape si, so;
    if (bnns_shape_of(&p->i_desc, &si) || bnns_shape_of(&p->o_desc, &so) || bnns_shape_count(&si) != bnns_shape_count(&so)) return NULL;
    bnns_filter *f = bnns_filter_new(BNNS_KIND_ACTIVATION, fp);
    if (!f) return NULL;
    f->p.act = *p;
    return f;
}

static float *bnns_rd_batch_logical(const BNNSNDArrayDescriptor *d, const void *base, size_t batch, size_t stride) {
    size_t n = bnns_count(d);
    if (!base) return NULL;
    float *all = malloc((n * batch ? n * batch : 1) * sizeof(float));
    if (!all) return NULL;
    for (size_t b = 0; b < batch; b++) {
        float *t = bnns_rd(d, base, b, stride, false);
        if (!t) { free(all); return NULL; }
        memcpy(all + b * n, t, n * sizeof(float));
        free(t);
    }
    return all;
}

static int bnns_wr_batch_logical(const BNNSNDArrayDescriptor *d, void *base, size_t batch, size_t stride, const float *all, bool delta) {
    size_t n = bnns_count(d);
    if (!base) return -1;
    for (size_t b = 0; b < batch; b++) {
        void *p = bnns_offset(d, base, b, stride);
        int r = delta ? bnns_write_delta(d, p, all + b * n) : bnns_write(d, p, all + b * n, false);
        if (r) return r;
    }
    return 0;
}

static int bnns_act_apply(bnns_filter *f, size_t batch, const void *in, size_t in_stride, void *out, size_t out_stride) {
    const BNNSLayerParametersActivation *p = &f->p.act;
    bnns_shape sh;
    if (bnns_shape_of(&p->i_desc, &sh)) return -1;
    float *x = bnns_rd_batch_logical(&p->i_desc, in, batch, in_stride);
    if (!x) return -1;
    int r = bnns_activate(&p->activation, p->axis_flags, &sh, x, batch);
    if (!r) r = bnns_wr_batch_logical(&p->o_desc, out, batch, out_stride, x, false);
    free(x);
    return r;
}

static int bnns_act_backward(bnns_filter *f, size_t batch, const void *in, size_t in_stride, BNNSNDArrayDescriptor *in_delta,
                             size_t in_delta_stride, const void *out, size_t out_stride, const BNNSNDArrayDescriptor *out_delta,
                             size_t out_delta_stride, BNNSNDArrayDescriptor *weights_delta) {
    const BNNSLayerParametersActivation *p = &f->p.act;
    bnns_shape sh;
    if (bnns_shape_of(&p->i_desc, &sh) || !out_delta) return -1;
    size_t n = bnns_shape_count(&sh);
    float *dy = bnns_rd_batch_logical(out_delta, bnns_delta_base(out_delta), batch, out_delta_stride);
    float *x = in ? bnns_rd_batch_logical(&p->i_desc, in, batch, in_stride) : NULL;
    float *y = out ? bnns_rd_batch_logical(&p->o_desc, out, batch, out_stride) : NULL;
    int r = -1;
    if (!dy) goto done;
    if (weights_delta) {
        // d/d(alpha) of leaky ReLU and its per-channel form.
        BNNSActivationFunction fn = p->activation.function;
        if ((fn != BNNSActivationFunctionLeakyRectifiedLinear && fn != BNNSActivationFunctionPReLUPerChannel) || !x) goto done;
        float da = 0;
        for (size_t i = 0; i < n * batch; i++) if (x[i] < 0) da += dy[i] * x[i];
        size_t nw = bnns_count(weights_delta);
        float *buf = bnns_zalloc_f(nw);
        if (!buf) goto done;
        for (size_t i = 0; i < nw; i++) buf[i] = nw == 1 ? da : 0;
        if (nw > 1) {
            // per channel: last logical dimension
            size_t chans = sh.n[sh.rank - 1], inner = n / (chans ? chans : 1);
            for (size_t b = 0; b < batch; b++)
                for (size_t i = 0; i < n; i++) {
                    size_t c = i / inner;
                    if (c < nw && x[b * n + i] < 0) buf[c] += dy[b * n + i] * x[b * n + i];
                }
        }
        r = bnns_write_delta(weights_delta, NULL, buf);
        free(buf);
        if (r) goto done;
        r = -1;
    }
    if (bnns_activate_backward(&p->activation, p->axis_flags, &sh, x, y, dy, batch)) goto done;
    r = in_delta ? bnns_wr_batch_logical(in_delta, in_delta->data, batch, in_delta_stride, dy, true) : 0;
done:
    free(dy); free(x); free(y);
    return r;
}

// MARK: - Loss

BNNSFilter BNNSFilterCreateLayerLoss(const void *layer_params, const BNNSFilterParameters *fp) {
    const BNNSLayerParametersLossBase *base = layer_params;
    if (!base) return NULL;
    BNNSLossFunction fn = base->function;
    if (fn < BNNSLossFunctionSoftmaxCrossEntropy || fn > BNNSLossFunctionCategoricalCrossEntropy || fn == BNNSLossFunctionYolo) return NULL;
    if (base->reduction > BNNSLossReductionNonZeroWeightMean || !bnns_count(&base->i_desc)) return NULL;
    // A reduced loss is one value; Apple refuses any other output size.
    if (base->reduction != BNNSLossReductionNone && bnns_count(&base->o_desc) != 1) return NULL;
    bnns_filter *f = bnns_filter_new(BNNS_KIND_LOSS, fp);
    if (!f) return NULL;
    size_t size = fn == BNNSLossFunctionSoftmaxCrossEntropy || fn == BNNSLossFunctionSigmoidCrossEntropy ? sizeof(BNNSLayerParametersLossSoftmaxCrossEntropy)
                : fn == BNNSLossFunctionHuber ? sizeof(BNNSLayerParametersLossHuber) : sizeof(BNNSLayerParametersLossBase);
    memcpy(&f->p.loss, layer_params, size);
    return f;
}

int BNNSLossFilterApplyBatch(BNNSFilter filter, size_t batch_size, const void *in, size_t in_stride, const void *labels,
                             size_t labels_stride, const void *weights, size_t weights_size, void *out,
                             BNNSNDArrayDescriptor *in_delta, size_t in_delta_stride) {
    bnns_filter *f = bnns_filter_get(filter);
    if (!f || f->kind != BNNS_KIND_LOSS || !in || !labels) return -1;
    const BNNSLayerParametersLossYolo *p = &f->p.loss;
    BNNSLossFunction fn = p->function;
    size_t n;
    float *x = bnns_rd_batch(&p->i_desc, in, batch_size, in_stride, &n);
    BNNSNDArrayDescriptor ld = p->i_desc;
    float *l = bnns_rd_batch(&ld, labels, batch_size, labels_stride, NULL);
    size_t total = n * batch_size;
    float *loss = bnns_zalloc_f(total), *grad = bnns_zalloc_f(total), *wt = bnns_zalloc_f(total);
    int r = -1;
    if (!x || !l || !loss || !grad || !wt) goto done;
    bool per_sample = fn == BNNSLossFunctionSoftmaxCrossEntropy || fn == BNNSLossFunctionCosineDistance ||
                      fn == BNNSLossFunctionCategoricalCrossEntropy;
    const float *w = weights;
    for (size_t i = 0; i < total; i++) {
        size_t b = i / n;
        wt[i] = !w || !weights_size ? 1 : weights_size == 1 ? w[0] : weights_size == batch_size ? w[b] : weights_size >= total ? w[i] : 1;
    }
    float smooth = (fn == BNNSLossFunctionSoftmaxCrossEntropy || fn == BNNSLossFunctionSigmoidCrossEntropy) ? p->huber_delta : 0;
    for (size_t b = 0; b < batch_size; b++) {
        float *xb = x + b * n, *lb = l + b * n, *gb = grad + b * n, *ob = loss + b * n;
        if (fn == BNNSLossFunctionSoftmaxCrossEntropy) {
            double mx = -INFINITY, sum = 0, lsum = 0, total_loss = 0;
            for (size_t i = 0; i < n; i++) if (xb[i] > mx) mx = xb[i];
            for (size_t i = 0; i < n; i++) sum += exp(xb[i] - mx);
            for (size_t i = 0; i < n; i++) {
                double lab = lb[i] * (1 - smooth) + smooth / (double)n;
                double logp = xb[i] - mx - log(sum);
                total_loss -= lab * logp;
                lsum += lab;
                gb[i] = (float)lab;
            }
            for (size_t i = 0; i < n; i++) gb[i] = (float)(exp(xb[i] - mx) / sum * lsum - gb[i]);
            ob[0] = (float)total_loss;
        } else if (fn == BNNSLossFunctionCategoricalCrossEntropy) {
            double t = 0;
            for (size_t i = 0; i < n; i++) {
                double pr = fmax(xb[i], 1e-12);
                t -= lb[i] * log(pr);
                gb[i] = (float)(-lb[i] / pr);
            }
            ob[0] = (float)t;
        } else if (fn == BNNSLossFunctionCosineDistance) {
            double dot = 0, nx = 0, nl = 0;
            for (size_t i = 0; i < n; i++) { dot += (double)xb[i] * lb[i]; nx += (double)xb[i] * xb[i]; nl += (double)lb[i] * lb[i]; }
            double denom = sqrt(nx * nl);
            ob[0] = (float)(1 - (denom > 0 ? dot / denom : 0));
            for (size_t i = 0; i < n; i++) gb[i] = denom > 0 ? (float)(-(lb[i] / denom - dot * xb[i] / (nx * denom))) : 0;
        } else {
            for (size_t i = 0; i < n; i++) {
                double xv = xb[i], lv = lb[i], d = xv - lv, v, g;
                switch (fn) {
                case BNNSLossFunctionSigmoidCrossEntropy:
                    lv = lv * (1 - smooth) + smooth / 2;
                    v = fmax(xv, 0) - xv * lv + log1p(exp(-fabs(xv)));
                    g = 1 / (1 + exp(-xv)) - lv;
                    break;
                case BNNSLossFunctionMeanSquareError: v = d * d; g = 2 * d; break;
                case BNNSLossFunctionMeanAbsoluteError: v = fabs(d); g = d > 0 ? 1 : d < 0 ? -1 : 0; break;
                case BNNSLossFunctionHuber: {
                    double delta = p->huber_delta;
                    if (fabs(d) <= delta) { v = 0.5 * d * d; g = d; }
                    else { v = delta * (fabs(d) - 0.5 * delta); g = d > 0 ? delta : -delta; }
                    break;
                }
                case BNNSLossFunctionLog: {
                    const double eps = 1e-7;
                    v = -(lv * log(xv + eps) + (1 - lv) * log(1 - xv + eps));
                    g = -(lv / (xv + eps)) + (1 - lv) / (1 - xv + eps);
                    break;
                }
                case BNNSLossFunctionHinge: v = fmax(0, 1 - lv * xv); g = 1 - lv * xv > 0 ? -lv : 0; break;
                default: goto done;
                }
                ob[i] = (float)v;
                gb[i] = (float)g;
            }
        }
    }
    // Reduction over the loss values (one per sample or one per element).
    size_t nvals = per_sample ? batch_size : total;
    double sum = 0, wsum = 0, nonzero = 0;
    for (size_t k = 0; k < nvals; k++) {
        size_t i = per_sample ? k * n : k;
        double wv = wt[i];
        sum += wv * loss[i];
        wsum += wv;
        if (wv != 0) nonzero++;
    }
    double scale;
    switch (p->reduction) {
    case BNNSLossReductionNone: scale = 1; break;
    case BNNSLossReductionSum: scale = 1; break;
    case BNNSLossReductionWeightedMean: scale = wsum != 0 ? 1 / wsum : 0; break;
    case BNNSLossReductionMean: scale = nvals ? 1.0 / (double)nvals : 0; break;
    default: scale = nonzero ? 1 / nonzero : 0;
    }
    float *o = out;
    if (o) {
        if (p->reduction == BNNSLossReductionNone)
            for (size_t k = 0; k < nvals; k++) { size_t i = per_sample ? k * n : k; o[k] = wt[i] * loss[i]; }
        else o[0] = (float)(sum * scale);
    }
    if (in_delta) {
        for (size_t i = 0; i < total; i++) grad[i] = (float)(grad[i] * wt[i] * scale);
        if (bnns_wr_batch(in_delta, in_delta->data, batch_size, in_delta_stride, grad, true)) goto done;
    }
    r = 0;
done:
    free(x); free(l); free(loss); free(grad); free(wt);
    return r;
}

// MARK: - Normalization

typedef struct { size_t C, S; } bnns_norm_dims;

static int bnns_norm_dims_of(const BNNSNDArrayDescriptor *d, bnns_norm_dims *nd) {
    bnns_image im;
    if (bnns_image_of(d, &im)) return -1;
    nd->C = im.c; nd->S = im.w * im.h;
    return 0;
}

// Layer norm: the number of trailing-in-memory elements one group covers.
static size_t bnns_layer_norm_group(const BNNSLayerParametersNormalization *p) {
    bnns_shape sh;
    if (bnns_shape_phys(&p->i_desc, &sh)) return 0;
    int dims = sh.rank - (int)p->normalization_axis;
    if (dims < 1) dims = 1;
    size_t g = 1;
    for (int k = 0; k < dims; k++) g *= sh.n[k];
    return g;
}

// Statistics groups for element i of sample b, and the number of groups.
static size_t bnns_norm_group(const bnns_filter *f, const bnns_norm_dims *nd, size_t lg, size_t b, size_t i, size_t *ngroups, size_t batch) {
    size_t c = i / nd->S, per = nd->C * nd->S;
    switch (f->norm_type) {
    case BNNSBatchNorm: *ngroups = nd->C; return c;
    case BNNSInstanceNorm: *ngroups = nd->C * batch; return b * nd->C + c;
    case BNNSLayerNorm: *ngroups = per / lg * batch; return b * (per / lg) + i / lg;
    default: {
        size_t G = f->p.norm.num_groups ? f->p.norm.num_groups : 1;
        *ngroups = G * batch;
        return b * G + c / (nd->C / G);
    }
    }
}

// Index into gamma/beta for element i.
static size_t bnns_norm_param_index(const bnns_filter *f, const bnns_norm_dims *nd, size_t lg, size_t i) {
    return f->norm_type == BNNSLayerNorm ? i % lg : i / nd->S;
}

static int bnns_norm_check(const BNNSLayerParametersNormalization *p, BNNSFilterType type) {
    bnns_norm_dims nd;
    if (type < BNNSBatchNorm || type > BNNSGroupNorm || bnns_norm_dims_of(&p->i_desc, &nd)) return -1;
    if (bnns_count(&p->i_desc) != bnns_count(&p->o_desc)) return -1;
    if (type == BNNSGroupNorm && (!p->num_groups || nd.C % p->num_groups)) return -1;
    if (type == BNNSLayerNorm && !bnns_layer_norm_group(p)) return -1;
    if (!bnns_activation_supported(p->activation.function) || p->activation.function == BNNSActivationFunctionSoftmax ||
        p->activation.function == BNNSActivationFunctionLogSoftmax) return -1;
    return 0;
}

static int bnns_norm_apply(bnns_filter *f, size_t batch, const void *in, size_t in_stride, void *out, size_t out_stride, bool training) {
    const BNNSLayerParametersNormalization *p = &f->p.norm;
    bnns_norm_dims nd;
    if (bnns_norm_dims_of(&p->i_desc, &nd) || !in || !out) return -1;
    size_t per = nd.C * nd.S, total = per * batch, lg = bnns_layer_norm_group(p), ng = 0;
    size_t nparam = f->norm_type == BNNSLayerNorm ? lg : nd.C;
    float *x = bnns_rd_batch(&p->i_desc, in, batch, in_stride, NULL);
    float *gamma = p->gamma_desc.data ? bnns_read_phys(&p->gamma_desc, NULL) : NULL;
    float *beta = p->beta_desc.data ? bnns_read_phys(&p->beta_desc, NULL) : NULL;
    bnns_norm_group(f, &nd, lg, 0, 0, &ng, batch);
    double *mean = calloc(ng ? ng : 1, sizeof(double)), *var = calloc(ng ? ng : 1, sizeof(double)), *cnt = calloc(ng ? ng : 1, sizeof(double));
    float *y = bnns_zalloc_f(total);
    int r = -1;
    if (!x || !mean || !var || !cnt || !y) goto done;
    if ((gamma && bnns_count(&p->gamma_desc) < nparam) || (beta && bnns_count(&p->beta_desc) < nparam)) goto done;
    // Batch and instance norm use the moving statistics at inference (Apple does for both).
    bool use_moving = (f->norm_type == BNNSBatchNorm || f->norm_type == BNNSInstanceNorm) && !training &&
                      p->moving_mean_desc.data && p->moving_variance_desc.data;
    if (use_moving) {
        float *mm = bnns_read_phys(&p->moving_mean_desc, NULL), *mv = bnns_read_phys(&p->moving_variance_desc, NULL);
        if (!mm || !mv) { free(mm); free(mv); goto done; }
        for (size_t k = 0; k < ng; k++) { mean[k] = mm[k % nd.C]; var[k] = mv[k % nd.C]; }
        free(mm); free(mv);
    } else {
        for (size_t b = 0; b < batch; b++)
            for (size_t i = 0; i < per; i++) {
                size_t gi = bnns_norm_group(f, &nd, lg, b, i, &ng, batch);
                mean[gi] += x[b * per + i];
                cnt[gi] += 1;
            }
        for (size_t k = 0; k < ng; k++) mean[k] = cnt[k] ? mean[k] / cnt[k] : 0;
        for (size_t b = 0; b < batch; b++)
            for (size_t i = 0; i < per; i++) {
                size_t gi = bnns_norm_group(f, &nd, lg, b, i, &ng, batch);
                double d = x[b * per + i] - mean[gi];
                var[gi] += d * d;
            }
        for (size_t k = 0; k < ng; k++) var[k] = cnt[k] ? var[k] / cnt[k] : 0;
    }
    for (size_t b = 0; b < batch; b++)
        for (size_t i = 0; i < per; i++) {
            size_t gi = bnns_norm_group(f, &nd, lg, b, i, &ng, batch), pi = bnns_norm_param_index(f, &nd, lg, i);
            double v = (x[b * per + i] - mean[gi]) / sqrt(var[gi] + p->epsilon);
            y[b * per + i] = (float)(v * (gamma ? gamma[pi] : 1) + (beta ? beta[pi] : 0));
        }
    if (training) {
        free(f->cache_x);
        f->cache_x = x;
        f->cache_batch = batch;
        x = NULL;
        if (f->norm_type == BNNSBatchNorm && p->moving_mean_desc.data && p->moving_variance_desc.data) {
            float *mm = bnns_read_phys(&p->moving_mean_desc, NULL), *mv = bnns_read_phys(&p->moving_variance_desc, NULL);
            if (mm && mv) {
                for (size_t c = 0; c < nd.C; c++) {
                    mm[c] = (float)(p->momentum * mm[c] + (1 - p->momentum) * mean[c]);
                    // The moving variance takes the unbiased (n - 1) batch variance.
                    double uv = cnt[c] > 1 ? var[c] * cnt[c] / (cnt[c] - 1) : var[c];
                    mv[c] = (float)(p->momentum * mv[c] + (1 - p->momentum) * uv);
                }
                bnns_write_phys(&p->moving_mean_desc, NULL, mm, false);
                bnns_write_phys(&p->moving_variance_desc, NULL, mv, false);
            }
            free(mm); free(mv);
        }
    }
    r = bnns_out_activate(&p->activation, &p->o_desc, y, batch);
    if (!r) r = bnns_wr_batch(&p->o_desc, out, batch, out_stride, y, false);
done:
    free(x); free(gamma); free(beta); free(mean); free(var); free(cnt); free(y);
    return r;
}

static int bnns_norm_backward(bnns_filter *f, size_t batch, BNNSNDArrayDescriptor *in_delta, size_t in_delta_stride,
                              const void *out, size_t out_stride, const BNNSNDArrayDescriptor *out_delta, size_t out_delta_stride,
                              BNNSNDArrayDescriptor *beta_delta, BNNSNDArrayDescriptor *gamma_delta) {
    const BNNSLayerParametersNormalization *p = &f->p.norm;
    bnns_norm_dims nd;
    if (bnns_norm_dims_of(&p->i_desc, &nd) || !out_delta || !f->cache_x || f->cache_batch != batch) return -1;
    size_t per = nd.C * nd.S, total = per * batch, lg = bnns_layer_norm_group(p), ng = 0;
    size_t nparam = f->norm_type == BNNSLayerNorm ? lg : nd.C;
    const float *x = f->cache_x;
    float *dy = bnns_rd_batch(out_delta, bnns_delta_base(out_delta), batch, out_delta_stride, NULL);
    float *gamma = p->gamma_desc.data ? bnns_read_phys(&p->gamma_desc, NULL) : NULL;
    float *beta = p->beta_desc.data ? bnns_read_phys(&p->beta_desc, NULL) : NULL;
    bnns_norm_group(f, &nd, lg, 0, 0, &ng, batch);
    double *mean = calloc(ng ? ng : 1, sizeof(double)), *var = calloc(ng ? ng : 1, sizeof(double)), *cnt = calloc(ng ? ng : 1, sizeof(double));
    double *s1 = calloc(ng ? ng : 1, sizeof(double)), *s2 = calloc(ng ? ng : 1, sizeof(double));
    float *xhat = bnns_zalloc_f(total), *dx = bnns_zalloc_f(total), *dgamma = bnns_zalloc_f(nparam), *dbeta = bnns_zalloc_f(nparam);
    int r = -1;
    (void)out; (void)out_stride;
    if (!dy || !mean || !var || !cnt || !s1 || !s2 || !xhat || !dx || !dgamma || !dbeta) goto done;
    for (size_t b = 0; b < batch; b++)
        for (size_t i = 0; i < per; i++) {
            size_t gi = bnns_norm_group(f, &nd, lg, b, i, &ng, batch);
            mean[gi] += x[b * per + i];
            cnt[gi] += 1;
        }
    for (size_t k = 0; k < ng; k++) mean[k] = cnt[k] ? mean[k] / cnt[k] : 0;
    for (size_t b = 0; b < batch; b++)
        for (size_t i = 0; i < per; i++) {
            size_t gi = bnns_norm_group(f, &nd, lg, b, i, &ng, batch);
            double d = x[b * per + i] - mean[gi];
            var[gi] += d * d;
        }
    for (size_t k = 0; k < ng; k++) var[k] = cnt[k] ? var[k] / cnt[k] : 0;
    for (size_t b = 0; b < batch; b++)
        for (size_t i = 0; i < per; i++) {
            size_t gi = bnns_norm_group(f, &nd, lg, b, i, &ng, batch);
            xhat[b * per + i] = (float)((x[b * per + i] - mean[gi]) / sqrt(var[gi] + p->epsilon));
        }
    if (!bnns_is_identity(&p->activation)) {
        float *pre = bnns_zalloc_f(total);
        if (!pre) goto done;
        for (size_t b = 0; b < batch; b++)
            for (size_t i = 0; i < per; i++) {
                size_t pi = bnns_norm_param_index(f, &nd, lg, i);
                pre[b * per + i] = xhat[b * per + i] * (gamma ? gamma[pi] : 1) + (beta ? beta[pi] : 0);
            }
        int ar = bnns_out_activate_backward(&p->activation, &p->o_desc, pre, NULL, dy, batch);
        free(pre);
        if (ar) goto done;
    }
    for (size_t b = 0; b < batch; b++)
        for (size_t i = 0; i < per; i++) {
            size_t gi = bnns_norm_group(f, &nd, lg, b, i, &ng, batch), pi = bnns_norm_param_index(f, &nd, lg, i);
            float g = dy[b * per + i];
            dbeta[pi] += g;
            dgamma[pi] += g * xhat[b * per + i];
            double dxh = g * (gamma ? gamma[pi] : 1);
            s1[gi] += dxh;
            s2[gi] += dxh * xhat[b * per + i];
        }
    for (size_t b = 0; b < batch; b++)
        for (size_t i = 0; i < per; i++) {
            size_t gi = bnns_norm_group(f, &nd, lg, b, i, &ng, batch), pi = bnns_norm_param_index(f, &nd, lg, i);
            double m = cnt[gi], dxh = dy[b * per + i] * (gamma ? gamma[pi] : 1);
            dx[b * per + i] = (float)((m * dxh - s1[gi] - xhat[b * per + i] * s2[gi]) / (m * sqrt(var[gi] + p->epsilon)));
        }
    r = 0;
    if (in_delta) r = bnns_wr_batch(in_delta, in_delta->data, batch, in_delta_stride, dx, true);
    if (!r && beta_delta) r = bnns_write_delta_phys(beta_delta, NULL, dbeta);
    if (!r && gamma_delta) r = bnns_write_delta_phys(gamma_delta, NULL, dgamma);
done:
    free(dy); free(gamma); free(beta); free(mean); free(var); free(cnt); free(s1); free(s2);
    free(xhat); free(dx); free(dgamma); free(dbeta);
    return r;
}

BNNSFilter BNNSFilterCreateLayerNormalization(BNNSFilterType type, const BNNSLayerParametersNormalization *p, const BNNSFilterParameters *fp) {
    if (!p || bnns_norm_check(p, type)) return NULL;
    bnns_filter *f = bnns_filter_new(BNNS_KIND_NORMALIZATION, fp);
    if (!f) return NULL;
    f->p.norm = *p;
    f->norm_type = type;
    if (bnns_own(f, &f->p.norm.beta_desc) || bnns_own(f, &f->p.norm.gamma_desc) ||
        bnns_own(f, &f->p.norm.moving_mean_desc) || bnns_own(f, &f->p.norm.moving_variance_desc)) {
        BNNSFilterDestroy(f);
        return NULL;
    }
    return f;
}

int BNNSNormalizationFilterApplyBatch(BNNSFilter filter, size_t batch_size, const void *in, size_t in_stride, void *out,
                                      size_t out_stride, bool training) {
    bnns_filter *f = bnns_filter_get(filter);
    if (!f || f->kind != BNNS_KIND_NORMALIZATION) return -1;
    return bnns_norm_apply(f, batch_size, in, in_stride, out, out_stride, training);
}

int BNNSNormalizationFilterApplyBackwardBatch(BNNSFilter filter, size_t batch_size, BNNSNDArrayDescriptor *in_delta, size_t in_delta_stride,
                                              const void *out, size_t out_stride, BNNSNDArrayDescriptor *out_delta, size_t out_delta_stride,
                                              BNNSNDArrayDescriptor *beta_delta, BNNSNDArrayDescriptor *gamma_delta) {
    bnns_filter *f = bnns_filter_get(filter);
    if (!f || f->kind != BNNS_KIND_NORMALIZATION) return -1;
    return bnns_norm_backward(f, batch_size, in_delta, in_delta_stride, out, out_stride, out_delta, out_delta_stride, beta_delta, gamma_delta);
}

// MARK: - Arithmetic

static int bnns_arith_arity(BNNSArithmeticFunction fn) {
    switch (fn) {
    case BNNSArithmeticAdd: case BNNSArithmeticSubtract: case BNNSArithmeticMultiply: case BNNSArithmeticDivide:
    case BNNSArithmeticPow: case BNNSArithmeticMultiplyNoNaN: case BNNSArithmeticDivideNoNaN: case BNNSArithmeticMinimum:
    case BNNSArithmeticMaximum: case BNNSArithmeticFloorDivide: case BNNSArithmeticTruncDivide: case BNNSArithmeticTruncRemainder:
        return 2;
    case BNNSArithmeticMultiplyAdd: case BNNSArithmeticSelect: return 3;
    default: return fn <= BNNSArithmeticErf ? 1 : 0;
    }
}

static float bnns_arith_value(BNNSArithmeticFunction fn, float a, float b, float c) {
    switch (fn) {
    case BNNSArithmeticAdd: return a + b;
    case BNNSArithmeticSubtract: return a - b;
    case BNNSArithmeticMultiply: return a * b;
    case BNNSArithmeticDivide: return a / b;
    case BNNSArithmeticSquareRoot: return sqrtf(a);
    case BNNSArithmeticReciprocalSquareRoot: return 1 / sqrtf(a);
    case BNNSArithmeticCeil: return ceilf(a);
    case BNNSArithmeticFloor: return floorf(a);
    case BNNSArithmeticRound: return roundf(a);
    case BNNSArithmeticSin: return sinf(a);
    case BNNSArithmeticCos: return cosf(a);
    case BNNSArithmeticTan: return tanf(a);
    case BNNSArithmeticAsin: return asinf(a);
    case BNNSArithmeticAcos: return acosf(a);
    case BNNSArithmeticAtan: return atanf(a);
    case BNNSArithmeticSinh: return sinhf(a);
    case BNNSArithmeticCosh: return coshf(a);
    case BNNSArithmeticTanh: return tanhf(a);
    case BNNSArithmeticAsinh: return asinhf(a);
    case BNNSArithmeticAcosh: return acoshf(a);
    case BNNSArithmeticAtanh: return atanhf(a);
    case BNNSArithmeticPow: return powf(a, b);
    case BNNSArithmeticExp: return expf(a);
    case BNNSArithmeticExp2: return exp2f(a);
    case BNNSArithmeticLog: return logf(a);
    case BNNSArithmeticLog2: return log2f(a);
    case BNNSArithmeticMultiplyNoNaN: return b == 0 ? 0 : a * b;
    case BNNSArithmeticDivideNoNaN: return b == 0 ? 0 : a / b;
    case BNNSArithmeticMultiplyAdd: return a * b + c;
    case BNNSArithmeticMinimum: return fminf(a, b);
    case BNNSArithmeticMaximum: return fmaxf(a, b);
    case BNNSArithmeticSelect: return a != 0 ? b : c;
    case BNNSArithmeticAbs: return fabsf(a);
    case BNNSArithmeticSign: return a > 0 ? 1.0f : a < 0 ? -1.0f : 0.0f;
    case BNNSArithmeticNegate: return -a;
    case BNNSArithmeticReciprocal: return 1 / a;
    case BNNSArithmeticSquare: return a * a;
    case BNNSArithmeticFloorDivide: return floorf(a / b);
    case BNNSArithmeticTruncDivide: return truncf(a / b);
    case BNNSArithmeticTruncRemainder: return fmodf(a, b);
    case BNNSArithmeticErf: return erff(a);
    default: return NAN;
    }
}

// Partial derivative with respect to input k (0..2), NAN if not differentiable here.
static float bnns_arith_partial(BNNSArithmeticFunction fn, int k, float a, float b, float c) {
    (void)c;
    switch (fn) {
    case BNNSArithmeticAdd: return 1;
    case BNNSArithmeticSubtract: return k ? -1 : 1;
    case BNNSArithmeticMultiply: return k ? a : b;
    case BNNSArithmeticDivide: return k ? -a / (b * b) : 1 / b;
    case BNNSArithmeticSquareRoot: return 0.5f / sqrtf(a);
    case BNNSArithmeticReciprocalSquareRoot: return -0.5f / (a * sqrtf(a));
    case BNNSArithmeticCeil: case BNNSArithmeticFloor: case BNNSArithmeticRound: case BNNSArithmeticSign: return 0;
    case BNNSArithmeticSin: return cosf(a);
    case BNNSArithmeticCos: return -sinf(a);
    case BNNSArithmeticTan: { float t = cosf(a); return 1 / (t * t); }
    case BNNSArithmeticAsin: return 1 / sqrtf(1 - a * a);
    case BNNSArithmeticAcos: return -1 / sqrtf(1 - a * a);
    case BNNSArithmeticAtan: return 1 / (1 + a * a);
    case BNNSArithmeticSinh: return coshf(a);
    case BNNSArithmeticCosh: return sinhf(a);
    case BNNSArithmeticTanh: { float t = tanhf(a); return 1 - t * t; }
    case BNNSArithmeticAsinh: return 1 / sqrtf(a * a + 1);
    case BNNSArithmeticAcosh: return 1 / sqrtf(a * a - 1);
    case BNNSArithmeticAtanh: return 1 / (1 - a * a);
    case BNNSArithmeticPow: return k ? powf(a, b) * logf(a) : b * powf(a, b - 1);
    case BNNSArithmeticExp: return expf(a);
    case BNNSArithmeticExp2: return exp2f(a) * 0.69314718f;
    case BNNSArithmeticLog: return 1 / a;
    case BNNSArithmeticLog2: return 1 / (a * 0.69314718f);
    case BNNSArithmeticMultiplyNoNaN: return b == 0 ? 0 : (k ? a : b);
    case BNNSArithmeticDivideNoNaN: return b == 0 ? 0 : (k ? -a / (b * b) : 1 / b);
    case BNNSArithmeticMultiplyAdd: return k == 2 ? 1 : k ? a : b;
    case BNNSArithmeticMinimum: return (k == 0) == (a <= b) ? 1 : 0;
    case BNNSArithmeticMaximum: return (k == 0) == (a >= b) ? 1 : 0;
    case BNNSArithmeticSelect: return k == 0 ? 0 : (k == 1) == (a != 0) ? 1 : 0;
    case BNNSArithmeticAbs: return a > 0 ? 1 : a < 0 ? -1 : 0;
    case BNNSArithmeticNegate: return -1;
    case BNNSArithmeticReciprocal: return -1 / (a * a);
    case BNNSArithmeticSquare: return 2 * a;
    case BNNSArithmeticErf: return 1.1283791670955126f * expf(-a * a);
    default: return NAN;
    }
}

BNNSFilter BNNSFilterCreateLayerArithmetic(const BNNSLayerParametersArithmetic *p, const BNNSFilterParameters *fp) {
    if (!p || !p->arithmetic_function_fields || !bnns_activation_supported(p->activation.function)) return NULL;
    int n = bnns_arith_arity(p->arithmetic_function);
    if (!n) return NULL;
    bnns_filter *f = bnns_filter_new(BNNS_KIND_ARITHMETIC, fp);
    if (!f) return NULL;
    f->arith_fn = p->arithmetic_function;
    f->arith_n = n;
    f->arith_act = p->activation;
    if (n == 1) {
        const BNNSArithmeticUnary *u = p->arithmetic_function_fields;
        f->arith_in[0] = u->in; f->arith_type[0] = u->in_type; f->arith_out = u->out;
    } else if (n == 2) {
        const BNNSArithmeticBinary *u = p->arithmetic_function_fields;
        f->arith_in[0] = u->in1; f->arith_type[0] = u->in1_type;
        f->arith_in[1] = u->in2; f->arith_type[1] = u->in2_type; f->arith_out = u->out;
    } else {
        const BNNSArithmeticTernary *u = p->arithmetic_function_fields;
        f->arith_in[0] = u->in1; f->arith_type[0] = u->in1_type;
        f->arith_in[1] = u->in2; f->arith_type[1] = u->in2_type;
        f->arith_in[2] = u->in3; f->arith_type[2] = u->in3_type; f->arith_out = u->out;
        // Apple takes Select's condition only as Boolean.
        if (p->arithmetic_function == BNNSArithmeticSelect && u->in1.data_type != BNNSDataTypeBoolean) { BNNSFilterDestroy(f); return NULL; }
    }
    bnns_shape so, si;
    if (bnns_shape_of(&f->arith_out, &so)) { BNNSFilterDestroy(f); return NULL; }
    for (int k = 0; k < n; k++) {
        if (bnns_shape_of(&f->arith_in[k], &si) || si.rank > so.rank) { BNNSFilterDestroy(f); return NULL; }
        for (int d = 0; d < si.rank; d++) if (si.n[d] != 1 && si.n[d] != so.n[d]) { BNNSFilterDestroy(f); return NULL; }
        // Constant and parameter inputs share one array across the batch.
        if (f->arith_type[k] != BNNSSample && bnns_own(f, &f->arith_in[k])) { BNNSFilterDestroy(f); return NULL; }
    }
    return f;
}

static const void *bnns_arith_input(const bnns_filter *f, int k, const void **in, const size_t *in_stride, size_t b) {
    const BNNSNDArrayDescriptor *d = &f->arith_in[k];
    if (f->arith_type[k] != BNNSSample) return d->data ? d->data : (in ? in[k] : NULL);
    if (!in || !in[k]) return NULL;
    return bnns_offset(d, in[k], b, in_stride ? in_stride[k] : 0);
}

// Inputs broadcast to the output shape (dense, logical order) for sample b.
static int bnns_arith_inputs(const bnns_filter *f, const void **in, const size_t *in_stride, size_t b, float **vals, size_t nout) {
    bnns_shape so;
    bnns_shape_of(&f->arith_out, &so);
    for (int k = 0; k < f->arith_n; k++) {
        const void *base = bnns_arith_input(f, k, in, in_stride, b);
        bnns_shape si;
        if (!base || bnns_shape_of(&f->arith_in[k], &si)) return -1;
        vals[k] = bnns_zalloc_f(nout);
        if (!vals[k]) return -1;
        size_t idx[BNNS_MAX_TENSOR_DIMENSION] = {0}, i = 0;
        if (nout) do {
            ptrdiff_t o = 0;
            for (int d = 0; d < si.rank; d++) if (si.n[d] != 1) o += (ptrdiff_t)idx[d] * si.s[d];
            vals[k][i++] = (float)bnns_load(&f->arith_in[k], base, o);
        } while (bnns_next(idx, so.n, so.rank));
    }
    return 0;
}

static int bnns_arith_apply(bnns_filter *f, size_t batch, size_t ninputs, const void **in, const size_t *in_stride, void *out,
                            size_t out_stride, float *keep) {
    if ((int)ninputs < f->arith_n && f->arith_n > 1) {
        // Missing inputs must be constants/parameters held by the filter.
        for (int k = (int)ninputs; k < f->arith_n; k++) if (f->arith_type[k] == BNNSSample) return -1;
    }
    bnns_shape so;
    if (bnns_shape_of(&f->arith_out, &so)) return -1;
    size_t nout = bnns_shape_count(&so);
    float *y = bnns_zalloc_f(nout * batch);
    if (!y) return -1;
    int r = 0;
    for (size_t b = 0; b < batch && !r; b++) {
        float *v[3] = {0};
        r = bnns_arith_inputs(f, in, in_stride, b, v, nout);
        for (size_t i = 0; !r && i < nout; i++)
            y[b * nout + i] = bnns_arith_value(f->arith_fn, v[0][i], v[1] ? v[1][i] : 0, v[2] ? v[2][i] : 0);
        for (int k = 0; k < 3; k++) free(v[k]);
    }
    if (!r && keep) memcpy(keep, y, nout * batch * sizeof(float));
    if (!r) r = bnns_activate(&f->arith_act, 0, &so, y, batch);
    if (!r && out) r = bnns_wr_batch_logical(&f->arith_out, out, batch, out_stride, y, false);
    free(y);
    return r;
}

static int bnns_arith_backward(bnns_filter *f, size_t batch, const void **in, const size_t *in_stride, BNNSNDArrayDescriptor **in_delta,
                               const size_t *in_delta_stride, const void *out, size_t out_stride, const BNNSNDArrayDescriptor *out_delta,
                               size_t out_delta_stride) {
    bnns_shape so;
    if (bnns_shape_of(&f->arith_out, &so) || !out_delta) return -1;
    size_t nout = bnns_shape_count(&so);
    float *dy = bnns_rd_batch_logical(out_delta, bnns_delta_base(out_delta), batch, out_delta_stride);
    float *grads[3] = {0};
    int r = -1;
    if (!dy) return -1;
    if (!bnns_is_identity(&f->arith_act)) {
        float *pre = bnns_zalloc_f(nout * batch);
        float *y = out ? bnns_rd_batch_logical(&f->arith_out, out, batch, out_stride) : NULL;
        int ar = pre ? bnns_arith_apply(f, batch, (size_t)f->arith_n, in, in_stride, NULL, 0, pre) : -1;
        if (!ar) ar = bnns_activate_backward(&f->arith_act, 0, &so, pre, y, dy, batch);
        free(pre); free(y);
        if (ar) { free(dy); return -1; }
    }
    for (int k = 0; k < f->arith_n; k++) {
        if (!in_delta || !in_delta[k]) continue;
        size_t n = bnns_count(&f->arith_in[k]);
        grads[k] = bnns_zalloc_f(n * (f->arith_type[k] == BNNSSample ? batch : 1));
        if (!grads[k]) goto done;
    }
    for (size_t b = 0; b < batch; b++) {
        float *v[3] = {0};
        if (bnns_arith_inputs(f, in, in_stride, b, v, nout)) { for (int k = 0; k < 3; k++) free(v[k]); goto done; }
        for (int k = 0; k < f->arith_n; k++) {
            if (!grads[k]) continue;
            bnns_shape si;
            bnns_shape_of(&f->arith_in[k], &si);
            size_t n = bnns_shape_count(&si);
            float *g = grads[k] + (f->arith_type[k] == BNNSSample ? b * n : 0);
            size_t idx[BNNS_MAX_TENSOR_DIMENSION] = {0}, i = 0;
            if (nout) do {
                size_t lin = 0, mul = 1;
                for (int d = 0; d < si.rank; d++) { if (si.n[d] != 1) lin += idx[d] * mul; mul *= si.n[d]; }
                float part = bnns_arith_partial(f->arith_fn, k, v[0][i], v[1] ? v[1][i] : 0, v[2] ? v[2][i] : 0);
                if (part != part) { for (int q = 0; q < 3; q++) free(v[q]); goto done; }
                g[lin] += dy[b * nout + i] * part;
                i++;
            } while (bnns_next(idx, so.n, so.rank));
        }
        for (int k = 0; k < 3; k++) free(v[k]);
    }
    for (int k = 0; k < f->arith_n; k++) {
        if (!grads[k]) continue;
        // Inputs that are the same array share one gradient: accumulate the later ones.
        bool shared = false;
        for (int j = 0; j < k; j++) if (grads[j] && in_delta[j] == in_delta[k]) shared = true;
        BNNSNDArrayDescriptor d = *in_delta[k];
        if (shared) d.flags = BNNSNDArrayFlagBackpropAccumulate;
        if (f->arith_type[k] == BNNSSample) {
            if (bnns_wr_batch_logical(&d, d.data, batch, in_delta_stride ? in_delta_stride[k] : 0, grads[k], true)) goto done;
        } else if (bnns_write_delta(&d, NULL, grads[k])) goto done;
    }
    r = 0;
done:
    free(dy);
    for (int k = 0; k < 3; k++) free(grads[k]);
    return r;
}

int BNNSArithmeticFilterApplyBatch(BNNSFilter filter, size_t batch_size, size_t number_of_inputs, const void **in, const size_t *in_stride,
                                   void *out, size_t out_stride) {
    bnns_filter *f = bnns_filter_get(filter);
    if (!f || f->kind != BNNS_KIND_ARITHMETIC || !in || !in_stride) return -1;
    // Apple wants every input pointer and a nonzero stride, constants included (they are not advanced).
    for (size_t i = 0; i < number_of_inputs; i++) if (!in[i] || !in_stride[i]) return -1;
    return bnns_arith_apply(f, batch_size, number_of_inputs, in, in_stride, out, out_stride, NULL);
}

int BNNSArithmeticFilterApplyBackwardBatch(BNNSFilter filter, size_t batch_size, size_t number_of_inputs, const void **in,
                                           const size_t *in_stride, BNNSNDArrayDescriptor **in_delta, const size_t *in_delta_stride,
                                           const void *out, size_t out_stride, BNNSNDArrayDescriptor *out_delta, size_t out_delta_stride) {
    bnns_filter *f = bnns_filter_get(filter);
    if (!f || f->kind != BNNS_KIND_ARITHMETIC || (int)number_of_inputs < f->arith_n) return -1;
    return bnns_arith_backward(f, batch_size, in, in_stride, in_delta, in_delta_stride, out, out_stride, out_delta, out_delta_stride);
}

// MARK: - Permute

BNNSFilter BNNSFilterCreateLayerPermute(const BNNSLayerParametersPermute *p, const BNNSFilterParameters *fp) {
    bnns_shape si, so;
    if (!p || bnns_shape_of(&p->i_desc, &si) || bnns_shape_of(&p->o_desc, &so) || si.rank != so.rank) return NULL;
    bool seen[BNNS_MAX_TENSOR_DIMENSION] = {0};
    for (int k = 0; k < so.rank; k++) {
        size_t s = p->permutation[k];
        if (s >= (size_t)si.rank || seen[s] || si.n[s] != so.n[k]) return NULL;
        seen[s] = true;
    }
    bnns_filter *f = bnns_filter_new(BNNS_KIND_PERMUTE, fp);
    if (!f) return NULL;
    f->p.permute = *p;
    return f;
}

// out[idx] <-> in[j] with j[perm[k]] = idx[k].
static int bnns_permute_move(const BNNSLayerParametersPermute *p, const BNNSNDArrayDescriptor *src, const void *sbase,
                             const BNNSNDArrayDescriptor *dst, void *dbase, bool backward, bool delta) {
    bnns_shape si, so;
    if (bnns_shape_of(&p->i_desc, &si) || bnns_shape_of(&p->o_desc, &so) || !sbase || !dbase) return -1;
    bnns_shape ss, sd;
    bnns_shape_of(src, &ss);
    bnns_shape_of(dst, &sd);
    bool acc = delta && dst->flags == BNNSNDArrayFlagBackpropAccumulate;
    if (!bnns_shape_count(&so)) return 0;
    size_t idx[BNNS_MAX_TENSOR_DIMENSION] = {0};
    do {
        size_t j[BNNS_MAX_TENSOR_DIMENSION] = {0};
        for (int k = 0; k < so.rank; k++) j[p->permutation[k]] = idx[k];
        ptrdiff_t oi = bnns_index_offset(backward ? &ss : &sd, idx), ii = bnns_index_offset(backward ? &sd : &ss, j);
        if (backward) {
            double v = bnns_load(src, sbase, oi);
            if (acc) v += bnns_load(dst, dbase, ii);
            bnns_store(dst, dbase, ii, v);
        } else bnns_store(dst, dbase, oi, bnns_load(src, sbase, ii));
    } while (bnns_next(idx, so.n, so.rank));
    return 0;
}

int BNNSPermuteFilterApplyBackwardBatch(BNNSFilter filter, size_t batch_size, BNNSNDArrayDescriptor *in_delta, size_t in_delta_stride,
                                        const BNNSNDArrayDescriptor *out_delta, size_t out_delta_stride) {
    bnns_filter *f = bnns_filter_get(filter);
    if (!f || f->kind != BNNS_KIND_PERMUTE || !in_delta || !out_delta) return -1;
    for (size_t b = 0; b < batch_size; b++) {
        int r = bnns_permute_move(&f->p.permute, out_delta, bnns_offset(out_delta, out_delta->data, b, out_delta_stride),
                                  in_delta, bnns_offset(in_delta, in_delta->data, b, in_delta_stride), true, true);
        if (r) return r;
    }
    return 0;
}

// MARK: - Dropout

BNNSFilter BNNSFilterCreateLayerDropout(const BNNSLayerParametersDropout *p, const BNNSFilterParameters *fp) {
    if (!p || p->rate < 0 || p->rate >= 1 || bnns_count(&p->i_desc) != bnns_count(&p->o_desc)) return NULL;
    bnns_filter *f = bnns_filter_new(BNNS_KIND_DROPOUT, fp);
    if (!f) return NULL;
    f->p.dropout = *p;
    uint64_t seed = p->seed ? p->seed : (uint64_t)(uintptr_t)f ^ 0x5DEECE66Dull;
    for (int k = 0; k < 4; k++) {
        seed += 0x9E3779B97F4A7C15ull;
        uint64_t z = seed;
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ull;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBull;
        f->rng[k] = z ^ (z >> 31);
    }
    return f;
}

static int bnns_dropout_apply(bnns_filter *f, size_t batch, const void *in, size_t in_stride, void *out, size_t out_stride) {
    const BNNSLayerParametersDropout *p = &f->p.dropout;
    bnns_shape sh;
    if (bnns_shape_of(&p->i_desc, &sh)) return -1;
    size_t n = bnns_shape_count(&sh);
    float *x = bnns_rd_batch_logical(&p->i_desc, in, batch, in_stride);
    uint8_t *mask = malloc(n * batch ? n * batch : 1);
    if (!x || !mask) { free(x); free(mask); return -1; }
    float keep = 1 - p->rate;
    // Elements whose coordinates differ only along the control axes share a decision.
    for (size_t b = 0; b < batch; b++) {
        size_t idx[BNNS_MAX_TENSOR_DIMENSION] = {0};
        for (size_t i = 0; i < n; i++) {
            size_t lead = 0;
            bool grouped = false;
            for (int k = 0; k < sh.rank; k++) if ((p->control >> k) & 1 && idx[k]) grouped = true;
            if (grouped) {
                size_t mul = 1;
                for (int k = 0; k < sh.rank; k++) { if (!((p->control >> k) & 1)) lead += idx[k] * mul; mul *= sh.n[k]; }
                mask[b * n + i] = mask[b * n + lead];
            } else mask[b * n + i] = (double)(bnns_random_next(f->rng) >> 11) * 0x1.0p-53 >= p->rate;
            x[b * n + i] = mask[b * n + i] ? x[b * n + i] / keep : 0;
            bnns_next(idx, sh.n, sh.rank);
        }
    }
    free(f->mask);
    f->mask = mask;
    f->mask_count = n * batch;
    int r = bnns_wr_batch_logical(&p->o_desc, out, batch, out_stride, x, false);
    free(x);
    return r;
}

static int bnns_dropout_backward(bnns_filter *f, size_t batch, BNNSNDArrayDescriptor *in_delta, size_t in_delta_stride,
                                 const BNNSNDArrayDescriptor *out_delta, size_t out_delta_stride) {
    size_t n = bnns_count(&f->p.dropout.i_desc);
    if (!out_delta || !in_delta || !f->mask || f->mask_count != n * batch) return -1;
    float *dy = bnns_rd_batch_logical(out_delta, out_delta->data, batch, out_delta_stride);
    if (!dy) return -1;
    float keep = 1 - f->p.dropout.rate;
    for (size_t i = 0; i < n * batch; i++) dy[i] = f->mask[i] ? dy[i] / keep : 0;
    int r = bnns_wr_batch_logical(in_delta, in_delta->data, batch, in_delta_stride, dy, true);
    free(dy);
    return r;
}

// MARK: - Padding

BNNSFilter BNNSFilterCreateLayerPadding(const BNNSLayerParametersPadding *p, const BNNSFilterParameters *fp) {
    bnns_shape si, so;
    if (!p || bnns_shape_of(&p->i_desc, &si) || bnns_shape_of(&p->o_desc, &so) || si.rank != so.rank) return NULL;
    if (p->padding_mode > BNNSPaddingModeSymmetric) return NULL;
    for (int k = 0; k < si.rank; k++) {
        if (so.n[k] != si.n[k] + p->padding_size[k][0] + p->padding_size[k][1]) return NULL;
        if (p->padding_mode == BNNSPaddingModeReflect && (p->padding_size[k][0] >= si.n[k] || p->padding_size[k][1] >= si.n[k]) &&
            (p->padding_size[k][0] || p->padding_size[k][1])) return NULL;
    }
    bnns_filter *f = bnns_filter_new(BNNS_KIND_PADDING, fp);
    if (!f) return NULL;
    f->p.pad = *p;
    return f;
}

// Source coordinate of output coordinate o along a dimension, or -1 for the constant.
static long bnns_pad_source(BNNSPaddingMode mode, long o, size_t before, size_t n) {
    long i = o - (long)before, N = (long)n;
    if (i >= 0 && i < N) return i;
    if (mode == BNNSPaddingModeConstant || N == 0) return -1;
    for (int guard = 0; guard < 64 && (i < 0 || i >= N); guard++) {
        if (mode == BNNSPaddingModeReflect) {
            if (N == 1) return 0;
            i = i < 0 ? -i : 2 * (N - 1) - i;
        } else i = i < 0 ? -i - 1 : 2 * N - 1 - i;
    }
    return i >= 0 && i < N ? i : -1;
}

static double bnns_pad_constant(const BNNSLayerParametersPadding *p, BNNSDataType t) {
    uint32_t bits = p->padding_value;
    BNNSNDArrayDescriptor d = { .data_type = t, .data_scale = 1 };
    if (!bnns_type_size(t) || bnns_type_size(t) > 4) return 0;
    return bnns_load(&d, &bits, 0);
}

static int bnns_pad_move(const BNNSLayerParametersPadding *p, const BNNSNDArrayDescriptor *src, const void *sbase,
                         const BNNSNDArrayDescriptor *dst, void *dbase, bool backward) {
    bnns_shape si, so, ss, sd;
    if (bnns_shape_of(&p->i_desc, &si) || bnns_shape_of(&p->o_desc, &so) || !sbase || !dbase) return -1;
    bnns_shape_of(src, &ss);
    bnns_shape_of(dst, &sd);
    size_t nin = bnns_shape_count(&si);
    float *acc = backward ? bnns_zalloc_f(nin) : NULL;
    if (backward && !acc) return -1;
    double fill = bnns_pad_constant(p, dst->data_type);
    size_t idx[BNNS_MAX_TENSOR_DIMENSION] = {0};
    if (bnns_shape_count(&so)) do {
        size_t j[BNNS_MAX_TENSOR_DIMENSION];
        bool inside = true;
        for (int k = 0; k < so.rank; k++) {
            long s = bnns_pad_source(p->padding_mode, (long)idx[k], p->padding_size[k][0], si.n[k]);
            if (s < 0) inside = false;
            else j[k] = (size_t)s;
        }
        if (backward) {
            if (inside) {
                size_t lin = 0, mul = 1;
                for (int k = 0; k < si.rank; k++) { lin += j[k] * mul; mul *= si.n[k]; }
                acc[lin] += (float)bnns_load(src, sbase, bnns_index_offset(&ss, idx));
            }
        } else bnns_store(dst, dbase, bnns_index_offset(&sd, idx), inside ? bnns_load(src, sbase, bnns_index_offset(&ss, j)) : fill);
    } while (bnns_next(idx, so.n, so.rank));
    int r = 0;
    if (backward) r = bnns_write_delta(dst, dbase, acc);
    free(acc);
    return r;
}

// MARK: - Broadcast matrix product

BNNSFilter BNNSFilterCreateLayerBroadcastMatMul(const BNNSLayerParametersBroadcastMatMul *p, const BNNSFilterParameters *fp) {
    bnns_shape s;
    if (!p || bnns_shape_of(&p->iA_desc, &s) || bnns_shape_of(&p->iB_desc, &s) || bnns_shape_of(&p->o_desc, &s)) return NULL;
    if (p->a_is_weights && p->b_is_weights) return NULL;
    if ((p->a_is_weights && !p->iA_desc.data) || (p->b_is_weights && !p->iB_desc.data)) return NULL;
    bnns_filter *f = bnns_filter_new(BNNS_KIND_BROADCAST_MATMUL, fp);
    if (!f) return NULL;
    f->p.bmm = *p;
    if ((p->a_is_weights && bnns_own(f, &f->p.bmm.iA_desc)) || (p->b_is_weights && bnns_own(f, &f->p.bmm.iB_desc))) {
        BNNSFilterDestroy(f);
        return NULL;
    }
    return f;
}

static int bnns_bmm_apply(bnns_filter *f, size_t batch, const void *a, size_t as, const void *b, size_t bs, void *out, size_t os) {
    const BNNSLayerParametersBroadcastMatMul *p = &f->p.bmm;
    const void *B = p->quadratic ? a : b;
    size_t BS = p->quadratic ? as : bs;
    for (size_t k = 0; k < batch; k++) {
        const void *ak = p->a_is_weights ? p->iA_desc.data : bnns_offset(&p->iA_desc, a, k, as);
        const void *bk = p->b_is_weights ? p->iB_desc.data : bnns_offset(&p->iB_desc, B, k, BS);
        int r = bnns_matmul(p->transA, p->transB, p->alpha, p->beta, &p->iA_desc, ak, p->quadratic ? &p->iA_desc : &p->iB_desc, bk,
                            &p->o_desc, bnns_offset(&p->o_desc, out, k, os));
        if (r) return r;
    }
    return 0;
}

static int bnns_bmm_backward(bnns_filter *f, size_t batch, const void *a, size_t as, BNNSNDArrayDescriptor *da, size_t das,
                             const void *b, size_t bs, BNNSNDArrayDescriptor *db, size_t dbs, const BNNSNDArrayDescriptor *dc, size_t dcs) {
    const BNNSLayerParametersBroadcastMatMul *p = &f->p.bmm;
    bool tA = p->transA, tB = p->transB;
    if (!dc || p->quadratic) return -1;
    for (size_t k = 0; k < batch; k++) {
        const void *ak = p->a_is_weights ? p->iA_desc.data : bnns_offset(&p->iA_desc, a, k, as);
        const void *bk = p->b_is_weights ? p->iB_desc.data : bnns_offset(&p->iB_desc, b, k, bs);
        const void *dck = bnns_offset(dc, dc->data, k, dcs);
        if (da) {
            if (!bk) return -1;
            BNNSNDArrayDescriptor d = *da;
            bool acc = p->a_is_weights ? (k > 0 || da->flags == BNNSNDArrayFlagBackpropAccumulate) : da->flags == BNNSNDArrayFlagBackpropAccumulate;
            void *dak = p->a_is_weights ? da->data : bnns_offset(da, da->data, k, das);
            int r = !tA ? bnns_matmul(false, !tB, p->alpha, acc, dc, dck, &p->iB_desc, bk, &d, dak)
                        : bnns_matmul(tB, true, p->alpha, acc, &p->iB_desc, bk, dc, dck, &d, dak);
            if (r) return r;
        }
        if (db) {
            if (!ak) return -1;
            BNNSNDArrayDescriptor d = *db;
            bool acc = p->b_is_weights ? (k > 0 || db->flags == BNNSNDArrayFlagBackpropAccumulate) : db->flags == BNNSNDArrayFlagBackpropAccumulate;
            void *dbk = p->b_is_weights ? db->data : bnns_offset(db, db->data, k, dbs);
            int r = !tB ? bnns_matmul(!tA, false, p->alpha, acc, &p->iA_desc, ak, dc, dck, &d, dbk)
                        : bnns_matmul(true, tA, p->alpha, acc, dc, dck, &p->iA_desc, ak, &d, dbk);
            if (r) return r;
        }
    }
    return 0;
}

// MARK: - Gram matrix

BNNSFilter BNNSFilterCreateLayerGram(const BNNSLayerParametersGram *p, const BNNSFilterParameters *fp) {
    bnns_shape si, so;
    if (!p || bnns_shape_of(&p->i_desc, &si) || bnns_shape_of(&p->o_desc, &so) || so.rank != 2) return NULL;
    size_t F = si.n[si.rank - 1];
    if (so.n[0] != F || so.n[1] != F) return NULL;
    bnns_filter *f = bnns_filter_new(BNNS_KIND_GRAM, fp);
    if (!f) return NULL;
    f->p.gram = *p;
    return f;
}

static int bnns_gram_apply(bnns_filter *f, size_t batch, const void *in, size_t in_stride, void *out, size_t out_stride) {
    const BNNSLayerParametersGram *p = &f->p.gram;
    bnns_shape si;
    bnns_shape_of(&p->i_desc, &si);
    size_t F = si.n[si.rank - 1], n = bnns_shape_count(&si), S = F ? n / F : 0;
    float *g = bnns_zalloc_f(F * F);
    if (!g) return -1;
    int r = 0;
    for (size_t b = 0; b < batch && !r; b++) {
        float *x = bnns_rd(&p->i_desc, in, b, in_stride, false); // [f][s] with s fastest
        if (!x) { r = -1; break; }
        bnns_sgemm(false, true, (int)F, (int)F, (int)S, p->alpha, x, (int)S, x, (int)S, 0, g, (int)F);
        r = bnns_write(&p->o_desc, bnns_offset(&p->o_desc, out, b, out_stride), g, false);
        free(x);
    }
    free(g);
    return r;
}

static int bnns_gram_backward(bnns_filter *f, size_t batch, const void *in, size_t in_stride, BNNSNDArrayDescriptor *in_delta,
                              size_t in_delta_stride, const BNNSNDArrayDescriptor *out_delta, size_t out_delta_stride) {
    const BNNSLayerParametersGram *p = &f->p.gram;
    bnns_shape si;
    bnns_shape_of(&p->i_desc, &si);
    size_t F = si.n[si.rank - 1], n = bnns_shape_count(&si), S = F ? n / F : 0;
    if (!in || !in_delta || !out_delta) return -1;
    float *sym = bnns_zalloc_f(F * F), *dx = bnns_zalloc_f(n);
    int r = sym && dx ? 0 : -1;
    for (size_t b = 0; b < batch && !r; b++) {
        float *x = bnns_rd(&p->i_desc, in, b, in_stride, false), *dg = bnns_rd(out_delta, out_delta->data, b, out_delta_stride, false);
        if (!x || !dg) { free(x); free(dg); r = -1; break; }
        for (size_t i = 0; i < F; i++) for (size_t j = 0; j < F; j++) sym[i * F + j] = dg[i + j * F] + dg[j + i * F];
        bnns_sgemm(false, false, (int)F, (int)S, (int)F, p->alpha, sym, (int)F, x, (int)S, 0, dx, (int)S);
        r = bnns_write_delta(in_delta, bnns_offset(in_delta, in_delta->data, b, in_delta_stride), dx);
        free(x); free(dg);
    }
    free(sym); free(dx);
    return r;
}

// MARK: - Resize

BNNSFilter BNNSFilterCreateLayerResize(const BNNSLayerParametersResize *p, const BNNSFilterParameters *fp) {
    bnns_shape si, so;
    if (!p || bnns_shape_of(&p->i_desc, &si) || bnns_shape_of(&p->o_desc, &so) || si.rank != so.rank) return NULL;
    if (p->method > BNNSInterpolationMethodLinear) return NULL;
    bnns_filter *f = bnns_filter_new(BNNS_KIND_RESIZE, fp);
    if (!f) return NULL;
    f->p.resize = *p;
    return f;
}

// Weights of output coordinate o: source indices i0, i1 and fraction t.
static void bnns_resize_coord(const BNNSLayerParametersResize *p, size_t o, size_t nin, size_t nout, size_t *i0, size_t *i1, float *t) {
    double s;
    if (p->align_corners) s = nout > 1 ? (double)o * (double)(nin - 1) / (double)(nout - 1) : 0;
    else s = ((double)o + 0.5) * (double)nin / (double)nout - 0.5;
    if (p->method == BNNSInterpolationMethodNearest) {
        size_t k = p->align_corners ? (size_t)llround(s) : (size_t)floor(((double)o) * (double)nin / (double)nout);
        if (k >= nin) k = nin - 1;
        *i0 = *i1 = k; *t = 0;
        return;
    }
    if (s < 0) s = 0;
    if (s > (double)(nin - 1)) s = (double)(nin - 1);
    *i0 = (size_t)floor(s);
    *i1 = *i0 + 1 < nin ? *i0 + 1 : *i0;
    *t = (float)(s - (double)*i0);
}

// Resizes dense logical data dimension by dimension; backward applies the transpose.
static float *bnns_resize_run(const BNNSLayerParametersResize *p, const float *src, bool backward) {
    bnns_shape si, so;
    bnns_shape_of(&p->i_desc, &si);
    bnns_shape_of(&p->o_desc, &so);
    const bnns_shape *from = backward ? &so : &si, *to = backward ? &si : &so;
    size_t cur[BNNS_MAX_TENSOR_DIMENSION];
    int rank = si.rank;
    for (int k = 0; k < rank; k++) cur[k] = from->n[k];
    size_t count = bnns_shape_count(from);
    float *data = malloc((count ? count : 1) * sizeof(float));
    if (!data) return NULL;
    memcpy(data, src, count * sizeof(float));
    for (int k = 0; k < rank; k++) {
        if (cur[k] == to->n[k]) continue;
        size_t inner = 1, outer = 1;
        for (int j = 0; j < k; j++) inner *= cur[j];
        for (int j = k + 1; j < rank; j++) outer *= cur[j];
        size_t nfrom = cur[k], nto = to->n[k];
        float *next = bnns_zalloc_f(inner * nto * outer);
        if (!next) { free(data); return NULL; }
        size_t nin = backward ? nto : nfrom, nout = backward ? nfrom : nto;
        for (size_t o = 0; o < nout; o++) {
            size_t i0, i1;
            float t;
            bnns_resize_coord(p, o, nin, nout, &i0, &i1, &t);
            for (size_t q = 0; q < outer; q++)
                for (size_t r = 0; r < inner; r++) {
                    if (!backward) {
                        const float *s = data + q * nfrom * inner + r;
                        next[(q * nto + o) * inner + r] = s[i0 * inner] * (1 - t) + s[i1 * inner] * t;
                    } else {
                        float g = data[(q * nfrom + o) * inner + r];
                        next[(q * nto + i0) * inner + r] += g * (1 - t);
                        next[(q * nto + i1) * inner + r] += g * t;
                    }
                }
        }
        free(data);
        data = next;
        cur[k] = nto;
    }
    return data;
}

static int bnns_resize_apply(bnns_filter *f, size_t batch, const void *in, size_t in_stride, void *out, size_t out_stride, bool backward,
                             const BNNSNDArrayDescriptor *src_desc, BNNSNDArrayDescriptor *dst_desc) {
    const BNNSLayerParametersResize *p = &f->p.resize;
    const BNNSNDArrayDescriptor *sd = src_desc ? src_desc : &p->i_desc, *dd = dst_desc ? dst_desc : &p->o_desc;
    for (size_t b = 0; b < batch; b++) {
        float *x = bnns_rd(sd, in, b, in_stride, false);
        float *y = x ? bnns_resize_run(p, x, backward) : NULL;
        void *ob = bnns_offset(dd, out, b, out_stride);
        int r = y && ob ? (backward ? bnns_write_delta(dd, ob, y) : bnns_write(dd, ob, y, false)) : -1;
        free(x); free(y);
        if (r) return r;
    }
    return 0;
}

// MARK: - Reduction

BNNSFilter BNNSFilterCreateLayerReduction(const BNNSLayerParametersReduction *p, const BNNSFilterParameters *fp) {
    bnns_shape si, so;
    if (!p || bnns_shape_of(&p->i_desc, &si) || bnns_shape_of(&p->o_desc, &so) || si.rank != so.rank) return NULL;
    if (p->reduce_func > BNNSReduceFunctionLogSum || p->reduce_func == BNNSReduceFunctionNone) return NULL;
    bnns_filter *f = bnns_filter_new(BNNS_KIND_REDUCTION, fp);
    if (!f) return NULL;
    f->p.reduce = *p;
    if (bnns_own(f, &f->p.reduce.w_desc)) { BNNSFilterDestroy(f); return NULL; }
    return f;
}

static int bnns_reduce_apply(bnns_filter *f, size_t batch, const void *in, size_t in_stride, void *out, size_t out_stride) {
    const BNNSLayerParametersReduction *p = &f->p.reduce;
    for (size_t b = 0; b < batch; b++) {
        int r = bnns_reduce(&p->i_desc, bnns_offset(&p->i_desc, in, b, in_stride), &p->o_desc, bnns_offset(&p->o_desc, out, b, out_stride),
                            &p->w_desc, p->reduce_func, p->epsilon);
        if (r) return r;
    }
    return 0;
}

static int bnns_reduce_backward(bnns_filter *f, size_t batch, const void *in, size_t in_stride, BNNSNDArrayDescriptor *in_delta,
                                size_t in_delta_stride, const void *out, size_t out_stride, const BNNSNDArrayDescriptor *out_delta,
                                size_t out_delta_stride) {
    const BNNSLayerParametersReduction *p = &f->p.reduce;
    bnns_shape si, so;
    bnns_shape_of(&p->i_desc, &si);
    bnns_shape_of(&p->o_desc, &so);
    if (!in_delta || !out_delta) return -1;
    BNNSReduceFunction fn = p->reduce_func;
    size_t n = bnns_shape_count(&si), no = bnns_shape_count(&so), red = no ? n / no : 0;
    float *w = p->w_desc.data ? bnns_read(&p->w_desc, NULL) : NULL;
    float *dx = bnns_zalloc_f(n);
    if (!dx) { free(w); return -1; }
    int r = 0;
    for (size_t b = 0; b < batch && !r; b++) {
        float *x = in ? bnns_rd(&p->i_desc, in, b, in_stride, false) : NULL;
        float *y = out ? bnns_rd(&p->o_desc, out, b, out_stride, false) : NULL;
        float *dy = bnns_rd(out_delta, out_delta->data, b, out_delta_stride, false);
        float *yy = NULL;
        if (!dy || (fn != BNNSReduceFunctionSum && fn != BNNSReduceFunctionMean && !x)) { r = -1; goto next; }
        if (!y && x && (fn == BNNSReduceFunctionMax || fn == BNNSReduceFunctionMin || fn == BNNSReduceFunctionL2Norm || fn == BNNSReduceFunctionLogSumExp)) {
            BNNSNDArrayDescriptor od = p->o_desc;
            od.data_type = BNNSDataTypeFloat32;
            memset(od.stride, 0, sizeof od.stride);
            yy = bnns_zalloc_f(no);
            BNNSNDArrayDescriptor xd = p->i_desc;
            if (!yy || bnns_reduce(&xd, bnns_offset(&xd, in, b, in_stride), &od, yy, &p->w_desc, fn, p->epsilon)) { r = -1; goto next; }
            y = yy; yy = NULL;
        }
        size_t idx[BNNS_MAX_TENSOR_DIMENSION] = {0}, i = 0;
        bool *taken = calloc(no ? no : 1, 1);
        if (!taken) { r = -1; goto next; }
        if (n) do {
            size_t oi = 0, mul = 1;
            for (int k = 0; k < si.rank; k++) { if (so.n[k] != 1 || si.n[k] == 1) oi += idx[k] * mul; mul *= so.n[k]; }
            double wv = w ? w[i] : 1, g = dy[oi], xv = x ? x[i] : 0, d;
            switch (fn) {
            case BNNSReduceFunctionSum: d = g * wv; break;
            case BNNSReduceFunctionMean: d = g * wv / (double)red; break;
            case BNNSReduceFunctionSumSquare: d = 2 * g * xv * wv; break;
            case BNNSReduceFunctionL1Norm: d = g * wv * (xv > 0 ? 1 : xv < 0 ? -1 : 0); break;
            case BNNSReduceFunctionL2Norm: d = y[oi] > 0 ? g * xv * wv / y[oi] : 0; break;
            case BNNSReduceFunctionLogSumExp: d = g * exp(xv - y[oi]) * wv; break;
            case BNNSReduceFunctionSumLog: d = g * wv / (xv + p->epsilon); break;
            case BNNSReduceFunctionMax: case BNNSReduceFunctionMin:
                d = !taken[oi] && xv == y[oi] ? g : 0;
                if (d != 0 || xv == y[oi]) taken[oi] = true;
                break;
            default: free(taken); r = -1; goto next;
            }
            dx[i++] = (float)d;
        } while (bnns_next(idx, si.n, si.rank));
        free(taken);
        r = bnns_write_delta(in_delta, bnns_offset(in_delta, in_delta->data, b, in_delta_stride), dx);
    next:
        free(x); free(dy); free(yy); free(y);
    }
    free(w); free(dx);
    return r;
}

// MARK: - Embedding

BNNSFilter BNNSFilterCreateLayerEmbedding(const BNNSLayerParametersEmbedding *p, const BNNSFilterParameters *fp) {
    bnns_shape si, so, sd;
    if (!p || bnns_shape_of(&p->i_desc, &si) || bnns_shape_of(&p->o_desc, &so) || bnns_shape_of(&p->dictionary, &sd)) return NULL;
    if (!p->dictionary.data || bnns_float_type(p->i_desc.data_type)) return NULL;
    size_t item = bnns_count(&p->dictionary) / (sd.n[sd.rank - 1] ? sd.n[sd.rank - 1] : 1);
    if (bnns_shape_count(&so) != item * bnns_shape_count(&si)) return NULL;
    bnns_filter *f = bnns_filter_new(BNNS_KIND_EMBEDDING, fp);
    if (!f) return NULL;
    f->p.embed = *p;
    if (bnns_own(f, &f->p.embed.dictionary)) { BNNSFilterDestroy(f); return NULL; }
    return f;
}

static int bnns_embed_apply(bnns_filter *f, size_t batch, const void *in, size_t in_stride, void *out, size_t out_stride) {
    const BNNSLayerParametersEmbedding *p = &f->p.embed;
    bnns_shape si, sd;
    bnns_shape_of(&p->i_desc, &si);
    bnns_shape_of(&p->dictionary, &sd);
    size_t words = sd.n[sd.rank - 1], item = bnns_count(&p->dictionary) / (words ? words : 1), nin = bnns_shape_count(&si);
    float *dict = bnns_read(&p->dictionary, NULL); // [word][item] since the word index is the last dimension
    float *y = bnns_zalloc_f(item * nin);
    int r = dict && y ? 0 : -1;
    for (size_t b = 0; b < batch && !r; b++) {
        const void *ib = bnns_offset(&p->i_desc, in, b, in_stride);
        size_t idx[BNNS_MAX_TENSOR_DIMENSION] = {0}, q = 0;
        if (!ib) { r = -1; break; }
        if (nin) do {
            int64_t wi = bnns_load_index(&p->i_desc, ib, bnns_index_offset(&si, idx));
            float *dst = y + q * item;
            if (wi < 0 || (uint64_t)wi >= words) { r = -1; break; }
            if ((size_t)wi == p->padding_idx) memset(dst, 0, item * sizeof(float));
            else {
                memcpy(dst, dict + (size_t)wi * item, item * sizeof(float));
                if (p->max_norm != 0) {
                    double pn = p->norm_type != 0 ? p->norm_type : 2, s = 0;
                    for (size_t e = 0; e < item; e++) s += pow(fabs(dst[e]), pn);
                    double norm = pow(s, 1 / pn);
                    if (norm > p->max_norm) for (size_t e = 0; e < item; e++) dst[e] = (float)(dst[e] * p->max_norm / norm);
                }
            }
            q++;
        } while (bnns_next(idx, si.n, si.rank));
        // Output logical order: item dimensions first, then the input's.
        if (!r) r = bnns_write(&p->o_desc, bnns_offset(&p->o_desc, out, b, out_stride), y, false);
    }
    free(dict); free(y);
    return r;
}

static int bnns_embed_backward(bnns_filter *f, size_t batch, const void *in, size_t in_stride, const BNNSNDArrayDescriptor *out_delta,
                               size_t out_delta_stride, BNNSNDArrayDescriptor *weights_delta) {
    const BNNSLayerParametersEmbedding *p = &f->p.embed;
    bnns_shape si, sd;
    bnns_shape_of(&p->i_desc, &si);
    bnns_shape_of(&p->dictionary, &sd);
    if (!in || !out_delta || !weights_delta) return -1;
    size_t words = sd.n[sd.rank - 1], item = bnns_count(&p->dictionary) / (words ? words : 1), nin = bnns_shape_count(&si);
    float *dd = bnns_zalloc_f(words * item), *freq = bnns_zalloc_f(words);
    int r = dd && freq ? 0 : -1;
    for (int pass = 0; pass < 2 && !r; pass++)
        for (size_t b = 0; b < batch && !r; b++) {
            const void *ib = bnns_offset(&p->i_desc, in, b, in_stride);
            float *dy = pass ? bnns_rd(out_delta, out_delta->data, b, out_delta_stride, false) : NULL;
            if (pass && !dy) { r = -1; break; }
            size_t idx[BNNS_MAX_TENSOR_DIMENSION] = {0}, q = 0;
            if (nin) do {
                int64_t wi = bnns_load_index(&p->i_desc, ib, bnns_index_offset(&si, idx));
                if (wi >= 0 && (uint64_t)wi < words && (size_t)wi != p->padding_idx) {
                    if (!pass) freq[wi] += 1;
                    else {
                        float scale = (p->flags & BNNSEmbeddingFlagScaleGradientByFrequency) && freq[wi] > 0 ? 1 / freq[wi] : 1;
                        for (size_t e = 0; e < item; e++) dd[(size_t)wi * item + e] += dy[q * item + e] * scale;
                    }
                }
                q++;
            } while (bnns_next(idx, si.n, si.rank));
            free(dy);
        }
    if (!r) r = bnns_write_delta(weights_delta, NULL, dd);
    free(dd); free(freq);
    return r;
}

// MARK: - Fused filters

static bnns_filter *bnns_make_sub(BNNSFilterType type, const void *params, const BNNSFilterParameters *fp) {
    switch (type) {
    case BNNSConvolution: return BNNSFilterCreateLayerConvolution(params, fp);
    case BNNSTransposedConvolution: return BNNSFilterCreateLayerTransposedConvolution(params, fp);
    case BNNSFullyConnected: return BNNSFilterCreateLayerFullyConnected(params, fp);
    case BNNSArithmetic: return BNNSFilterCreateLayerArithmetic(params, fp);
    case BNNSBatchNorm: case BNNSInstanceNorm: case BNNSLayerNorm: case BNNSGroupNorm:
        return BNNSFilterCreateLayerNormalization(type, params, fp);
    case BNNSQuantization: {
        const BNNSLayerParametersQuantization *q = params;
        bnns_filter *f = bnns_filter_new(BNNS_KIND_QUANTIZATION, fp);
        if (!f) return NULL;
        f->p.quant = *q;
        if (bnns_own(f, &f->p.quant.scale) || bnns_own(f, &f->p.quant.bias)) { BNNSFilterDestroy(f); return NULL; }
        return f;
    }
    default: return NULL;
    }
}

static const BNNSNDArrayDescriptor *bnns_sub_output(const bnns_filter *f) {
    switch (f->kind) {
    case BNNS_KIND_CONVOLUTION: case BNNS_KIND_TRANSPOSED_CONVOLUTION: return &f->p.conv.o_desc;
    case BNNS_KIND_FULLY_CONNECTED: return &f->p.fc.o_desc;
    case BNNS_KIND_ARITHMETIC: return &f->arith_out;
    default: return NULL;
    }
}

BNNSFilter BNNSFilterCreateFusedLayer(size_t number_of_fused_filters, const BNNSFilterType *filter_type, const void **layer_params,
                                      const BNNSFilterParameters *fp) {
    if (number_of_fused_filters != 2 || !filter_type || !layer_params || !layer_params[0] || !layer_params[1]) return NULL;
    BNNSFilterType t0 = filter_type[0], t1 = filter_type[1];
    bool second_ok = (t1 >= BNNSBatchNorm && t1 <= BNNSGroupNorm) || (t1 == BNNSQuantization && t0 != BNNSArithmetic);
    bool first_ok = t0 == BNNSConvolution || t0 == BNNSFullyConnected || t0 == BNNSTransposedConvolution ||
                    (t0 == BNNSArithmetic && t1 >= BNNSBatchNorm && t1 <= BNNSGroupNorm);
    if (!first_ok || !second_ok) return NULL;
    bnns_filter *f = bnns_filter_new(BNNS_KIND_FUSED, fp);
    if (!f) return NULL;
    f->sub[0] = bnns_make_sub(t0, layer_params[0], fp);
    f->sub[1] = bnns_make_sub(t1, layer_params[1], fp);
    if (!f->sub[0] || !f->sub[1]) { BNNSFilterDestroy(f); return NULL; }
    return f;
}

// Intermediate buffer: float32 packed copy of the first filter's output shape.
static BNNSNDArrayDescriptor bnns_fused_mid(const bnns_filter *f) {
    BNNSNDArrayDescriptor d = *bnns_sub_output(f->sub[0]);
    memset(d.stride, 0, sizeof d.stride);
    d.data_type = BNNSDataTypeFloat32;
    d.data = NULL;
    d.data_scale = 1; d.data_bias = 0;
    d.flags = 0;
    return d;
}

static int bnns_filter_forward(bnns_filter *f, size_t batch, size_t ninputs, const void **in, const size_t *in_stride,
                               void *out, size_t out_stride, bool training);

static int bnns_fused_apply(bnns_filter *f, size_t batch, size_t ninputs, const void **in, const size_t *in_stride, void *out,
                            size_t out_stride, bool training, float **mid_out) {
    BNNSNDArrayDescriptor mid = bnns_fused_mid(f);
    size_t n = bnns_count(&mid);
    float *buf = bnns_zalloc_f(n * batch);
    if (!buf) return -1;
    int r = bnns_filter_forward(f->sub[0], batch, ninputs, in, in_stride, buf, n, training);
    if (!r) {
        bnns_filter *s = f->sub[1];
        if (s->kind == BNNS_KIND_NORMALIZATION) r = bnns_norm_apply(s, batch, buf, n, out, out_stride, training);
        else {
            BNNSLayerParametersQuantization q = s->p.quant;
            q.i_desc = mid; q.i_desc.data = buf;
            q.o_desc.data = out;
            r = BNNSDirectApplyQuantizer(&q, NULL, batch, n, out_stride);
        }
    }
    if (!r && mid_out) *mid_out = buf;
    else free(buf);
    return r;
}

int BNNSFusedFilterApplyBatch(BNNSFilter filter, size_t batch_size, const void *in, size_t in_stride, void *out, size_t out_stride, bool training) {
    bnns_filter *f = bnns_filter_get(filter);
    if (!f || f->kind != BNNS_KIND_FUSED || f->sub[0]->kind == BNNS_KIND_ARITHMETIC) return -1;
    const void *ins[1] = { in };
    size_t strides[1] = { in_stride };
    return bnns_fused_apply(f, batch_size, 1, ins, strides, out, out_stride, training, NULL);
}

int BNNSFusedFilterApplyMultiInputBatch(BNNSFilter filter, size_t batch_size, size_t number_of_inputs, const void **in, const size_t *in_stride,
                                        void *out, size_t out_stride, bool training) {
    bnns_filter *f = bnns_filter_get(filter);
    if (!f || f->kind != BNNS_KIND_FUSED) return -1;
    return bnns_fused_apply(f, batch_size, number_of_inputs, in, in_stride, out, out_stride, training, NULL);
}

static int bnns_fused_backward(bnns_filter *f, size_t batch, size_t ninputs, const void **in, const size_t *in_stride,
                               BNNSNDArrayDescriptor **in_delta, const size_t *in_delta_stride, const void *out, size_t out_stride,
                               BNNSNDArrayDescriptor *out_delta, size_t out_delta_stride, BNNSNDArrayDescriptor **params) {
    bnns_filter *a = f->sub[0], *n = f->sub[1];
    if (n->kind != BNNS_KIND_NORMALIZATION || !n->cache_x || n->cache_batch != batch) return -1;
    BNNSNDArrayDescriptor mid = bnns_fused_mid(f);
    size_t count = bnns_count(&mid);
    float *dmid = bnns_zalloc_f(count * batch);
    if (!dmid) return -1;
    BNNSNDArrayDescriptor dm = mid;
    dm.data = dmid;
    int first = a->kind == BNNS_KIND_ARITHMETIC ? 0 : 2;
    int r = bnns_norm_backward(n, batch, &dm, count, out, out_stride, out_delta, out_delta_stride,
                               params ? params[first] : NULL, params ? params[first + 1] : NULL);
    if (!r) {
        if (a->kind == BNNS_KIND_ARITHMETIC)
            r = bnns_arith_backward(a, batch, in, in_stride, in_delta, in_delta_stride, n->cache_x, count, &dm, count);
        else {
            BNNSNDArrayDescriptor *wd = params ? params[0] : NULL, *bd = params ? params[1] : NULL;
            const void *x = ninputs ? in[0] : NULL;
            size_t xs = ninputs ? in_stride[0] : 0;
            BNNSNDArrayDescriptor *id = in_delta ? in_delta[0] : NULL;
            size_t ids = in_delta_stride ? in_delta_stride[0] : 0;
            if (a->kind == BNNS_KIND_FULLY_CONNECTED) r = bnns_fc_backward(a, batch, x, xs, id, ids, n->cache_x, count, &dm, count, wd, bd);
            else r = bnns_conv_backward(a, batch, x, xs, id, ids, n->cache_x, count, &dm, count, wd, bd);
        }
    }
    free(dmid);
    return r;
}

int BNNSFusedFilterApplyBackwardBatch(BNNSFilter filter, size_t batch_size, const void *in, size_t in_stride, BNNSNDArrayDescriptor *in_delta,
                                      size_t in_delta_stride, const void *out, size_t out_stride, BNNSNDArrayDescriptor *out_delta,
                                      size_t out_delta_stride, BNNSNDArrayDescriptor **delta_parameters) {
    bnns_filter *f = bnns_filter_get(filter);
    if (!f || f->kind != BNNS_KIND_FUSED || f->sub[0]->kind == BNNS_KIND_ARITHMETIC) return -1;
    const void *ins[1] = { in };
    size_t strides[1] = { in_stride }, dstrides[1] = { in_delta_stride };
    BNNSNDArrayDescriptor *deltas[1] = { in_delta };
    return bnns_fused_backward(f, batch_size, 1, ins, strides, deltas, dstrides, out, out_stride, out_delta, out_delta_stride, delta_parameters);
}

int BNNSFusedFilterApplyBackwardMultiInputBatch(BNNSFilter filter, size_t batch_size, size_t number_of_inputs, const void **in,
                                                const size_t *in_stride, BNNSNDArrayDescriptor **in_delta, const size_t *in_delta_stride,
                                                const void *out, size_t out_stride, BNNSNDArrayDescriptor *out_delta, size_t out_delta_stride,
                                                BNNSNDArrayDescriptor **delta_parameters) {
    bnns_filter *f = bnns_filter_get(filter);
    if (!f || f->kind != BNNS_KIND_FUSED) return -1;
    return bnns_fused_backward(f, batch_size, number_of_inputs, in, in_stride, in_delta, in_delta_stride, out, out_stride, out_delta,
                               out_delta_stride, delta_parameters);
}

// MARK: - Generic apply

static int bnns_filter_forward(bnns_filter *f, size_t batch, size_t ninputs, const void **in, const size_t *in_stride,
                               void *out, size_t out_stride, bool training) {
    const void *x = ninputs ? in[0] : NULL;
    size_t xs = ninputs && in_stride ? in_stride[0] : 0;
    switch (f->kind) {
    case BNNS_KIND_CONVOLUTION: case BNNS_KIND_TRANSPOSED_CONVOLUTION: return bnns_conv_apply(f, batch, x, xs, out, out_stride, NULL);
    case BNNS_KIND_FULLY_CONNECTED: return bnns_fc_apply(f, batch, x, xs, out, out_stride, NULL);
    case BNNS_KIND_POOLING: return bnns_pool_apply(f, batch, x, xs, out, out_stride, BNNSDataTypeUInt64, NULL, 0);
    case BNNS_KIND_ACTIVATION: return bnns_act_apply(f, batch, x, xs, out, out_stride);
    case BNNS_KIND_NORMALIZATION: return bnns_norm_apply(f, batch, x, xs, out, out_stride, training);
    case BNNS_KIND_ARITHMETIC: return bnns_arith_apply(f, batch, ninputs, in, in_stride, out, out_stride, NULL);
    case BNNS_KIND_PERMUTE:
        for (size_t b = 0; b < batch; b++) {
            int r = bnns_permute_move(&f->p.permute, &f->p.permute.i_desc, bnns_offset(&f->p.permute.i_desc, x, b, xs),
                                      &f->p.permute.o_desc, bnns_offset(&f->p.permute.o_desc, out, b, out_stride), false, false);
            if (r) return r;
        }
        return 0;
    case BNNS_KIND_DROPOUT: return bnns_dropout_apply(f, batch, x, xs, out, out_stride);
    case BNNS_KIND_PADDING:
        for (size_t b = 0; b < batch; b++) {
            int r = bnns_pad_move(&f->p.pad, &f->p.pad.i_desc, bnns_offset(&f->p.pad.i_desc, x, b, xs),
                                  &f->p.pad.o_desc, bnns_offset(&f->p.pad.o_desc, out, b, out_stride), false);
            if (r) return r;
        }
        return 0;
    case BNNS_KIND_BROADCAST_MATMUL: {
        const BNNSLayerParametersBroadcastMatMul *p = &f->p.bmm;
        if (p->a_is_weights) return bnns_bmm_apply(f, batch, NULL, 0, x, xs, out, out_stride);
        if (p->b_is_weights || p->quadratic) return bnns_bmm_apply(f, batch, x, xs, NULL, 0, out, out_stride);
        if (ninputs < 2) return -1;
        return bnns_bmm_apply(f, batch, x, xs, in[1], in_stride ? in_stride[1] : 0, out, out_stride);
    }
    case BNNS_KIND_GRAM: return bnns_gram_apply(f, batch, x, xs, out, out_stride);
    case BNNS_KIND_RESIZE: return bnns_resize_apply(f, batch, x, xs, out, out_stride, false, NULL, NULL);
    case BNNS_KIND_REDUCTION: return bnns_reduce_apply(f, batch, x, xs, out, out_stride);
    case BNNS_KIND_EMBEDDING: return bnns_embed_apply(f, batch, x, xs, out, out_stride);
    case BNNS_KIND_FUSED: return bnns_fused_apply(f, batch, ninputs, in, in_stride, out, out_stride, training, NULL);
    default: return -1;
    }
}

int BNNSFilterApplyBatch(BNNSFilter filter, size_t batch_size, const void *in, size_t in_stride, void *out, size_t out_stride) {
    bnns_filter *f = bnns_filter_get(filter);
    if (!f || f->kind == BNNS_KIND_LOSS) return -1;
    const void *ins[1] = { in };
    size_t strides[1] = { in_stride };
    return bnns_filter_forward(f, batch_size, 1, ins, strides, out, out_stride, false);
}

int BNNSFilterApplyTwoInputBatch(BNNSFilter filter, size_t batch_size, const void *inA, size_t inA_stride, const void *inB, size_t inB_stride,
                                 void *out, size_t out_stride) {
    bnns_filter *f = bnns_filter_get(filter);
    if (!f) return -1;
    const void *ins[2] = { inA, inB };
    size_t strides[2] = { inA_stride, inB_stride };
    if (f->kind == BNNS_KIND_BROADCAST_MATMUL) return bnns_bmm_apply(f, batch_size, inA, inA_stride, inB, inB_stride, out, out_stride);
    if (f->kind == BNNS_KIND_ARITHMETIC) return bnns_arith_apply(f, batch_size, 2, ins, strides, out, out_stride, NULL);
    return -1;
}

// One sample: a batch of one (the strides are never stepped over).
int BNNSFilterApply(BNNSFilter filter, const void *in, void *out) { return BNNSFilterApplyBatch(filter, 1, in, 1, out, 1); }

int BNNSFilterApplyTwoInput(BNNSFilter filter, const void *inA, const void *inB, void *out) {
    return BNNSFilterApplyTwoInputBatch(filter, 1, inA, 1, inB, 1, out, 1);
}

int BNNSFilterApplyBackwardBatch(BNNSFilter filter, size_t batch_size, const void *in, size_t in_stride, BNNSNDArrayDescriptor *in_delta,
                                 size_t in_delta_stride, const void *out, size_t out_stride, const BNNSNDArrayDescriptor *out_delta,
                                 size_t out_delta_stride, BNNSNDArrayDescriptor *weights_delta, BNNSNDArrayDescriptor *bias_delta) {
    bnns_filter *f = bnns_filter_get(filter);
    if (!f || !out_delta) return -1;
    switch (f->kind) {
    case BNNS_KIND_CONVOLUTION: case BNNS_KIND_TRANSPOSED_CONVOLUTION:
        return bnns_conv_backward(f, batch_size, in, in_stride, in_delta, in_delta_stride, out, out_stride, out_delta, out_delta_stride,
                                  weights_delta, bias_delta);
    case BNNS_KIND_FULLY_CONNECTED:
        return bnns_fc_backward(f, batch_size, in, in_stride, in_delta, in_delta_stride, out, out_stride, out_delta, out_delta_stride,
                                weights_delta, bias_delta);
    case BNNS_KIND_POOLING:
        return bnns_pool_backward(f, batch_size, in, in_stride, in_delta, in_delta_stride, out, out_stride, out_delta, out_delta_stride,
                                  bias_delta, BNNSDataTypeUInt64, NULL, 0);
    case BNNS_KIND_ACTIVATION:
        return bnns_act_backward(f, batch_size, in, in_stride, in_delta, in_delta_stride, out, out_stride, out_delta, out_delta_stride, weights_delta);
    case BNNS_KIND_ARITHMETIC: {
        const void *ins[1] = { in };
        size_t strides[1] = { in_stride }, dstrides[1] = { in_delta_stride };
        BNNSNDArrayDescriptor *deltas[1] = { in_delta };
        if (f->arith_n != 1) return -1;
        return bnns_arith_backward(f, batch_size, ins, strides, deltas, dstrides, out, out_stride, out_delta, out_delta_stride);
    }
    case BNNS_KIND_PERMUTE: return BNNSPermuteFilterApplyBackwardBatch(f, batch_size, in_delta, in_delta_stride, out_delta, out_delta_stride);
    case BNNS_KIND_DROPOUT: return bnns_dropout_backward(f, batch_size, in_delta, in_delta_stride, out_delta, out_delta_stride);
    case BNNS_KIND_PADDING:
        if (!in_delta) return -1;
        for (size_t b = 0; b < batch_size; b++) {
            int r = bnns_pad_move(&f->p.pad, out_delta, bnns_offset(out_delta, out_delta->data, b, out_delta_stride),
                                  in_delta, bnns_offset(in_delta, in_delta->data, b, in_delta_stride), true);
            if (r) return r;
        }
        return 0;
    case BNNS_KIND_BROADCAST_MATMUL: {
        const BNNSLayerParametersBroadcastMatMul *p = &f->p.bmm;
        if (p->a_is_weights) return bnns_bmm_backward(f, batch_size, NULL, 0, weights_delta, 0, in, in_stride, in_delta, in_delta_stride, out_delta, out_delta_stride);
        if (p->b_is_weights) return bnns_bmm_backward(f, batch_size, in, in_stride, in_delta, in_delta_stride, NULL, 0, weights_delta, 0, out_delta, out_delta_stride);
        return -1;
    }
    case BNNS_KIND_GRAM: return bnns_gram_backward(f, batch_size, in, in_stride, in_delta, in_delta_stride, out_delta, out_delta_stride);
    case BNNS_KIND_RESIZE:
        if (!in_delta) return -1;
        return bnns_resize_apply(f, batch_size, out_delta->data, out_delta_stride, in_delta->data, in_delta_stride, true, out_delta, in_delta);
    case BNNS_KIND_REDUCTION:
        return bnns_reduce_backward(f, batch_size, in, in_stride, in_delta, in_delta_stride, out, out_stride, out_delta, out_delta_stride);
    case BNNS_KIND_EMBEDDING: return bnns_embed_backward(f, batch_size, in, in_stride, out_delta, out_delta_stride, weights_delta);
    default: return -1;
    }
}

int BNNSFilterApplyBackwardTwoInputBatch(BNNSFilter filter, size_t batch_size, const void *inA, size_t inA_stride,
                                         BNNSNDArrayDescriptor *inA_delta, size_t inA_delta_stride, const void *inB, size_t inB_stride,
                                         BNNSNDArrayDescriptor *inB_delta, size_t inB_delta_stride, const void *out, size_t out_stride,
                                         const BNNSNDArrayDescriptor *out_delta, size_t out_delta_stride,
                                         BNNSNDArrayDescriptor *weights_delta, BNNSNDArrayDescriptor *bias_delta) {
    (void)weights_delta; (void)bias_delta;
    bnns_filter *f = bnns_filter_get(filter);
    if (!f || !out_delta) return -1;
    if (f->kind == BNNS_KIND_BROADCAST_MATMUL)
        return bnns_bmm_backward(f, batch_size, inA, inA_stride, inA_delta, inA_delta_stride, inB, inB_stride, inB_delta, inB_delta_stride,
                                 out_delta, out_delta_stride);
    if (f->kind == BNNS_KIND_ARITHMETIC && f->arith_n == 2) {
        const void *ins[2] = { inA, inB };
        size_t strides[2] = { inA_stride, inB_stride }, dstrides[2] = { inA_delta_stride, inB_delta_stride };
        BNNSNDArrayDescriptor *deltas[2] = { inA_delta, inB_delta };
        return bnns_arith_backward(f, batch_size, ins, strides, deltas, dstrides, out, out_stride, out_delta, out_delta_stride);
    }
    return -1;
}
