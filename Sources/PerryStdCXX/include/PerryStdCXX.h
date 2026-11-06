#ifndef PERRYSTDCXX_H
#define PERRYSTDCXX_H

// libPerryStdCXX: Darwin's libstdc++ imports, bound to Linux's libstdc++.

/// Linux's symbol for a Mach-O name, or NULL. The loader asks for imports
/// this library does not define itself.
void *perry_provider_symbol(const char *name);

#endif
