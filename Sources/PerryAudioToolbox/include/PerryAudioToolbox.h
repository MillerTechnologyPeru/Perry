#ifndef PERRY_AUDIO_TOOLBOX_H
#define PERRY_AUDIO_TOOLBOX_H

// libPerryAudioToolbox: the provider for AudioToolbox.framework's system
// sounds. There is no audio output: sounds are created and disposed of, and
// playing one finishes at once.

#include <stdint.h>

#define DARWIN_SYMBOL(name) __asm__("_" #name) __attribute__((visibility("default"), used))

typedef int32_t OSStatus;
typedef uint32_t SystemSoundID;
typedef uint32_t AudioServicesPropertyID;

#endif
