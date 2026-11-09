// libPerryOpenGL: the provider for a Mac program's OpenGL.framework, over
// Linux's libGL. The gl* functions have the same names, arguments and calling
// convention on both, so every import binds by name, to libGL's dispatch to
// the context current on the thread. AppKit's NSOpenGLContext makes contexts.

#include "PerryOpenGL.h"
#include "perry_wrapped.h"

#include <dlfcn.h>
#include <string.h>

static perry_wrapped_library gl = PERRY_WRAPPED_SONAME("libGL.so.1");

__attribute__((visibility("default")))
void *perry_provider_symbol(const char *name) {
    void *symbol = perry_wrapped_symbol(&gl, name, NULL);
    // That checks where the symbol came from, which dladdr can't tell through
    // an emulator's native libGL. A gl name is only ever libGL's.
    if (!symbol && gl.handle && strncmp(name, "_gl", 3) == 0 && name[3] >= 'A' && name[3] <= 'Z')
        symbol = dlsym(gl.handle, name + 1);
    return symbol;
}
