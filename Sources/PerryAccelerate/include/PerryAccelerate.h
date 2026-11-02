#ifndef PERRY_ACCELERATE_H
#define PERRY_ACCELERATE_H

// libPerryAccelerate: the provider for Accelerate.framework. vDSP, vForce
// and vImage are implemented here; BLAS and LAPACK bind to OpenBLAS, whose
// CBLAS and LAPACK functions have Apple's ABI (32-bit integers).

#include <stddef.h>

#define DARWIN_SYMBOL(name) __asm__("_" #name) __attribute__((visibility("default"), used))

typedef unsigned long vDSP_Length;
typedef long vDSP_Stride;

typedef struct DSPComplex { float real, imag; } DSPComplex;
typedef struct DSPSplitComplex { float *realp, *imagp; } DSPSplitComplex;
typedef struct DSPDoubleComplex { double real, imag; } DSPDoubleComplex;
typedef struct DSPDoubleSplitComplex { double *realp, *imagp; } DSPDoubleSplitComplex;

#endif
