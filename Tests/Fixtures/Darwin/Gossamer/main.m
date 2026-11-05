// WKWebView over a real web engine: a page loaded from HTML, the
// navigation delegate's calls in order, the page's title and URL, scripts'
// values as Foundation's objects and a script's exception, layout read
// back from the page, and a snapshot whose pixels show the page's
// background. Pixels are checked against the page's color within a
// tolerance.

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#include <stdio.h>
#include <stdlib.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

/// RGBA (premultiplied) at x, y in pixels from the image's top left.
static uint32_t pixel(UIImage *image, int x, int y) {
    CGImageRef cg = image.CGImage;
    size_t width = CGImageGetWidth(cg), height = CGImageGetHeight(cg);
    uint8_t *buffer = calloc(width * height, 4);
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(buffer, width, height, 8, width * 4, rgb,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), cg);
    uint8_t *p = buffer + ((size_t)y * width + (size_t)x) * 4;
    uint32_t value = (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3];
    CGContextRelease(context);
    CGColorSpaceRelease(rgb);
    free(buffer);
    return value;
}

static BOOL near(uint32_t value, uint32_t expected) {
    for (int shift = 0; shift < 32; shift += 8) {
        int a = (value >> shift) & 0xff, b = (expected >> shift) & 0xff;
        if (abs(a - b) > 8) return NO;
    }
    return YES;
}

static NSString *const page =
    @"<!DOCTYPE html><html><head><title>Gossamer page</title>"
    @"<meta name=viewport content='width=device-width'>"
    @"<style>body { margin: 8px; background: rgb(255, 0, 0); } #box { height: 50px; }</style></head>"
    @"<body><div id=box>Hello</div></body></html>";

@interface Controller : NSObject <WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) NSArray<NSString *> *scripts;
@end

@implementation Controller

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    say(@"did start provisional navigation");
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
    say(@"did commit navigation");
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    say(@"did finish navigation");
    say([NSString stringWithFormat:@"URL %@", webView.URL.absoluteString]);
    say([NSString stringWithFormat:@"loading %d, progress %.1f", webView.isLoading, webView.estimatedProgress]);
    self.scripts = @[
        @"1 + 2",
        @"'gos' + 'samer'",
        @"true",
        @"[1, 'two', false]",
        @"({ name: 'web', size: 2 })",
        @"null",
        @"undefined",
        @"document.title",
        @"document.getElementById('box').offsetWidth",
        @"document.getElementById('box').offsetHeight",
        @"getComputedStyle(document.body).backgroundColor",
        @"throw new Error('no')",
    ];
    [self runScript:0];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    say([NSString stringWithFormat:@"did fail navigation %@ %ld", error.domain, (long)error.code]);
    exit(1);
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    say([NSString stringWithFormat:@"did fail provisional navigation %@ %ld", error.domain, (long)error.code]);
    exit(1);
}

- (void)runScript:(NSUInteger)index {
    if (index == self.scripts.count) {
        [self snapshot];
        return;
    }
    NSString *script = self.scripts[index];
    [self.webView evaluateJavaScript:script completionHandler:^(id value, NSError *error) {
        if (error) {
            say([NSString stringWithFormat:@"%@ -> error %@ %ld", script, error.domain, (long)error.code]);
        } else {
            say([NSString stringWithFormat:@"%@ -> %@", script, value]);
        }
        [self runScript:index + 1];
    }];
}

- (void)snapshot {
    [self.webView takeSnapshotWithConfiguration:nil completionHandler:^(UIImage *image, NSError *error) {
        say([NSString stringWithFormat:@"snapshot %@, error %@", NSStringFromCGSize(image.size), error ? error.domain : @"none"]);
        CGFloat scale = image.scale;
        say([NSString stringWithFormat:@"snapshot center is red %d",
             near(pixel(image, (int)(160 * scale), (int)(200 * scale)), 0xff0000ff)]);
        exit(0);
    }];
}

@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation AppDelegate
@end

@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) Controller *controller;
@end

@implementation SceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.frame = CGRectMake(0, 0, 320, 480);
    UIViewController *root = [[UIViewController alloc] init];
    self.window.rootViewController = root;
    [self.window makeKeyAndVisible];

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    WKWebView *webView = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, 320, 400) configuration:configuration];
    [root.view addSubview:webView];
    say([NSString stringWithFormat:@"before load: title %@, URL %@, loading %d",
         webView.title ?: @"nil", webView.URL ?: @"nil", webView.isLoading]);

    self.controller = [[Controller alloc] init];
    self.controller.webView = webView;
    webView.navigationDelegate = self.controller;
    WKNavigation *navigation = [webView loadHTMLString:page baseURL:nil];
    say([NSString stringWithFormat:@"load returned a navigation %d", navigation != nil]);
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
    }
}
