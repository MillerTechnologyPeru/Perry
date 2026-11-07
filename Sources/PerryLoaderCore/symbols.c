// Symbol resolution across Mach-O images and Linux providers.

#define _GNU_SOURCE
#include "image.h"
#include "leb128.h"
#include "log.h"
#include "perry_interface.h"

#include <dlfcn.h>
#include <limits.h>
#include <pthread.h>
#include <link.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

// MARK: - Hash table

typedef struct hash_entry {
    struct hash_entry *next;
    const void *key_ptr;        // for pointer keys
    char *key;                  // for string keys
    void *value;
} hash_entry;

#define HASH_BUCKETS 4096

typedef struct hash_table {
    hash_entry *buckets[HASH_BUCKETS];
} hash_table;

static uint32_t hash_string(const char *s) {
    uint32_t h = 2166136261u;
    while (*s)
        h = (h ^ (uint8_t)*s++) * 16777619u;
    return h;
}

static void **hash_lookup_string(hash_table *table, const char *key, bool insert) {
    uint32_t bucket = hash_string(key) % HASH_BUCKETS;
    for (hash_entry *e = table->buckets[bucket]; e; e = e->next)
        if (strcmp(e->key, key) == 0)
            return &e->value;
    if (!insert)
        return NULL;
    hash_entry *e = calloc(1, sizeof(*e));
    e->key = strdup(key);
    e->next = table->buckets[bucket];
    table->buckets[bucket] = e;
    return &e->value;
}

static void **hash_lookup_pointer(hash_table *table, const void *key, bool insert) {
    uint32_t bucket = (uint32_t)(((uintptr_t)key >> 3) * 2654435761u) % HASH_BUCKETS;
    for (hash_entry *e = table->buckets[bucket]; e; e = e->next)
        if (e->key_ptr == key)
            return &e->value;
    if (!insert)
        return NULL;
    hash_entry *e = calloc(1, sizeof(*e));
    e->key_ptr = key;
    e->next = table->buckets[bucket];
    table->buckets[bucket] = e;
    return &e->value;
}

// MARK: - Export trie

// Returns the terminal info for `name`, or NULL if it is not exported.
static const uint8_t *trie_find(const uint8_t *start, uint32_t size, const char *name, const uint8_t **terminal_end) {
    const uint8_t *end = start + size;
    const uint8_t *p = start;
    for (int depth = 0; p < end && depth < 512; depth++) {
        uint64_t terminal_size = perry_read_uleb(&p, end);
        // A name that ends where a longer one goes on can have its terminal
        // a node further, behind an empty edge, as newer linkers write
        // ("_XalGetSandbox" beside "_XalGetSandboxSize"): with no terminal
        // here, the children are searched for one.
        if (*name == 0 && terminal_size != 0) {
            *terminal_end = p + terminal_size;
            return p;
        }
        const uint8_t *children = p + terminal_size;
        if (children >= end)
            return NULL;
        uint8_t child_count = *children++;
        const uint8_t *next = NULL;
        for (uint8_t i = 0; i < child_count && children < end; i++) {
            const char *edge = (const char *)children;
            size_t len = strnlen(edge, (size_t)(end - children));
            children += len + 1;
            uint64_t offset = perry_read_uleb(&children, end);
            if (strncmp(name, edge, len) == 0) {
                name += len;
                next = start + offset;
                break;
            }
        }
        if (!next)
            return NULL;
        p = next;
    }
    return NULL;
}

static bool provider_lookup(perry_loader *loader, perry_provider *provider, const char *name, perry_symbol *out);

static bool lookup_in_dependency(perry_loader *loader, perry_dependency *dep, const char *name,
                                 perry_symbol *out, int depth) {
    if (dep->image) {
        if (perry_exports_lookup(loader, dep->image, name, out, depth + 1))
            return true;
        // A Swift overlay's API newer than the overlay, which Perry adds.
        return dep->swift_additions && strncmp(name, "_$s", 3) == 0 &&
               perry_exports_lookup(loader, dep->swift_additions, name, out, depth + 1);
    }
    if (dep->provider && provider_lookup(loader, dep->provider, name, out))
        return true;
    // Swift symbols of a framework whose Swift code the provider lacks.
    if (strncmp(name, "_$s", 3) == 0) {
        if (dep->swift_overlay && perry_exports_lookup(loader, dep->swift_overlay, name, out, depth + 1))
            return true;
        if (dep->swift_additions && perry_exports_lookup(loader, dep->swift_additions, name, out, depth + 1))
            return true;
    }
    return false;
}

bool perry_exports_lookup(perry_loader *loader, perry_image *image, const char *name, perry_symbol *out, int depth) {
    if (depth > 32)
        return false;
    if (image->exports_trie) {
        const uint8_t *end;
        const uint8_t *p = trie_find(image->exports_trie, image->exports_trie_size, name, &end);
        if (p) {
            uint64_t flags = perry_read_uleb(&p, end);
            if (flags & EXPORT_SYMBOL_FLAGS_REEXPORT) {
                uint64_t ordinal = perry_read_uleb(&p, end);
                const char *imported = (const char *)p;
                if (!*imported)
                    imported = name;
                if (ordinal == 0 || ordinal > image->dep_count)
                    return false;
                return lookup_in_dependency(loader, &image->deps[ordinal - 1], imported, out, depth);
            }
            uint64_t address = perry_read_uleb(&p, end);
            out->found = true;
            out->weak_def = flags & EXPORT_SYMBOL_FLAGS_WEAK_DEFINITION;
            switch (flags & EXPORT_SYMBOL_FLAGS_KIND_MASK) {
            case EXPORT_SYMBOL_FLAGS_KIND_ABSOLUTE:
                out->address = (void *)(uintptr_t)address;
                break;
            default:
                out->address = image->base + address;
                break;
            }
            if (flags & EXPORT_SYMBOL_FLAGS_STUB_AND_RESOLVER) {
                uint64_t resolver = perry_read_uleb(&p, end);
                void *(*fn)(void) = (void *(*)(void))(void *)(image->base + resolver);
                out->address = fn();
            }
            return true;
        }
    }
    // Symbols of re-exported libraries are visible through this image.
    for (uint32_t i = 0; i < image->dep_count; i++)
        if (image->deps[i].reexport && lookup_in_dependency(loader, &image->deps[i], name, out, depth))
            return true;
    return false;
}

// MARK: - Providers

#define LIBDISPATCH "/usr/lib/system/libdispatch.dylib"
#define LIBOBJC "/usr/lib/libobjc.A.dylib"
#define CFNETWORK "/System/Library/Frameworks/CFNetwork.framework/CFNetwork"
#define QUARTZCORE "/System/Library/Frameworks/QuartzCore.framework/QuartzCore"
#define MAPKIT "/System/Library/Frameworks/MapKit.framework/MapKit"
#define COREFOUNDATION "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"

// Libraries a provider needs loaded with it, as Darwin's link: libdispatch's
// objects are Objective-C objects, Foundation's run loop drains the main
// queue, CoreGraphics' objects are CoreFoundation's (Foundation's provider),
// and UIKit's views are backed by QuartzCore's layers. Loading them while
// binding gives them their startup too.
static const struct {
    const char *short_name;
    const char *install_name;
} provider_links[] = {
    {"dispatch", LIBOBJC},
    {"Foundation", LIBDISPATCH},
    {"CoreGraphics", COREFOUNDATION},
    {"UIKit", QUARTZCORE},
    {"MapKitAppKit", MAPKIT},
};

// Sets up a provider just found under `short_name`: its re-exports and the
// libraries it needs.
static void link_provider(perry_loader *loader, perry_provider *provider, const char *short_name) {
    // libSystem re-exports libdispatch, and Foundation CFNetwork's URL
    // loading classes, each found the first time the library lacks a
    // symbol, so programs that never use them never load them. Programs
    // linked against older SDKs bind NSObject to CoreFoundation, which
    // re-exported libobjc's root classes.
    if (strcmp(short_name, "System") == 0)
        provider->reexports[0] = LIBDISPATCH;
    if (strcmp(short_name, "Foundation") == 0) {
        provider->reexports[0] = CFNETWORK;
        provider->reexports[1] = LIBOBJC;
    }
    // A Mac app's MapKit has its views from AppKit's MapKit provider and the
    // rest from iOS apps' MapKit provider.
    if (strcmp(short_name, "MapKitAppKit") == 0)
        provider->reexports[0] = MAPKIT;
    for (size_t i = 0; i < sizeof(provider_links) / sizeof(provider_links[0]); i++)
        if (strcmp(provider_links[i].short_name, short_name) == 0)
            perry_find_provider(loader, provider_links[i].install_name);
}

// Maps an install name to the provider's short name, following the
// libPerry<Name>.so convention:
//   /usr/lib/libSystem.B.dylib                           -> System
//   /usr/lib/system/libsystem_c.dylib                    -> System
//   /usr/lib/libc++.1.dylib, /usr/lib/libc++abi.dylib     -> CXX
//   /usr/lib/libstdc++.6.dylib                           -> StdCXX
//   /System/Library/Frameworks/UIKit.framework/UIKit     -> UIKit
//   …/CoreFoundation.framework/CoreFoundation             -> Foundation
//   /usr/lib/system/libdispatch.dylib                    -> dispatch
//   …/MobileCoreServices.framework/MobileCoreServices     -> UniformTypeIdentifiers
//   /System/Library/Frameworks/ImageIO.framework/ImageIO  -> CoreGraphics
//   …/QuartzCore.framework/QuartzCore                     -> QuartzCore
//   …/Metal.framework/Metal                               -> Metal, else QuartzCore
//   …/Network.framework/Network, /usr/lib/libnetwork.dylib -> SystemConfiguration
//   …/OpenGLES.framework/OpenGLES, …/GLKit.framework/GLKit -> UIKit
//   …/MetalKit.framework/MetalKit                       -> UIKit
//   /usr/lib/libAccessibility.dylib, …/Accessibility.framework/Accessibility -> UIKit
//   …/Social.framework, …/SafariServices.framework, …/CoreText.framework  -> UIKit
//   …/AVKit.framework                                    -> UIKit
//   …/AppTrackingTransparency.framework, …/AdSupport.framework -> UIKit
//   …/CoreImage.framework/CoreImage                       -> UIKit
//   …/Carbon.framework, …/HIToolbox.framework             -> AppKit (not on armv7)
//   …/WebKit.framework/Versions/A/WebKit (a Mac app's)     -> AppKit (not on armv7)
static bool provider_short_name(const char *install_name, char *out, size_t out_size) {
    if (strcmp(install_name, LIBDISPATCH) == 0) {
        snprintf(out, out_size, "dispatch");
        return true;
    }
    if (strncmp(install_name, "/usr/lib/system/", 16) == 0) {
        snprintf(out, out_size, "System");
        return true;
    }
    // Darwin splits classes such as NSArray between CoreFoundation and
    // Foundation; one provider keeps a single copy of each.
    if (strstr(install_name, "/CoreFoundation.framework/")) {
        snprintf(out, out_size, "Foundation");
        return true;
    }
    // The compiler's runtime, whose arithmetic helpers armv6 code calls, and
    // the operators new and delete programs built with GCC take from
    // libstdc++: both are libSystem's provider's.
    if (strncmp(install_name, "/usr/lib/libgcc_s.", 18) == 0 || strncmp(install_name, "/usr/lib/libstdc++.", 19) == 0) {
        snprintf(out, out_size, "System");
        return true;
    }
    // CoreAudio has the types AudioToolbox's functions take.
    if (strstr(install_name, "/CoreAudio.framework/")) {
        snprintf(out, out_size, "AudioToolbox");
        return true;
    }
    // libc++ and libc++abi are one provider.
    if (strncmp(install_name, "/usr/lib/libc++", 15) == 0) {
        snprintf(out, out_size, "CXX");
        return true;
    }
    // GNU's libstdc++, which apps built before libc++ link.
    if (strncmp(install_name, "/usr/lib/libstdc++", 18) == 0) {
        snprintf(out, out_size, "StdCXX");
        return true;
    }
    // MobileCoreServices' (and macOS CoreServices') UTType functions live
    // with UTType.
    if (strstr(install_name, "/MobileCoreServices.framework/") || strstr(install_name, "/CoreServices.framework/")) {
        snprintf(out, out_size, "UniformTypeIdentifiers");
        return true;
    }
    // Accelerate's sub-frameworks (vecLib, vImage) are the umbrella's provider.
    if (strstr(install_name, "/Accelerate.framework/")) {
        snprintf(out, out_size, "Accelerate");
        return true;
    }
#if !defined(__arm__)
    // A Mac app's WebKit (a versioned framework) is AppKit's: its web views
    // are NSViews. perry32 runs only iOS apps and has no AppKit.
    if (strstr(install_name, "/WebKit.framework/Versions/")) {
        snprintf(out, out_size, "AppKit");
        return true;
    }
    // A Mac app's MapKit (a versioned framework) has map views that are
    // NSViews; its provider re-exports iOS apps' for the rest.
    if (strstr(install_name, "/MapKit.framework/Versions/")) {
        snprintf(out, out_size, "MapKitAppKit");
        return true;
    }
#endif
    // UIKit keeps OpenGL ES's contexts and GLKit's views built on them,
    // MetalKit's views over QuartzCore's Metal layers,
    // answers libAccessibility's and Accessibility's questions about
    // accessibility settings, and stands in for Social's and Safari's view
    // controllers, AuthenticationServices' web sign-in sessions, CoreText's
    // text attributes, AVKit's player view controller and Core Image's
    // images and filters.
    if (strstr(install_name, "/OpenGLES.framework/") || strstr(install_name, "/GLKit.framework/") ||
        strstr(install_name, "/MetalKit.framework/") ||
        strstr(install_name, "/WebKit.framework/") || strcmp(install_name, "/usr/lib/libAccessibility.dylib") == 0 ||
        strstr(install_name, "/Accessibility.framework/") || strstr(install_name, "/Social.framework/") ||
        strstr(install_name, "/SafariServices.framework/") || strstr(install_name, "/AuthenticationServices.framework/") ||
        strstr(install_name, "/CoreText.framework/") ||
        strstr(install_name, "/AVKit.framework/") || strstr(install_name, "/AppTrackingTransparency.framework/") ||
        strstr(install_name, "/AdSupport.framework/") || strstr(install_name, "/CoreImage.framework/")) {
        snprintf(out, out_size, "UIKit");
        return true;
    }
#if !defined(__arm__)
    // Carbon's (HIToolbox's) text input sources are AppKit's: the keyboard
    // layouts AppKit's key events are typed with.
    if (strstr(install_name, "/Carbon.framework/") || strstr(install_name, "/HIToolbox.framework/")) {
        snprintf(out, out_size, "AppKit");
        return true;
    }
#endif
    // AVFAudio's classes are AVFoundation's, which re-exports them; and
    // AVFoundation's provider has the times of CoreMedia, the pixel buffers
    // of CoreVideo and the audio taps of MediaToolbox that its players and
    // video outputs hand out.
    if (strstr(install_name, "/AVFAudio.framework/") || strstr(install_name, "/CoreMedia.framework/") ||
        strstr(install_name, "/CoreVideo.framework/") || strstr(install_name, "/MediaToolbox.framework/")) {
        snprintf(out, out_size, "AVFoundation");
        return true;
    }
    // CoreMotion's attitude here is a gamepad's stick, which
    // GameController's provider reads.
    if (strstr(install_name, "/CoreMotion.framework/")) {
        snprintf(out, out_size, "GameController");
        return true;
    }
    // Network's path monitor reads the routes SystemConfiguration's
    // reachability does. Its C API is libnetwork's, which Network's Swift
    // overlay binds to directly.
    if (strstr(install_name, "/Network.framework/") || strcmp(install_name, "/usr/lib/libnetwork.dylib") == 0) {
        snprintf(out, out_size, "SystemConfiguration");
        return true;
    }
    // ImageIO's images are CoreGraphics' own.
    if (strstr(install_name, "/ImageIO.framework/")) {
        snprintf(out, out_size, "CoreGraphics");
        return true;
    }
    const char *base = strrchr(install_name, '/');
    base = base ? base + 1 : install_name;
    size_t len = strlen(base);
    if (len > 6 && strcmp(base + len - 6, ".dylib") == 0) {
        if (strncmp(base, "lib", 3) == 0)
            base += 3;
        const char *dot = strchr(base, '.');
        len = (size_t)(dot - base);
    }
    if (len == 0 || len + 1 > out_size)
        return false;
    memcpy(out, base, len);
    out[len] = 0;
    return true;
}

/// Loads the Swift corelibs' Foundation before any provider, so that its
/// own calls bind to its own functions. Its CoreFoundation has SPI named
/// like Darwin's functions as exported, with an underscore
/// (_CFCharacterSetCreateMutableCopy, _CFArrayReplaceValues…), which
/// providers define as Darwin's; loaded first as a provider's dependency,
/// it would bind those to the provider's, which return Objective-C objects.
/// The Swift runtime's directory is the one libswiftCore is in, which the
/// Objective-C runtime's provider loads without Foundation.
static void load_corelibs_foundation(perry_loader *loader) {
    static bool loaded;
    if (loaded)
        return;
    loaded = true;
    if (dlopen("libFoundation.so", RTLD_NOW | RTLD_GLOBAL))
        return;
    for (uint32_t i = 0; i < loader->library_dir_count; i++) {
        char path[PATH_MAX];
        snprintf(path, sizeof(path), "%s/libPerryobjc.so", loader->library_dirs[i]);
        void *objc = access(path, R_OK) == 0 ? dlopen(path, RTLD_NOW | RTLD_LOCAL) : NULL;
        void *retain = objc ? dlsym(objc, "swift_retain") : NULL;
        Dl_info info;
        if (!retain || !dladdr(retain, &info) || !info.dli_fname)
            continue;
        const char *slash = strrchr(info.dli_fname, '/');
        if (!slash)
            continue;
        snprintf(path, sizeof(path), "%.*s/libFoundation.so", (int)(slash - info.dli_fname), info.dli_fname);
        if (dlopen(path, RTLD_NOW | RTLD_GLOBAL))
            return;
    }
    perry_trace(PERRY_TRACE_BIND, "corelibs Foundation not loaded first: %s", dlerror());
}

perry_provider *perry_find_provider(perry_loader *loader, const char *install_name) {
    for (uint32_t i = 0; i < loader->provider_count; i++)
        if (strcmp(loader->providers[i]->install_name, install_name) == 0)
            return loader->providers[i]->handle ? loader->providers[i] : NULL;

    perry_provider *provider = calloc(1, sizeof(*provider));
    provider->install_name = strdup(install_name);
    loader->providers = realloc(loader->providers, sizeof(perry_provider *) * (loader->provider_count + 1));
    loader->providers[loader->provider_count++] = provider;

    char short_name[256];
    if (!provider_short_name(install_name, short_name, sizeof(short_name)))
        return NULL;
    // WebKit's web views make URL requests of their own, as CFNetwork's
    // classes, which must start with the program.
    if (strstr(install_name, "/WebKit.framework/"))
        perry_find_provider(loader, CFNETWORK);

    // Several install names may map to one provider (libSystem's sublibraries).
    for (uint32_t i = 0; i + 1 < loader->provider_count; i++) {
        perry_provider *other = loader->providers[i];
        char other_name[256];
        if (other->handle && provider_short_name(other->install_name, other_name, sizeof(other_name)) &&
            strcmp(other_name, short_name) == 0) {
            provider->path = other->path;
            provider->handle = other->handle;
            provider->base = other->base;
            provider->symbol = other->symbol;
            memcpy(provider->reexports, other->reexports, sizeof(provider->reexports));
            return provider;
        }
    }

    // Metal is libPerryMetal's, on Vulkan; without it, QuartzCore, which
    // has the layers, answers that there is no device, so apps that can
    // draw with OpenGL ES do. PERRY_METAL=0 has it so with libPerryMetal
    // there too.
    bool metal = strcmp(short_name, "Metal") == 0;
    const char *metal_setting = getenv("PERRY_METAL");
    if (metal && metal_setting && (strcmp(metal_setting, "0") == 0 || strcmp(metal_setting, "off") == 0)) {
        perry_trace(PERRY_TRACE_LOAD, "Metal turned off by PERRY_METAL; QuartzCore answers for it");
        metal = false;
        snprintf(short_name, sizeof(short_name), "QuartzCore");
    }
retry:
    for (uint32_t i = 0; i < loader->library_dir_count; i++) {
        char path[PATH_MAX];
        snprintf(path, sizeof(path), "%s/libPerry%s.so", loader->library_dirs[i], short_name);
        if (access(path, R_OK) != 0)
            continue;
        // A provider loaded for another name already (QuartzCore, standing
        // in for Metal) is the same one.
        for (uint32_t j = 0; j + 1 < loader->provider_count; j++) {
            perry_provider *other = loader->providers[j];
            if (other->handle && other->path && strcmp(other->path, path) == 0) {
                provider->path = other->path;
                provider->handle = other->handle;
                provider->base = other->base;
                provider->symbol = other->symbol;
                memcpy(provider->reexports, other->reexports, sizeof(provider->reexports));
                return provider;
            }
        }
        load_corelibs_foundation(loader);
        void *handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
        if (!handle) {
            // A provider over a library the host lacks (JavaScriptCore's,
            // on a system without WebKitGTK) is as if there were none: a
            // program that links the framework and never needs it runs.
            const char *error = dlerror();
            if (error && strstr(error, "cannot open shared object file")) {
                perry_warn("provider %s is not available: %s", path, error);
                return NULL;
            }
            perry_fatal("cannot load provider %s: %s", path, error ? error : "unknown error");
        }
        struct link_map *map = NULL;
        dlinfo(handle, RTLD_DI_LINKMAP, &map);
        provider->path = strdup(path);
        provider->handle = handle;
        provider->base = map ? (void *)map->l_addr : NULL;
        void *hook = dlsym(handle, PERRY_PROVIDER_SYMBOL_SYMBOL);
        Dl_info hook_info;
        if (hook && dladdr(hook, &hook_info) && hook_info.dli_fbase == provider->base)
            provider->symbol = (void *(*)(const char *))hook;
        perry_trace(PERRY_TRACE_LOAD, "provider %s for %s", path, install_name);
        link_provider(loader, provider, short_name);
        return provider;
    }
    if (metal) {
        metal = false;
        snprintf(short_name, sizeof(short_name), "QuartzCore");
        goto retry;
    }
    return NULL;
}

void *perry_provider_symbol(perry_loader *loader, const char *install_name, const char *name) {
    perry_provider *provider = perry_find_provider(loader, install_name);
    perry_symbol sym = {0};
    return provider && provider_lookup(loader, provider, name, &sym) ? sym.address : NULL;
}

static bool provider_lookup(perry_loader *loader, perry_provider *provider, const char *name, perry_symbol *out) {
    void *sym = dlsym(provider->handle, name);
    // dlsym also searches the provider's own dependencies (glibc). Only symbols
    // defined in the provider itself count, so that a Darwin name such as
    // "__exit" never binds to an unrelated glibc symbol.
    Dl_info info;
    if (sym && (!dladdr(sym, &info) || info.dli_fbase != provider->base))
        sym = NULL;
    // Symbols the provider defines at run time, such as Swift constants.
    if (!sym && provider->symbol)
        sym = provider->symbol(name);
    for (size_t i = 0; !sym && i < sizeof(provider->reexports) / sizeof(provider->reexports[0]); i++) {
        if (!provider->reexports[i]) continue;
        perry_provider *reexported = perry_find_provider(loader, provider->reexports[i]);
        if (reexported && provider_lookup(loader, reexported, name, out)) return true;
    }
    if (!sym)
        return false;
    out->address = sym;
    out->found = true;
    out->weak_def = false;
    return true;
}

// MARK: - Unresolved stubs

// Calling an unresolved import lands in a stub that reports which symbol was
// missing instead of jumping to address zero. With
// PERRY_UNIMPLEMENTED=continue, for finding what a program needs, each is
// reported the first time and returns zero.
static uintptr_t perry_unimplemented(const char *description) {
    static int continues = -1;
    if (continues < 0) {
        const char *mode = getenv("PERRY_UNIMPLEMENTED");
        continues = mode && strcmp(mode, "continue") == 0;
    }
    fflush(stdout);
    if (!continues) {
        fprintf(stderr, "perry: unimplemented: %s\n", description);
        abort();
    }
    static hash_table reported;
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    pthread_mutex_lock(&lock);
    void **slot = hash_lookup_string(&reported, description, true);
    bool first = !*slot;
    *slot = (void *)1;
    pthread_mutex_unlock(&lock);
    if (first)
        fprintf(stderr, "perry: unimplemented: %s, returning 0\n", description);
    return 0;
}

typedef struct stub_page {
    uint8_t *base;
    size_t used;
    size_t size;
    bool writable_exec;         // false when the host refuses RWX and pages flip RW <-> RX
} stub_page;

static hash_table stub_table;
static stub_page current_page;

void *perry_unresolved_stub(const char *library, const char *name) {
    char description[1024];
    snprintf(description, sizeof(description), "%s (%s)", name, library ? library : "?");
    void **slot = hash_lookup_string(&stub_table, description, true);
    if (*slot)
        return *slot;

    enum { STUB_SIZE = 32 };
    if (!current_page.base || current_page.used + STUB_SIZE > current_page.size) {
        current_page.size = 0x4000;
        current_page.base = mmap(NULL, current_page.size, PROT_READ | PROT_WRITE | PROT_EXEC,
                                 MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        current_page.writable_exec = current_page.base != MAP_FAILED;
        if (!current_page.writable_exec) {
            current_page.base = mmap(NULL, current_page.size, PROT_READ | PROT_WRITE,
                                     MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
            if (current_page.base == MAP_FAILED)
                perry_fatal("cannot allocate stub page");
        }
        current_page.used = 0;
    } else if (!current_page.writable_exec) {
        mprotect(current_page.base, current_page.size, PROT_READ | PROT_WRITE);
    }
    uint32_t *code = (uint32_t *)(current_page.base + current_page.used);
    current_page.used += STUB_SIZE;

#if defined(__LP64__)
    code[0] = 0x58000080;   // ldr x0, #16    (description)
    code[1] = 0x580000b0;   // ldr x16, #20   (handler)
    code[2] = 0xd61f0200;   // br x16
    code[3] = 0xd503201f;   // nop
    *(uint64_t *)&code[4] = (uint64_t)(uintptr_t)strdup(description);
    *(uint64_t *)&code[6] = (uint64_t)(uintptr_t)&perry_unimplemented;
#else
    // ARM state, so the stub's address has no Thumb bit; callers reach it by
    // blx or bx, which switch to ARM state by that bit.
    code[0] = 0xe59f0008;   // ldr r0, [pc, #8]   (description, at +16)
    code[1] = 0xe59ff008;   // ldr pc, [pc, #8]   (handler, at +20)
    code[2] = 0xe320f000;   // nop
    code[3] = 0xe320f000;   // nop
    code[4] = (uint32_t)(uintptr_t)strdup(description);
    code[5] = (uint32_t)(uintptr_t)&perry_unimplemented;
#endif
    __builtin___clear_cache((char *)code, (char *)code + STUB_SIZE);
    if (!current_page.writable_exec)
        mprotect(current_page.base, current_page.size, PROT_READ | PROT_EXEC);

    *slot = code;
    return code;
}

// MARK: - Aligned entries

#if defined(__arm__)
void perry_align_call(void);

// Functions that keep or use their caller's frame, which a call through
// perry_align_call would put a frame of its own under: setjmp returns a
// second time, after that frame is gone.
static bool keeps_callers_frame(const char *name) {
    static const char *const names[] = {
        "_setjmp", "__setjmp", "_sigsetjmp", "_vfork", "_getcontext", "_swapcontext", "_alloca",
        "__Unwind_SjLj_Register", "__Unwind_SjLj_Unregister",
    };
    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++)
        if (strcmp(names[i], name) == 0)
            return true;
    return false;
}

// What an image's lazy pointer to `function` holds: an entry that calls it
// through perry_align_call, which aligns the stack 32-bit Darwin code calls
// with. One entry a function, so its address compares as one.
void *perry_aligned_entry(void *function, const char *name) {
    static hash_table entries;
    static uint32_t *page;
    static size_t used;
    enum { ENTRY_WORDS = 4, PAGE_SIZE = 0x10000 };
    if (!function || keeps_callers_frame(name))
        return function;
    char key[24];
    snprintf(key, sizeof(key), "%p", function);
    void **slot = hash_lookup_string(&entries, key, true);
    if (*slot)
        return *slot;
    if (!page || used + ENTRY_WORDS * 4 > PAGE_SIZE) {
        page = mmap(NULL, PAGE_SIZE, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (page == MAP_FAILED) {
            // A host that refuses writable code: the function itself.
            page = NULL;
            return function;
        }
        used = 0;
    }
    uint32_t *code = (uint32_t *)((uint8_t *)page + used);
    used += ENTRY_WORDS * 4;
    code[0] = 0xe59fc000;   // ldr r12, [pc]      (the function, at +8)
    code[1] = 0xe59ff000;   // ldr pc, [pc]       (perry_align_call, at +12)
    code[2] = (uint32_t)(uintptr_t)function;
    code[3] = (uint32_t)(uintptr_t)&perry_align_call;
    __builtin___clear_cache((char *)code, (char *)code + ENTRY_WORDS * 4);
    *slot = code;
    return code;
}
#endif

// MARK: - Import records

static perry_import_record *records;
static size_t record_count, record_capacity;
static hash_table record_table;
static hash_table bind_locations;

void perry_record_import(const perry_image *image, const char *library, const char *name, perry_import_status status) {
    char key[2048];
    snprintf(key, sizeof(key), "%p|%s|%s", (const void *)image, library, name);
    void **slot = hash_lookup_string(&record_table, key, true);
    if (*slot)
        return;
    if (record_count == record_capacity) {
        record_capacity = record_capacity ? record_capacity * 2 : 256;
        records = realloc(records, sizeof(*records) * record_capacity);
    }
    records[record_count] = (perry_import_record){ image, library, name, status };
    *slot = (void *)(uintptr_t)(++record_count);
}

const perry_import_record *perry_import_records(size_t *count) {
    *count = record_count;
    return records;
}

void perry_record_bind_location(void *location, const char *name) {
    *hash_lookup_pointer(&bind_locations, location, true) = (void *)name;
}

const char *perry_bind_name_at(const void *location) {
    void **slot = hash_lookup_pointer(&bind_locations, location, false);
    return slot ? *slot : NULL;
}

// MARK: - Resolution

static bool ends_with(const char *name, const char *suffix) {
    size_t n = strlen(name), m = strlen(suffix);
    return n >= m && strcmp(name + n - m, suffix) == 0;
}

/// For an unresolved string constant's import, a pointer to a constant
/// CFString of its name ("_UIFooNotification" is @"UIFooNotification"),
/// made once; NULL for other symbols, or before Foundation is loaded. A
/// constant is known by its name's ending (notification names, keys, error
/// domains, pasteboard types, accessibility roles and actions, bindings and
/// their options, exception names, run loop modes) or by the families of
/// string constants Apple names alike: user activity types, capture device
/// types and session presets, authorization scopes and options, pasteboard
/// types and image names.
static void *string_constant(perry_loader *loader, const char *name) {
    if (name[0] != '_' || strncmp(name, "_OBJC_", 6) == 0) return NULL;
    static const char *const families[] = { "_NSUserActivityType", "_AVCaptureDeviceType", "_AVCaptureSessionPreset",
                                            "_ASAuthorizationScope", "_ASAuthorizationPublicKeyCredential" };
    bool family = false;
    for (size_t i = 0; i < sizeof(families) / sizeof(families[0]) && !family; i++)
        family = strncmp(name, families[i], strlen(families[i])) == 0;
    static const char *const endings[] = { "Notification", "NotificationName", "Key", "Attribute", "AttributeName", "Identifier",
                                           "ErrorDomain", "PboardType", "Role", "Subrole", "Action", "Binding", "BindingOption",
                                           "Exception", "RunLoopMode" };
    for (size_t i = 0; i < sizeof(endings) / sizeof(endings[0]) && !family; i++)
        family = ends_with(name, endings[i]);
    if (!family && strncmp(name, "_NSPasteboardType", 17) != 0 && strncmp(name, "_NSImageName", 12) != 0)
        return NULL;
    perry_symbol isa = { 0 };
    for (uint32_t i = 0; i < loader->provider_count && !isa.found; i++)
        if (loader->providers[i]->handle)
            provider_lookup(loader, loader->providers[i], "___CFConstantStringClassReference", &isa);
    if (!isa.found) return NULL;
    // { isa, flags, bytes, length }, as clang emits for @"…"; then the
    // variable holding it, which the import names.
    struct { void *isa; uint64_t flags; const char *bytes; uint64_t length; } *string = calloc(1, sizeof *string);
    void **variable = calloc(1, sizeof *variable);
    if (!string || !variable) return NULL;
    char *bytes = strdup(name + 1);
    *string = (typeof(*string)){ isa.address, 0x7C8, bytes, strlen(bytes) };
    *variable = string;
    perry_trace(PERRY_TRACE_BIND, "string constant %s for unresolved import", name);
    return variable;
}

/// Witness tables apps take directly whose conformances the libraries have
/// only as resilient ones: each a table of this many words, filled in
/// once every image is bound.
#define WITNESS_TABLE_WORDS 256
typedef struct pending_witness_table {
    void **table;
    const int32_t *conformance;
    const char *name;
    struct pending_witness_table *next;
} pending_witness_table;
static pending_witness_table *pending_tables;

/// For an unresolved protocol witness table ("…WP"), room for the table of
/// the conformance the library has ("…Mc"), which the Swift runtime makes
/// before initializers run (perry_make_witness_tables). Apple's SwiftUI
/// declares its types and their protocols in one module, so apps take its
/// witness tables directly; Perry's declares some types in another module
/// than the protocol, which makes the conformance resilient, with no static
/// table. Only a conformance with no conditional requirements is made: its
/// table is the same for every use.
static void *resilient_witness_table(perry_loader *loader, perry_dependency *dep, const char *name) {
    if (!dep || strncmp(name, "_$s", 3) != 0 || !ends_with(name, "WP")) return NULL;
    static hash_table made;
    void **slot = hash_lookup_string(&made, name, false);
    if (slot) return *slot;
    size_t length = strlen(name);
    char *descriptor_name = strdup(name);
    if (!descriptor_name) return NULL;
    descriptor_name[length - 2] = 'M';
    descriptor_name[length - 1] = 'c';
    perry_symbol descriptor = { 0 };
    lookup_in_dependency(loader, dep, descriptor_name, &descriptor, 0);
    free(descriptor_name);
    if (!descriptor.found) return NULL;
    // A protocol conformance descriptor: protocol, type reference, witness
    // table pattern (relative), then flags, with the count of conditional
    // requirements in bits 8-15.
    const int32_t *conformance = descriptor.address;
    if (((uint32_t)conformance[3] >> 8) & 0xff) return NULL;
    pending_witness_table *pending = calloc(1, sizeof *pending);
    void **table = calloc(WITNESS_TABLE_WORDS, sizeof(void *));
    if (!pending || !table) return NULL;
    *pending = (pending_witness_table){ table, conformance, strdup(name), pending_tables };
    pending_tables = pending;
    *hash_lookup_string(&made, name, true) = table;
    return table;
}

static const void *relative_target(const int32_t *field) {
    return (const char *)field + *field;
}

/// A relative pointer whose low bit says it points at a pointer to the
/// target.
static const void *relative_indirectable_target(const int32_t *field) {
    const char *target = (const char *)field + (*field & ~1);
    return (*field & 1) ? *(const void *const *)target : target;
}

void perry_make_witness_tables(perry_loader *loader) {
    typedef const void *(*access_function)(size_t request);
    typedef const void *const *(*get_witness_table)(const void *conformance, const void *type, const void *const *arguments);
    get_witness_table get = NULL;
    for (pending_witness_table *pending = pending_tables; pending; pending = pending->next) {
        if (!get) {
            perry_symbol sym = { 0 };
            for (perry_image *img = loader->images; img && !sym.found; img = img->next)
                perry_exports_lookup(loader, img, "_swift_getWitnessTable", &sym, 0);
            if (!sym.found) return;
            get = (get_witness_table)sym.address;
        }
        const int32_t *conformance = pending->conformance;
        // The type reference's kind (bits 3-5 of the flags): a type
        // descriptor, directly or through a pointer.
        uint32_t flags = (uint32_t)conformance[3];
        const int32_t *type;
        switch ((flags >> 3) & 7) {
        case 0: type = relative_target(&conformance[1]); break;
        case 1: type = *(const int32_t *const *)relative_target(&conformance[1]); break;
        default: continue;
        }
        // A type context descriptor: flags (generic: bit 7), parent, name,
        // then its metadata access function, relative.
        if (!type || ((uint32_t)type[0] & 0x80)) continue;
        // A protocol descriptor: flags, parent, name, the counts of its
        // requirements in its signature and of its requirements.
        const int32_t *protocol = relative_indirectable_target(&conformance[0]);
        uint32_t words = 1 + (uint32_t)protocol[4];
        if (words > WITNESS_TABLE_WORDS) continue;
        const void *metadata = ((access_function)relative_target(&type[3]))(0);
        const void *const *table = metadata ? get(conformance, metadata, NULL) : NULL;
        if (!table) continue;
        memcpy(pending->table, table, words * sizeof(void *));
        perry_trace(PERRY_TRACE_BIND, "witness table %s made from its conformance", pending->name);
    }
}

perry_symbol perry_resolve(perry_loader *loader, perry_image *image, int ordinal, const char *name, bool weak_import) {
    perry_symbol sym = { 0 };
    const char *library;

    if (ordinal > 0) {
        if ((uint32_t)ordinal > image->dep_count)
            perry_fatal("%s: library ordinal %d out of range for %s", image->path, ordinal, name);
        perry_dependency *dep = &image->deps[ordinal - 1];
        library = dep->install_name;
        lookup_in_dependency(loader, dep, name, &sym, 0);
    } else if (ordinal == BIND_SPECIAL_DYLIB_SELF) {
        library = "<self>";
        perry_exports_lookup(loader, image, name, &sym, 0);
    } else if (ordinal == BIND_SPECIAL_DYLIB_MAIN_EXECUTABLE) {
        library = "<main>";
        perry_exports_lookup(loader, loader->main_image, name, &sym, 0);
    } else {
        // Flat and weak lookups search every image in load order, then providers.
        library = ordinal == BIND_SPECIAL_DYLIB_WEAK_LOOKUP ? "<weak>" : "<flat>";
        for (perry_image *img = loader->images; img && !sym.found; img = img->next)
            perry_exports_lookup(loader, img, name, &sym, 0);
        for (uint32_t i = 0; i < loader->provider_count && !sym.found; i++)
            if (loader->providers[i]->handle)
                provider_lookup(loader, loader->providers[i], name, &sym);
        if (!sym.found && ordinal == BIND_SPECIAL_DYLIB_WEAK_LOOKUP && weak_import)
            return sym;
    }

    // Objective-C classes are global, and move between frameworks from
    // one SDK to the next (NSLayoutConstraint, bound to Foundation by newer
    // SDKs, or AVAudioPlayer to AVFAudio): one another provider defines is
    // the same class.
    bool is_class = strncmp(name, "_OBJC_CLASS_$_", 14) == 0 || strncmp(name, "_OBJC_METACLASS_$_", 18) == 0;
    for (uint32_t i = 0; is_class && !sym.found && i < loader->provider_count; i++)
        if (loader->providers[i]->handle)
            provider_lookup(loader, loader->providers[i], name, &sym);

    if (!sym.found && ordinal > 0) {
        void *table = resilient_witness_table(loader, &image->deps[ordinal - 1], name);
        if (table) {
            sym.found = true;
            sym.address = table;
        }
    }

    if (sym.found) {
        perry_record_import(image, library, name, PERRY_IMPORT_RESOLVED);
        return sym;
    }
    if (weak_import) {
        perry_record_import(image, library, name, PERRY_IMPORT_WEAK_MISSING);
        perry_trace(PERRY_TRACE_BIND, "weak import %s from %s missing", name, library);
        // A weak string constant is there on any system the app runs on,
        // and read without a check: it gets the constant string of its
        // name, as a missing one that is not weak does. Other weak
        // imports stay NULL, for the app's own checks.
        void *constant = string_constant(loader, name);
        if (constant)
            sym.address = constant;
        return sym;
    }
    perry_record_import(image, library, name, PERRY_IMPORT_UNRESOLVED);
    if (loader->strict)
        perry_fatal("%s: unresolved symbol %s from %s", image->path, name, library);
    perry_trace(PERRY_TRACE_BIND, "unresolved %s from %s", name, library);
    // A class is data, which libobjc reads rather than calls: it gets an
    // empty class, with no class_ro_t, holding its name where the vtable
    // goes, so libobjc can name it if an app's class inherits from it.
    if (is_class) {
        const char *class_name = strchr(name, '$') + 2;
        void **placeholder = calloc(5, sizeof(void *));
        placeholder[3] = strdup(class_name);
        if (name[6] == 'C') {
            fprintf(stderr, "perry: warning: %s: class %s (%s) is not available\n", image->path, class_name, library);
        }
        sym.address = placeholder;
        return sym;
    }
    // A string constant (a notification's name, a dictionary key) is data
    // the app reads, and Apple names each for its value: it gets a constant
    // string of its name, as the framework's would be.
    void *constant = string_constant(loader, name);
    if (constant) {
        sym.address = constant;
        return sym;
    }
    sym.address = perry_unresolved_stub(library, name);
    return sym;
}
