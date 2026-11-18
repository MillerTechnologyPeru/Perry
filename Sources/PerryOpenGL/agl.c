// AGL, Carbon's OpenGL contexts, over NSOpenGLContext as CGL's are: an
// AGLContext is an NSOpenGLContext and an AGLPixelFormat an
// NSOpenGLPixelFormat, made from AGL's attributes (which NSOpenGLPixelFormat's
// mostly are). A drawable is a Carbon window's port, which AppKit's Carbon
// gives the content view of (-_perryCarbonContentView); full screen is that
// of a window AppKit's Carbon covers the screen with. The renderer is the
// one CGL describes.

#include "perry_interface.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define AGL_SYMBOL(name) __asm__("_" #name) __attribute__((visibility("default"), used))

typedef void *id;
typedef void *SEL;
typedef unsigned char GLboolean;
typedef int GLint;
typedef unsigned int GLenum;

enum {
    AGL_NONE = 0,
    AGL_ALL_RENDERERS = 1,
    AGL_BUFFER_SIZE = 2,
    AGL_LEVEL = 3,
    AGL_RGBA = 4,
    AGL_DOUBLEBUFFER = 5,
    AGL_STEREO = 6,
    AGL_AUX_BUFFERS = 7,
    AGL_RED_SIZE = 8,
    AGL_GREEN_SIZE = 9,
    AGL_BLUE_SIZE = 10,
    AGL_ALPHA_SIZE = 11,
    AGL_DEPTH_SIZE = 12,
    AGL_STENCIL_SIZE = 13,
    AGL_ACCUM_RED_SIZE = 14,
    AGL_ACCUM_GREEN_SIZE = 15,
    AGL_ACCUM_BLUE_SIZE = 16,
    AGL_ACCUM_ALPHA_SIZE = 17,
    AGL_PIXEL_SIZE = 50,
    AGL_SAMPLE_BUFFERS_ARB = 55,
    AGL_SAMPLES_ARB = 56,
    AGL_RENDERER_ID = 70,
    AGL_VIRTUAL_SCREEN = 82,

    AGL_SWAP_RECT = 200,
    AGL_BUFFER_RECT = 202,
    AGL_SWAP_LIMIT = 203,
    AGL_COLORMAP_TRACKING = 210,
    AGL_COLORMAP_ENTRY = 212,
    AGL_RASTERIZATION = 220,
    AGL_SWAP_INTERVAL = 222,
    AGL_STATE_VALIDATION = 230,

    AGL_NO_ERROR = 0,
    AGL_BAD_ATTRIBUTE = 10000,
    AGL_BAD_PROPERTY = 10001,
    AGL_BAD_PIXELFMT = 10002,
    AGL_BAD_RENDINFO = 10003,
    AGL_BAD_CONTEXT = 10004,
    AGL_BAD_DRAWABLE = 10005,
    AGL_BAD_STATE = 10007,
    AGL_BAD_VALUE = 10008,
    AGL_BAD_MATCH = 10009,
    AGL_BAD_ALLOC = 10016,
};

static id (*msg_send)(id, SEL, ...);
static SEL (*sel_register)(const char *);
static id (*get_class)(const char *);
// The runtime's functions, which cgl.c looked up at startup, and Carbon's
// provider's for its ports.
extern void perry_opengl_objc(id (**send)(id, SEL, ...), SEL (**selector)(const char *), id (**class)(const char *));
extern void *perry_opengl_lookup(const char *library, const char *name);

#define CARBON "/System/Library/Frameworks/Carbon.framework/Versions/A/Carbon"

static void *carbon(const char *name) { return perry_opengl_lookup(CARBON, name); }

static int ready(void) {
    if (!msg_send) perry_opengl_objc(&msg_send, &sel_register, &get_class);
    return msg_send && sel_register && get_class;
}

#define SELECTOR(name) ({ static SEL selector_; if (!selector_ && sel_register) selector_ = sel_register(name); selector_; })

static _Thread_local GLenum last_error;

static GLboolean fail(GLenum error) {
    last_error = error;
    return 0;
}

// MARK: - Pixel formats

// AGL's attributes as NSOpenGLPixelFormat's: the color and accumulation
// sizes are each one there, of all the channels; RGBA, the only kind there
// is, and the level go.
static uint32_t *ns_attributes(const GLint *attributes) {
    size_t capacity = 64, count = 0;
    uint32_t *out = calloc(capacity, sizeof *out);
    if (!out) return NULL;
    int color = 0, accum = 0, have_color = 0, have_accum = 0;
#define PUT(value) do { if (count + 3 >= capacity) { capacity *= 2; uint32_t *grown = realloc(out, capacity * sizeof *out); if (!grown) { free(out); return NULL; } out = grown; } out[count++] = (uint32_t)(value); } while (0)
    for (const GLint *cursor = attributes; cursor && *cursor != AGL_NONE; cursor++) {
        switch (*cursor) {
        case AGL_RGBA: case AGL_ALL_RENDERERS: break;
        case AGL_LEVEL: cursor++; break;
        case AGL_BUFFER_SIZE: case AGL_PIXEL_SIZE: color = cursor[1] > color ? cursor[1] : color; have_color = 1; cursor++; break;
        case AGL_RED_SIZE: case AGL_GREEN_SIZE: case AGL_BLUE_SIZE:
            color += cursor[1]; have_color = 1; cursor++; break;
        case AGL_ACCUM_RED_SIZE: case AGL_ACCUM_GREEN_SIZE: case AGL_ACCUM_BLUE_SIZE: case AGL_ACCUM_ALPHA_SIZE:
            accum += cursor[1]; have_accum = 1; cursor++; break;
        // Those with a value.
        case AGL_AUX_BUFFERS: case AGL_ALPHA_SIZE: case AGL_DEPTH_SIZE: case AGL_STENCIL_SIZE:
        case AGL_SAMPLE_BUFFERS_ARB: case AGL_SAMPLES_ARB: case AGL_RENDERER_ID: case AGL_VIRTUAL_SCREEN:
            PUT(cursor[0]); PUT(cursor[1]); cursor++; break;
        // AGL_FULLSCREEN (54) and the other booleans, which are the same.
        default: PUT(cursor[0]); break;
        }
    }
    if (have_color) { PUT(8); PUT(color); }
    if (have_accum) { PUT(14); PUT(accum); }
    PUT(0);
#undef PUT
    return out;
}

id perry_aglChoosePixelFormat(const void *devices, GLint count, const GLint *attributes) AGL_SYMBOL(aglChoosePixelFormat);
id perry_aglChoosePixelFormat(const void *devices, GLint count, const GLint *attributes) {
    (void)devices; (void)count;
    if (!ready()) return (id)(uintptr_t)fail(AGL_BAD_ALLOC);
    uint32_t *converted = ns_attributes(attributes);
    if (!converted) return (id)(uintptr_t)fail(AGL_BAD_ALLOC);
    id format = msg_send(get_class("NSOpenGLPixelFormat"), SELECTOR("alloc"));
    format = ((id (*)(id, SEL, const uint32_t *))msg_send)(format, SELECTOR("initWithAttributes:"), converted);
    free(converted);
    if (!format) last_error = AGL_BAD_PIXELFMT;
    return format;
}

void perry_aglDestroyPixelFormat(id format) AGL_SYMBOL(aglDestroyPixelFormat);
void perry_aglDestroyPixelFormat(id format) {
    if (format && ready()) msg_send(format, SELECTOR("release"));
}

// MARK: - Contexts

id perry_aglCreateContext(id format, id share) AGL_SYMBOL(aglCreateContext);
id perry_aglCreateContext(id format, id share) {
    if (!format) return (id)(uintptr_t)fail(AGL_BAD_PIXELFMT);
    if (!ready()) return (id)(uintptr_t)fail(AGL_BAD_ALLOC);
    id context = msg_send(get_class("NSOpenGLContext"), SELECTOR("alloc"));
    context = ((id (*)(id, SEL, id, id))msg_send)(context, SELECTOR("initWithFormat:shareContext:"), format, share);
    if (!context) last_error = AGL_BAD_MATCH;
    return context;
}

GLboolean perry_aglDestroyContext(id context) AGL_SYMBOL(aglDestroyContext);
GLboolean perry_aglDestroyContext(id context) {
    if (!context || !ready()) return fail(AGL_BAD_CONTEXT);
    if (msg_send(get_class("NSOpenGLContext"), SELECTOR("currentContext")) == context)
        msg_send(get_class("NSOpenGLContext"), SELECTOR("clearCurrentContext"));
    msg_send(context, SELECTOR("clearDrawable"));
    msg_send(context, SELECTOR("release"));
    return 1;
}

GLboolean perry_aglSetCurrentContext(id context) AGL_SYMBOL(aglSetCurrentContext);
GLboolean perry_aglSetCurrentContext(id context) {
    if (!ready()) return fail(AGL_BAD_CONTEXT);
    if (context) msg_send(context, SELECTOR("makeCurrentContext"));
    else msg_send(get_class("NSOpenGLContext"), SELECTOR("clearCurrentContext"));
    return 1;
}

id perry_aglGetCurrentContext(void) AGL_SYMBOL(aglGetCurrentContext);
id perry_aglGetCurrentContext(void) {
    return ready() ? msg_send(get_class("NSOpenGLContext"), SELECTOR("currentContext")) : NULL;
}

// A drawable is a port: its window's content view is what the context
// draws into. NULL takes the context off its drawable.
GLboolean perry_aglSetDrawable(id context, id port) AGL_SYMBOL(aglSetDrawable);
GLboolean perry_aglSetDrawable(id context, id port) {
    if (!context || !ready()) return fail(AGL_BAD_CONTEXT);
    if (!port) {
        msg_send(context, SELECTOR("clearDrawable"));
        return 1;
    }
    id (*port_view)(id) = (id (*)(id))carbon("_PerryCarbonPortView");
    id view = port_view ? port_view(port) : NULL;
    if (!view) return fail(AGL_BAD_DRAWABLE);
    ((void (*)(id, SEL, id))msg_send)(context, SELECTOR("setView:"), view);
    msg_send(context, SELECTOR("update"));
    return 1;
}

id perry_aglGetDrawable(id context) AGL_SYMBOL(aglGetDrawable);
id perry_aglGetDrawable(id context) {
    if (!context || !ready()) return (id)(uintptr_t)fail(AGL_BAD_CONTEXT);
    id view = msg_send(context, SELECTOR("view"));
    id (*view_port)(id) = (id (*)(id))carbon("_PerryCarbonViewPort");
    return view && view_port ? view_port(view) : NULL;
}

// The whole screen, at the size asked for if the display can change to it:
// a window AppKit's Carbon covers the screen with, whose port the context
// draws into.
GLboolean perry_aglSetFullScreen(id context, GLint width, GLint height, GLint frequency, GLint device)
    AGL_SYMBOL(aglSetFullScreen);
GLboolean perry_aglSetFullScreen(id context, GLint width, GLint height, GLint frequency, GLint device) {
    (void)frequency; (void)device;
    if (!context || !ready()) return fail(AGL_BAD_CONTEXT);
    id (*full_screen)(GLint, GLint) = (id (*)(GLint, GLint))carbon("_PerryCarbonFullScreenPort");
    id port = full_screen ? full_screen(width, height) : NULL;
    if (!port) return fail(AGL_BAD_DRAWABLE);
    return perry_aglSetDrawable(context, port);
}

void perry_aglSwapBuffers(id context) AGL_SYMBOL(aglSwapBuffers);
void perry_aglSwapBuffers(id context) {
    if (!context || !ready()) {
        last_error = AGL_BAD_CONTEXT;
        return;
    }
    msg_send(context, SELECTOR("flushBuffer"));
}

GLboolean perry_aglUpdateContext(id context) AGL_SYMBOL(aglUpdateContext);
GLboolean perry_aglUpdateContext(id context) {
    if (!context || !ready()) return fail(AGL_BAD_CONTEXT);
    msg_send(context, SELECTOR("update"));
    return 1;
}

// The swap interval is the context's; a buffer or swap rectangle, the
// whole drawable here, and the other options change nothing.
GLboolean perry_aglSetInteger(id context, GLenum name, const GLint *values) AGL_SYMBOL(aglSetInteger);
GLboolean perry_aglSetInteger(id context, GLenum name, const GLint *values) {
    if (!context || !ready()) return fail(AGL_BAD_CONTEXT);
    if (name == AGL_SWAP_INTERVAL) {
        if (!values) return fail(AGL_BAD_VALUE);
        ((void (*)(id, SEL, const GLint *, long))msg_send)(context, SELECTOR("setValues:forParameter:"), values, 222);
    }
    return 1;
}

GLboolean perry_aglEnable(id context, GLenum name) AGL_SYMBOL(aglEnable);
GLboolean perry_aglEnable(id context, GLenum name) { (void)name; return context ? 1 : fail(AGL_BAD_CONTEXT); }

GLboolean perry_aglDisable(id context, GLenum name) AGL_SYMBOL(aglDisable);
GLboolean perry_aglDisable(id context, GLenum name) { (void)name; return context ? 1 : fail(AGL_BAD_CONTEXT); }

GLint perry_aglGetVirtualScreen(id context) AGL_SYMBOL(aglGetVirtualScreen);
GLint perry_aglGetVirtualScreen(id context) { (void)context; return 0; }

GLboolean perry_aglSetVirtualScreen(id context, GLint screen) AGL_SYMBOL(aglSetVirtualScreen);
GLboolean perry_aglSetVirtualScreen(id context, GLint screen) { return context && screen == 0 ? 1 : fail(AGL_BAD_VALUE); }

GLenum perry_aglGetError(void) AGL_SYMBOL(aglGetError);
GLenum perry_aglGetError(void) {
    GLenum error = last_error;
    last_error = AGL_NO_ERROR;
    return error;
}

const unsigned char *perry_aglErrorString(GLenum code) AGL_SYMBOL(aglErrorString);
const unsigned char *perry_aglErrorString(GLenum code) {
    switch (code) {
    case AGL_NO_ERROR: return (const unsigned char *)"no error";
    case AGL_BAD_ATTRIBUTE: return (const unsigned char *)"invalid pixel format attribute";
    case AGL_BAD_PIXELFMT: return (const unsigned char *)"invalid pixel format";
    case AGL_BAD_CONTEXT: return (const unsigned char *)"invalid context";
    case AGL_BAD_DRAWABLE: return (const unsigned char *)"invalid drawable";
    case AGL_BAD_VALUE: return (const unsigned char *)"invalid numeric value";
    case AGL_BAD_ALLOC: return (const unsigned char *)"memory allocation failure";
    default: return (const unsigned char *)"unknown error";
    }
}

void perry_aglGetVersion(GLint *major, GLint *minor) AGL_SYMBOL(aglGetVersion);
void perry_aglGetVersion(GLint *major, GLint *minor) {
    if (major) *major = 3;
    if (minor) *minor = 0;
}

// MARK: - Renderers

// The one renderer, CGL's; its properties are CGL's, whose numbers AGL's are.
extern int perry_CGLQueryRendererInfo(uint32_t display_mask, void **info, int *count) __asm__("_CGLQueryRendererInfo");
extern int perry_CGLDescribeRenderer(void *info, int index, int property, int *value) __asm__("_CGLDescribeRenderer");
extern int perry_CGLDescribePixelFormat(id format, int screen, int attribute, int *value) __asm__("_CGLDescribePixelFormat");

// A pixel format's attributes by AGL's names: the color by its parts, and
// the rest as NSOpenGLPixelFormat's, whose numbers are the same.
GLboolean perry_aglDescribePixelFormat(id format, GLint attribute, GLint *value) AGL_SYMBOL(aglDescribePixelFormat);
GLboolean perry_aglDescribePixelFormat(id format, GLint attribute, GLint *value) {
    if (!format || !value) return fail(AGL_BAD_PIXELFMT);
    int color = 0, alpha = 0, accum = 0;
    perry_CGLDescribePixelFormat(format, 0, 8, &color);    // NSOpenGLPFAColorSize
    perry_CGLDescribePixelFormat(format, 0, 11, &alpha);   // NSOpenGLPFAAlphaSize
    switch (attribute) {
    case AGL_RGBA: *value = 1; break;
    case AGL_LEVEL: *value = 0; break;
    case AGL_BUFFER_SIZE: case AGL_PIXEL_SIZE: *value = color + (color < 32 ? alpha : 0); break;
    case AGL_RED_SIZE: case AGL_GREEN_SIZE: case AGL_BLUE_SIZE: *value = color >= 24 ? 8 : color / 3; break;
    case AGL_ACCUM_RED_SIZE: case AGL_ACCUM_GREEN_SIZE: case AGL_ACCUM_BLUE_SIZE: case AGL_ACCUM_ALPHA_SIZE:
        perry_CGLDescribePixelFormat(format, 0, 14, &accum);   // NSOpenGLPFAAccumSize
        *value = accum / 4;
        break;
    default:
        if (perry_CGLDescribePixelFormat(format, 0, attribute, value) != 0) return fail(AGL_BAD_ATTRIBUTE);
    }
    return 1;
}

// A context's options: its swap interval; the rest as they are when
// they've not been set.
GLboolean perry_aglGetInteger(id context, GLenum name, GLint *values) AGL_SYMBOL(aglGetInteger);
GLboolean perry_aglGetInteger(id context, GLenum name, GLint *values) {
    if (!context || !ready()) return fail(AGL_BAD_CONTEXT);
    if (!values) return fail(AGL_BAD_VALUE);
    if (name == AGL_SWAP_INTERVAL) {
        ((void (*)(id, SEL, GLint *, long))msg_send)(context, SELECTOR("getValues:forParameter:"), values, 222);
    } else if (name == AGL_SWAP_RECT || name == AGL_BUFFER_RECT) {
        values[0] = values[1] = values[2] = values[3] = 0;
    } else {
        values[0] = 0;
    }
    return 1;
}

id perry_aglQueryRendererInfo(const void *devices, GLint count) AGL_SYMBOL(aglQueryRendererInfo);
id perry_aglQueryRendererInfo(const void *devices, GLint count) {
    (void)devices; (void)count;
    void *info = NULL;
    int renderers = 0;
    perry_CGLQueryRendererInfo(1, &info, &renderers);
    return info;
}

id perry_aglNextRendererInfo(id info) AGL_SYMBOL(aglNextRendererInfo);
id perry_aglNextRendererInfo(id info) { (void)info; return NULL; }

void perry_aglDestroyRendererInfo(id info) AGL_SYMBOL(aglDestroyRendererInfo);
void perry_aglDestroyRendererInfo(id info) { (void)info; }

GLboolean perry_aglDescribeRenderer(id info, GLint property, GLint *value) AGL_SYMBOL(aglDescribeRenderer);
GLboolean perry_aglDescribeRenderer(id info, GLint property, GLint *value) {
    if (!info) return fail(AGL_BAD_RENDINFO);
    if (perry_CGLDescribeRenderer(info, 0, property, value) != 0) return fail(AGL_BAD_PROPERTY);
    return 1;
}

// MARK: - Pixel buffers

// Pixel buffers aren't made: a program asking for one finds there are none
// to have, as on a renderer without them, and draws to its window instead.
GLboolean perry_aglCreatePBuffer(GLint width, GLint height, GLenum target, GLenum format, long level, id *pbuffer)
    AGL_SYMBOL(aglCreatePBuffer);
GLboolean perry_aglCreatePBuffer(GLint width, GLint height, GLenum target, GLenum format, long level, id *pbuffer) {
    (void)width; (void)height; (void)target; (void)format; (void)level;
    if (pbuffer) *pbuffer = NULL;
    return fail(AGL_BAD_ALLOC);
}

GLboolean perry_aglDestroyPBuffer(id pbuffer) AGL_SYMBOL(aglDestroyPBuffer);
GLboolean perry_aglDestroyPBuffer(id pbuffer) { return pbuffer ? 1 : fail(AGL_BAD_VALUE); }

GLboolean perry_aglSetPBuffer(id context, id pbuffer, GLint face, GLint level, GLint screen) AGL_SYMBOL(aglSetPBuffer);
GLboolean perry_aglSetPBuffer(id context, id pbuffer, GLint face, GLint level, GLint screen) {
    (void)context; (void)face; (void)level; (void)screen;
    return pbuffer ? 1 : fail(AGL_BAD_VALUE);
}

GLboolean perry_aglTexImagePBuffer(id context, id pbuffer, GLint source) AGL_SYMBOL(aglTexImagePBuffer);
GLboolean perry_aglTexImagePBuffer(id context, id pbuffer, GLint source) {
    (void)context; (void)source;
    return pbuffer ? 1 : fail(AGL_BAD_VALUE);
}
