// Auxiliary color buffers (GL_AUX0…), which a Mac's drivers give a context
// whose pixel format asks for them and Mesa has none of: a game draws a pass
// into one (shadows, reflections, what a glow is made from), copies it into
// a texture and draws the frame with that. Without the buffer the call
// fails and the pass lands on the frame itself.
//
// A context that selects an auxiliary buffer draws from then on into a
// framebuffer object of the window's size: its first color attachment is
// the back buffer, the second GL_AUX0, and they share the depth and stencil
// buffer as a window's buffers do. Swapping copies the back buffer to the
// window. The program sees none of it: the buffers it selects and asks
// about are the window's, and framebuffer 0 is this one.

#include "PerryOpenGL.h"

#include <dlfcn.h>
#include <stdbool.h>
#include <stddef.h>

enum {
    GL_NONE = 0, GL_FRONT_LEFT = 0x0400, GL_BACK_RIGHT = 0x0403, GL_FRONT = 0x0404, GL_BACK = 0x0405, GL_LEFT = 0x0406,
    GL_RIGHT = 0x0407, GL_FRONT_AND_BACK = 0x0408, GL_AUX0 = 0x0409, GL_AUX3 = 0x040C,
    GL_AUX_BUFFERS = 0x0C00, GL_DRAW_BUFFER = 0x0C01, GL_READ_BUFFER = 0x0C02, GL_SCISSOR_TEST = 0x0C11, GL_VIEWPORT = 0x0BA2,
    GL_TEXTURE_2D = 0x0DE1, GL_TEXTURE_BINDING_2D = 0x8069, GL_RGBA = 0x1908, GL_UNSIGNED_BYTE = 0x1401, GL_RGBA8 = 0x8058,
    GL_NEAREST = 0x2600, GL_TEXTURE_MAG_FILTER = 0x2800, GL_TEXTURE_MIN_FILTER = 0x2801, GL_COLOR_BUFFER_BIT = 0x4000,
    GL_DRAW_BUFFER0 = 0x8825, GL_DEPTH24_STENCIL8 = 0x88F0, GL_DEPTH_STENCIL_ATTACHMENT = 0x821A,
    GL_FRAMEBUFFER_BINDING = 0x8CA6, GL_RENDERBUFFER_BINDING = 0x8CA7, GL_READ_FRAMEBUFFER = 0x8CA8,
    GL_DRAW_FRAMEBUFFER = 0x8CA9, GL_READ_FRAMEBUFFER_BINDING = 0x8CAA, GL_COLOR_ATTACHMENT0 = 0x8CE0,
    GL_FRAMEBUFFER = 0x8D40, GL_RENDERBUFFER = 0x8D41, GL_FRAMEBUFFER_COMPLETE = 0x8CD5,
};

static struct {
    void (*GetIntegerv)(unsigned, int *);
    void (*DrawBuffer)(unsigned);
    void (*ReadBuffer)(unsigned);
    void (*DrawBuffers)(int, const unsigned *);
    void (*BindFramebuffer)(unsigned, unsigned);
    void (*GenFramebuffers)(int, unsigned *);
    void (*GenTextures)(int, unsigned *);
    void (*GenRenderbuffers)(int, unsigned *);
    void (*BindTexture)(unsigned, unsigned);
    void (*BindRenderbuffer)(unsigned, unsigned);
    void (*TexImage2D)(unsigned, int, int, int, int, int, unsigned, unsigned, const void *);
    void (*TexParameteri)(unsigned, unsigned, int);
    void (*RenderbufferStorage)(unsigned, unsigned, int, int);
    void (*FramebufferTexture2D)(unsigned, unsigned, unsigned, unsigned, int);
    void (*FramebufferRenderbuffer)(unsigned, unsigned, unsigned, unsigned);
    unsigned (*CheckFramebufferStatus)(unsigned);
    void (*BlitFramebuffer)(int, int, int, int, int, int, int, int, unsigned, unsigned);
    unsigned char (*IsEnabled)(unsigned);
    void (*Enable)(unsigned);
    void (*Disable)(unsigned);
} gl;

static bool load(void) {
    static int loaded;
    if (loaded) return loaded > 0;
#define LOAD(name) (gl.name = (__typeof__(gl.name))perry_opengl_function("_gl" #name))
    bool all = LOAD(GetIntegerv) && LOAD(DrawBuffer) && LOAD(ReadBuffer) && LOAD(DrawBuffers) && LOAD(BindFramebuffer) &&
               LOAD(GenFramebuffers) && LOAD(GenTextures) && LOAD(GenRenderbuffers) && LOAD(BindTexture) &&
               LOAD(BindRenderbuffer) && LOAD(TexImage2D) && LOAD(TexParameteri) && LOAD(RenderbufferStorage) &&
               LOAD(FramebufferTexture2D) && LOAD(FramebufferRenderbuffer) && LOAD(CheckFramebufferStatus) &&
               LOAD(BlitFramebuffer) && LOAD(IsEnabled) && LOAD(Enable) && LOAD(Disable);
#undef LOAD
    loaded = all ? 1 : -1;
    return all;
}

// MARK: - The window

static void *library_function(const char *library, const char *name) {
    void *handle = dlopen(library, RTLD_LAZY | RTLD_NOLOAD);
    return handle ? dlsym(handle, name) : NULL;
}

/// The context current on this thread, EGL's or GLX's, to tell it from
/// another.
static void *current_context(void) {
    void *(*egl)(void) = (void *(*)(void))library_function("libEGL.so.1", "eglGetCurrentContext");
    void *context = egl ? egl() : NULL;
    if (context) return context;
    void *(*glx)(void) = (void *(*)(void))library_function("libGL.so.1", "glXGetCurrentContext");
    return glx ? glx() : NULL;
}

/// The window's size in pixels: its surface's, or without a way to ask,
/// what the viewport reaches.
static void window_size(int *width, int *height) {
    *width = *height = 0;
    void *(*display)(void) = (void *(*)(void))library_function("libEGL.so.1", "eglGetCurrentDisplay");
    void *(*surface)(int) = (void *(*)(int))library_function("libEGL.so.1", "eglGetCurrentSurface");
    unsigned (*query)(void *, void *, int, int *) = (unsigned (*)(void *, void *, int, int *))library_function("libEGL.so.1", "eglQuerySurface");
    void *drawn = display && surface && query ? surface(0x3059 /* EGL_DRAW */) : NULL;
    if (drawn && query(display(), drawn, 0x3057 /* EGL_WIDTH */, width) && query(display(), drawn, 0x3056 /* EGL_HEIGHT */, height) &&
        *width > 0 && *height > 0)
        return;
    void *(*x_display)(void) = (void *(*)(void))library_function("libGL.so.1", "glXGetCurrentDisplay");
    unsigned long (*x_drawable)(void) = (unsigned long (*)(void))library_function("libGL.so.1", "glXGetCurrentDrawable");
    void (*x_query)(void *, unsigned long, int, unsigned *) =
        (void (*)(void *, unsigned long, int, unsigned *))library_function("libGL.so.1", "glXQueryDrawable");
    if (x_display && x_drawable && x_query && x_display() && x_drawable()) {
        unsigned wide = 0, high = 0;
        x_query(x_display(), x_drawable(), 0x801D /* GLX_WIDTH */, &wide);
        x_query(x_display(), x_drawable(), 0x801E /* GLX_HEIGHT */, &high);
        if (wide > 0 && high > 0) {
            *width = (int)wide;
            *height = (int)high;
            return;
        }
    }
    int viewport[4] = {0, 0, 0, 0};
    gl.GetIntegerv(GL_VIEWPORT, viewport);
    *width = viewport[0] + viewport[2];
    *height = viewport[1] + viewport[3];
}

// MARK: - The framebuffer

enum { AUX_COUNT = 1, COLORS = 1 + AUX_COUNT };

static struct {
    void *context;
    unsigned framebuffer, colors[COLORS], depth;
    int width, height;
    /// The program's own framebuffer objects, bound over this one.
    unsigned draw_bound, read_bound;
} aux;

static bool active(void) { return aux.context && aux.context == current_context(); }

/// Storage of the window's size for the attachments.
static void allocate(int width, int height) {
    int texture = 0, renderbuffer = 0;
    gl.GetIntegerv(GL_TEXTURE_BINDING_2D, &texture);
    gl.GetIntegerv(GL_RENDERBUFFER_BINDING, &renderbuffer);
    for (int index = 0; index < COLORS; index++) {
        gl.BindTexture(GL_TEXTURE_2D, aux.colors[index]);
        gl.TexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
        gl.TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        gl.TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    }
    gl.BindRenderbuffer(GL_RENDERBUFFER, aux.depth);
    gl.RenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, width, height);
    gl.BindTexture(GL_TEXTURE_2D, (unsigned)texture);
    gl.BindRenderbuffer(GL_RENDERBUFFER, (unsigned)renderbuffer);
    aux.width = width;
    aux.height = height;
}

/// The window's buffer as this framebuffer's attachment: the back buffer
/// (and the front, which there is none of to draw into) is the first, an
/// auxiliary one follows. 0 for one there isn't.
static unsigned attachment(unsigned buffer) {
    if (buffer >= GL_FRONT_LEFT && buffer <= GL_FRONT_AND_BACK) return GL_COLOR_ATTACHMENT0;
    if (buffer >= GL_AUX0 && buffer < GL_AUX0 + AUX_COUNT) return GL_COLOR_ATTACHMENT0 + 1 + (buffer - GL_AUX0);
    return 0;
}

static unsigned window_buffer(unsigned attached, unsigned front_or_back) {
    if (attached == GL_COLOR_ATTACHMENT0) return front_or_back;
    if (attached > GL_COLOR_ATTACHMENT0 && attached < GL_COLOR_ATTACHMENT0 + COLORS) return GL_AUX0 + (attached - GL_COLOR_ATTACHMENT0 - 1);
    return attached;
}

/// Starts drawing into the framebuffer, with what the window's back buffer
/// has so far.
static bool activate(void) {
    if (!load()) return false;
    void *context = current_context();
    if (!context) return false;
    int bound = 0, width, height, draw = GL_BACK, read = GL_BACK;
    gl.GetIntegerv(GL_FRAMEBUFFER_BINDING, &bound);
    if (bound != 0) return false;
    window_size(&width, &height);
    if (width <= 0 || height <= 0) return false;
    gl.GetIntegerv(GL_DRAW_BUFFER, &draw);
    gl.GetIntegerv(GL_READ_BUFFER, &read);
    gl.GenFramebuffers(1, &aux.framebuffer);
    gl.GenTextures(COLORS, aux.colors);
    gl.GenRenderbuffers(1, &aux.depth);
    allocate(width, height);
    gl.BindFramebuffer(GL_FRAMEBUFFER, aux.framebuffer);
    for (int index = 0; index < COLORS; index++)
        gl.FramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0 + (unsigned)index, GL_TEXTURE_2D, aux.colors[index], 0);
    gl.FramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, aux.depth);
    if (gl.CheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        gl.BindFramebuffer(GL_FRAMEBUFFER, 0);
        return false;
    }
    // The frame so far.
    unsigned char scissor = gl.IsEnabled(GL_SCISSOR_TEST);
    if (scissor) gl.Disable(GL_SCISSOR_TEST);
    gl.BindFramebuffer(GL_READ_FRAMEBUFFER, 0);
    gl.ReadBuffer(GL_BACK);
    gl.DrawBuffer(GL_COLOR_ATTACHMENT0);
    gl.BlitFramebuffer(0, 0, width, height, 0, 0, width, height, GL_COLOR_BUFFER_BIT, GL_NEAREST);
    if (scissor) gl.Enable(GL_SCISSOR_TEST);
    gl.BindFramebuffer(GL_FRAMEBUFFER, aux.framebuffer);
    unsigned drawn = attachment((unsigned)draw), read_from = attachment((unsigned)read);
    gl.DrawBuffer(drawn ? drawn : GL_NONE);
    gl.ReadBuffer(read_from ? read_from : GL_COLOR_ATTACHMENT0);
    aux.context = context;
    aux.draw_bound = aux.read_bound = 0;
    return true;
}

// MARK: - The program's calls

static void aux_DrawBuffer(unsigned buffer) {
    if (!load()) return;
    if (!active() && buffer >= GL_AUX0 && buffer <= GL_AUX3) activate();
    if (active() && aux.draw_bound == 0 && buffer != GL_NONE) {
        unsigned attached = attachment(buffer);
        if (attached) {
            gl.DrawBuffer(attached);
            return;
        }
    }
    gl.DrawBuffer(buffer);
}

static void aux_ReadBuffer(unsigned buffer) {
    if (!load()) return;
    if (!active() && buffer >= GL_AUX0 && buffer <= GL_AUX3) activate();
    if (active() && aux.read_bound == 0 && buffer != GL_NONE) {
        unsigned attached = attachment(buffer);
        if (attached) {
            gl.ReadBuffer(attached);
            return;
        }
    }
    gl.ReadBuffer(buffer);
}

static void aux_DrawBuffers(int count, const unsigned *buffers) {
    if (!load()) return;
    unsigned mapped[16];
    if (active() && aux.draw_bound == 0 && buffers && count > 0 && count <= 16) {
        for (int index = 0; index < count; index++) {
            unsigned attached = attachment(buffers[index]);
            mapped[index] = attached ? attached : buffers[index];
        }
        buffers = mapped;
    }
    gl.DrawBuffers(count, buffers);
}

static void aux_BindFramebuffer(unsigned target, unsigned framebuffer) {
    if (!load()) return;
    if (active()) {
        if (target == GL_FRAMEBUFFER || target == GL_DRAW_FRAMEBUFFER) aux.draw_bound = framebuffer;
        if (target == GL_FRAMEBUFFER || target == GL_READ_FRAMEBUFFER) aux.read_bound = framebuffer;
        if (framebuffer == 0) framebuffer = aux.framebuffer;
    }
    gl.BindFramebuffer(target, framebuffer);
}

/// What the program asked about, as the window's: called after libGL
/// answered.
void perry_aux_integer(unsigned name, int *values) {
    if (!values) return;
    if (name == GL_AUX_BUFFERS) {
        if (values[0] < AUX_COUNT && load()) values[0] = AUX_COUNT;
        return;
    }
    if (!aux.context || !active()) return;
    switch (name) {
    case GL_FRAMEBUFFER_BINDING: case GL_READ_FRAMEBUFFER_BINDING:
        if ((unsigned)values[0] == aux.framebuffer) values[0] = 0;
        break;
    case GL_DRAW_BUFFER: case GL_DRAW_BUFFER0:
        if (aux.draw_bound == 0) values[0] = (int)window_buffer((unsigned)values[0], GL_BACK);
        break;
    case GL_READ_BUFFER:
        if (aux.read_bound == 0) values[0] = (int)window_buffer((unsigned)values[0], GL_BACK);
        break;
    }
}

// MARK: - Swapping

static struct { bool pending; int read; unsigned char scissor; } swap;

/// Before the window's buffers swap: the back buffer's attachment goes to
/// the window, and attachments follow a window that changed size.
void perry_aux_before_swap(void) {
    swap.pending = false;
    if (!aux.context || !active()) return;
    gl.GetIntegerv(GL_READ_BUFFER, &swap.read);
    swap.scissor = gl.IsEnabled(GL_SCISSOR_TEST);
    if (swap.scissor) gl.Disable(GL_SCISSOR_TEST);
    gl.BindFramebuffer(GL_READ_FRAMEBUFFER, aux.framebuffer);
    gl.ReadBuffer(GL_COLOR_ATTACHMENT0);
    gl.BindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
    gl.DrawBuffer(GL_BACK);
    int width, height;
    window_size(&width, &height);
    gl.BlitFramebuffer(0, 0, aux.width, aux.height, 0, 0, aux.width, aux.height, GL_COLOR_BUFFER_BIT, GL_NEAREST);
    if (width > 0 && height > 0 && (width != aux.width || height != aux.height)) allocate(width, height);
    swap.pending = true;
}

void perry_aux_after_swap(void) {
    if (!swap.pending) return;
    swap.pending = false;
    gl.BindFramebuffer(GL_DRAW_FRAMEBUFFER, aux.draw_bound ? aux.draw_bound : aux.framebuffer);
    gl.BindFramebuffer(GL_READ_FRAMEBUFFER, aux.read_bound ? aux.read_bound : aux.framebuffer);
    if (aux.read_bound == 0) gl.ReadBuffer((unsigned)swap.read);
    if (swap.scissor) gl.Enable(GL_SCISSOR_TEST);
}

/// The context's own function for one of the names this replaces.
void *perry_aux_symbol(const char *name) {
    static const struct { const char *name; void *function; } replaced[] = {
        {"_glDrawBuffer", (void *)aux_DrawBuffer}, {"_glReadBuffer", (void *)aux_ReadBuffer},
        {"_glDrawBuffers", (void *)aux_DrawBuffers}, {"_glDrawBuffersARB", (void *)aux_DrawBuffers},
        {"_glBindFramebuffer", (void *)aux_BindFramebuffer}, {"_glBindFramebufferEXT", (void *)aux_BindFramebuffer},
    };
    for (size_t index = 0; index < sizeof replaced / sizeof replaced[0]; index++) {
        const char *left = name, *right = replaced[index].name;
        while (*left && *left == *right) left++, right++;
        if (!*left && !*right) return replaced[index].function;
    }
    return NULL;
}
