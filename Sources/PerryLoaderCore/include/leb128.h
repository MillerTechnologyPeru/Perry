#ifndef PERRY_LEB128_H
#define PERRY_LEB128_H

#include <stdint.h>

// LEB128 decoding for dyld info opcodes and export tries. Reads stop at `end`.

static inline uint64_t perry_read_uleb(const uint8_t **p, const uint8_t *end) {
    uint64_t result = 0;
    unsigned shift = 0;
    while (*p < end) {
        uint8_t byte = *(*p)++;
        if (shift < 64)
            result |= (uint64_t)(byte & 0x7f) << shift;
        shift += 7;
        if (!(byte & 0x80))
            break;
    }
    return result;
}

static inline int64_t perry_read_sleb(const uint8_t **p, const uint8_t *end) {
    int64_t result = 0;
    unsigned shift = 0;
    uint8_t byte = 0;
    while (*p < end) {
        byte = *(*p)++;
        if (shift < 64)
            result |= (int64_t)(byte & 0x7f) << shift;
        shift += 7;
        if (!(byte & 0x80))
            break;
    }
    if (shift < 64 && (byte & 0x40))
        result |= -((int64_t)1 << shift);
    return result;
}

#endif
