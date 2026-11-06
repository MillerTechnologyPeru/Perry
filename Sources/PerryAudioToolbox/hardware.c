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
