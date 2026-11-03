// Apple's math additions to libm, which Darwin's compilers call for sin
// and cos of one value together (returning both in registers, as a struct
// of two) and for sine, cosine and tangent of π times a value.

#define _GNU_SOURCE
#include "PerrySystem.h"

#include <math.h>

struct darwin_float2 { float sinval, cosval; };
struct darwin_double2 { double sinval, cosval; };

struct darwin_float2 darwin___sincosf_stret(float x) DARWIN_SYMBOL(__sincosf_stret);
struct darwin_float2 darwin___sincosf_stret(float x) {
    struct darwin_float2 result;
    sincosf(x, &result.sinval, &result.cosval);
    return result;
}

struct darwin_double2 darwin___sincos_stret(double x) DARWIN_SYMBOL(__sincos_stret);
struct darwin_double2 darwin___sincos_stret(double x) {
    struct darwin_double2 result;
    sincos(x, &result.sinval, &result.cosval);
    return result;
}

// π times x, reduced to a turn either way first.
static double pi_times(double x) { return remainder(x, 2.0) * M_PI; }

double darwin___sinpi(double x) DARWIN_SYMBOL(__sinpi);
double darwin___sinpi(double x) {
    double r = remainder(x, 2.0);
    if (r == 0 || r == 1 || r == -1) return copysign(0.0, x);
    if (r == 0.5) return 1;
    if (r == -0.5) return -1;
    return sin(pi_times(x));
}

double darwin___cospi(double x) DARWIN_SYMBOL(__cospi);
double darwin___cospi(double x) {
    double r = fabs(remainder(x, 2.0));
    if (r == 0.5) return 0;
    if (r == 0) return 1;
    if (r == 1) return -1;
    return cos(pi_times(x));
}

double darwin___tanpi(double x) DARWIN_SYMBOL(__tanpi);
double darwin___tanpi(double x) { return darwin___sinpi(x) / darwin___cospi(x); }

float darwin___sinpif(float x) DARWIN_SYMBOL(__sinpif);
float darwin___sinpif(float x) { return (float)darwin___sinpi(x); }

float darwin___cospif(float x) DARWIN_SYMBOL(__cospif);
float darwin___cospif(float x) { return (float)darwin___cospi(x); }

float darwin___tanpif(float x) DARWIN_SYMBOL(__tanpif);
float darwin___tanpif(float x) { return (float)darwin___tanpi(x); }

struct darwin_float2 darwin___sincospif_stret(float x) DARWIN_SYMBOL(__sincospif_stret);
struct darwin_float2 darwin___sincospif_stret(float x) {
    struct darwin_float2 result = { darwin___sinpif(x), darwin___cospif(x) };
    return result;
}

struct darwin_double2 darwin___sincospi_stret(double x) DARWIN_SYMBOL(__sincospi_stret);
struct darwin_double2 darwin___sincospi_stret(double x) {
    struct darwin_double2 result = { darwin___sinpi(x), darwin___cospi(x) };
    return result;
}
