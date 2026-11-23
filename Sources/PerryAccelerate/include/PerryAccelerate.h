#ifndef PERRY_ACCELERATE_H
#define PERRY_ACCELERATE_H

// libPerryAccelerate: the provider for Accelerate.framework. vDSP, vForce
// and vImage are implemented here; BLAS and LAPACK bind to OpenBLAS, whose
// CBLAS and LAPACK functions have Apple's ABI (32-bit integers).

#include <stddef.h>

#ifdef PERRY_ACCELERATE_TEST
// Built on a Mac to compare with Accelerate itself: perry_vDSP_vadd and so on.
#define DARWIN_SYMBOL(name) __asm__("_perry_" #name) __attribute__((visibility("default"), used))
#else
#define DARWIN_SYMBOL(name) __asm__("_" #name) __attribute__((visibility("default"), used))
#endif

typedef unsigned long vDSP_Length;
typedef long vDSP_Stride;

typedef struct DSPComplex { float real, imag; } DSPComplex;
typedef struct DSPSplitComplex { float *realp, *imagp; } DSPSplitComplex;
typedef struct DSPDoubleComplex { double real, imag; } DSPDoubleComplex;
typedef struct DSPDoubleSplitComplex { double *realp, *imagp; } DSPDoubleSplitComplex;

#endif
