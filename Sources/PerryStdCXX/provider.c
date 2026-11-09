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

#if defined(__i386__)
// A function returning a small structure, such as a string's iterators:
// Darwin returns it in eax, Linux through a hidden pointer before the
// arguments, which the callee pops. These make Linux's call and return the
// word Darwin's callers look for in eax. reverse_iterator has a copy
// constructor of its own, so both return it through a pointer: no thunks.
void *perry_stdcxx_sret(void *function, void *a, void *b, void *c);

#define THUNK1(id, mach)                                                                   \
    static void *id(void *a) {                                                             \
        static void *function;                                                             \
        if (!function) function = perry_wrapped_symbol(&stdcxx, mach, NULL);               \
        return perry_stdcxx_sret(function, a, NULL, NULL);                                                         \
    }
#define THUNK2(id, mach)                                                                   \
    static void *id(void *a, void *b) {                                                    \
        static void *function;                                                             \
        if (!function) function = perry_wrapped_symbol(&stdcxx, mach, NULL);               \
        return perry_stdcxx_sret(function, a, b, NULL);                                                      \
    }
#define THUNK3(id, mach)                                                                   \
    static void *id(void *a, void *b, void *c) {                                           \
        static void *function;                                                             \
        if (!function) function = perry_wrapped_symbol(&stdcxx, mach, NULL);               \
        return perry_stdcxx_sret(function, a, b, c);                                                   \
    }

#define STRING "__ZNSs"
#define CONST_STRING "__ZNKSs"
#define WSTRING "__ZNSbIwSt11char_traitsIwESaIwEE"
#define CONST_WSTRING "__ZNKSbIwSt11char_traitsIwESaIwEE"

#define ACCESSORS(prefix, tag)                         \
    THUNK1(tag##_begin, prefix "5beginEv")             \
    THUNK1(tag##_end, prefix "3endEv")

ACCESSORS(STRING, string)
ACCESSORS(CONST_STRING, const_string)
ACCESSORS(WSTRING, wstring)
ACCESSORS(CONST_WSTRING, const_wstring)

#define STRING_ITERATOR "N9__gnu_cxx17__normal_iteratorIPcSsEE"
#define WSTRING_ITERATOR "N9__gnu_cxx17__normal_iteratorIPwS2_EE"

THUNK2(string_erase, STRING "5eraseE" STRING_ITERATOR)
THUNK3(string_erase_range, STRING "5eraseE" STRING_ITERATOR "S2_")
THUNK3(string_insert, STRING "6insertE" STRING_ITERATOR "c")
THUNK2(wstring_erase, WSTRING "5eraseE" WSTRING_ITERATOR)
THUNK3(wstring_erase_range, WSTRING "5eraseE" WSTRING_ITERATOR "S6_")
THUNK3(wstring_insert, WSTRING "6insertE" WSTRING_ITERATOR "w")

#define ENTRY(prefix, tag)                             \
    { prefix "5beginEv", tag##_begin },                \
    { prefix "3endEv", tag##_end }

static const struct { const char *name; void *thunk; } iterator_returns[] = {
    ENTRY(STRING, string), ENTRY(CONST_STRING, const_string),
    ENTRY(WSTRING, wstring), ENTRY(CONST_WSTRING, const_wstring),
    { STRING "5eraseE" STRING_ITERATOR, string_erase },
    { STRING "5eraseE" STRING_ITERATOR "S2_", string_erase_range },
    { STRING "6insertE" STRING_ITERATOR "c", string_insert },
    { WSTRING "5eraseE" WSTRING_ITERATOR, wstring_erase },
    { WSTRING "5eraseE" WSTRING_ITERATOR "S6_", wstring_erase_range },
    { WSTRING "6insertE" WSTRING_ITERATOR "w", wstring_insert },
};
#endif

__attribute__((visibility("default")))
void *perry_provider_symbol(const char *name) {
#if defined(__i386__)
    for (size_t i = 0; name && i < sizeof(iterator_returns) / sizeof(iterator_returns[0]); i++)
        if (strcmp(name, iterator_returns[i].name) == 0)
            return iterator_returns[i].thunk;
#endif
    void *symbol = perry_wrapped_symbol(&stdcxx, name, NULL);
#if defined(__arm__)
    char other[512];
    if (!symbol && name && as_unsigned_int(name, other, sizeof other))
        symbol = perry_wrapped_symbol(&stdcxx, other, NULL);
#endif
    return symbol;
}
