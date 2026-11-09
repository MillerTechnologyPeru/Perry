// Audio units: RemoteIO (and the other output units) played through
// GStreamer, the multichannel, stereo and 3D mixers, the format converter and
// the varispeed.
//
// An output unit that has started has a thread that renders its input bus,
// from the bus's render callback or the unit connected to it, and pushes the
// audio to GStreamer, whose limited room paces it. A mixer renders each
// input bus in the bus's own format, resamples it to the output's rate (and
// by the 3D mixer's playback rate), applies its gain and pan, and sums them.
// App callbacks are called without any lock held: render notifications
// commonly set parameters.

#include "PerryAudioToolbox.h"

#include <math.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef OSStatus (*render_callback)(void *refcon, uint32_t *flags, const AudioTimeStamp *time, uint32_t bus, uint32_t frames,
                                    AudioBufferList *data);

typedef struct AudioComponentDescription {
    uint32_t componentType, componentSubType, componentManufacturer, componentFlags, componentFlagsMask;
} AudioComponentDescription;

enum kind { OUTPUT, MULTICHANNEL_MIXER, STEREO_MIXER, MIXER_3D, CONVERTER, VARISPEED };

typedef struct component {
    AudioComponentDescription description;
    enum kind kind;
    const char *name;
} component;

#define APPLE FOURCC('a', 'p', 'p', 'l')
static const component components[] = {
    { { FOURCC('a', 'u', 'o', 'u'), FOURCC('r', 'i', 'o', 'c'), APPLE, 0, 0 }, OUTPUT, "AURemoteIO" },
    { { FOURCC('a', 'u', 'o', 'u'), FOURCC('v', 'p', 'i', 'o'), APPLE, 0, 0 }, OUTPUT, "AUVoiceProcessingIO" },
    { { FOURCC('a', 'u', 'o', 'u'), FOURCC('g', 'e', 'n', 'r'), APPLE, 0, 0 }, OUTPUT, "AUGenericOutput" },
    { { FOURCC('a', 'u', 'o', 'u'), FOURCC('d', 'e', 'f', ' '), APPLE, 0, 0 }, OUTPUT, "AUDefaultOutput" },
    // macOS's HAL and system outputs: the one device (hardware.c).
    { { FOURCC('a', 'u', 'o', 'u'), FOURCC('a', 'h', 'a', 'l'), APPLE, 0, 0 }, OUTPUT, "AUHAL" },
    { { FOURCC('a', 'u', 'o', 'u'), FOURCC('s', 'y', 's', ' '), APPLE, 0, 0 }, OUTPUT, "AUSystemOutput" },
    { { FOURCC('a', 'u', 'm', 'x'), FOURCC('m', 'c', 'm', 'x'), APPLE, 0, 0 }, MULTICHANNEL_MIXER, "AUMultiChannelMixer" },
    { { FOURCC('a', 'u', 'm', 'x'), FOURCC('s', 'm', 'x', 'r'), APPLE, 0, 0 }, STEREO_MIXER, "AUMixer" },
    { { FOURCC('a', 'u', 'm', 'x'), FOURCC('3', 'd', 'e', 'm'), APPLE, 0, 0 }, MIXER_3D, "AU3DMixerEmbedded" },
    { { FOURCC('a', 'u', 'm', 'x'), FOURCC('3', 'd', 'm', 'x'), APPLE, 0, 0 }, MIXER_3D, "AU3DMixer" },
    { { FOURCC('a', 'u', 'f', 'c'), FOURCC('c', 'o', 'n', 'v'), APPLE, 0, 0 }, CONVERTER, "AUConverter" },
    { { FOURCC('a', 'u', 'f', 'c'), FOURCC('v', 'a', 'r', 'i'), APPLE, 0, 0 }, VARISPEED, "AUVarispeed" },
};
#define COMPONENT_COUNT (sizeof components / sizeof *components)

// Scopes, properties and parameters.
#define kAudioUnitScope_Global 0
#define kAudioUnitScope_Input 1
#define kAudioUnitScope_Output 2
#define kAudioUnitProperty_MakeConnection 1
#define kAudioUnitProperty_SampleRate 2
#define kAudioUnitProperty_StreamFormat 8
#define kAudioUnitProperty_ElementCount 11
#define kAudioUnitProperty_Latency 12
#define kAudioUnitProperty_MaximumFramesPerSlice 14
#define kAudioUnitProperty_LastRenderError 22
#define kAudioUnitProperty_SetRenderCallback 23
#define kAudioUnitProperty_ShouldAllocateBuffer 51
#define kAudioOutputUnitProperty_EnableIO 2003
#define kAudioUnitRenderAction_PreRender (1u << 2)
#define kAudioUnitRenderAction_PostRender (1u << 3)
#define kAudioUnitRenderAction_OutputIsSilence (1u << 4)
#define kMultiChannelMixerParam_Volume 0
#define kMultiChannelMixerParam_Enable 1
#define kMultiChannelMixerParam_Pan 2
#define kStereoMixerParam_Volume 0
#define kStereoMixerParam_Pan 1
#define kVarispeedParam_PlaybackRate 0
#define kVarispeedParam_PlaybackCents 1
#define k3DMixerParam_Azimuth 0
#define k3DMixerParam_Gain 3
#define k3DMixerParam_PlaybackRate 4

#define PARAMETERS 32
#define MAX_CHANNELS 8

typedef struct bus {
    AudioStreamBasicDescription format;
    bool format_set;                        // by the program, on the input scope
    bool rate_follows_output;               // set with a sample rate of 0
    render_callback callback;
    void *refcon;
    struct unit *source;
    uint32_t source_output;
    float parameters[PARAMETERS];
    /// Resampling: the last frame of the previous slice and the next
    /// output's position after it.
    float last[MAX_CHANNELS];
    double position;
} bus;

typedef struct stored_property {
    uint32_t id, scope, element, size;
    void *value;
} stored_property;

typedef struct notification {
    render_callback proc;
    void *refcon;
} notification;

typedef struct unit {
    uint32_t magic;
    const component *component;
    pthread_mutex_t lock;
    bus *inputs;
    uint32_t input_count;
    AudioStreamBasicDescription output;     // the output element's format
    float output_parameters[PARAMETERS];
    float global_parameters[PARAMETERS];
    uint32_t max_frames;
    uint32_t enable_io[2];                  // input, output
    notification notifications[8];
    uint32_t notification_count;
    stored_property *stored;
    uint32_t stored_count;
    bool initialized;
    /// Scratch output buffers for AudioUnitRender callers that give none.
    void *scratch;
    size_t scratch_size;

    // Output units.
    /// The thread pushing to the pipeline runs from the first start to
    /// disposal; between a stop and the next start it pushes silence
    /// instead of rendering, so the device stays open and the stream's
    /// times keep up with the clock. `rendering` is held while it renders.
    pthread_t thread;
    pthread_mutex_t rendering;
    bool thread_started, running, stop;
    void *pipeline, *src;
    double sample_time;
} unit;

#define UNIT_MAGIC FOURCC('p', 'a', 'u', 'n')

static unit *valid(void *handle) {
    unit *u = handle;
    return u && u->magic == UNIT_MAGIC ? u : NULL;
}

/// Float32, non-interleaved, stereo at 44.1 kHz: the canonical format.
static AudioStreamBasicDescription canonical(void) {
    return (AudioStreamBasicDescription){
        44100, kAudioFormatLinearPCM,
        kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
        4, 1, 4, 2, 32, 0,
    };
}

static void bus_defaults(unit *u, bus *b) {
    memset(b, 0, sizeof *b);
    b->format = canonical();
    switch (u->component->kind) {
    case MULTICHANNEL_MIXER:
        b->parameters[kMultiChannelMixerParam_Volume] = 1;
        b->parameters[kMultiChannelMixerParam_Enable] = 1;
        break;
    case STEREO_MIXER:
        b->parameters[kStereoMixerParam_Volume] = 1;
        b->parameters[kStereoMixerParam_Pan] = 0.5f;
        break;
    case MIXER_3D:
        b->parameters[k3DMixerParam_PlaybackRate] = 1;
        break;
    default:
        break;
    }
}

/// A mixer may have no inputs, as games set before adding their voices;
/// the buses' storage stays, for one.
static bool set_input_count(unit *u, uint32_t count) {
    if (count > 128) return false;
    bus *inputs = realloc(u->inputs, (count ? count : 1) * sizeof *inputs);
    if (!inputs) return false;
    for (uint32_t i = u->input_count; i < count; i++) bus_defaults(u, &inputs[i]);
    u->inputs = inputs;
    u->input_count = count;
    return true;
}

// MARK: - Components

void *darwin_AudioComponentFindNext(const void *after, const AudioComponentDescription *description) DARWIN_SYMBOL(AudioComponentFindNext);
void *darwin_AudioComponentFindNext(const void *after, const AudioComponentDescription *description) {
    size_t start = 0;
    if (after) {
        for (size_t i = 0; i < COMPONENT_COUNT; i++) if (&components[i] == after) start = i + 1;
    }
    for (size_t i = start; i < COMPONENT_COUNT; i++) {
        const AudioComponentDescription *d = &components[i].description;
        if (description && ((description->componentType && description->componentType != d->componentType)
                            || (description->componentSubType && description->componentSubType != d->componentSubType)
                            || (description->componentManufacturer && description->componentManufacturer != d->componentManufacturer))) {
            continue;
        }
        return (void *)&components[i];
    }
    if (description) {
        uint32_t t = description->componentType, s = description->componentSubType;
        perry_audio_warn("no audio unit '%c%c%c%c'/'%c%c%c%c'", t >> 24, t >> 16 & 0xff, t >> 8 & 0xff, t & 0xff,
                         s >> 24, s >> 16 & 0xff, s >> 8 & 0xff, s & 0xff);
    }
    return NULL;
}

static const component *valid_component(const void *c) {
    for (size_t i = 0; i < COMPONENT_COUNT; i++) if (&components[i] == c) return &components[i];
    return NULL;
}

OSStatus darwin_AudioComponentGetDescription(const void *c, AudioComponentDescription *description) DARWIN_SYMBOL(AudioComponentGetDescription);
OSStatus darwin_AudioComponentGetDescription(const void *c, AudioComponentDescription *description) {
    const component *found = valid_component(c);
    if (!found || !description) return kAudio_ParamError;
    *description = found->description;
    return 0;
}

OSStatus darwin_AudioComponentGetVersion(const void *c, uint32_t *version) DARWIN_SYMBOL(AudioComponentGetVersion);
OSStatus darwin_AudioComponentGetVersion(const void *c, uint32_t *version) {
    if (!valid_component(c) || !version) return kAudio_ParamError;
    *version = 0x10000;
    return 0;
}

OSStatus darwin_AudioComponentInstanceNew(const void *c, void **out) DARWIN_SYMBOL(AudioComponentInstanceNew);
OSStatus darwin_AudioComponentInstanceNew(const void *c, void **out) {
    const component *found = valid_component(c);
    if (!found || !out) return kAudio_ParamError;
    unit *u = calloc(1, sizeof *u);
    if (!u) return kAudio_MemFullError;
    u->magic = UNIT_MAGIC;
    u->component = found;
    pthread_mutexattr_t attributes;
    pthread_mutexattr_init(&attributes);
    pthread_mutexattr_settype(&attributes, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&u->lock, &attributes);
    pthread_mutex_init(&u->rendering, NULL);
    pthread_mutexattr_destroy(&attributes);
    u->output = canonical();
    u->max_frames = 4096;
    u->enable_io[0] = 0;
    u->enable_io[1] = 1;
    switch (found->kind) {
    case MULTICHANNEL_MIXER: u->output_parameters[kMultiChannelMixerParam_Volume] = 1; set_input_count(u, 8); break;
    case STEREO_MIXER: u->output_parameters[kStereoMixerParam_Volume] = 1; set_input_count(u, 8); break;
    case MIXER_3D: set_input_count(u, 8); break;
    case VARISPEED: u->global_parameters[kVarispeedParam_PlaybackRate] = 1; set_input_count(u, 1); break;
    default: set_input_count(u, 1); break;
    }
    perry_audio_trace("%s %p", found->name, (void *)u);
    *out = u;
    return 0;
}

static void output_end(unit *u);

OSStatus darwin_AudioComponentInstanceDispose(void *handle) DARWIN_SYMBOL(AudioComponentInstanceDispose);
OSStatus darwin_AudioComponentInstanceDispose(void *handle) {
    unit *u = valid(handle);
    if (!u) return kAudio_ParamError;
    output_end(u);
    const perry_gst *g = perry_gst_get();
    if (g && u->pipeline) {
        if (u->src) g->object_unref(u->src);
        g->object_unref(u->pipeline);
    }
    u->magic = 0;
    for (uint32_t i = 0; i < u->stored_count; i++) free(u->stored[i].value);
    free(u->stored);
    free(u->inputs);
    free(u->scratch);
    pthread_mutex_destroy(&u->lock);
    free(u);
    return 0;
}

void *darwin_AudioComponentInstanceGetComponent(void *handle) DARWIN_SYMBOL(AudioComponentInstanceGetComponent);
void *darwin_AudioComponentInstanceGetComponent(void *handle) {
    unit *u = valid(handle);
    return u ? (void *)u->component : NULL;
}

OSStatus darwin_AudioUnitInitialize(void *handle) DARWIN_SYMBOL(AudioUnitInitialize);
OSStatus darwin_AudioUnitInitialize(void *handle) {
    unit *u = valid(handle);
    if (!u) return kAudio_ParamError;
    u->initialized = true;
    return 0;
}

OSStatus darwin_AudioUnitUninitialize(void *handle) DARWIN_SYMBOL(AudioUnitUninitialize);
OSStatus darwin_AudioUnitUninitialize(void *handle) {
    unit *u = valid(handle);
    if (!u) return kAudio_ParamError;
    u->initialized = false;
    return 0;
}

OSStatus darwin_AudioUnitReset(void *handle, uint32_t scope, uint32_t element) DARWIN_SYMBOL(AudioUnitReset);
OSStatus darwin_AudioUnitReset(void *handle, uint32_t scope, uint32_t element) {
    unit *u = valid(handle);
    if (!u) return kAudio_ParamError;
    pthread_mutex_lock(&u->lock);
    for (uint32_t i = 0; i < u->input_count; i++) {
        memset(u->inputs[i].last, 0, sizeof u->inputs[i].last);
        u->inputs[i].position = 0;
    }
    pthread_mutex_unlock(&u->lock);
    return 0;
}

// MARK: - Rendering

typedef struct buffers {
    AudioBufferList *list;
    void *memory;
} buffers;

/// An AudioBufferList for `frames` frames of `format`, zeroed.
static bool allocate(const AudioStreamBasicDescription *format, uint32_t frames, buffers *out) {
    bool split = format->mFormatFlags & kAudioFormatFlagIsNonInterleaved;
    uint32_t count = split ? format->mChannelsPerFrame : 1;
    size_t each = (size_t)frames * format->mBytesPerFrame;
    out->list = calloc(1, sizeof(AudioBufferList) + count * sizeof(AudioBuffer));
    out->memory = calloc(count, each ? each : 1);
    if (!out->list || !out->memory) {
        free(out->list);
        free(out->memory);
        return false;
    }
    out->list->mNumberBuffers = count;
    for (uint32_t i = 0; i < count; i++) {
        out->list->mBuffers[i] = (AudioBuffer){ split ? 1 : format->mChannelsPerFrame, (uint32_t)each, (uint8_t *)out->memory + i * each };
    }
    return true;
}

static void release(buffers *b) {
    free(b->list);
    free(b->memory);
}

static OSStatus render(unit *u, uint32_t *flags, const AudioTimeStamp *time, uint32_t frames, AudioBufferList *io);

/// An input bus's audio, `frames` frames in its own format; silence if it
/// has no source.
static OSStatus pull(unit *u, uint32_t index, const AudioTimeStamp *time, uint32_t frames, AudioBufferList *io) {
    pthread_mutex_lock(&u->lock);
    bus b = u->inputs[index];
    pthread_mutex_unlock(&u->lock);
    uint32_t flags = 0;
    if (b.callback) return b.callback(b.refcon, &flags, time, index, frames, io);
    if (b.source && valid(b.source)) {
        unit *source = b.source;
        if (!memcmp(&source->output, &b.format, sizeof b.format)) return render(source, &flags, time, frames, io);
        // Different formats: render the source's, and convert.
        buffers rendered;
        if (!allocate(&source->output, frames, &rendered)) return kAudio_MemFullError;
        OSStatus status = render(source, &flags, time, frames, rendered.list);
        uint32_t in_channels = source->output.mChannelsPerFrame, out_channels = b.format.mChannelsPerFrame;
        float *a = malloc((size_t)frames * in_channels * sizeof(float)), *c = malloc((size_t)frames * out_channels * sizeof(float));
        if (a && c) {
            perry_pcm_read(&source->output, rendered.list, 0, frames, a);
            perry_pcm_remap(a, in_channels, c, out_channels, frames);
            perry_pcm_write(&b.format, io, 0, frames, c);
        }
        free(a);
        free(c);
        release(&rendered);
        return status;
    }
    return 0;   // silence: io is zeroed
}

/// Pan, as gains for the left and right channels: -1 left to 1 right, at
/// equal power.
static void pan_gains(float pan, float *left, float *right) {
    if (pan < -1) pan = -1;
    if (pan > 1) pan = 1;
    double angle = (pan + 1) * M_PI / 4;
    *left = (float)(cos(angle) * M_SQRT2);
    *right = (float)(sin(angle) * M_SQRT2);
    if (*left > 1) *left = 1;
    if (*right > 1) *right = 1;
}

/// A mixer's output: each input bus resampled, its gain and pan applied,
/// summed, and the output's gain.
static OSStatus mix(unit *u, const AudioTimeStamp *time, uint32_t frames, AudioBufferList *io) {
    const AudioStreamBasicDescription out = u->output;
    uint32_t channels = out.mChannelsPerFrame > MAX_CHANNELS ? MAX_CHANNELS : out.mChannelsPerFrame;
    float *sum = calloc((size_t)frames * out.mChannelsPerFrame, sizeof(float));
    if (!sum) return kAudio_MemFullError;
    enum kind kind = u->component->kind;
    for (uint32_t index = 0; index < u->input_count; index++) {
        pthread_mutex_lock(&u->lock);
        bus *b = &u->inputs[index];
        bool connected = b->callback || b->source;
        AudioStreamBasicDescription format = b->format;
        float volume = 1, pan = 0, rate = 1;
        bool enabled = true;
        if (kind == MULTICHANNEL_MIXER) {
            volume = b->parameters[kMultiChannelMixerParam_Volume];
            enabled = b->parameters[kMultiChannelMixerParam_Enable] != 0;
            pan = b->parameters[kMultiChannelMixerParam_Pan];
        } else if (kind == STEREO_MIXER) {
            // Pan runs from 0 to 1 here, not -1 to 1.
            volume = b->parameters[kStereoMixerParam_Volume];
            pan = b->parameters[kStereoMixerParam_Pan] * 2 - 1;
        } else if (kind == VARISPEED) {
            rate = u->global_parameters[kVarispeedParam_PlaybackRate];
            if (rate <= 0) rate = 1;
        } else if (kind == MIXER_3D) {
            volume = powf(10, b->parameters[k3DMixerParam_Gain] / 20);
            pan = sinf(b->parameters[k3DMixerParam_Azimuth] * (float)M_PI / 180);
            rate = b->parameters[k3DMixerParam_PlaybackRate];
            if (rate <= 0) rate = 1;
        }
        double step = rate * format.mSampleRate / (out.mSampleRate > 0 ? out.mSampleRate : 44100);
        double position = b->position;
        float last[MAX_CHANNELS];
        memcpy(last, b->last, sizeof last);
        pthread_mutex_unlock(&u->lock);
        if (!connected || !enabled || !perry_pcm_supported(&format)) continue;

        uint32_t needed = (uint32_t)floor(position + frames * step);
        uint32_t in_channels = format.mChannelsPerFrame > MAX_CHANNELS ? MAX_CHANNELS : format.mChannelsPerFrame;
        float *input = calloc(((size_t)needed + 1) * format.mChannelsPerFrame, sizeof(float));
        if (!input) continue;
        memcpy(input, last, in_channels * sizeof(float));
        if (needed) {
            buffers pulled;
            if (allocate(&format, needed, &pulled)) {
                OSStatus status = pull(u, index, time, needed, pulled.list);
                if (!status) perry_pcm_read(&format, pulled.list, 0, needed, input + format.mChannelsPerFrame);
                release(&pulled);
            }
        }
        // Gains for each output channel from each input channel.
        float left = 1, right = 1;
        if (channels == 2) pan_gains(pan, &left, &right);
        for (uint32_t i = 0; i < frames; i++) {
            double x = position + i * step;
            uint32_t k = (uint32_t)x;
            float t = (float)(x - k);
            if (k > needed) k = needed;
            uint32_t k1 = k + 1 > needed ? needed : k + 1;
            const float *a = input + (size_t)k * format.mChannelsPerFrame, *c = input + (size_t)k1 * format.mChannelsPerFrame;
            float frame[MAX_CHANNELS];
            for (uint32_t ch = 0; ch < in_channels; ch++) frame[ch] = a[ch] + (c[ch] - a[ch]) * t;
            float *target = sum + (size_t)i * out.mChannelsPerFrame;
            if (channels == 2) {
                float l = frame[0], r = in_channels > 1 ? frame[1] : frame[0];
                target[0] += l * volume * left;
                target[1] += r * volume * right;
            } else {
                float mapped[MAX_CHANNELS];
                perry_pcm_remap(frame, in_channels, mapped, channels, 1);
                for (uint32_t ch = 0; ch < channels; ch++) target[ch] += mapped[ch] * volume;
            }
        }
        pthread_mutex_lock(&u->lock);
        if (index < u->input_count) {
            b = &u->inputs[index];
            memcpy(b->last, input + (size_t)needed * format.mChannelsPerFrame, in_channels * sizeof(float));
            b->position = position + frames * step - needed;
        }
        pthread_mutex_unlock(&u->lock);
        free(input);
    }
    float master = 1;
    if (kind == MULTICHANNEL_MIXER) master = u->output_parameters[kMultiChannelMixerParam_Volume];
    else if (kind == STEREO_MIXER) master = u->output_parameters[kStereoMixerParam_Volume];
    else if (kind == MIXER_3D) master = powf(10, u->output_parameters[k3DMixerParam_Gain] / 20);
    if (master != 1) for (size_t i = 0; i < (size_t)frames * out.mChannelsPerFrame; i++) sum[i] *= master;
    perry_pcm_write(&out, io, 0, frames, sum);
    free(sum);
    return 0;
}

/// A unit's output, `frames` frames in its output format, between its
/// render notifications.
static OSStatus render(unit *u, uint32_t *flags, const AudioTimeStamp *time, uint32_t frames, AudioBufferList *io) {
    pthread_mutex_lock(&u->lock);
    notification notifications[8];
    uint32_t count = u->notification_count;
    memcpy(notifications, u->notifications, count * sizeof *notifications);
    pthread_mutex_unlock(&u->lock);
    for (uint32_t i = 0; i < count; i++) {
        uint32_t pre = (flags ? *flags : 0) | kAudioUnitRenderAction_PreRender;
        notifications[i].proc(notifications[i].refcon, &pre, time, 0, frames, io);
    }
    for (uint32_t i = 0; i < io->mNumberBuffers; i++) if (io->mBuffers[i].mData) memset(io->mBuffers[i].mData, 0, io->mBuffers[i].mDataByteSize);
    OSStatus status;
    if (u->component->kind == OUTPUT) {
        // An output unit's output is its input bus 0, as the hardware gets it.
        status = pull(u, 0, time, frames, io);
    } else {
        status = mix(u, time, frames, io);
    }
    for (uint32_t i = 0; i < count; i++) {
        uint32_t post = (flags ? *flags : 0) | kAudioUnitRenderAction_PostRender;
        notifications[i].proc(notifications[i].refcon, &post, time, 0, frames, io);
    }
    return status;
}

OSStatus darwin_AudioUnitRender(void *handle, uint32_t *flags, const AudioTimeStamp *time, uint32_t bus_number, uint32_t frames,
                                AudioBufferList *io) DARWIN_SYMBOL(AudioUnitRender);
OSStatus darwin_AudioUnitRender(void *handle, uint32_t *flags, const AudioTimeStamp *time, uint32_t bus_number, uint32_t frames,
                                AudioBufferList *io) {
    unit *u = valid(handle);
    if (!u || !io) return kAudio_ParamError;
    if (frames > u->max_frames) return -10874;     // kAudioUnitErr_TooManyFramesToProcess
    // Buffers without memory get the unit's own.
    size_t needed = (size_t)frames * u->output.mBytesPerFrame;
    for (uint32_t i = 0; i < io->mNumberBuffers; i++) {
        if (!io->mBuffers[i].mData) {
            pthread_mutex_lock(&u->lock);
            size_t total = needed * io->mNumberBuffers;
            if (u->scratch_size < total) {
                free(u->scratch);
                u->scratch = calloc(1, total);
                u->scratch_size = u->scratch ? total : 0;
            }
            pthread_mutex_unlock(&u->lock);
            if (!u->scratch) return kAudio_MemFullError;
            io->mBuffers[i].mData = (uint8_t *)u->scratch + i * needed;
            io->mBuffers[i].mDataByteSize = (uint32_t)needed;
        }
    }
    AudioTimeStamp zero = { 0 };
    return render(u, flags, time ? time : &zero, frames, io);
}

// MARK: - Output units

static uint64_t monotonic(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint64_t)now.tv_sec * 1000000000ull + (uint64_t)now.tv_nsec;
}

/// What the output thread hands GStreamer: the input bus's format, as
/// interleaved floats.
static void *output_run(void *argument) {
    unit *u = argument;
    const perry_gst *g = perry_gst_get();
    uint32_t frames = u->max_frames < 512 ? u->max_frames : 512;
    uint64_t pushed = 0;
    AudioStreamBasicDescription built = canonical();
    for (;;) {
        pthread_mutex_lock(&u->lock);
        bool stop = u->stop;
        AudioStreamBasicDescription format = u->inputs[0].format;
        pthread_mutex_unlock(&u->lock);
        if (stop) break;
        if (!perry_pcm_supported(&format)) format = canonical();
        // The pipeline's caps are its first format's.
        if (pushed == 0) built = format;
        else if (format.mSampleRate != built.mSampleRate || format.mChannelsPerFrame != built.mChannelsPerFrame) format = built;
        uint32_t channels = format.mChannelsPerFrame;
        size_t bytes = (size_t)frames * channels * sizeof(float);
        float *samples = calloc(1, bytes);
        if (!samples) break;
        pthread_mutex_lock(&u->rendering);
        pthread_mutex_lock(&u->lock);
        bool running = u->running;
        pthread_mutex_unlock(&u->lock);
        if (running) {
            buffers io;
            if (allocate(&format, frames, &io)) {
                AudioTimeStamp time = { 0 };
                time.mSampleTime = u->sample_time;
                time.mHostTime = monotonic();
                time.mRateScalar = 1;
                time.mFlags = kAudioTimeStampSampleTimeValid | kAudioTimeStampHostTimeValid;
                uint32_t flags = 0;
                render(u, &flags, &time, frames, io.list);
                u->sample_time += frames;
                perry_pcm_read(&format, io.list, 0, frames, samples);
                release(&io);
            }
        }
        pthread_mutex_unlock(&u->rendering);
        if (g && u->src) {
            void *buffer = g->buffer_new_allocate(NULL, bytes, NULL);
            if (buffer) {
                g->buffer_fill(buffer, 0, samples, bytes);
                uint64_t start = (uint64_t)((double)pushed * 1e9 / format.mSampleRate);
                pushed += frames;
                perry_gst_buffer_set_time(buffer, start, (uint64_t)((double)pushed * 1e9 / format.mSampleRate) - start);
                if (g->app_src_push_buffer(u->src, buffer) != 0) {
                    // Stopped under the push, or the pipeline failed: wait
                    // as long as the audio would have sounded.
                    struct timespec wait = { 0, (long)((double)frames * 1e9 / format.mSampleRate) };
                    nanosleep(&wait, NULL);
                }
            }
        } else {
            // Silent: as long as the audio would sound.
            struct timespec wait = { 0, (long)((double)frames * 1e9 / format.mSampleRate) };
            nanosleep(&wait, NULL);
        }
        free(samples);
    }
    return NULL;
}

/// The pipeline for the unit's input format.
static bool output_build(unit *u) {
    const perry_gst *g = perry_gst_get();
    if (!g) return false;
    AudioStreamBasicDescription format = u->inputs[0].format;
    if (!perry_pcm_supported(&format)) format = canonical();
    if (u->pipeline) return true;
    char description[512];
    // A twentieth of a second waiting in the source keeps the delay short.
    size_t room = (size_t)(format.mSampleRate * format.mChannelsPerFrame * 4 / 20);
    snprintf(description, sizeof description,
             "appsrc name=src format=time block=true max-bytes=%zu "
             "caps=\"audio/x-raw,format=F32LE,layout=interleaved,rate=(int)%d,channels=(int)%u\" ! "
             "audioconvert ! audioresample ! autoaudiosink", room, (int)format.mSampleRate, format.mChannelsPerFrame);
    perry_audio_trace("%s %p: %s", u->component->name, (void *)u, description);
    u->pipeline = g->parse_launch(description, NULL);
    if (u->pipeline) u->src = g->bin_get_by_name(u->pipeline, "src");
    if (!u->pipeline || !u->src) {
        perry_audio_warn("%s: GStreamer can't build its pipeline; playing silently", u->component->name);
        return false;
    }
    return true;
}

OSStatus darwin_AudioOutputUnitStart(void *handle) DARWIN_SYMBOL(AudioOutputUnitStart);
OSStatus darwin_AudioOutputUnitStart(void *handle) {
    unit *u = valid(handle);
    if (!u || u->component->kind != OUTPUT) return kAudio_ParamError;
    pthread_mutex_lock(&u->lock);
    if (u->running) { pthread_mutex_unlock(&u->lock); return 0; }
    if (!u->thread_started) {
        if (output_build(u)) perry_gst_get()->set_state(u->pipeline, PERRY_GST_STATE_PLAYING);
        u->stop = false;
        u->thread_started = pthread_create(&u->thread, NULL, output_run, u) == 0;
    }
    u->running = u->thread_started;
    pthread_mutex_unlock(&u->lock);
    return u->running ? 0 : kAudio_MemFullError;
}

/// Stops rendering: once this returns, the unit's callbacks aren't called,
/// as on Darwin. The thread goes on pushing silence.
static OSStatus output_stop(unit *u) {
    pthread_mutex_lock(&u->lock);
    bool was = u->running;
    u->running = false;
    pthread_mutex_unlock(&u->lock);
    // Waits out a render under way, unless this is that render's thread.
    if (was && u->thread_started && !pthread_equal(pthread_self(), u->thread)) {
        pthread_mutex_lock(&u->rendering);
        pthread_mutex_unlock(&u->rendering);
    }
    return 0;
}

/// Ends the thread and closes the device, for disposal.
static void output_end(unit *u) {
    output_stop(u);
    pthread_mutex_lock(&u->lock);
    bool started = u->thread_started;
    u->stop = true;
    u->thread_started = false;
    pthread_t thread = u->thread;
    pthread_mutex_unlock(&u->lock);
    // Stopping the pipeline frees a push waiting for room.
    const perry_gst *g = perry_gst_get();
    if (g && u->pipeline) g->set_state(u->pipeline, PERRY_GST_STATE_NULL);
    if (!started) return;
    if (!pthread_equal(pthread_self(), thread)) pthread_join(thread, NULL);
    else pthread_detach(thread);
}

OSStatus darwin_AudioOutputUnitStop(void *handle) DARWIN_SYMBOL(AudioOutputUnitStop);
OSStatus darwin_AudioOutputUnitStop(void *handle) {
    unit *u = valid(handle);
    if (!u || u->component->kind != OUTPUT) return kAudio_ParamError;
    return output_stop(u);
}

// MARK: - Properties

static stored_property *find_stored(unit *u, uint32_t id, uint32_t scope, uint32_t element) {
    for (uint32_t i = 0; i < u->stored_count; i++) {
        stored_property *p = &u->stored[i];
        if (p->id == id && p->scope == scope && p->element == element) return p;
    }
    return NULL;
}

/// The property's value and size; false if the unit has none.
static bool property(unit *u, uint32_t id, uint32_t scope, uint32_t element, void *value, uint32_t *size, OSStatus *error) {
    union {
        AudioStreamBasicDescription format;
        uint32_t u32;
        double f64;
        struct { render_callback proc; void *refcon; } callback;
        struct { void *source; uint32_t output, input; } connection;
    } v;
    uint32_t length;
    const void *source = &v;
    *error = 0;
    switch (id) {
    case kAudioUnitProperty_StreamFormat:
    case kAudioUnitProperty_SampleRate:
        if (scope == kAudioUnitScope_Input) {
            if (element >= u->input_count) { *error = kAudioUnitErr_InvalidElement; return false; }
            v.format = u->inputs[element].format;
        } else {
            v.format = u->output;
        }
        if (id == kAudioUnitProperty_SampleRate) { v.f64 = v.format.mSampleRate; length = 8; }
        else length = sizeof v.format;
        break;
    case kAudioUnitProperty_ElementCount:
        v.u32 = scope == kAudioUnitScope_Input ? u->input_count : 1;
        length = 4;
        break;
    case kAudioUnitProperty_MaximumFramesPerSlice: v.u32 = u->max_frames; length = 4; break;
    case kAudioUnitProperty_Latency: v.f64 = 0; length = 8; break;
    case kAudioUnitProperty_LastRenderError: v.u32 = 0; length = 4; break;
    case kAudioUnitProperty_ShouldAllocateBuffer: v.u32 = 1; length = 4; break;
    case kAudioOutputUnitProperty_EnableIO: v.u32 = u->enable_io[scope == kAudioUnitScope_Input ? 0 : 1]; length = 4; break;
    case kAudioUnitProperty_SetRenderCallback:
        if (element >= u->input_count) { *error = kAudioUnitErr_InvalidElement; return false; }
        v.callback.proc = u->inputs[element].callback;
        v.callback.refcon = u->inputs[element].refcon;
        length = sizeof v.callback;
        break;
    case kAudioUnitProperty_MakeConnection:
        if (element >= u->input_count) { *error = kAudioUnitErr_InvalidElement; return false; }
        v.connection.source = u->inputs[element].source;
        v.connection.output = u->inputs[element].source_output;
        v.connection.input = element;
        length = sizeof v.connection;
        break;
    default: {
        stored_property *stored = find_stored(u, id, scope, element);
        if (!stored) { *error = kAudioUnitErr_InvalidProperty; return false; }
        source = stored->value;
        length = stored->size;
        break;
    }
    }
    if (value) {
        if (*size < length) { *error = kAudioUnitErr_InvalidPropertyValue; return false; }
        memcpy(value, source, length);
    }
    *size = length;
    return true;
}

OSStatus darwin_AudioUnitGetProperty(void *handle, uint32_t id, uint32_t scope, uint32_t element, void *value, uint32_t *size)
    DARWIN_SYMBOL(AudioUnitGetProperty);
OSStatus darwin_AudioUnitGetProperty(void *handle, uint32_t id, uint32_t scope, uint32_t element, void *value, uint32_t *size) {
    unit *u = valid(handle);
    if (!u || !value || !size) return kAudio_ParamError;
    pthread_mutex_lock(&u->lock);
    OSStatus error;
    property(u, id, scope, element, value, size, &error);
    pthread_mutex_unlock(&u->lock);
    if (error) perry_audio_trace("%s: no property %u (scope %u, element %u)", u->component->name, id, scope, element);
    return error;
}

OSStatus darwin_AudioUnitGetPropertyInfo(void *handle, uint32_t id, uint32_t scope, uint32_t element, uint32_t *size,
                                         uint8_t *writable) DARWIN_SYMBOL(AudioUnitGetPropertyInfo);
OSStatus darwin_AudioUnitGetPropertyInfo(void *handle, uint32_t id, uint32_t scope, uint32_t element, uint32_t *size,
                                         uint8_t *writable) {
    unit *u = valid(handle);
    if (!u) return kAudio_ParamError;
    pthread_mutex_lock(&u->lock);
    uint32_t length = 0;
    OSStatus error;
    property(u, id, scope, element, NULL, &length, &error);
    pthread_mutex_unlock(&u->lock);
    if (size) *size = length;
    if (writable) *writable = 1;
    return error;
}

static void store(unit *u, uint32_t id, uint32_t scope, uint32_t element, const void *value, uint32_t size) {
    stored_property *p = find_stored(u, id, scope, element);
    if (!p) {
        stored_property *grown = realloc(u->stored, (u->stored_count + 1) * sizeof *grown);
        if (!grown) return;
        u->stored = grown;
        p = &u->stored[u->stored_count++];
        *p = (stored_property){ id, scope, element, 0, NULL };
    }
    void *copy = malloc(size ? size : 1);
    if (!copy) return;
    if (value) memcpy(copy, value, size);
    free(p->value);
    p->value = copy;
    p->size = size;
}

OSStatus darwin_AudioUnitSetProperty(void *handle, uint32_t id, uint32_t scope, uint32_t element, const void *value, uint32_t size)
    DARWIN_SYMBOL(AudioUnitSetProperty);
OSStatus darwin_AudioUnitSetProperty(void *handle, uint32_t id, uint32_t scope, uint32_t element, const void *value, uint32_t size) {
    unit *u = valid(handle);
    if (!u) return kAudio_ParamError;
    OSStatus status = 0;
    pthread_mutex_lock(&u->lock);
    switch (id) {
    case kAudioUnitProperty_StreamFormat: {
        if (!value || size < sizeof(AudioStreamBasicDescription)) { status = kAudio_ParamError; break; }
        const AudioStreamBasicDescription *f = value;
        if (!perry_pcm_supported(f) || f->mSampleRate < 0) { status = kAudioUnitErr_FormatNotSupported; break; }
        // A sample rate of 0 leaves it to the unit: an input takes the
        // output's, now or when the output's is set.
        if (scope == kAudioUnitScope_Input) {
            if (element >= u->input_count) { status = kAudioUnitErr_InvalidElement; break; }
            u->inputs[element].format = *f;
            u->inputs[element].format_set = true;
            u->inputs[element].rate_follows_output = f->mSampleRate == 0;
            if (f->mSampleRate == 0) u->inputs[element].format.mSampleRate = u->output.mSampleRate;
        } else {
            double kept = u->output.mSampleRate;
            u->output = *f;
            if (f->mSampleRate == 0) u->output.mSampleRate = kept;
            for (uint32_t i = 0; i < u->input_count; i++) {
                if (u->inputs[i].rate_follows_output) u->inputs[i].format.mSampleRate = u->output.mSampleRate;
            }
            // A program that gives an output unit's element 0 a format and
            // no input format renders in that one (Resident Evil 4). Its
            // 16-bit samples with the fixed-point flags of 8.24 are written
            // interleaved, however the flags read.
            if (u->component->kind == OUTPUT && element == 0 && u->input_count > 0 && !u->inputs[0].format_set) {
                AudioStreamBasicDescription input = u->output;
                bool fixed = input.mFormatFlags & kLinearPCMFormatFlagsSampleFractionMask;
                if (fixed && input.mBitsPerChannel == 16 && (input.mFormatFlags & kAudioFormatFlagIsNonInterleaved)) {
                    input.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
                    input.mBytesPerFrame = input.mBytesPerPacket = 2 * input.mChannelsPerFrame;
                }
                u->inputs[0].format = input;
            }
        }
        perry_audio_trace("%s: element %u %s format %u Hz, %u channels, flags %#x, %u bits", u->component->name, element,
                          scope == kAudioUnitScope_Input ? "input" : "output", (unsigned)f->mSampleRate, f->mChannelsPerFrame,
                          f->mFormatFlags, f->mBitsPerChannel);
        break;
    }
    case kAudioUnitProperty_SampleRate:
        if (!value || size < 8) { status = kAudio_ParamError; break; }
        if (scope == kAudioUnitScope_Input && element < u->input_count) u->inputs[element].format.mSampleRate = *(const double *)value;
        else if (scope != kAudioUnitScope_Input) u->output.mSampleRate = *(const double *)value;
        else status = kAudioUnitErr_InvalidElement;
        break;
    case kAudioUnitProperty_ElementCount:
        if (!value || size < 4) { status = kAudio_ParamError; break; }
        if (scope == kAudioUnitScope_Input && u->component->kind != OUTPUT) {
            if (!set_input_count(u, *(const uint32_t *)value)) status = kAudioUnitErr_InvalidPropertyValue;
        }
        break;
    case kAudioUnitProperty_MaximumFramesPerSlice:
        if (!value || size < 4) { status = kAudio_ParamError; break; }
        u->max_frames = *(const uint32_t *)value ? *(const uint32_t *)value : 4096;
        break;
    case kAudioOutputUnitProperty_EnableIO:
        if (!value || size < 4) { status = kAudio_ParamError; break; }
        u->enable_io[scope == kAudioUnitScope_Input ? 0 : 1] = *(const uint32_t *)value;
        break;
    case kAudioUnitProperty_SetRenderCallback: {
        if (element >= u->input_count) { status = kAudioUnitErr_InvalidElement; break; }
        bus *b = &u->inputs[element];
        // AURenderCallbackStruct: the function, then its refcon, a word each.
        if (value && size >= 2 * sizeof(void *)) {
            memcpy(&b->callback, value, sizeof b->callback);
            memcpy(&b->refcon, (const uint8_t *)value + sizeof(void *), sizeof b->refcon);
        } else {
            b->callback = NULL;
            b->refcon = NULL;
        }
        if (b->callback) b->source = NULL;
        break;
    }
    case kAudioUnitProperty_MakeConnection: {
        if (element >= u->input_count) { status = kAudioUnitErr_InvalidElement; break; }
        bus *b = &u->inputs[element];
        // AudioUnitConnection: the source unit, a word, then two 32-bit numbers.
        if (value && size >= sizeof(void *) + 8) {
            void *source;
            memcpy(&source, value, sizeof source);
            b->source = valid(source);
            memcpy(&b->source_output, (const uint8_t *)value + sizeof(void *), 4);
            if (b->source) b->callback = NULL;
        } else {
            b->source = NULL;
        }
        break;
    }
    default:
        store(u, id, scope, element, value, size);
        break;
    }
    pthread_mutex_unlock(&u->lock);
    if (status) perry_audio_trace("%s: setting property %u (scope %u, element %u) failed: %d", u->component->name, id, scope, element, (int)status);
    return status;
}

/// Property listeners are kept by the app and never called: nothing here
/// changes a property behind its back.
OSStatus darwin_AudioUnitAddPropertyListener(void *handle, uint32_t id, void *proc, void *user) DARWIN_SYMBOL(AudioUnitAddPropertyListener);
OSStatus darwin_AudioUnitAddPropertyListener(void *handle, uint32_t id, void *proc, void *user) {
    return valid(handle) ? 0 : kAudio_ParamError;
}

OSStatus darwin_AudioUnitRemovePropertyListenerWithUserData(void *handle, uint32_t id, void *proc, void *user)
    DARWIN_SYMBOL(AudioUnitRemovePropertyListenerWithUserData);
OSStatus darwin_AudioUnitRemovePropertyListenerWithUserData(void *handle, uint32_t id, void *proc, void *user) {
    return valid(handle) ? 0 : kAudio_ParamError;
}

OSStatus darwin_AudioUnitAddRenderNotify(void *handle, render_callback proc, void *refcon) DARWIN_SYMBOL(AudioUnitAddRenderNotify);
OSStatus darwin_AudioUnitAddRenderNotify(void *handle, render_callback proc, void *refcon) {
    unit *u = valid(handle);
    if (!u || !proc) return kAudio_ParamError;
    pthread_mutex_lock(&u->lock);
    OSStatus status = 0;
    if (u->notification_count < 8) u->notifications[u->notification_count++] = (notification){ proc, refcon };
    else status = kAudio_MemFullError;
    pthread_mutex_unlock(&u->lock);
    return status;
}

OSStatus darwin_AudioUnitRemoveRenderNotify(void *handle, render_callback proc, void *refcon) DARWIN_SYMBOL(AudioUnitRemoveRenderNotify);
OSStatus darwin_AudioUnitRemoveRenderNotify(void *handle, render_callback proc, void *refcon) {
    unit *u = valid(handle);
    if (!u) return kAudio_ParamError;
    pthread_mutex_lock(&u->lock);
    for (uint32_t i = 0; i < u->notification_count; i++) {
        if (u->notifications[i].proc == proc && u->notifications[i].refcon == refcon) {
            memmove(u->notifications + i, u->notifications + i + 1, (u->notification_count - i - 1) * sizeof *u->notifications);
            u->notification_count--;
            break;
        }
    }
    pthread_mutex_unlock(&u->lock);
    return 0;
}

// MARK: - Parameters

static float *parameter(unit *u, uint32_t id, uint32_t scope, uint32_t element) {
    if (id >= PARAMETERS) return NULL;
    switch (scope) {
    case kAudioUnitScope_Input: return element < u->input_count ? &u->inputs[element].parameters[id] : NULL;
    case kAudioUnitScope_Output: return &u->output_parameters[id];
    case kAudioUnitScope_Global: return &u->global_parameters[id];
    default: return NULL;
    }
}

DARWIN_FLOAT_ABI OSStatus darwin_AudioUnitSetParameter(void *handle, uint32_t id, uint32_t scope, uint32_t element, float value,
                                                         uint32_t offset)
    DARWIN_SYMBOL(AudioUnitSetParameter);
DARWIN_FLOAT_ABI OSStatus darwin_AudioUnitSetParameter(void *handle, uint32_t id, uint32_t scope, uint32_t element, float value,
                                                         uint32_t offset) {
    unit *u = valid(handle);
    if (!u) return kAudio_ParamError;
    pthread_mutex_lock(&u->lock);
    float *p = parameter(u, id, scope, element);
    if (p) *p = value;
    // A varispeed's rate and its pitch in cents are one setting.
    if (p && u->component->kind == VARISPEED && scope == kAudioUnitScope_Global) {
        if (id == kVarispeedParam_PlaybackRate && value > 0) u->global_parameters[kVarispeedParam_PlaybackCents] = 1200 * log2f(value);
        else if (id == kVarispeedParam_PlaybackCents) u->global_parameters[kVarispeedParam_PlaybackRate] = powf(2, value / 1200);
    }
    pthread_mutex_unlock(&u->lock);
    if (!p) perry_audio_trace("%s: no parameter %u (scope %u, element %u)", u->component->name, id, scope, element);
    return p ? 0 : kAudioUnitErr_InvalidParameter;
}

OSStatus darwin_AudioUnitGetParameter(void *handle, uint32_t id, uint32_t scope, uint32_t element, float *value)
    DARWIN_SYMBOL(AudioUnitGetParameter);
OSStatus darwin_AudioUnitGetParameter(void *handle, uint32_t id, uint32_t scope, uint32_t element, float *value) {
    unit *u = valid(handle);
    if (!u || !value) return kAudio_ParamError;
    pthread_mutex_lock(&u->lock);
    float *p = parameter(u, id, scope, element);
    if (p) *value = *p;
    pthread_mutex_unlock(&u->lock);
    return p ? 0 : kAudioUnitErr_InvalidParameter;
}
