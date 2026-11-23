// vImage's bridges to Core Graphics and Core Video: image formats described
// by vImage_CGImageFormat, converters between them (vImageConvert_AnyToAny),
// CGImages made from buffers and buffers from CGImages, and Core Video
// pixel formats described by vImageCVImageFormat.
//
// A converter decodes each pixel to red, green, blue and alpha in floating
// point and encodes it again. Color spaces are matched by model only (gray
// or RGB): a conversion between two RGB spaces, or from a Y'CbCr format's
// RGB space to another, is treated as the identity. RGB to gray uses the
// Rec. 709 luma weights.
//
// The converter and CV image format are Objective-C objects, as Darwin's
// are (Swift retains and releases them as objects), each an instance of a
// class made here with its state in the instance's extra bytes.

#define _GNU_SOURCE
#include "vimage.h"

#include <dlfcn.h>
#include <math.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>

#define EXPORT(ret, name, args) ret name args DARWIN_SYMBOL(name); ret name args

typedef double CGFloat;
typedef void *CGColorSpaceRef;
typedef void *CGImageRef;
typedef void *CFStringRef;
typedef void *CVPixelBufferRef;
typedef uint32_t vImageBufferTypeCode;

typedef struct vImage_CGImageFormat {
    uint32_t bitsPerComponent;
    uint32_t bitsPerPixel;
    CGColorSpaceRef colorSpace;
    uint32_t bitmapInfo;
    uint32_t version;
    const CGFloat *decode;
    int32_t renderingIntent;
} vImage_CGImageFormat;

typedef struct vImage_ARGBToYpCbCrMatrix { float R_Yp, G_Yp, B_Yp, R_Cb, G_Cb, B_Cb_R_Cr, G_Cr, B_Cr; } vImage_ARGBToYpCbCrMatrix;
typedef struct vImageChannelDescription { CGFloat min, zero, full, max; } vImageChannelDescription;

extern const vImage_ARGBToYpCbCrMatrix *perry_vimage_matrix_601, *perry_vimage_matrix_709;
float perry_vimage_half_to_float(uint16_t h);
uint16_t perry_vimage_float_to_half(float f);

enum {
    TypeEnd = 0, TypeChannel1 = 1, TypeChannel2 = 2, TypeChannel3 = 3, TypeAlpha = 17, TypeYCbCr = 19, TypeLuminance = 20,
    TypeChroma = 21, TypeCb = 22, TypeCr = 23, TypeCGFormat = 24, TypeChunky = 25,
};
enum { FormatErrorMatrix = -21600, FormatErrorChromaSiting = -21601, FormatErrorColorSpace = -21602 };

// MARK: - Other frameworks

typedef struct { const uint8_t *(*bytes)(void *); long (*length)(void *); } cfdata_fns;

static struct {
    // Core Graphics
    size_t (*imageWidth)(CGImageRef), (*imageHeight)(CGImageRef), (*imageBitsPerComponent)(CGImageRef),
        (*imageBitsPerPixel)(CGImageRef), (*imageBytesPerRow)(CGImageRef);
    uint32_t (*imageBitmapInfo)(CGImageRef);
    CGColorSpaceRef (*imageColorSpace)(CGImageRef);
    void *(*imageDataProvider)(CGImageRef);
    int32_t (*imageRenderingIntent)(CGImageRef);
    void *(*providerCopyData)(void *);
    void *(*providerCreateWithData)(void *, const void *, size_t, void (*)(void *, const void *, size_t));
    void (*providerRelease)(void *);
    CGImageRef (*imageCreate)(size_t, size_t, size_t, size_t, size_t, CGColorSpaceRef, uint32_t, void *, const CGFloat *, bool, int32_t);
    CGColorSpaceRef (*colorSpaceCreateDeviceRGB)(void);
    int32_t (*colorSpaceGetModel)(CGColorSpaceRef);
    size_t (*colorSpaceComponents)(CGColorSpaceRef);
    CGColorSpaceRef (*colorSpaceRetain)(CGColorSpaceRef);
    void (*colorSpaceRelease)(CGColorSpaceRef);
    // Core Foundation
    const uint8_t *(*dataBytes)(void *);
    long (*dataLength)(void *);
    void *(*retain)(void *);
    void (*release)(void *);
    bool (*equal)(void *, void *);
    // Core Video
    uint32_t (*pixelFormat)(CVPixelBufferRef);
    size_t (*width)(CVPixelBufferRef), (*height)(CVPixelBufferRef), (*bytesPerRow)(CVPixelBufferRef);
    int32_t (*lock)(CVPixelBufferRef, uint64_t), (*unlock)(CVPixelBufferRef, uint64_t);
    bool (*isPlanar)(CVPixelBufferRef);
    size_t (*planeCount)(CVPixelBufferRef);
    void *(*base)(CVPixelBufferRef);
    void *(*planeBase)(CVPixelBufferRef, size_t);
    size_t (*planeBytesPerRow)(CVPixelBufferRef, size_t), (*planeWidth)(CVPixelBufferRef, size_t),
        (*planeHeight)(CVPixelBufferRef, size_t);
    void *(*attachment)(CVPixelBufferRef, void *, uint32_t *);
    CGColorSpaceRef (*bufferColorSpace)(CVPixelBufferRef);
    void **matrixKey, **matrix709, **matrix601, **chromaKey, **chromaCenter;
    // Objective-C
    void *(*getClass)(const char *);
    void *(*allocateClassPair)(void *, const char *, size_t);
    void (*registerClassPair)(void *);
    int (*addMethod)(void *, const char *, void *, const char *);
    void *(*createInstance)(void *, size_t);
    void *(*indexedIvars)(void *);
    void *(*registerName)(const char *);
    void *msgSendSuper;
    void *converterClass, *formatClass;
    pthread_once_t once;
} rt = { .once = PTHREAD_ONCE_INIT };

static void converter_dealloc(void *self, void *cmd);
static void format_dealloc(void *self, void *cmd);

#ifdef PERRY_ACCELERATE_TEST
// Built on a Mac against the real frameworks; objects are plain memory.
extern size_t CGImageGetWidth(void *), CGImageGetHeight(void *), CGImageGetBitsPerComponent(void *), CGImageGetBitsPerPixel(void *),
    CGImageGetBytesPerRow(void *);
extern uint32_t CGImageGetBitmapInfo(void *);
extern void *CGImageGetColorSpace(void *), *CGImageGetDataProvider(void *), *CGDataProviderCopyData(void *);
extern int32_t CGImageGetRenderingIntent(void *);
extern void *CGDataProviderCreateWithData(void *, const void *, size_t, void (*)(void *, const void *, size_t));
extern void CGDataProviderRelease(void *);
extern void *CGImageCreate(size_t, size_t, size_t, size_t, size_t, void *, uint32_t, void *, const CGFloat *, bool, int32_t);
extern void *CGColorSpaceCreateDeviceRGB(void), *CGColorSpaceRetain(void *);
extern int32_t CGColorSpaceGetModel(void *);
extern size_t CGColorSpaceGetNumberOfComponents(void *);
extern void CGColorSpaceRelease(void *);
extern const uint8_t *CFDataGetBytePtr(void *);
extern long CFDataGetLength(void *);
extern void *CFRetain(void *);
extern void CFRelease(void *);
extern bool CFEqual(void *, void *);
extern uint32_t CVPixelBufferGetPixelFormatType(void *);
extern size_t CVPixelBufferGetWidth(void *), CVPixelBufferGetHeight(void *), CVPixelBufferGetBytesPerRow(void *),
    CVPixelBufferGetPlaneCount(void *), CVPixelBufferGetBytesPerRowOfPlane(void *, size_t), CVPixelBufferGetWidthOfPlane(void *, size_t),
    CVPixelBufferGetHeightOfPlane(void *, size_t);
extern int32_t CVPixelBufferLockBaseAddress(void *, uint64_t), CVPixelBufferUnlockBaseAddress(void *, uint64_t);
extern bool CVPixelBufferIsPlanar(void *);
extern void *CVPixelBufferGetBaseAddress(void *), *CVPixelBufferGetBaseAddressOfPlane(void *, size_t);
extern void *CVBufferGetAttachment(void *, void *, uint32_t *), *CVImageBufferGetColorSpace(void *);
extern void *kCVImageBufferYCbCrMatrixKey, *kCVImageBufferYCbCrMatrix_ITU_R_709_2, *kCVImageBufferYCbCrMatrix_ITU_R_601_4,
    *kCVImageBufferChromaLocationTopFieldKey, *kCVImageBufferChromaLocation_Center;

static void load_runtime(void) {
    rt.imageWidth = CGImageGetWidth; rt.imageHeight = CGImageGetHeight; rt.imageBitsPerComponent = CGImageGetBitsPerComponent;
    rt.imageBitsPerPixel = CGImageGetBitsPerPixel; rt.imageBytesPerRow = CGImageGetBytesPerRow; rt.imageBitmapInfo = CGImageGetBitmapInfo;
    rt.imageColorSpace = CGImageGetColorSpace; rt.imageDataProvider = CGImageGetDataProvider;
    rt.imageRenderingIntent = CGImageGetRenderingIntent; rt.providerCopyData = CGDataProviderCopyData;
    rt.providerCreateWithData = CGDataProviderCreateWithData; rt.providerRelease = CGDataProviderRelease; rt.imageCreate = CGImageCreate;
    rt.colorSpaceCreateDeviceRGB = CGColorSpaceCreateDeviceRGB; rt.colorSpaceGetModel = CGColorSpaceGetModel;
    rt.colorSpaceComponents = CGColorSpaceGetNumberOfComponents; rt.colorSpaceRetain = CGColorSpaceRetain;
    rt.colorSpaceRelease = CGColorSpaceRelease;
    rt.dataBytes = CFDataGetBytePtr; rt.dataLength = CFDataGetLength; rt.retain = CFRetain; rt.release = CFRelease; rt.equal = CFEqual;
    rt.pixelFormat = CVPixelBufferGetPixelFormatType; rt.width = CVPixelBufferGetWidth; rt.height = CVPixelBufferGetHeight;
    rt.bytesPerRow = CVPixelBufferGetBytesPerRow; rt.lock = CVPixelBufferLockBaseAddress; rt.unlock = CVPixelBufferUnlockBaseAddress;
    rt.isPlanar = CVPixelBufferIsPlanar; rt.planeCount = CVPixelBufferGetPlaneCount; rt.base = CVPixelBufferGetBaseAddress;
    rt.planeBase = CVPixelBufferGetBaseAddressOfPlane; rt.planeBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane;
    rt.planeWidth = CVPixelBufferGetWidthOfPlane; rt.planeHeight = CVPixelBufferGetHeightOfPlane; rt.attachment = CVBufferGetAttachment;
    rt.bufferColorSpace = CVImageBufferGetColorSpace;
    rt.matrixKey = &kCVImageBufferYCbCrMatrixKey; rt.matrix709 = &kCVImageBufferYCbCrMatrix_ITU_R_709_2;
    rt.matrix601 = &kCVImageBufferYCbCrMatrix_ITU_R_601_4; rt.chromaKey = &kCVImageBufferChromaLocationTopFieldKey;
    rt.chromaCenter = &kCVImageBufferChromaLocation_Center;
    (void)converter_dealloc;
    (void)format_dealloc;
}
#else
/// A provider's export: its native entry when it has one, else the Darwin name.
static void *lookup(void *handle, const char *name) {
    if (!handle) return NULL;
    char symbol[128];
    snprintf(symbol, sizeof symbol, "perry_native_%s", name);
    void *found = dlsym(handle, symbol);
    if (found) return found;
    snprintf(symbol, sizeof symbol, "_%s", name);
    return dlsym(handle, symbol);
}

#define BIND(handle, field, name) (*(void **)&rt.field = lookup(handle, name))

static void *make_class(const char *name, void (*dealloc)(void *, void *)) {
    void *base = rt.getClass ? rt.getClass("NSObject") : NULL;
    void *cls = base ? rt.allocateClassPair(base, name, 0) : NULL;
    if (!cls) return rt.getClass(name);
    rt.addMethod(cls, "dealloc", (void *)dealloc, "v16@0:8");
    rt.registerClassPair(cls);
    return cls;
}

static void load_runtime(void) {
    void *cg = dlopen("libPerryCoreGraphics.so", RTLD_NOW | RTLD_NOLOAD);
    BIND(cg, imageWidth, "CGImageGetWidth"); BIND(cg, imageHeight, "CGImageGetHeight");
    BIND(cg, imageBitsPerComponent, "CGImageGetBitsPerComponent"); BIND(cg, imageBitsPerPixel, "CGImageGetBitsPerPixel");
    BIND(cg, imageBytesPerRow, "CGImageGetBytesPerRow"); BIND(cg, imageBitmapInfo, "CGImageGetBitmapInfo");
    BIND(cg, imageColorSpace, "CGImageGetColorSpace"); BIND(cg, imageDataProvider, "CGImageGetDataProvider");
    BIND(cg, imageRenderingIntent, "CGImageGetRenderingIntent"); BIND(cg, providerCopyData, "CGDataProviderCopyData");
    BIND(cg, providerCreateWithData, "CGDataProviderCreateWithData"); BIND(cg, providerRelease, "CGDataProviderRelease");
    BIND(cg, imageCreate, "CGImageCreate"); BIND(cg, colorSpaceCreateDeviceRGB, "CGColorSpaceCreateDeviceRGB");
    BIND(cg, colorSpaceGetModel, "CGColorSpaceGetModel"); BIND(cg, colorSpaceComponents, "CGColorSpaceGetNumberOfComponents");
    BIND(cg, colorSpaceRetain, "CGColorSpaceRetain"); BIND(cg, colorSpaceRelease, "CGColorSpaceRelease");

    void *cf = dlopen("libPerryFoundation.so", RTLD_NOW | RTLD_NOLOAD);
    BIND(cf, dataBytes, "CFDataGetBytePtr"); BIND(cf, dataLength, "CFDataGetLength");
    BIND(cf, retain, "CFRetain"); BIND(cf, release, "CFRelease"); BIND(cf, equal, "CFEqual");

    // Core Video's pixel buffers are AVFoundation's provider's.
    void *cv = dlopen("libPerryAVFoundation.so", RTLD_NOW | RTLD_NOLOAD);
    BIND(cv, pixelFormat, "CVPixelBufferGetPixelFormatType"); BIND(cv, width, "CVPixelBufferGetWidth");
    BIND(cv, height, "CVPixelBufferGetHeight"); BIND(cv, bytesPerRow, "CVPixelBufferGetBytesPerRow");
    BIND(cv, lock, "CVPixelBufferLockBaseAddress"); BIND(cv, unlock, "CVPixelBufferUnlockBaseAddress");
    BIND(cv, isPlanar, "CVPixelBufferIsPlanar"); BIND(cv, planeCount, "CVPixelBufferGetPlaneCount");
    BIND(cv, base, "CVPixelBufferGetBaseAddress"); BIND(cv, planeBase, "CVPixelBufferGetBaseAddressOfPlane");
    BIND(cv, planeBytesPerRow, "CVPixelBufferGetBytesPerRowOfPlane"); BIND(cv, planeWidth, "CVPixelBufferGetWidthOfPlane");
    BIND(cv, planeHeight, "CVPixelBufferGetHeightOfPlane"); BIND(cv, attachment, "CVBufferGetAttachment");
    BIND(cv, bufferColorSpace, "CVImageBufferGetColorSpace");
    // The attachment keys, where the provider has them as data.
    rt.matrixKey = cv ? dlsym(cv, "_kCVImageBufferYCbCrMatrixKey") : NULL;
    rt.matrix709 = cv ? dlsym(cv, "_kCVImageBufferYCbCrMatrix_ITU_R_709_2") : NULL;
    rt.matrix601 = cv ? dlsym(cv, "_kCVImageBufferYCbCrMatrix_ITU_R_601_4") : NULL;
    rt.chromaKey = cv ? dlsym(cv, "_kCVImageBufferChromaLocationTopFieldKey") : NULL;
    rt.chromaCenter = cv ? dlsym(cv, "_kCVImageBufferChromaLocation_Center") : NULL;

    void *objc = dlopen("libPerryobjc.so", RTLD_NOW | RTLD_NOLOAD);
    if (!objc) return;
    rt.getClass = dlsym(objc, "_objc_getClass");
    rt.allocateClassPair = dlsym(objc, "_objc_allocateClassPair");
    rt.registerClassPair = dlsym(objc, "_objc_registerClassPair");
    rt.addMethod = dlsym(objc, "_class_addMethod");
    rt.createInstance = dlsym(objc, "_class_createInstance");
    rt.indexedIvars = dlsym(objc, "_object_getIndexedIvars");
    rt.registerName = dlsym(objc, "_sel_registerName");
    rt.msgSendSuper = dlsym(objc, "_objc_msgSendSuper2");
    if (!rt.getClass || !rt.allocateClassPair || !rt.registerClassPair || !rt.addMethod || !rt.createInstance || !rt.indexedIvars)
        return;
    rt.converterClass = make_class("vImageConverter", converter_dealloc);
    rt.formatClass = make_class("vImageCVImageFormat", format_dealloc);
}
#endif

static void load(void) { pthread_once(&rt.once, load_runtime); }

/// A new object of `cls` with `size` zeroed bytes of state, or NULL.
static void *make_object(void *cls, size_t size, void **state) {
#ifdef PERRY_ACCELERATE_TEST
    (void)cls;
    void *object = calloc(1, size);
    *state = object;
    return object;
#else
    if (!cls) return NULL;
    void *object = rt.createInstance(cls, size);
    *state = object ? rt.indexedIvars(object) : NULL;
    if (*state) memset(*state, 0, size);
    return *state ? object : NULL;
#endif
}

static void *state_of(void *object) {
#ifdef PERRY_ACCELERATE_TEST
    return object;
#else
    return object && rt.indexedIvars ? rt.indexedIvars(object) : NULL;
#endif
}

#ifndef PERRY_ACCELERATE_TEST
/// [super dealloc] for an instance of `cls`.
static void super_dealloc(void *self, void *cls) {
    if (!rt.msgSendSuper || !rt.registerName) return;
    struct { void *receiver; void *cls; } super = { self, cls };
    ((void (*)(void *, void *))rt.msgSendSuper)(&super, rt.registerName("dealloc"));
}
#endif

// MARK: - Pixel layouts

enum alpha_kind { AlphaNone, AlphaReal, AlphaSkip };
enum component { Uint8, Uint16, Half, Float32 };

/// One chunky pixel layout, from a vImage_CGImageFormat.
struct layout {
    enum component component;
    int componentBytes, pixelBytes;
    int colors;          // 1 (gray) or 3 (RGB)
    enum alpha_kind alpha;
    bool alphaFirst, premultiplied;
    bool reverse2, reverse4; // 8-bit components in 16- or 32-bit little-endian words
    bool littleComponents;   // 16- and 32-bit components' byte order
    bool bgr;                // colors stored blue first (Core Video's 24BGR alone)
};

static uint32_t alpha_info(uint32_t bitmapInfo) { return bitmapInfo & 0x1f; }

static int colorspace_colors(CGColorSpaceRef space) {
    if (!space) return 3;
    load();
    if (rt.colorSpaceComponents) return (int)rt.colorSpaceComponents(space);
    return 3;
}

/// The layout of `format`, or an error.
static vImage_Error describe(const vImage_CGImageFormat *format, struct layout *out) {
    if (!format) return kvImageNullPointerArgument;
    struct layout l = {0};
    uint32_t info = format->bitmapInfo, alpha = alpha_info(info), order = info & 0x7000;
    bool isFloat = info & 0x100;
    l.colors = colorspace_colors(format->colorSpace);
    if (l.colors != 1 && l.colors != 3) return kvImageUnsupportedConversion;
    if (alpha > 6) return kvImageUnsupportedConversion;
    switch (format->bitsPerComponent) {
    case 8: if (isFloat) return kvImageInvalidImageFormat; l.component = Uint8; l.componentBytes = 1; break;
    case 16: l.component = isFloat ? Half : Uint16; l.componentBytes = 2; break;
    case 32: if (!isFloat) return kvImageUnsupportedConversion; l.component = Float32; l.componentBytes = 4; break;
    default: return kvImageUnsupportedConversion;
    }
    l.alpha = alpha == 0 ? AlphaNone : alpha >= 5 ? AlphaSkip : AlphaReal;
    l.alphaFirst = alpha == 2 || alpha == 4 || alpha == 6;
    l.premultiplied = alpha == 1 || alpha == 2;
    int channels = l.colors + (l.alpha != AlphaNone);
    if (format->bitsPerPixel % 8 || (int)format->bitsPerPixel < channels * (int)format->bitsPerComponent || format->bitsPerPixel > 128)
        return kvImageInvalidImageFormat;
    l.pixelBytes = (int)format->bitsPerPixel / 8;
    if (l.component == Uint8) {
        if (order == 0x2000) { if (l.pixelBytes % 4) return kvImageInvalidImageFormat; l.reverse4 = true; }
        if (order == 0x1000) { if (l.pixelBytes % 2) return kvImageInvalidImageFormat; l.reverse2 = true; }
    } else l.littleComponents = order == 0x1000 || order == 0x2000;
    *out = l;
    return kvImageNoError;
}

/// A pixel's channels as stored, colors then alpha, in floating point
/// (integers scaled to 0...1). Returns alpha, or 1 if there is none.
static void decode(const struct layout *l, const uint8_t *p, float rgba[4]) {
    uint8_t bytes[16];
    memcpy(bytes, p, (size_t)l->pixelBytes);
    if (l->reverse4)
        for (int i = 0; i + 3 < l->pixelBytes; i += 4) {
            uint8_t t = bytes[i]; bytes[i] = bytes[i + 3]; bytes[i + 3] = t;
            t = bytes[i + 1]; bytes[i + 1] = bytes[i + 2]; bytes[i + 2] = t;
        }
    if (l->reverse2)
        for (int i = 0; i + 1 < l->pixelBytes; i += 2) { uint8_t t = bytes[i]; bytes[i] = bytes[i + 1]; bytes[i + 1] = t; }
    float values[4];
    int channels = l->colors + (l->alpha != AlphaNone);
    for (int c = 0; c < channels; c++) {
        const uint8_t *q = bytes + c * l->componentBytes;
        switch (l->component) {
        case Uint8: values[c] = q[0] / 255.0f; break;
        case Uint16: {
            uint16_t v = l->littleComponents ? (uint16_t)(q[0] | q[1] << 8) : (uint16_t)(q[0] << 8 | q[1]);
            values[c] = v / 65535.0f;
            break;
        }
        case Half: {
            uint16_t v = l->littleComponents ? (uint16_t)(q[0] | q[1] << 8) : (uint16_t)(q[0] << 8 | q[1]);
            values[c] = perry_vimage_half_to_float(v);
            break;
        }
        case Float32: {
            uint32_t v = l->littleComponents ? (uint32_t)(q[0] | q[1] << 8 | q[2] << 16 | (uint32_t)q[3] << 24)
                                             : (uint32_t)((uint32_t)q[0] << 24 | q[1] << 16 | q[2] << 8 | q[3]);
            memcpy(&values[c], &v, 4);
            break;
        }
        }
    }
    int first = l->alpha != AlphaNone && l->alphaFirst ? 1 : 0;
    for (int c = 0; c < 3; c++) rgba[c] = values[first + (l->colors == 3 ? (l->bgr ? 2 - c : c) : 0)];
    rgba[3] = l->alpha != AlphaNone ? values[l->alphaFirst ? 0 : l->colors] : 1.0f;
}

static uint8_t encode8(float v) {
    if (!(v > 0)) return 0;
    if (v >= 1) return 255;
    return (uint8_t)nearbyintf(v * 255.0f);
}

static uint16_t encode16(float v) {
    if (!(v > 0)) return 0;
    if (v >= 1) return 65535;
    return (uint16_t)nearbyintf(v * 65535.0f);
}

/// Writes colors (gray from RGB by luma) and alpha in `l`'s layout.
static void encode(const struct layout *l, const float rgba[4], uint8_t *p) {
    float values[4];
    int channels = 0;
    float alpha = l->alpha != AlphaNone ? rgba[3] : 1.0f;
    if (l->alpha != AlphaNone && l->alphaFirst) values[channels++] = alpha;
    if (l->colors == 3) for (int c = 0; c < 3; c++) values[channels++] = rgba[l->bgr ? 2 - c : c];
    else values[channels++] = 0.2126f * rgba[0] + 0.7152f * rgba[1] + 0.0722f * rgba[2];
    if (l->alpha != AlphaNone && !l->alphaFirst) values[channels++] = alpha;
    uint8_t bytes[16] = {0};
    for (int c = 0; c < channels; c++) {
        uint8_t *q = bytes + c * l->componentBytes;
        uint32_t v;
        switch (l->component) {
        case Uint8: q[0] = encode8(values[c]); continue;
        case Uint16: v = encode16(values[c]); break;
        case Half: v = perry_vimage_float_to_half(values[c]); break;
        default: memcpy(&v, &values[c], 4); break;
        }
        for (int i = 0; i < l->componentBytes; i++)
            q[i] = (uint8_t)(l->littleComponents ? v >> (8 * i) : v >> (8 * (l->componentBytes - 1 - i)));
    }
    if (l->reverse4)
        for (int i = 0; i + 3 < l->pixelBytes; i += 4) {
            uint8_t t = bytes[i]; bytes[i] = bytes[i + 3]; bytes[i + 3] = t;
            t = bytes[i + 1]; bytes[i + 1] = bytes[i + 2]; bytes[i + 2] = t;
        }
    if (l->reverse2)
        for (int i = 0; i + 1 < l->pixelBytes; i += 2) { uint8_t t = bytes[i]; bytes[i] = bytes[i + 1]; bytes[i + 1] = t; }
    memcpy(p, bytes, (size_t)l->pixelBytes);
}

// MARK: - Core Video formats

enum cv_kind { CVChunky, CV420, CV422 };

/// What we know of a Core Video pixel format.
struct cv_info {
    uint32_t code;
    enum cv_kind kind;
    vImage_CGImageFormat chunky; // for CVChunky, with a NULL color space
    bool bgr;                    // 24BGR: colors reversed
    bool fullRange;
    int lumaFirst;               // 422: 1 for Y0 Cb Y1 Cr, 0 for Cb Y0 Cr Y1
    int channelCount;
    vImageBufferTypeCode names[5];
};

#define FOURCC(a, b, c, d) ((uint32_t)(a) << 24 | (uint32_t)(b) << 16 | (uint32_t)(c) << 8 | (uint32_t)(d))

static const struct cv_info cv_formats[] = {
    { FOURCC('B', 'G', 'R', 'A'), CVChunky, {8, 32, NULL, 4 | 0x2000, 0, NULL, 0}, false, false, 0, 4, {3, 2, 1, 17} },
    { 32, CVChunky, {8, 32, NULL, 4, 0, NULL, 0}, false, false, 0, 4, {17, 1, 2, 3} },
    { FOURCC('R', 'G', 'B', 'A'), CVChunky, {8, 32, NULL, 3, 0, NULL, 0}, false, false, 0, 4, {1, 2, 3, 17} },
    { FOURCC('A', 'B', 'G', 'R'), CVChunky, {8, 32, NULL, 3 | 0x2000, 0, NULL, 0}, false, false, 0, 4, {17, 3, 2, 1} },
    { 24, CVChunky, {8, 24, NULL, 0, 0, NULL, 0}, false, false, 0, 3, {1, 2, 3} },
    { FOURCC('2', '4', 'B', 'G'), CVChunky, {8, 24, NULL, 0, 0, NULL, 0}, true, false, 0, 3, {3, 2, 1} },
    { FOURCC('L', '0', '0', '8'), CVChunky, {8, 8, NULL, 0, 0, NULL, 0}, false, false, 0, 1, {1} },
    { FOURCC('R', 'G', 'f', 'A'), CVChunky, {32, 128, NULL, 3 | 0x100 | 0x2000, 0, NULL, 0}, false, false, 0, 4, {1, 2, 3, 17} },
    { FOURCC('R', 'G', 'h', 'A'), CVChunky, {16, 64, NULL, 3 | 0x100 | 0x1000, 0, NULL, 0}, false, false, 0, 4, {1, 2, 3, 17} },
    { FOURCC('4', '2', '0', 'v'), CV420, {0}, false, false, 0, 3, {20, 22, 23} },
    { FOURCC('4', '2', '0', 'f'), CV420, {0}, false, true, 0, 3, {20, 22, 23} },
    { FOURCC('2', 'v', 'u', 'y'), CV422, {0}, false, false, 0, 3, {22, 20, 23} },
    { FOURCC('y', 'u', 'v', 's'), CV422, {0}, false, false, 1, 3, {20, 22, 23} },
    { FOURCC('y', 'u', 'v', 'f'), CV422, {0}, false, true, 1, 3, {20, 22, 23} },
};

static const struct cv_info *cv_lookup(uint32_t code) {
    for (size_t i = 0; i < sizeof cv_formats / sizeof cv_formats[0]; i++)
        if (cv_formats[i].code == code) return &cv_formats[i];
    return NULL;
}

/// A vImageCVImageFormat's state.
struct cv_format {
    const struct cv_info *info;
    vImage_ARGBToYpCbCrMatrix matrix;
    bool hasMatrix;
    CFStringRef chromaSiting;
    CGColorSpaceRef colorSpace;
    int alphaHint;
    vImageChannelDescription descriptions[4];
};

static void format_release_contents(struct cv_format *f) {
    if (f->chromaSiting && rt.release) rt.release(f->chromaSiting);
    if (f->colorSpace && rt.colorSpaceRelease) rt.colorSpaceRelease(f->colorSpace);
    f->chromaSiting = NULL;
    f->colorSpace = NULL;
}

static void format_dealloc(void *self, void *cmd) {
    struct cv_format *f = state_of(self);
    if (f) format_release_contents(f);
#ifdef PERRY_ACCELERATE_TEST
    free(self);
#else
    super_dealloc(self, rt.formatClass);
#endif
}

static bool yuv(const struct cv_info *info) { return info->kind != CVChunky; }

EXPORT(void *, vImageCVImageFormat_Create, (uint32_t imageFormatType, const vImage_ARGBToYpCbCrMatrix *matrix,
                                            CFStringRef cvImageBufferChromaLocation, CGColorSpaceRef baseColorspace,
                                            int alphaIsOneHint)) {
    const struct cv_info *info = cv_lookup(imageFormatType);
    if (!info) return NULL;
    load();
    // A color space must have the format's color channels.
    if (baseColorspace && info->kind == CVChunky && colorspace_colors(baseColorspace) != (info->channelCount >= 3 ? 3 : 1)) return NULL;
    if (info->kind == CVChunky) {
        // Matrix and chroma siting are Y'CbCr's alone.
        matrix = NULL;
        cvImageBufferChromaLocation = NULL;
    }
    struct cv_format *f;
    void *object = make_object(rt.formatClass, sizeof *f, (void **)&f);
    if (!object) return NULL;
    f->info = info;
    if (matrix) { f->matrix = *matrix; f->hasMatrix = true; }
    if (cvImageBufferChromaLocation) f->chromaSiting = rt.retain ? rt.retain(cvImageBufferChromaLocation) : cvImageBufferChromaLocation;
    if (baseColorspace) f->colorSpace = rt.colorSpaceRetain ? rt.colorSpaceRetain(baseColorspace) : baseColorspace;
    bool hasAlpha = false;
    for (int i = 0; i < info->channelCount; i++) hasAlpha |= info->names[i] == TypeAlpha;
    f->alphaHint = hasAlpha ? alphaIsOneHint : 2;
    for (int i = 0; i < info->channelCount; i++) {
        vImageChannelDescription d = {0, 0, 255, 255};
        if (info->code == FOURCC('R', 'G', 'f', 'A') || info->code == FOURCC('R', 'G', 'h', 'A'))
            d = (vImageChannelDescription){-INFINITY, 0, 1, INFINITY};
        else if (info->names[i] == TypeLuminance) d = info->fullRange ? (vImageChannelDescription){0, 0, 255, 255}
                                                                       : (vImageChannelDescription){0, 16, 235, 255};
        else if (info->names[i] == TypeCb || info->names[i] == TypeCr)
            d = info->fullRange ? (vImageChannelDescription){0, 128, 255, 255} : (vImageChannelDescription){0, 128, 240, 255};
        f->descriptions[i] = d;
    }
    return object;
}

EXPORT(void *, vImageCVImageFormat_CreateWithCVPixelBuffer, (CVPixelBufferRef buffer)) {
    if (!buffer) return NULL;
    load();
    if (!rt.pixelFormat) return NULL;
    uint32_t code = rt.pixelFormat(buffer);
    const struct cv_info *info = cv_lookup(code);
    if (!info) return NULL;
    // What the buffer's attachments say; where a Y'CbCr buffer says
    // nothing, Rec. 601 and centered chroma (Perry's buffers carry none).
    const vImage_ARGBToYpCbCrMatrix *matrix = NULL;
    CFStringRef siting = NULL;
    bool attached = false;
    if (yuv(info)) {
        matrix = perry_vimage_matrix_601;
        if (rt.attachment && rt.matrixKey && *rt.matrixKey) {
            void *value = rt.attachment(buffer, *rt.matrixKey, NULL);
            if (value && rt.equal && rt.matrix709 && *rt.matrix709 && rt.equal(value, *rt.matrix709)) matrix = perry_vimage_matrix_709;
            attached = value != NULL;
        }
        if (rt.attachment && rt.chromaKey && *rt.chromaKey) siting = rt.attachment(buffer, *rt.chromaKey, NULL);
        if (!siting && rt.chromaCenter) siting = *rt.chromaCenter;
    }
    (void)attached;
    CGColorSpaceRef space = rt.bufferColorSpace ? rt.bufferColorSpace(buffer) : NULL;
    CGColorSpaceRef made = NULL;
    if (!space && rt.colorSpaceCreateDeviceRGB && info->channelCount >= 3) space = made = rt.colorSpaceCreateDeviceRGB();
    void *format = vImageCVImageFormat_Create(code, matrix, siting, space, 0);
    if (made && rt.colorSpaceRelease) rt.colorSpaceRelease(made);
    return format;
}

EXPORT(int, vImageCVImageFormat_GetAlphaHint, (const void *format)) {
    struct cv_format *f = state_of((void *)format);
    return f ? f->alphaHint : 0;
}

EXPORT(vImage_Error, vImageCVImageFormat_SetAlphaHint, (void *format, int alphaIsOne)) {
    struct cv_format *f = state_of(format);
    if (!f) return kvImageNullPointerArgument;
    if (f->alphaHint != 2) f->alphaHint = alphaIsOne; // formats without alpha keep 2
    return kvImageNoError;
}

EXPORT(uint32_t, vImageCVImageFormat_GetChannelCount, (const void *format)) {
    struct cv_format *f = state_of((void *)format);
    return f ? (uint32_t)f->info->channelCount : 0;
}

EXPORT(const vImageBufferTypeCode *, vImageCVImageFormat_GetChannelNames, (const void *format)) {
    struct cv_format *f = state_of((void *)format);
    return f ? f->info->names : NULL;
}

EXPORT(const vImageChannelDescription *, vImageCVImageFormat_GetChannelDescription, (const void *format, vImageBufferTypeCode type)) {
    struct cv_format *f = state_of((void *)format);
    if (!f) return NULL;
    for (int i = 0; i < f->info->channelCount; i++)
        if (f->info->names[i] == type) return &f->descriptions[i];
    return NULL;
}

EXPORT(CFStringRef, vImageCVImageFormat_GetChromaSiting, (const void *format)) {
    struct cv_format *f = state_of((void *)format);
    return f ? f->chromaSiting : NULL;
}

EXPORT(vImage_Error, vImageCVImageFormat_SetChromaSiting, (void *format, CFStringRef siting)) {
    struct cv_format *f = state_of(format);
    if (!f) return kvImageNullPointerArgument;
    if (siting && rt.retain) rt.retain(siting);
    if (f->chromaSiting && rt.release) rt.release(f->chromaSiting);
    f->chromaSiting = siting;
    return kvImageNoError;
}

EXPORT(CGColorSpaceRef, vImageCVImageFormat_GetColorSpace, (const void *format)) {
    struct cv_format *f = state_of((void *)format);
    return f ? f->colorSpace : NULL;
}

EXPORT(vImage_Error, vImageCVImageFormat_SetColorSpace, (void *format, CGColorSpaceRef colorspace)) {
    struct cv_format *f = state_of(format);
    if (!f) return kvImageNullPointerArgument;
    if (colorspace && rt.colorSpaceRetain) rt.colorSpaceRetain(colorspace);
    if (f->colorSpace && rt.colorSpaceRelease) rt.colorSpaceRelease(f->colorSpace);
    f->colorSpace = colorspace;
    return kvImageNoError;
}

EXPORT(uint32_t, vImageCVImageFormat_GetFormatCode, (const void *format)) {
    struct cv_format *f = state_of((void *)format);
    return f ? f->info->code : 0;
}

// MARK: - Converters

enum side_kind { SideCG, SideCV };

/// One side of a conversion: a chunky layout, or a Y'CbCr CV format.
struct side {
    enum side_kind kind;
    struct layout layout;          // CG formats and chunky CV formats
    const struct cv_info *cv;
    float toRGB[3][3], fromRGB[3][3]; // Y'CbCr formats: RGB <-> (Y', Cb, Cr)
    float yZero, yRange, cZero, cRange;
    vImageBufferTypeCode order[3];
    int buffers;
};

struct converter {
    struct side src, dest;
    float background[3];
    unsigned background8[3];
};

static void converter_dealloc(void *self, void *cmd) {
#ifdef PERRY_ACCELERATE_TEST
    free(self);
#else
    super_dealloc(self, rt.converterClass);
#endif
}

static void set_error(vImage_Error *error, vImage_Error value) {
    if (error) *error = value;
}

static vImage_Error side_from_cg(const vImage_CGImageFormat *format, struct side *side) {
    if (!format) return kvImageNullPointerArgument;
    if (format->decode) return kvImageInvalidParameter;
    side->kind = SideCG;
    side->order[0] = TypeCGFormat;
    side->order[1] = TypeEnd;
    side->buffers = 1;
    return describe(format, &side->layout);
}

static void invert3(const float m[3][3], float out[3][3]) {
    float a = m[0][0], b = m[0][1], c = m[0][2], d = m[1][0], e = m[1][1], f = m[1][2], g = m[2][0], h = m[2][1], i = m[2][2];
    float det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
    out[0][0] = (e * i - f * h) / det; out[0][1] = (c * h - b * i) / det; out[0][2] = (b * f - c * e) / det;
    out[1][0] = (f * g - d * i) / det; out[1][1] = (a * i - c * g) / det; out[1][2] = (c * d - a * f) / det;
    out[2][0] = (d * h - e * g) / det; out[2][1] = (b * g - a * h) / det; out[2][2] = (a * e - b * d) / det;
}

static vImage_Error side_from_cv(const void *format, struct side *side) {
    struct cv_format *f = state_of((void *)format);
    if (!f) return kvImageNullPointerArgument;
    side->kind = SideCV;
    side->cv = f->info;
    if (!f->colorSpace) return FormatErrorColorSpace;
    if (f->info->kind == CVChunky) {
        vImage_CGImageFormat chunky = f->info->chunky;
        chunky.colorSpace = f->colorSpace;
        side->order[0] = f->info->bgr ? TypeChunky : TypeCGFormat; // 24BGR has no CG equivalent
        side->order[1] = TypeEnd;
        side->buffers = 1;
        vImage_Error error = describe(&chunky, &side->layout);
        side->layout.bgr = f->info->bgr;
        return error;
    }
    if (f->info->kind == CV420 && !f->chromaSiting) return FormatErrorChromaSiting;
    if (!f->hasMatrix) return FormatErrorMatrix;
    const vImage_ARGBToYpCbCrMatrix *m = &f->matrix;
    float forward[3][3] = {
        {m->R_Yp, m->G_Yp, m->B_Yp},
        {m->R_Cb, m->G_Cb, m->B_Cb_R_Cr},
        {m->B_Cb_R_Cr, m->G_Cr, m->B_Cr},
    };
    memcpy(side->fromRGB, forward, sizeof forward);
    invert3(forward, side->toRGB);
    side->yZero = (float)f->descriptions[f->info->names[0] == TypeLuminance ? 0 : 1].zero;
    const vImageChannelDescription *luma = NULL, *chroma = NULL;
    for (int i = 0; i < 3; i++) {
        if (f->info->names[i] == TypeLuminance) luma = &f->descriptions[i];
        if (f->info->names[i] == TypeCb) chroma = &f->descriptions[i];
    }
    side->yZero = (float)luma->zero;
    side->yRange = (float)(luma->full - luma->zero);
    side->cZero = (float)chroma->zero;
    side->cRange = (float)(chroma->full - chroma->zero) * 2;
    if (f->info->kind == CV420) {
        side->order[0] = TypeLuminance;
        side->order[1] = TypeChroma;
        side->order[2] = TypeEnd;
        side->buffers = 2;
    } else {
        side->order[0] = TypeYCbCr;
        side->order[1] = TypeEnd;
        side->buffers = 1;
    }
    return kvImageNoError;
}

static void *make_converter(const struct side *src, const struct side *dest, const CGFloat *background, vImage_Error *error) {
    load();
    struct converter *c;
    void *object = make_object(rt.converterClass, sizeof *c, (void **)&c);
    if (!object) {
        set_error(error, kvImageMemoryAllocationError);
        return NULL;
    }
    c->src = *src;
    c->dest = *dest;
    for (int i = 0; i < 3; i++) c->background[i] = background ? (float)background[i] : 0;
    // A gray destination's background is one value.
    if (dest->kind == SideCG && dest->layout.colors == 1 && background)
        c->background[1] = c->background[2] = c->background[0];
    for (int i = 0; i < 3; i++) {
        float v = c->background[i] * 255;
        c->background8[i] = v <= 0 ? 0 : v >= 255 ? 255 : (unsigned)nearbyintf(v);
    }
    set_error(error, kvImageNoError);
    return object;
}

EXPORT(void *, vImageConverter_CreateWithCGImageFormat, (const vImage_CGImageFormat *srcFormat, const vImage_CGImageFormat *destFormat,
                                                         const CGFloat *backgroundColor, vImage_Flags flags, vImage_Error *error)) {
    struct side src, dest;
    vImage_Error e = side_from_cg(srcFormat, &src);
    if (!e) e = side_from_cg(destFormat, &dest);
    if (e) {
        set_error(error, e);
        return NULL;
    }
    return make_converter(&src, &dest, backgroundColor, error);
}

/// The color conversion info is not used: color spaces are matched by model only.
EXPORT(void *, vImageConverter_CreateWithCGColorConversionInfo, (void *colorConversionInfoRef, const vImage_CGImageFormat *sFormat,
                                                                 const vImage_CGImageFormat *dFormat, const CGFloat *bg,
                                                                 vImage_Flags flags, vImage_Error *error)) {
    return vImageConverter_CreateWithCGImageFormat(sFormat, dFormat, bg, flags, error);
}

EXPORT(void *, vImageConverter_CreateForCGToCVImageFormat, (const vImage_CGImageFormat *srcFormat, void *destFormat,
                                                            const CGFloat *backgroundColor, vImage_Flags flags, vImage_Error *error)) {
    struct side src, dest;
    if (!srcFormat || !srcFormat->colorSpace) {
        set_error(error, srcFormat ? kvImageInvalidImageFormat : kvImageNullPointerArgument);
        return NULL;
    }
    vImage_Error e = side_from_cg(srcFormat, &src);
    if (!e) e = destFormat ? side_from_cv(destFormat, &dest) : kvImageInvalidCVImageFormat;
    if (e) {
        set_error(error, e);
        return NULL;
    }
    return make_converter(&src, &dest, backgroundColor, error);
}

EXPORT(void *, vImageConverter_CreateForCVToCGImageFormat, (void *srcFormat, const vImage_CGImageFormat *destFormat,
                                                            const CGFloat *backgroundColor, vImage_Flags flags, vImage_Error *error)) {
    struct side src, dest;
    vImage_Error e = srcFormat ? side_from_cv(srcFormat, &src) : kvImageInvalidCVImageFormat;
    if (!e) e = side_from_cg(destFormat, &dest);
    if (e) {
        set_error(error, e);
        return NULL;
    }
    return make_converter(&src, &dest, backgroundColor, error);
}

EXPORT(unsigned long, vImageConverter_GetNumberOfSourceBuffers, (const void *converter)) {
    struct converter *c = state_of((void *)converter);
    return c ? (unsigned long)c->src.buffers : 0;
}

EXPORT(unsigned long, vImageConverter_GetNumberOfDestinationBuffers, (const void *converter)) {
    struct converter *c = state_of((void *)converter);
    return c ? (unsigned long)c->dest.buffers : 0;
}

EXPORT(const vImageBufferTypeCode *, vImageConverter_GetSourceBufferOrder, (void *converter)) {
    struct converter *c = state_of(converter);
    return c ? c->src.order : NULL;
}

EXPORT(const vImageBufferTypeCode *, vImageConverter_GetDestinationBufferOrder, (void *converter)) {
    struct converter *c = state_of(converter);
    return c ? c->dest.order : NULL;
}

static int side_pixel_bytes(const struct side *s) {
    if (s->kind == SideCG || s->cv->kind == CVChunky) return s->layout.pixelBytes;
    return s->cv->kind == CV422 ? 2 : 1;
}

/// In place works when each destination pixel is no larger than its source pixel.
EXPORT(vImage_Error, vImageConverter_MustOperateOutOfPlace, (const void *converter, const vImage_Buffer *srcs, const vImage_Buffer *dests,
                                                             vImage_Flags flags)) {
    struct converter *c = state_of((void *)converter);
    if (!c) return kvImageNullPointerArgument;
    // As vImage answers: by pixel sizes alone, whatever the buffers.
    if (side_pixel_bytes(&c->dest) > side_pixel_bytes(&c->src) || c->src.buffers != c->dest.buffers)
        return kvImageOutOfPlaceOperationRequired;
    return kvImageNoError;
}

/// Y'CbCr codes to RGB.
static void yuv_to_rgb(const struct side *s, float y, float cb, float cr, float rgb[3]) {
    float v[3] = {(y - s->yZero) / s->yRange, (cb - s->cZero) / s->cRange, (cr - s->cZero) / s->cRange};
    for (int i = 0; i < 3; i++) rgb[i] = s->toRGB[i][0] * v[0] + s->toRGB[i][1] * v[1] + s->toRGB[i][2] * v[2];
}

static uint8_t code8(float v) {
    if (!(v > 0)) return 0;
    if (v >= 255) return 255;
    return (uint8_t)nearbyintf(v);
}

/// RGB to Y'CbCr codes.
static void rgb_to_yuv(const struct side *s, const float rgb[3], float out[3]) {
    float v[3];
    for (int i = 0; i < 3; i++) v[i] = s->fromRGB[i][0] * rgb[0] + s->fromRGB[i][1] * rgb[1] + s->fromRGB[i][2] * rgb[2];
    out[0] = s->yZero + v[0] * s->yRange;
    out[1] = s->cZero + v[1] * s->cRange;
    out[2] = s->cZero + v[2] * s->cRange;
}

/// Source pixel (x, y) as straight RGBA, flattened onto the background
/// when the destination has no alpha.
static void read_pixel(const struct converter *c, const vImage_Buffer *srcs, vImagePixelCount x, vImagePixelCount y, float rgba[4]) {
    const struct side *s = &c->src;
    if (s->kind == SideCG || s->cv->kind == CVChunky) {
        decode(&s->layout, vimage_pixel(&srcs[0], x, y, (size_t)s->layout.pixelBytes), rgba);
        bool chunkyDest = c->dest.kind == SideCG || c->dest.cv->kind == CVChunky;
        bool destAlpha = chunkyDest && c->dest.layout.alpha == AlphaReal;
        // A skipped channel carries over into a skipped channel; otherwise it is opaque.
        if (s->layout.alpha != AlphaReal && !(s->layout.alpha == AlphaSkip && chunkyDest && c->dest.layout.alpha == AlphaSkip))
            rgba[3] = 1;
        if (s->layout.alpha == AlphaReal && s->layout.component == Uint8 && chunkyDest && c->dest.layout.component == Uint8) {
            // Byte to byte: vImage's integer formulas.
            unsigned a = (unsigned)nearbyintf(rgba[3] * 255), v[3];
            for (int i = 0; i < 3; i++) v[i] = (unsigned)nearbyintf(rgba[i] * 255);
            if (!destAlpha) {
                for (int i = 0; i < 3; i++) {
                    unsigned back = c->background8[i];
                    if (s->layout.premultiplied) {
                        unsigned color = (v[i] < a ? v[i] : a) + ((255 - a) * back + 127) / 255;
                        v[i] = color > 255 ? 255 : color;
                    } else v[i] = (v[i] * a + (255 - a) * back + 127) / 255;
                }
                a = 255;
            } else if (s->layout.premultiplied && !c->dest.layout.premultiplied) {
                for (int i = 0; i < 3; i++) v[i] = a ? ((v[i] < a ? v[i] : a) * 255 + a / 2) / a : 0;
            } else if (!s->layout.premultiplied && c->dest.layout.premultiplied) {
                for (int i = 0; i < 3; i++) v[i] = (v[i] * a + 127) / 255;
            }
            for (int i = 0; i < 3; i++) rgba[i] = (float)v[i] / 255.0f;
            rgba[3] = (float)a / 255.0f;
            return;
        }
        if (s->layout.alpha == AlphaReal) {
            float a = rgba[3];
            if (!destAlpha) {
                // Flatten onto the background.
                for (int i = 0; i < 3; i++) {
                    float color = s->layout.premultiplied ? fminf(rgba[i], a) : rgba[i] * a;
                    rgba[i] = color + (1 - a) * c->background[i];
                }
                rgba[3] = 1;
            } else if (s->layout.premultiplied && !c->dest.layout.premultiplied) {
                for (int i = 0; i < 3; i++) rgba[i] = a > 0 ? fminf(rgba[i], a) / a : 0;
            } else if (!s->layout.premultiplied && c->dest.layout.premultiplied) {
                for (int i = 0; i < 3; i++) rgba[i] *= a;
            }
        }
        return;
    }
    float yp, cb, cr;
    if (s->cv->kind == CV420) {
        yp = *vimage_pixel(&srcs[0], x, y, 1);
        const uint8_t *chroma = vimage_pixel(&srcs[1], x / 2, y / 2, 2);
        cb = chroma[0];
        cr = chroma[1];
    } else {
        const uint8_t *pair = vimage_pixel(&srcs[0], x & ~(vImagePixelCount)1, y, 2);
        if (s->cv->lumaFirst) { yp = pair[(x & 1) ? 2 : 0]; cb = pair[1]; cr = pair[3]; }
        else { yp = pair[(x & 1) ? 3 : 1]; cb = pair[0]; cr = pair[2]; }
    }
    yuv_to_rgb(s, yp, cb, cr, rgba);
    rgba[3] = 1;
}

static vImage_Error convert_to_yuv(const struct converter *c, const vImage_Buffer *srcs, const vImage_Buffer *dests) {
    const struct side *d = &c->dest;
    vImagePixelCount width = dests[0].width, height = dests[0].height;
    if (srcs[0].width < width || srcs[0].height < height) return kvImageRoiLargerThanInputBuffer;
    if (d->cv->kind == CV420) {
        if (!dests[1].data) return kvImageNullPointerArgument;
        for (vImagePixelCount y = 0; y < height; y += 2)
            for (vImagePixelCount x = 0; x < width; x += 2) {
                float sum[2] = {0, 0};
                int count = 0;
                for (vImagePixelCount j = y; j < y + 2 && j < height; j++)
                    for (vImagePixelCount i = x; i < x + 2 && i < width; i++) {
                        float rgba[4], ycc[3];
                        read_pixel(c, srcs, i, j, rgba);
                        rgb_to_yuv(d, rgba, ycc);
                        *vimage_pixel(&dests[0], i, j, 1) = code8(ycc[0]);
                        sum[0] += ycc[1];
                        sum[1] += ycc[2];
                        count++;
                    }
                uint8_t *chroma = vimage_pixel(&dests[1], x / 2, y / 2, 2);
                chroma[0] = code8(sum[0] / (float)count);
                chroma[1] = code8(sum[1] / (float)count);
            }
        return kvImageNoError;
    }
    for (vImagePixelCount y = 0; y < height; y++)
        for (vImagePixelCount x = 0; x < width; x += 2) {
            float ycc[2][3], rgba[4];
            read_pixel(c, srcs, x, y, rgba);
            rgb_to_yuv(d, rgba, ycc[0]);
            if (x + 1 < width) {
                read_pixel(c, srcs, x + 1, y, rgba);
                rgb_to_yuv(d, rgba, ycc[1]);
            } else memcpy(ycc[1], ycc[0], sizeof ycc[0]);
            uint8_t *pair = vimage_pixel(&dests[0], x, y, 2);
            uint8_t y0 = code8(ycc[0][0]), y1 = code8(ycc[1][0]);
            uint8_t cb = code8((ycc[0][1] + ycc[1][1]) / 2), cr = code8((ycc[0][2] + ycc[1][2]) / 2);
            uint8_t out[4];
            if (d->cv->lumaFirst) { out[0] = y0; out[1] = cb; out[2] = y1; out[3] = cr; }
            else { out[0] = cb; out[1] = y0; out[2] = cr; out[3] = y1; }
            memcpy(pair, out, x + 1 < width ? 4 : 2);
        }
    return kvImageNoError;
}

EXPORT(vImage_Error, vImageConvert_AnyToAny, (const void *converter, const vImage_Buffer *srcs, const vImage_Buffer *dests,
                                              void *tempBuffer, vImage_Flags flags)) {
    if (flags & kvImageGetTempBufferSize) return 0;
    struct converter *c = state_of((void *)converter);
    if (!c || !srcs || !dests) return kvImageNullPointerArgument;
    for (int i = 0; i < c->src.buffers; i++)
        if (!srcs[i].data) return kvImageNullPointerArgument;
    if (!dests[0].data) return kvImageNullPointerArgument;
    if (c->dest.kind == SideCV && c->dest.cv->kind != CVChunky) return convert_to_yuv(c, srcs, dests);
    vImagePixelCount width = dests[0].width, height = dests[0].height;
    if (srcs[0].width < width || srcs[0].height < height) return kvImageRoiLargerThanInputBuffer;
    const struct layout *out = &c->dest.layout;
    // Rows are converted through a copy so that a destination sharing
    // the source's memory reads each source row before it is written.
    for (vImagePixelCount y = 0; y < height; y++) {
        for (vImagePixelCount x = 0; x < width; x++) {
            float rgba[4];
            read_pixel(c, srcs, x, y, rgba);
            encode(out, rgba, vimage_pixel(&dests[0], x, y, (size_t)out->pixelBytes));
        }
    }
    return kvImageNoError;
}

// MARK: - Core Graphics images

EXPORT(uint32_t, vImageCGImageFormat_GetComponentCount, (const vImage_CGImageFormat *format)) {
    if (!format) return 0;
    uint32_t alpha = alpha_info(format->bitmapInfo);
    return (uint32_t)colorspace_colors(format->colorSpace) + (alpha >= 1 && alpha <= 6 ? 1 : 0);
}

/// Rows padded to 16 bytes, as vImageBuffer_Init does.
static vImage_Error allocate(vImage_Buffer *buffer, vImagePixelCount width, vImagePixelCount height, uint32_t bitsPerPixel) {
    size_t row = ((size_t)width * bitsPerPixel + 7) / 8;
    row = (row + 15) / 16 * 16;
    buffer->width = width;
    buffer->height = height;
    buffer->rowBytes = row;
    buffer->data = malloc(row * height ? row * height : 1);
    return buffer->data ? kvImageNoError : kvImageMemoryAllocationError;
}

EXPORT(vImage_Error, vImageBuffer_InitWithCGImage, (vImage_Buffer *buf, vImage_CGImageFormat *format, const CGFloat *backgroundColor,
                                                    CGImageRef image, vImage_Flags flags)) {
    if (!buf || !format || !image) return kvImageNullPointerArgument;
    load();
    if (!rt.imageWidth || !rt.providerCopyData || !rt.dataBytes) return kvImageInternalError;
    if (format->decode) return kvImageInvalidParameter;
    vImage_CGImageFormat source = {
        (uint32_t)rt.imageBitsPerComponent(image), (uint32_t)rt.imageBitsPerPixel(image), rt.imageColorSpace(image),
        rt.imageBitmapInfo(image), 0, NULL, rt.imageRenderingIntent ? rt.imageRenderingIntent(image) : 0,
    };
    if (format->bitsPerComponent == 0) {
        // The image's own format.
        *format = source;
        if (format->colorSpace && rt.colorSpaceRetain) rt.colorSpaceRetain(format->colorSpace);
    }
    vImagePixelCount width = rt.imageWidth(image), height = rt.imageHeight(image);
    vImage_Error error = kvImageNoError;
    void *converter = vImageConverter_CreateWithCGImageFormat(&source, format, backgroundColor, flags, &error);
    if (!converter) {
        if (!(flags & kvImageNoAllocate)) buf->data = NULL;
        return error;
    }
    void *data = rt.providerCopyData(rt.imageDataProvider(image));
    if (!data) {
        error = kvImageInvalidImageObject;
        goto done;
    }
    if (flags & kvImageNoAllocate) {
        if (buf->width < width || buf->height < height) { error = kvImageBufferSizeMismatch; goto done; }
    } else if ((error = allocate(buf, width, height, format->bitsPerPixel))) goto done;
    vImage_Buffer src = {(void *)rt.dataBytes(data), height, width, rt.imageBytesPerRow(image)};
    vImage_Buffer dest = *buf;
    dest.width = width;
    dest.height = height;
    error = vImageConvert_AnyToAny(converter, &src, &dest, NULL, flags);
    if (error && !(flags & kvImageNoAllocate)) {
        free(buf->data);
        buf->data = NULL;
    }
done:
    if (data && rt.release) rt.release(data);
#ifdef PERRY_ACCELERATE_TEST
    free(converter);
#else
    if (rt.release) rt.release(converter);
#endif
    return error;
}

struct image_bytes { void (*callback)(void *, void *); void *userData; void *data; };

static void release_image_bytes(void *info, const void *data, size_t size) {
    struct image_bytes *bytes = info;
    if (bytes->callback) bytes->callback(bytes->userData, bytes->data);
    else free(bytes->data);
    free(bytes);
}

EXPORT(CGImageRef, vImageCreateCGImageFromBuffer, (const vImage_Buffer *buf, const vImage_CGImageFormat *format,
                                                   void (*callback)(void *userData, void *buf_data), void *userData, vImage_Flags flags,
                                                   vImage_Error *error)) {
    if (!buf || !format || !buf->data) {
        set_error(error, kvImageNullPointerArgument);
        return NULL;
    }
    load();
    struct layout layout;
    vImage_Error e = describe(format, &layout);
    if (e) {
        set_error(error, e);
        return NULL;
    }
    if (!rt.imageCreate || !rt.providerCreateWithData) {
        set_error(error, kvImageInternalError);
        return NULL;
    }
    struct image_bytes *bytes = calloc(1, sizeof *bytes);
    if (!bytes) {
        set_error(error, kvImageMemoryAllocationError);
        return NULL;
    }
    size_t rowBytes = buf->rowBytes, size = rowBytes * buf->height;
    if (flags & kvImageNoAllocate) {
        // The image takes the buffer's memory; the callback (or free) gives it back.
        bytes->callback = callback;
        bytes->userData = userData;
        bytes->data = buf->data;
    } else {
        rowBytes = ((size_t)buf->width * format->bitsPerPixel + 7) / 8;
        size = rowBytes * buf->height;
        bytes->data = malloc(size ? size : 1);
        if (!bytes->data) {
            free(bytes);
            set_error(error, kvImageMemoryAllocationError);
            return NULL;
        }
        for (vImagePixelCount y = 0; y < buf->height; y++)
            memcpy((uint8_t *)bytes->data + y * rowBytes, vimage_pixel(buf, 0, y, 0), rowBytes);
    }
    void *provider = rt.providerCreateWithData(bytes, bytes->data, size, release_image_bytes);
    if (!provider) {
        release_image_bytes(bytes, NULL, 0);
        set_error(error, kvImageMemoryAllocationError);
        return NULL;
    }
    CGColorSpaceRef space = format->colorSpace, made = NULL;
    if (!space && rt.colorSpaceCreateDeviceRGB) space = made = rt.colorSpaceCreateDeviceRGB();
    CGImageRef image = rt.imageCreate(buf->width, buf->height, format->bitsPerComponent, format->bitsPerPixel, rowBytes, space,
                                      format->bitmapInfo, provider, NULL, false, format->renderingIntent);
    if (made && rt.colorSpaceRelease) rt.colorSpaceRelease(made);
    if (rt.providerRelease) rt.providerRelease(provider);
    set_error(error, image ? kvImageNoError : kvImageInvalidImageFormat);
    return image;
}

// MARK: - Core Video buffers

/// Points `buffers` at a locked pixel buffer's planes, in the order of `side`.
static vImage_Error buffers_for(const struct side *side, CVPixelBufferRef pixelBuffer, vImage_Buffer *buffers) {
    load();
    if (!rt.width || !rt.base) return kvImageInternalError;
    size_t width = rt.width(pixelBuffer), height = rt.height(pixelBuffer);
    if (side->kind == SideCV && side->cv->kind == CV420) {
        for (size_t plane = 0; plane < 2; plane++) {
            // Both described at the image's size, as vImage describes them.
            buffers[plane].width = width;
            buffers[plane].height = height;
            buffers[plane].rowBytes = rt.planeBytesPerRow(pixelBuffer, plane);
            buffers[plane].data = rt.planeBase(pixelBuffer, plane);
            if (!buffers[plane].data) return kvImageInvalidImageObject;
        }
        return kvImageNoError;
    }
    buffers[0].width = width;
    buffers[0].height = height;
    buffers[0].rowBytes = rt.bytesPerRow(pixelBuffer);
    buffers[0].data = rt.base(pixelBuffer);
    return buffers[0].data ? kvImageNoError : kvImageInvalidImageObject;
}

static vImage_Error init_for_copy(vImage_Buffer *buffers, const struct side *side, CVPixelBufferRef pixelBuffer, vImage_Flags flags) {
    if (!buffers) return kvImageNullPointerArgument;
    if (!pixelBuffer) return kvImageNoError;
    if (!(flags & kvImageNoAllocate)) return kvImageInvalidParameter;
    if (side->kind != SideCV) return kvImageInvalidParameter;
    return buffers_for(side, pixelBuffer, buffers);
}

EXPORT(vImage_Error, vImageBuffer_InitForCopyFromCVPixelBuffer, (vImage_Buffer *buffers, const void *converter,
                                                                 const CVPixelBufferRef pixelBuffer, vImage_Flags flags)) {
    struct converter *c = state_of((void *)converter);
    if (!c) return kvImageNullPointerArgument;
    return init_for_copy(buffers, &c->src, pixelBuffer, flags);
}

EXPORT(vImage_Error, vImageBuffer_InitForCopyToCVPixelBuffer, (vImage_Buffer *buffers, const void *converter,
                                                               const CVPixelBufferRef pixelBuffer, vImage_Flags flags)) {
    struct converter *c = state_of((void *)converter);
    if (!c) return kvImageNullPointerArgument;
    return init_for_copy(buffers, &c->dest, pixelBuffer, flags);
}

static void release_object(void *object) {
#ifdef PERRY_ACCELERATE_TEST
    struct cv_format *f = object;
    (void)f;
    free(object);
#else
    if (object && rt.release) rt.release(object);
#endif
}

// C programs' reference counting of converters and formats (Swift's ARC
// retains and releases them as objects). The test build's plain structs
// are not counted: Release frees them.
static void retain_object(void *object) {
#ifndef PERRY_ACCELERATE_TEST
    if (object && rt.retain) rt.retain(object);
#else
    (void)object;
#endif
}

EXPORT(void, vImageConverter_Retain, (void *converter)) { retain_object(converter); }
EXPORT(void, vImageConverter_Release, (void *converter)) { if (converter) release_object(converter); }
EXPORT(void, vImageCVImageFormat_Retain, (void *format)) { retain_object(format); }
EXPORT(void, vImageCVImageFormat_Release, (void *format)) { if (format) release_object(format); }

EXPORT(vImage_Error, vImageBuffer_InitWithCVPixelBuffer, (vImage_Buffer *buffer, vImage_CGImageFormat *desiredFormat,
                                                          CVPixelBufferRef cvPixelBuffer, void *cvImageFormat,
                                                          const CGFloat *backgroundColor, vImage_Flags flags)) {
    if (!buffer) return kvImageInvalidParameter;
    if (!cvPixelBuffer) return kvImageInvalidImageObject;
    if (!desiredFormat) return kvImageInvalidImageFormat;
    load();
    void *format = cvImageFormat, *made = NULL;
    if (!format) format = made = vImageCVImageFormat_CreateWithCVPixelBuffer(cvPixelBuffer);
    if (!format) return kvImageInvalidCVImageFormat;
    vImage_Error error = kvImageNoError;
    void *converter = vImageConverter_CreateForCVToCGImageFormat(format, desiredFormat, backgroundColor, flags, &error);
    if (made) {
#ifdef PERRY_ACCELERATE_TEST
        format_release_contents(state_of(made));
#endif
        release_object(made);
    }
    if (!converter) return error;
    struct converter *c = state_of(converter);
    if (rt.lock && rt.lock(cvPixelBuffer, 1) != 0) {
        release_object(converter);
        return kvImageInvalidImageObject;
    }
    vImage_Buffer planes[2];
    error = buffers_for(&c->src, cvPixelBuffer, planes);
    if (!error) {
        if (flags & kvImageNoAllocate) {
            if (buffer->width != planes[0].width || buffer->height != planes[0].height) error = kvImageBufferSizeMismatch;
        } else error = allocate(buffer, planes[0].width, planes[0].height, desiredFormat->bitsPerPixel);
    }
    if (!error) {
        error = vImageConvert_AnyToAny(converter, planes, buffer, NULL, flags);
        if (error && !(flags & kvImageNoAllocate)) {
            free(buffer->data);
            buffer->data = NULL;
        }
    }
    if (rt.unlock) rt.unlock(cvPixelBuffer, 1);
    release_object(converter);
    return error;
}

EXPORT(vImage_Error, vImageBuffer_CopyToCVPixelBuffer, (const vImage_Buffer *buffer, const vImage_CGImageFormat *bufferFormat,
                                                        CVPixelBufferRef cvPixelBuffer, void *cvImageFormat, const CGFloat *backgroundColor,
                                                        vImage_Flags flags)) {
    if (!buffer) return kvImageNullPointerArgument;
    if (!cvPixelBuffer) return kvImageInvalidImageObject;
    if (!bufferFormat) return kvImageInvalidImageFormat;
    load();
    void *format = cvImageFormat, *made = NULL;
    if (!format) format = made = vImageCVImageFormat_CreateWithCVPixelBuffer(cvPixelBuffer);
    if (!format) return kvImageInvalidCVImageFormat;
    vImage_Error error = kvImageNoError;
    void *converter = vImageConverter_CreateForCGToCVImageFormat(bufferFormat, format, backgroundColor, flags, &error);
    if (made) {
#ifdef PERRY_ACCELERATE_TEST
        format_release_contents(state_of(made));
#endif
        release_object(made);
    }
    if (!converter) return error;
    struct converter *c = state_of(converter);
    if (rt.lock && rt.lock(cvPixelBuffer, 0) != 0) {
        release_object(converter);
        return kvImageInvalidImageObject;
    }
    vImage_Buffer planes[2];
    error = buffers_for(&c->dest, cvPixelBuffer, planes);
    if (!error && (buffer->width != planes[0].width || buffer->height != planes[0].height)) error = kvImageBufferSizeMismatch;
    if (!error) error = vImageConvert_AnyToAny(converter, buffer, planes, NULL, flags);
    if (rt.unlock) rt.unlock(cvPixelBuffer, 0);
    release_object(converter);
    return error;
}
