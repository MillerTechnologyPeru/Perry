// UIWebView over a real web engine: a page loaded from HTML, the
// delegate's calls in order (asked first, then started and finished),
// scripts run to completion with their values as strings, layout read back
// from the page, and a link the delegate refuses. UIWebView is unavailable
// on Mac Catalyst, so this is recorded on the iOS Simulator.

#import <UIKit/UIKit.h>
#include <stdio.h>
#include <stdlib.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static NSString *const page =
    @"<!DOCTYPE html><html><head><title>Cobweb page</title>"
    @"<style>body { margin: 8px; } #box { height: 40px; }</style></head>"
    @"<body><div id=box>Hello</div><a id=link href='perry-fixture://refused'>link</a></body></html>";

@interface Delegate : NSObject <UIWebViewDelegate>
@property (nonatomic) BOOL finished;
@end

@implementation Delegate

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request
 navigationType:(UIWebViewNavigationType)navigationType {
    BOOL allowed = ![request.URL.scheme isEqualToString:@"perry-fixture"];
    say([NSString stringWithFormat:@"should start %@, type %ld, a request %d: %@", request.URL.absoluteString,
         (long)navigationType, [request isKindOfClass:NSURLRequest.class], allowed ? @"yes" : @"no"]);
    return allowed;
}

- (void)webViewDidStartLoad:(UIWebView *)webView {
    say(@"did start load");
}

- (void)webViewDidFinishLoad:(UIWebView *)webView {
    say([NSString stringWithFormat:@"did finish load: loading %d, request %@", webView.isLoading,
         webView.request.URL.absoluteString]);
    self.finished = YES;
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
    say([NSString stringWithFormat:@"did fail load %@ %ld", error.domain, (long)error.code]);
}

@end

static void runUntil(BOOL (^done)(void)) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:20];
    while (!done() && [limit timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        UIWebView *webView = [[UIWebView alloc] initWithFrame:CGRectMake(0, 0, 320, 400)];
        say([NSString stringWithFormat:@"made: loading %d, back %d, forward %d, request %@, scales %d",
             webView.isLoading, webView.canGoBack, webView.canGoForward, webView.request ?: @"nil", webView.scalesPageToFit]);
        Delegate *delegate = [[Delegate alloc] init];
        webView.delegate = delegate;
        [webView loadHTMLString:page baseURL:nil];
        say(@"load asked");
        runUntil(^{ return delegate.finished; });

        for (NSString *script in @[
            @"1 + 2",
            @"'cob' + 'web'",
            @"true",
            @"[1, 'two', false]",
            @"({ name: 'web' })",
            @"null",
            @"undefined",
            @"document.title",
            @"document.getElementById('box').offsetWidth",
            @"document.getElementById('box').offsetHeight",
            @"throw new Error('no')",
        ]) {
            NSString *value = [webView stringByEvaluatingJavaScriptFromString:script];
            say([NSString stringWithFormat:@"%@ -> \"%@\"", script, value ?: @"(nil)"]);
        }

        [webView stringByEvaluatingJavaScriptFromString:@"document.getElementById('link').click()"];
        __block BOOL waited = NO;
        [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:NO block:^(NSTimer *timer) { waited = YES; }];
        runUntil(^{ return waited; });
        say([NSString stringWithFormat:@"after refused link: title %@, back %d",
             [webView stringByEvaluatingJavaScriptFromString:@"document.title"], webView.canGoBack]);
        return 0;
    }
}
