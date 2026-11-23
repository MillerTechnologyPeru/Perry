// Quadrature: integration of a function over an interval by adaptive
// 15-point Gauss-Kronrod rules, bisecting the interval with the largest
// error estimate until the requested tolerance is met. Infinite bounds are
// mapped onto finite ones (x = a + (1 - t) / t and its mirror images).

#include "PerryAccelerate.h"

#include <math.h>
#include <stdlib.h>

typedef void (*quadrature_function_array)(void *arg, size_t n, const double *x, double *y);
typedef struct { quadrature_function_array fun; void *fun_arg; } quadrature_integrate_function;
typedef struct {
    int integrator; // QNG 0, QAG 1, QAGS 2
    double abs_tolerance;
    double rel_tolerance;
    size_t qag_points_per_interval;
    size_t max_intervals;
} quadrature_integrate_options;

enum {
    QUADRATURE_SUCCESS = 0,
    QUADRATURE_ERROR = -1,
    QUADRATURE_INVALID_ARG_ERROR = -2,
    QUADRATURE_ALLOC_ERROR = -3,
    QUADRATURE_INTEGRATE_MAX_EVAL_ERROR = -101,
};

static const double kronrod_nodes[8] = {
    0.991455371120812639206854697526329, 0.949107912342758524526189684047851, 0.864864423359769072789712788640926,
    0.741531185599394439863864773280788, 0.586087235467691130294144845693013, 0.405845151377397166906606412076961,
    0.207784955007898467600689403773245, 0.0,
};
static const double kronrod_weights[8] = {
    0.022935322010529224963732008058970, 0.063092092629978553290700663189204, 0.104790010322250183839876322541518,
    0.140653259715525918745189590510238, 0.169004726639267902826583426598550, 0.190350578064785409913256402421014,
    0.204432940075298892414161999234649, 0.209482141084727828012999174891714,
};
// The 7-point Gauss rule's weights, at the odd Kronrod nodes and the centre.
static const double gauss_weights[4] = {
    0.129484966168869693270611432679082, 0.279705391489276667901467771423780, 0.381830050505118944950369775488975,
    0.417959183673469387755102040816327,
};

typedef struct integrand {
    const quadrature_integrate_function *f;
    int mapping; // 0 finite; 1 [a, +inf); 2 (-inf, b]; 3 (-inf, +inf)
    double bound;
} integrand;

/// The 15 values of the integrand at t's nodes, mapped as `g` says.
static void evaluate(const integrand *g, const double *t, double *y, size_t n) {
    double x[15];
    for (size_t i = 0; i < n; i++) {
        double u = t[i];
        switch (g->mapping) {
        case 1: x[i] = g->bound + (1 - u) / u; break;
        case 2: x[i] = g->bound - (1 - u) / u; break;
        case 3: x[i] = (1 - u) / u; break;
        default: x[i] = u; break;
        }
    }
    g->f->fun(g->f->fun_arg, n, x, y);
    for (size_t i = 0; i < n; i++) {
        double u = t[i];
        if (g->mapping) y[i] /= u * u;
    }
    if (g->mapping == 3) {
        // f(x) + f(-x) over (0, 1]: evaluate the mirror image too.
        double m[15], z[15];
        for (size_t i = 0; i < n; i++) m[i] = -x[i];
        g->f->fun(g->f->fun_arg, n, m, z);
        for (size_t i = 0; i < n; i++) y[i] += z[i] / (t[i] * t[i]);
    }
}

/// One Gauss-Kronrod step over [a, b]: the estimate and its error.
static double rule(const integrand *g, double a, double b, double *error) {
    double centre = (a + b) / 2, half = (b - a) / 2, t[15], y[15];
    for (int i = 0; i < 7; i++) { t[2 * i] = centre - half * kronrod_nodes[i]; t[2 * i + 1] = centre + half * kronrod_nodes[i]; }
    t[14] = centre;
    evaluate(g, t, y, 15);
    double kronrod = y[14] * kronrod_weights[7], gauss = y[14] * gauss_weights[3];
    for (int i = 0; i < 7; i++) {
        double pair = y[2 * i] + y[2 * i + 1];
        kronrod += pair * kronrod_weights[i];
        if (i & 1) gauss += pair * gauss_weights[i / 2];
    }
    *error = fabs((kronrod - gauss) * half);
    return kronrod * half;
}

typedef struct piece { double a, b, value, error; } piece;

double quadrature_integrate(const quadrature_integrate_function *f, double a, double b, const quadrature_integrate_options *options,
                            int *status, double *abs_error, size_t workspace_size, void *workspace)
    DARWIN_SYMBOL(quadrature_integrate);
double quadrature_integrate(const quadrature_integrate_function *f, double a, double b, const quadrature_integrate_options *options,
                            int *status, double *abs_error, size_t workspace_size, void *workspace) {
    int ignored;
    if (!status) status = &ignored;
    if (!f || !f->fun || !options || isnan(a) || isnan(b)) { *status = QUADRATURE_INVALID_ARG_ERROR; return 0; }
    if (a == b) { *status = QUADRATURE_SUCCESS; if (abs_error) *abs_error = 0; return 0; }
    double sign = 1;
    if (a > b) { double t = a; a = b; b = t; sign = -1; }
    integrand g = {f, 0, 0};
    double lo = a, hi = b;
    if (isinf(a) || isinf(b)) {
        if (isinf(a) && isinf(b)) g.mapping = 3;
        else if (isinf(b)) { g.mapping = 1; g.bound = a; }
        else { g.mapping = 2; g.bound = b; }
        lo = 0; hi = 1;
    }
    size_t limit = options->max_intervals ? options->max_intervals : 50;

    piece *pieces = malloc(limit * sizeof(piece));
    if (!pieces) { *status = QUADRATURE_ALLOC_ERROR; return 0; }
    size_t count = 1;
    pieces[0].a = lo; pieces[0].b = hi;
    pieces[0].value = rule(&g, lo, hi, &pieces[0].error);
    double total = pieces[0].value, error = pieces[0].error;
    *status = QUADRATURE_SUCCESS;
    while (error > fmax(options->abs_tolerance, options->rel_tolerance * fabs(total))) {
        if (count >= limit) { *status = QUADRATURE_INTEGRATE_MAX_EVAL_ERROR; break; }
        size_t worst = 0;
        for (size_t i = 1; i < count; i++) if (pieces[i].error > pieces[worst].error) worst = i;
        piece p = pieces[worst];
        double middle = (p.a + p.b) / 2, e1, e2;
        double v1 = rule(&g, p.a, middle, &e1), v2 = rule(&g, middle, p.b, &e2);
        pieces[worst] = (piece){p.a, middle, v1, e1};
        pieces[count++] = (piece){middle, p.b, v2, e2};
        total = 0; error = 0;
        for (size_t i = 0; i < count; i++) { total += pieces[i].value; error += pieces[i].error; }
    }
    free(pieces);
    if (abs_error) *abs_error = error;
    return sign * total;
}
