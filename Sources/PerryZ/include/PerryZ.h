#ifndef PERRYZ_H
#define PERRYZ_H

// libPerryz: Darwin's zlib imports, bound to Linux's zlib.

/// Linux's symbol for a Mach-O name, or NULL. The loader asks for imports
/// this library does not define itself.
void *perry_provider_symbol(const char *name);

#endif
