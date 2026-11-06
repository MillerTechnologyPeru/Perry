// Audio queues for output. Each queue has a thread that hands its enqueued
// buffers, in order, to a GStreamer pipeline: linear PCM and IMA4 as floats,
// AAC and MP3 packets as they are, for GStreamer to decode. A buffer goes
// back to the app's callback once its audio is in the pipeline, whose
// limited room paces the queue. Callbacks and property listeners are called
// on the queue's thread, whatever run loop the app names; that run loop
// holds an input source while the queue lives, so that an app running it
// for the queue waits there, as on Darwin, rather than spinning on a run
// loop with nothing in it. Without GStreamer
// a queue plays silently, taking each buffer as long as it would sound.

#include "PerryAudioToolbox.h"

#include <math.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/// Darwin's AudioQueueBuffer.
typedef struct AudioQueueBuffer {
    const uint32_t mAudioDataBytesCapacity;
    void *const mAudioData;
    uint32_t mAudioDataByteSize;
    void *mUserData;
    const uint32_t mPacketDescriptionCapacity;
    AudioStreamPacketDescription *const mPacketDescriptions;
    uint32_t mPacketDescriptionCount;
} AudioQueueBuffer;

typedef void (*output_callback)(void *user, void *queue, AudioQueueBuffer *buffer);
typedef void (*property_listener)(void *user, void *queue, uint32_t property);

#define kAudioQueueProperty_IsRunning FOURCC('a', 'q', 'r', 'n')
#define kAudioQueueProperty_MagicCookie FOURCC('a', 'q', 'm', 'c')
#define kAudioQueueProperty_StreamDescription FOURCC('a', 'q', 'f', 't')
#define kAudioQueueProperty_MaximumOutputPacketSize FOURCC('x', 'o', 'p', 's')
#define kAudioQueueParam_Volume 1
#define kAudioQueueErr_BufferEmpty (-66686)
#define kAudioQueueErr_DisposalPending (-66678)

typedef struct pending_buffer {
    AudioQueueBuffer *buffer;
    uint32_t descriptions;
    AudioStreamPacketDescription *copy;     // the descriptions passed to enqueue, if any
} pending_buffer;

typedef struct listener {
    uint32_t property;
    property_listener proc;
    void *user;
} listener;

typedef struct queue {
    uint32_t magic;
    AudioStreamBasicDescription format;
    output_callback callback;
    void *user;
    uint8_t *cookie;
    uint32_t cookie_size;
    double volume;

    pthread_t thread;
    void *run_loop;
    pthread_mutex_t lock;
    pthread_cond_t changed;
    pending_buffer *pending;
    size_t count, capacity;
    listener listeners[8];
    size_t listener_count;

    bool running, paused, stopping, quit, notify_running;
    /// Frames pushed since started, for timestamps.
    uint64_t frames;

    void *pipeline, *src, *volume_element;
    bool silent;
} queue;

#define QUEUE_MAGIC FOURCC('p', 'a', 'q', 'u')

static queue *valid(void *handle) {
    queue *q = handle;
    return q && q->magic == QUEUE_MAGIC ? q : NULL;
}

static void notify(queue *q, uint32_t property) {
    pthread_mutex_lock(&q->lock);
    listener copies[8];
    size_t count = q->listener_count;
    memcpy(copies, q->listeners, count * sizeof *copies);
    pthread_mutex_unlock(&q->lock);
    for (size_t i = 0; i < count; i++) {
        if (copies[i].property == property) copies[i].proc(copies[i].user, q, property);
    }
}

// MARK: - The pipeline

static bool has_element(const char *name) {
    const perry_gst *g = perry_gst_get();
    void *factory = g && g->factory_find ? g->factory_find(name) : NULL;
    if (factory) g->object_unref(factory);
    return factory != NULL;
}

/// The decoder for compressed packets: one whose pads are always there,
/// so the pipeline stays linked when a stop takes it back to its start
/// (decodebin's pads come and go, and parse_launch links them once), or
/// decodebin for formats without one.
static const char *decoder(uint32_t format) {
    if (format == kAudioFormatMPEG4AAC && has_element("avdec_aac")) return "avdec_aac !";
    if (format == kAudioFormatMPEGLayer3 && has_element("mpegaudioparse") && has_element("mpg123audiodec"))
        return "mpegaudioparse ! mpg123audiodec !";
    return "decodebin !";
}

/// Builds the pipeline for the queue's format; false (and silent) if it
/// can't be.
static bool build(queue *q) {
    if (q->pipeline) return true;
    const perry_gst *g = perry_gst_get();
    if (!g) { q->silent = true; return false; }
    const AudioStreamBasicDescription *f = &q->format;
    char caps[512], description[1024];
    bool decoded = f->mFormatID == kAudioFormatLinearPCM || f->mFormatID == kAudioFormatAppleIMA4;
    size_t room;
    if (decoded) {
        snprintf(caps, sizeof caps, "audio/x-raw,format=F32LE,layout=interleaved,rate=(int)%d,channels=(int)%u",
                 (int)f->mSampleRate, f->mChannelsPerFrame);
        room = (size_t)(f->mSampleRate * f->mChannelsPerFrame * 4 / 4);     // a quarter of a second
    } else if (perry_gst_caps(f, q->cookie, q->cookie_size, caps, sizeof caps)) {
        room = 16384;
    } else {
        perry_audio_warn("audio queue: can't play '%c%c%c%c'; playing silently", f->mFormatID >> 24, f->mFormatID >> 16 & 0xff,
                         f->mFormatID >> 8 & 0xff, f->mFormatID & 0xff);
        q->silent = true;
        return false;
    }
    snprintf(description, sizeof description,
             "appsrc name=src format=time block=true max-bytes=%zu caps=\"%s\" ! %s audioconvert ! audioresample ! "
             "volume name=volume ! autoaudiosink", room, caps, decoded ? "" : decoder(f->mFormatID));
    perry_audio_trace("audio queue %p: %s", (void *)q, description);
    q->pipeline = g->parse_launch(description, NULL);
    if (q->pipeline) {
        q->src = g->bin_get_by_name(q->pipeline, "src");
        q->volume_element = g->bin_get_by_name(q->pipeline, "volume");
    }
    if (!q->pipeline || !q->src) {
        perry_audio_warn("audio queue: GStreamer can't build its pipeline; playing silently");
        q->silent = true;
        return false;
    }
    g->object_set(q->volume_element, "volume", q->volume, NULL);
    return true;
}

static uint64_t nanoseconds(uint64_t frames, double rate) {
    return rate > 0 ? (uint64_t)((double)frames * 1e9 / rate) : 0;
}

/// Pushes interleaved floats.
static void push_floats(queue *q, const perry_gst *g, const float *samples, size_t frames) {
    size_t bytes = frames * q->format.mChannelsPerFrame * sizeof(float);
    void *buffer = g->buffer_new_allocate(NULL, bytes, NULL);
    if (!buffer) return;
    g->buffer_fill(buffer, 0, samples, bytes);
    uint64_t start = nanoseconds(q->frames, q->format.mSampleRate);
    q->frames += frames;
    perry_gst_buffer_set_time(buffer, start, nanoseconds(q->frames, q->format.mSampleRate) - start);
    g->app_src_push_buffer(q->src, buffer);
}

/// Hands a buffer's audio to the pipeline, or waits as long as it would
/// sound when silent.
static void play(queue *q, pending_buffer *p) {
    const AudioStreamBasicDescription *f = &q->format;
    AudioQueueBuffer *b = p->buffer;
    uint32_t count = p->copy ? p->descriptions : b->mPacketDescriptionCount;
    const AudioStreamPacketDescription *descriptions = p->copy ? p->copy : b->mPacketDescriptions;
    const perry_gst *g = (!q->silent && build(q)) ? perry_gst_get() : NULL;

    if (f->mFormatID == kAudioFormatLinearPCM && perry_pcm_supported(f)) {
        size_t frames = b->mAudioDataByteSize / f->mBytesPerFrame;
        if (g) {
            uint32_t channels = f->mChannelsPerFrame;
            float *samples = malloc((frames ? frames : 1) * channels * sizeof(float));
            AudioBufferList *list = calloc(1, sizeof(AudioBufferList) + channels * sizeof(AudioBuffer));
            if (samples && list) {
                bool split = f->mFormatFlags & kAudioFormatFlagIsNonInterleaved;
                list->mNumberBuffers = split ? channels : 1;
                for (uint32_t c = 0; c < list->mNumberBuffers; c++) {
                    // A non-interleaved queue buffer holds its channels one after another.
                    list->mBuffers[c] = (AudioBuffer){ split ? 1 : channels, (uint32_t)(frames * f->mBytesPerFrame),
                                                       (uint8_t *)b->mAudioData + (split ? c * frames * f->mBytesPerFrame : 0) };
                }
                perry_pcm_read(f, list, 0, frames, samples);
                push_floats(q, g, samples, frames);
            }
            free(samples);
            free(list);
        } else {
            q->frames += frames;
            struct timespec wait = { 0, (long)nanoseconds(frames, f->mSampleRate) };
            while (wait.tv_nsec >= 1000000000) { wait.tv_sec++; wait.tv_nsec -= 1000000000; }
            nanosleep(&wait, NULL);
        }
        return;
    }
    if (f->mFormatID == kAudioFormatAppleIMA4) {
        uint32_t size = f->mBytesPerPacket ? f->mBytesPerPacket : 34 * f->mChannelsPerFrame;
        uint32_t packets = b->mAudioDataByteSize / size, channels = f->mChannelsPerFrame > 8 ? 8 : f->mChannelsPerFrame;
        float *samples = malloc((size_t)(packets ? packets : 1) * 64 * channels * sizeof(float));
        if (!samples) return;
        for (uint32_t i = 0; i < packets; i++) perry_ima4_decode((uint8_t *)b->mAudioData + i * size, channels, samples + i * 64 * channels);
        if (g) push_floats(q, g, samples, (size_t)packets * 64);
        else q->frames += (uint64_t)packets * 64;
        free(samples);
        return;
    }
    // Compressed packets, one GStreamer buffer each.
    uint32_t frames_per_packet = f->mFramesPerPacket ? f->mFramesPerPacket : 1024;
    if (!count && f->mBytesPerPacket) count = b->mAudioDataByteSize / f->mBytesPerPacket;
    for (uint32_t i = 0; i < count; i++) {
        uint64_t offset = descriptions ? (uint64_t)descriptions[i].mStartOffset : (uint64_t)i * f->mBytesPerPacket;
        uint32_t size = descriptions ? descriptions[i].mDataByteSize : f->mBytesPerPacket;
        uint32_t frames = (descriptions && descriptions[i].mVariableFramesInPacket) ? descriptions[i].mVariableFramesInPacket : frames_per_packet;
        if (offset + size > b->mAudioDataByteSize) break;
        uint64_t start = nanoseconds(q->frames, f->mSampleRate);
        q->frames += frames;
        if (!g) continue;
        void *buffer = g->buffer_new_allocate(NULL, size, NULL);
        if (!buffer) continue;
        g->buffer_fill(buffer, 0, (uint8_t *)b->mAudioData + offset, size);
        perry_gst_buffer_set_time(buffer, start, nanoseconds(q->frames, f->mSampleRate) - start);
        g->app_src_push_buffer(q->src, buffer);
    }
    if (!g && count) {
        struct timespec wait = { 0, (long)nanoseconds((uint64_t)count * frames_per_packet, f->mSampleRate) };
        while (wait.tv_nsec >= 1000000000) { wait.tv_sec++; wait.tv_nsec -= 1000000000; }
        nanosleep(&wait, NULL);
    }
}

/// After a stop that lets queued audio finish: the end of the stream, and
/// waiting for the pipeline to play it (or an immediate stop).
static void play_out(queue *q) {
    const perry_gst *g = perry_gst_get();
    if (!g || !q->pipeline || q->silent) return;
    g->app_src_end_of_stream(q->src);
    void *bus = g->get_bus(q->pipeline);
    for (int i = 0; bus && i < 100; i++) {
        void *message = g->bus_timed_pop_filtered(bus, PERRY_GST_SECOND / 10, PERRY_GST_MESSAGE_EOS | PERRY_GST_MESSAGE_ERROR);
        if (message) { g->mini_object_unref(message); break; }
        pthread_mutex_lock(&q->lock);
        bool stop = q->quit || !q->stopping;
        pthread_mutex_unlock(&q->lock);
        if (stop) break;
    }
    if (bus) g->object_unref(bus);
}

/// Back to the start: nothing in the pipeline, ready to play again.
static void reset_pipeline(queue *q) {
    const perry_gst *g = perry_gst_get();
    if (g && q->pipeline) g->set_state(q->pipeline, PERRY_GST_STATE_NULL);
    q->frames = 0;
}

static void *run(void *argument) {
    queue *q = argument;
    pthread_mutex_lock(&q->lock);
    while (!q->quit) {
        if (q->notify_running) {
            q->notify_running = false;
            pthread_mutex_unlock(&q->lock);
            notify(q, kAudioQueueProperty_IsRunning);
            pthread_mutex_lock(&q->lock);
            continue;
        }
        if (q->running && q->stopping && q->count == 0) {
            // Stopping once what was queued has played.
            pthread_mutex_unlock(&q->lock);
            play_out(q);
            reset_pipeline(q);
            pthread_mutex_lock(&q->lock);
            if (q->stopping) {
                q->running = false;
                q->stopping = false;
                q->notify_running = true;
            }
            continue;
        }
        if (!q->running || q->paused || q->count == 0) {
            pthread_cond_wait(&q->changed, &q->lock);
            continue;
        }
        pending_buffer next = q->pending[0];
        memmove(q->pending, q->pending + 1, (q->count - 1) * sizeof *q->pending);
        q->count--;
        pthread_mutex_unlock(&q->lock);
        play(q, &next);
        free(next.copy);
        if (q->callback) q->callback(q->user, q, next.buffer);
        pthread_mutex_lock(&q->lock);
    }
    pthread_mutex_unlock(&q->lock);
    return NULL;
}

// MARK: - Creating and disposing

/// An input source on the run loop the app named, or off it; none for NULL,
/// which on Darwin means the queue's own thread.
static void attach_run_loop(queue *q, void *run_loop, bool attach) {
    static const char *foundation = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation";
    typedef void (*source_change)(void *);
    static source_change add, remove;
    if (!add) {
        add = (source_change)perry_audio_lookup(foundation, "_perry_CFRunLoopAddInputSource");
        remove = (source_change)perry_audio_lookup(foundation, "_perry_CFRunLoopRemoveInputSource");
    }
    if (!run_loop || !add || !remove) return;
    (attach ? add : remove)(run_loop);
}

OSStatus darwin_AudioQueueNewOutput(const AudioStreamBasicDescription *format, output_callback callback, void *user,
                                    void *run_loop, const void *mode, uint32_t flags, void **out) DARWIN_SYMBOL(AudioQueueNewOutput);
OSStatus darwin_AudioQueueNewOutput(const AudioStreamBasicDescription *format, output_callback callback, void *user,
                                    void *run_loop, const void *mode, uint32_t flags, void **out) {
    if (!format || !out || format->mSampleRate <= 0 || !format->mChannelsPerFrame) return kAudio_ParamError;
    *out = NULL;
    queue *q = calloc(1, sizeof *q);
    if (!q) return kAudio_MemFullError;
    q->magic = QUEUE_MAGIC;
    q->format = *format;
    q->callback = callback;
    q->user = user;
    q->volume = 1.0;
    pthread_mutex_init(&q->lock, NULL);
    pthread_cond_init(&q->changed, NULL);
    if (pthread_create(&q->thread, NULL, run, q)) {
        free(q);
        return kAudio_MemFullError;
    }
    q->run_loop = run_loop;
    attach_run_loop(q, run_loop, true);
    perry_audio_trace("audio queue %p: '%c%c%c%c' %u Hz, %u channels", (void *)q, format->mFormatID >> 24,
                      format->mFormatID >> 16 & 0xff, format->mFormatID >> 8 & 0xff, format->mFormatID & 0xff,
                      (unsigned)format->mSampleRate, format->mChannelsPerFrame);
    *out = q;
    return 0;
}

OSStatus darwin_AudioQueueDispose(void *handle, uint8_t immediate) DARWIN_SYMBOL(AudioQueueDispose);
OSStatus darwin_AudioQueueDispose(void *handle, uint8_t immediate) {
    queue *q = valid(handle);
    if (!q) return kAudio_ParamError;
    pthread_mutex_lock(&q->lock);
    q->quit = true;
    q->stopping = false;
    pthread_cond_broadcast(&q->changed);
    pthread_mutex_unlock(&q->lock);
    attach_run_loop(q, q->run_loop, false);
    q->run_loop = NULL;
    // A thread blocked pushing into a full pipeline is freed by stopping it.
    reset_pipeline(q);
    if (!pthread_equal(pthread_self(), q->thread)) pthread_join(q->thread, NULL);
    else pthread_detach(q->thread);
    const perry_gst *g = perry_gst_get();
    if (g && q->pipeline) {
        if (q->src) g->object_unref(q->src);
        if (q->volume_element) g->object_unref(q->volume_element);
        g->object_unref(q->pipeline);
    }
    for (size_t i = 0; i < q->count; i++) free(q->pending[i].copy);
    free(q->pending);
    free(q->cookie);
    q->magic = 0;
    // Its buffers are the app's to free, with AudioQueueFreeBuffer, before
    // this; any left are leaked rather than freed under it.
    free(q);
    return 0;
}

// MARK: - Buffers

OSStatus darwin_AudioQueueAllocateBufferWithPacketDescriptions(void *handle, uint32_t capacity, uint32_t descriptions,
                                                               AudioQueueBuffer **out)
    DARWIN_SYMBOL(AudioQueueAllocateBufferWithPacketDescriptions);
OSStatus darwin_AudioQueueAllocateBufferWithPacketDescriptions(void *handle, uint32_t capacity, uint32_t descriptions,
                                                               AudioQueueBuffer **out) {
    if (!valid(handle) || !out) return kAudio_ParamError;
    size_t header = (sizeof(AudioQueueBuffer) + 15) & ~(size_t)15;
    size_t table = (size_t)descriptions * sizeof(AudioStreamPacketDescription);
    uint8_t *memory = calloc(1, header + table + capacity);
    if (!memory) return kAudio_MemFullError;
    AudioQueueBuffer initial = {
        capacity, memory + header + table, 0, NULL, descriptions,
        descriptions ? (AudioStreamPacketDescription *)(memory + header) : NULL, 0,
    };
    memcpy(memory, &initial, sizeof initial);
    *out = (AudioQueueBuffer *)memory;
    return 0;
}

OSStatus darwin_AudioQueueAllocateBuffer(void *handle, uint32_t capacity, AudioQueueBuffer **out) DARWIN_SYMBOL(AudioQueueAllocateBuffer);
OSStatus darwin_AudioQueueAllocateBuffer(void *handle, uint32_t capacity, AudioQueueBuffer **out) {
    return darwin_AudioQueueAllocateBufferWithPacketDescriptions(handle, capacity, 0, out);
}

OSStatus darwin_AudioQueueFreeBuffer(void *handle, AudioQueueBuffer *buffer) DARWIN_SYMBOL(AudioQueueFreeBuffer);
OSStatus darwin_AudioQueueFreeBuffer(void *handle, AudioQueueBuffer *buffer) {
    queue *q = valid(handle);
    if (!q || !buffer) return kAudio_ParamError;
    pthread_mutex_lock(&q->lock);
    for (size_t i = 0; i < q->count; i++) {
        if (q->pending[i].buffer == buffer) {
            free(q->pending[i].copy);
            memmove(q->pending + i, q->pending + i + 1, (q->count - i - 1) * sizeof *q->pending);
            q->count--;
            break;
        }
    }
    pthread_mutex_unlock(&q->lock);
    free(buffer);
    return 0;
}

OSStatus darwin_AudioQueueEnqueueBuffer(void *handle, AudioQueueBuffer *buffer, uint32_t count,
                                        const AudioStreamPacketDescription *descriptions) DARWIN_SYMBOL(AudioQueueEnqueueBuffer);
OSStatus darwin_AudioQueueEnqueueBuffer(void *handle, AudioQueueBuffer *buffer, uint32_t count,
                                        const AudioStreamPacketDescription *descriptions) {
    queue *q = valid(handle);
    if (!q || !buffer) return kAudioQueueErr_InvalidBuffer;
    if (!buffer->mAudioDataByteSize) return kAudioQueueErr_BufferEmpty;
    pending_buffer p = { buffer, 0, NULL };
    if (descriptions && count) {
        p.copy = malloc(count * sizeof *descriptions);
        if (!p.copy) return kAudio_MemFullError;
        memcpy(p.copy, descriptions, count * sizeof *descriptions);
        p.descriptions = count;
    }
    pthread_mutex_lock(&q->lock);
    if (q->count == q->capacity) {
        size_t capacity = q->capacity ? q->capacity * 2 : 8;
        pending_buffer *grown = realloc(q->pending, capacity * sizeof *grown);
        if (!grown) { pthread_mutex_unlock(&q->lock); free(p.copy); return kAudio_MemFullError; }
        q->pending = grown;
        q->capacity = capacity;
    }
    q->pending[q->count++] = p;
    pthread_cond_broadcast(&q->changed);
    pthread_mutex_unlock(&q->lock);
    return 0;
}

/// Trimming, scheduled start times and per-buffer parameters are ignored.
OSStatus darwin_AudioQueueEnqueueBufferWithParameters(void *handle, AudioQueueBuffer *buffer, uint32_t count,
                                                      const AudioStreamPacketDescription *descriptions, uint32_t trim_start,
                                                      uint32_t trim_end, uint32_t parameters, const void *values,
                                                      const AudioTimeStamp *start, AudioTimeStamp *actual)
    DARWIN_SYMBOL(AudioQueueEnqueueBufferWithParameters);
OSStatus darwin_AudioQueueEnqueueBufferWithParameters(void *handle, AudioQueueBuffer *buffer, uint32_t count,
                                                      const AudioStreamPacketDescription *descriptions, uint32_t trim_start,
                                                      uint32_t trim_end, uint32_t parameters, const void *values,
                                                      const AudioTimeStamp *start, AudioTimeStamp *actual) {
    if (actual) memset(actual, 0, sizeof *actual);
    return darwin_AudioQueueEnqueueBuffer(handle, buffer, count, descriptions);
}

// MARK: - Playing

OSStatus darwin_AudioQueueStart(void *handle, const AudioTimeStamp *start) DARWIN_SYMBOL(AudioQueueStart);
OSStatus darwin_AudioQueueStart(void *handle, const AudioTimeStamp *start) {
    queue *q = valid(handle);
    if (!q) return kAudio_ParamError;
    if (build(q)) perry_gst_get()->set_state(q->pipeline, PERRY_GST_STATE_PLAYING);
    pthread_mutex_lock(&q->lock);
    bool was_running = q->running;
    q->running = true;
    q->paused = false;
    q->stopping = false;
    if (!was_running) q->notify_running = true;
    pthread_cond_broadcast(&q->changed);
    pthread_mutex_unlock(&q->lock);
    return 0;
}

OSStatus darwin_AudioQueuePrime(void *handle, uint32_t frames, uint32_t *prepared) DARWIN_SYMBOL(AudioQueuePrime);
OSStatus darwin_AudioQueuePrime(void *handle, uint32_t frames, uint32_t *prepared) {
    if (!valid(handle)) return kAudio_ParamError;
    if (prepared) *prepared = 0;
    return 0;
}

OSStatus darwin_AudioQueuePause(void *handle) DARWIN_SYMBOL(AudioQueuePause);
OSStatus darwin_AudioQueuePause(void *handle) {
    queue *q = valid(handle);
    if (!q) return kAudio_ParamError;
    pthread_mutex_lock(&q->lock);
    q->paused = true;
    pthread_mutex_unlock(&q->lock);
    const perry_gst *g = perry_gst_get();
    if (g && q->pipeline) g->set_state(q->pipeline, PERRY_GST_STATE_PAUSED);
    return 0;
}

/// Everything enqueued is played; nothing to do, as each buffer is.
OSStatus darwin_AudioQueueFlush(void *handle) DARWIN_SYMBOL(AudioQueueFlush);
OSStatus darwin_AudioQueueFlush(void *handle) { return valid(handle) ? 0 : kAudio_ParamError; }

/// Stopping at once drops what is enqueued; otherwise the queue stops when
/// it has played it.
OSStatus darwin_AudioQueueStop(void *handle, uint8_t immediate) DARWIN_SYMBOL(AudioQueueStop);
OSStatus darwin_AudioQueueStop(void *handle, uint8_t immediate) {
    queue *q = valid(handle);
    if (!q) return kAudio_ParamError;
    pthread_mutex_lock(&q->lock);
    if (!q->running) {
        pthread_mutex_unlock(&q->lock);
        return 0;
    }
    if (!immediate) {
        q->stopping = true;
        q->paused = false;
        pthread_cond_broadcast(&q->changed);
        pthread_mutex_unlock(&q->lock);
        return 0;
    }
    for (size_t i = 0; i < q->count; i++) free(q->pending[i].copy);
    q->count = 0;
    q->running = false;
    q->stopping = false;
    q->paused = false;
    q->notify_running = true;
    pthread_cond_broadcast(&q->changed);
    pthread_mutex_unlock(&q->lock);
    reset_pipeline(q);
    return 0;
}

OSStatus darwin_AudioQueueReset(void *handle) DARWIN_SYMBOL(AudioQueueReset);
OSStatus darwin_AudioQueueReset(void *handle) {
    queue *q = valid(handle);
    if (!q) return kAudio_ParamError;
    pthread_mutex_lock(&q->lock);
    for (size_t i = 0; i < q->count; i++) free(q->pending[i].copy);
    q->count = 0;
    pthread_mutex_unlock(&q->lock);
    return 0;
}

OSStatus darwin_AudioQueueGetCurrentTime(void *handle, void *timeline, AudioTimeStamp *time, uint8_t *discontinuity)
    DARWIN_SYMBOL(AudioQueueGetCurrentTime);
OSStatus darwin_AudioQueueGetCurrentTime(void *handle, void *timeline, AudioTimeStamp *time, uint8_t *discontinuity) {
    queue *q = valid(handle);
    if (!q) return kAudio_ParamError;
    if (time) {
        memset(time, 0, sizeof *time);
        time->mSampleTime = (double)q->frames;
        time->mFlags = kAudioTimeStampSampleTimeValid;
    }
    if (discontinuity) *discontinuity = 0;
    return 0;
}

// MARK: - Properties and parameters

OSStatus darwin_AudioQueueGetProperty(void *handle, uint32_t id, void *value, uint32_t *size) DARWIN_SYMBOL(AudioQueueGetProperty);
OSStatus darwin_AudioQueueGetProperty(void *handle, uint32_t id, void *value, uint32_t *size) {
    queue *q = valid(handle);
    if (!q || !value || !size) return kAudio_ParamError;
    switch (id) {
    case kAudioQueueProperty_IsRunning: {
        if (*size < 4) return kAudio_ParamError;
        pthread_mutex_lock(&q->lock);
        uint32_t running = q->running;
        pthread_mutex_unlock(&q->lock);
        memcpy(value, &running, 4);
        *size = 4;
        return 0;
    }
    case kAudioQueueProperty_StreamDescription:
        if (*size < sizeof q->format) return kAudio_ParamError;
        memcpy(value, &q->format, sizeof q->format);
        *size = sizeof q->format;
        return 0;
    case kAudioQueueProperty_MagicCookie:
        if (!q->cookie) return kAudioQueueErr_InvalidProperty;
        if (*size > q->cookie_size) *size = q->cookie_size;
        memcpy(value, q->cookie, *size);
        return 0;
    default:
        return kAudioQueueErr_InvalidProperty;
    }
}

OSStatus darwin_AudioQueueGetPropertySize(void *handle, uint32_t id, uint32_t *size) DARWIN_SYMBOL(AudioQueueGetPropertySize);
OSStatus darwin_AudioQueueGetPropertySize(void *handle, uint32_t id, uint32_t *size) {
    queue *q = valid(handle);
    if (!q || !size) return kAudio_ParamError;
    switch (id) {
    case kAudioQueueProperty_IsRunning: *size = 4; return 0;
    case kAudioQueueProperty_StreamDescription: *size = sizeof q->format; return 0;
    case kAudioQueueProperty_MagicCookie: *size = q->cookie_size; return 0;
    default: return kAudioQueueErr_InvalidProperty;
    }
}

OSStatus darwin_AudioQueueSetProperty(void *handle, uint32_t id, const void *value, uint32_t size) DARWIN_SYMBOL(AudioQueueSetProperty);
OSStatus darwin_AudioQueueSetProperty(void *handle, uint32_t id, const void *value, uint32_t size) {
    queue *q = valid(handle);
    if (!q) return kAudio_ParamError;
    if (id == kAudioQueueProperty_MagicCookie) {
        if (q->pipeline) return 0;      // too late to change the decoder
        free(q->cookie);
        q->cookie = malloc(size ? size : 1);
        if (!q->cookie) return kAudio_MemFullError;
        memcpy(q->cookie, value, size);
        q->cookie_size = size;
        return 0;
    }
    // Channel layouts, metering, decode sizes, time pitch: accepted.
    return 0;
}

OSStatus darwin_AudioQueueAddPropertyListener(void *handle, uint32_t id, property_listener proc, void *user)
    DARWIN_SYMBOL(AudioQueueAddPropertyListener);
OSStatus darwin_AudioQueueAddPropertyListener(void *handle, uint32_t id, property_listener proc, void *user) {
    queue *q = valid(handle);
    if (!q || !proc) return kAudio_ParamError;
    pthread_mutex_lock(&q->lock);
    OSStatus status = 0;
    if (q->listener_count < 8) q->listeners[q->listener_count++] = (listener){ id, proc, user };
    else status = kAudio_MemFullError;
    pthread_mutex_unlock(&q->lock);
    return status;
}

OSStatus darwin_AudioQueueRemovePropertyListener(void *handle, uint32_t id, property_listener proc, void *user)
    DARWIN_SYMBOL(AudioQueueRemovePropertyListener);
OSStatus darwin_AudioQueueRemovePropertyListener(void *handle, uint32_t id, property_listener proc, void *user) {
    queue *q = valid(handle);
    if (!q) return kAudio_ParamError;
    pthread_mutex_lock(&q->lock);
    for (size_t i = 0; i < q->listener_count; i++) {
        if (q->listeners[i].property == id && q->listeners[i].proc == proc && q->listeners[i].user == user) {
            memmove(q->listeners + i, q->listeners + i + 1, (q->listener_count - i - 1) * sizeof *q->listeners);
            q->listener_count--;
            break;
        }
    }
    pthread_mutex_unlock(&q->lock);
    return 0;
}

DARWIN_FLOAT_ABI OSStatus darwin_AudioQueueSetParameter(void *handle, uint32_t id, float value) DARWIN_SYMBOL(AudioQueueSetParameter);
DARWIN_FLOAT_ABI OSStatus darwin_AudioQueueSetParameter(void *handle, uint32_t id, float value) {
    queue *q = valid(handle);
    if (!q) return kAudio_ParamError;
    if (id == kAudioQueueParam_Volume) {
        q->volume = value < 0 ? 0 : value > 1 ? 1 : value;
        const perry_gst *g = perry_gst_get();
        if (g && q->volume_element) g->object_set(q->volume_element, "volume", q->volume, NULL);
    }
    return 0;
}

OSStatus darwin_AudioQueueGetParameter(void *handle, uint32_t id, float *value) DARWIN_SYMBOL(AudioQueueGetParameter);
OSStatus darwin_AudioQueueGetParameter(void *handle, uint32_t id, float *value) {
    queue *q = valid(handle);
    if (!q || !value) return kAudio_ParamError;
    *value = id == kAudioQueueParam_Volume ? (float)q->volume : 0;
    return 0;
}

// Offline rendering, a queue rendering into the caller's buffers instead of
// playing: queues here play through GStreamer only, so it is refused
// (kAudioQueueErr_InvalidOfflineMode), as for a queue that can't.
OSStatus darwin_AudioQueueSetOfflineRenderFormat(void *queue, const void *format, const void *layout)
    DARWIN_SYMBOL(AudioQueueSetOfflineRenderFormat);
OSStatus darwin_AudioQueueSetOfflineRenderFormat(void *queue, const void *format, const void *layout) {
    (void)queue, (void)format, (void)layout;
    return -66626;
}

OSStatus darwin_AudioQueueOfflineRender(void *queue, const void *time, void *buffer, uint32_t frames)
    DARWIN_SYMBOL(AudioQueueOfflineRender);
OSStatus darwin_AudioQueueOfflineRender(void *queue, const void *time, void *buffer, uint32_t frames) {
    (void)queue, (void)time, (void)buffer, (void)frames;
    return -66626;
}
