#ifndef PERRY_SYSTEM_H
#define PERRY_SYSTEM_H

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

// The loader's symbol lookup (perry_startup_info.lookup_symbol), once
// libSystem has started: by Mach-O name, in a library or (NULL) anywhere.
extern void *(*perry_system_lookup)(const char *install_name, const char *name);

#endif
