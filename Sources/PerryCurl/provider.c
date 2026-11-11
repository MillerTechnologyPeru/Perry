// libPerrycurl: the provider for /usr/lib/libcurl.4.dylib, over Linux's
// libcurl 4. Its handles are opaque and the structures a program sees
// (CURLMsg, curl_slist, the fd_sets curl_multi_fdset fills, 1024 bits on
// both) are laid out alike, its option and info numbers are curl's own on
// every system, and its callbacks have the C calling convention. Its
// variadic functions (curl_easy_setopt, curl_easy_getinfo, curl_multi_setopt)
// take their one argument after the option as both systems pass variadic
// arguments on i386 and x86_64; arm64's Darwin passes them differently, so
// there they are not bound. libcurl is opened by its soname, so where it
// isn't installed its imports stay unresolved and only fail if called.

#include "PerryCurl.h"
#include "perry_wrapped.h"

#include <string.h>

static perry_wrapped_library curl = PERRY_WRAPPED_SONAME("libcurl.so.4");

__attribute__((visibility("default")))
void *perry_provider_symbol(const char *name) {
#if defined(__aarch64__)
    if (name && (strcmp(name, "_curl_easy_setopt") == 0 || strcmp(name, "_curl_easy_getinfo") == 0 ||
                 strcmp(name, "_curl_multi_setopt") == 0 || strcmp(name, "_curl_share_setopt") == 0 ||
                 strcmp(name, "_curl_formadd") == 0 || strcmp(name, "_curl_mprintf") == 0))
        return NULL;
#endif
    return perry_wrapped_symbol(&curl, name, NULL);
}
