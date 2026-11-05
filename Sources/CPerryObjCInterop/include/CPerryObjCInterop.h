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

// A structure as 32-bit Darwin passes it: its words, in core registers and on
// the stack, and through memory when returned, where Linux's armhf passes a
// structure of floats or doubles in VFP registers. Structures of words pass
// the same way on both.
typedef struct perry_words2 { uint32_t words[2]; } perry_words2;
typedef struct perry_words3 { uint32_t words[3]; } perry_words3;
typedef struct perry_words4 { uint32_t words[4]; } perry_words4;
typedef struct perry_words6 { uint32_t words[6]; } perry_words6;
typedef struct perry_words8 { uint32_t words[8]; } perry_words8;
typedef struct perry_words16 { uint32_t words[16]; } perry_words16;

#endif
