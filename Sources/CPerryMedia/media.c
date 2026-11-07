// CoreMedia's constant times, which programs read as data.

#include "CPerryMedia.h"

#define DARWIN_DATA(name) __asm__("_" #name) __attribute__((visibility("default"), used))

extern const CMTime darwin_kCMTimeZero DARWIN_DATA(kCMTimeZero);
extern const CMTime darwin_kCMTimeInvalid DARWIN_DATA(kCMTimeInvalid);
extern const CMTime darwin_kCMTimeIndefinite DARWIN_DATA(kCMTimeIndefinite);
extern const CMTime darwin_kCMTimePositiveInfinity DARWIN_DATA(kCMTimePositiveInfinity);
extern const CMTime darwin_kCMTimeNegativeInfinity DARWIN_DATA(kCMTimeNegativeInfinity);
extern const CMTimeRange darwin_kCMTimeRangeZero DARWIN_DATA(kCMTimeRangeZero);
extern const CMTimeRange darwin_kCMTimeRangeInvalid DARWIN_DATA(kCMTimeRangeInvalid);
extern const CMSampleTimingInfo darwin_kCMTimingInfoInvalid DARWIN_DATA(kCMTimingInfoInvalid);

const CMTime darwin_kCMTimeZero = { 0, 1, 1, 0 };
const CMTime darwin_kCMTimeInvalid = { 0, 0, 0, 0 };
const CMTime darwin_kCMTimeIndefinite = { 0, 0, 1 | 16, 0 };
const CMTime darwin_kCMTimePositiveInfinity = { 0, 0, 1 | 4, 0 };
const CMTime darwin_kCMTimeNegativeInfinity = { 0, 0, 1 | 8, 0 };
const CMTimeRange darwin_kCMTimeRangeZero = { { 0, 1, 1, 0 }, { 0, 1, 1, 0 } };
const CMTimeRange darwin_kCMTimeRangeInvalid = { { 0, 0, 0, 0 }, { 0, 0, 0, 0 } };
const CMSampleTimingInfo darwin_kCMTimingInfoInvalid = { { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 } };
