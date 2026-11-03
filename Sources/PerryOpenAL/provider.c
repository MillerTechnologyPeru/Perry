// libPerryOpenAL: the provider for OpenAL.framework, over OpenAL Soft.
//
// Apple's OpenAL implements the same OpenAL 1.1 C API, with plain
// functions and no variadics, so every import binds by name. OpenAL Soft
// is opened when first asked for; without it, the imports stay unbound.

#include "PerryOpenAL.h"
#include "perry_wrapped.h"

static perry_wrapped_library openal = PERRY_WRAPPED_SONAME("libopenal.so.1");

__attribute__((visibility("default")))
void *perry_provider_symbol(const char *name) {
    return perry_wrapped_symbol(&openal, name, NULL);
}
