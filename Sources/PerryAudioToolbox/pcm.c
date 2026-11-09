// Linear PCM in any of the layouts an AudioStreamBasicDescription names,
// read to and written from interleaved floats; and Apple's IMA4.

#include "PerryAudioToolbox.h"

#include <math.h>
#include <string.h>

/// Bytes per sample, and the shift of a fixed-point integer's fraction.
static uint32_t sample_bytes(const AudioStreamBasicDescription *f) {
    return f->mBitsPerChannel ? (f->mBitsPerChannel + 7) / 8 : 0;
}

bool perry_pcm_supported(const AudioStreamBasicDescription *f) {
    if (f->mFormatID != kAudioFormatLinearPCM || f->mChannelsPerFrame == 0 || f->mBytesPerFrame == 0) return false;
    uint32_t bytes = sample_bytes(f);
    uint32_t container = (f->mFormatFlags & kAudioFormatFlagIsNonInterleaved)
        ? f->mBytesPerFrame : f->mBytesPerFrame / f->mChannelsPerFrame;
    if (container == 0 || bytes > container) return false;
    if (f->mFormatFlags & kAudioFormatFlagIsFloat) return f->mBitsPerChannel == 32 || f->mBitsPerChannel == 64;
    return f->mBitsPerChannel >= 8 && f->mBitsPerChannel <= 32;
}

/// The sample at `p`, in a container of `size` bytes.
static float read_sample(const AudioStreamBasicDescription *f, const uint8_t *p, uint32_t size) {
    bool big = f->mFormatFlags & kAudioFormatFlagIsBigEndian;
    if (f->mFormatFlags & kAudioFormatFlagIsFloat) {
        uint8_t b[8];
        for (uint32_t i = 0; i < size; i++) b[i] = big ? p[size - 1 - i] : p[i];
        if (f->mBitsPerChannel == 64) {
            double d;
            memcpy(&d, b, 8);
            return (float)d;
        }
        float v;
        memcpy(&v, b, 4);
        return v;
    }
    // An integer, its significant bits at the top of the container unless
    // packed (when the container is exactly its bits).
    uint32_t raw = 0;
    for (uint32_t i = 0; i < size; i++) raw |= (uint32_t)(big ? p[i] : p[size - 1 - i]) << (8 * (size - 1 - i));
    if (!(f->mFormatFlags & kAudioFormatFlagIsSignedInteger)) {
        // Unsigned, as 8-bit WAV: centred on half the range.
        double v = (double)raw / (double)((size == 4) ? 4294967295.0 : (double)((1ull << (8 * size)) - 1));
        return (float)(v * 2.0 - 1.0);
    }
    int32_t value = (int32_t)(raw << (32 - 8 * size));     // sign-extended at the top of 32 bits
    uint32_t fraction = (f->mFormatFlags & kLinearPCMFormatFlagsSampleFractionMask) >> kLinearPCMFormatFlagsSampleFractionShift;
    if (fraction && fraction < 8 * size) {
        // Fixed point (8.24, the old canonical audio unit format): value is
        // shifted up by the container's spare bits; 1.0 is 1 << fraction.
        return (float)((double)value / (double)(1ull << (fraction + 32 - 8 * size)));
    }
    return (float)((double)value / 2147483648.0);
}

static void write_sample(const AudioStreamBasicDescription *f, uint8_t *p, uint32_t size, float v) {
    bool big = f->mFormatFlags & kAudioFormatFlagIsBigEndian;
    uint8_t b[8];
    if (f->mFormatFlags & kAudioFormatFlagIsFloat) {
        if (f->mBitsPerChannel == 64) {
            double d = v;
            memcpy(b, &d, 8);
        } else {
            memcpy(b, &v, 4);
        }
        for (uint32_t i = 0; i < size; i++) p[i] = big ? b[size - 1 - i] : b[i];
        return;
    }
    uint32_t fraction = (f->mFormatFlags & kLinearPCMFormatFlagsSampleFractionMask) >> kLinearPCMFormatFlagsSampleFractionShift;
    uint32_t raw;
    if (!(f->mFormatFlags & kAudioFormatFlagIsSignedInteger)) {
        double clamped = v < -1 ? -1 : v > 1 ? 1 : v;
        double maximum = (size == 4) ? 4294967295.0 : (double)((1ull << (8 * size)) - 1);
        raw = (uint32_t)lrint((clamped + 1.0) / 2.0 * maximum);
    } else if (fraction && fraction < 8 * size) {
        double scaled = (double)v * (double)(1ull << fraction);
        double limit = (double)(1ull << (8 * size - 1));
        if (scaled > limit - 1) scaled = limit - 1;
        if (scaled < -limit) scaled = -limit;
        raw = (uint32_t)(int32_t)lrint(scaled);
    } else {
        double limit = (double)(1ull << (8 * size - 1));
        double scaled = (double)v * limit;
        if (scaled > limit - 1) scaled = limit - 1;
        if (scaled < -limit) scaled = -limit;
        raw = (uint32_t)(int32_t)lrint(scaled);
    }
    for (uint32_t i = 0; i < size; i++) {
        uint8_t byte = (uint8_t)(raw >> (8 * i));
        if (big) p[size - 1 - i] = byte; else p[i] = byte;
    }
}

/// Where a sample sits: its container size and the bytes from one frame to
/// the next in its buffer.
static void layout(const AudioStreamBasicDescription *f, uint32_t *container, uint32_t *stride) {
    if (f->mFormatFlags & kAudioFormatFlagIsNonInterleaved) {
        *container = f->mBytesPerFrame;
        *stride = f->mBytesPerFrame;
    } else {
        *container = f->mBytesPerFrame / f->mChannelsPerFrame;
        *stride = f->mBytesPerFrame;
    }
}

/// The container's significant bytes: a sample sits at its low end when
/// packed or aligned high, which the shift in read_sample accounts for, so
/// read the whole container.
void perry_pcm_read(const AudioStreamBasicDescription *f, const AudioBufferList *buffers, size_t first, size_t frames, float *out) {
    uint32_t container, stride, channels = f->mChannelsPerFrame;
    layout(f, &container, &stride);
    bool split = f->mFormatFlags & kAudioFormatFlagIsNonInterleaved;
    for (uint32_t c = 0; c < channels; c++) {
        const AudioBuffer *buffer = &buffers->mBuffers[split ? (c < buffers->mNumberBuffers ? c : buffers->mNumberBuffers - 1) : 0];
        const uint8_t *base = buffer->mData;
        size_t available = stride ? buffer->mDataByteSize / stride : 0;
        for (size_t i = 0; i < frames; i++) {
            size_t frame = first + i;
            out[i * channels + c] = (base && frame < available)
                ? read_sample(f, base + frame * stride + (split ? 0 : c * container), container) : 0.0f;
        }
    }
}

void perry_pcm_write(const AudioStreamBasicDescription *f, AudioBufferList *buffers, size_t first, size_t frames, const float *in) {
    uint32_t container, stride, channels = f->mChannelsPerFrame;
    layout(f, &container, &stride);
    bool split = f->mFormatFlags & kAudioFormatFlagIsNonInterleaved;
    for (uint32_t c = 0; c < channels; c++) {
        if (split && c >= buffers->mNumberBuffers) break;
        AudioBuffer *buffer = &buffers->mBuffers[split ? c : 0];
        uint8_t *base = buffer->mData;
        if (!base) continue;
        for (size_t i = 0; i < frames; i++) {
            write_sample(f, base + (first + i) * stride + (split ? 0 : c * container), container, in[i * channels + c]);
        }
    }
}

void perry_pcm_remap(const float *in, uint32_t in_channels, float *out, uint32_t out_channels, size_t frames) {
    for (size_t i = 0; i < frames; i++) {
        const float *frame = in + i * in_channels;
        float *target = out + i * out_channels;
        if (in_channels == out_channels) {
            memmove(target, frame, out_channels * sizeof(float));
        } else if (in_channels == 1) {
            for (uint32_t c = 0; c < out_channels; c++) target[c] = frame[0];
        } else if (out_channels == 1) {
            float sum = 0;
            for (uint32_t c = 0; c < in_channels; c++) sum += frame[c];
            target[0] = sum / (float)in_channels;
        } else {
            for (uint32_t c = 0; c < out_channels; c++) target[c] = c < in_channels ? frame[c] : 0.0f;
        }
    }
}

// MARK: - IMA4

static const int16_t ima_steps[89] = {
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118,
    130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963, 1060,
    1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484,
    7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767,
};
static const int8_t ima_indexes[16] = { -1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8 };

void perry_ima4_decode(const uint8_t *packet, uint32_t channels, float *out) {
    for (uint32_t c = 0; c < channels; c++) {
        const uint8_t *block = packet + 34 * c;
        uint16_t header = (uint16_t)(block[0] << 8 | block[1]);
        int predictor = (int16_t)(header & 0xff80);
        int index = header & 0x7f;
        if (index > 88) index = 88;
        for (int i = 0; i < 64; i++) {
            uint8_t byte = block[2 + i / 2];
            int nibble = (i & 1) ? byte >> 4 : byte & 15;
            int step = ima_steps[index];
            int diff = step >> 3;
            if (nibble & 1) diff += step >> 2;
            if (nibble & 2) diff += step >> 1;
            if (nibble & 4) diff += step;
            if (nibble & 8) diff = -diff;
            predictor += diff;
            if (predictor > 32767) predictor = 32767;
            if (predictor < -32768) predictor = -32768;
            index += ima_indexes[nibble];
            if (index < 0) index = 0;
            if (index > 88) index = 88;
            out[i * channels + c] = (float)predictor / 32768.0f;
        }
    }
}
