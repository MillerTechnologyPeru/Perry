// CoreGraphics through Darwin's types: geometry functions that pass and
// return CGFloat structures (in core registers and memory on armv7, where
// CGFloat is a float), affine transforms, colors' components, paths, and a
// bitmap context filled with rects and an ellipse and read back. Its fills
// are axis-aligned or sampled away from edges, so any renderer gives the
// same pixels; a Mac records what it prints.
#include "darwin.h"

#if __LP64__
typedef double CGFloat;
#else
typedef float CGFloat;
#endif
typedef struct { CGFloat x, y; } CGPoint;
typedef struct { CGFloat width, height; } CGSize;
typedef struct { CGPoint origin; CGSize size; } CGRect;
typedef struct { CGFloat a, b, c, d, tx, ty; } CGAffineTransform;
typedef const void *CGColorSpaceRef, *CGColorRef, *CGContextRef, *CGPathRef;
typedef void *CGMutablePathRef;
typedef _Bool bool;
void *calloc(size_t, size_t);

CGFloat CGRectGetMidX(CGRect);
CGFloat CGRectGetMaxY(CGRect);
CGRect CGRectIntersection(CGRect, CGRect);
CGRect CGRectUnion(CGRect, CGRect);
CGRect CGRectInset(CGRect, CGFloat, CGFloat);
CGRect CGRectOffset(CGRect, CGFloat, CGFloat);
bool CGRectContainsPoint(CGRect, CGPoint);
bool CGRectEqualToRect(CGRect, CGRect);
CGAffineTransform CGAffineTransformMakeRotation(CGFloat);
CGAffineTransform CGAffineTransformMakeScale(CGFloat, CGFloat);
CGAffineTransform CGAffineTransformTranslate(CGAffineTransform, CGFloat, CGFloat);
CGAffineTransform CGAffineTransformConcat(CGAffineTransform, CGAffineTransform);
CGAffineTransform CGAffineTransformInvert(CGAffineTransform);
CGPoint CGPointApplyAffineTransform(CGPoint, CGAffineTransform);
CGRect CGRectApplyAffineTransform(CGRect, CGAffineTransform);

CGColorSpaceRef CGColorSpaceCreateDeviceRGB(void);
void CGColorSpaceRelease(CGColorSpaceRef);
CGColorRef CGColorCreate(CGColorSpaceRef, const CGFloat *);
const CGFloat *CGColorGetComponents(CGColorRef);
CGFloat CGColorGetAlpha(CGColorRef);
void CGColorRelease(CGColorRef);

CGContextRef CGBitmapContextCreate(void *, size_t, size_t, size_t, size_t, CGColorSpaceRef, unsigned int);
void CGContextRelease(CGContextRef);
void CGContextSetRGBFillColor(CGContextRef, CGFloat, CGFloat, CGFloat, CGFloat);
void CGContextFillRect(CGContextRef, CGRect);
void CGContextFillEllipseInRect(CGContextRef, CGRect);
void CGContextTranslateCTM(CGContextRef, CGFloat, CGFloat);
void CGContextScaleCTM(CGContextRef, CGFloat, CGFloat);

CGMutablePathRef CGPathCreateMutable(void);
void CGPathMoveToPoint(CGMutablePathRef, const CGAffineTransform *, CGFloat, CGFloat);
void CGPathAddLineToPoint(CGMutablePathRef, const CGAffineTransform *, CGFloat, CGFloat);
void CGPathAddRect(CGMutablePathRef, const CGAffineTransform *, CGRect);
CGRect CGPathGetBoundingBox(CGPathRef);
void CGPathRelease(CGPathRef);

static CGRect rect(CGFloat x, CGFloat y, CGFloat w, CGFloat h) { CGRect r = { { x, y }, { w, h } }; return r; }

static void show(const char *label, CGRect r) {
    printf("%s %.2f %.2f %.2f %.2f\n", label, (double)r.origin.x, (double)r.origin.y, (double)r.size.width,
           (double)r.size.height);
}

// kCGImageAlphaPremultipliedLast: R, G, B, A bytes.
static void pixel(const unsigned char *pixels, int width, int x, int y) {
    const unsigned char *p = pixels + (y * width + x) * 4;
    printf("pixel %d,%d: %d %d %d %d\n", x, y, p[0], p[1], p[2], p[3]);
}

int main(void) {
    CGRect a = rect(10, 20, 100, 50), b = rect(60, 40, 100, 100);
    printf("mid %.2f maxY %.2f\n", (double)CGRectGetMidX(a), (double)CGRectGetMaxY(a));
    show("intersection", CGRectIntersection(a, b));
    show("union", CGRectUnion(a, b));
    show("inset", CGRectInset(a, 5, 2.5f));
    show("offset", CGRectOffset(a, -10, 0.5f));
    CGPoint inside = { 50, 30 }, outside = { 5, 30 };
    printf("contains %d %d equal %d\n", CGRectContainsPoint(a, inside), CGRectContainsPoint(a, outside),
           CGRectEqualToRect(a, rect(10, 20, 100, 50)));

    CGAffineTransform scale = CGAffineTransformMakeScale(2, 3);
    CGAffineTransform moved = CGAffineTransformTranslate(scale, 5, -1);
    CGAffineTransform turned = CGAffineTransformConcat(moved, CGAffineTransformMakeRotation(3.14159265f / 2));
    printf("transform %.3f %.3f %.3f %.3f %.3f %.3f\n", (double)turned.a, (double)turned.b, (double)turned.c,
           (double)turned.d, (double)turned.tx, (double)turned.ty);
    CGPoint p = CGPointApplyAffineTransform(inside, moved);
    printf("point %.2f %.2f\n", (double)p.x, (double)p.y);
    CGAffineTransform back = CGAffineTransformInvert(moved);
    CGPoint q = CGPointApplyAffineTransform(p, back);
    printf("inverted %.2f %.2f\n", (double)q.x, (double)q.y);
    show("transformed", CGRectApplyAffineTransform(a, scale));

    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    const CGFloat orange[] = { 1, 0.5f, 0.25f, 0.75f };
    CGColorRef color = CGColorCreate(space, orange);
    const CGFloat *components = CGColorGetComponents(color);
    printf("color %.3f %.3f %.3f %.3f alpha %.3f\n", (double)components[0], (double)components[1],
           (double)components[2], (double)components[3], (double)CGColorGetAlpha(color));
    CGColorRelease(color);

    CGMutablePathRef path = CGPathCreateMutable();
    CGPathMoveToPoint(path, 0, 3, 4);
    CGPathAddLineToPoint(path, 0, 30, -6);
    CGPathAddRect(path, 0, rect(-2, 10, 5, 8.5f));
    show("path", CGPathGetBoundingBox(path));
    CGPathRelease(path);

    enum { width = 40, height = 30 };
    unsigned char *pixels = calloc(width * height, 4);
    CGContextRef context = CGBitmapContextCreate(pixels, width, height, 8, width * 4, space, 1);
    CGContextSetRGBFillColor(context, 0, 0, 1, 1);
    CGContextFillRect(context, rect(0, 0, width, height));
    CGContextSetRGBFillColor(context, 1, 0, 0, 1);
    CGContextFillRect(context, rect(5, 5, 10, 8));
    CGContextTranslateCTM(context, 20, 10);
    CGContextScaleCTM(context, 2, 1);
    CGContextSetRGBFillColor(context, 0, 1, 0, 1);
    CGContextFillEllipseInRect(context, rect(0, 0, 8, 12));
    // Rows run top to bottom in memory; CoreGraphics' y runs up.
    pixel(pixels, width, 2, height - 1 - 2);
    pixel(pixels, width, 10, height - 1 - 9);
    pixel(pixels, width, 28, height - 1 - 16);
    pixel(pixels, width, 21, height - 1 - 11);
    CGContextRelease(context);
    CGColorSpaceRelease(space);
    free(pixels);
    return 0;
}
