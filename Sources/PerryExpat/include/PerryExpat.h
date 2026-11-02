#ifndef PERRYEXPAT_H
#define PERRYEXPAT_H

// libPerryexpat: Darwin's Expat imports, bound to Linux's libexpat.

/// Linux's symbol for a Mach-O name, or NULL. The loader asks for imports
/// this library does not define itself.
void *perry_provider_symbol(const char *name);

#endif
