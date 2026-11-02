// libPerrybz2: the provider for /usr/lib/libbz2.1.0.dylib, over Linux's
// libbz2. bzip2 1.0's API, bz_stream included, is the same on both and has
// nothing variadic, so every import binds to Linux's library.

#include "PerryBZ2.h"
#include "perry_wrapped.h"

extern const char *BZ2_bzlibVersion(void);

static perry_wrapped_library bzip2 = PERRY_WRAPPED_LIBRARY(BZ2_bzlibVersion);

__attribute__((visibility("default")))
void *perry_provider_symbol(const char *name) {
    return perry_wrapped_symbol(&bzip2, name, NULL);
}
