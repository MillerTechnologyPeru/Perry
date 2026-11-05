#ifndef PERRY_INTERFACE_H
#define PERRY_INTERFACE_H

// Interface between the Perry loader and the Linux provider libraries that
// stand in for Darwin libraries (libPerrySystem.so and friends).

#include <stdint.h>

#define PERRY_STARTUP_INFO_VERSION 2

typedef struct perry_startup_info {
    uint32_t version;
    int argc;
    char **argv;
    char **envp;
    const char *progname;
    const char *executable_path;
    const char *bundle_path;        // NULL when not launched from a bundle
    const void *main_header;        // mach header of the main executable

    // Version 2.
    // Looks up a symbol by its Mach-O name ("__Block_copy") in the provider
    // standing in for `install_name`, loading it if needed, or in the Mach-O
    // image with that install name. A NULL install name searches as
    // dlsym(RTLD_DEFAULT) does: the program's images in load order, then the
    // providers loaded. NULL if missing.
    void *(*lookup_symbol)(const char *install_name, const char *name);
} perry_startup_info;

// Providers may export this function. The loader calls it after mapping and
// binding every image, before any Mach-O initializer runs.
typedef void (*perry_provider_startup_fn)(const perry_startup_info *info);
#define PERRY_PROVIDER_STARTUP_SYMBOL "perry_provider_startup"

typedef struct perry_image_info {
    const void *header;             // mach_header_64 in memory
    intptr_t slide;                 // added to the image's unslid vmaddrs
    const char *path;
} perry_image_info;

// Providers may export this function. The loader calls it for each Mach-O
// image after its dependencies are initialized and just before its own
// initializers run: where dyld notifies the Objective-C runtime, which
// registers the image's classes and calls +load here.
typedef void (*perry_provider_image_fn)(const perry_image_info *image);
#define PERRY_PROVIDER_IMAGE_INIT_SYMBOL "perry_provider_image_init"

// Providers may export this function. The loader calls it, while binding,
// for a symbol (by Mach-O name, "_NSCocoaErrorDomain") the provider does not
// define as an ELF symbol; it returns the symbol's address, or NULL. Lets a
// provider define data symbols, such as exported constants, at run time.
// Called before perry_provider_startup.
typedef void *(*perry_provider_symbol_fn)(const char *name);
#define PERRY_PROVIDER_SYMBOL_SYMBOL "perry_provider_symbol"

// Prints `title`, then the calling thread's frames by their frame
// pointers, each as the file it is mapped from and the offset in it (for
// atos -l 0 on a Mach-O dylib, -l 0x100000000 on an app), on standard
// error. For tracing who calls a function.
void perry_print_frames(const char *title);

#endif
