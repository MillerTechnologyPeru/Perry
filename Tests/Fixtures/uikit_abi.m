// UIKit's geometry both ways across the Objective-C boundary, without an
// application or a screen: this program calling UIKit with frames, points,
// transforms and colors' CGFloats, and UIKit calling this program's
// overrides of -sizeThatFits:, -pointInside:withEvent: and -drawRect:. On
// armv7 CGFloat is a float, and structures of them pass in core registers.
// Built against the real UIKit where an SDK has it (Mac Catalyst records the
// expected output on a Mac), and otherwise against the declarations below.
#if __has_include(<UIKit/UIKit.h>)
#import <UIKit/UIKit.h>
#include <stdio.h>
#else
#include "darwin.h"
typedef struct objc_class *Class;
typedef struct objc_selector *SEL;
typedef signed char BOOL;
#define nil ((id)0)
#define NO ((BOOL)0)
#if __LP64__
typedef double CGFloat;
#else
typedef float CGFloat;
#endif
typedef struct CGPoint { CGFloat x, y; } CGPoint;
typedef struct CGSize { CGFloat width, height; } CGSize;
typedef struct CGRect { CGPoint origin; CGSize size; } CGRect;
typedef struct CGAffineTransform { CGFloat a, b, c, d, tx, ty; } CGAffineTransform;
typedef struct UIEdgeInsets { CGFloat top, left, bottom, right; } UIEdgeInsets;
static inline CGRect CGRectMake(CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
    CGRect r = { { x, y }, { w, h } };
    return r;
}
static inline CGPoint CGPointMake(CGFloat x, CGFloat y) { CGPoint p = { x, y }; return p; }
static inline CGSize CGSizeMake(CGFloat w, CGFloat h) { CGSize s = { w, h }; return s; }
CGAffineTransform CGAffineTransformMakeScale(CGFloat, CGFloat);
typedef struct CGContext *CGContextRef;

@class NSString, UIEvent, UIColor, UIImage, CALayer;

__attribute__((objc_root_class))
@interface NSObject { Class isa; }
+ (instancetype)alloc;
+ (instancetype)new;
- (instancetype)init;
@end

@interface NSString : NSObject
- (const char *)UTF8String;
@end

@interface UIColor : NSObject
+ (UIColor *)colorWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha;
+ (UIColor *)colorWithWhite:(CGFloat)white alpha:(CGFloat)alpha;
- (BOOL)getRed:(CGFloat *)red green:(CGFloat *)green blue:(CGFloat *)blue alpha:(CGFloat *)alpha;
- (BOOL)getWhite:(CGFloat *)white alpha:(CGFloat *)alpha;
- (UIColor *)colorWithAlphaComponent:(CGFloat)alpha;
@end

@interface CALayer : NSObject
@property CGFloat cornerRadius;
@property CGFloat borderWidth;
@property float opacity;
@property CGPoint position;
@property CGRect bounds;
- (void)renderInContext:(CGContextRef)context;
@end

@interface UIView : NSObject
- (instancetype)initWithFrame:(CGRect)frame;
@property CGRect frame;
@property CGRect bounds;
@property CGPoint center;
@property CGAffineTransform transform;
@property CGFloat alpha;
@property (readonly) CALayer *layer;
@property (copy) UIColor *backgroundColor;
- (void)addSubview:(UIView *)view;
- (CGPoint)convertPoint:(CGPoint)point toView:(UIView *)view;
- (CGRect)convertRect:(CGRect)rect fromView:(UIView *)view;
- (CGSize)sizeThatFits:(CGSize)size;
- (void)sizeToFit;
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event;
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event;
- (void)drawRect:(CGRect)rect;
- (void)setNeedsDisplay;
@end

@interface UIBezierPath : NSObject
+ (instancetype)bezierPathWithRoundedRect:(CGRect)rect cornerRadius:(CGFloat)radius;
+ (instancetype)bezierPathWithOvalInRect:(CGRect)rect;
@property (readonly) CGRect bounds;
- (void)applyTransform:(CGAffineTransform)transform;
@end

void UIGraphicsBeginImageContextWithOptions(CGSize size, BOOL opaque, CGFloat scale);
CGContextRef UIGraphicsGetCurrentContext(void);
void UIGraphicsEndImageContext(void);
#endif

static void showRect(const char *label, CGRect r) {
    printf("%s %.2f %.2f %.2f %.2f\n", label, (double)r.origin.x, (double)r.origin.y, (double)r.size.width,
           (double)r.size.height);
}

static void showPoint(const char *label, CGPoint p) { printf("%s %.2f %.2f\n", label, (double)p.x, (double)p.y); }

// A view whose overrides UIKit calls with geometry.
@interface Box : UIView
@property (nonatomic) int draws;
@end

@implementation Box
- (CGSize)sizeThatFits:(CGSize)size {
    printf("sizeThatFits %.2f %.2f\n", (double)size.width, (double)size.height);
    return CGSizeMake(size.width / 2 + 0.5f, 40.25f);
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    printf("pointInside %.2f %.2f\n", (double)point.x, (double)point.y);
    return point.x >= 0 && point.y >= 0 && point.x < self.bounds.size.width && point.y < self.bounds.size.height;
}

// UIKit may draw more than once for one render; the first is printed.
- (void)drawRect:(CGRect)rect {
    if (self.draws++ == 0)
        showRect("drawRect", rect);
}
@end

int main(void) {
    @autoreleasepool {
        UIView *root = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 480)];
        Box *box = [[Box alloc] initWithFrame:CGRectMake(20.5f, 40, 100, 60)];
        [root addSubview:box];
        showRect("frame", box.frame);
        showRect("bounds", box.bounds);
        showPoint("center", box.center);
        box.center = CGPointMake(160, 240.25f);
        showRect("moved", box.frame);
        showPoint("converted", [box convertPoint:CGPointMake(10, 5) toView:root]);
        showRect("from root", [box convertRect:CGRectMake(120, 220, 10, 10) fromView:root]);

        box.transform = CGAffineTransformMakeScale(2, 0.5f);
        CGAffineTransform t = box.transform;
        printf("transform %.2f %.2f %.2f %.2f %.2f %.2f\n", (double)t.a, (double)t.b, (double)t.c, (double)t.d,
               (double)t.tx, (double)t.ty);
        showRect("scaled frame", box.frame);
        box.transform = CGAffineTransformMakeScale(1, 1);

        [box sizeToFit];
        showRect("sized", box.frame);
        CGSize fits = [box sizeThatFits:CGSizeMake(30, 7.5f)];
        printf("fits %.2f %.2f\n", (double)fits.width, (double)fits.height);

        box.frame = CGRectMake(10, 10, 50, 50);
        UIView *hit = [root hitTest:CGPointMake(30, 20) withEvent:nil];
        printf("hit box %d\n", hit == box);

        box.alpha = 0.25f;
        box.layer.cornerRadius = 6.5f;
        box.layer.borderWidth = 1.5f;
        printf("alpha %.2f corner %.2f border %.2f opacity %.2f\n", (double)box.alpha, (double)box.layer.cornerRadius,
               (double)box.layer.borderWidth, (double)box.layer.opacity);
        showPoint("position", box.layer.position);
        showRect("layer bounds", box.layer.bounds);

        UIColor *color = [UIColor colorWithRed:1 green:0.5f blue:0.25f alpha:0.75f];
        CGFloat r = 0, g = 0, b = 0, a = 0;
        BOOL rgb = [color getRed:&r green:&g blue:&b alpha:&a];
        printf("color %d %.3f %.3f %.3f %.3f\n", rgb, (double)r, (double)g, (double)b, (double)a);
        CGFloat white = 0, alpha = 0;
        BOOL gray = [[UIColor colorWithWhite:0.4f alpha:1] getWhite:&white alpha:&alpha];
        printf("white %d %.3f %.3f\n", gray, (double)white, (double)alpha);
        [[color colorWithAlphaComponent:0.5f] getRed:&r green:&g blue:&b alpha:&a];
        printf("faded %.3f %.3f %.3f %.3f\n", (double)r, (double)g, (double)b, (double)a);

        UIBezierPath *rounded = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(5, 6, 30, 20) cornerRadius:4];
        showRect("rounded", rounded.bounds);
        UIBezierPath *oval = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(-10, 0, 20, 10)];
        [oval applyTransform:CGAffineTransformMakeScale(3, 2)];
        showRect("oval", oval.bounds);

        UIGraphicsBeginImageContextWithOptions(CGSizeMake(50, 50), NO, 1);
        [box.layer renderInContext:UIGraphicsGetCurrentContext()];
        UIGraphicsEndImageContext();
        printf("drawn %d\n", box.draws > 0);
    }
    return 0;
}
