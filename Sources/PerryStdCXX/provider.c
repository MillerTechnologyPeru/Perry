// libPerryStdCXX: the provider for /usr/lib/libstdc++.6.dylib, the GNU
// C++ library apps built before libc++ link, over Linux's libstdc++.
//
// Apple's libstdc++ is GCC 4.2's, and Linux's still exports that ABI
// beside its newer one: the copy-on-write std::string ("Ss"), the list
// node hooks, the streams. On arm64 both mangle size_t as "m", so every
// import binds by name ("__ZNSs6assignEPKcm" is "_ZNSs6assignEPKcm"), as
// do operator new and delete, the __cxa functions and the type_info
// vtables. The process already has the library: Swift's runtime links it.
//
// On armv7 Darwin's size_t is unsigned long ("m") and Linux's unsigned int
// ("j"), both 32 bits: a name not found as it is is looked up again with
// its "m" types as "j" ("__Znwm" is "_Znwj").

#include "PerryStdCXX.h"
#include "perry_wrapped.h"

#include <ctype.h>
#include <string.h>

static perry_wrapped_library stdcxx = PERRY_WRAPPED_SONAME("libstdc++.so.6");

#if defined(__arm__)
/// `name` with each unsigned long type ("m") as unsigned int ("j"), skipping
/// identifiers, which a length leads ("6assign"). False if it has none.
static int as_unsigned_int(const char *name, char *out, size_t size) {
    size_t length = strlen(name);
    if (length >= size)
        return 0;
    int changed = 0;
    size_t i = 0;
    while (i < length) {
        if (isdigit((unsigned char)name[i])) {
            size_t count = 0;
            while (i < length && isdigit((unsigned char)name[i])) {
                count = count * 10 + (size_t)(name[i] - '0');
                out[i] = name[i];
                i++;
            }
            for (size_t end = i + count; i < end && i < length; i++)
                out[i] = name[i];
            continue;
        }
        if (name[i] == 'm' && i > 0) {
            out[i++] = 'j';
            changed = 1;
            continue;
        }
        out[i] = name[i];
        i++;
    }
    out[length] = 0;
    return changed;
}
#endif

__attribute__((visibility("default")))
void *perry_provider_symbol(const char *name) {
    void *symbol = perry_wrapped_symbol(&stdcxx, name, NULL);
#if defined(__arm__)
    char other[512];
    if (!symbol && name && as_unsigned_int(name, other, sizeof other))
        symbol = perry_wrapped_symbol(&stdcxx, other, NULL);
#endif
    return symbol;
}
