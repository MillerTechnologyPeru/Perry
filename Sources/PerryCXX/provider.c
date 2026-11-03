// libPerryCXX: the provider for /usr/lib/libc++.1.dylib and
// /usr/lib/libc++abi.dylib, over LLVM's libc++ and libc++abi for Linux.
//
// Darwin's libc++ is LLVM's, with the same Itanium mangling, the same
// std::__1 inline namespace and, on arm64, the same layouts, so its imports
// bind by name ("__ZNSt3__1…" is "_ZNSt3__1…"). Each library is opened on
// its own: the process already has libstdc++, whose __cxa functions and
// type_info vtables share libc++abi's names but are not the same objects.

#include "PerryCXX.h"
#include "perry_wrapped.h"

#include <stddef.h>

static perry_wrapped_library cxx = PERRY_WRAPPED_SONAME("libc++.so.1");
static perry_wrapped_library cxxabi = PERRY_WRAPPED_SONAME("libc++abi.so.1");

__attribute__((visibility("default")))
void *perry_provider_symbol(const char *name) {
    void *symbol = perry_wrapped_symbol(&cxx, name, NULL);
    return symbol ? symbol : perry_wrapped_symbol(&cxxabi, name, NULL);
}
