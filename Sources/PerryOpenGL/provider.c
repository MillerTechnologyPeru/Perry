// libPerryOpenGL: the provider for a Mac program's OpenGL.framework, over
// Linux's libGL. The gl* functions have the same names, arguments and calling
// convention on both, so every import binds by name, to libGL's dispatch to
// the context current on the thread. AppKit's NSOpenGLContext makes contexts.

#include "PerryOpenGL.h"
#include "perry_wrapped.h"

#include <dlfcn.h>
#include <stdlib.h>
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

/// glGetIntegerv, with texture units no more than a Mac's drivers report,
/// 16: Direct3D 9 has that many samplers, and games ported from it keep
/// that many in arrays that a count of Linux's (32 and more) runs past.
static void perry_glGetIntegerv(unsigned int name, int *values) {
    static void (*get_integer)(unsigned int, int *);
    if (!get_integer) {
        void *symbol = perry_wrapped_symbol(&gl, "_glGetIntegerv", NULL);
        if (!symbol && gl.handle) symbol = dlsym(gl.handle, "glGetIntegerv");
        get_integer = (void (*)(unsigned int, int *))symbol;
    }
    if (!get_integer) return;
    get_integer(name, values);
    switch (name) {
    case 0x8872:   // GL_MAX_TEXTURE_IMAGE_UNITS
    case 0x8B4C:   // GL_MAX_VERTEX_TEXTURE_IMAGE_UNITS
    case 0x8B4D:   // GL_MAX_COMBINED_TEXTURE_IMAGE_UNITS
    case 0x8871:   // GL_MAX_TEXTURE_COORDS
        if (values && values[0] > 16) values[0] = 16;
        break;
    }
}

static void *gl_function(const char *name) {
    void *symbol = perry_wrapped_symbol(&gl, name, NULL);
    if (!symbol && gl.handle) symbol = dlsym(gl.handle, name + 1);
    return symbol;
}

/// glProgramString(ARB), with a classic Mac's line ends, carriage returns
/// alone, made Linux's: Mac programs' assembly shaders end their lines
/// so, which a Mac's drivers take and Mesa's parser doesn't.
static void perry_glProgramString(unsigned int target, unsigned int format, int length, const void *string) {
    static void (*program_string)(unsigned int, unsigned int, int, const void *);
    if (!program_string) program_string = (void (*)(unsigned int, unsigned int, int, const void *))gl_function("_glProgramStringARB");
    if (!program_string) return;
    const char *text = string;
    if (!text || length <= 0 || !memchr(text, '\r', (size_t)length)) {
        program_string(target, format, length, string);
        return;
    }
    char *copy = malloc((size_t)length);
    if (!copy) {
        program_string(target, format, length, string);
        return;
    }
    for (int index = 0; index < length; index++)
        copy[index] = text[index] == '\r' && (index + 1 == length || text[index + 1] != '\n') ? '\n' : text[index];
    program_string(target, format, length, copy);
    free(copy);
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
    if (strcmp(name, "_glGetIntegerv") == 0) return (void *)perry_glGetIntegerv;
    if (strcmp(name, "_glProgramStringARB") == 0) return (void *)perry_glProgramString;
    void *symbol = perry_wrapped_symbol(&gl, name, NULL);
    // That checks where the symbol came from, which dladdr can't tell through
    // an emulator's native libGL. A gl name is only ever libGL's.
    if (!symbol && gl.handle && strncmp(name, "_gl", 3) == 0 && name[3] >= 'A' && name[3] <= 'Z')
        symbol = dlsym(gl.handle, name + 1);
    return symbol;
}
