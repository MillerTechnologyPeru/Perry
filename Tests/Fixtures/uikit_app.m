// A UIKit app as iOS 5 and 6 apps are written: UIApplicationMain makes the
// delegate, which makes the window and its root view controller; the
// controller builds a label, a button and a colored view, and a tap on the
// button reaches its action. Without arguments it reports what it laid out,
// sends the button's action itself and exits; with "stay" it keeps running,
// to be looked at and tapped. There is no armv7 SDK, so UIKit is declared
// here.
#include "darwin.h"
typedef struct objc_class *Class;
typedef struct objc_selector *SEL;
typedef signed char BOOL;
#define nil ((id)0)
#define YES ((BOOL)1)
#define NO ((BOOL)0)
#if __LP64__
typedef double CGFloat;
typedef long NSInteger;
typedef unsigned long NSUInteger;
#else
typedef float CGFloat;
typedef int NSInteger;
typedef unsigned int NSUInteger;
#endif
typedef struct CGPoint { CGFloat x, y; } CGPoint;
typedef struct CGSize { CGFloat width, height; } CGSize;
typedef struct CGRect { CGPoint origin; CGSize size; } CGRect;
static inline CGRect CGRectMake(CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
    CGRect r = { { x, y }, { w, h } };
    return r;
}

@class NSString, NSDictionary, UIColor, UIFont, UIView, UIWindow, UIViewController, UIApplication, UIEvent;

__attribute__((objc_root_class))
@interface NSObject { Class isa; }
+ (instancetype)alloc;
- (instancetype)init;
+ (Class)class;
- (Class)class;
@end

@interface NSString : NSObject
+ (instancetype)stringWithFormat:(NSString *)format, ...;
- (const char *)UTF8String;
@end

@interface NSTimer : NSObject
+ (NSTimer *)scheduledTimerWithTimeInterval:(double)seconds target:(id)target selector:(SEL)selector
                                   userInfo:(id)userInfo repeats:(BOOL)repeats;
@end

NSString *NSStringFromClass(Class cls);

@interface UIColor : NSObject
+ (UIColor *)colorWithRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha;
+ (UIColor *)whiteColor;
+ (UIColor *)blackColor;
@end

@interface UIFont : NSObject
+ (UIFont *)boldSystemFontOfSize:(CGFloat)size;
+ (UIFont *)systemFontOfSize:(CGFloat)size;
@end

@interface UIResponder : NSObject
@end

@interface UIScreen : NSObject
+ (UIScreen *)mainScreen;
@property (readonly) CGRect bounds;
@property (readonly) CGFloat scale;
@end

@interface UIView : UIResponder
- (instancetype)initWithFrame:(CGRect)frame;
@property CGRect frame;
@property CGRect bounds;
@property (copy) UIColor *backgroundColor;
@property NSUInteger autoresizingMask;
@property (readonly) UIView *superview;
@property (readonly) UIWindow *window;
- (void)addSubview:(UIView *)view;
@end

@interface UIWindow : UIView
@property (retain) UIViewController *rootViewController;
@property (readonly, getter=isKeyWindow) BOOL keyWindow;
- (void)makeKeyAndVisible;
@end

@interface UILabel : UIView
@property (copy) NSString *text;
@property (retain) UIColor *textColor;
@property (retain) UIFont *font;
@property NSInteger textAlignment;
@end

@interface UIControl : UIView
- (void)addTarget:(id)target action:(SEL)action forControlEvents:(NSUInteger)events;
- (void)sendActionsForControlEvents:(NSUInteger)events;
@end

@interface UIButton : UIControl
+ (instancetype)buttonWithType:(NSInteger)type;
- (void)setTitle:(NSString *)title forState:(NSUInteger)state;
- (void)setTitleColor:(UIColor *)color forState:(NSUInteger)state;
@property (readonly) UILabel *titleLabel;
@end

@interface UIViewController : UIResponder
@property (retain) UIView *view;
- (void)viewDidLoad;
- (void)viewDidAppear:(BOOL)animated;
@end

@interface UIApplication : UIResponder
+ (UIApplication *)sharedApplication;
@property (assign) id delegate;
@end

int UIApplicationMain(int argc, char *argv[], NSString *principal, NSString *delegate);

enum { UIControlEventTouchUpInside = 1 << 6, UIViewAutoresizingFlexibleWidth = 1 << 1 };

static BOOL stay;

static void showRect(const char *label, CGRect r) {
    printf("%s %.1f %.1f %.1f %.1f\n", label, (double)r.origin.x, (double)r.origin.y, (double)r.size.width,
           (double)r.size.height);
    fflush(stdout);
}

@interface CounterController : UIViewController
@property (nonatomic, retain) UILabel *label;
@property (nonatomic, retain) UIButton *button;
@property (nonatomic) int taps;
@end

@implementation CounterController

- (void)viewDidLoad {
    [super viewDidLoad];
    CGRect bounds = self.view.bounds;
    self.view.backgroundColor = [UIColor colorWithRed:0.12f green:0.16f blue:0.24f alpha:1];

    UIView *band = [[UIView alloc] initWithFrame:CGRectMake(0, 0, bounds.size.width, 64)];
    band.backgroundColor = [UIColor colorWithRed:0.95f green:0.45f blue:0.15f alpha:1];
    band.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:band];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, bounds.size.width, 44)];
    title.text = @"Perry armv7";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont boldSystemFontOfSize:20];
    title.textAlignment = 1;
    title.backgroundColor = nil;
    title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [band addSubview:title];

    self.label = [[UILabel alloc] initWithFrame:CGRectMake(20, 120, bounds.size.width - 40, 40)];
    self.label.text = @"Taps: 0";
    self.label.textColor = [UIColor whiteColor];
    self.label.font = [UIFont systemFontOfSize:28];
    self.label.textAlignment = 1;
    self.label.backgroundColor = nil;
    [self.view addSubview:self.label];

    self.button = [UIButton buttonWithType:0];
    self.button.frame = CGRectMake(60, 200, bounds.size.width - 120, 56);
    self.button.backgroundColor = [UIColor colorWithRed:0.2f green:0.6f blue:0.9f alpha:1];
    [self.button setTitle:@"Tap me" forState:0];
    [self.button setTitleColor:[UIColor whiteColor] forState:0];
    [self.button addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.button];

    printf("viewDidLoad\n");
    showRect("view", bounds);
    showRect("label", self.label.frame);
    showRect("button", self.button.frame);
}

- (void)tapped:(id)sender {
    self.taps++;
    self.label.text = [NSString stringWithFormat:@"Taps: %d", self.taps];
    printf("tapped %d sender is button %d: %s\n", self.taps, sender == self.button, self.label.text.UTF8String);
    fflush(stdout);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    printf("viewDidAppear in window %d\n", self.view.window != nil);
    fflush(stdout);
    if (!stay)
        [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(finish:) userInfo:nil repeats:NO];
}

- (void)finish:(NSTimer *)timer {
    [self.button sendActionsForControlEvents:UIControlEventTouchUpInside];
    [self.button sendActionsForControlEvents:UIControlEventTouchUpInside];
    printf("done\n");
    exit(0);
}

@end

@interface AppDelegate : UIResponder
@property (nonatomic, retain) UIWindow *window;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    printf("didFinishLaunching: delegate %s, is application's %d\n", NSStringFromClass([self class]).UTF8String,
           application.delegate == self);
    CGRect screen = [UIScreen mainScreen].bounds;
    printf("screen has size %d\n", screen.size.width > 0 && screen.size.height > 0);
    self.window = [[UIWindow alloc] initWithFrame:screen];
    self.window.rootViewController = [[CounterController alloc] init];
    [self.window makeKeyAndVisible];
    printf("window is key %d\n", self.window.keyWindow);
    fflush(stdout);
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        stay = argc > 1 && strcmp(argv[1], "stay") == 0;
        printf("main\n");
        fflush(stdout);
        return UIApplicationMain(argc, argv, nil, @"AppDelegate");
    }
}
