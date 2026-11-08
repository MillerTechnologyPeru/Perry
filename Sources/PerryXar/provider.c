// libPerryxar: the provider for /usr/lib/libxar.1.dylib, over Linux's libxar,
// which Debian builds from Apple's sources. Its handles are opaque and
// xar_stream, the one structure its functions take, is the same on both. It
// is opened by its soname, so where it isn't installed its imports stay
// unresolved and only fail if called: Sparkle reads binary delta updates
// with it.

#include "PerryXar.h"
#include "perry_wrapped.h"

#include <string.h>

static perry_wrapped_library xar = PERRY_WRAPPED_SONAME("libxar.so.1");

__attribute__((visibility("default")))
void *perry_provider_symbol(const char *name) {
#if !defined(__x86_64__)
    // Variadic, with no va_list form to thunk to; only x86_64 passes
    // Darwin's variadic arguments as Linux does.
    if (name && strcmp(name, "_xar_err_set_formatted_string") == 0)
        return NULL;
#endif
    return perry_wrapped_symbol(&xar, name, NULL);
}
