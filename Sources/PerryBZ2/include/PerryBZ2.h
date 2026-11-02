#ifndef PERRYBZ2_H
#define PERRYBZ2_H

// libPerrybz2: Darwin's bzip2 imports, bound to Linux's libbz2.

/// Linux's symbol for a Mach-O name, or NULL. The loader asks for imports
/// this library does not define itself.
void *perry_provider_symbol(const char *name);

#endif
