#ifndef CPERRY_OBJC_INTEROP_H
#define CPERRY_OBJC_INTEROP_H

// C types for PerryObjCInterop's values at the Objective-C and C boundary,
// which Swift's @c functions and @convention(c) types can only have as C
// types.

#include <stdint.h>

// A double or a 64-bit integer as 32-bit Darwin passes it: two words, the
// low one first, in the next two core registers or stack words from any
// word. Linux's armhf passes this structure word by word too, where it
// would align a uint64_t to an even register pair and pass a double in a
// VFP register.
typedef struct perry_word_pair {
    uint32_t low;
    uint32_t high;
} perry_word_pair;

#endif
