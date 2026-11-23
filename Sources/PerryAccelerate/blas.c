// BLAS and LAPACK are OpenBLAS's (provider.c binds their names); this is
// Accelerate's threading switch over OpenBLAS's thread count.

#include "PerryAccelerate.h"

extern void openblas_set_num_threads(int threads);
extern int openblas_get_num_threads(void);
extern int openblas_get_num_procs(void);

enum { BLAS_THREADING_MULTI_THREADED = 0, BLAS_THREADING_SINGLE_THREADED = 1, BLAS_THREADING_MAX_OPTIONS = 2 };

static unsigned threading = BLAS_THREADING_MULTI_THREADED;

int BLASSetThreading(unsigned model) DARWIN_SYMBOL(BLASSetThreading);
int BLASSetThreading(unsigned model) {
    if (model >= BLAS_THREADING_MAX_OPTIONS) return -1;
    threading = model;
#ifndef PERRY_ACCELERATE_TEST
    openblas_set_num_threads(model == BLAS_THREADING_SINGLE_THREADED ? 1 : openblas_get_num_procs());
#endif
    return 0;
}

unsigned BLASGetThreading(void) DARWIN_SYMBOL(BLASGetThreading);
unsigned BLASGetThreading(void) { return threading; }
