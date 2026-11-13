#ifndef PERRYBOM_H
#define PERRYBOM_H

// libPerryBom: the provider for Bom.framework's copier, which unpacks and copies
// files and archives: zip archives and directory trees.

/// Linux's symbol for a Mach-O name, or NULL. The loader asks for imports
/// this library does not define itself.
void *perry_provider_symbol(const char *name);

#endif
