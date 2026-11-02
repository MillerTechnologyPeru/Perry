#ifndef PERRY_INTERFACE_H
#define PERRY_INTERFACE_H

// Interface between the Perry loader and the Linux provider libraries that
// stand in for Darwin libraries (libPerrySystem.so and friends).

#include <stdint.h>

#define PERRY_STARTUP_INFO_VERSION 1

typedef struct perry_startup_info {
    uint32_t version;
    int argc;
    char **argv;
    char **envp;
    const char *progname;
    const char *executable_path;
    const char *bundle_path;        // NULL when not launched from a bundle
    const void *main_header;        // mach header of the main executable
} perry_startup_info;

// Providers may export this function. The loader calls it after mapping and
// binding every image, before any Mach-O initializer runs.
typedef void (*perry_provider_startup_fn)(const perry_startup_info *info);
#define PERRY_PROVIDER_STARTUP_SYMBOL "perry_provider_startup"

#endif
