#ifndef PERRYCURL_H
#define PERRYCURL_H

// libPerrycurl: Darwin's libcurl imports, bound to Linux's libcurl.

/// Linux's symbol for a Mach-O name, or NULL. The loader asks for imports
/// this library does not define itself.
void *perry_provider_symbol(const char *name);

#endif
