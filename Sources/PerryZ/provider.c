// libPerryz: the provider for /usr/lib/libz.1.dylib, over Linux's zlib.
//
// The iOS SDK's zlib (1.2.12) and Ubuntu's (1.3) share z_stream and the
// rest of the API, so every import binds to Linux's zlib except gzprintf,
// whose variadic arguments thunks.S converts.

#include "PerryZ.h"
#include "perry_wrapped.h"

extern const char *zlibVersion(void);

static perry_wrapped_library zlib = PERRY_WRAPPED_LIBRARY(zlibVersion);

__attribute__((visibility("default")))
void *perry_provider_symbol(const char *name) {
    return perry_wrapped_symbol(&zlib, name, NULL);
}
