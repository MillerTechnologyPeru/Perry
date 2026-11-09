// libPerryOpenGL: the provider for a Mac program's OpenGL.framework, over
// Linux's libGL. The gl* functions have the same names, arguments and calling
// convention on both, so every import binds by name, to libGL's dispatch to
// the context current on the thread. AppKit's NSOpenGLContext makes contexts.

#include "PerryOpenGL.h"
#include "perry_wrapped.h"

static perry_wrapped_library gl = PERRY_WRAPPED_SONAME("libGL.so.1");

__attribute__((visibility("default")))
void *perry_provider_symbol(const char *name) {
    return perry_wrapped_symbol(&gl, name, NULL);
}
