// GStreamer, loaded the first time audio needs it, and what the rest of the
// provider shares: looking up other libraries' symbols, CFURL paths and
// tracing.

#include "PerryAudioToolbox.h"
#include "perry_interface.h"

#include <dlfcn.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// MARK: - The loader's symbol lookup

static void *(*lookup_symbol)(const char *install_name, const char *name);

__attribute__((visibility("default")))
void perry_provider_startup(const perry_startup_info *info) {
    if (info->version >= 2) lookup_symbol = info->lookup_symbol;
}

void *perry_audio_lookup(const char *install_name, const char *name) {
    return lookup_symbol ? lookup_symbol(install_name, name) : NULL;
}

bool perry_audio_url_path(const void *url, char *buffer, size_t size) {
    typedef uint8_t (*get_path)(const void *url, uint8_t resolve, uint8_t *buffer, long size);
    static get_path function;
    if (!function) {
        function = (get_path)perry_audio_lookup("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation",
                                                "_CFURLGetFileSystemRepresentation");
    }
    return url && function && function(url, 1, (uint8_t *)buffer, (long)size);
}

void perry_audio_trace(const char *format, ...) {
    static int enabled = -1;
    if (enabled < 0) enabled = getenv("PERRY_TRACE_AUDIO") != NULL;
    if (!enabled) return;
    va_list arguments;
    va_start(arguments, format);
    fputs("perry: AudioToolbox: ", stderr);
    vfprintf(stderr, format, arguments);
    fputc('\n', stderr);
    va_end(arguments);
}

void perry_audio_warn(const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    fputs("perry: AudioToolbox: ", stderr);
    vfprintf(stderr, format, arguments);
    fputc('\n', stderr);
    va_end(arguments);
}

// MARK: - GStreamer

static perry_gst gst;
static bool gst_loaded;
static pthread_once_t gst_once = PTHREAD_ONCE_INIT;

static void load_gst(void) {
    void *core = dlopen("libgstreamer-1.0.so.0", RTLD_NOW | RTLD_GLOBAL);
    void *app = dlopen("libgstapp-1.0.so.0", RTLD_NOW | RTLD_GLOBAL);
    void *gobject = dlopen("libgobject-2.0.so.0", RTLD_NOW | RTLD_GLOBAL);
    if (!core || !app || !gobject) {
        perry_audio_warn("GStreamer is not installed; audio plays silently");
        return;
    }
    int (*init_check)(int *, char ***, void **) = (int (*)(int *, char ***, void **))dlsym(core, "gst_init_check");
#define BIND(field, library, name) if (!(*(void **)&gst.field = dlsym(library, name))) { \
        perry_audio_warn("GStreamer lacks %s; audio plays silently", name); return; }
    BIND(parse_launch, core, "gst_parse_launch");
    BIND(bin_get_by_name, core, "gst_bin_get_by_name");
    BIND(set_state, core, "gst_element_set_state");
    BIND(get_state, core, "gst_element_get_state");
    BIND(get_bus, core, "gst_element_get_bus");
    BIND(bus_pop_filtered, core, "gst_bus_pop_filtered");
    BIND(bus_timed_pop_filtered, core, "gst_bus_timed_pop_filtered");
    BIND(object_unref, core, "gst_object_unref");
    BIND(mini_object_unref, core, "gst_mini_object_unref");
    BIND(buffer_new_allocate, core, "gst_buffer_new_allocate");
    BIND(buffer_fill, core, "gst_buffer_fill");
    BIND(buffer_map, core, "gst_buffer_map");
    BIND(buffer_unmap, core, "gst_buffer_unmap");
    BIND(app_src_push_buffer, app, "gst_app_src_push_buffer");
    BIND(app_src_end_of_stream, app, "gst_app_src_end_of_stream");
    BIND(app_sink_try_pull_sample, app, "gst_app_sink_try_pull_sample");
    BIND(sample_get_buffer, core, "gst_sample_get_buffer");
    BIND(sample_get_caps, core, "gst_sample_get_caps");
    BIND(caps_get_structure, core, "gst_caps_get_structure");
    BIND(structure_get_int, core, "gst_structure_get_int");
    BIND(object_set, gobject, "g_object_set");
    BIND(message_parse_error, core, "gst_message_parse_error");
    BIND(element_send_event, core, "gst_element_send_event");
    BIND(event_new_flush_start, core, "gst_event_new_flush_start");
    BIND(event_new_flush_stop, core, "gst_event_new_flush_stop");
#undef BIND
    void *error = NULL;
    if (!init_check || !init_check(NULL, NULL, &error)) {
        perry_audio_warn("GStreamer didn't initialize; audio plays silently");
        return;
    }
    gst_loaded = true;
}

const perry_gst *perry_gst_get(void) {
    pthread_once(&gst_once, load_gst);
    return gst_loaded ? &gst : NULL;
}

void perry_gst_buffer_set_time(void *buffer, uint64_t pts, uint64_t duration) {
    uint64_t *fields = (uint64_t *)((uint8_t *)buffer + 72);
    fields[0] = pts;        // pts
    fields[1] = pts;        // dts
    fields[2] = duration;   // duration
}

bool perry_gst_check_error(const perry_gst *g, void *pipeline, const char *what) {
    void *bus = g->get_bus(pipeline);
    if (!bus) return false;
    void *message = g->bus_pop_filtered(bus, PERRY_GST_MESSAGE_ERROR);
    g->object_unref(bus);
    if (!message) return false;
    void *error = NULL;
    char *debug = NULL;
    g->message_parse_error(message, &error, &debug);
    // GError: domain (4 bytes), code (4), message.
    const char *text = error ? *(const char **)((uint8_t *)error + 8) : NULL;
    perry_audio_warn("%s: %s%s%s", what, text ? text : "GStreamer error", debug ? " — " : "", debug ? debug : "");
    g->mini_object_unref(message);
    return true;
}

static void hex(const void *data, uint32_t size, char *out) {
    static const char digits[] = "0123456789abcdef";
    const uint8_t *bytes = data;
    for (uint32_t i = 0; i < size; i++) {
        out[2 * i] = digits[bytes[i] >> 4];
        out[2 * i + 1] = digits[bytes[i] & 15];
    }
    out[2 * size] = 0;
}

/// An MPEG-4 descriptor's length, in up to four 7-bit bytes.
static uint32_t descriptor_length(const uint8_t **p, const uint8_t *end) {
    uint32_t length = 0;
    for (int i = 0; i < 4 && *p < end; i++) {
        uint8_t byte = *(*p)++;
        length = length << 7 | (byte & 0x7f);
        if (!(byte & 0x80)) break;
    }
    return length;
}

/// The AudioSpecificConfig in an AAC magic cookie: an esds atom, an
/// ES_Descriptor, or the config itself.
static bool aac_config(const uint8_t *cookie, uint32_t size, const uint8_t **config, uint32_t *config_size) {
    const uint8_t *end = cookie + size;
    for (const uint8_t *p = cookie; p + 2 < end; p++) {
        if (*p != 0x04) continue;   // DecoderConfigDescriptor
        const uint8_t *q = p + 1;
        uint32_t length = descriptor_length(&q, end);
        if (length < 13 || q + 13 > end) continue;
        const uint8_t *r = q + 13;
        if (r < end && *r == 0x05) {    // DecoderSpecificInfo
            r++;
            uint32_t info = descriptor_length(&r, end);
            if (r + info <= end && info > 0) {
                *config = r;
                *config_size = info;
                return true;
            }
        }
    }
    if (size >= 2 && size <= 8) {
        *config = cookie;
        *config_size = size;
        return true;
    }
    return false;
}

bool perry_gst_caps(const AudioStreamBasicDescription *f, const void *cookie, uint32_t cookie_size, char *caps, size_t size) {
    int rate = (int)f->mSampleRate, channels = (int)f->mChannelsPerFrame;
    switch (f->mFormatID) {
    case kAudioFormatMPEG4AAC: {
        const uint8_t *config = NULL;
        uint32_t config_size = 0;
        if (cookie && aac_config(cookie, cookie_size, &config, &config_size) && config_size <= 64) {
            char text[129];
            hex(config, config_size, text);
            snprintf(caps, size, "audio/mpeg,mpegversion=(int)4,stream-format=(string)raw,codec_data=(buffer)%s,"
                     "rate=(int)%d,channels=(int)%d", text, rate, channels);
        } else {
            // No cookie: the AAC-LC config for the rate and channels.
            static const int rates[] = { 96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000 };
            int index = 4;
            for (int i = 0; i < 12; i++) if (rates[i] == rate) index = i;
            uint8_t lc[2] = { (uint8_t)(2 << 3 | index >> 1), (uint8_t)((index & 1) << 7 | (channels & 15) << 3) };
            char text[5];
            hex(lc, 2, text);
            snprintf(caps, size, "audio/mpeg,mpegversion=(int)4,stream-format=(string)raw,codec_data=(buffer)%s,"
                     "rate=(int)%d,channels=(int)%d", text, rate, channels);
        }
        return true;
    }
    case kAudioFormatMPEGLayer3:
        snprintf(caps, size, "audio/mpeg,mpegversion=(int)1,layer=(int)3,parsed=(boolean)true,rate=(int)%d,channels=(int)%d",
                 rate, channels);
        return true;
    default:
        return false;
    }
}

bool perry_gst_decode(const void *data, size_t size, int16_t **samples, size_t *frames, uint32_t *rate, uint32_t *channels) {
    const perry_gst *g = perry_gst_get();
    if (!g) return false;
    void *pipeline = g->parse_launch("appsrc name=src format=bytes ! decodebin ! audioconvert ! "
                                     "audio/x-raw,format=S16LE,layout=interleaved ! appsink name=sink sync=false", NULL);
    if (!pipeline) return false;
    void *src = g->bin_get_by_name(pipeline, "src");
    void *sink = g->bin_get_by_name(pipeline, "sink");
    bool ok = false;
    size_t count = 0, capacity = 0;
    int16_t *out = NULL;
    int found_rate = 0, found_channels = 0;
    if (src && sink && g->set_state(pipeline, PERRY_GST_STATE_PLAYING) != 0) {
        void *buffer = g->buffer_new_allocate(NULL, size, NULL);
        g->buffer_fill(buffer, 0, data, size);
        g->app_src_push_buffer(src, buffer);
        g->app_src_end_of_stream(src);
        void *sample;
        while ((sample = g->app_sink_try_pull_sample(sink, 10 * PERRY_GST_SECOND))) {
            void *caps = g->sample_get_caps(sample);
            void *structure = caps ? g->caps_get_structure(caps, 0) : NULL;
            if (structure && !found_rate) {
                g->structure_get_int(structure, "rate", &found_rate);
                g->structure_get_int(structure, "channels", &found_channels);
            }
            void *buffer = g->sample_get_buffer(sample);
            uint8_t info[PERRY_GST_MAP_INFO_SIZE];
            if (buffer && found_channels > 0 && g->buffer_map(buffer, info, PERRY_GST_MAP_READ)) {
                const void *bytes = *(void **)(info + PERRY_GST_MAP_INFO_DATA);
                size_t length = *(size_t *)(info + PERRY_GST_MAP_INFO_LENGTH);
                size_t values = length / 2;
                if (count + values > capacity) {
                    capacity = (count + values) * 2;
                    out = realloc(out, capacity * sizeof *out);
                }
                memcpy(out + count, bytes, values * 2);
                count += values;
                g->buffer_unmap(buffer, info);
            }
            g->mini_object_unref(sample);
        }
        ok = !perry_gst_check_error(g, pipeline, "decoding a file") && found_rate > 0 && found_channels > 0 && count > 0;
    }
    g->set_state(pipeline, PERRY_GST_STATE_NULL);
    if (src) g->object_unref(src);
    if (sink) g->object_unref(sink);
    g->object_unref(pipeline);
    if (!ok) {
        free(out);
        return false;
    }
    *samples = out;
    *frames = count / (size_t)found_channels;
    *rate = (uint32_t)found_rate;
    *channels = (uint32_t)found_channels;
    return true;
}
