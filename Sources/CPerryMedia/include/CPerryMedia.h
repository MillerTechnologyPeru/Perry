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

// A sample's duration and its presentation and decode times.
typedef struct CMSampleTimingInfo {
    CMTime duration;
    CMTime presentationTimeStamp;
    CMTime decodeTimeStamp;
} CMSampleTimingInfo;

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

// CoreVideo's time, as a display link gives its refresh period.
typedef struct CVTime {
    int64_t timeValue;
    int32_t timeScale;
    int32_t flags;
} CVTime;

// The time a display link hands its callback: 80 bytes.
typedef struct CVTimeStamp {
    uint32_t version;
    int32_t videoTimeScale;
    int64_t videoTime;
    uint64_t hostTime;
    double rateScalar;
    int64_t videoRefreshPeriod;
    uint8_t smpteTime[24];
    uint64_t flags;
    uint64_t reserved;
} CVTimeStamp;

/// g_object_set(object, name, value, NULL), called as the variadic function it is.
void perry_g_object_set_double(void *object_set, void *object, const char *name, double value);

#endif
