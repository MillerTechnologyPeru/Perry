// libPerryOpenGL: the provider for a Mac program's OpenGL.framework, over
// Linux's libGL. The gl* functions have the same names, arguments and calling
// convention on both, so every import binds by name, to libGL's dispatch to
// the context current on the thread. AppKit's NSOpenGLContext makes contexts.

#include "PerryOpenGL.h"
#include "perry_wrapped.h"

#include <dlfcn.h>
#include <string.h>

static perry_wrapped_library gl = PERRY_WRAPPED_SONAME("libGL.so.1");

/// glGetString, with the shading language version a Mac's legacy (2.1)
/// context reports, 1.20, for contexts made without a core profile pixel
/// format: Linux's compatibility contexts report their newest (4.60), and
/// programs that put that in their shaders' #version line get the core
/// language, which has none of the built-in variables (gl_TexCoord) their
/// shaders were written to use.
static const unsigned char *perry_glGetString(unsigned int name) {
    static const unsigned char *(*get_string)(unsigned int);
    if (!get_string) {
        void *symbol = perry_wrapped_symbol(&gl, "_glGetString", NULL);
        if (!symbol && gl.handle) symbol = dlsym(gl.handle, "glGetString");
        get_string = (const unsigned char *(*)(unsigned int))symbol;
    }
    if (name == 0x8B8C /* GL_SHADING_LANGUAGE_VERSION */ && !perry_cgl_current_is_core())
        return (const unsigned char *)"1.20";
    return get_string ? get_string(name) : NULL;
}

/// gluCheckExtension: whether a name is one of a list's, which spaces part.
/// OpenGL.framework has GLU's functions with its own.
__attribute__((visibility("default"), used))
unsigned char perry_gluCheckExtension(const unsigned char *name, const unsigned char *list) __asm__("_gluCheckExtension");
unsigned char perry_gluCheckExtension(const unsigned char *name, const unsigned char *list) {
    if (!name || !list) return 0;
    size_t length = strlen((const char *)name);
    if (length == 0) return 0;
    for (const char *cursor = (const char *)list; *cursor;) {
        while (*cursor == ' ') cursor++;
        size_t word = strcspn(cursor, " ");
        if (word == length && strncmp(cursor, (const char *)name, length) == 0) return 1;
        cursor += word;
    }
    return 0;
}

__attribute__((visibility("default")))
void *perry_provider_symbol(const char *name) {
    if (strcmp(name, "_glGetString") == 0) return (void *)perry_glGetString;
    void *symbol = perry_wrapped_symbol(&gl, name, NULL);
    // That checks where the symbol came from, which dladdr can't tell through
    // an emulator's native libGL. A gl name is only ever libGL's.
    if (!symbol && gl.handle && strncmp(name, "_gl", 3) == 0 && name[3] >= 'A' && name[3] <= 'Z')
        symbol = dlsym(gl.handle, name + 1);
    return symbol;
}
