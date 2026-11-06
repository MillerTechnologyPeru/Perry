// The audio session, which this platform has no others to share the output
// with: initializing, activating and setting its properties all succeed.

#include "PerryAudioToolbox.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

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

/// The output's rate and channels, no other audio playing, a short buffer
/// and the speaker as the route; other properties aren't supported.
OSStatus darwin_AudioSessionGetProperty(uint32_t property, uint32_t *size, void *value) DARWIN_SYMBOL(AudioSessionGetProperty);
OSStatus darwin_AudioSessionGetProperty(uint32_t property, uint32_t *size, void *value) {
    if (!size || !value) return -50;
    switch (property) {
    case FOURCC('c', 'h', 's', 'r'): {      // CurrentHardwareSampleRate
        double rate = 44100;
        if (*size < 8) return -50;
        memcpy(value, &rate, 8);
        *size = 8;
        return 0;
    }
    case FOURCC('c', 'h', 'o', 'c'): {      // CurrentHardwareOutputNumberChannels
        uint32_t channels = 2;
        if (*size < 4) return -50;
        memcpy(value, &channels, 4);
        *size = 4;
        return 0;
    }
    case FOURCC('o', 't', 'h', 'r'): case FOURCC('i', 'a', 'v', 'a'): {    // OtherAudioIsPlaying, AudioInputAvailable
        uint32_t no = 0;
        if (*size < 4) return -50;
        memcpy(value, &no, 4);
        *size = 4;
        return 0;
    }
    case FOURCC('c', 'h', 'b', 'd'): {      // CurrentHardwareIOBufferDuration
        float duration = 0.0116f;
        if (*size < 4) return -50;
        memcpy(value, &duration, 4);
        *size = 4;
        return 0;
    }
    case FOURCC('r', 'o', 'u', 't'): {      // AudioRoute: a CFString the caller releases
        typedef const void *(*create_string)(const void *allocator, const char *text, uint32_t encoding);
        static create_string create;
        if (!create) {
            create = (create_string)perry_audio_lookup(
                "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation", "_CFStringCreateWithCString");
        }
        if (*size < sizeof(void *) || !create) return -50;
        const void *route = create(NULL, "Speaker", 0x08000100);    // kCFStringEncodingUTF8
        memcpy(value, &route, sizeof(route));
        *size = sizeof(route);
        return 0;
    }
    default:
        return FOURCC('p', 't', 'y', '?');
    }
}

OSStatus darwin_AudioSessionAddPropertyListener(uint32_t property, void *proc, void *data) DARWIN_SYMBOL(AudioSessionAddPropertyListener);
OSStatus darwin_AudioSessionAddPropertyListener(uint32_t property, void *proc, void *data) { return 0; }
