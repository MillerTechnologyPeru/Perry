// Resolving Darwin imports in the Linux library a provider wraps.

#define _GNU_SOURCE
#include "perry_wrapped.h"

#include <dlfcn.h>
#include <link.h>
#include <string.h>

static void load(perry_wrapped_library *library) {
    Dl_info info;
    if (library->soname) {
        // Its own symbols and its dependencies' before the process's: a
        // namesake that is among the global ones (libstdc++ is, once
        // something loaded for all to see depends on it) would otherwise
        // take the place of the library's own, when its references to
        // itself are bound.
        int own_first = 0;
#ifdef RTLD_DEEPBIND
        own_first = RTLD_DEEPBIND;
#endif
        library->handle = dlopen(library->soname, RTLD_NOW | RTLD_LOCAL | own_first);
        struct link_map *map = NULL;
        if (library->handle && dlinfo(library->handle, RTLD_DI_LINKMAP, &map) == 0 && map)
            library->base = (void *)map->l_addr;
    } else if (dladdr(library->anchor, &info)) {
        library->base = info.dli_fbase;
        library->handle = dlopen(info.dli_fname, RTLD_NOW | RTLD_NOLOAD);
    }
    library->loaded = 1;
}

void *perry_wrapped_symbol(perry_wrapped_library *library, const char *name, const char *const *allowed) {
    pthread_mutex_lock(&library->lock);
    if (!library->loaded)
        load(library);
    pthread_mutex_unlock(&library->lock);
    if (!library->handle || !name || name[0] != '_')
        return NULL;
    const char *linux_name = name + 1;
    if (allowed) {
        const char *const *entry = allowed;
        while (*entry && strcmp(*entry, linux_name) != 0)
            entry++;
        if (!*entry)
            return NULL;
    }
    void *symbol = dlsym(library->handle, linux_name);
    Dl_info info;
    if (!symbol || !dladdr(symbol, &info) || info.dli_fbase != library->base)
        return NULL;
    return symbol;
}
