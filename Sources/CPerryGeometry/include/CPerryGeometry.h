#ifndef CPERRY_GEOMETRY_H
#define CPERRY_GEOMETRY_H

// CoreGraphics' geometry types, laid out as on 64-bit Darwin. Declared in C
// so Swift passes them as clang does: a CGRect is four doubles in d0-d3.
// CGFloat is double on 64-bit Darwin; it is spelled out because Swift's C
// importer treats a typedef named CGFloat specially and drops it on Linux.

typedef struct CGPoint {
    double x;
    double y;
} CGPoint;

typedef struct CGSize {
    double width;
    double height;
} CGSize;

typedef struct CGRect {
    CGPoint origin;
    CGSize size;
} CGRect;

typedef struct CGAffineTransform {
    double a, b, c, d;
    double tx, ty;
} CGAffineTransform;

#endif
