#ifndef CPERRY_MEDIA_H
#define CPERRY_MEDIA_H

// CoreMedia's times, laid out as on Darwin. Declared in C so Swift passes
// them as clang does: a CMTime is 24 bytes, which arm64 passes by reference
// and returns through x8.

#include <stdint.h>

typedef struct CMTime {
    int64_t value;
    int32_t timescale;
    uint32_t flags;         // kCMTimeFlags_Valid 1, positive infinity 4, negative 8, indefinite 16
    int64_t epoch;
} CMTime;

typedef struct CMTimeRange {
    CMTime start;
    CMTime duration;
} CMTimeRange;

typedef struct CMVideoDimensions {
    int32_t width;
    int32_t height;
} CMVideoDimensions;

// The pixel format and type CVOpenGLESTextureCacheCreateTextureFromImage
// takes after eight arguments in registers: two GLenums that Darwin packs
// into one eight-byte stack slot, where Linux gives each its own. As one
// struct they are passed on Linux as Darwin lays them out.
typedef struct CVTextureFormatAndType {
    uint32_t format;
    uint32_t type;
} CVTextureFormatAndType;

#endif
