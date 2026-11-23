#ifndef CPERRY_CORE_GRAPHICS_H
#define CPERRY_CORE_GRAPHICS_H

// The part of libPerryCoreGraphics that must be C: constants exported as
// data under their Mach-O names, and the structures CoreGraphics' newer C
// functions pass by value or by pointer, laid out as Darwin's are.

#include "CPerryGeometry.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// CGContentToneMappingInfo: a CGToneMapping and its options dictionary.
typedef struct PerryCGContentToneMappingInfo {
    uint32_t method;
    void *options;
} PerryCGContentToneMappingInfo;

// CGContentInfo: what an adaptive bitmap context's content needs.
typedef struct PerryCGContentInfo {
    uint32_t deepestImageComponent;   // CGComponent
    uint32_t contentColorModels;      // CGColorModel
    bool hasWideGamut;
    bool hasTransparency;
    float largestContentHeadroom;
} PerryCGContentInfo;

// CGBitmapParameters: the bitmap an adaptive context resolves to.
typedef struct PerryCGBitmapParameters {
    size_t width;
    size_t height;
    size_t bytesPerPixel;
    size_t alignedBytesPerRow;
    uint32_t component;               // CGComponent
    uint32_t layout;                  // CGBitmapLayout
    uint32_t format;                  // CGImagePixelFormatInfo
    void *colorSpace;                 // CGColorSpaceRef
    bool hasPremultipliedAlpha;
    long byteOrder;                   // CFByteOrder
    float edrTargetHeadroom;
} PerryCGBitmapParameters;

#endif
