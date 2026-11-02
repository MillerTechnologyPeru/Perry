// Darwin's entry point for zlib's one variadic function.

#include "perry_wrapped.h"

#if defined(__aarch64__) && defined(__ELF__)

.text

// int gzprintf(gzFile file, const char *format, ...)
VARIADIC _gzprintf, gzvprintf, 2

#endif

.section .note.GNU-stack, "", %progbits
