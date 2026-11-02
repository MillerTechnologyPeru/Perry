// Drawing: paths, fills (winding and even-odd), strokes with widths, caps
// and dashes, ellipses, arcs, rounded rects, clipping, transforms, linear
// and radial gradients, transparency layers, blend modes and text, in a
// bitmap context of each memory layout. Anti-aliased edges differ between
// renderers, so pixels are checked well inside shapes and gaps, against
// expected colors within a tolerance; each line prints 1 for a pass.
// Recorded on the iOS Simulator.

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static NSString *rectString(CGRect r) {
    return [NSString stringWithFormat:@"{{%g, %g}, {%g, %g}}", r.origin.x, r.origin.y, r.size.width, r.size.height];
}
#define NSStringFromCGRect rectString

static CGContextRef context;
static uint8_t *memory;
static size_t rowBytes;
static int uikitLayout;

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

/// RGBA at x, y counted from the top-left of memory.
static void rgba(int x, int y, int out[4]) {
    uint8_t *p = memory + y * rowBytes + x * 4;
    if (uikitLayout) { out[0] = p[2]; out[1] = p[1]; out[2] = p[0]; out[3] = p[3]; }
    else { out[0] = p[0]; out[1] = p[1]; out[2] = p[2]; out[3] = p[3]; }
}

/// Whether the pixel is within `tolerance` of r, g, b, a.
static int is(int x, int y, int r, int g, int b, int a, int tolerance) {
    int p[4];
    rgba(x, y, p);
    int want[4] = {r, g, b, a};
    for (int i = 0; i < 4; i++) if (abs(p[i] - want[i]) > tolerance) return 0;
    return 1;
}

static void fresh(int uikit) {
    if (context) CGContextRelease(context);
    free(memory);
    uikitLayout = uikit;
    rowBytes = 64 * 4;
    memory = calloc(64 * rowBytes, 1);
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    context = CGBitmapContextCreate(memory, 64, 64, 8, rowBytes, rgb,
                                    uikit ? (kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little)
                                          : (kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big));
    CGColorSpaceRelease(rgb);
}

static void scene(int uikit) {
    const char *name = uikit ? "uikit layout" : "rgba layout";

    // A triangle, filled: points near its middle are red, outside clear.
    fresh(uikit);
    CGContextSetRGBFillColor(context, 1, 0, 0, 1);
    CGContextBeginPath(context);
    CGContextMoveToPoint(context, 8, 8);
    CGContextAddLineToPoint(context, 56, 8);
    CGContextAddLineToPoint(context, 32, 56);
    CGContextClosePath(context);
    say([NSString stringWithFormat:@"%s triangle: path empty %d, current %.0f,%.0f, box %@", name, CGContextIsPathEmpty(context),
         CGContextGetPathCurrentPoint(context).x, CGContextGetPathCurrentPoint(context).y,
         NSStringFromCGRect(CGContextGetPathBoundingBox(context))]);
    CGContextFillPath(context);
    say([NSString stringWithFormat:@"  fill: inside %d, top corner clear %d, after fill empty %d", is(32, 40, 255, 0, 0, 255, 0),
         is(4, 4, 0, 0, 0, 0, 0), CGContextIsPathEmpty(context)]);

    // Even-odd: a square with a square hole.
    fresh(uikit);
    CGContextSetRGBFillColor(context, 0, 0, 1, 1);
    CGContextAddRect(context, CGRectMake(8, 8, 48, 48));
    CGContextAddRect(context, CGRectMake(24, 24, 16, 16));
    CGContextEOFillPath(context);
    say([NSString stringWithFormat:@"%s even-odd: ring %d, hole %d", name, is(12, 12, 0, 0, 255, 255, 0), is(32, 32, 0, 0, 0, 0, 0)]);
    CGContextAddRect(context, CGRectMake(8, 8, 48, 48));
    CGContextAddRect(context, CGRectMake(24, 24, 16, 16));
    CGContextFillPath(context);
    say([NSString stringWithFormat:@"  winding fills the hole %d", is(32, 32, 0, 0, 255, 255, 0)]);

    // Strokes: width, square caps reaching past the end, a dash gap.
    fresh(uikit);
    CGContextSetRGBStrokeColor(context, 0, 1, 0, 1);
    CGContextSetLineWidth(context, 6);
    CGContextSetLineCap(context, kCGLineCapSquare);
    CGContextMoveToPoint(context, 10, 32);
    CGContextAddLineToPoint(context, 40, 32);
    CGContextStrokePath(context);
    say([NSString stringWithFormat:@"%s stroke: on line %d, within width %d, beyond width %d, square cap %d, past cap %d", name,
         is(25, 31, 0, 255, 0, 255, 0), is(25, 29, 0, 255, 0, 255, 0), is(25, 26, 0, 0, 0, 0, 0), is(42, 31, 0, 255, 0, 255, 0),
         is(46, 31, 0, 0, 0, 0, 0)]);
    CGFloat dashes[] = {8, 8};
    CGContextSetLineDash(context, 0, dashes, 2);
    CGContextSetLineCap(context, kCGLineCapButt);
    CGContextSetLineWidth(context, 4);
    CGContextMoveToPoint(context, 0, 10);
    CGContextAddLineToPoint(context, 64, 10);
    CGContextStrokePath(context);
    say([NSString stringWithFormat:@"  dashes: dash %d gap %d dash %d", is(4, 53, 0, 255, 0, 255, 0), is(12, 53, 0, 0, 0, 0, 0),
         is(20, 53, 0, 255, 0, 255, 0)]);

    // Ellipse, arc, rounded rect.
    fresh(uikit);
    CGContextSetRGBFillColor(context, 1, 1, 0, 1);
    CGContextFillEllipseInRect(context, CGRectMake(0, 0, 64, 32));
    say([NSString stringWithFormat:@"%s ellipse: center %d, corner clear %d, edge middle %d", name, is(32, 48, 255, 255, 0, 255, 0),
         is(1, 33, 0, 0, 0, 0, 0), is(2, 48, 255, 255, 0, 255, 0)]);
    CGContextSetRGBStrokeColor(context, 1, 0, 1, 1);
    CGContextSetLineWidth(context, 4);
    CGContextAddArc(context, 32, 44, 12, 0, M_PI, 0);
    CGContextStrokePath(context);
    say([NSString stringWithFormat:@"  arc: top %d, below center clear %d", is(32, 8, 255, 0, 255, 255, 0), is(32, 31, 0, 0, 0, 0, 0)]);
    CGPathRef rounded = CGPathCreateWithRoundedRect(CGRectMake(40, 40, 20, 20), 8, 8, NULL);
    CGContextAddPath(context, rounded);
    CGContextSetRGBFillColor(context, 0, 1, 1, 1);
    CGContextFillPath(context);
    say([NSString stringWithFormat:@"  rounded rect: middle %d, rounded corner clear %d, flat edge %d", is(50, 14, 0, 255, 255, 255, 0),
         is(40, 4, 0, 0, 0, 0, 0), is(50, 5, 0, 255, 255, 255, 0)]);

    // Clipping and the graphics state.
    fresh(uikit);
    CGContextSaveGState(context);
    CGContextClipToRect(context, CGRectMake(0, 0, 32, 64));
    CGContextSetRGBFillColor(context, 1, 0, 0, 1);
    CGContextFillRect(context, CGRectMake(0, 0, 64, 64));
    CGContextRestoreGState(context);
    say([NSString stringWithFormat:@"%s clip: inside %d outside %d", name, is(10, 10, 255, 0, 0, 255, 0), is(50, 10, 0, 0, 0, 0, 0)]);
    CGContextFillRect(context, CGRectMake(48, 0, 16, 16));
    say([NSString stringWithFormat:@"  restored fill color black %d", is(56, 56, 0, 0, 0, 255, 0)]);

    // Transforms.
    fresh(uikit);
    CGContextTranslateCTM(context, 32, 32);
    CGContextScaleCTM(context, 2, 2);
    CGContextRotateCTM(context, M_PI_2);
    CGAffineTransform ctm = CGContextGetCTM(context);
    say([NSString stringWithFormat:@"%s ctm: %.2f %.2f %.2f %.2f %.1f %.1f", name, ctm.a + 0.0, ctm.b + 0.0, ctm.c + 0.0, ctm.d + 0.0,
         ctm.tx, ctm.ty]);
    CGContextSetRGBFillColor(context, 0, 0, 1, 1);
    CGContextFillRect(context, CGRectMake(0, 0, 8, 4));
    // Rotated a quarter turn and doubled: device x -8..0, y 0..16 up from the center.
    say([NSString stringWithFormat:@"  rotated rect: %d, unrotated spot clear %d", is(28, 24, 0, 0, 255, 255, 0), is(36, 30, 0, 0, 0, 0, 0)]);

    // Gradients.
    fresh(uikit);
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGFloat components[] = {1, 0, 0, 1, 0, 0, 1, 1};
    CGGradientRef gradient = CGGradientCreateWithColorComponents(rgb, components, NULL, 2);
    CGContextDrawLinearGradient(context, gradient, CGPointMake(0, 0), CGPointMake(64, 0), 0);
    say([NSString stringWithFormat:@"%s linear: start %d, middle %d, end %d", name, is(0, 32, 255, 0, 0, 255, 6),
         is(32, 32, 127, 0, 127, 255, 6), is(63, 32, 0, 0, 255, 255, 6)]);
    fresh(uikit);
    CGContextDrawRadialGradient(context, gradient, CGPointMake(32, 32), 0, CGPointMake(32, 32), 32, 0);
    say([NSString stringWithFormat:@"  radial: center %d, halfway %d, corner unpainted %d", is(32, 32, 255, 0, 0, 255, 24),
         is(48, 32, 127, 0, 127, 255, 10), is(1, 1, 0, 0, 0, 0, 0)]);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(rgb);

    // Alpha, layers and blend modes.
    fresh(uikit);
    CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    CGContextFillRect(context, CGRectMake(0, 0, 64, 64));
    CGContextSetAlpha(context, 0.5);
    CGContextSetRGBFillColor(context, 0, 0, 0, 1);
    CGContextFillRect(context, CGRectMake(0, 0, 32, 64));
    say([NSString stringWithFormat:@"%s global alpha: half black over white %d", name, is(10, 10, 128, 128, 128, 255, 2)]);
    CGContextSetAlpha(context, 1);
    CGContextSetBlendMode(context, kCGBlendModeMultiply);
    CGContextSetRGBFillColor(context, 1, 0, 0, 1);
    CGContextFillRect(context, CGRectMake(32, 0, 32, 32));
    say([NSString stringWithFormat:@"  multiply: red over white %d", is(48, 48, 255, 0, 0, 255, 0)]);
    CGContextSetBlendMode(context, kCGBlendModeNormal);
    CGContextSetAlpha(context, 0.5);
    CGContextBeginTransparencyLayer(context, NULL);
    CGContextSetRGBFillColor(context, 0, 0, 1, 1);
    CGContextFillRect(context, CGRectMake(32, 32, 32, 32));
    CGContextFillRect(context, CGRectMake(40, 40, 16, 16));
    CGContextEndTransparencyLayer(context);
    say([NSString stringWithFormat:@"  layer: overlap composited once %d", is(48, 16, 128, 128, 255, 255, 2)]);

    // Clearing and text.
    CGContextClearRect(context, CGRectMake(0, 0, 8, 8));
    say([NSString stringWithFormat:@"%s clear: %d", name, is(2, 61, 0, 0, 0, 0, 0)]);
    fresh(uikit);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CGContextSelectFont(context, "Helvetica", 24, kCGEncodingMacRoman);
    CGContextSetRGBFillColor(context, 0, 0, 0, 1);
    CGContextShowTextAtPoint(context, 4, 20, "Hi", 2);
#pragma clang diagnostic pop
    int painted = 0;
    for (int y = 0; y < 64; y++) for (int x = 0; x < 64; x++) { int p[4]; rgba(x, y, p); if (p[3] > 128) painted++; }
    say([NSString stringWithFormat:@"%s text: painted %d, advanced %d", name, painted > 20, CGContextGetTextPosition(context).x > 20]);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // Paths on their own.
        CGMutablePathRef path = CGPathCreateMutable();
        CGPathMoveToPoint(path, NULL, 0, 0);
        CGPathAddLineToPoint(path, NULL, 10, 0);
        CGPathAddCurveToPoint(path, NULL, 10, 20, 0, 20, 0, 10);
        CGPathCloseSubpath(path);
        int counts[5] = {0};
        int *tally = counts;
        CGPathApplyWithBlock(path, ^(const CGPathElement *element) { tally[element->type]++; });
        CGRect rect;
        say([NSString stringWithFormat:@"path: box %@, empty %d, contains %d %d, current %.0f,%.0f, elements %d %d %d %d %d, rect %d",
             NSStringFromCGRect(CGPathGetBoundingBox(path)), CGPathIsEmpty(path), CGPathContainsPoint(path, NULL, CGPointMake(5, 5), false),
             CGPathContainsPoint(path, NULL, CGPointMake(30, 5), false), CGPathGetCurrentPoint(path).x, CGPathGetCurrentPoint(path).y,
             counts[0], counts[1], counts[2], counts[3], counts[4], CGPathIsRect(path, &rect)]);
        CGPathRef box = CGPathCreateWithRect(CGRectMake(1, 2, 3, 4), NULL);
        CGAffineTransform shift = CGAffineTransformMakeTranslation(10, 0);
        CGPathRef moved = CGPathCreateCopyByTransformingPath(box, &shift);
        say([NSString stringWithFormat:@"rect path: is rect %d %@, moved %@, equal %d %d", CGPathIsRect(box, &rect), NSStringFromCGRect(rect),
             NSStringFromCGRect(CGPathGetBoundingBox(moved)), CGPathEqualToPath(box, box), CGPathEqualToPath(box, moved)]);
        CGPathRef ellipse = CGPathCreateWithEllipseInRect(CGRectMake(0, 0, 20, 10), NULL);
        say([NSString stringWithFormat:@"ellipse path: box %@, contains center %d corner %d", NSStringFromCGRect(CGPathGetBoundingBox(ellipse)),
             CGPathContainsPoint(ellipse, NULL, CGPointMake(10, 5), false), CGPathContainsPoint(ellipse, NULL, CGPointMake(1, 1), false)]);

        scene(0);
        scene(1);
    }
    return 0;
}
