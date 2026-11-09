// AppKit as 32-bit Mac programs use it: a subclass of NSView with its own
// instance variables at fixed offsets, and CGFloat a float, in structures
// passed on the stack and returned through a pointer. No display is needed.
#include "darwin.h"

typedef struct objc_class *Class;
typedef struct objc_selector *SEL;
typedef signed char BOOL;
typedef float CGFloat;
typedef struct { CGFloat x, y; } NSPoint;
typedef struct { CGFloat width, height; } NSSize;
typedef struct { NSPoint origin; NSSize size; } NSRect;

NSRect NSInsetRect(NSRect rect, CGFloat dx, CGFloat dy);
BOOL NSPointInRect(NSPoint point, NSRect rect);

@interface NSObject { Class isa; }
+ (id)alloc;
- (id)init;
- (void)release;
@end

@interface NSAutoreleasePool : NSObject
@end

@interface NSView : NSObject
- (id)initWithFrame:(NSRect)frame;
- (NSRect)frame;
- (NSRect)bounds;
- (void)setFrame:(NSRect)frame;
- (void)setFrameSize:(NSSize)size;
- (void)addSubview:(NSView *)view;
- (NSView *)superview;
- (BOOL)isFlipped;
- (NSPoint)convertPoint:(NSPoint)point toView:(NSView *)view;
@end

@interface NSColor : NSObject
+ (NSColor *)colorWithCalibratedRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha;
- (CGFloat)redComponent;
- (CGFloat)alphaComponent;
@end

@interface Panel : NSView {
@public
    int tag;
    double scale;
    NSRect remembered;
}
@end

@implementation Panel
- (id)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        tag = 77;
        scale = 1.5;
        remembered = frame;
    }
    return self;
}
- (BOOL)isFlipped { return 1; }
- (NSRect)frame {
    NSRect rect = [super frame];
    rect.size.width += 1000;
    return rect;
}
@end

static void show(const char *label, NSRect r) {
    printf("%s %.1f %.1f %.1f %.1f\n", label, r.origin.x, r.origin.y, r.size.width, r.size.height);
}

int main(void) {
    id pool = [[NSAutoreleasePool alloc] init];
    NSRect start = { { 10, 20 }, { 300, 200.5f } };
    Panel *panel = [[Panel alloc] initWithFrame:start];
    printf("ivars %d %.1f %.1f\n", panel->tag, panel->scale, panel->remembered.size.height);
    show("frame", [panel frame]);
    show("bounds", [panel bounds]);
    NSRect moved = { { 1, 2 }, { 30, 40 } };
    [panel setFrame:moved];
    show("moved", [panel frame]);
    NSSize size = { 50, 60.25f };
    [panel setFrameSize:size];
    show("sized", [panel frame]);

    NSRect childFrame = { { 5, 6 }, { 7, 8 } };
    NSView *child = [[NSView alloc] initWithFrame:childFrame];
    [panel addSubview:child];
    printf("tree %d flipped %d %d\n", [child superview] == panel, [panel isFlipped], [child isFlipped]);
    NSPoint origin = { 1, 1 };
    NSPoint converted = [child convertPoint:origin toView:panel];
    printf("converted %.1f %.1f\n", converted.x, converted.y);

    show("inset", NSInsetRect(start, 2.5f, 5));
    NSPoint inside = { 11, 21 };
    printf("in %d\n", NSPointInRect(inside, start));

    NSColor *color = [NSColor colorWithCalibratedRed:0.25f green:0.5f blue:0.75f alpha:0.125f];
    printf("color %.3f %.3f\n", [color redComponent], [color alphaComponent]);
    [pool release];
    return 0;
}
