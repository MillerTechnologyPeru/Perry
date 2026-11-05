// The audio session, which this platform has no others to share the output
// with: initializing, activating and setting its properties all succeed.
// No audio units are found yet, as on a device with no audio output, so
// apps that play through one carry on without sound.

#include "PerryAudioToolbox.h"

#include <stddef.h>
#include <stdint.h>

typedef void (*interruption_listener)(void *data, uint32_t state);

OSStatus darwin_AudioSessionInitialize(void *run_loop, const void *mode, interruption_listener listener, void *data)
    DARWIN_SYMBOL(AudioSessionInitialize);
OSStatus darwin_AudioSessionInitialize(void *run_loop, const void *mode, interruption_listener listener, void *data) {
    return 0;
}

OSStatus darwin_AudioSessionSetActive(uint8_t active) DARWIN_SYMBOL(AudioSessionSetActive);
OSStatus darwin_AudioSessionSetActive(uint8_t active) { return 0; }

OSStatus darwin_AudioSessionSetProperty(uint32_t property, uint32_t size, const void *value) DARWIN_SYMBOL(AudioSessionSetProperty);
OSStatus darwin_AudioSessionSetProperty(uint32_t property, uint32_t size, const void *value) { return 0; }

void *darwin_AudioComponentFindNext(void *component, const void *description) DARWIN_SYMBOL(AudioComponentFindNext);
void *darwin_AudioComponentFindNext(void *component, const void *description) { return NULL; }

// Audio files and queues are not decoded or played yet: opening a file
// fails as for a type that isn't supported, and creating an output queue or
// a converter fails, so apps skip their sounds.

/// kAudioFileUnsupportedFileTypeError, 'typ?'.
#define UNSUPPORTED_FILE_TYPE 0x7479703f
/// kAudioFileNotOpenError.
#define FILE_NOT_OPEN (-38)
#define PARAMETER_ERROR (-50)

OSStatus darwin_AudioFileOpenURL(const void *url, int8_t permissions, uint32_t type, void **file) DARWIN_SYMBOL(AudioFileOpenURL);
OSStatus darwin_AudioFileOpenURL(const void *url, int8_t permissions, uint32_t type, void **file) {
    if (file) *file = NULL;
    return UNSUPPORTED_FILE_TYPE;
}

OSStatus darwin_AudioFileOpenWithCallbacks(void *data, void *read, void *write, void *get_size, void *set_size,
                                           uint32_t type, void **file) DARWIN_SYMBOL(AudioFileOpenWithCallbacks);
OSStatus darwin_AudioFileOpenWithCallbacks(void *data, void *read, void *write, void *get_size, void *set_size,
                                           uint32_t type, void **file) {
    if (file) *file = NULL;
    return UNSUPPORTED_FILE_TYPE;
}

OSStatus darwin_AudioFileClose(void *file) DARWIN_SYMBOL(AudioFileClose);
OSStatus darwin_AudioFileClose(void *file) { return FILE_NOT_OPEN; }

OSStatus darwin_AudioFileGetProperty(void *file, uint32_t property, uint32_t *size, void *value) DARWIN_SYMBOL(AudioFileGetProperty);
OSStatus darwin_AudioFileGetProperty(void *file, uint32_t property, uint32_t *size, void *value) { return FILE_NOT_OPEN; }

OSStatus darwin_AudioFileGetPropertyInfo(void *file, uint32_t property, uint32_t *size, uint32_t *writable)
    DARWIN_SYMBOL(AudioFileGetPropertyInfo);
OSStatus darwin_AudioFileGetPropertyInfo(void *file, uint32_t property, uint32_t *size, uint32_t *writable) { return FILE_NOT_OPEN; }

OSStatus darwin_AudioFileReadPackets(void *file, uint8_t cache, uint32_t *bytes, void *descriptions, int64_t start,
                                     uint32_t *packets, void *buffer) DARWIN_SYMBOL(AudioFileReadPackets);
OSStatus darwin_AudioFileReadPackets(void *file, uint8_t cache, uint32_t *bytes, void *descriptions, int64_t start,
                                     uint32_t *packets, void *buffer) {
    if (bytes) *bytes = 0;
    if (packets) *packets = 0;
    return FILE_NOT_OPEN;
}

OSStatus darwin_AudioQueueNewOutput(const void *format, void *callback, void *data, void *run_loop, const void *mode,
                                    uint32_t flags, void **queue) DARWIN_SYMBOL(AudioQueueNewOutput);
OSStatus darwin_AudioQueueNewOutput(const void *format, void *callback, void *data, void *run_loop, const void *mode,
                                    uint32_t flags, void **queue) {
    if (queue) *queue = NULL;
    return PARAMETER_ERROR;
}

OSStatus darwin_AudioConverterNew(const void *source, const void *destination, void **converter) DARWIN_SYMBOL(AudioConverterNew);
OSStatus darwin_AudioConverterNew(const void *source, const void *destination, void **converter) {
    if (converter) *converter = NULL;
    return PARAMETER_ERROR;
}
