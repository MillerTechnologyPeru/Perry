// libPerryexpat: the provider for /usr/lib/libexpat.1.dylib, over Linux's
// libexpat. Expat's parser is opaque, its handlers are not variadic, and
// the API is the same, so every import binds to Linux's library. Functions
// newer than Ubuntu's Expat (2.6) stay unresolved.

#include "PerryExpat.h"
#include "perry_wrapped.h"

extern const char *XML_ExpatVersion(void);

static perry_wrapped_library expat = PERRY_WRAPPED_LIBRARY(XML_ExpatVersion);

__attribute__((visibility("default")))
void *perry_provider_symbol(const char *name) {
    return perry_wrapped_symbol(&expat, name, NULL);
}
