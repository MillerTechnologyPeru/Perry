// Audio converters: linear PCM, IMA4, AAC or MP3 in, linear PCM out, at any
// sample rates and channel counts. Input is decoded to floats, remapped to
// the output's channels and resampled linearly; the converter keeps what
// one call doesn't use for the next. AAC and MP3 packets are decoded by
// GStreamer, as an audio queue's are: a game may decode its music itself
// and play what comes out.

#include "PerryAudioToolbox.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef OSStatus (*input_proc)(void *converter, uint32_t *packets, AudioBufferList *data,
                               AudioStreamPacketDescription **descriptions, void *user);

typedef struct converter {
    uint32_t magic;
    AudioStreamBasicDescription in, out;
    /// Decoded input, in the output's channels at the input's rate.
    float *pending;
    size_t count, capacity;
    /// The next output frame's position in pending.
    double position;
    /// For compressed input: GStreamer's decoder, its source and sink, the
    /// packets pushed and whether the input has ended.
    void *pipeline, *src, *sink;
    uint64_t pushed;
    bool ended;
} converter;

#define CONVERTER_MAGIC FOURCC('p', 'a', 'c', 'v')

static converter *valid(void *handle) {
    converter *c = handle;
    return c && c->magic == CONVERTER_MAGIC ? c : NULL;
}

static bool compressed(const AudioStreamBasicDescription *f) {
    return f->mFormatID == kAudioFormatMPEG4AAC || f->mFormatID == kAudioFormatMPEGLayer3;
}

static bool input_supported(const AudioStreamBasicDescription *f) {
    if (f->mSampleRate <= 0) return false;
    if (f->mFormatID == kAudioFormatAppleIMA4 || compressed(f)) return f->mChannelsPerFrame > 0;
    return perry_pcm_supported(f);
}

/// The decoder for compressed input: packets in, interleaved floats out at
/// the input's rate and channels. False when GStreamer can't make it.
static bool build_decoder(converter *c) {
    const perry_gst *g = perry_gst_get();
    char caps[256], description[640];
    if (!g || !perry_gst_caps(&c->in, NULL, 0, caps, sizeof caps)) return false;
    bool aac = c->in.mFormatID == kAudioFormatMPEG4AAC;
    const char *decoder = aac && g->factory_find && g->factory_find("avdec_aac") ? "avdec_aac !"
        : !aac && g->factory_find && g->factory_find("mpegaudioparse") && g->factory_find("mpg123audiodec")
            ? "mpegaudioparse ! mpg123audiodec !" : "decodebin !";
    snprintf(description, sizeof description,
             "appsrc name=src format=time caps=\"%s\" ! %s audioconvert ! audioresample ! "
             "audio/x-raw,format=F32LE,layout=interleaved,rate=%d,channels=%d ! appsink name=sink sync=false",
             caps, decoder, (int)c->in.mSampleRate, (int)c->in.mChannelsPerFrame);
    perry_audio_trace("converter %p: %s", (void *)c, description);
    c->pipeline = g->parse_launch(description, NULL);
    if (c->pipeline) {
        c->src = g->bin_get_by_name(c->pipeline, "src");
        c->sink = g->bin_get_by_name(c->pipeline, "sink");
    }
    if (!c->pipeline || !c->src || !c->sink || g->set_state(c->pipeline, PERRY_GST_STATE_PLAYING) == 0) return false;
    return true;
}

static void free_decoder(converter *c) {
    const perry_gst *g = c->pipeline ? perry_gst_get() : NULL;
    if (!g) return;
    g->set_state(c->pipeline, PERRY_GST_STATE_NULL);
    if (c->src) g->object_unref(c->src);
    if (c->sink) g->object_unref(c->sink);
    g->object_unref(c->pipeline);
    c->pipeline = c->src = c->sink = NULL;
}

OSStatus darwin_AudioConverterNew(const AudioStreamBasicDescription *in, const AudioStreamBasicDescription *out, void **result)
    DARWIN_SYMBOL(AudioConverterNew);
OSStatus darwin_AudioConverterNew(const AudioStreamBasicDescription *in, const AudioStreamBasicDescription *out, void **result) {
    if (!in || !out || !result) return kAudio_ParamError;
    *result = NULL;
    if (!input_supported(in) || !perry_pcm_supported(out) || out->mSampleRate <= 0) {
        perry_audio_warn("can't convert '%c%c%c%c' to '%c%c%c%c'", in->mFormatID >> 24, in->mFormatID >> 16 & 0xff,
                         in->mFormatID >> 8 & 0xff, in->mFormatID & 0xff, out->mFormatID >> 24, out->mFormatID >> 16 & 0xff,
                         out->mFormatID >> 8 & 0xff, out->mFormatID & 0xff);
        return kAudioConverterErr_FormatNotSupported;
    }
    converter *c = calloc(1, sizeof *c);
    if (!c) return kAudio_MemFullError;
    c->magic = CONVERTER_MAGIC;
    c->in = *in;
    c->out = *out;
    if (compressed(in) && !build_decoder(c)) {
        perry_audio_warn("can't decode '%c%c%c%c': GStreamer has no decoder for it", in->mFormatID >> 24,
                         in->mFormatID >> 16 & 0xff, in->mFormatID >> 8 & 0xff, in->mFormatID & 0xff);
        free_decoder(c);
        free(c);
        return kAudioConverterErr_FormatNotSupported;
    }
    perry_audio_trace("converter %p: %u Hz %u ch '%c%c%c%c' to %u Hz %u ch, flags %#x, %u bits", (void *)c,
                      (unsigned)in->mSampleRate, in->mChannelsPerFrame, in->mFormatID >> 24, in->mFormatID >> 16 & 0xff,
                      in->mFormatID >> 8 & 0xff, in->mFormatID & 0xff, (unsigned)out->mSampleRate, out->mChannelsPerFrame,
                      out->mFormatFlags, out->mBitsPerChannel);
    *result = c;
    return 0;
}

OSStatus darwin_AudioConverterDispose(void *handle) DARWIN_SYMBOL(AudioConverterDispose);
OSStatus darwin_AudioConverterDispose(void *handle) {
    converter *c = valid(handle);
    if (!c) return kAudio_ParamError;
    c->magic = 0;
    free_decoder(c);
    free(c->pending);
    free(c);
    return 0;
}

OSStatus darwin_AudioConverterReset(void *handle) DARWIN_SYMBOL(AudioConverterReset);
OSStatus darwin_AudioConverterReset(void *handle) {
    converter *c = valid(handle);
    if (!c) return kAudio_ParamError;
    c->count = 0;
    c->position = 0;
    // Compressed input starts over with a decoder that has heard nothing.
    if (c->pipeline) {
        free_decoder(c);
        c->pushed = 0;
        c->ended = false;
        if (!build_decoder(c)) free_decoder(c);
    }
    return 0;
}

/// Room for `frames` more pending frames.
static bool reserve(converter *c, size_t frames) {
    size_t channels = c->out.mChannelsPerFrame;
    if (c->count + frames <= c->capacity) return true;
    size_t capacity = (c->count + frames) * 2;
    float *pending = realloc(c->pending, capacity * channels * sizeof(float));
    if (!pending) return false;
    c->pending = pending;
    c->capacity = capacity;
    return true;
}

/// Appends decoded frames, `in_channels` interleaved, remapped.
static void append(converter *c, const float *frames, uint32_t in_channels, size_t count) {
    if (!reserve(c, count)) return;
    perry_pcm_remap(frames, in_channels, c->pending + c->count * c->out.mChannelsPerFrame, c->out.mChannelsPerFrame, count);
    c->count += count;
}

/// Takes what the decoder has ready, waiting up to `timeout` for the
/// first of it; whether there was any.
static bool drain_decoder(converter *c, uint64_t timeout) {
    const perry_gst *g = perry_gst_get();
    bool any = false;
    void *sample;
    while ((sample = g->app_sink_try_pull_sample(c->sink, any ? 0 : timeout))) {
        void *buffer = g->sample_get_buffer(sample);
        uint8_t info[PERRY_GST_MAP_INFO_SIZE];
        if (buffer && g->buffer_map(buffer, info, PERRY_GST_MAP_READ)) {
            const float *floats = *(void **)(info + PERRY_GST_MAP_INFO_DATA);
            size_t length = *(size_t *)(info + PERRY_GST_MAP_INFO_LENGTH);
            append(c, floats, c->in.mChannelsPerFrame, length / sizeof(float) / c->in.mChannelsPerFrame);
            g->buffer_unmap(buffer, info);
            any = true;
        }
        g->mini_object_unref(sample);
    }
    return any;
}

/// Compressed input: asks the input proc for packets, gives them to the
/// decoder and takes what it has decoded. The decoder is a few packets
/// behind, so this gives as long as there were packets or anything decoded.
static OSStatus pull_compressed(converter *c, input_proc proc, void *user, bool *gave) {
    const perry_gst *g = perry_gst_get();
    *gave = false;
    if (!g || !c->pipeline) return kAudioConverterErr_FormatNotSupported;
    OSStatus status = 0;
    if (!c->ended) {
        uint32_t packets = 8;
        AudioBufferList list = { 1, {{ c->in.mChannelsPerFrame, 0, NULL }} };
        AudioStreamPacketDescription *descriptions = NULL;
        status = proc(c, &packets, &list, &descriptions, user);
        const uint8_t *data = list.mBuffers[0].mData;
        if (packets > 0 && data) {
            uint32_t total = list.mBuffers[0].mDataByteSize, fixed = c->in.mBytesPerPacket;
            for (uint32_t i = 0; i < packets; i++) {
                // Without descriptions, packets of one size, or the lot as one.
                uint64_t start = descriptions ? (uint64_t)descriptions[i].mStartOffset : (uint64_t)i * fixed;
                uint32_t size = descriptions ? descriptions[i].mDataByteSize : fixed ? fixed : total;
                if (start + size > total || !size) break;
                void *buffer = g->buffer_new_allocate(NULL, size, NULL);
                if (!buffer) break;
                g->buffer_fill(buffer, 0, data + start, size);
                double frames = c->in.mFramesPerPacket ? c->in.mFramesPerPacket : 1024;
                uint64_t duration = (uint64_t)(frames / c->in.mSampleRate * PERRY_GST_SECOND);
                perry_gst_buffer_set_time(buffer, c->pushed * duration, duration);
                g->app_src_push_buffer(c->src, buffer);
                c->pushed++;
                if (!descriptions && !fixed) break;
            }
            *gave = true;
        } else {
            c->ended = true;
            g->app_src_end_of_stream(c->src);
        }
    }
    // What is decoded so far; at the end, all that is left.
    if (drain_decoder(c, c->ended ? PERRY_GST_SECOND : PERRY_GST_SECOND / 10)) *gave = true;
    perry_gst_check_error(g, c->pipeline, "decoding for a converter");
    return status;
}

/// Asks the input proc for about `frames` frames and decodes them; the
/// proc's status, and whether it gave any.
static OSStatus pull(converter *c, input_proc proc, void *user, size_t frames, bool *gave) {
    if (c->pipeline) return pull_compressed(c, proc, user, gave);
    const AudioStreamBasicDescription *in = &c->in;
    bool ima4 = in->mFormatID == kAudioFormatAppleIMA4;
    uint32_t packets = ima4 ? (uint32_t)((frames + 63) / 64) : (uint32_t)frames;
    if (packets < 1) packets = 1;
    if (packets > 16384) packets = 16384;
    uint32_t buffers = (!ima4 && (in->mFormatFlags & kAudioFormatFlagIsNonInterleaved)) ? in->mChannelsPerFrame : 1;
    AudioBufferList *list = calloc(1, sizeof(AudioBufferList) + buffers * sizeof(AudioBuffer));
    if (!list) return kAudio_MemFullError;
    list->mNumberBuffers = buffers;
    for (uint32_t i = 0; i < buffers; i++) list->mBuffers[i].mNumberChannels = buffers == 1 ? in->mChannelsPerFrame : 1;
    AudioStreamPacketDescription *descriptions = NULL;
    OSStatus status = proc(c, &packets, list, &descriptions, user);
    *gave = packets > 0 && list->mBuffers[0].mData;
    if (*gave) {
        if (ima4) {
            uint32_t packet_size = in->mBytesPerPacket ? in->mBytesPerPacket : 34 * in->mChannelsPerFrame;
            const uint8_t *data = list->mBuffers[0].mData;
            uint32_t available = list->mBuffers[0].mDataByteSize / packet_size;
            // Packets of one size follow each other: their descriptions, if
            // the proc gives any, aren't needed, as Darwin's converter
            // doesn't use them (apps pass ones relative to other buffers).
            if (in->mBytesPerPacket) descriptions = NULL;
            if (!descriptions && packets > available) packets = available;
            float decoded[64 * 8];
            uint32_t channels = in->mChannelsPerFrame > 8 ? 8 : in->mChannelsPerFrame;
            for (uint32_t i = 0; i < packets; i++) {
                const uint8_t *packet = data + (descriptions ? (size_t)descriptions[i].mStartOffset : (size_t)i * packet_size);
                perry_ima4_decode(packet, channels, decoded);
                append(c, decoded, channels, 64);
            }
        } else {
            size_t available = list->mBuffers[0].mDataByteSize / in->mBytesPerFrame;
            size_t count = packets < available ? packets : available;
            float *decoded = malloc((count ? count : 1) * in->mChannelsPerFrame * sizeof(float));
            if (decoded) {
                perry_pcm_read(in, list, 0, count, decoded);
                append(c, decoded, in->mChannelsPerFrame, count);
                free(decoded);
            }
        }
    }
    free(list);
    return status;
}

/// Up to `wanted` output frames into `out`, interleaved floats; how many.
static size_t produce(converter *c, input_proc proc, void *user, size_t wanted, float *out, OSStatus *status) {
    size_t channels = c->out.mChannelsPerFrame, produced = 0;
    double step = c->in.mSampleRate / c->out.mSampleRate;
    bool ended = false;
    *status = 0;
    while (produced < wanted) {
        // Two frames to interpolate between, unless the input has ended.
        while (!ended && (size_t)c->position + 1 >= c->count) {
            bool gave = false;
            size_t frames = (size_t)ceil((double)(wanted - produced) * step) + 2;
            OSStatus result = pull(c, proc, user, frames, &gave);
            if (result) { *status = result; ended = true; }
            if (!gave) ended = true;
        }
        size_t k = (size_t)c->position;
        if (k >= c->count) break;
        double t = c->position - (double)k;
        const float *a = c->pending + k * channels;
        const float *b = (k + 1 < c->count) ? a + channels : a;
        for (size_t ch = 0; ch < channels; ch++) out[produced * channels + ch] = a[ch] + (b[ch] - a[ch]) * (float)t;
        produced++;
        c->position += step;
        if (ended && k + 1 >= c->count && (size_t)c->position >= c->count) break;
    }
    // Keep from the frame the next output starts at.
    size_t drop = (size_t)c->position;
    if (drop > c->count) drop = c->count;
    memmove(c->pending, c->pending + drop * channels, (c->count - drop) * channels * sizeof(float));
    c->count -= drop;
    c->position -= (double)drop;
    return produced;
}

OSStatus darwin_AudioConverterFillComplexBuffer(void *handle, input_proc proc, void *user, uint32_t *packets,
                                                AudioBufferList *out, AudioStreamPacketDescription *descriptions)
    DARWIN_SYMBOL(AudioConverterFillComplexBuffer);
OSStatus darwin_AudioConverterFillComplexBuffer(void *handle, input_proc proc, void *user, uint32_t *packets,
                                                AudioBufferList *out, AudioStreamPacketDescription *descriptions) {
    converter *c = valid(handle);
    if (!c || !proc || !packets || !out) return kAudio_ParamError;
    size_t wanted = *packets;
    // No more than the output buffers hold.
    size_t room = c->out.mBytesPerFrame ? out->mBuffers[0].mDataByteSize / c->out.mBytesPerFrame : 0;
    if (wanted > room) wanted = room;
    float *frames = malloc((wanted ? wanted : 1) * c->out.mChannelsPerFrame * sizeof(float));
    if (!frames) return kAudio_MemFullError;
    OSStatus status;
    size_t produced = produce(c, proc, user, wanted, frames, &status);
    perry_pcm_write(&c->out, out, 0, produced, frames);
    free(frames);
    uint32_t buffers = (c->out.mFormatFlags & kAudioFormatFlagIsNonInterleaved) ? c->out.mChannelsPerFrame : 1;
    for (uint32_t i = 0; i < out->mNumberBuffers && i < buffers; i++) {
        out->mBuffers[i].mDataByteSize = (uint32_t)(produced * c->out.mBytesPerFrame);
    }
    *packets = (uint32_t)produced;
    return status;
}

// MARK: - Converting whole buffers

typedef struct whole_input {
    const AudioBufferList *list;
    size_t frames, done;
    uint32_t bytes_per_frame;
    AudioBuffer copies[8];
} whole_input;

/// Gives the rest of the input buffers, once.
static OSStatus give_whole(void *handle, uint32_t *packets, AudioBufferList *data, AudioStreamPacketDescription **descriptions, void *user) {
    whole_input *input = user;
    size_t left = input->frames - input->done;
    if (!left) { *packets = 0; return 0; }
    uint32_t count = input->list->mNumberBuffers < data->mNumberBuffers ? input->list->mNumberBuffers : data->mNumberBuffers;
    for (uint32_t i = 0; i < count; i++) {
        data->mBuffers[i] = input->list->mBuffers[i];
        data->mBuffers[i].mData = (uint8_t *)data->mBuffers[i].mData + input->done * input->bytes_per_frame;
        data->mBuffers[i].mDataByteSize = (uint32_t)(left * input->bytes_per_frame);
    }
    *packets = (uint32_t)left;
    input->done = input->frames;
    return 0;
}

OSStatus darwin_AudioConverterConvertComplexBuffer(void *handle, uint32_t frames, const AudioBufferList *in, AudioBufferList *out)
    DARWIN_SYMBOL(AudioConverterConvertComplexBuffer);
OSStatus darwin_AudioConverterConvertComplexBuffer(void *handle, uint32_t frames, const AudioBufferList *in, AudioBufferList *out) {
    converter *c = valid(handle);
    if (!c || !in || !out) return kAudio_ParamError;
    if (c->in.mFormatID != kAudioFormatLinearPCM) return kAudioConverterErr_FormatNotSupported;
    whole_input input = { in, frames, 0, c->in.mBytesPerFrame, {{0}} };
    uint32_t packets = (uint32_t)ceil(frames * c->out.mSampleRate / c->in.mSampleRate);
    return darwin_AudioConverterFillComplexBuffer(c, give_whole, &input, &packets, out, NULL);
}

OSStatus darwin_AudioConverterConvertBuffer(void *handle, uint32_t in_size, const void *in, uint32_t *out_size, void *out)
    DARWIN_SYMBOL(AudioConverterConvertBuffer);
OSStatus darwin_AudioConverterConvertBuffer(void *handle, uint32_t in_size, const void *in, uint32_t *out_size, void *out) {
    converter *c = valid(handle);
    if (!c || !in || !out_size || !out) return kAudio_ParamError;
    if (c->in.mFormatID != kAudioFormatLinearPCM || (c->in.mFormatFlags & kAudioFormatFlagIsNonInterleaved)
        || (c->out.mFormatFlags & kAudioFormatFlagIsNonInterleaved)) {
        return kAudioConverterErr_FormatNotSupported;
    }
    AudioBufferList in_list = { 1, {{ c->in.mChannelsPerFrame, in_size, (void *)in }} };
    AudioBufferList out_list = { 1, {{ c->out.mChannelsPerFrame, *out_size, out }} };
    whole_input input = { &in_list, in_size / c->in.mBytesPerFrame, 0, c->in.mBytesPerFrame, {{0}} };
    uint32_t packets = *out_size / c->out.mBytesPerFrame;
    OSStatus status = darwin_AudioConverterFillComplexBuffer(c, give_whole, &input, &packets, &out_list, NULL);
    *out_size = packets * c->out.mBytesPerFrame;
    return status;
}

// MARK: - Properties

#define kAudioConverterCurrentInputStreamDescription FOURCC('a', 'c', 'i', 'd')
#define kAudioConverterCurrentOutputStreamDescription FOURCC('a', 'c', 'o', 'd')
#define kAudioConverterPropertyMaximumOutputPacketSize FOURCC('x', 'o', 'p', 's')
#define kAudioConverterPropertyMaximumInputPacketSize FOURCC('x', 'i', 'p', 's')
#define kAudioConverterPropertyMinimumInputBufferSize FOURCC('m', 'i', 'b', 's')
#define kAudioConverterPropertyMinimumOutputBufferSize FOURCC('m', 'o', 'b', 's')
#define kAudioConverterPrimeInfo FOURCC('p', 'r', 'i', 'm')
#define kAudioConverterPrimeMethod FOURCC('p', 'r', 'm', 'm')

static OSStatus converter_property(converter *c, uint32_t id, uint32_t *size, void *value) {
    union { uint32_t u32; AudioStreamBasicDescription format; uint32_t prime[2]; } v;
    uint32_t length;
    switch (id) {
    case kAudioConverterCurrentInputStreamDescription: v.format = c->in; length = sizeof v.format; break;
    case kAudioConverterCurrentOutputStreamDescription: v.format = c->out; length = sizeof v.format; break;
    case kAudioConverterPropertyMaximumOutputPacketSize: v.u32 = c->out.mBytesPerPacket; length = 4; break;
    case kAudioConverterPropertyMaximumInputPacketSize:
        v.u32 = c->in.mBytesPerPacket ? c->in.mBytesPerPacket : 34 * c->in.mChannelsPerFrame; length = 4; break;
    case kAudioConverterPropertyMinimumInputBufferSize:
        v.u32 = c->in.mBytesPerPacket ? c->in.mBytesPerPacket : 34; length = 4; break;
    case kAudioConverterPropertyMinimumOutputBufferSize: v.u32 = c->out.mBytesPerPacket; length = 4; break;
    case kAudioConverterPrimeInfo: v.prime[0] = v.prime[1] = 0; length = 8; break;
    case kAudioConverterPrimeMethod: v.u32 = 2; length = 4; break;      // kConverterPrimeMethod_None
    default: return kAudioConverterErr_PropertyNotSupported;
    }
    if (!value) { *size = length; return 0; }
    if (*size < length) return kAudioFileBadPropertySizeError;
    memcpy(value, &v, length);
    *size = length;
    return 0;
}

OSStatus darwin_AudioConverterGetProperty(void *handle, uint32_t id, uint32_t *size, void *value) DARWIN_SYMBOL(AudioConverterGetProperty);
OSStatus darwin_AudioConverterGetProperty(void *handle, uint32_t id, uint32_t *size, void *value) {
    converter *c = valid(handle);
    if (!c || !size || !value) return kAudio_ParamError;
    return converter_property(c, id, size, value);
}

OSStatus darwin_AudioConverterGetPropertyInfo(void *handle, uint32_t id, uint32_t *size, uint8_t *writable)
    DARWIN_SYMBOL(AudioConverterGetPropertyInfo);
OSStatus darwin_AudioConverterGetPropertyInfo(void *handle, uint32_t id, uint32_t *size, uint8_t *writable) {
    converter *c = valid(handle);
    if (!c) return kAudio_ParamError;
    uint32_t length = 0;
    OSStatus status = converter_property(c, id, &length, NULL);
    if (size) *size = length;
    if (writable) *writable = 0;
    return status;
}

/// Quality, priming, cookies and channel maps are accepted and change
/// nothing: linear interpolation, no priming, no decoders that need them.
OSStatus darwin_AudioConverterSetProperty(void *handle, uint32_t id, uint32_t size, const void *value) DARWIN_SYMBOL(AudioConverterSetProperty);
OSStatus darwin_AudioConverterSetProperty(void *handle, uint32_t id, uint32_t size, const void *value) {
    converter *c = valid(handle);
    if (!c) return kAudio_ParamError;
    switch (id) {
    case FOURCC('s', 'r', 'c', 'q'): case FOURCC('s', 'r', 'c', 'a'): case FOURCC('s', 'r', 'c', 'm'):
    case FOURCC('d', 'm', 'g', 'c'): case FOURCC('c', 'h', 'm', 'p'): case FOURCC('p', 'r', 'm', 'm'):
    case FOURCC('q', 'u', 'a', 'l'): case FOURCC('d', 'i', 't', 'h'):
        return 0;
    default:
        perry_audio_trace("converter: unsupported property '%c%c%c%c'", id >> 24, id >> 16 & 0xff, id >> 8 & 0xff, id & 0xff);
        return kAudioConverterErr_PropertyNotSupported;
    }
}
