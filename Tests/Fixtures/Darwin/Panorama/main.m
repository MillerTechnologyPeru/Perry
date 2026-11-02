// Scroll views without touches: the content offset as the bounds' origin,
// the delegate's callbacks, scrolling a rectangle into view, insets and
// their automatic adjustment under a navigation bar, hit testing and
// drawing through the offset. Geometry under the bar is checked against
// the bar, so the output does not depend on the device's screen.

#import <UIKit/UIKit.h>
#include <stdio.h>
#include <stdlib.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static NSString *point(CGPoint p) { return NSStringFromCGPoint(p); }

@interface Watcher : NSObject <UIScrollViewDelegate>
@property (nonatomic) NSInteger scrolls;
@end

@implementation Watcher
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    self.scrolls++;
}
@end

@interface Content : UIViewController
@property (nonatomic, strong) UIScrollView *scrollView;
@end

@implementation Content
- (void)loadView {
    self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, 300, 600)];
    self.scrollView.contentSize = CGSizeMake(300, 2000);
    self.view = self.scrollView;
}
@end

@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UINavigationController *navigation;
@property (nonatomic, strong) Content *content;
@end

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    // Defaults.
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, 100, 200)];
    say([NSString stringWithFormat:@"defaults: offset %@, size %@, inset %@, adjusted %@, behavior %ld",
         point(scroll.contentOffset), NSStringFromCGSize(scroll.contentSize), NSStringFromUIEdgeInsets(scroll.contentInset),
         NSStringFromUIEdgeInsets(scroll.adjustedContentInset), (long)scroll.contentInsetAdjustmentBehavior]);
    say([NSString stringWithFormat:@"  clips %d, scroll enabled %d, paging %d, bounces %d, always bounce %d %d, lock %d, to top %d",
         scroll.clipsToBounds, scroll.scrollEnabled, scroll.pagingEnabled, scroll.bounces, scroll.alwaysBounceVertical,
         scroll.alwaysBounceHorizontal, scroll.directionalLockEnabled, scroll.scrollsToTop]);
    say([NSString stringWithFormat:@"  indicators %d %d, deceleration %.3f fast %.3f, zoom %.0f %.0f %.0f, pan %d, tracking %d %d %d",
         scroll.showsVerticalScrollIndicator, scroll.showsHorizontalScrollIndicator, scroll.decelerationRate,
         UIScrollViewDecelerationRateFast, scroll.zoomScale, scroll.minimumZoomScale, scroll.maximumZoomScale,
         scroll.panGestureRecognizer != nil, scroll.tracking, scroll.dragging, scroll.decelerating]);

    // The offset is the bounds' origin.
    Watcher *watcher = [[Watcher alloc] init];
    scroll.delegate = watcher;
    UIView *marker = [[UIView alloc] initWithFrame:CGRectMake(10, 300, 20, 20)];
    [scroll addSubview:marker];
    scroll.contentSize = CGSizeMake(100, 1000);
    say([NSString stringWithFormat:@"content size: scrolls %ld", (long)watcher.scrolls]);
    scroll.contentOffset = CGPointMake(0, 250);
    say([NSString stringWithFormat:@"offset: bounds %@, scrolls %ld, marker in scroll view's superview space %@",
         NSStringFromCGRect(scroll.bounds), (long)watcher.scrolls, point([scroll convertPoint:marker.frame.origin toView:nil])]);
    [scroll setContentOffset:CGPointMake(0, 250) animated:NO];
    say([NSString stringWithFormat:@"same offset: scrolls %ld", (long)watcher.scrolls]);
    [scroll setContentOffset:CGPointMake(0, 5000) animated:NO];
    say([NSString stringWithFormat:@"past the end: offset %@, scrolls %ld", point(scroll.contentOffset), (long)watcher.scrolls]);
    scroll.bounds = CGRectMake(0, 40, 100, 200);
    say([NSString stringWithFormat:@"bounds: offset %@, scrolls %ld", point(scroll.contentOffset), (long)watcher.scrolls]);
    scroll.frame = CGRectMake(5, 5, 100, 150);
    say([NSString stringWithFormat:@"frame: offset %@, bounds %@, scrolls %ld", point(scroll.contentOffset),
         NSStringFromCGRect(scroll.bounds), (long)watcher.scrolls]);

    // Scrolling a rectangle into view: the least movement that shows it.
    scroll.frame = CGRectMake(0, 0, 100, 200);
    scroll.contentOffset = CGPointZero;
    [scroll scrollRectToVisible:CGRectMake(0, 500, 10, 50) animated:NO];
    say([NSString stringWithFormat:@"to visible below: %@", point(scroll.contentOffset)]);
    [scroll scrollRectToVisible:CGRectMake(0, 100, 10, 10) animated:NO];
    say([NSString stringWithFormat:@"to visible above: %@", point(scroll.contentOffset)]);
    [scroll scrollRectToVisible:CGRectMake(0, 200, 10, 10) animated:NO];
    say([NSString stringWithFormat:@"already visible: %@", point(scroll.contentOffset)]);
    [scroll scrollRectToVisible:CGRectMake(0, 980, 10, 100) animated:NO];
    say([NSString stringWithFormat:@"past the end: %@", point(scroll.contentOffset)]);

    // Insets.
    scroll.contentInset = UIEdgeInsetsMake(20, 0, 30, 0);
    say([NSString stringWithFormat:@"inset: offset %@, adjusted %@, scrolls %ld", point(scroll.contentOffset),
         NSStringFromUIEdgeInsets(scroll.adjustedContentInset), (long)watcher.scrolls]);
    scroll.contentOffset = CGPointMake(0, -20);
    [scroll scrollRectToVisible:CGRectMake(0, 0, 10, 10) animated:NO];
    say([NSString stringWithFormat:@"top with inset: %@", point(scroll.contentOffset)]);

    // Hit testing and drawing through the offset.
    UIScrollView *page = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, 50, 50)];
    page.backgroundColor = UIColor.whiteColor;
    page.contentSize = CGSizeMake(50, 200);
    UIView *red = [[UIView alloc] initWithFrame:CGRectMake(0, 100, 50, 50)];
    red.backgroundColor = UIColor.redColor;
    [page addSubview:red];
    page.contentOffset = CGPointMake(0, 90);
    UIView *hit = [page hitTest:CGPointMake(25, 105) withEvent:nil];
    say([NSString stringWithFormat:@"hit: red at content point %d, scroll view above it %d", hit == red,
         [page hitTest:CGPointMake(25, 95) withEvent:nil] == page]);
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1;
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(50, 50) format:format]
                      imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [page drawViewHierarchyInRect:CGRectMake(0, 0, 50, 50) afterScreenUpdates:YES];
    }];
    CGImageRef cg = image.CGImage;
    uint8_t pixels[50 * 50 * 4];
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextRef bitmap = CGBitmapContextCreate(pixels, 50, 50, 8, 200, rgb, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGContextDrawImage(bitmap, CGRectMake(0, 0, 50, 50), cg);
    say([NSString stringWithFormat:@"drawn: white above %d, red below %d", pixels[(5 * 50 + 25) * 4 + 1] == 255,
         pixels[(20 * 50 + 25) * 4] == 255 && pixels[(20 * 50 + 25) * 4 + 1] == 0]);
    CGContextRelease(bitmap);
    CGColorSpaceRelease(rgb);

    // A scroll view as a controller's view under a navigation bar.
    self.content = [[Content alloc] init];
    self.navigation = [[UINavigationController alloc] initWithRootViewController:self.content];
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = self.navigation;
    [self.window makeKeyAndVisible];
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
    [NSTimer scheduledTimerWithTimeInterval:0.3 repeats:NO block:^(NSTimer *timer) {
        UIScrollView *scroll = self.content.scrollView;
        UINavigationBar *bar = self.navigation.navigationBar;
        UIEdgeInsets adjusted = scroll.adjustedContentInset;
        say([NSString stringWithFormat:@"under bar: inset %@, adjusted top at bar %d, bottom is window's %d, offset at top %d, safe top %d",
             NSStringFromUIEdgeInsets(scroll.contentInset), adjusted.top == CGRectGetMaxY(bar.frame),
             adjusted.bottom == self.window.safeAreaInsets.bottom, scroll.contentOffset.y == -adjusted.top,
             scroll.safeAreaInsets.top == adjusted.top]);
        scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        say([NSString stringWithFormat:@"never: adjusted %@, offset unchanged %d", NSStringFromUIEdgeInsets(scroll.adjustedContentInset),
             scroll.contentOffset.y == -adjusted.top]);
        scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
        [scroll setContentOffset:CGPointMake(0, 2000) animated:NO];
        [scroll scrollRectToVisible:CGRectMake(0, 0, 10, 10) animated:NO];
        say([NSString stringWithFormat:@"to top under bar: at top %d", scroll.contentOffset.y == -adjusted.top]);
        say(@"done");
        exit(0);
    }];
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, nil);
    }
}
