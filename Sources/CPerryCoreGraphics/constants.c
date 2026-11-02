// CoreGraphics' geometry constants, under Darwin's symbol names.

#include "CPerryCoreGraphics.h"

#include <math.h>
#include <float.h>

#define DARWIN_SYMBOL(name) __asm__(name) __attribute__((visibility("default"), used))

const CGPoint cg_point_zero DARWIN_SYMBOL("_CGPointZero") = {0, 0};
const CGSize cg_size_zero DARWIN_SYMBOL("_CGSizeZero") = {0, 0};
const CGRect cg_rect_zero DARWIN_SYMBOL("_CGRectZero") = {{0, 0}, {0, 0}};
// The null rect: an origin at infinity, which no rect intersects.
const CGRect cg_rect_null DARWIN_SYMBOL("_CGRectNull") = {{INFINITY, INFINITY}, {0, 0}};
// The infinite rect: as large as CGFloat allows, centred on the origin.
const CGRect cg_rect_infinite DARWIN_SYMBOL("_CGRectInfinite") =
    {{-DBL_MAX / 2, -DBL_MAX / 2}, {DBL_MAX, DBL_MAX}};
const CGAffineTransform cg_affine_transform_identity DARWIN_SYMBOL("_CGAffineTransformIdentity") =
    {1, 0, 0, 1, 0, 0};
