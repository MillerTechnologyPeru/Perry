// CoreAudio's audio objects, as macOS programs find their output device:
// the system object (1) has one device (2), a stereo output at 48 kHz
// that the default and HAL output units play to through GStreamer. Its
// properties answer what device pickers and Wwise ask; listeners are
// kept but never called, as nothing about the device changes.

#include "PerryAudioToolbox.h"

#include <string.h>

typedef uint32_t AudioObjectID;

typedef struct {
    uint32_t selector, scope, element;
} AudioObjectPropertyAddress;

typedef struct {
    double minimum, maximum;
} AudioValueRange;

enum { SYSTEM = 1, DEVICE = 2, STREAM = 3, RATE = 48000, CHANNELS = 2, FRAMES = 512 };

#define kAudioHardwareUnknownPropertyError FOURCC('w', 'h', 'o', '?')
#define kAudioHardwareBadObjectError FOURCC('!', 'o', 'b', 'j')
#define kAudioHardwareBadPropertySizeError FOURCC('!', 's', 'i', 'z')
#define kAudioHardwareIllegalOperationError FOURCC('n', 'o', 'p', 'e')
#define SCOPE_INPUT FOURCC('i', 'n', 'p', 't')

static const void *string(const char *text) {
    typedef const void *(*create_string)(const void *allocator, const char *text, uint32_t encoding);
    static create_string create;
    if (!create)
        create = (create_string)perry_audio_lookup("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation",
                                                   "_CFStringCreateWithCString");
    return create ? create(NULL, text, 0x08000100) : NULL;     // kCFStringEncodingUTF8
}

static AudioStreamBasicDescription format(void) {
    AudioStreamBasicDescription description;
    memset(&description, 0, sizeof(description));
    description.mSampleRate = RATE;
    description.mFormatID = kAudioFormatLinearPCM;
    description.mFormatFlags = 1 | 8;               // float, packed
    description.mBytesPerPacket = description.mBytesPerFrame = 4 * CHANNELS;
    description.mFramesPerPacket = 1;
    description.mChannelsPerFrame = CHANNELS;
    description.mBitsPerChannel = 32;
    return description;
}

/// The property's value into `out` (NULL asks only its size), or an error.
static OSStatus property(AudioObjectID object, const AudioObjectPropertyAddress *address, void *out, uint32_t *size) {
    uint32_t word = 0;
    const void *bytes = &word, *text = NULL;
    uint32_t length = 4;
    double rate = RATE;
    AudioValueRange range = { RATE, RATE }, frames = { 64, 4096 };
    AudioStreamBasicDescription description = format();
    uint32_t channels[2] = { 1, 2 };
    struct { uint32_t count; AudioBuffer buffer; } configuration = { 1, { CHANNELS, 0, NULL } };
    int output = address->scope != SCOPE_INPUT;
    switch (object) {
    case SYSTEM:
        switch (address->selector) {
        case FOURCC('d', 'O', 'u', 't'):    // default output device
        case FOURCC('s', 'O', 'u', 't'):    // default system output device
            word = DEVICE;
            break;
        case FOURCC('d', 'I', 'n', ' '):    // default input device: none
            word = 0;
            break;
        case FOURCC('d', 'e', 'v', '#'):    // devices
            word = DEVICE;
            break;
        case FOURCC('p', 'l', 'u', 'g'):    // plug-ins: none
            length = 0;
            break;
        default:
            return kAudioHardwareUnknownPropertyError;
        }
        break;
    case DEVICE:
        switch (address->selector) {
        case FOURCC('l', 'n', 'a', 'm'):    // name
        case FOURCC('n', 'a', 'm', 'e'):
            text = "Perry Output";
            break;
        case FOURCC('m', 'a', 'k', 'r'):    // manufacturer
            text = "Perry";
            break;
        case FOURCC('u', 'i', 'd', ' '):    // device UID
            text = "PerryOutputDevice";
            break;
        case FOURCC('m', 'u', 'i', 'd'):    // model UID
            text = "PerryOutput";
            break;
        case FOURCC('t', 'r', 'a', 'n'):    // transport type: built-in
            word = FOURCC('b', 'l', 't', 'n');
            break;
        case FOURCC('l', 'i', 'v', 'n'):    // alive
        case FOURCC('g', 'o', 'i', 'n'):    // running somewhere
        case FOURCC('d', 'f', 'l', 't'):    // can be default
        case FOURCC('s', 'f', 'l', 't'):    // can be the system default
            word = output;
            break;
        case FOURCC('n', 's', 'r', 't'):    // nominal sample rate
            bytes = &rate;
            length = sizeof(rate);
            break;
        case FOURCC('n', 's', 'r', '#'):    // available sample rates
            bytes = &range;
            length = sizeof(range);
            break;
        case FOURCC('f', 's', 'i', 'z'):    // buffer frame size
            word = FRAMES;
            break;
        case FOURCC('f', 's', 'z', '#'):    // buffer frame size range
            bytes = &frames;
            length = sizeof(frames);
            break;
        case FOURCC('l', 't', 'n', 'c'):    // latency
        case FOURCC('s', 'a', 'f', 't'):    // safety offset
            word = 0;
            break;
        case FOURCC('s', 't', 'm', '#'):    // streams
            if (output) word = STREAM; else length = 0;
            break;
        case FOURCC('s', 'l', 'a', 'y'):    // stream configuration: an AudioBufferList
            if (!output) configuration.count = 0;
            bytes = &configuration;
            length = sizeof(configuration);
            break;
        case FOURCC('d', 'c', 'h', '2'):    // preferred stereo channels
            bytes = channels;
            length = sizeof(channels);
            break;
        case FOURCC('s', 'f', 'm', 't'):    // stream format
        case FOURCC('p', 'f', 't', ' '):
            bytes = &description;
            length = sizeof(description);
            break;
        default:
            return kAudioHardwareUnknownPropertyError;
        }
        break;
    case STREAM:
        switch (address->selector) {
        case FOURCC('s', 'f', 'm', 't'):    // virtual format
        case FOURCC('p', 'f', 't', ' '):    // physical format
            bytes = &description;
            length = sizeof(description);
            break;
        case FOURCC('s', 'd', 'i', 'r'):    // direction: output
            word = 0;
            break;
        case FOURCC('s', 'c', 'h', 'n'):    // starting channel
            word = 1;
            break;
        default:
            return kAudioHardwareUnknownPropertyError;
        }
        break;
    default:
        return kAudioHardwareBadObjectError;
    }
    if (text) {
        length = sizeof(void *);
        if (out) {
            if (*size < length) return kAudioHardwareBadPropertySizeError;
            const void *made = string(text);
            memcpy(out, &made, length);
        }
        *size = length;
        return 0;
    }
    if (out) {
        if (*size < length) return kAudioHardwareBadPropertySizeError;
        memcpy(out, bytes, length);
    }
    *size = length;
    return 0;
}

uint8_t darwin_AudioObjectHasProperty(AudioObjectID object, const AudioObjectPropertyAddress *address)
    DARWIN_SYMBOL(AudioObjectHasProperty);
uint8_t darwin_AudioObjectHasProperty(AudioObjectID object, const AudioObjectPropertyAddress *address) {
    uint32_t size = 0;
    return address && property(object, address, NULL, &size) == 0;
}

OSStatus darwin_AudioObjectGetPropertyDataSize(AudioObjectID object, const AudioObjectPropertyAddress *address, uint32_t qualifier_size,
                                               const void *qualifier, uint32_t *size) DARWIN_SYMBOL(AudioObjectGetPropertyDataSize);
OSStatus darwin_AudioObjectGetPropertyDataSize(AudioObjectID object, const AudioObjectPropertyAddress *address, uint32_t qualifier_size,
                                               const void *qualifier, uint32_t *size) {
    (void)qualifier_size, (void)qualifier;
    if (!address || !size) return kAudioHardwareIllegalOperationError;
    return property(object, address, NULL, size);
}

OSStatus darwin_AudioObjectGetPropertyData(AudioObjectID object, const AudioObjectPropertyAddress *address, uint32_t qualifier_size,
                                           const void *qualifier, uint32_t *size, void *data) DARWIN_SYMBOL(AudioObjectGetPropertyData);
OSStatus darwin_AudioObjectGetPropertyData(AudioObjectID object, const AudioObjectPropertyAddress *address, uint32_t qualifier_size,
                                           const void *qualifier, uint32_t *size, void *data) {
    (void)qualifier_size, (void)qualifier;
    if (!address || !size || !data) return kAudioHardwareIllegalOperationError;
    return property(object, address, data, size);
}

/// The device's rate and buffer size may be "set" to what they are; other
/// values, and other properties, can't be changed.
OSStatus darwin_AudioObjectSetPropertyData(AudioObjectID object, const AudioObjectPropertyAddress *address, uint32_t qualifier_size,
                                           const void *qualifier, uint32_t size, const void *data) DARWIN_SYMBOL(AudioObjectSetPropertyData);
OSStatus darwin_AudioObjectSetPropertyData(AudioObjectID object, const AudioObjectPropertyAddress *address, uint32_t qualifier_size,
                                           const void *qualifier, uint32_t size, const void *data) {
    (void)qualifier_size, (void)qualifier, (void)size, (void)data;
    if (!address) return kAudioHardwareIllegalOperationError;
    uint32_t known = 0;
    if (property(object, address, NULL, &known) != 0) return kAudioHardwareUnknownPropertyError;
    // A buffer size or rate request is honored by the output unit's own
    // buffering; the device itself stays as it is.
    return 0;
}

typedef OSStatus (*property_listener)(AudioObjectID, uint32_t, const AudioObjectPropertyAddress *, void *);

OSStatus darwin_AudioObjectAddPropertyListener(AudioObjectID object, const AudioObjectPropertyAddress *address, property_listener listener,
                                               void *client) DARWIN_SYMBOL(AudioObjectAddPropertyListener);
OSStatus darwin_AudioObjectAddPropertyListener(AudioObjectID object, const AudioObjectPropertyAddress *address, property_listener listener,
                                               void *client) {
    (void)address, (void)client;
    if (object != SYSTEM && object != DEVICE && object != STREAM) return kAudioHardwareBadObjectError;
    return listener ? 0 : kAudioHardwareIllegalOperationError;
}

OSStatus darwin_AudioObjectRemovePropertyListener(AudioObjectID object, const AudioObjectPropertyAddress *address,
                                                  property_listener listener, void *client)
    DARWIN_SYMBOL(AudioObjectRemovePropertyListener);
OSStatus darwin_AudioObjectRemovePropertyListener(AudioObjectID object, const AudioObjectPropertyAddress *address,
                                                  property_listener listener, void *client) {
    (void)object, (void)address, (void)listener, (void)client;
    return 0;
}

// The block forms, which Wwise's macOS output also uses on newer systems.
OSStatus darwin_AudioObjectAddPropertyListenerBlock(AudioObjectID object, const AudioObjectPropertyAddress *address, void *queue,
                                                    void *block) DARWIN_SYMBOL(AudioObjectAddPropertyListenerBlock);
OSStatus darwin_AudioObjectAddPropertyListenerBlock(AudioObjectID object, const AudioObjectPropertyAddress *address, void *queue,
                                                    void *block) {
    (void)address, (void)queue;
    if (object != SYSTEM && object != DEVICE && object != STREAM) return kAudioHardwareBadObjectError;
    return block ? 0 : kAudioHardwareIllegalOperationError;
}

OSStatus darwin_AudioObjectRemovePropertyListenerBlock(AudioObjectID object, const AudioObjectPropertyAddress *address, void *queue,
                                                       void *block) DARWIN_SYMBOL(AudioObjectRemovePropertyListenerBlock);
OSStatus darwin_AudioObjectRemovePropertyListenerBlock(AudioObjectID object, const AudioObjectPropertyAddress *address, void *queue,
                                                       void *block) {
    (void)object, (void)address, (void)queue, (void)block;
    return 0;
}

#if !defined(__arm__)
// The HAL's calls from before audio objects, which older Mac programs make.
#include <pthread.h>
#include <stdbool.h>
#include <time.h>

#define kAudioObjectPropertyScopeGlobal FOURCC('g', 'l', 'o', 'b')
#define kAudioDevicePropertyScopeInput FOURCC('i', 'n', 'p', 't')
#define kAudioDevicePropertyScopeOutput FOURCC('o', 'u', 't', 'p')

static AudioObjectPropertyAddress hardware_address(uint32_t property) {
    return (AudioObjectPropertyAddress){ property, kAudioObjectPropertyScopeGlobal, 0 };
}

static AudioObjectPropertyAddress device_address(uint32_t channel, uint8_t is_input, uint32_t property) {
    return (AudioObjectPropertyAddress){ property,
        is_input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput, channel };
}

OSStatus darwin_AudioHardwareGetPropertyInfo(uint32_t property, uint32_t *size, uint8_t *writable) DARWIN_SYMBOL(AudioHardwareGetPropertyInfo);
OSStatus darwin_AudioHardwareGetPropertyInfo(uint32_t property, uint32_t *size, uint8_t *writable) {
    AudioObjectPropertyAddress address = hardware_address(property);
    if (writable) *writable = 0;
    uint32_t found = 0;
    OSStatus status = darwin_AudioObjectGetPropertyDataSize(1, &address, 0, NULL, &found);
    if (size) *size = found;
    return status;
}

OSStatus darwin_AudioHardwareGetProperty(uint32_t property, uint32_t *size, void *data) DARWIN_SYMBOL(AudioHardwareGetProperty);
OSStatus darwin_AudioHardwareGetProperty(uint32_t property, uint32_t *size, void *data) {
    AudioObjectPropertyAddress address = hardware_address(property);
    return darwin_AudioObjectGetPropertyData(1, &address, 0, NULL, size, data);
}

OSStatus darwin_AudioDeviceGetPropertyInfo(uint32_t device, uint32_t channel, uint8_t is_input, uint32_t property,
                                           uint32_t *size, uint8_t *writable) DARWIN_SYMBOL(AudioDeviceGetPropertyInfo);
OSStatus darwin_AudioDeviceGetPropertyInfo(uint32_t device, uint32_t channel, uint8_t is_input, uint32_t property,
                                           uint32_t *size, uint8_t *writable) {
    AudioObjectPropertyAddress address = device_address(channel, is_input, property);
    if (writable) *writable = 0;
    uint32_t found = 0;
    OSStatus status = darwin_AudioObjectGetPropertyDataSize(device, &address, 0, NULL, &found);
    if (size) *size = found;
    return status;
}

OSStatus darwin_AudioDeviceGetProperty(uint32_t device, uint32_t channel, uint8_t is_input, uint32_t property,
                                       uint32_t *size, void *data) DARWIN_SYMBOL(AudioDeviceGetProperty);
OSStatus darwin_AudioDeviceGetProperty(uint32_t device, uint32_t channel, uint8_t is_input, uint32_t property,
                                       uint32_t *size, void *data) {
    AudioObjectPropertyAddress address = device_address(channel, is_input, property);
    return darwin_AudioObjectGetPropertyData(device, &address, 0, NULL, size, data);
}

// Nothing about the device changes, so listeners are never called.
#define NO_LISTENER(name, ...)                              \
    OSStatus darwin_##name(__VA_ARGS__) DARWIN_SYMBOL(name); \
    OSStatus darwin_##name(__VA_ARGS__) { return 0; }

NO_LISTENER(AudioHardwareAddPropertyListener, uint32_t a, void *b, void *c)
NO_LISTENER(AudioHardwareRemovePropertyListener, uint32_t a, void *b)
NO_LISTENER(AudioDeviceAddPropertyListener, uint32_t a, uint32_t b, uint8_t c, uint32_t d, void *e, void *f)
NO_LISTENER(AudioDeviceRemovePropertyListener, uint32_t a, uint32_t b, uint8_t c, uint32_t d, void *e)

OSStatus darwin_AudioDeviceSetProperty(uint32_t device, const void *when, uint32_t channel, uint8_t is_input, uint32_t property,
                                       uint32_t size, const void *data) DARWIN_SYMBOL(AudioDeviceSetProperty);
OSStatus darwin_AudioDeviceSetProperty(uint32_t device, const void *when, uint32_t channel, uint8_t is_input, uint32_t property,
                                       uint32_t size, const void *data) {
    (void)when;
    AudioObjectPropertyAddress address = device_address(channel, is_input, property);
    return darwin_AudioObjectSetPropertyData(device, &address, 0, NULL, size, data);
}

uint64_t darwin_AudioGetCurrentHostTime(void) DARWIN_SYMBOL(AudioGetCurrentHostTime);
uint64_t darwin_AudioGetCurrentHostTime(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint64_t)now.tv_sec * 1000000000u + (uint64_t)now.tv_nsec;
}

double darwin_AudioGetHostClockFrequency(void) DARWIN_SYMBOL(AudioGetHostClockFrequency);
double darwin_AudioGetHostClockFrequency(void) { return 1e9; }

// MARK: - I/O procs
//
// A program playing straight to the device registers I/O procs, which the
// device's thread calls for each buffer. Here that thread is an output
// unit's, rendering in the device's format, and its render callback calls
// them; each one's audio is summed, as the HAL does.

typedef struct {
    uint32_t type, subtype, manufacturer, flags, mask;
} component_description;

void *darwin_AudioComponentFindNext(const void *after, const component_description *description) DARWIN_SYMBOL(AudioComponentFindNext);
OSStatus darwin_AudioComponentInstanceNew(const void *component, void **out) DARWIN_SYMBOL(AudioComponentInstanceNew);
OSStatus darwin_AudioUnitSetProperty(void *unit, uint32_t id, uint32_t scope, uint32_t element, const void *value, uint32_t size)
    DARWIN_SYMBOL(AudioUnitSetProperty);
OSStatus darwin_AudioUnitInitialize(void *unit) DARWIN_SYMBOL(AudioUnitInitialize);
OSStatus darwin_AudioOutputUnitStart(void *unit) DARWIN_SYMBOL(AudioOutputUnitStart);
OSStatus darwin_AudioOutputUnitStop(void *unit) DARWIN_SYMBOL(AudioOutputUnitStop);

#define kAudioHardwareBadDeviceError FOURCC('!', 'd', 'e', 'v')
#define kAudioHardwareNotRunningError FOURCC('s', 't', 'o', 'p')
#define kAudioTimeStampRateScalarValid (1u << 2)

typedef OSStatus (*io_proc)(AudioObjectID device, const AudioTimeStamp *now, const AudioBufferList *input,
                            const AudioTimeStamp *input_time, AudioBufferList *output, const AudioTimeStamp *output_time, void *client);

typedef struct {
    io_proc proc;
    void *client;
    bool started;
} io_client;

enum { IO_CLIENTS = 8 };

// The lock is never held across the output unit's start or stop, which
// wait for a render that takes it.
static pthread_mutex_t io_lock = PTHREAD_MUTEX_INITIALIZER;
static io_client io_clients[IO_CLIENTS];
static void *io_unit;
static bool io_running;
static AudioTimeStamp io_time;

/// Lock held.
static io_client *io_find(io_proc proc) {
    for (int i = 0; i < IO_CLIENTS; i++) if (io_clients[i].proc == proc) return &io_clients[i];
    return NULL;
}

/// Lock held.
static bool io_any_started(void) {
    for (int i = 0; i < IO_CLIENTS; i++) if (io_clients[i].proc && io_clients[i].started) return true;
    return false;
}

static OSStatus io_render(void *refcon, uint32_t *flags, const AudioTimeStamp *time, uint32_t bus, uint32_t frames,
                          AudioBufferList *data) {
    (void)refcon, (void)flags, (void)bus;
    io_client clients[IO_CLIENTS];
    pthread_mutex_lock(&io_lock);
    memcpy(clients, io_clients, sizeof clients);
    io_time = *time;
    pthread_mutex_unlock(&io_lock);
    if (frames > FRAMES) return kAudio_ParamError;
    const AudioBufferList input = { 0 };
    bool first = true;
    float more[FRAMES * CHANNELS];
    for (int i = 0; i < IO_CLIENTS; i++) {
        if (!clients[i].proc || !clients[i].started) continue;
        if (first) {
            clients[i].proc(DEVICE, time, &input, time, data, time, clients[i].client);
            first = false;
            continue;
        }
        memset(more, 0, sizeof more);
        struct { uint32_t count; AudioBuffer buffer; } list = { 1, { CHANNELS, frames * CHANNELS * sizeof(float), more } };
        clients[i].proc(DEVICE, time, &input, time, (AudioBufferList *)&list, time, clients[i].client);
        float *sum = data->mBuffers[0].mData;
        for (uint32_t k = 0; k < frames * CHANNELS; k++) sum[k] += more[k];
    }
    return 0;
}

/// The output unit, made the first time it's needed. Lock held.
static bool io_open(void) {
    if (io_unit) return true;
    const component_description description = { FOURCC('a', 'u', 'o', 'u'), FOURCC('d', 'e', 'f', ' '), FOURCC('a', 'p', 'p', 'l'), 0, 0 };
    void *unit = NULL;
    void *component = darwin_AudioComponentFindNext(NULL, &description);
    if (!component || darwin_AudioComponentInstanceNew(component, &unit) != 0) return false;
    AudioStreamBasicDescription device_format = format();
    struct { void *proc; void *refcon; } callback = { (void *)io_render, NULL };
    darwin_AudioUnitSetProperty(unit, 8, 1, 0, &device_format, sizeof device_format);      // the input's stream format
    darwin_AudioUnitSetProperty(unit, 23, 1, 0, &callback, sizeof callback);               // its render callback
    darwin_AudioUnitInitialize(unit);
    io_unit = unit;
    return true;
}

OSStatus darwin_AudioDeviceAddIOProc(uint32_t device, io_proc proc, void *client) DARWIN_SYMBOL(AudioDeviceAddIOProc);
OSStatus darwin_AudioDeviceAddIOProc(uint32_t device, io_proc proc, void *client) {
    if (device != DEVICE) return kAudioHardwareBadDeviceError;
    if (!proc) return kAudioHardwareIllegalOperationError;
    pthread_mutex_lock(&io_lock);
    io_client *slot = io_find(proc);
    if (!slot) slot = io_find(NULL);
    if (slot) *slot = (io_client){ proc, client, slot->proc == proc && slot->started };
    pthread_mutex_unlock(&io_lock);
    return slot ? 0 : kAudioHardwareIllegalOperationError;
}

OSStatus darwin_AudioDeviceStart(uint32_t device, io_proc proc) DARWIN_SYMBOL(AudioDeviceStart);
OSStatus darwin_AudioDeviceStart(uint32_t device, io_proc proc) {
    if (device != DEVICE) return kAudioHardwareBadDeviceError;
    pthread_mutex_lock(&io_lock);
    io_client *slot = proc ? io_find(proc) : NULL;
    if (proc && !slot) {
        pthread_mutex_unlock(&io_lock);
        return kAudioHardwareIllegalOperationError;
    }
    if (slot) slot->started = true;
    bool start = !io_running && io_any_started() && io_open();
    if (start) io_running = true;
    void *unit = io_unit;
    pthread_mutex_unlock(&io_lock);
    return start ? darwin_AudioOutputUnitStart(unit) : 0;
}

/// Stops the proc, and the device with its last one. A proc may stop itself.
static OSStatus io_stop(io_proc proc, bool remove) {
    pthread_mutex_lock(&io_lock);
    io_client *slot = proc ? io_find(proc) : NULL;
    if (proc && !slot) {
        pthread_mutex_unlock(&io_lock);
        return kAudioHardwareIllegalOperationError;
    }
    if (slot) {
        slot->started = false;
        if (remove) *slot = (io_client){ NULL, NULL, false };
    }
    bool stop = io_running && !io_any_started();
    if (stop) io_running = false;
    void *unit = io_unit;
    pthread_mutex_unlock(&io_lock);
    return stop ? darwin_AudioOutputUnitStop(unit) : 0;
}

OSStatus darwin_AudioDeviceStop(uint32_t device, io_proc proc) DARWIN_SYMBOL(AudioDeviceStop);
OSStatus darwin_AudioDeviceStop(uint32_t device, io_proc proc) {
    return device == DEVICE ? io_stop(proc, false) : kAudioHardwareBadDeviceError;
}

OSStatus darwin_AudioDeviceRemoveIOProc(uint32_t device, io_proc proc) DARWIN_SYMBOL(AudioDeviceRemoveIOProc);
OSStatus darwin_AudioDeviceRemoveIOProc(uint32_t device, io_proc proc) {
    if (device != DEVICE) return kAudioHardwareBadDeviceError;
    return proc ? io_stop(proc, true) : kAudioHardwareIllegalOperationError;
}

/// The last buffer's time, carried forward to now by the clock.
OSStatus darwin_AudioDeviceGetCurrentTime(uint32_t device, AudioTimeStamp *out) DARWIN_SYMBOL(AudioDeviceGetCurrentTime);
OSStatus darwin_AudioDeviceGetCurrentTime(uint32_t device, AudioTimeStamp *out) {
    if (device != DEVICE) return kAudioHardwareBadDeviceError;
    if (!out) return kAudioHardwareIllegalOperationError;
    pthread_mutex_lock(&io_lock);
    bool running = io_running;
    AudioTimeStamp last = io_time;
    pthread_mutex_unlock(&io_lock);
    if (!running) return kAudioHardwareNotRunningError;
    uint64_t now = darwin_AudioGetCurrentHostTime();
    memset(out, 0, sizeof *out);
    out->mSampleTime = last.mHostTime ? last.mSampleTime + (double)(now - last.mHostTime) * RATE / 1e9 : 0;
    out->mHostTime = now;
    out->mRateScalar = 1;
    out->mFlags = kAudioTimeStampSampleTimeValid | kAudioTimeStampHostTimeValid | kAudioTimeStampRateScalarValid;
    return 0;
}
#endif
