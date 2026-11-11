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

__attribute__((visibility("default")))
void perry_provider_startup(const perry_startup_info *info) {
    if (info->version < 2 || !info->lookup_symbol) return;
    const char *objc = "/usr/lib/libobjc.A.dylib";
    msg_send = (id (*)(id, SEL, ...))info->lookup_symbol(objc, "_objc_msgSend");
    sel_register = (SEL (*)(const char *))info->lookup_symbol(objc, "_sel_registerName");
    get_class = (id (*)(const char *))info->lookup_symbol(objc, "_objc_getClass");
}

static id send(id object, const char *selector) {
    return object && msg_send && sel_register ? msg_send(object, sel_register(selector)) : NULL;
}

static id context_class(void) { return get_class ? get_class("NSOpenGLContext") : NULL; }

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
    if (msg_send && sel_register) msg_send(context, sel_register("setValues:forParameter:"), values, (intptr_t)parameter);
    return kCGLNoError;
}

CGLError perry_CGLGetParameter(id context, int parameter, int *values) CGL_SYMBOL(CGLGetParameter);
CGLError perry_CGLGetParameter(id context, int parameter, int *values) {
    if (!context) return kCGLBadContext;
    if (values) *values = 0;
    if (msg_send && sel_register) msg_send(context, sel_register("getValues:forParameter:"), values, (intptr_t)parameter);
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
