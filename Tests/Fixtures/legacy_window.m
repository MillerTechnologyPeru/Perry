// A 32-bit Mac application's whole path to the screen: NSApplication's run
// loop, a delegate from the old ABI, a window, and a view's -drawRect:.
#include "darwin.h"

typedef struct objc_class *Class;
typedef struct objc_selector *SEL;
typedef signed char BOOL;
typedef float CGFloat;
typedef struct { CGFloat x, y; } NSPoint;
typedef struct { CGFloat width, height; } NSSize;
typedef struct { NSPoint origin; NSSize size; } NSRect;

void NSRectFill(NSRect rect);
void exit(int);

@interface NSObject { Class isa; }
+ (id)alloc;
- (id)init;
- (void)release;
- (void)performSelector:(SEL)selector withObject:(id)object afterDelay:(double)delay;
@end

@interface NSAutoreleasePool : NSObject
@end

@interface NSColor : NSObject
+ (NSColor *)colorWithCalibratedRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha;
- (void)set;
@end

@interface NSView : NSObject
- (id)initWithFrame:(NSRect)frame;
- (NSRect)bounds;
- (id)window;
@end

@interface NSWindow : NSObject
- (id)initWithContentRect:(NSRect)rect styleMask:(unsigned)style backing:(unsigned)backing defer:(BOOL)defer;
- (void)setContentView:(NSView *)view;
- (NSView *)contentView;
- (void)setTitle:(id)title;
- (void)makeKeyAndOrderFront:(id)sender;
- (NSRect)frame;
@end

@interface NSApplication : NSObject
+ (NSApplication *)sharedApplication;
- (void)setDelegate:(id)delegate;
- (void)run;
- (void)terminate:(id)sender;
@end

@interface Canvas : NSView { int draws; }
@end

@implementation Canvas
- (void)drawRect:(NSRect)rect {
    if (draws++) return;
    [[NSColor colorWithCalibratedRed:0.5 green:0.25 blue:1 alpha:1] set];
    NSRectFill([self bounds]);
    NSRect bounds = [self bounds];
    printf("drew %.0f %.0f in window %d\n", bounds.size.width, bounds.size.height, [self window] != (id)0);
    fflush((void *)0);
    // Later, so the frame this draw is part of reaches the window.
    [[NSApplication sharedApplication] performSelector:@selector(terminate:) withObject:(id)0 afterDelay:1.5];
}
@end

@interface Delegate : NSObject { id window; }
@end

@implementation Delegate
- (void)giveUp { printf("no draw\n"); exit(3); }
- (void)applicationDidFinishLaunching:(id)note {
    NSRect content = { { 40, 50 }, { 200, 100 } };
    window = [[NSWindow alloc] initWithContentRect:content styleMask:15 backing:2 defer:0];
    Canvas *canvas = [[Canvas alloc] initWithFrame:content];
    [window setContentView:canvas];
    NSRect bounds = [[window contentView] bounds];
    printf("launched content %.0f %.0f\n", bounds.size.width, bounds.size.height);
    [window makeKeyAndOrderFront:(id)0];
    [self performSelector:@selector(giveUp) withObject:(id)0 afterDelay:15.0];
}
@end

int main(void) {
    id pool = [[NSAutoreleasePool alloc] init];
    NSApplication *app = [NSApplication sharedApplication];
    [app setDelegate:[[Delegate alloc] init]];
    [app run];
    printf("run returned\n");
    [pool release];
    return 1;
}
