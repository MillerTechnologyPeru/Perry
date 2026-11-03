#ifndef PERRYOPENAL_H
#define PERRYOPENAL_H

// libPerryOpenAL: Darwin's OpenAL imports, bound to OpenAL Soft.

/// Linux's symbol for a Mach-O name, or NULL. The loader asks for imports
/// this library does not define itself.
void *perry_provider_symbol(const char *name);

#endif
