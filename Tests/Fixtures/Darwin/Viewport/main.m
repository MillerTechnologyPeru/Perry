// Views, windows and view controllers without drawing: geometry, the view
// hierarchy and its callbacks, view loading, the key window and the
// responder chain from a view up to the application.

#import <UIKit/UIKit.h>
#include <stdio.h>
#include <stdlib.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static NSString *name(id object) {
    if (!object) return @"nil";
    NSString *label = [object isKindOfClass:UIView.class] ? [object accessibilityIdentifier] : nil;
    return label ?: NSStringFromClass([object class]);
}

@interface Box : UIView
@end

@implementation Box

- (void)willMoveToSuperview:(UIView *)superview {
    say([NSString stringWithFormat:@"%@ will move to superview %@", name(self), name(superview)]);
}

- (void)didMoveToSuperview {
    say([NSString stringWithFormat:@"%@ did move to superview %@", name(self), name(self.superview)]);
}

- (void)willMoveToWindow:(UIWindow *)window {
    say([NSString stringWithFormat:@"%@ will move to window %@", name(self), window ? @"window" : @"nil"]);
}

- (void)didMoveToWindow {
    say([NSString stringWithFormat:@"%@ did move to window %@", name(self), self.window ? @"window" : @"nil"]);
}

- (void)didAddSubview:(UIView *)subview {
    say([NSString stringWithFormat:@"%@ did add subview %@", name(self), name(subview)]);
}

- (void)willRemoveSubview:(UIView *)subview {
    say([NSString stringWithFormat:@"%@ will remove subview %@", name(self), name(subview)]);
}

@end

@interface Controller : UIViewController
@end

@implementation Controller

- (void)loadView {
    say([NSString stringWithFormat:@"loadView, view loaded %d", self.isViewLoaded]);
    Box *root = [[Box alloc] initWithFrame:CGRectMake(0, 0, 320, 480)];
    root.accessibilityIdentifier = @"root";
    self.view = root;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    say([NSString stringWithFormat:@"viewDidLoad: view %@, loaded %d", name(self.view), self.isViewLoaded]);
}

@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation AppDelegate
@end

@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UIWindowScene *windowScene = (UIWindowScene *)scene;

    // Geometry.
    UIView *plain = [[UIView alloc] initWithFrame:CGRectMake(10, 20, 100, 50)];
    say([NSString stringWithFormat:@"frame %@ bounds %@ center %@", NSStringFromCGRect(plain.frame),
         NSStringFromCGRect(plain.bounds), NSStringFromCGPoint(plain.center)]);
    plain.center = CGPointMake(100, 100);
    say([NSString stringWithFormat:@"moved: frame %@", NSStringFromCGRect(plain.frame)]);
    plain.bounds = CGRectMake(5, 5, 40, 40);
    say([NSString stringWithFormat:@"resized: frame %@ bounds %@", NSStringFromCGRect(plain.frame),
         NSStringFromCGRect(plain.bounds)]);
    UIView *empty = [[UIView alloc] init];
    say([NSString stringWithFormat:@"init: frame %@, hidden %d, alpha %.1f, tag %ld, interaction %d",
         NSStringFromCGRect(empty.frame), empty.hidden, empty.alpha, (long)empty.tag,
         empty.userInteractionEnabled]);

    // The hierarchy and its callbacks.
    Box *outer = [[Box alloc] initWithFrame:CGRectMake(0, 0, 200, 200)];
    outer.accessibilityIdentifier = @"outer";
    Box *inner = [[Box alloc] initWithFrame:CGRectMake(30, 40, 50, 50)];
    inner.accessibilityIdentifier = @"inner";
    inner.tag = 7;
    [outer addSubview:inner];
    say([NSString stringWithFormat:@"subviews %lu, superview %@, viewWithTag %@, descendant %d",
         (unsigned long)outer.subviews.count, name(inner.superview), name([outer viewWithTag:7]),
         [inner isDescendantOfView:outer]]);
    CGPoint converted = [inner convertPoint:CGPointMake(5, 5) toView:outer];
    say([NSString stringWithFormat:@"converted %@", NSStringFromCGPoint(converted)]);
    Box *sibling = [[Box alloc] initWithFrame:CGRectZero];
    sibling.accessibilityIdentifier = @"sibling";
    [outer insertSubview:sibling belowSubview:inner];
    say([NSString stringWithFormat:@"order %@ %@", name(outer.subviews[0]), name(outer.subviews[1])]);
    [sibling removeFromSuperview];
    say([NSString stringWithFormat:@"after removal %lu", (unsigned long)outer.subviews.count]);

    // A window with a root view controller.
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:windowScene];
    self.window = window;
    say([NSString stringWithFormat:@"window: scene matches %d, hidden %d, key %d, windows %lu",
         window.windowScene == windowScene, window.hidden, window.isKeyWindow,
         (unsigned long)windowScene.windows.count]);
    Controller *controller = [[Controller alloc] init];
    say([NSString stringWithFormat:@"controller view loaded %d", controller.isViewLoaded]);
    window.rootViewController = controller;
    say([NSString stringWithFormat:@"root set: view loaded %d, root view in window %d",
         controller.isViewLoaded, controller.view.window == window]);
    [controller.view addSubview:outer];
    [window makeKeyAndVisible];
    say([NSString stringWithFormat:@"visible: hidden %d, key %d, inner window %d",
         window.hidden, window.isKeyWindow, inner.window == window]);

    // The responder chain from the innermost view.
    NSMutableArray *chain = [NSMutableArray array];
    for (UIResponder *responder = inner; responder; responder = responder.nextResponder) {
        [chain addObject:name(responder)];
    }
    say([@"chain " stringByAppendingString:[chain componentsJoinedByString:@" > "]]);

    [NSTimer scheduledTimerWithTimeInterval:0.2 repeats:NO block:^(NSTimer *timer) {
        [outer removeFromSuperview];
        say(@"done");
        exit(0);
    }];
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
    }
}
