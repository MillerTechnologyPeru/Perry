#ifndef CPERRY_JAVASCRIPTCORE_H
#define CPERRY_JAVASCRIPTCORE_H

#include <stdint.h>

// Calls `function` with x0 to x7 from `x` and d0 to d7 from `d` (bit
// patterns: a float sits in the low 32 bits), as exported methods and
// blocks take their arguments; returns x0 and stores d0 in `d0`. Arguments
// that would go on the stack, and structures, are not supported.
uint64_t perry_jsc_call(const void *function, const uint64_t x[8], const uint64_t d[8], uint64_t *d0);

#endif
