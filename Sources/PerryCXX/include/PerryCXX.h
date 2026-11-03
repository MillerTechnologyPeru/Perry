#ifndef PERRYCXX_H
#define PERRYCXX_H

// libPerryCXX: Darwin's libc++ and libc++abi imports, bound to libc++ built
// with Darwin's arm64 ABI.

/// Linux's symbol for a Mach-O name, or NULL. The loader asks for imports
/// this library does not define itself.
void *perry_provider_symbol(const char *name);

#endif
