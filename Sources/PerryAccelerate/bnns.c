// BNNS: arrays, data movement, activations, matrix products, reductions,
// norms and clipping, random numbers, nearest neighbors, optimizers.
// Everything computes in float (double for sums); other data types are
// converted on the way in and out.

#include "bnns.h"

#include <float.h>
#include <math.h>
#include <time.h>

// MARK: - Types and shapes

int bnns_layout_rank(BNNSDataLayout layout) {
    int rank = (int)((layout >> 16) & 0xF);
    return rank >= 1 && rank <= BNNS_MAX_TENSOR_DIMENSION ? rank : 0;
}

static bool bnns_first_major(BNNSDataLayout layout) {
    return (layout & 0x8000) && (layout & 1);
}

size_t bnns_type_size(BNNSDataType type) {
    unsigned bits = type & 0xFF;
    if (bits == 0 || bits % 8) return 0;
    switch (type & 0x1F0000) {
    case BNNSDataTypeFloatBit:
        return type == BNNSDataTypeFloat32 || type == BNNSDataTypeFloat16 || type == BNNSDataTypeBFloat16 ? bits / 8 : 0;
    case BNNSDataTypeIntBit: case BNNSDataTypeUIntBit: case BNNSDataTypeIndexedBit: case BNNSDataTypeMiscellaneousBit:
        return bits / 8;
    }
    return 0;
}

bool bnns_float_type(BNNSDataType type) {
    return type == BNNSDataTypeFloat32 || type == BNNSDataTypeFloat16 || type == BNNSDataTypeBFloat16;
}

static int bnns_shape_ex(const BNNSNDArrayDescriptor *d, bnns_shape *sh, bool physical) {
    memset(sh, 0, sizeof *sh);
    if (!d) return -1;
    int rank = bnns_layout_rank(d->layout);
    if (!rank) return -1;
    bool fm = bnns_first_major(d->layout);
    // Strides in memory order, with the size each pairs with.
    ptrdiff_t ps[BNNS_MAX_TENSOR_DIMENSION];
    for (int p = 0; p < rank; p++) {
        size_t paired_prev = p ? d->size[fm ? rank - p : p - 1] : 0;
        ps[p] = d->stride[p] ? (ptrdiff_t)d->stride[p] : (p ? ps[p - 1] * (ptrdiff_t)paired_prev : 1);
    }
    sh->rank = rank;
    for (int k = 0; k < rank; k++) {
        int logical = physical && fm ? rank - 1 - k : k;
        sh->n[k] = d->size[logical];
        sh->s[k] = fm ? ps[rank - 1 - logical] : ps[logical];
    }
    return 0;
}

int bnns_shape_of(const BNNSNDArrayDescriptor *d, bnns_shape *sh) { return bnns_shape_ex(d, sh, false); }
int bnns_shape_phys(const BNNSNDArrayDescriptor *d, bnns_shape *sh) { return bnns_shape_ex(d, sh, true); }

size_t bnns_shape_count(const bnns_shape *sh) {
    size_t n = 1;
    for (int k = 0; k < sh->rank; k++) n *= sh->n[k];
    return n;
}

size_t bnns_count(const BNNSNDArrayDescriptor *d) {
    bnns_shape sh;
    return bnns_shape_of(d, &sh) ? 0 : bnns_shape_count(&sh);
}

// Advances a dimension-0-fastest index; false after the last one.
bool bnns_next(size_t *idx, const size_t *n, int rank) {
    for (int k = 0; k < rank; k++) {
        if (++idx[k] < n[k]) return true;
        idx[k] = 0;
    }
    return false;
}

ptrdiff_t bnns_index_offset(const bnns_shape *sh, const size_t *idx) {
    ptrdiff_t o = 0;
    for (int k = 0; k < sh->rank; k++) o += (ptrdiff_t)idx[k] * sh->s[k];
    return o;
}

void *bnns_offset(const BNNSNDArrayDescriptor *d, const void *base, size_t batch, size_t stride) {
    if (!base) return NULL;
    return (char *)base + batch * stride * bnns_type_size(d->data_type);
}

// MARK: - Element conversion

static float bnns_half_to_float(uint16_t h) {
    uint32_t sign = (uint32_t)(h & 0x8000) << 16, exp = (h >> 10) & 0x1F, man = h & 0x3FF, bits;
    if (exp == 0) {
        if (!man) bits = sign;
        else {
            exp = 113;
            while (!(man & 0x400)) { man <<= 1; exp--; }
            bits = sign | (exp << 23) | ((man & 0x3FF) << 13);
        }
    } else if (exp == 31) bits = sign | 0x7F800000 | (man << 13);
    else bits = sign | ((exp + 112) << 23) | (man << 13);
    float f;
    memcpy(&f, &bits, 4);
    return f;
}

static uint16_t bnns_float_to_half(float f) {
    uint32_t x;
    memcpy(&x, &f, 4);
    uint16_t sign = (x >> 16) & 0x8000;
    uint32_t abs = x & 0x7FFFFFFF;
    if (abs >= 0x7F800000) return sign | 0x7C00 | (abs > 0x7F800000 ? 0x200 : 0);
    if (abs >= 0x477FF000) return sign | 0x7C00; // rounds past the largest half
    if (abs < 0x38800000) { // subnormal half
        if (abs < 0x33000000) return sign;
        uint32_t man = (abs & 0x7FFFFF) | 0x800000;
        int shift = 126 - (int)(abs >> 23);
        uint32_t half = man >> (shift + 1), rem = man & ((1u << (shift + 1)) - 1), mid = 1u << shift;
        if (rem > mid || (rem == mid && (half & 1))) half++;
        return sign | (uint16_t)half;
    }
    uint32_t v = abs - 0x38000000;
    uint32_t half = v >> 13, rem = v & 0x1FFF;
    if (rem > 0x1000 || (rem == 0x1000 && (half & 1))) half++;
    return sign | (uint16_t)half;
}

static float bnns_bf16_to_float(uint16_t b) {
    uint32_t bits = (uint32_t)b << 16;
    float f;
    memcpy(&f, &bits, 4);
    return f;
}

static uint16_t bnns_float_to_bf16(float f) {
    uint32_t x;
    memcpy(&x, &f, 4);
    if ((x & 0x7FFFFFFF) > 0x7F800000) return (uint16_t)((x >> 16) | 0x40);
    x += 0x7FFF + ((x >> 16) & 1);
    return (uint16_t)(x >> 16);
}

// The integer stored at element i, without scale or bias.
int64_t bnns_load_index(const BNNSNDArrayDescriptor *d, const void *base, ptrdiff_t i) {
    switch (d->data_type) {
    case BNNSDataTypeInt8: return ((const int8_t *)base)[i];
    case BNNSDataTypeInt16: return ((const int16_t *)base)[i];
    case BNNSDataTypeInt32: return ((const int32_t *)base)[i];
    case BNNSDataTypeInt64: return ((const int64_t *)base)[i];
    case BNNSDataTypeUInt8: case BNNSDataTypeBoolean: case BNNSDataTypeIndexed8: return ((const uint8_t *)base)[i];
    case BNNSDataTypeUInt16: return ((const uint16_t *)base)[i];
    case BNNSDataTypeUInt32: return ((const uint32_t *)base)[i];
    case BNNSDataTypeUInt64: return (int64_t)((const uint64_t *)base)[i];
    default: return (int64_t)bnns_load(d, base, i);
    }
}

static void bnns_store_int(BNNSDataType t, void *base, ptrdiff_t i, double v) {
    double lo, hi;
    switch (t) {
    case BNNSDataTypeInt8: lo = INT8_MIN; hi = INT8_MAX; break;
    case BNNSDataTypeInt16: lo = INT16_MIN; hi = INT16_MAX; break;
    case BNNSDataTypeInt32: lo = INT32_MIN; hi = INT32_MAX; break;
    case BNNSDataTypeInt64: lo = -9223372036854775808.0; hi = 9223372036854775807.0; break;
    case BNNSDataTypeUInt8: lo = 0; hi = UINT8_MAX; break;
    case BNNSDataTypeUInt16: lo = 0; hi = UINT16_MAX; break;
    case BNNSDataTypeUInt32: lo = 0; hi = UINT32_MAX; break;
    case BNNSDataTypeUInt64: lo = 0; hi = 18446744073709551615.0; break;
    default: return;
    }
    if (v != v) v = 0;
    v = trunc(v);
    if (v < lo) v = lo;
    if (v > hi) v = hi;
    switch (t) {
    case BNNSDataTypeInt8: ((int8_t *)base)[i] = (int8_t)v; break;
    case BNNSDataTypeInt16: ((int16_t *)base)[i] = (int16_t)v; break;
    case BNNSDataTypeInt32: ((int32_t *)base)[i] = (int32_t)v; break;
    case BNNSDataTypeInt64: ((int64_t *)base)[i] = v >= hi ? INT64_MAX : (int64_t)v; break;
    case BNNSDataTypeUInt8: ((uint8_t *)base)[i] = (uint8_t)v; break;
    case BNNSDataTypeUInt16: ((uint16_t *)base)[i] = (uint16_t)v; break;
    case BNNSDataTypeUInt32: ((uint32_t *)base)[i] = (uint32_t)v; break;
    case BNNSDataTypeUInt64: ((uint64_t *)base)[i] = v >= hi ? UINT64_MAX : (uint64_t)v; break;
    }
}

static void bnns_int_scale(const BNNSNDArrayDescriptor *d, double *scale, double *bias) {
    *scale = d->data_scale == 0 ? 1 : d->data_scale;
    *bias = d->data_bias;
}

double bnns_load(const BNNSNDArrayDescriptor *d, const void *base, ptrdiff_t i) {
    switch (d->data_type) {
    case BNNSDataTypeFloat32: return ((const float *)base)[i];
    case BNNSDataTypeFloat16: return bnns_half_to_float(((const uint16_t *)base)[i]);
    case BNNSDataTypeBFloat16: return bnns_bf16_to_float(((const uint16_t *)base)[i]);
    case BNNSDataTypeBoolean: return ((const uint8_t *)base)[i] != 0;
    case BNNSDataTypeIndexed8: {
        uint8_t k = ((const uint8_t *)base)[i];
        if (!d->table_data) return k;
        BNNSNDArrayDescriptor table = { .data_type = d->table_data_type, .data_scale = 1 };
        return bnns_load(&table, d->table_data, k);
    }
    default: {
        double scale, bias;
        bnns_int_scale(d, &scale, &bias);
        return (double)bnns_load_index(d, base, i) * scale + bias;
    }
    }
}

void bnns_store(const BNNSNDArrayDescriptor *d, void *base, ptrdiff_t i, double v) {
    switch (d->data_type) {
    case BNNSDataTypeFloat32: ((float *)base)[i] = (float)v; return;
    case BNNSDataTypeFloat16: ((uint16_t *)base)[i] = bnns_float_to_half((float)v); return;
    case BNNSDataTypeBFloat16: ((uint16_t *)base)[i] = bnns_float_to_bf16((float)v); return;
    case BNNSDataTypeBoolean: ((uint8_t *)base)[i] = v != 0; return;
    default: {
        double scale, bias;
        bnns_int_scale(d, &scale, &bias);
        bnns_store_int(d->data_type, base, i, (v - bias) / scale);
    }
    }
}

static bool bnns_type_ok(BNNSDataType t) {
    return bnns_type_size(t) != 0;
}

// MARK: - Dense float copies

static float *bnns_read_ex(const BNNSNDArrayDescriptor *d, const void *base, bool physical) {
    bnns_shape sh;
    if (bnns_shape_ex(d, &sh, physical)) return NULL;
    if (!base) base = d->data;
    if (!base || !bnns_type_ok(d->data_type)) return NULL;
    size_t n = bnns_shape_count(&sh);
    float *out = malloc((n ? n : 1) * sizeof(float));
    if (!out || !n) return out;
    size_t idx[BNNS_MAX_TENSOR_DIMENSION] = {0};
    size_t i = 0;
    if (d->data_type == BNNSDataTypeFloat32) {
        // Runs along dimension 0.
        do {
            const float *p = (const float *)base + bnns_index_offset(&sh, idx);
            ptrdiff_t s0 = sh.s[0];
            for (size_t j = 0; j < sh.n[0]; j++) out[i++] = p[(ptrdiff_t)j * s0];
            idx[0] = sh.n[0] - 1;
        } while (bnns_next(idx, sh.n, sh.rank));
        return out;
    }
    do out[i++] = (float)bnns_load(d, base, bnns_index_offset(&sh, idx));
    while (bnns_next(idx, sh.n, sh.rank));
    return out;
}

static int bnns_write_ex(const BNNSNDArrayDescriptor *d, void *base, const float *src, bool accumulate, bool physical) {
    bnns_shape sh;
    if (bnns_shape_ex(d, &sh, physical)) return -1;
    if (!base) base = d->data;
    if (!base || !src || !bnns_type_ok(d->data_type)) return -1;
    if (!bnns_shape_count(&sh)) return 0;
    size_t idx[BNNS_MAX_TENSOR_DIMENSION] = {0};
    size_t i = 0;
    do {
        ptrdiff_t o = bnns_index_offset(&sh, idx);
        double v = src[i++];
        if (accumulate) v += bnns_load(d, base, o);
        bnns_store(d, base, o, v);
    } while (bnns_next(idx, sh.n, sh.rank));
    return 0;
}

float *bnns_read(const BNNSNDArrayDescriptor *d, const void *base) { return bnns_read_ex(d, base, false); }
float *bnns_read_phys(const BNNSNDArrayDescriptor *d, const void *base) { return bnns_read_ex(d, base, true); }
int bnns_write(const BNNSNDArrayDescriptor *d, void *base, const float *src, bool accumulate) { return bnns_write_ex(d, base, src, accumulate, false); }
int bnns_write_phys(const BNNSNDArrayDescriptor *d, void *base, const float *src, bool accumulate) { return bnns_write_ex(d, base, src, accumulate, true); }
int bnns_write_delta(const BNNSNDArrayDescriptor *d, void *base, const float *src) {
    return bnns_write_ex(d, base, src, d && d->flags == BNNSNDArrayFlagBackpropAccumulate, false);
}
int bnns_write_delta_phys(const BNNSNDArrayDescriptor *d, void *base, const float *src) {
    return bnns_write_ex(d, base, src, d && d->flags == BNNSNDArrayFlagBackpropAccumulate, true);
}

// MARK: - Activations

bool bnns_activation_supported(BNNSActivationFunction f) {
    return f <= BNNSActivationFunctionGELUApproximationSigmoid && f != BNNSActivationFunctionIntegerLinearSaturate &&
           f != BNNSActivationFunctionIntegerLinearSaturatePerChannel && f != BNNSActivationFunctionGumbel &&
           f != BNNSActivationFunctionGumbelMax;
}

static bool bnns_activation_softmax(BNNSActivationFunction f) {
    return f == BNNSActivationFunctionSoftmax || f == BNNSActivationFunctionLogSoftmax;
}

static float bnns_sigmoid(float x) { return 1 / (1 + expf(-x)); }

float bnns_activation_value(const BNNSActivation *a, float x) {
    float al = a->alpha, be = a->beta;
    switch (a->function) {
    case BNNSActivationFunctionIdentity: return x;
    case BNNSActivationFunctionRectifiedLinear: return x < 0 ? 0 : x;
    case BNNSActivationFunctionLeakyRectifiedLinear:
    case BNNSActivationFunctionPReLUPerChannel: return x < 0 ? al * x : x;
    case BNNSActivationFunctionSigmoid: return bnns_sigmoid(x);
    case BNNSActivationFunctionTanh: return tanhf(x);
    case BNNSActivationFunctionScaledTanh: return al * tanhf(be * x);
    case BNNSActivationFunctionAbs: return fabsf(x);
    case BNNSActivationFunctionLinear: return al * x;
    case BNNSActivationFunctionClamp: return fminf(fmaxf(x, al), be);
    case BNNSActivationFunctionGELUApproximation: return 0.5f * x * (1 + tanhf(al * (x + be * x * x * x)));
    case BNNSActivationFunctionHardSigmoid: return fmaxf(0, fminf(1, al * x + be));
    case BNNSActivationFunctionSoftplus: {
        float t = be * x;
        return al * (t > 20 ? t : log1pf(expf(t)));
    }
    case BNNSActivationFunctionSoftsign: return x / (1 + fabsf(x));
    case BNNSActivationFunctionELU: return x < 0 ? al * expm1f(x) : x;
    case BNNSActivationFunctionClampedLeakyRectifiedLinear: return fminf(x < 0 ? al * x : x, be);
    case BNNSActivationFunctionLinearWithBias: return al * x + be;
    case BNNSActivationFunctionLogSigmoid: return x >= 0 ? -log1pf(expf(-x)) : x - log1pf(expf(x));
    case BNNSActivationFunctionSELU: return 1.0507009873554805f * (x < 0 ? 1.6732632423543772f * expm1f(x) : x);
    case BNNSActivationFunctionCELU: return x < 0 ? al * expm1f(x / al) : x;
    case BNNSActivationFunctionHardShrink: return fabsf(x) < fabsf(al) ? 0 : x;
    case BNNSActivationFunctionSoftShrink: return fabsf(x) < fabsf(al) ? 0 : x - copysignf(al, x);
    case BNNSActivationFunctionTanhShrink: return x - tanhf(x);
    case BNNSActivationFunctionThreshold: return x <= al ? be : x;
    case BNNSActivationFunctionHardSwish: return x * fminf(fmaxf(x + 3, 0), 6) / 6;
    case BNNSActivationFunctionSiLU: return x * bnns_sigmoid(x);
    case BNNSActivationFunctionReLU6: return fminf(fmaxf(x, 0), 6);
    case BNNSActivationFunctionErf: return erff(x);
    case BNNSActivationFunctionGELU: return 0.5f * x * (1 + erff(x * 0.70710678118654752f));
    case BNNSActivationFunctionGELUApproximationSigmoid: return x * bnns_sigmoid(1.702f * x);
    default: return x;
    }
}

// dy/dx at input x (or, when x is unavailable, from output y). NAN if neither works.
float bnns_activation_derivative(const BNNSActivation *a, const float *xp, const float *yp) {
    float al = a->alpha, be = a->beta;
    if (!xp) {
        if (!yp) return a->function == BNNSActivationFunctionIdentity ? 1 : NAN;
        float y = *yp;
        switch (a->function) {
        case BNNSActivationFunctionIdentity: return 1;
        case BNNSActivationFunctionRectifiedLinear: return y > 0;
        case BNNSActivationFunctionLeakyRectifiedLinear:
        case BNNSActivationFunctionPReLUPerChannel: return al > 0 && y < 0 ? al : 1;
        case BNNSActivationFunctionSigmoid: return y * (1 - y);
        case BNNSActivationFunctionTanh: return 1 - y * y;
        case BNNSActivationFunctionLinear: return al;
        case BNNSActivationFunctionLinearWithBias: return al;
        case BNNSActivationFunctionClamp: return y > al && y < be;
        case BNNSActivationFunctionReLU6: return y > 0 && y < 6;
        case BNNSActivationFunctionELU: return y < 0 ? y + al : 1;
        case BNNSActivationFunctionSELU: return y < 0 ? y + 1.0507009873554805f * 1.6732632423543772f : 1.0507009873554805f;
        case BNNSActivationFunctionCELU: return y < 0 ? y / al + 1 : 1;
        case BNNSActivationFunctionLogSigmoid: return 1 - expf(y);
        case BNNSActivationFunctionSoftsign: { float t = 1 - fabsf(y); return t * t; }
        case BNNSActivationFunctionHardSigmoid: return y > 0 && y < 1 ? al : 0;
        default: return NAN;
        }
    }
    float x = *xp;
    switch (a->function) {
    case BNNSActivationFunctionIdentity: return 1;
    case BNNSActivationFunctionRectifiedLinear: return x > 0;
    case BNNSActivationFunctionLeakyRectifiedLinear:
    case BNNSActivationFunctionPReLUPerChannel: return x < 0 ? al : 1;
    case BNNSActivationFunctionSigmoid: { float s = bnns_sigmoid(x); return s * (1 - s); }
    case BNNSActivationFunctionTanh: { float t = tanhf(x); return 1 - t * t; }
    case BNNSActivationFunctionScaledTanh: { float t = tanhf(be * x); return al * be * (1 - t * t); }
    case BNNSActivationFunctionAbs: return x > 0 ? 1 : x < 0 ? -1 : 0;
    case BNNSActivationFunctionLinear: return al;
    case BNNSActivationFunctionClamp: return x > al && x < be;
    case BNNSActivationFunctionGELUApproximation: {
        float u = al * (x + be * x * x * x), t = tanhf(u);
        return 0.5f * (1 + t) + 0.5f * x * (1 - t * t) * al * (1 + 3 * be * x * x);
    }
    case BNNSActivationFunctionHardSigmoid: { float t = al * x + be; return t > 0 && t < 1 ? al : 0; }
    case BNNSActivationFunctionSoftplus: return al * be * bnns_sigmoid(be * x);
    case BNNSActivationFunctionSoftsign: { float t = 1 + fabsf(x); return 1 / (t * t); }
    case BNNSActivationFunctionELU: return x < 0 ? al * expf(x) : 1;
    case BNNSActivationFunctionClampedLeakyRectifiedLinear: {
        float v = x < 0 ? al * x : x;
        return v >= be ? 0 : (x < 0 ? al : 1);
    }
    case BNNSActivationFunctionLinearWithBias: return al;
    case BNNSActivationFunctionLogSigmoid: return 1 - bnns_sigmoid(x);
    case BNNSActivationFunctionSELU: return 1.0507009873554805f * (x < 0 ? 1.6732632423543772f * expf(x) : 1);
    case BNNSActivationFunctionCELU: return x < 0 ? expf(x / al) : 1;
    case BNNSActivationFunctionHardShrink: return fabsf(x) < fabsf(al) ? 0 : 1;
    case BNNSActivationFunctionSoftShrink: return fabsf(x) < fabsf(al) ? 0 : 1;
    case BNNSActivationFunctionTanhShrink: { float t = tanhf(x); return t * t; }
    case BNNSActivationFunctionThreshold: return x <= al ? 0 : 1;
    case BNNSActivationFunctionHardSwish: return x < -3 ? 0 : x > 3 ? 1 : (2 * x + 3) / 6;
    case BNNSActivationFunctionSiLU: { float s = bnns_sigmoid(x); return s * (1 + x * (1 - s)); }
    case BNNSActivationFunctionReLU6: return x > 0 && x < 6;
    case BNNSActivationFunctionErf: return 1.1283791670955126f * expf(-x * x);
    case BNNSActivationFunctionGELU:
        return 0.5f * (1 + erff(x * 0.70710678118654752f)) + x * 0.3989422804014327f * expf(-0.5f * x * x);
    case BNNSActivationFunctionGELUApproximationSigmoid: {
        float s = bnns_sigmoid(1.702f * x);
        return s + 1.702f * x * s * (1 - s);
    }
    default: return NAN;
    }
}

// Groups for softmax: the elements of a dense array (shape sh plus a batch
// dimension of size batch at index rank) that share every coordinate outside
// the axes in axis_flags (0 means axis 0). Returns the group of each element.
static size_t *bnns_softmax_groups(uint32_t axis_flags, const bnns_shape *sh, size_t batch, size_t *ngroups) {
    int rank = sh->rank + 1;
    size_t n[BNNS_MAX_TENSOR_DIMENSION + 1];
    for (int k = 0; k < sh->rank; k++) n[k] = sh->n[k];
    n[sh->rank] = batch;
    if (!axis_flags) axis_flags = 1;
    size_t total = 1, groups = 1, gstride[BNNS_MAX_TENSOR_DIMENSION + 1];
    for (int k = 0; k < rank; k++) {
        total *= n[k];
        if (axis_flags & (1u << k)) gstride[k] = 0;
        else { gstride[k] = groups; groups *= n[k]; }
    }
    size_t *g = malloc((total ? total : 1) * sizeof(size_t));
    if (!g) return NULL;
    size_t idx[BNNS_MAX_TENSOR_DIMENSION + 1] = {0};
    for (size_t i = 0; i < total; i++) {
        size_t id = 0;
        for (int k = 0; k < rank; k++) id += idx[k] * gstride[k];
        g[i] = id;
        bnns_next(idx, n, rank);
    }
    *ngroups = groups;
    return g;
}

int bnns_activate(const BNNSActivation *a, uint32_t axis_flags, const bnns_shape *sh, float *x, size_t batch) {
    size_t total = bnns_shape_count(sh) * batch;
    if (!bnns_activation_supported(a->function)) return -1;
    if (!bnns_activation_softmax(a->function)) {
        if (a->function != BNNSActivationFunctionIdentity)
            for (size_t i = 0; i < total; i++) x[i] = bnns_activation_value(a, x[i]);
        return 0;
    }
    size_t ngroups;
    size_t *g = bnns_softmax_groups(axis_flags, sh, batch, &ngroups);
    double *mx = malloc(ngroups * sizeof(double)), *sum = calloc(ngroups, sizeof(double));
    if (!g || !mx || !sum) { free(g); free(mx); free(sum); return -1; }
    for (size_t k = 0; k < ngroups; k++) mx[k] = -INFINITY;
    for (size_t i = 0; i < total; i++) if (x[i] > mx[g[i]]) mx[g[i]] = x[i];
    for (size_t i = 0; i < total; i++) sum[g[i]] += exp(x[i] - mx[g[i]]);
    for (size_t i = 0; i < total; i++) {
        double t = x[i] - mx[g[i]];
        x[i] = (float)(a->function == BNNSActivationFunctionSoftmax ? exp(t) / sum[g[i]] : t - log(sum[g[i]]));
    }
    free(g); free(mx); free(sum);
    return 0;
}

int bnns_activate_backward(const BNNSActivation *a, uint32_t axis_flags, const bnns_shape *sh,
                           const float *x, const float *y, float *dy, size_t batch) {
    size_t total = bnns_shape_count(sh) * batch;
    if (!bnns_activation_supported(a->function)) return -1;
    if (a->function == BNNSActivationFunctionIdentity) return 0;
    if (!bnns_activation_softmax(a->function)) {
        for (size_t i = 0; i < total; i++) {
            float d = bnns_activation_derivative(a, x ? x + i : NULL, y ? y + i : NULL);
            if (d != d) return -1;
            dy[i] *= d;
        }
        return 0;
    }
    float *out = NULL;
    if (!y) {
        if (!x) return -1;
        out = malloc((total ? total : 1) * sizeof(float));
        if (!out) return -1;
        memcpy(out, x, total * sizeof(float));
        bnns_activate(a, axis_flags, sh, out, batch);
        y = out;
    }
    size_t ngroups;
    size_t *g = bnns_softmax_groups(axis_flags, sh, batch, &ngroups);
    double *dot = calloc(ngroups, sizeof(double));
    if (!g || !dot) { free(g); free(dot); free(out); return -1; }
    if (a->function == BNNSActivationFunctionSoftmax) {
        for (size_t i = 0; i < total; i++) dot[g[i]] += (double)dy[i] * y[i];
        for (size_t i = 0; i < total; i++) dy[i] = (float)(y[i] * (dy[i] - dot[g[i]]));
    } else {
        for (size_t i = 0; i < total; i++) dot[g[i]] += dy[i];
        for (size_t i = 0; i < total; i++) dy[i] = (float)(dy[i] - exp(y[i]) * dot[g[i]]);
    }
    free(g); free(dot); free(out);
    return 0;
}

// MARK: - Matrix products

extern void cblas_sgemm(int order, int transA, int transB, int M, int N, int K, float alpha, const float *A, int lda,
                        const float *B, int ldb, float beta, float *C, int ldc);

void bnns_sgemm(bool transA, bool transB, int M, int N, int K, float alpha, const float *A, int lda,
                const float *B, int ldb, float beta, float *C, int ldc) {
    if (M <= 0 || N <= 0) return;
    if (K <= 0) {
        for (int i = 0; i < M; i++)
            for (int j = 0; j < N; j++) C[i * ldc + j] = beta == 0 ? 0 : beta * C[i * ldc + j];
        return;
    }
    cblas_sgemm(101, transA ? 112 : 111, transB ? 112 : 111, M, N, K, alpha, A, lda, B, ldb, beta, C, ldc);
}

// The matrix dimensions of an array: its last two logical dimensions
// (a row-major matrix's rows are size[1]); rank 1 is one row.
static void bnns_matrix_dims(const BNNSNDArrayDescriptor *d, const bnns_shape *sh, int *row_dim, int *col_dim) {
    if (sh->rank == 1) { *row_dim = -1; *col_dim = 0; return; }
    if (d->layout == BNNSDataLayoutRowMajorMatrix) { *row_dim = 1; *col_dim = 0; return; }
    *row_dim = sh->rank - 2;
    *col_dim = sh->rank - 1;
}

int bnns_matmul(bool transA, bool transB, float alpha, float beta,
                const BNNSNDArrayDescriptor *a, const void *a_data,
                const BNNSNDArrayDescriptor *b, const void *b_data,
                const BNNSNDArrayDescriptor *c, void *c_data) {
    bnns_shape sa, sb, sc;
    if (bnns_shape_of(a, &sa) || bnns_shape_of(b, &sb) || bnns_shape_of(c, &sc)) return -1;
    if (!a_data || !b_data || !c_data) return -1;
    int ar, ac, br, bc, cr, cc;
    bnns_matrix_dims(a, &sa, &ar, &ac);
    bnns_matrix_dims(b, &sb, &br, &bc);
    bnns_matrix_dims(c, &sc, &cr, &cc);
    size_t am = ar < 0 ? 1 : sa.n[ar], ak = sa.n[ac], bk = br < 0 ? 1 : sb.n[br], bn = sb.n[bc];
    ptrdiff_t ars = ar < 0 ? 0 : sa.s[ar], acs = sa.s[ac], brs = br < 0 ? 0 : sb.s[br], bcs = sb.s[bc];
    if (transA) { size_t t = am; am = ak; ak = t; ptrdiff_t u = ars; ars = acs; acs = u; }
    if (transB) { size_t t = bk; bk = bn; bn = t; ptrdiff_t u = brs; brs = bcs; bcs = u; }
    size_t M = am, K = ak, N = bn;
    size_t cm = cr < 0 ? 1 : sc.n[cr], cn = sc.n[cc];
    if (bk != K || cm != M || cn != N) return -1;
    ptrdiff_t crs = cr < 0 ? 0 : sc.s[cr], ccs = sc.s[cc];
    // Batch dimensions: the ones before the matrix, matched from the back.
    int abatch = sa.rank > 2 ? sa.rank - 2 : 0, bbatch = sb.rank > 2 ? sb.rank - 2 : 0, cbatch = sc.rank > 2 ? sc.rank - 2 : 0;
    if (cbatch < abatch || cbatch < bbatch) return -1;
    for (int k = 0; k < cbatch; k++) {
        int ka = k - (cbatch - abatch), kb = k - (cbatch - bbatch);
        size_t na = ka >= 0 ? sa.n[ka] : 1, nb = kb >= 0 ? sb.n[kb] : 1;
        if ((na != 1 && na != sc.n[k]) || (nb != 1 && nb != sc.n[k])) return -1;
    }
    float *A = malloc((M * K ? M * K : 1) * sizeof(float)), *B = malloc((K * N ? K * N : 1) * sizeof(float));
    float *C = malloc((M * N ? M * N : 1) * sizeof(float));
    if (!A || !B || !C) { free(A); free(B); free(C); return -1; }
    size_t bidx[BNNS_MAX_TENSOR_DIMENSION] = {0}, bn_[BNNS_MAX_TENSOR_DIMENSION];
    for (int k = 0; k < cbatch; k++) bn_[k] = sc.n[k];
    do {
        ptrdiff_t ao = 0, bo = 0, co = 0;
        for (int k = 0; k < cbatch; k++) {
            int ka = k - (cbatch - abatch), kb = k - (cbatch - bbatch);
            if (ka >= 0 && sa.n[ka] != 1) ao += (ptrdiff_t)bidx[k] * sa.s[ka];
            if (kb >= 0 && sb.n[kb] != 1) bo += (ptrdiff_t)bidx[k] * sb.s[kb];
            co += (ptrdiff_t)bidx[k] * sc.s[k];
        }
        for (size_t i = 0; i < M; i++)
            for (size_t j = 0; j < K; j++) A[i * K + j] = (float)bnns_load(a, a_data, ao + (ptrdiff_t)i * ars + (ptrdiff_t)j * acs);
        for (size_t i = 0; i < K; i++)
            for (size_t j = 0; j < N; j++) B[i * N + j] = (float)bnns_load(b, b_data, bo + (ptrdiff_t)i * brs + (ptrdiff_t)j * bcs);
        if (beta != 0)
            for (size_t i = 0; i < M; i++)
                for (size_t j = 0; j < N; j++) C[i * N + j] = (float)bnns_load(c, c_data, co + (ptrdiff_t)i * crs + (ptrdiff_t)j * ccs);
        bnns_sgemm(false, false, (int)M, (int)N, (int)K, alpha, A, (int)K, B, (int)N, beta, C, (int)N);
        for (size_t i = 0; i < M; i++)
            for (size_t j = 0; j < N; j++) bnns_store(c, c_data, co + (ptrdiff_t)i * crs + (ptrdiff_t)j * ccs, C[i * N + j]);
    } while (cbatch && bnns_next(bidx, bn_, cbatch));
    free(A); free(B); free(C);
    return 0;
}

ssize_t BNNSMatMulWorkspaceSize(bool transA, bool transB, float alpha, const BNNSNDArrayDescriptor *inputA,
                                const BNNSNDArrayDescriptor *inputB, const BNNSNDArrayDescriptor *output,
                                const BNNSFilterParameters *fp) {
    (void)transA; (void)transB; (void)alpha; (void)fp;
    bnns_shape s;
    if (bnns_shape_of(inputA, &s) || bnns_shape_of(inputB, &s) || bnns_shape_of(output, &s)) return -1;
    return 0;
}

int BNNSMatMul(bool transA, bool transB, float alpha, const BNNSNDArrayDescriptor *inputA, const BNNSNDArrayDescriptor *inputB,
               const BNNSNDArrayDescriptor *output, void *workspace, const BNNSFilterParameters *fp) {
    (void)workspace; (void)fp;
    if (!inputA || !inputB || !output) return -1;
    return bnns_matmul(transA, transB, alpha, 0, inputA, inputA->data, inputB, inputB->data, output, output->data);
}

// MARK: - Arrays

size_t BNNSDataLayoutGetRank(BNNSDataLayout layout) {
    int rank = bnns_layout_rank(layout);
    return rank ? (size_t)rank : SIZE_MAX;
}

size_t BNNSNDArrayGetDataSize(const BNNSNDArrayDescriptor *array) {
    bnns_shape sh;
    if (!array || bnns_shape_of(array, &sh)) return 0;
    size_t es = bnns_type_size(array->data_type);
    if (!es) return 0;
    ptrdiff_t last = 0;
    for (int k = 0; k < sh.rank; k++) {
        if (!sh.n[k]) return 0;
        last += (ptrdiff_t)(sh.n[k] - 1) * sh.s[k];
    }
    return (size_t)(last + 1) * es;
}

size_t BNNSTensorGetAllocationSize(const BNNSTensor *tensor) {
    if (!tensor || tensor->rank > BNNS_MAX_TENSOR_DIMENSION) return SIZE_MAX;
    size_t es = bnns_type_size(tensor->data_type);
    if (!es) return SIZE_MAX;
    size_t last = 0;
    for (int k = 0; k < tensor->rank; k++) {
        if (tensor->shape[k] < 0 || tensor->stride[k] < 0) return SIZE_MAX;
        if (tensor->shape[k] == 0) return 0;
        last += (size_t)(tensor->shape[k] - 1) * (size_t)tensor->stride[k];
    }
    return (last + 1) * es;
}

static bool bnns_same_shape(const bnns_shape *a, const bnns_shape *b) {
    if (a->rank != b->rank) return false;
    for (int k = 0; k < a->rank; k++) if (a->n[k] != b->n[k]) return false;
    return true;
}

static bool bnns_int_type(BNNSDataType t) {
    return (t & (BNNSDataTypeIntBit | BNNSDataTypeUIntBit)) && bnns_type_size(t);
}

int BNNSCopy(BNNSNDArrayDescriptor *dest, const BNNSNDArrayDescriptor *src, const BNNSFilterParameters *fp) {
    (void)fp;
    bnns_shape sd, ss;
    if (!dest || !src || bnns_shape_of(dest, &sd) || bnns_shape_of(src, &ss)) return -1;
    if (!dest->data || !src->data || !bnns_type_ok(dest->data_type) || !bnns_type_ok(src->data_type)) return -1;
    if (!bnns_same_shape(&sd, &ss)) return -1;
    if (!bnns_shape_count(&sd)) return 0;
    bool ints = bnns_int_type(dest->data_type) && bnns_int_type(src->data_type) &&
                dest->data_scale == src->data_scale && dest->data_bias == src->data_bias;
    size_t idx[BNNS_MAX_TENSOR_DIMENSION] = {0};
    do {
        ptrdiff_t od = bnns_index_offset(&sd, idx), os = bnns_index_offset(&ss, idx);
        if (ints) {
            BNNSNDArrayDescriptor raw = *dest;
            raw.data_scale = 1; raw.data_bias = 0;
            int64_t v = bnns_load_index(src, src->data, os);
            if (dest->data_type == BNNSDataTypeInt64 || dest->data_type == BNNSDataTypeUInt64) ((int64_t *)dest->data)[od] = v;
            else bnns_store(&raw, dest->data, od, (double)v);
        } else if (dest->data_type == src->data_type && bnns_float_type(src->data_type)) {
            size_t es = bnns_type_size(src->data_type);
            memcpy((char *)dest->data + od * (ptrdiff_t)es, (const char *)src->data + os * (ptrdiff_t)es, es);
        } else bnns_store(dest, dest->data, od, bnns_load(src, src->data, os));
    } while (bnns_next(idx, sd.n, sd.rank));
    return 0;
}

int BNNSTranspose(BNNSNDArrayDescriptor *dest, const BNNSNDArrayDescriptor *src, size_t axis0, size_t axis1, const BNNSFilterParameters *fp) {
    (void)fp;
    bnns_shape sd, ss;
    if (!dest || !src || bnns_shape_of(dest, &sd) || bnns_shape_of(src, &ss)) return -1;
    if (sd.rank != ss.rank || axis0 >= (size_t)ss.rank || axis1 >= (size_t)ss.rank || !dest->data || !src->data) return -1;
    bnns_shape sw = ss;
    sw.n[axis0] = ss.n[axis1]; sw.s[axis0] = ss.s[axis1];
    sw.n[axis1] = ss.n[axis0]; sw.s[axis1] = ss.s[axis0];
    if (!bnns_same_shape(&sd, &sw)) return -1;
    if (!bnns_shape_count(&sd)) return 0;
    size_t idx[BNNS_MAX_TENSOR_DIMENSION] = {0};
    do bnns_store(dest, dest->data, bnns_index_offset(&sd, idx), bnns_load(src, src->data, bnns_index_offset(&sw, idx)));
    while (bnns_next(idx, sd.n, sd.rank));
    return 0;
}

int BNNSTile(const BNNSNDArrayDescriptor *input, BNNSNDArrayDescriptor *output, const BNNSFilterParameters *fp) {
    (void)fp;
    bnns_shape si, so;
    if (!input || !output || bnns_shape_of(input, &si) || bnns_shape_of(output, &so)) return -1;
    if (si.rank != so.rank || !input->data || !output->data) return -1;
    for (int k = 0; k < si.rank; k++) if (!si.n[k] || so.n[k] % si.n[k]) return -1;
    if (!bnns_shape_count(&so)) return 0;
    size_t idx[BNNS_MAX_TENSOR_DIMENSION] = {0}, src[BNNS_MAX_TENSOR_DIMENSION];
    do {
        for (int k = 0; k < si.rank; k++) src[k] = idx[k] % si.n[k];
        bnns_store(output, output->data, bnns_index_offset(&so, idx), bnns_load(input, input->data, bnns_index_offset(&si, src)));
    } while (bnns_next(idx, so.n, so.rank));
    return 0;
}

int BNNSTileBackward(BNNSNDArrayDescriptor *in_delta, const BNNSNDArrayDescriptor *out_delta, const BNNSFilterParameters *fp) {
    (void)fp;
    bnns_shape si, so;
    if (!in_delta || !out_delta || bnns_shape_of(in_delta, &si) || bnns_shape_of(out_delta, &so)) return -1;
    if (si.rank != so.rank || !in_delta->data || !out_delta->data) return -1;
    for (int k = 0; k < si.rank; k++) if (!si.n[k] || so.n[k] % si.n[k]) return -1;
    size_t ni = bnns_shape_count(&si);
    float *acc = calloc(ni ? ni : 1, sizeof(float));
    if (!acc) return -1;
    size_t idx[BNNS_MAX_TENSOR_DIMENSION] = {0};
    if (bnns_shape_count(&so)) do {
        size_t lin = 0, mul = 1;
        for (int k = 0; k < si.rank; k++) { lin += (idx[k] % si.n[k]) * mul; mul *= si.n[k]; }
        acc[lin] += (float)bnns_load(out_delta, out_delta->data, bnns_index_offset(&so, idx));
    } while (bnns_next(idx, so.n, so.rank));
    int r = bnns_write_delta(in_delta, NULL, acc);
    free(acc);
    return r;
}

// Index tensor value as an in-range position, or -1.
static ptrdiff_t bnns_checked_index(const BNNSNDArrayDescriptor *d, ptrdiff_t off, size_t limit) {
    int64_t v = bnns_load_index(d, d->data, off);
    return v >= 0 && (uint64_t)v < limit ? (ptrdiff_t)v : -1;
}

int BNNSGather(size_t axis, const BNNSNDArrayDescriptor *input, const BNNSNDArrayDescriptor *indices,
               BNNSNDArrayDescriptor *output, const BNNSFilterParameters *fp) {
    (void)fp;
    bnns_shape si, sx, so;
    if (!input || !indices || !output || bnns_shape_of(input, &si) || bnns_shape_of(indices, &sx) || bnns_shape_of(output, &so)) return -1;
    if (si.rank != so.rank || axis >= (size_t)si.rank || !input->data || !indices->data || !output->data) return -1;
    bool full = bnns_same_shape(&sx, &so) && so.rank > 1;
    if (!full && (sx.rank != 1 || sx.n[0] < so.n[axis])) return -1;
    for (int k = 0; k < so.rank; k++) if ((size_t)k != axis && so.n[k] != si.n[k]) return -1;
    if (!bnns_shape_count(&so)) return 0;
    size_t idx[BNNS_MAX_TENSOR_DIMENSION] = {0};
    do {
        ptrdiff_t io = full ? bnns_index_offset(&sx, idx) : (ptrdiff_t)idx[axis] * sx.s[0];
        ptrdiff_t j = bnns_checked_index(indices, io, si.n[axis]);
        if (j < 0) return -1;
        size_t src[BNNS_MAX_TENSOR_DIMENSION];
        memcpy(src, idx, sizeof src);
        src[axis] = (size_t)j;
        bnns_store(output, output->data, bnns_index_offset(&so, idx), bnns_load(input, input->data, bnns_index_offset(&si, src)));
    } while (bnns_next(idx, so.n, so.rank));
    return 0;
}

static int bnns_scatter_apply(BNNSReduceFunction op, BNNSNDArrayDescriptor *out, ptrdiff_t o, double v) {
    double cur;
    switch (op) {
    case BNNSReduceFunctionNone: break;
    case BNNSReduceFunctionSum: v += bnns_load(out, out->data, o); break;
    case BNNSReduceFunctionMax: cur = bnns_load(out, out->data, o); if (cur > v) v = cur; break;
    case BNNSReduceFunctionMin: cur = bnns_load(out, out->data, o); if (cur < v) v = cur; break;
    case BNNSReduceFunctionProduct: v *= bnns_load(out, out->data, o); break;
    default: return -1;
    }
    bnns_store(out, out->data, o, v);
    return 0;
}

int BNNSScatter(size_t axis, BNNSReduceFunction op, const BNNSNDArrayDescriptor *input, const BNNSNDArrayDescriptor *indices,
                BNNSNDArrayDescriptor *output, const BNNSFilterParameters *fp) {
    (void)fp;
    bnns_shape si, sx, so;
    if (!input || !indices || !output || bnns_shape_of(input, &si) || bnns_shape_of(indices, &sx) || bnns_shape_of(output, &so)) return -1;
    if (si.rank != so.rank || axis >= (size_t)si.rank || !input->data || !indices->data || !output->data) return -1;
    bool full = bnns_same_shape(&sx, &si) && si.rank > 1;
    if (!full && (sx.rank != 1 || sx.n[0] < si.n[axis])) return -1;
    for (int k = 0; k < so.rank; k++) if ((size_t)k != axis && so.n[k] != si.n[k]) return -1;
    if (!bnns_shape_count(&si)) return 0;
    size_t idx[BNNS_MAX_TENSOR_DIMENSION] = {0};
    do {
        ptrdiff_t io = full ? bnns_index_offset(&sx, idx) : (ptrdiff_t)idx[axis] * sx.s[0];
        ptrdiff_t j = bnns_checked_index(indices, io, so.n[axis]);
        if (j < 0) return -1;
        size_t dst[BNNS_MAX_TENSOR_DIMENSION];
        memcpy(dst, idx, sizeof dst);
        dst[axis] = (size_t)j;
        if (bnns_scatter_apply(op, output, bnns_index_offset(&so, dst), bnns_load(input, input->data, bnns_index_offset(&si, idx)))) return -1;
    } while (bnns_next(idx, si.n, si.rank));
    return 0;
}

// Shared by GatherND and ScatterND: "big" is the array indexed by lookup
// vectors, "small" the one shaped (indices batch dims..., slice dims...).
static int bnns_nd(bool gather, BNNSReduceFunction op, const BNNSNDArrayDescriptor *big, const BNNSNDArrayDescriptor *indices,
                   const BNNSNDArrayDescriptor *small) {
    bnns_shape sb, sx, ss;
    if (bnns_shape_of(big, &sb) || bnns_shape_of(indices, &sx) || bnns_shape_of(small, &ss)) return -1;
    if (!big->data || !indices->data || !small->data) return -1;
    size_t m = sx.n[sx.rank - 1];
    int batch_rank = sx.rank - 1, slice_rank = sb.rank - (int)m;
    if (m > (size_t)sb.rank || ss.rank != batch_rank + slice_rank) {
        // A rank-1 indices array is a single lookup vector.
        if (!(sx.rank == 1 && ss.rank == slice_rank)) return -1;
    }
    for (int k = 0; k < slice_rank; k++) if (ss.n[ss.rank - slice_rank + k] != sb.n[m + k]) return -1;
    if (!bnns_shape_count(&ss)) return 0;
    size_t idx[BNNS_MAX_TENSOR_DIMENSION] = {0};
    do {
        size_t xi[BNNS_MAX_TENSOR_DIMENSION] = {0}, bi[BNNS_MAX_TENSOR_DIMENSION] = {0};
        int sbatch = ss.rank - slice_rank;
        for (int k = 0; k < sbatch; k++) xi[k] = idx[k];
        for (size_t t = 0; t < m; t++) {
            xi[sx.rank - 1] = t;
            ptrdiff_t v = bnns_checked_index(indices, bnns_index_offset(&sx, xi), sb.n[t]);
            if (v < 0) return -1;
            bi[t] = (size_t)v;
        }
        for (int k = 0; k < slice_rank; k++) bi[m + k] = idx[sbatch + k];
        ptrdiff_t ob = bnns_index_offset(&sb, bi), os = bnns_index_offset(&ss, idx);
        if (gather) bnns_store(small, small->data, os, bnns_load(big, big->data, ob));
        else if (bnns_scatter_apply(op, (BNNSNDArrayDescriptor *)big, ob, bnns_load(small, small->data, os))) return -1;
    } while (bnns_next(idx, ss.n, ss.rank));
    return 0;
}

int BNNSGatherND(const BNNSNDArrayDescriptor *input, const BNNSNDArrayDescriptor *indices, BNNSNDArrayDescriptor *output,
                 const BNNSFilterParameters *fp) {
    (void)fp;
    if (!input || !indices || !output) return -1;
    return bnns_nd(true, BNNSReduceFunctionNone, input, indices, output);
}

int BNNSScatterND(BNNSReduceFunction op, const BNNSNDArrayDescriptor *input, const BNNSNDArrayDescriptor *indices,
                  BNNSNDArrayDescriptor *output, const BNNSFilterParameters *fp) {
    (void)fp;
    if (!input || !indices || !output) return -1;
    return bnns_nd(false, op, output, indices, input);
}

int BNNSShuffle(BNNSShuffleType type, const BNNSNDArrayDescriptor *input, BNNSNDArrayDescriptor *output, const BNNSFilterParameters *fp) {
    (void)fp;
    bnns_shape si, so;
    if (!input || !output || bnns_shape_phys(input, &si) || bnns_shape_phys(output, &so)) return -1;
    if (si.rank != so.rank || si.rank < 3 || !input->data || !output->data || type > BNNSShuffleTypeSpaceToDepthNCHW) return -1;
    bool up = type == BNNSShuffleTypePixelShuffleNCHW || type == BNNSShuffleTypeDepthToSpaceNCHW;
    // Physical order: W, H, C, then N.
    const bnns_shape *big = up ? &so : &si, *small = up ? &si : &so;
    if (!small->n[0] || !small->n[1] || big->n[0] % small->n[0]) return -1;
    size_t r = big->n[0] / small->n[0];
    if (big->n[1] != small->n[1] * r || small->n[2] != big->n[2] * r * r) return -1;
    for (int k = 3; k < si.rank; k++) if (si.n[k] != so.n[k]) return -1;
    size_t cbig = big->n[2];
    bool dcr = type == BNNSShuffleTypeDepthToSpaceNCHW || type == BNNSShuffleTypeSpaceToDepthNCHW;
    if (!bnns_shape_count(big)) return 0;
    size_t idx[BNNS_MAX_TENSOR_DIMENSION] = {0};
    do {
        size_t w = idx[0], h = idx[1], c = idx[2], i = h % r, j = w % r;
        size_t sidx[BNNS_MAX_TENSOR_DIMENSION];
        memcpy(sidx, idx, sizeof sidx);
        sidx[0] = w / r; sidx[1] = h / r;
        sidx[2] = dcr ? (i * r + j) * cbig + c : c * r * r + i * r + j;
        ptrdiff_t ob = bnns_index_offset(big, idx), os = bnns_index_offset(small, sidx);
        if (up) bnns_store(output, output->data, ob, bnns_load(input, input->data, os));
        else bnns_store(output, output->data, os, bnns_load(input, input->data, ob));
    } while (bnns_next(idx, big->n, big->rank));
    return 0;
}

int BNNSBandPart(int num_lower, int num_upper, const BNNSNDArrayDescriptor *input, BNNSNDArrayDescriptor *output,
                 const BNNSFilterParameters *fp) {
    (void)fp;
    bnns_shape si, so;
    if (!input || !output || bnns_shape_phys(input, &si) || bnns_shape_phys(output, &so)) return -1;
    if (!bnns_same_shape(&si, &so) || si.rank < 2 || !input->data || !output->data) return -1;
    if (!bnns_shape_count(&si)) return 0;
    size_t idx[BNNS_MAX_TENSOR_DIMENSION] = {0};
    do {
        long col = (long)idx[0], row = (long)idx[1];
        bool keep = (num_lower < 0 || row - col <= num_lower) && (num_upper < 0 || col - row <= num_upper);
        bnns_store(output, output->data, bnns_index_offset(&so, idx), keep ? bnns_load(input, input->data, bnns_index_offset(&si, idx)) : 0);
    } while (bnns_next(idx, si.n, si.rank));
    return 0;
}

// Offset of idx in sh when sh broadcasts (size 1, or missing trailing dimensions) to the iterated shape.
static ptrdiff_t bnns_broadcast_offset(const bnns_shape *sh, const size_t *idx) {
    ptrdiff_t o = 0;
    for (int k = 0; k < sh->rank; k++) if (sh->n[k] != 1) o += (ptrdiff_t)idx[k] * sh->s[k];
    return o;
}

static bool bnns_broadcasts(const bnns_shape *in, const bnns_shape *out) {
    if (in->rank > out->rank) return false;
    for (int k = 0; k < in->rank; k++) if (in->n[k] != 1 && in->n[k] != out->n[k]) return false;
    return true;
}

int BNNSCompareTensor(const BNNSNDArrayDescriptor *in0, const BNNSNDArrayDescriptor *in1, BNNSRelationalOperator op,
                      BNNSNDArrayDescriptor *out) {
    bnns_shape s0, s1, so;
    if (!in0 || !out || bnns_shape_of(in0, &s0) || bnns_shape_of(out, &so) || !in0->data || !out->data) return -1;
    bool unary = op == BNNSRelationalOperatorLogicalNOT;
    if (!unary && (!in1 || bnns_shape_of(in1, &s1) || !in1->data || !bnns_broadcasts(&s1, &so))) return -1;
    if (!bnns_broadcasts(&s0, &so) || op > BNNSRelationalOperatorLogicalXOR) return -1;
    // Apple's type rules: both inputs share a type, ordering needs numbers, logical operators need Boolean.
    bool boolean = in0->data_type == BNNSDataTypeBoolean;
    if (in1 && in1->data_type != in0->data_type) return -1;
    if (op >= BNNSRelationalOperatorLogicalAND ? !boolean : boolean && op != BNNSRelationalOperatorEqual && op != BNNSRelationalOperatorNotEqual) return -1;
    if (!bnns_shape_count(&so)) return 0;
    size_t idx[BNNS_MAX_TENSOR_DIMENSION] = {0};
    do {
        double a = bnns_load(in0, in0->data, bnns_broadcast_offset(&s0, idx));
        double b = unary ? 0 : bnns_load(in1, in1->data, bnns_broadcast_offset(&s1, idx));
        bool ta = a != 0, tb = b != 0, r = false;
        switch (op) {
        case BNNSRelationalOperatorEqual: r = a == b; break;
        case BNNSRelationalOperatorLess: r = a < b; break;
        case BNNSRelationalOperatorLessEqual: r = a <= b; break;
        case BNNSRelationalOperatorGreater: r = a > b; break;
        case BNNSRelationalOperatorGreaterEqual: r = a >= b; break;
        case BNNSRelationalOperatorNotEqual: r = a != b; break;
        case BNNSRelationalOperatorLogicalAND: r = ta && tb; break;
        case BNNSRelationalOperatorLogicalOR: r = ta || tb; break;
        case BNNSRelationalOperatorLogicalNOT: r = !ta; break;
        case BNNSRelationalOperatorLogicalNAND: r = !(ta && tb); break;
        case BNNSRelationalOperatorLogicalNOR: r = !(ta || tb); break;
        case BNNSRelationalOperatorLogicalXOR: r = ta != tb; break;
        }
        bnns_store(out, out->data, bnns_index_offset(&so, idx), r);
    } while (bnns_next(idx, so.n, so.rank));
    return 0;
}

// MARK: - Norms and clipping

int BNNSClipByValue(BNNSNDArrayDescriptor *dest, const BNNSNDArrayDescriptor *src, float min_val, float max_val) {
    float *x = src ? bnns_read(src, NULL) : NULL;
    if (!x || !dest || bnns_count(dest) != bnns_count(src)) { free(x); return -1; }
    size_t n = bnns_count(src);
    for (size_t i = 0; i < n; i++) x[i] = fminf(fmaxf(x[i], min_val), max_val);
    int r = bnns_write(dest, NULL, x, false);
    free(x);
    return r;
}

// Group of each element when the axes in axis_flags (0: all) are reduced away.
static size_t *bnns_axis_groups(const bnns_shape *sh, uint32_t axis_flags, size_t *ngroups) {
    bnns_shape dummy = *sh;
    uint32_t mask = axis_flags ? axis_flags : (1u << sh->rank) - 1;
    return bnns_softmax_groups(mask, &dummy, 1, ngroups);
}

int BNNSClipByNorm(BNNSNDArrayDescriptor *dest, const BNNSNDArrayDescriptor *src, float max_norm, uint32_t axis_flags) {
    bnns_shape sh;
    if (!dest || !src || bnns_shape_of(src, &sh) || bnns_count(dest) != bnns_shape_count(&sh)) return -1;
    float *x = bnns_read(src, NULL);
    size_t ng, n = bnns_shape_count(&sh);
    size_t *g = bnns_axis_groups(&sh, axis_flags, &ng);
    double *ss = calloc(ng ? ng : 1, sizeof(double));
    if (!x || !g || !ss) { free(x); free(g); free(ss); return -1; }
    for (size_t i = 0; i < n; i++) ss[g[i]] += (double)x[i] * x[i];
    for (size_t i = 0; i < n; i++) {
        double norm = sqrt(ss[g[i]]);
        if (norm > max_norm) x[i] = (float)(x[i] * max_norm / norm);
    }
    int r = bnns_write(dest, NULL, x, false);
    free(x); free(g); free(ss);
    return r;
}

int BNNSClipByGlobalNorm(BNNSNDArrayDescriptor **dest, const BNNSNDArrayDescriptor **src, size_t count, float max_norm, float use_norm) {
    if (!dest || !src) return -1;
    double norm = use_norm;
    if (norm == 0) {
        double ss = 0;
        for (size_t t = 0; t < count; t++) {
            float *x = src[t] ? bnns_read(src[t], NULL) : NULL;
            if (!x) return -1;
            size_t n = bnns_count(src[t]);
            for (size_t i = 0; i < n; i++) ss += (double)x[i] * x[i];
            free(x);
        }
        norm = sqrt(ss);
    }
    double scale = norm > max_norm ? max_norm / norm : 1;
    for (size_t t = 0; t < count; t++) {
        float *x = bnns_read(src[t], NULL);
        if (!x || !dest[t] || bnns_count(dest[t]) != bnns_count(src[t])) { free(x); return -1; }
        size_t n = bnns_count(src[t]);
        for (size_t i = 0; i < n; i++) x[i] = (float)(x[i] * scale);
        int r = bnns_write(dest[t], NULL, x, false);
        free(x);
        if (r) return r;
    }
    return 0;
}

int BNNSComputeNorm(BNNSNDArrayDescriptor *dest, const BNNSNDArrayDescriptor *src, BNNSNormType norm_type, uint32_t axis_flags) {
    bnns_shape sh;
    if (norm_type != BNNSL2Norm || !dest || !src || bnns_shape_of(src, &sh)) return -1;
    float *x = bnns_read(src, NULL);
    size_t ng, n = bnns_shape_count(&sh);
    size_t *g = bnns_axis_groups(&sh, axis_flags, &ng);
    double *ss = calloc(ng ? ng : 1, sizeof(double));
    float *out = malloc((ng ? ng : 1) * sizeof(float));
    int r = -1;
    if (x && g && ss && out && bnns_count(dest) == ng) {
        for (size_t i = 0; i < n; i++) ss[g[i]] += (double)x[i] * x[i];
        for (size_t k = 0; k < ng; k++) out[k] = (float)sqrt(ss[k]);
        r = bnns_write(dest, NULL, out, false);
    }
    free(x); free(g); free(ss); free(out);
    return r;
}

int BNNSComputeNormBackward(const void *in, BNNSNDArrayDescriptor *in_delta, const void *out,
                            const BNNSNDArrayDescriptor *out_delta, BNNSNormType norm_type, uint32_t axis_flags) {
    bnns_shape sh;
    if (norm_type != BNNSL2Norm || !in || !in_delta || !out || !out_delta || bnns_shape_of(in_delta, &sh)) return -1;
    BNNSNDArrayDescriptor xd = *in_delta, yd = *out_delta;
    xd.data = (void *)in; yd.data = (void *)out;
    xd.data_type = yd.data_type = in_delta->data_type;
    float *x = bnns_read(&xd, NULL), *y = bnns_read(&yd, NULL), *dy = bnns_read(out_delta, NULL);
    size_t ng, n = bnns_shape_count(&sh);
    size_t *g = bnns_axis_groups(&sh, axis_flags, &ng);
    float *dx = malloc((n ? n : 1) * sizeof(float));
    int r = -1;
    if (x && y && dy && g && dx && bnns_count(out_delta) == ng) {
        for (size_t i = 0; i < n; i++) dx[i] = y[g[i]] > 0 ? dy[g[i]] * x[i] / y[g[i]] : 0;
        r = bnns_write_delta(in_delta, NULL, dx);
    }
    free(x); free(y); free(dy); free(g); free(dx);
    return r;
}

// MARK: - Top K

typedef struct { float v; size_t i; } bnns_ranked;

static int bnns_rank_compare(const void *pa, const void *pb) {
    const bnns_ranked *a = pa, *b = pb;
    if (a->v != b->v) return a->v > b->v ? -1 : 1;
    return a->i < b->i ? -1 : a->i > b->i;
}

// Removes dimension axis from sh.
static bnns_shape bnns_drop_axis(const bnns_shape *sh, size_t axis) {
    bnns_shape r = { .rank = sh->rank - 1 };
    for (int k = 0, j = 0; k < sh->rank; k++) if ((size_t)k != axis) { r.n[j] = sh->n[k]; r.s[j] = sh->s[k]; j++; }
    if (r.rank == 0) { r.rank = 1; r.n[0] = 1; r.s[0] = 0; }
    return r;
}

int BNNSDirectApplyTopK(size_t K, size_t axis, size_t batch_size, const BNNSNDArrayDescriptor *input, size_t input_batch_stride,
                        BNNSNDArrayDescriptor *best_values, size_t best_values_batch_stride,
                        BNNSNDArrayDescriptor *best_indices, size_t best_indices_batch_stride, const BNNSFilterParameters *fp) {
    (void)fp;
    bnns_shape si, sv, sx;
    if (!input || !best_values || bnns_shape_of(input, &si) || bnns_shape_of(best_values, &sv)) return -1;
    if (axis >= (size_t)si.rank || sv.rank != si.rank || sv.n[axis] < K || K > si.n[axis] || !input->data || !best_values->data) return -1;
    bool want_idx = best_indices && best_indices->data;
    if (want_idx && (bnns_shape_of(best_indices, &sx) || sx.rank != si.rank)) return -1;
    size_t len = si.n[axis];
    bnns_ranked *row = malloc((len ? len : 1) * sizeof *row);
    if (!row) return -1;
    bnns_shape outer = bnns_drop_axis(&si, axis);
    for (size_t b = 0; b < batch_size; b++) {
        const void *ib = bnns_offset(input, input->data, b, input_batch_stride);
        void *vb = bnns_offset(best_values, best_values->data, b, best_values_batch_stride);
        void *xb = want_idx ? bnns_offset(best_indices, best_indices->data, b, best_indices_batch_stride) : NULL;
        size_t oidx[BNNS_MAX_TENSOR_DIMENSION] = {0};
        do {
            size_t full[BNNS_MAX_TENSOR_DIMENSION] = {0};
            for (int k = 0, j = 0; k < si.rank; k++) if ((size_t)k != axis) full[k] = oidx[j++];
            for (size_t t = 0; t < len; t++) {
                full[axis] = t;
                row[t].v = (float)bnns_load(input, ib, bnns_index_offset(&si, full));
                row[t].i = t;
            }
            qsort(row, len, sizeof *row, bnns_rank_compare);
            for (size_t t = 0; t < K; t++) {
                full[axis] = t;
                bnns_store(best_values, vb, bnns_index_offset(&sv, full), row[t].v);
                if (want_idx) {
                    BNNSNDArrayDescriptor raw = *best_indices;
                    raw.data_scale = 1; raw.data_bias = 0;
                    bnns_store(&raw, xb, bnns_index_offset(&sx, full), (double)row[t].i);
                }
            }
        } while (bnns_next(oidx, outer.n, outer.rank));
    }
    free(row);
    return 0;
}

int BNNSDirectApplyInTopK(size_t K, size_t axis, size_t batch_size, const BNNSNDArrayDescriptor *input, size_t input_batch_stride,
                          const BNNSNDArrayDescriptor *test_indices, size_t test_indices_batch_stride,
                          BNNSNDArrayDescriptor *output, size_t output_batch_stride, const BNNSFilterParameters *fp) {
    (void)fp;
    bnns_shape si, st, so;
    if (!input || !test_indices || !output || bnns_shape_of(input, &si) || bnns_shape_of(test_indices, &st) || bnns_shape_of(output, &so)) return -1;
    if (axis >= (size_t)si.rank || !input->data || !test_indices->data || !output->data) return -1;
    bnns_shape outer = bnns_drop_axis(&si, axis);
    if (bnns_shape_count(&st) != bnns_shape_count(&outer) || bnns_shape_count(&so) != bnns_shape_count(&outer)) return -1;
    size_t len = si.n[axis];
    for (size_t b = 0; b < batch_size; b++) {
        const void *ib = bnns_offset(input, input->data, b, input_batch_stride);
        const void *tb = bnns_offset(test_indices, test_indices->data, b, test_indices_batch_stride);
        void *ob = bnns_offset(output, output->data, b, output_batch_stride);
        size_t oidx[BNNS_MAX_TENSOR_DIMENSION] = {0}, lin = 0;
        do {
            size_t full[BNNS_MAX_TENSOR_DIMENSION] = {0}, tidx[BNNS_MAX_TENSOR_DIMENSION] = {0}, rem = lin;
            for (int k = 0, j = 0; k < si.rank; k++) if ((size_t)k != axis) full[k] = oidx[j++];
            for (int k = 0; k < st.rank; k++) { tidx[k] = rem % st.n[k]; rem /= st.n[k]; }
            int64_t t = bnns_load_index(test_indices, tb, bnns_index_offset(&st, tidx));
            bool r = false;
            if (t >= 0 && (uint64_t)t < len) {
                full[axis] = (size_t)t;
                float v = (float)bnns_load(input, ib, bnns_index_offset(&si, full));
                size_t greater = 0;
                for (size_t q = 0; q < len; q++) {
                    full[axis] = q;
                    if ((float)bnns_load(input, ib, bnns_index_offset(&si, full)) > v) greater++;
                }
                r = greater < K;
            }
            size_t oi[BNNS_MAX_TENSOR_DIMENSION] = {0};
            rem = lin;
            for (int k = 0; k < so.rank; k++) { oi[k] = rem % so.n[k]; rem /= so.n[k]; }
            bnns_store(output, ob, bnns_index_offset(&so, oi), r);
            lin++;
        } while (bnns_next(oidx, outer.n, outer.rank));
    }
    return 0;
}

// MARK: - Reduction

int bnns_reduce(const BNNSNDArrayDescriptor *in, const void *in_data, const BNNSNDArrayDescriptor *out, void *out_data,
                const BNNSNDArrayDescriptor *w, BNNSReduceFunction f, float epsilon) {
    bnns_shape si, so, sw;
    if (bnns_shape_of(in, &si) || bnns_shape_of(out, &so) || si.rank != so.rank || !in_data || !out_data) return -1;
    bool weighted = w && w->data;
    if (weighted && (bnns_shape_of(w, &sw) || !bnns_same_shape(&sw, &si))) return -1;
    if (f > BNNSReduceFunctionLogSum || f == BNNSReduceFunctionNone) return -1;
    uint32_t axes = 0;
    for (int k = 0; k < si.rank; k++) {
        if (so.n[k] == 1 && si.n[k] != 1) axes |= 1u << k;
        else if (so.n[k] != si.n[k]) return -1;
    }
    size_t n = bnns_shape_count(&si), no = bnns_shape_count(&so);
    double *acc = calloc(no ? no : 1, sizeof(double)), *cnt = calloc(no ? no : 1, sizeof(double)), *best = malloc((no ? no : 1) * sizeof(double));
    size_t *arg = calloc(no ? no : 1, sizeof(size_t));
    if (!acc || !cnt || !best || !arg) { free(acc); free(cnt); free(best); free(arg); return -1; }
    for (size_t k = 0; k < no; k++) {
        best[k] = f == BNNSReduceFunctionMax || f == BNNSReduceFunctionArgMax ? -INFINITY : INFINITY;
        if (f == BNNSReduceFunctionProduct || f == BNNSReduceFunctionLogicalAnd) acc[k] = 1;
    }
    size_t idx[BNNS_MAX_TENSOR_DIMENSION] = {0};
    if (n) do {
        size_t oi = 0, mul = 1, ri = 0, rmul = 1;
        for (int k = 0; k < si.rank; k++) {
            if (axes & (1u << k)) { ri += idx[k] * rmul; rmul *= si.n[k]; }
            else { oi += idx[k] * mul; mul *= so.n[k]; }
        }
        double x = bnns_load(in, in_data, bnns_index_offset(&si, idx));
        double wv = weighted ? bnns_load(w, w->data, bnns_index_offset(&sw, idx)) : 1;
        switch (f) {
        case BNNSReduceFunctionMax: case BNNSReduceFunctionArgMax:
            if (x > best[oi]) { best[oi] = x; arg[oi] = ri; } break;
        case BNNSReduceFunctionMin: case BNNSReduceFunctionArgMin:
            if (x < best[oi]) { best[oi] = x; arg[oi] = ri; } break;
        case BNNSReduceFunctionMean: case BNNSReduceFunctionSum: acc[oi] += x * wv; cnt[oi] += 1; break;
        case BNNSReduceFunctionMeanNonZero:
            // Apple divides by the number of nonzero weights; with no weights it returns the plain sum.
            acc[oi] += x * wv; if (weighted && wv != 0) cnt[oi] += 1; break;
        case BNNSReduceFunctionSumSquare: acc[oi] += x * x * wv; break;
        case BNNSReduceFunctionSumLog: acc[oi] += log(x + epsilon) * wv; break;
        case BNNSReduceFunctionL1Norm: acc[oi] += fabs(x) * wv; break;
        case BNNSReduceFunctionL2Norm: acc[oi] += x * x * wv; break;
        case BNNSReduceFunctionLogicalOr: if (x != 0) acc[oi] = 1; break;
        case BNNSReduceFunctionLogicalAnd: if (x == 0) acc[oi] = 0; break;
        case BNNSReduceFunctionLogSumExp:
            if (x > best[oi] || best[oi] == INFINITY) {
                if (best[oi] != INFINITY) acc[oi] *= exp(best[oi] - x);
                best[oi] = x;
            }
            acc[oi] += exp(x - best[oi]) * wv;
            break;
        case BNNSReduceFunctionProduct: acc[oi] *= x * wv; break;
        case BNNSReduceFunctionLogSum: acc[oi] += x * wv; break;
        }
    } while (bnns_next(idx, si.n, si.rank));
    float *res = malloc((no ? no : 1) * sizeof(float));
    if (!res) { free(acc); free(cnt); free(best); free(arg); return -1; }
    for (size_t k = 0; k < no; k++) {
        double v;
        switch (f) {
        case BNNSReduceFunctionMax: case BNNSReduceFunctionMin: v = best[k]; break;
        case BNNSReduceFunctionArgMax: case BNNSReduceFunctionArgMin: v = (double)arg[k]; break;
        case BNNSReduceFunctionMean: v = cnt[k] ? acc[k] / cnt[k] : 0; break;
        case BNNSReduceFunctionMeanNonZero: v = cnt[k] ? acc[k] / cnt[k] : acc[k]; break;
        case BNNSReduceFunctionL2Norm: v = sqrt(acc[k]); break;
        case BNNSReduceFunctionLogSumExp: v = best[k] + log(acc[k]); break;
        case BNNSReduceFunctionLogSum: v = log(acc[k] + epsilon); break;
        default: v = acc[k];
        }
        res[k] = (float)v;
    }
    int r = bnns_write(out, out_data, res, false);
    free(res); free(acc); free(cnt); free(best); free(arg);
    return r;
}

int BNNSDirectApplyReduction(const BNNSLayerParametersReduction *p, const BNNSFilterParameters *fp) {
    (void)fp;
    if (!p) return -1;
    return bnns_reduce(&p->i_desc, p->i_desc.data, &p->o_desc, p->o_desc.data, &p->w_desc, p->reduce_func, p->epsilon);
}

// MARK: - Quantization and activation

int BNNSDirectApplyQuantizer(const BNNSLayerParametersQuantization *p, const BNNSFilterParameters *fp, size_t batch_size,
                             size_t input_stride, size_t output_stride) {
    (void)fp;
    bnns_shape si, so;
    if (!p || bnns_shape_of(&p->i_desc, &si) || bnns_shape_of(&p->o_desc, &so) || !bnns_same_shape(&si, &so)) return -1;
    if (!p->i_desc.data || !p->o_desc.data || p->function > BNNSQuantizerFunctionDequantize) return -1;
    int axis = -1;
    if (p->axis_mask) {
        for (int k = 0; k <= si.rank; k++) if (p->axis_mask == (size_t)1 << k) axis = k;
        if (axis < 0) return -1;
    }
    BNNSNDArrayDescriptor in = p->i_desc, out = p->o_desc;
    in.data_scale = out.data_scale = 1;
    in.data_bias = out.data_bias = 0;
    for (size_t b = 0; b < batch_size; b++) {
        const void *ib = bnns_offset(&in, in.data, b, input_stride);
        void *ob = bnns_offset(&out, out.data, b, output_stride);
        if (!bnns_shape_count(&si)) continue;
        size_t idx[BNNS_MAX_TENSOR_DIMENSION] = {0};
        do {
            size_t c = axis < 0 ? 0 : axis == si.rank ? b : idx[axis];
            double scale = p->scale.data ? bnns_load(&p->scale, p->scale.data, (ptrdiff_t)c * (p->scale.stride[0] ? (ptrdiff_t)p->scale.stride[0] : 1)) : 1;
            double bias = p->bias.data ? bnns_load(&p->bias, p->bias.data, (ptrdiff_t)c * (p->bias.stride[0] ? (ptrdiff_t)p->bias.stride[0] : 1)) : 0;
            double x = bnns_load(&in, ib, bnns_index_offset(&si, idx)), y;
            // Apple: quantize is x * scale + bias, rounded half to even (then saturated);
            // dequantize is the inverse, (x - bias) / scale.
            if (p->function == BNNSQuantizerFunctionQuantize) {
                y = x * scale + bias;
                if (!bnns_float_type(out.data_type)) y = nearbyint(y);
            } else y = (x - bias) / scale;
            bnns_store(&out, ob, bnns_index_offset(&so, idx), y);
        } while (bnns_next(idx, si.n, si.rank));
    }
    return 0;
}

int BNNSDirectApplyActivationBatch(const BNNSLayerParametersActivation *p, const BNNSFilterParameters *fp, size_t batch_size,
                                   size_t in_stride, size_t out_stride) {
    (void)fp;
    bnns_shape si, so;
    if (!p || bnns_shape_of(&p->i_desc, &si) || bnns_shape_of(&p->o_desc, &so) || !bnns_same_shape(&si, &so)) return -1;
    if (!p->i_desc.data || !p->o_desc.data || !bnns_activation_supported(p->activation.function)) return -1;
    size_t n = bnns_shape_count(&si);
    float *x = malloc((n * batch_size ? n * batch_size : 1) * sizeof(float));
    if (!x) return -1;
    for (size_t b = 0; b < batch_size; b++) {
        float *t = bnns_read(&p->i_desc, bnns_offset(&p->i_desc, p->i_desc.data, b, in_stride));
        if (!t) { free(x); return -1; }
        memcpy(x + b * n, t, n * sizeof(float));
        free(t);
    }
    int r = bnns_activate(&p->activation, p->axis_flags, &si, x, batch_size);
    for (size_t b = 0; !r && b < batch_size; b++)
        r = bnns_write(&p->o_desc, bnns_offset(&p->o_desc, p->o_desc.data, b, out_stride), x + b * n, false);
    free(x);
    return r;
}

// MARK: - Crop and resize

// Sampling positions along one spatial axis for an output of length n, from box edges lo..hi.
static double bnns_crop_position(const BNNSLayerParametersCropResize *p, double lo, double hi, size_t i, size_t n) {
    switch (p->sampling_mode) {
    case BNNSLinearSamplingUnalignCorners: {
        double step = (hi - lo) / (double)n;
        return lo + ((double)i + 0.5) * step - 0.5;
    }
    case BNNSLinearSamplingOffsetCorners: {
        double step = (hi - lo) / (double)n;
        return lo + 0.5 * step + (double)i * step;
    }
    default:
        return n > 1 ? lo + (double)i * (hi - lo) / (double)(n - 1) : (lo + hi) / 2;
    }
}

// Box edges in pixels: x0, x1, y0, y1; box batch index.
static int bnns_crop_box(const BNNSLayerParametersCropResize *p, const float *roi, size_t roi_len, size_t width, size_t height,
                         double *x0, double *x1, double *y0, double *y1, size_t *image) {
    const float *c = roi_len >= 5 ? roi + 1 : roi;
    *image = roi_len >= 5 ? (size_t)roi[0] : 0;
    double a = c[0], b = c[1], d = c[2], e = c[3];
    switch (p->box_coordinate_mode) {
    case BNNSCornersHeightFirst: *y0 = a; *x0 = b; *y1 = d; *x1 = e; break;
    case BNNSCornersWidthFirst: *x0 = a; *y0 = b; *x1 = d; *y1 = e; break;
    case BNNSCenterSizeHeightFirst: *y0 = a - d / 2; *x0 = b - e / 2; *y1 = a + d / 2; *x1 = b + e / 2; break;
    case BNNSCenterSizeWidthFirst: *x0 = a - d / 2; *y0 = b - e / 2; *x1 = a + d / 2; *y1 = b + e / 2; break;
    default: return -1;
    }
    double sx = p->normalized_coordinates ? (double)(width - 1) : 1, sy = p->normalized_coordinates ? (double)(height - 1) : 1;
    double sc = p->spatial_scale ? p->spatial_scale : 1;
    *x0 *= sx * sc; *x1 *= sx * sc; *y0 *= sy * sc; *y1 *= sy * sc;
    return 0;
}

static int bnns_crop_resize(const BNNSLayerParametersCropResize *p, const BNNSNDArrayDescriptor *input, BNNSNDArrayDescriptor *in_delta,
                            const BNNSNDArrayDescriptor *roi, const BNNSNDArrayDescriptor *output, bool backward) {
    const BNNSNDArrayDescriptor *image_desc = backward ? in_delta : input;
    bnns_shape si, so, sr;
    if (!p || !image_desc || !roi || !output || bnns_shape_phys(image_desc, &si) || bnns_shape_phys(output, &so) || bnns_shape_phys(roi, &sr)) return -1;
    if (si.rank < 3 || so.rank < 3 || si.n[2] != so.n[2]) return -1;
    size_t W = si.n[0], H = si.n[1], C = si.n[2], N = si.rank > 3 ? si.n[3] : 1;
    size_t OW = so.n[0], OH = so.n[1], boxes = so.rank > 3 ? so.n[3] : 1;
    size_t roi_len = sr.n[0];
    if (roi_len < 4 || bnns_shape_count(&sr) / roi_len < boxes) return -1;
    float *img = backward ? calloc(W * H * C * N ? W * H * C * N : 1, sizeof(float)) : bnns_read_phys(input, NULL);
    float *boxv = bnns_read_phys(roi, NULL);
    float *o = backward ? bnns_read_phys(output, NULL) : malloc((OW * OH * C * boxes ? OW * OH * C * boxes : 1) * sizeof(float));
    int r = -1;
    if (!img || !boxv || !o) goto done;
    for (size_t bx = 0; bx < boxes; bx++) {
        double x0, x1, y0, y1;
        size_t image;
        if (bnns_crop_box(p, boxv + bx * roi_len, roi_len, W, H, &x0, &x1, &y0, &y1, &image) || image >= N) goto done;
        for (size_t oy = 0; oy < OH; oy++) {
            double fy = bnns_crop_position(p, y0, y1, oy, OH);
            for (size_t ox = 0; ox < OW; ox++) {
                double fx = bnns_crop_position(p, x0, x1, ox, OW);
                bool outside = fx < 0 || fy < 0 || fx > (double)(W - 1) || fy > (double)(H - 1);
                long xa = (long)floor(fx), ya = (long)floor(fy);
                long xb = xa + 1 < (long)W ? xa + 1 : xa, yb = ya + 1 < (long)H ? ya + 1 : ya;
                double tx = fx - xa, ty = fy - ya;
                if (p->method == BNNSInterpolationMethodNearest) { xa = xb = lround(fx); ya = yb = lround(fy); tx = ty = 0; }
                for (size_t c = 0; c < C; c++) {
                    size_t oo = ((bx * C + c) * OH + oy) * OW + ox;
                    float *plane = img + (image * C + c) * W * H;
                    if (outside) {
                        if (!backward) o[oo] = p->extrapolation_value;
                        continue;
                    }
                    double w00 = (1 - tx) * (1 - ty), w01 = tx * (1 - ty), w10 = (1 - tx) * ty, w11 = tx * ty;
                    if (backward) {
                        double g = o[oo];
                        plane[ya * (long)W + xa] += (float)(g * w00);
                        plane[ya * (long)W + xb] += (float)(g * w01);
                        plane[yb * (long)W + xa] += (float)(g * w10);
                        plane[yb * (long)W + xb] += (float)(g * w11);
                    } else {
                        o[oo] = (float)(plane[ya * (long)W + xa] * w00 + plane[ya * (long)W + xb] * w01 +
                                        plane[yb * (long)W + xa] * w10 + plane[yb * (long)W + xb] * w11);
                    }
                }
            }
        }
    }
    r = backward ? bnns_write_delta_phys(in_delta, NULL, img) : bnns_write_phys(output, NULL, o, false);
done:
    free(img); free(boxv); free(o);
    return r;
}

int BNNSCropResize(const BNNSLayerParametersCropResize *p, const BNNSNDArrayDescriptor *input, const BNNSNDArrayDescriptor *roi,
                   BNNSNDArrayDescriptor *output, const BNNSFilterParameters *fp) {
    (void)fp;
    return bnns_crop_resize(p, input, NULL, roi, output, false);
}

int BNNSCropResizeBackward(const BNNSLayerParametersCropResize *p, BNNSNDArrayDescriptor *in_delta, const BNNSNDArrayDescriptor *roi,
                           const BNNSNDArrayDescriptor *out_delta, const BNNSFilterParameters *fp) {
    (void)fp;
    return bnns_crop_resize(p, NULL, in_delta, roi, out_delta, true);
}

// MARK: - Optimizers

typedef struct {
    float lr, gscale, rscale, cmin, cmax, max_norm, use_norm;
    BNNSOptimizerRegularizationFunction reg;
    BNNSOptimizerClippingFunction clip;
} bnns_opt_common;

static float bnns_regularized(const bnns_opt_common *c, float g, float w) {
    if (c->reg == BNNSOptimizerRegularizationL1) return g + c->rscale * (w > 0 ? 1.0f : w < 0 ? -1.0f : 0.0f);
    if (c->reg == BNNSOptimizerRegularizationL2) return g + c->rscale * w;
    return g;
}

int BNNSOptimizerStep(BNNSOptimizerFunction function, const void *fields, size_t count, BNNSNDArrayDescriptor **parameters,
                      const BNNSNDArrayDescriptor **gradients, BNNSNDArrayDescriptor **accumulators, const BNNSFilterParameters *fp) {
    (void)fp;
    if (!fields || !parameters || !gradients) return -1;
    bnns_opt_common c = { .clip = BNNSOptimizerClippingNone };
    float momentum = 0, beta1 = 0, beta2 = 0, t = 1, eps = 0, alpha = 0;
    bool nesterov = false, centered = false;
    BNNSOptimizerSGDMomentumVariant variant = 0;
    enum { SGD, ADAM, RMS } kind;
    bool decoupled = false, amsgrad = false;
    switch (function) {
    case BNNSOptimizerFunctionSGDMomentum: {
        const BNNSOptimizerSGDMomentumFields *f = fields;
        kind = SGD; c.lr = f->learning_rate; momentum = f->momentum; c.gscale = f->gradient_scale; c.rscale = f->regularization_scale;
        if (f->clip_gradients) { c.clip = BNNSOptimizerClippingByValue; c.cmin = f->clip_gradients_min; c.cmax = f->clip_gradients_max; }
        nesterov = f->nesterov; c.reg = f->regularization_func; variant = f->sgd_momentum_variant;
        break;
    }
    case BNNSOptimizerFunctionSGDMomentumWithClipping: {
        const BNNSOptimizerSGDMomentumWithClippingFields *f = fields;
        kind = SGD; c.lr = f->learning_rate; momentum = f->momentum; c.gscale = f->gradient_scale; c.rscale = f->regularization_scale;
        nesterov = f->nesterov; c.reg = f->regularization_func; variant = f->sgd_momentum_variant; c.clip = f->clipping_func;
        c.cmin = f->clip_gradients_min; c.cmax = f->clip_gradients_max; c.max_norm = f->clip_gradients_max_norm; c.use_norm = f->clip_gradients_use_norm;
        break;
    }
    case BNNSOptimizerFunctionAdam: case BNNSOptimizerFunctionAdamW: case BNNSOptimizerFunctionAdamAMSGrad: case BNNSOptimizerFunctionAdamWAMSGrad: {
        const BNNSOptimizerAdamFields *f = fields;
        kind = ADAM; c.lr = f->learning_rate; beta1 = f->beta1; beta2 = f->beta2; t = f->time_step; eps = f->epsilon;
        c.gscale = f->gradient_scale; c.rscale = f->regularization_scale; c.reg = f->regularization_func;
        if (f->clip_gradients) { c.clip = BNNSOptimizerClippingByValue; c.cmin = f->clip_gradients_min; c.cmax = f->clip_gradients_max; }
        decoupled = function == BNNSOptimizerFunctionAdamW || function == BNNSOptimizerFunctionAdamWAMSGrad;
        amsgrad = function == BNNSOptimizerFunctionAdamAMSGrad || function == BNNSOptimizerFunctionAdamWAMSGrad;
        break;
    }
    case BNNSOptimizerFunctionAdamWithClipping: case BNNSOptimizerFunctionAdamWWithClipping:
    case BNNSOptimizerFunctionAdamAMSGradWithClipping: case BNNSOptimizerFunctionAdamWAMSGradWithClipping: {
        const BNNSOptimizerAdamWithClippingFields *f = fields;
        kind = ADAM; c.lr = f->learning_rate; beta1 = f->beta1; beta2 = f->beta2; t = f->time_step; eps = f->epsilon;
        c.gscale = f->gradient_scale; c.rscale = f->regularization_scale; c.reg = f->regularization_func; c.clip = f->clipping_func;
        c.cmin = f->clip_gradients_min; c.cmax = f->clip_gradients_max; c.max_norm = f->clip_gradients_max_norm; c.use_norm = f->clip_gradients_use_norm;
        decoupled = function == BNNSOptimizerFunctionAdamWWithClipping || function == BNNSOptimizerFunctionAdamWAMSGradWithClipping;
        amsgrad = function == BNNSOptimizerFunctionAdamAMSGradWithClipping || function == BNNSOptimizerFunctionAdamWAMSGradWithClipping;
        break;
    }
    case BNNSOptimizerFunctionRMSProp: {
        const BNNSOptimizerRMSPropFields *f = fields;
        kind = RMS; c.lr = f->learning_rate; alpha = f->alpha; eps = f->epsilon; centered = f->centered; momentum = f->momentum;
        c.gscale = f->gradient_scale; c.rscale = f->regularization_scale; c.reg = f->regularization_func;
        if (f->clip_gradients) { c.clip = BNNSOptimizerClippingByValue; c.cmin = f->clip_gradients_min; c.cmax = f->clip_gradients_max; }
        break;
    }
    case BNNSOptimizerFunctionRMSPropWithClipping: {
        const BNNSOptimizerRMSPropWithClippingFields *f = fields;
        kind = RMS; c.lr = f->learning_rate; alpha = f->alpha; eps = f->epsilon; centered = f->centered; momentum = f->momentum;
        c.gscale = f->gradient_scale; c.rscale = f->regularization_scale; c.reg = f->regularization_func; c.clip = f->clipping_func;
        c.cmin = f->clip_gradients_min; c.cmax = f->clip_gradients_max; c.max_norm = f->clip_gradients_max_norm; c.use_norm = f->clip_gradients_use_norm;
        break;
    }
    default: return -1;
    }
    if (kind != SGD && !accumulators) return -1;
    if (kind == SGD && momentum != 0 && !accumulators) return -1;
    // Gradients scaled and (optionally) clipped, all read up front for global norms.
    float **g = calloc(count ? count : 1, sizeof(float *));
    if (!g) return -1;
    int r = 0;
    double global = 0;
    for (size_t p = 0; p < count && !r; p++) {
        if (!parameters[p] || !gradients[p] || bnns_count(parameters[p]) != bnns_count(gradients[p])) { r = -1; break; }
        g[p] = bnns_read(gradients[p], NULL);
        if (!g[p]) { r = -1; break; }
        size_t n = bnns_count(parameters[p]);
        for (size_t i = 0; i < n; i++) {
            g[p][i] *= c.gscale;
            global += (double)g[p][i] * g[p][i];
        }
    }
    double global_scale = 1;
    if (!r && c.clip == BNNSOptimizerClippingByGlobalNorm) {
        double norm = c.use_norm != 0 ? c.use_norm : sqrt(global);
        if (norm > c.max_norm) global_scale = c.max_norm / norm;
    }
    for (size_t p = 0; p < count && !r; p++) {
        size_t n = bnns_count(parameters[p]);
        float *w = bnns_read(parameters[p], NULL);
        float *acc[3] = {0};
        int nacc = kind == SGD ? (momentum != 0) : kind == ADAM ? (amsgrad ? 3 : 2) : 1 + centered + (momentum != 0);
        for (int a = 0; a < nacc; a++) {
            BNNSNDArrayDescriptor *ad = accumulators[a * count + p];
            acc[a] = ad && bnns_count(ad) == n ? bnns_read(ad, NULL) : NULL;
            if (!acc[a]) r = -1;
        }
        if (!w) r = -1;
        if (!r) {
            double norm_scale = 1;
            if (c.clip == BNNSOptimizerClippingByNorm) {
                double ss = 0;
                for (size_t i = 0; i < n; i++) ss += (double)g[p][i] * g[p][i];
                double norm = sqrt(ss);
                if (norm > c.max_norm) norm_scale = c.max_norm / norm;
            } else if (c.clip == BNNSOptimizerClippingByGlobalNorm) norm_scale = global_scale;
            for (size_t i = 0; i < n; i++) {
                float gi = (float)(g[p][i] * norm_scale);
                if (c.clip == BNNSOptimizerClippingByValue) gi = fminf(fmaxf(gi, c.cmin), c.cmax);
                if (kind == SGD) {
                    gi = bnns_regularized(&c, gi, w[i]);
                    if (momentum == 0) { w[i] -= c.lr * gi; continue; }
                    float v0 = acc[0][i], v;
                    switch (variant) {
                    case BNNSSGDMomentumVariant0:
                        v = momentum * v0 - gi * c.lr;
                        w[i] += nesterov ? v + momentum * (v - v0) : v;
                        break;
                    case BNNSSGDMomentumVariant1:
                        v = momentum * v0 + gi;
                        w[i] -= nesterov ? (momentum * v + gi) * c.lr : v * c.lr;
                        break;
                    default:
                        if (nesterov) { v = momentum * v0 + gi; w[i] -= c.lr * (gi + v * momentum); }
                        else { v = momentum * v0 + c.lr * gi; w[i] -= v; }
                    }
                    acc[0][i] = v;
                } else if (kind == ADAM) {
                    if (!decoupled) gi = bnns_regularized(&c, gi, w[i]);
                    float m = acc[0][i] = beta1 * acc[0][i] + (1 - beta1) * gi;
                    float v = acc[1][i] = beta2 * acc[1][i] + (1 - beta2) * gi * gi;
                    if (amsgrad) v = acc[2][i] = fmaxf(acc[2][i], v);
                    double step = c.lr * sqrt(1 - pow(beta2, t)) / (1 - pow(beta1, t));
                    if (decoupled) w[i] -= c.lr * c.rscale * w[i];
                    w[i] -= (float)(step * m / (sqrt(v) + eps));
                } else {
                    gi = bnns_regularized(&c, gi, w[i]);
                    float nv = acc[0][i] = alpha * acc[0][i] + (1 - alpha) * gi * gi;
                    float denom = nv;
                    int next = 1;
                    if (centered) {
                        float gv = acc[1][i] = alpha * acc[1][i] + (1 - alpha) * gi;
                        denom = nv - gv * gv;
                        next = 2;
                    }
                    float delta = -c.lr * gi / (sqrtf(fmaxf(denom, 0)) + eps);
                    if (momentum != 0) delta = acc[next][i] = momentum * acc[next][i] + delta;
                    w[i] += delta;
                }
            }
            r = bnns_write(parameters[p], NULL, w, false);
            for (int a = 0; !r && a < nacc; a++) r = bnns_write(accumulators[a * count + p], NULL, acc[a], false);
        }
        free(w);
        for (int a = 0; a < 3; a++) free(acc[a]);
    }
    for (size_t p = 0; p < count; p++) free(g[p]);
    free(g);
    return r;
}

// MARK: - Sparse weights (unsupported: the packed sparse layout is device specific)

int BNNSNDArrayFullyConnectedSparsifySparseCOO(const BNNSNDArrayDescriptor *in_dense_shape, const BNNSNDArrayDescriptor *in_indices,
                                               const BNNSNDArrayDescriptor *in_values, BNNSNDArrayDescriptor *out,
                                               const BNNSSparsityParameters *sparse_params, size_t batch_size, void *workspace,
                                               size_t workspace_size, const BNNSFilterParameters *fp) {
    (void)in_dense_shape; (void)in_indices; (void)in_values; (void)out; (void)sparse_params;
    (void)batch_size; (void)workspace; (void)workspace_size; (void)fp;
    return -1;
}

int BNNSNDArrayFullyConnectedSparsifySparseCSR(const BNNSNDArrayDescriptor *in_dense_shape, const BNNSNDArrayDescriptor *in_column_indices,
                                               const BNNSNDArrayDescriptor *in_row_starts, const BNNSNDArrayDescriptor *in_values,
                                               BNNSNDArrayDescriptor *out, const BNNSSparsityParameters *sparse_params, size_t batch_size,
                                               void *workspace, size_t workspace_size, const BNNSFilterParameters *fp) {
    (void)in_dense_shape; (void)in_column_indices; (void)in_row_starts; (void)in_values; (void)out; (void)sparse_params;
    (void)batch_size; (void)workspace; (void)workspace_size; (void)fp;
    return -1;
}

// MARK: - Random numbers (xoshiro256**, seeded through splitmix64)

typedef struct {
    uint64_t s[4];
    BNNSFree free_memory;
} bnns_random;

static uint64_t bnns_splitmix(uint64_t *x) {
    uint64_t z = (*x += 0x9E3779B97F4A7C15ull);
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ull;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBull;
    return z ^ (z >> 31);
}

static uint64_t bnns_rotl(uint64_t x, int k) { return (x << k) | (x >> (64 - k)); }

uint64_t bnns_random_next(uint64_t *s) {
    uint64_t result = bnns_rotl(s[1] * 5, 7) * 9, t = s[1] << 17;
    s[2] ^= s[0]; s[3] ^= s[1]; s[1] ^= s[2]; s[0] ^= s[3];
    s[2] ^= t;
    s[3] = bnns_rotl(s[3], 45);
    return result;
}

void *bnns_alloc(const BNNSFilterParameters *fp, size_t size) {
    void *p = NULL;
    if (fp && fp->alloc_memory) {
        if (fp->alloc_memory(&p, 16, size ? size : 1)) return NULL;
        if (p) memset(p, 0, size);
        return p;
    }
    return calloc(1, size ? size : 1);
}

void bnns_release(BNNSFree free_memory, void *p) {
    if (!p) return;
    if (free_memory) free_memory(p);
    else free(p);
}

BNNSRandomGenerator BNNSCreateRandomGeneratorWithSeed(BNNSRandomGeneratorMethod method, uint64_t seed, const BNNSFilterParameters *fp) {
    if (method != BNNSRandomGeneratorMethodAES_CTR) return NULL;
    bnns_random *g = bnns_alloc(fp, sizeof *g);
    if (!g) return NULL;
    g->free_memory = fp && fp->alloc_memory ? fp->free_memory : NULL;
    for (int k = 0; k < 4; k++) g->s[k] = bnns_splitmix(&seed);
    return g;
}

BNNSRandomGenerator BNNSCreateRandomGenerator(BNNSRandomGeneratorMethod method, const BNNSFilterParameters *fp) {
    static uint64_t counter;
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    uint64_t seed = ((uint64_t)ts.tv_sec * 1000000007ull) ^ (uint64_t)ts.tv_nsec ^ (__atomic_add_fetch(&counter, 1, __ATOMIC_RELAXED) << 40);
    seed ^= (uint64_t)(uintptr_t)&seed;
    return BNNSCreateRandomGeneratorWithSeed(method, seed, fp);
}

void BNNSDestroyRandomGenerator(BNNSRandomGenerator generator) {
    bnns_random *g = generator;
    if (g) bnns_release(g->free_memory, g);
}

size_t BNNSRandomGeneratorStateSize(BNNSRandomGenerator generator) { return generator ? sizeof(((bnns_random *)0)->s) : 0; }

int BNNSRandomGeneratorGetState(BNNSRandomGenerator generator, size_t state_size, void *state) {
    bnns_random *g = generator;
    if (!g || !state || state_size < sizeof g->s) return -1;
    memcpy(state, g->s, sizeof g->s);
    return 0;
}

int BNNSRandomGeneratorSetState(BNNSRandomGenerator generator, size_t state_size, void *state) {
    bnns_random *g = generator;
    if (!g || !state || state_size < sizeof g->s) return -1;
    memcpy(g->s, state, sizeof g->s);
    return 0;
}

static double bnns_uniform01(bnns_random *g) { return (double)(bnns_random_next(g->s) >> 11) * 0x1.0p-53; }

static int bnns_fill(bnns_random *g, BNNSNDArrayDescriptor *d, int kind, double a, double b) {
    bnns_shape sh;
    if (!g || !d || bnns_shape_of(d, &sh) || !d->data || !bnns_type_ok(d->data_type)) return -1;
    if (kind != 1 ? !bnns_float_type(d->data_type) : !bnns_int_type(d->data_type)) return -1;
    if (!bnns_shape_count(&sh)) return 0;
    BNNSNDArrayDescriptor raw = *d;
    raw.data_scale = 1; raw.data_bias = 0;
    size_t idx[BNNS_MAX_TENSOR_DIMENSION] = {0};
    do {
        double v;
        if (kind == 0) {
            v = a + (b - a) * bnns_uniform01(g);
            if (d->data_type == BNNSDataTypeFloat32 && (float)v >= (float)b && b > a) v = nextafterf((float)b, (float)a);
        } else if (kind == 1) {
            // Apple draws from [a, b): the upper bound is never produced.
            uint64_t span = (uint64_t)((int64_t)b - (int64_t)a);
            v = (double)((int64_t)a + (int64_t)(span ? bnns_random_next(g->s) % span : 0));
        } else {
            double u1 = bnns_uniform01(g), u2 = bnns_uniform01(g);
            if (u1 < 1e-300) u1 = 1e-300;
            v = a + b * sqrt(-2 * log(u1)) * cos(6.283185307179586 * u2);
        }
        bnns_store(&raw, d->data, bnns_index_offset(&sh, idx), v);
    } while (bnns_next(idx, sh.n, sh.rank));
    return 0;
}

int BNNSRandomFillUniformFloat(BNNSRandomGenerator generator, BNNSNDArrayDescriptor *desc, float a, float b) {
    return bnns_fill(generator, desc, 0, a, b);
}

int BNNSRandomFillUniformInt(BNNSRandomGenerator generator, BNNSNDArrayDescriptor *desc, int64_t a, int64_t b) {
    if (b < a) return -1;
    return bnns_fill(generator, desc, 1, (double)a, (double)b);
}

int BNNSRandomFillNormalFloat(BNNSRandomGenerator generator, BNNSNDArrayDescriptor *desc, float mean, float stddev) {
    return bnns_fill(generator, desc, 2, mean, stddev);
}

// MARK: - Nearest neighbors (brute force, Euclidean)

typedef struct {
    unsigned max_samples, features, neighbors, count;
    BNNSDataType type;
    float *data;
    BNNSFree free_memory;
} bnns_knn;

BNNSNearestNeighbors BNNSCreateNearestNeighbors(unsigned int max_n_samples, unsigned int n_features, unsigned int n_neighbors,
                                                BNNSDataType data_type, const BNNSFilterParameters *fp) {
    if (data_type != BNNSDataTypeFloat32 && data_type != BNNSDataTypeFloat16) return NULL;
    if (!max_n_samples || !n_features || !n_neighbors) return NULL;
    bnns_knn *k = bnns_alloc(fp, sizeof *k);
    if (!k) return NULL;
    k->free_memory = fp && fp->alloc_memory ? fp->free_memory : NULL;
    k->max_samples = max_n_samples; k->features = n_features; k->neighbors = n_neighbors; k->type = data_type;
    k->data = bnns_alloc(fp, (size_t)max_n_samples * n_features * sizeof(float));
    if (!k->data) { bnns_release(k->free_memory, k); return NULL; }
    return k;
}

void BNNSDestroyNearestNeighbors(BNNSNearestNeighbors knn) {
    bnns_knn *k = knn;
    if (!k) return;
    bnns_release(k->free_memory, k->data);
    bnns_release(k->free_memory, k);
}

int BNNSNearestNeighborsLoad(BNNSNearestNeighbors knn, unsigned int n_new_samples, const void *data_ptr) {
    bnns_knn *k = knn;
    if (!k || (!data_ptr && n_new_samples) || (size_t)k->count + n_new_samples > k->max_samples) return -1;
    BNNSNDArrayDescriptor d = { .data_type = k->type, .data_scale = 1 };
    size_t n = (size_t)n_new_samples * k->features;
    float *dst = k->data + (size_t)k->count * k->features;
    for (size_t i = 0; i < n; i++) dst[i] = (float)bnns_load(&d, data_ptr, (ptrdiff_t)i);
    k->count += n_new_samples;
    return 0;
}

static int bnns_knn_one(const bnns_knn *k, unsigned sample, int *indices, void *distances, size_t out_offset, bnns_ranked *buf) {
    const float *q = k->data + (size_t)sample * k->features;
    size_t m = 0;
    // Apple counts the sample itself: its first neighbor is itself at distance 0.
    for (unsigned j = 0; j < k->count; j++) {
        const float *p = k->data + (size_t)j * k->features;
        double ss = 0;
        for (unsigned f = 0; f < k->features; f++) { double t = (double)p[f] - q[f]; ss += t * t; }
        buf[m].v = -(float)sqrt(ss);
        buf[m].i = j;
        m++;
    }
    qsort(buf, m, sizeof *buf, bnns_rank_compare);
    BNNSNDArrayDescriptor d = { .data_type = k->type, .data_scale = 1 };
    for (unsigned t = 0; t < k->neighbors; t++) {
        if (indices) indices[out_offset + t] = t < m ? (int)buf[t].i : -1;
        if (distances) bnns_store(&d, distances, (ptrdiff_t)(out_offset + t), t < m ? -buf[t].v : INFINITY);
    }
    return 0;
}

int BNNSNearestNeighborsGetInfo(BNNSNearestNeighbors knn, int sample_number, int *indices, void *distances) {
    const bnns_knn *k = knn;
    if (!k || (sample_number >= 0 && (unsigned)sample_number >= k->count)) return -1;
    bnns_ranked *buf = malloc((k->count ? k->count : 1) * sizeof *buf);
    if (!buf) return -1;
    if (sample_number >= 0) bnns_knn_one(k, (unsigned)sample_number, indices, distances, 0, buf);
    else for (unsigned s = 0; s < k->count; s++) bnns_knn_one(k, s, indices, distances, (size_t)s * k->neighbors, buf);
    free(buf);
    return 0;
}
