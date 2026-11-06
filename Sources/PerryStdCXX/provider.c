// libPerryStdCXX: the provider for /usr/lib/libstdc++.6.dylib, the GNU
// C++ library apps built before libc++ link, over Linux's libstdc++.
//
// Apple's libstdc++ is GCC 4.2's, and Linux's still exports that ABI
// beside its newer one: the copy-on-write std::string ("Ss"), the list
// node hooks, the streams. On arm64 both mangle size_t as "m", so every
// import binds by name ("__ZNSs6assignEPKcm" is "_ZNSs6assignEPKcm"), as
// do operator new and delete, the __cxa functions and the type_info
// vtables. The process already has the library: Swift's runtime links it.

#include "PerryStdCXX.h"
#include "perry_wrapped.h"

static perry_wrapped_library stdcxx = PERRY_WRAPPED_SONAME("libstdc++.so.6");

__attribute__((visibility("default")))
void *perry_provider_symbol(const char *name) {
    return perry_wrapped_symbol(&stdcxx, name, NULL);
}
