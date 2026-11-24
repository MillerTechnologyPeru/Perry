// libPerryOpenGL: the provider for a Mac program's OpenGL.framework, over
// Linux's libGL. The gl* functions have the same names, arguments and calling
// convention on both, so every import binds by name, to libGL's dispatch to
// the context current on the thread. AppKit's NSOpenGLContext makes contexts.

#include "PerryOpenGL.h"
#include "perry_wrapped.h"

#include <dlfcn.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

static perry_wrapped_library gl = PERRY_WRAPPED_SONAME("libGL.so.1");

/// glGetString, with the shading language version a Mac's legacy (2.1)
/// context reports, 1.20, for contexts made without a core profile pixel
/// format: Linux's compatibility contexts report their newest (4.60), and
/// programs that put that in their shaders' #version line get the core
/// language, which has none of the built-in variables (gl_TexCoord) their
/// shaders were written to use.
static void *gl_function(const char *name);

/// GL_EXTENSIONS as a Mac's: with GL_APPLE_vertex_array_object, which every
/// Mac's driver has and Linux's lack, made of ARB_vertex_array_object's
/// functions (perry_provider_symbol), when the host has those; Age of
/// Empires III uses vertex array objects without checking further. For a
/// 32-bit program it's also no longer than a 32-bit Mac's drivers made it,
/// a few thousand bytes: programs of their time copy it into a buffer of
/// about that size (Age of Empires III's is 4 KB), which Linux's list, many
/// times longer, runs past. It's cut at a name's end; Mesa lists the oldest
/// first, so the names those programs look for are kept.
static const unsigned char *mac_extensions(const unsigned char *full) {
    static const char apple_vao[] = "GL_APPLE_vertex_array_object";
#if defined(__i386__)
    enum { LIMIT = 4000 };
#else
    enum { LIMIT = 1 << 16 };
#endif
    static const unsigned char *source;
    static char made[LIMIT + sizeof apple_vao + 1];
    if (!full) return full;
    bool add = !strstr((const char *)full, apple_vao) && gl_function("_glBindVertexArray");
    size_t length = strlen((const char *)full);
    if (!add && length <= LIMIT) return full;
    if (full != source) {
        if (length > LIMIT) {
            length = LIMIT;
            while (length > 0 && full[length] != ' ') length--;
        }
        memcpy(made, full, length);
        made[length] = 0;
        if (add) {
            if (length > 0 && made[length - 1] != ' ') strcat(made, " ");
            strcat(made, apple_vao);
        }
        source = full;
    }
    return (const unsigned char *)made;
}

static const unsigned char *perry_glGetString(unsigned int name) {
    static const unsigned char *(*get_string)(unsigned int);
    if (!get_string) {
        void *symbol = perry_wrapped_symbol(&gl, "_glGetString", NULL);
        if (!symbol && gl.handle) symbol = dlsym(gl.handle, "glGetString");
        get_string = (const unsigned char *(*)(unsigned int))symbol;
    }
    if (name == 0x8B8C /* GL_SHADING_LANGUAGE_VERSION */ && !perry_cgl_current_is_core())
        return (const unsigned char *)"1.20";
    if (name == 0x1F03 /* GL_EXTENSIONS */ && get_string) return mac_extensions(get_string(name));
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

/// What an ALIAS of a binding should have been declared as: OUTPUT for a
/// result, ATTRIB for a vertex's or a fragment's attribute, PARAM for a
/// program's or the state's parameter; NULL for an ALIAS of a variable,
/// which is what the language has ALIAS for.
static const char *alias_declaration(const char *text, const char *end) {
    const char *cursor = text;
    while (cursor < end && *cursor != '=' && *cursor != ';' && *cursor != '\n' && *cursor != '\r') cursor++;
    if (cursor >= end || *cursor != '=') return NULL;
    cursor++;
    while (cursor < end && (*cursor == ' ' || *cursor == '\t')) cursor++;
    size_t left = (size_t)(end - cursor);
    if (left >= 7 && memcmp(cursor, "result.", 7) == 0) return "OUTPUT";
    if (left >= 7 && memcmp(cursor, "vertex.", 7) == 0) return "ATTRIB";
    if (left >= 9 && memcmp(cursor, "fragment.", 9) == 0) return "ATTRIB";
    if (left >= 8 && memcmp(cursor, "program.", 8) == 0) return "PARAM";
    if (left >= 6 && memcmp(cursor, "state.", 6) == 0) return "PARAM";
    return NULL;
}

/// glProgramString(ARB), with what a Mac's drivers take and Mesa's parser
/// doesn't made right: a classic Mac's line ends, carriage returns alone,
/// become Linux's; and an ALIAS that names a binding ("ALIAS oPos =
/// result.position;", as MacSoft's Halo declares every output of its vertex
/// programs) becomes the declaration the language has for it.
static void perry_glProgramString(unsigned int target, unsigned int format, int length, const void *string) {
    static void (*program_string)(unsigned int, unsigned int, int, const void *);
    if (!program_string) program_string = (void (*)(unsigned int, unsigned int, int, const void *))gl_function("_glProgramStringARB");
    if (!program_string) return;
    const char *text = string;
    if (!text || length <= 0) {
        program_string(target, format, length, string);
        return;
    }
    const char *end = text + length;
    // "OUTPUT" and "ATTRIB" are a byte longer than "ALIAS": at most one
    // more for each five there are.
    char *copy = malloc((size_t)length + (size_t)length / 5 + 1);
    if (!copy) {
        program_string(target, format, length, string);
        return;
    }
    size_t written = 0;
    bool changed = false, line_start = true, comment = false;
    for (const char *cursor = text; cursor < end; cursor++) {
        char character = *cursor;
        if (character == '\r' && (cursor + 1 == end || cursor[1] != '\n')) {
            character = '\n';
            changed = true;
        }
        if (character == '\n') {
            comment = false;
            line_start = true;
            copy[written++] = character;
            continue;
        }
        if (character == '#') comment = true;
        if (line_start && !comment && end - cursor > 5 && memcmp(cursor, "ALIAS", 5) == 0 && (cursor[5] == ' ' || cursor[5] == '\t')) {
            const char *declaration = alias_declaration(cursor + 5, end);
            if (declaration) {
                size_t size = strlen(declaration);
                memcpy(copy + written, declaration, size);
                written += size;
                cursor += 4;
                changed = true;
                line_start = false;
                continue;
            }
        }
        // A statement starts a line, or follows the one before it.
        if (character == ';') line_start = true;
        else if (character != ' ' && character != '\t') line_start = false;
        copy[written++] = character;
    }
    if (changed) program_string(target, format, (int)written, copy);
    else program_string(target, format, length, string);
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
    // APPLE_vertex_array_object's functions are ARB_vertex_array_object's,
    // which a compatibility context's client arrays work with too.
    static const char *const apple_vao[][2] = {
        {"_glBindVertexArrayAPPLE", "_glBindVertexArray"}, {"_glDeleteVertexArraysAPPLE", "_glDeleteVertexArrays"},
        {"_glGenVertexArraysAPPLE", "_glGenVertexArrays"}, {"_glIsVertexArrayAPPLE", "_glIsVertexArray"},
    };
    for (size_t index = 0; index < sizeof apple_vao / sizeof apple_vao[0]; index++)
        if (strcmp(name, apple_vao[index][0]) == 0) return gl_function(apple_vao[index][1]);
    void *symbol = perry_wrapped_symbol(&gl, name, NULL);
    // That checks where the symbol came from, which dladdr can't tell through
    // an emulator's native libGL. A gl name is only ever libGL's.
    if (!symbol && gl.handle && strncmp(name, "_gl", 3) == 0 && name[3] >= 'A' && name[3] <= 'Z')
        symbol = dlsym(gl.handle, name + 1);
    return symbol;
}
