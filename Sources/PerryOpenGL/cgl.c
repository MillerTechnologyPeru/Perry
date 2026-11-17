// CGL, OpenGL.framework's contexts, for Mac programs that make theirs with
// NSOpenGLContext and then work with what its -CGLContextObj gives: AppKit's
// provider gives the NSOpenGLContext itself, so each CGL call here is that
// context's method. Contexts made by CGL alone (CGLCreateContext) aren't.
// The renderer information is one accelerated renderer, the one SDL's
// contexts are on.

#include "perry_interface.h"

#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define CGL_SYMBOL(name) __asm__("_" #name) __attribute__((visibility("default"), used))

typedef int CGLError;
enum {
    kCGLNoError = 0,
    kCGLBadAttribute = 10000,
    kCGLBadProperty = 10001,
    kCGLBadRendererInfo = 10003,
    kCGLBadContext = 10004,
};

typedef void *id;
typedef void *SEL;

static id (*msg_send)(id, SEL, ...);
static SEL (*sel_register)(const char *);
static id (*get_class)(const char *);
static void *(*lookup_symbol)(const char *, const char *);

__attribute__((visibility("default")))
void perry_provider_startup(const perry_startup_info *info) {
    if (info->version < 2 || !info->lookup_symbol) return;
    lookup_symbol = info->lookup_symbol;
    const char *objc = "/usr/lib/libobjc.A.dylib";
    msg_send = (id (*)(id, SEL, ...))info->lookup_symbol(objc, "_objc_msgSend");
    sel_register = (SEL (*)(const char *))info->lookup_symbol(objc, "_sel_registerName");
    get_class = (id (*)(const char *))info->lookup_symbol(objc, "_objc_getClass");
}

// The runtime's functions and the loader's lookup, for AGL's contexts
// (agl.c), which are these.
void *perry_opengl_lookup(const char *library, const char *name) {
    return lookup_symbol ? lookup_symbol(library, name) : NULL;
}

void perry_opengl_objc(id (**send)(id, SEL, ...), SEL (**selector)(const char *), id (**class)(const char *)) {
    *send = msg_send;
    *selector = sel_register;
    *class = get_class;
}

// Selectors and the class, looked up once: games call CGLSetCurrentContext
// thousands of times a frame.
#define SELECTOR(name) ({ static SEL selector_; if (!selector_ && sel_register) selector_ = sel_register(name); selector_; })
#define send(object, name) send_selector(object, SELECTOR(name))

static id send_selector(id object, SEL selector) {
    return object && msg_send && selector ? msg_send(object, selector) : NULL;
}

static id context_class(void) {
    static id class;
    if (!class && get_class) class = get_class("NSOpenGLContext");
    return class;
}

// MARK: - Current context

CGLError perry_CGLSetCurrentContext(id context) CGL_SYMBOL(CGLSetCurrentContext);
CGLError perry_CGLSetCurrentContext(id context) {
    if (context) send(context, "makeCurrentContext");
    else send(context_class(), "clearCurrentContext");
    return kCGLNoError;
}

id perry_CGLGetCurrentContext(void) CGL_SYMBOL(CGLGetCurrentContext);
id perry_CGLGetCurrentContext(void) { return send(context_class(), "currentContext"); }

CGLError perry_CGLFlushDrawable(id context) CGL_SYMBOL(CGLFlushDrawable);
CGLError perry_CGLFlushDrawable(id context) {
    if (!context) return kCGLBadContext;
    send(context, "flushBuffer");
    return kCGLNoError;
}

CGLError perry_CGLClearDrawable(id context) CGL_SYMBOL(CGLClearDrawable);
CGLError perry_CGLClearDrawable(id context) {
    if (!context) return kCGLBadContext;
    send(context, "clearDrawable");
    return kCGLNoError;
}

CGLError perry_CGLUpdateContext(id context) CGL_SYMBOL(CGLUpdateContext);
CGLError perry_CGLUpdateContext(id context) {
    if (!context) return kCGLBadContext;
    send(context, "update");
    return kCGLNoError;
}

// MARK: - Pixel formats and contexts

// CGL's own: a pixel format is an NSOpenGLPixelFormat, whose attributes
// CGL's are, and a context an NSOpenGLContext, which draws once it has a
// drawable (CGLSetFullScreen, or a view given it by AppKit or AGL).

CGLError perry_CGLChoosePixelFormat(const int *attributes, id *format, int *count) CGL_SYMBOL(CGLChoosePixelFormat);
CGLError perry_CGLChoosePixelFormat(const int *attributes, id *format, int *count) {
    if (!format) return kCGLBadAttribute;
    *format = NULL;
    if (count) *count = 0;
    if (!msg_send || !get_class) return kCGLBadAttribute;
    // The list is NSOpenGLPixelFormat's, 32-bit unsigned ints with 0 at the end.
    size_t length = 0;
    while (attributes && attributes[length]) length++;
    uint32_t *converted = calloc(length + 1, sizeof *converted);
    if (!converted) return kCGLBadAttribute;
    for (size_t index = 0; index < length; index++) converted[index] = (uint32_t)attributes[index];
    id pixel_format = msg_send(get_class("NSOpenGLPixelFormat"), SELECTOR("alloc"));
    pixel_format = ((id (*)(id, SEL, const uint32_t *))msg_send)(pixel_format, SELECTOR("initWithAttributes:"), converted);
    free(converted);
    if (!pixel_format) return kCGLNoError;   // none matches: NULL, and no error
    *format = pixel_format;
    if (count) *count = 1;
    return kCGLNoError;
}

CGLError perry_CGLDestroyPixelFormat(id format) CGL_SYMBOL(CGLDestroyPixelFormat);
CGLError perry_CGLDestroyPixelFormat(id format) {
    if (format) send(format, "release");
    return kCGLNoError;
}

CGLError perry_CGLReleasePixelFormat(id format) CGL_SYMBOL(CGLReleasePixelFormat);
CGLError perry_CGLReleasePixelFormat(id format) { return perry_CGLDestroyPixelFormat(format); }

id perry_CGLRetainPixelFormat(id format) CGL_SYMBOL(CGLRetainPixelFormat);
id perry_CGLRetainPixelFormat(id format) { return format ? send(format, "retain") : NULL; }

CGLError perry_CGLDescribePixelFormat(id format, int screen, int attribute, int *value) CGL_SYMBOL(CGLDescribePixelFormat);
CGLError perry_CGLDescribePixelFormat(id format, int screen, int attribute, int *value) {
    if (!format || !value) return kCGLBadAttribute;
    ((void (*)(id, SEL, int *, uint32_t, int))msg_send)(format, SELECTOR("getValues:forAttribute:forVirtualScreen:"),
                                                        value, (uint32_t)attribute, screen);
    return kCGLNoError;
}

CGLError perry_CGLCreateContext(id format, id share, id *context) CGL_SYMBOL(CGLCreateContext);
CGLError perry_CGLCreateContext(id format, id share, id *context) {
    if (!context) return kCGLBadContext;
    *context = NULL;
    if (!format || !msg_send) return kCGLBadAttribute;
    id made = msg_send(context_class(), SELECTOR("alloc"));
    made = ((id (*)(id, SEL, id, id))msg_send)(made, SELECTOR("initWithFormat:shareContext:"), format, share);
    if (!made) return 10011;   // kCGLBadMatch
    *context = made;
    return kCGLNoError;
}

CGLError perry_CGLDestroyContext(id context) CGL_SYMBOL(CGLDestroyContext);
CGLError perry_CGLDestroyContext(id context) {
    if (!context) return kCGLBadContext;
    if (send(context_class(), "currentContext") == context) send(context_class(), "clearCurrentContext");
    send(context, "clearDrawable");
    send(context, "release");
    return kCGLNoError;
}

CGLError perry_CGLReleaseContext(id context) CGL_SYMBOL(CGLReleaseContext);
CGLError perry_CGLReleaseContext(id context) { return perry_CGLDestroyContext(context); }

id perry_CGLRetainContext(id context) CGL_SYMBOL(CGLRetainContext);
id perry_CGLRetainContext(id context) { return context ? send(context, "retain") : NULL; }

id perry_CGLGetPixelFormat(id context) CGL_SYMBOL(CGLGetPixelFormat);
id perry_CGLGetPixelFormat(id context) { return context ? send(context, "pixelFormat") : NULL; }

// MARK: - Locks

// One recursive lock per context, as CGLLockContext's are, for programs
// that draw from a thread of their own.
static pthread_mutex_t locks_lock = PTHREAD_MUTEX_INITIALIZER;
static struct context_lock { id context; pthread_mutex_t mutex; struct context_lock *next; } *locks;

static pthread_mutex_t *lock_for(id context) {
    pthread_mutex_lock(&locks_lock);
    struct context_lock *entry = locks;
    while (entry && entry->context != context) entry = entry->next;
    if (!entry && (entry = calloc(1, sizeof(*entry)))) {
        pthread_mutexattr_t attributes;
        pthread_mutexattr_init(&attributes);
        pthread_mutexattr_settype(&attributes, PTHREAD_MUTEX_RECURSIVE);
        pthread_mutex_init(&entry->mutex, &attributes);
        pthread_mutexattr_destroy(&attributes);
        entry->context = context;
        entry->next = locks;
        locks = entry;
    }
    pthread_mutex_unlock(&locks_lock);
    return entry ? &entry->mutex : NULL;
}

CGLError perry_CGLLockContext(id context) CGL_SYMBOL(CGLLockContext);
CGLError perry_CGLLockContext(id context) {
    pthread_mutex_t *mutex = context ? lock_for(context) : NULL;
    if (!mutex) return kCGLBadContext;
    pthread_mutex_lock(mutex);
    return kCGLNoError;
}

CGLError perry_CGLUnlockContext(id context) CGL_SYMBOL(CGLUnlockContext);
CGLError perry_CGLUnlockContext(id context) {
    pthread_mutex_t *mutex = context ? lock_for(context) : NULL;
    if (!mutex) return kCGLBadContext;
    pthread_mutex_unlock(mutex);
    return kCGLNoError;
}

// MARK: - Parameters and options

// CGLContextParameter is NSOpenGLContextParameter: the context keeps them.
CGLError perry_CGLSetParameter(id context, int parameter, const int *values) CGL_SYMBOL(CGLSetParameter);
CGLError perry_CGLSetParameter(id context, int parameter, const int *values) {
    if (!context) return kCGLBadContext;
    if (msg_send && sel_register) msg_send(context, SELECTOR("setValues:forParameter:"), values, (intptr_t)parameter);
    return kCGLNoError;
}

CGLError perry_CGLGetParameter(id context, int parameter, int *values) CGL_SYMBOL(CGLGetParameter);
CGLError perry_CGLGetParameter(id context, int parameter, int *values) {
    if (!context) return kCGLBadContext;
    if (values) *values = 0;
    if (msg_send && sel_register) msg_send(context, SELECTOR("getValues:forParameter:"), values, (intptr_t)parameter);
    return kCGLNoError;
}

// Context options (multithreaded GL, surface backing size, ...) change
// nothing here.
CGLError perry_CGLEnable(id context, int option) CGL_SYMBOL(CGLEnable);
CGLError perry_CGLEnable(id context, int option) { (void)option; return context ? kCGLNoError : kCGLBadContext; }

CGLError perry_CGLDisable(id context, int option) CGL_SYMBOL(CGLDisable);
CGLError perry_CGLDisable(id context, int option) { (void)option; return context ? kCGLNoError : kCGLBadContext; }

CGLError perry_CGLIsEnabled(id context, int option, int *enabled) CGL_SYMBOL(CGLIsEnabled);
CGLError perry_CGLIsEnabled(id context, int option, int *enabled) {
    (void)option;
    if (enabled) *enabled = 0;
    return context ? kCGLNoError : kCGLBadContext;
}

// The share group, for OpenCL's sharing with OpenGL, which isn't here: the
// context stands for it.
id perry_CGLGetShareGroup(id context) CGL_SYMBOL(CGLGetShareGroup);
id perry_CGLGetShareGroup(id context) { return context; }

// MARK: - The current context's profile

int perry_cgl_current_is_core(void) {
    if (!msg_send || !sel_register) return 0;
    id format = send(send(context_class(), "currentContext"), "pixelFormat");
    if (!format) return 0;
    // NSOpenGLPFAOpenGLProfile (99): NSOpenGLProfileVersionLegacy (0x1000),
    // or 3.2 Core (0x3200) and 4.1 Core (0x4100).
    int profile = 0;
    ((void (*)(id, SEL, int *, uint32_t, int))msg_send)(format, SELECTOR("getValues:forAttribute:forVirtualScreen:"),
                                                        &profile, 99, 0);
    return profile >= 0x3200;
}

// MARK: - Renderers

static int renderer_info_token;

CGLError perry_CGLQueryRendererInfo(uint32_t display_mask, void **info, int *count) CGL_SYMBOL(CGLQueryRendererInfo);
CGLError perry_CGLQueryRendererInfo(uint32_t display_mask, void **info, int *count) {
    (void)display_mask;
    if (!info || !count) return kCGLBadAttribute;
    *info = &renderer_info_token;
    *count = 1;
    return kCGLNoError;
}

CGLError perry_CGLDestroyRendererInfo(void *info) CGL_SYMBOL(CGLDestroyRendererInfo);
CGLError perry_CGLDestroyRendererInfo(void *info) { return info == &renderer_info_token ? kCGLNoError : kCGLBadRendererInfo; }

// The renderer's properties, by CGLRendererProperty. Its memory is what a
// mid-range GPU has (2 GB), which programs size their textures by.
CGLError perry_CGLDescribeRenderer(void *info, int index, int property, int *value) CGL_SYMBOL(CGLDescribeRenderer);
CGLError perry_CGLDescribeRenderer(void *info, int index, int property, int *value) {
    if (info != &renderer_info_token || index != 0) return kCGLBadRendererInfo;
    if (!value) return kCGLBadProperty;
    switch (property) {
    case 70: *value = 0x00024000; return kCGLNoError;           // kCGLRPRendererID: an Intel GPU's
    case 73: case 80: case 83: case 129:                          // accelerated, window, compliant, online
    case 122: case 123: case 76: case 78:                         // GPU vertex/fragment processing, backing store, MP safe
        *value = 1; return kCGLNoError;
    case 84: *value = 1; return kCGLNoError;                      // kCGLRPDisplayMask: the one display
    case 128: *value = 1; return kCGLNoError;                     // kCGLRPRendererCount
    case 120: case 121: *value = (int)(2047u << 20); return kCGLNoError;   // video and texture memory, in bytes
    case 131: case 132: *value = 2048; return kCGLNoError;        // the same, in megabytes
    case 108: *value = 1; return kCGLNoError;                     // kCGLRPMaxSampleBuffers
    case 109: *value = 8; return kCGLNoError;                     // kCGLRPMaxSamples
    case 107: *value = 0; return kCGLNoError;                     // kCGLRPMaxAuxBuffers
    case 53: case 54: case 81: case 75: case 130: *value = 0; return kCGLNoError;
    default: *value = 0; return kCGLBadProperty;
    }
}
