// libPerryAccelerate's provider hook: the functions this library defines
// (vDSP, vForce, vImage) are its own ELF symbols, found first; the rest of
// Accelerate's imports (cblas_*, LAPACK) bind to OpenBLAS.

#include "PerryAccelerate.h"
#include "perry_wrapped.h"

extern float cblas_sdot(const int n, const float *x, const int incx, const float *y, const int incy);

static perry_wrapped_library openblas = PERRY_WRAPPED_LIBRARY(cblas_sdot);

__attribute__((visibility("default")))
void *perry_provider_symbol(const char *name) {
    return perry_wrapped_symbol(&openblas, name, NULL);
}
