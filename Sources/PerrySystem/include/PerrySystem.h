#ifndef PERRY_SYSTEM_H
#define PERRY_SYSTEM_H

#include <stdint.h>

// libPerrySystem: the Darwin libSystem ABI implemented over glibc.
//
// Exported ELF symbols use the exact Mach-O symbol names (with the leading
// underscore), so the loader binds an import of `_printf` from
// /usr/lib/libSystem.B.dylib to the ELF symbol `_printf` in this library.

// Declares a function or variable under its Darwin Mach-O name.
#define DARWIN_SYMBOL(name) __asm__("_" #name) __attribute__((visibility("default"), used))

// Darwin errno values (sys/errno.h). Values 1-34 match Linux except EAGAIN
// and EDEADLK.
int perry_darwin_errno_from_linux(int linux_errno);
int perry_linux_errno_from_darwin(int darwin_errno);

// Darwin's __error(): the calling thread's Darwin-numbered errno.
int *darwin_error(void) DARWIN_SYMBOL(__error);

// Linux's number for a Darwin signal, or -1 where Linux has none.
int perry_signal_to_linux(int signal);

// A section's header in a Mach-O image's load commands (section_64).
struct darwin_section_64 {
    char sectname[16], segname[16];
    uint64_t addr, size;
    uint32_t offset, align, reloff, nreloc, flags, reserved1, reserved2, reserved3;
};

// The section's header in a mapped image, or NULL.
const struct darwin_section_64 *darwin_getsectbynamefromheader_64(const void *header, const char *segment, const char *section)
    DARWIN_SYMBOL(getsectbynamefromheader_64);

// The loader's symbol lookup (perry_startup_info.lookup_symbol), once
// libSystem has started: by Mach-O name, in a library or (NULL) anywhere.
extern void *(*perry_system_lookup)(const char *install_name, const char *name);
// The main executable's mach header, for what the system says it is.
extern const void *perry_system_main_header;
// For a macOS program, the Darwin release of its SDK's macOS (25.5 for
// macOS 26.5); zeros for others.
typedef struct { int darwin, minor; } perry_macos_release;
perry_macos_release perry_system_macos_release(void);

#endif
