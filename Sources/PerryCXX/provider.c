// libPerryCXX: the provider for /usr/lib/libc++.1.dylib and
// /usr/lib/libc++abi.dylib, over LLVM's libc++ and libc++abi built as
// Apple builds them for arm64 (libperry-c++, see the Dockerfile).
//
// Darwin's libc++ is LLVM's, with the same Itanium mangling and the same
// std::__1 inline namespace, so its imports bind by name ("__ZNSt3__1…" is
// "_ZNSt3__1…"). Each library is opened on its own: the process already
// has libstdc++, whose __cxa functions and type_info vtables share
// libc++abi's names but are not the same objects.

#include "PerryCXX.h"
#include "perry_wrapped.h"

#include <stddef.h>
#include <stdio.h>
#include <string.h>

static perry_wrapped_library cxx = PERRY_WRAPPED_SONAME("libperry-c++.so.1");
static perry_wrapped_library cxxabi = PERRY_WRAPPED_SONAME("libperry-c++abi.so.1");

// Darwin's typed operator new and delete take the allocated type's
// descriptor as an extra last argument, for its allocator to sort memory
// by; the plain operators, which ignore it, stand in for them.
static const char type_descriptor[] = "St19__type_descriptor_t";

static void *library_symbol(const char *name) {
    void *symbol = perry_wrapped_symbol(&cxx, name, NULL);
    return symbol ? symbol : perry_wrapped_symbol(&cxxabi, name, NULL);
}

__attribute__((visibility("default")))
void *perry_provider_symbol(const char *name) {
    void *symbol = library_symbol(name);
    const char *typed = strstr(name, type_descriptor);
    if (!symbol && typed && (strncmp(name, "__Znw", 5) == 0 || strncmp(name, "__Zna", 5) == 0 ||
                             strncmp(name, "__Zdl", 5) == 0 || strncmp(name, "__Zda", 5) == 0)) {
        char plain[256];
        snprintf(plain, sizeof(plain), "%.*s%s", (int)(typed - name), name, typed + strlen(type_descriptor));
        symbol = library_symbol(plain);
    }
    return symbol;
}
