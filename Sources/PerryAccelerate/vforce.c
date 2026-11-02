// vForce: math functions over arrays. Each takes the result first and the
// count by pointer; vvpow(z, y, x, n) is x to the y.

#include "PerryAccelerate.h"

#include <math.h>

#define UNARY(name, function) \
    void vv##name##f(float *y, const float *x, const int *n) DARWIN_SYMBOL(vv##name##f); \
    void vv##name##f(float *y, const float *x, const int *n) { for (int i = 0; i < *n; i++) y[i] = function##f(x[i]); } \
    void vv##name(double *y, const double *x, const int *n) DARWIN_SYMBOL(vv##name); \
    void vv##name(double *y, const double *x, const int *n) { for (int i = 0; i < *n; i++) y[i] = function(x[i]); }

#define BINARY(name, expr) \
    void vv##name##f(float *z, const float *y, const float *x, const int *n) DARWIN_SYMBOL(vv##name##f); \
    void vv##name##f(float *z, const float *y, const float *x, const int *n) { \
        for (int i = 0; i < *n; i++) { float a = y[i], b = x[i]; z[i] = (float)(expr); } \
    } \
    void vv##name(double *z, const double *y, const double *x, const int *n) DARWIN_SYMBOL(vv##name); \
    void vv##name(double *z, const double *y, const double *x, const int *n) { \
        for (int i = 0; i < *n; i++) { double a = y[i], b = x[i]; z[i] = (expr); } \
    }

static inline float recf(float x) { return 1 / x; }
static inline double rec(double x) { return 1 / x; }
static inline float rsqrtf(float x) { return 1 / sqrtf(x); }
static inline double rsqrt(double x) { return 1 / sqrt(x); }
static inline float nintf(float x) { return rintf(x); }
static inline double nint(double x) { return rint(x); }

UNARY(sqrt, sqrt)
UNARY(cbrt, cbrt)
UNARY(rsqrt, rsqrt)
UNARY(rec, rec)
UNARY(exp, exp)
UNARY(exp2, exp2)
UNARY(expm1, expm1)
UNARY(log, log)
UNARY(log2, log2)
UNARY(log10, log10)
UNARY(log1p, log1p)
UNARY(logb, logb)
UNARY(sin, sin)
UNARY(cos, cos)
UNARY(tan, tan)
UNARY(asin, asin)
UNARY(acos, acos)
UNARY(atan, atan)
UNARY(sinh, sinh)
UNARY(cosh, cosh)
UNARY(tanh, tanh)
UNARY(asinh, asinh)
UNARY(acosh, acosh)
UNARY(atanh, atanh)
UNARY(fabs, fabs)
UNARY(floor, floor)
UNARY(ceil, ceil)
UNARY(nint, nint)

void vvintf(float *y, const float *x, const int *n) DARWIN_SYMBOL(vvintf);
void vvintf(float *y, const float *x, const int *n) { for (int i = 0; i < *n; i++) y[i] = truncf(x[i]); }
void vvint(double *y, const double *x, const int *n) DARWIN_SYMBOL(vvint);
void vvint(double *y, const double *x, const int *n) { for (int i = 0; i < *n; i++) y[i] = trunc(x[i]); }

BINARY(pow, pow(b, a))
BINARY(atan2, atan2(a, b))
BINARY(div, a / b)
BINARY(fmod, fmod(a, b))
BINARY(remainder, remainder(a, b))
BINARY(copysign, copysign(a, b))
BINARY(nextafter, nextafter(a, b))

void vvsincosf(float *s, float *c, const float *x, const int *n) DARWIN_SYMBOL(vvsincosf);
void vvsincosf(float *s, float *c, const float *x, const int *n) { for (int i = 0; i < *n; i++) { s[i] = sinf(x[i]); c[i] = cosf(x[i]); } }
void vvsincos(double *s, double *c, const double *x, const int *n) DARWIN_SYMBOL(vvsincos);
void vvsincos(double *s, double *c, const double *x, const int *n) { for (int i = 0; i < *n; i++) { s[i] = sin(x[i]); c[i] = cos(x[i]); } }

void vvpowsf(float *z, const float *y, const float *x, const int *n) DARWIN_SYMBOL(vvpowsf);
void vvpowsf(float *z, const float *y, const float *x, const int *n) { for (int i = 0; i < *n; i++) z[i] = powf(x[i], *y); }
void vvpows(double *z, const double *y, const double *x, const int *n) DARWIN_SYMBOL(vvpows);
void vvpows(double *z, const double *y, const double *x, const int *n) { for (int i = 0; i < *n; i++) z[i] = pow(x[i], *y); }
