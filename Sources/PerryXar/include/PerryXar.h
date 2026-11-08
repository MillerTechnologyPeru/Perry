#ifndef PERRYXAR_H
#define PERRYXAR_H

// libPerryxar: Darwin's xar imports, bound to Linux's libxar.

/// Linux's symbol for a Mach-O name, or NULL. The loader asks for imports
/// this library does not define itself.
void *perry_provider_symbol(const char *name);

#endif
