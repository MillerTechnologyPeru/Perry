#ifndef PERRY_XML2_H
#define PERRY_XML2_H

// libPerryxml2: Darwin's libxml2 imports, bound to Linux's libxml2.

/// Linux's libxml2 symbol for a Mach-O name ("_xmlParseMemory"), function
/// or data, or NULL. The loader asks for imports this library does not
/// define itself.
void *perry_provider_symbol(const char *name);

#endif
