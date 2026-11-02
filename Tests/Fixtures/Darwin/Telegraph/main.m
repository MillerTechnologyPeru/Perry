// NSURLSession against an HTTP server this program runs on 127.0.0.1 with
// BSD sockets: data, upload and download tasks, completion handlers and
// delegates, redirects, errors, timeouts, cancellation, cookies, requests,
// responses and configurations. Then NSURLConnection: synchronous and
// asynchronous requests, and delegates on the run loop or a queue.

#import <Foundation/Foundation.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

// MARK: - The server

static int listener;
static unsigned short port;

static void reply(int client, int status, NSString *reason, NSDictionary *headers, NSData *body) {
    NSMutableString *head = [NSMutableString stringWithFormat:@"HTTP/1.1 %d %@\r\n", status, reason];
    [head appendFormat:@"Content-Length: %lu\r\nConnection: close\r\n", (unsigned long)body.length];
    for (NSString *name in [headers.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [head appendFormat:@"%@: %@\r\n", name, headers[name]];
    }
    [head appendString:@"\r\n"];
    NSMutableData *response = [[head dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [response appendData:body];
    size_t sent = 0;
    while (sent < response.length) {
        ssize_t n = write(client, (const char *)response.bytes + sent, response.length - sent);
        if (n <= 0) break;
        sent += (size_t)n;
    }
}

static NSData *text(NSString *string) {
    return [string dataUsingEncoding:NSUTF8StringEncoding];
}

static void serve(int client) {
    NSMutableData *request = [NSMutableData data];
    char buffer[4096];
    NSRange end = NSMakeRange(NSNotFound, 0);
    while (end.location == NSNotFound) {
        ssize_t n = read(client, buffer, sizeof(buffer));
        if (n <= 0) return;
        [request appendBytes:buffer length:(NSUInteger)n];
        end = [request rangeOfData:text(@"\r\n\r\n") options:0 range:NSMakeRange(0, request.length)];
    }
    NSString *head = [[NSString alloc] initWithData:[request subdataWithRange:NSMakeRange(0, end.location)]
                                           encoding:NSUTF8StringEncoding];
    NSArray *lines = [head componentsSeparatedByString:@"\r\n"];
    NSArray *requestLine = [lines[0] componentsSeparatedByString:@" "];
    NSString *method = requestLine[0], *path = requestLine[1];
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    for (NSString *line in [lines subarrayWithRange:NSMakeRange(1, lines.count - 1)]) {
        NSRange colon = [line rangeOfString:@": "];
        if (colon.location != NSNotFound) {
            headers[[line substringToIndex:colon.location].lowercaseString] = [line substringFromIndex:NSMaxRange(colon)];
        }
    }
    NSUInteger length = (NSUInteger)[headers[@"content-length"] integerValue];
    NSUInteger bodyStart = end.location + 4;
    while (request.length < bodyStart + length) {
        ssize_t n = read(client, buffer, sizeof(buffer));
        if (n <= 0) break;
        [request appendBytes:buffer length:(NSUInteger)n];
    }
    NSData *body = [request subdataWithRange:NSMakeRange(bodyStart, MIN(length, request.length - bodyStart))];

    if ([path isEqualToString:@"/hello"]) {
        reply(client, 200, @"OK", @{@"Content-Type": @"text/plain; charset=utf-8", @"X-Custom": @"yes"},
              text(@"Hello, world"));
    } else if ([path isEqualToString:@"/echo"]) {
        reply(client, 200, @"OK", @{@"Content-Type": headers[@"content-type"] ?: @"application/octet-stream",
                                    @"X-Method": method}, body);
    } else if ([path isEqualToString:@"/json"]) {
        reply(client, 200, @"OK", @{@"Content-Type": @"application/json"},
              text(@"{\"name\":\"Perry\",\"items\":[1,2,3]}"));
    } else if ([path isEqualToString:@"/redirect"]) {
        reply(client, 302, @"Found", @{@"Location": @"/hello"}, [NSData data]);
    } else if ([path isEqualToString:@"/slow"]) {
        sleep(2);
        reply(client, 200, @"OK", @{}, text(@"late"));
    } else if ([path isEqualToString:@"/headers"]) {
        reply(client, 200, @"OK", @{@"Content-Type": @"text/plain"},
              text([NSString stringWithFormat:@"X-Request=%@", headers[@"x-request"]]));
    } else if ([path isEqualToString:@"/cookie"]) {
        reply(client, 200, @"OK", @{@"Set-Cookie": @"session=abc123; Path=/"}, text(@"set"));
    } else if ([path isEqualToString:@"/cookies"]) {
        reply(client, 200, @"OK", @{}, text(headers[@"cookie"] ?: @"none"));
    } else if ([path isEqualToString:@"/big"]) {
        NSMutableData *data = [NSMutableData dataWithLength:100000];
        memset(data.mutableBytes, 'a', data.length);
        reply(client, 200, @"OK", @{@"Content-Type": @"application/octet-stream"}, data);
    } else {
        reply(client, 404, @"Not Found", @{@"Content-Type": @"text/plain"}, text(@"not found"));
    }
}

static void *accepting(void *unused) {
    while (1) {
        int client = accept(listener, NULL, NULL);
        if (client < 0) continue;
        @autoreleasepool {
            // Each connection on its own thread, so a slow reply holds no other.
            dispatch_async(dispatch_get_global_queue(0, 0), ^{
                @autoreleasepool { serve(client); }
                close(client);
            });
        }
    }
    return NULL;
}

static void startServer(void) {
    listener = socket(AF_INET, SOCK_STREAM, 0);
    int yes = 1;
    setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    struct sockaddr_in address = {0};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = 0;
    if (bind(listener, (struct sockaddr *)&address, sizeof(address)) != 0) perror("bind");
    if (listen(listener, 16) != 0) perror("listen");
    socklen_t size = sizeof(address);
    getsockname(listener, (struct sockaddr *)&address, &size);
    port = ntohs(address.sin_port);
    say([NSString stringWithFormat:@"server: listening %d, family %d, size %u", port != 0, address.sin_family, size]);
    pthread_t thread;
    pthread_create(&thread, NULL, accepting, NULL);
}

static NSURL *url(NSString *path) {
    return [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%d%@", port, path]];
}

static NSString *string(NSData *data) {
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"(null)";
}

static NSString *describe(NSError *error) {
    return error ? [NSString stringWithFormat:@"%@ %ld", error.domain, (long)error.code] : @"nil";
}

// Runs a task to completion, waiting for its completion handler.
typedef void (^Handler)(NSData *, NSURLResponse *, NSError *);

static void fetch(NSURLSession *session, NSURLRequest *request, Handler handler) {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        handler(data, response, error);
        dispatch_semaphore_signal(done);
    }];
    [task resume];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
}

// MARK: - Delegates

@interface Watcher : NSObject <NSURLSessionDataDelegate>
@property NSUInteger received;
@property NSInteger status;
@property NSInteger redirects;
@property BOOL onQueue;
@property NSOperationQueue *queue;
@property (copy) NSString *completion;
@property dispatch_semaphore_t done;
@property dispatch_semaphore_t invalidated;
@end

@implementation Watcher
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task
didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    self.status = ((NSHTTPURLResponse *)response).statusCode;
    self.onQueue = NSOperationQueue.currentQueue == self.queue;
    completionHandler(NSURLSessionResponseAllow);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    self.received += data.length;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completionHandler {
    self.redirects++;
    completionHandler(request);
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    self.completion = [NSString stringWithFormat:@"%@ after %lu bytes", describe(error), (unsigned long)task.countOfBytesReceived];
    dispatch_semaphore_signal(self.done);
}
- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(NSError *)error {
    dispatch_semaphore_signal(self.invalidated);
}
@end

// An NSURLConnection delegate that records what it is told.
@interface Listener : NSObject <NSURLConnectionDataDelegate>
@property (readonly) NSMutableArray<NSString *> *events;
@property (readonly) NSMutableData *body;
@property BOOL done;
@property BOOL onMain;
@property NSOperationQueue *queue;
@property BOOL onQueue;
@end

@implementation Listener
- (instancetype)init {
    if ((self = [super init])) {
        _events = [NSMutableArray array];
        _body = [NSMutableData data];
    }
    return self;
}
- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request
            redirectResponse:(NSURLResponse *)response {
    [self.events addObject:[NSString stringWithFormat:@"will send %@ after %ld", request.URL.path,
                            (long)((NSHTTPURLResponse *)response).statusCode]];
    return request;
}
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    [self.events addObject:[NSString stringWithFormat:@"response %ld", (long)((NSHTTPURLResponse *)response).statusCode]];
    self.onMain = NSThread.isMainThread;
    self.onQueue = self.queue && NSOperationQueue.currentQueue == self.queue;
}
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [self.body appendData:data];
}
- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    [self.events addObject:@"finished"];
    self.done = YES;
}
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    [self.events addObject:[NSString stringWithFormat:@"failed %ld", (long)error.code]];
    self.done = YES;
}
@end

static void runUntil(BOOL (^condition)(void), NSTimeInterval limit) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:limit];
    while (!condition() && [end timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static void connections(void) {
    NSURLResponse *response = nil;
    NSError *error = nil;
    NSData *data = [NSURLConnection sendSynchronousRequest:[NSURLRequest requestWithURL:url(@"/hello")]
                                         returningResponse:&response error:&error];
    say([NSString stringWithFormat:@"sync: %ld '%@' %@, error %@", (long)((NSHTTPURLResponse *)response).statusCode,
         string(data), response.MIMEType, describe(error)]);
    response = nil;
    data = [NSURLConnection sendSynchronousRequest:[NSURLRequest requestWithURL:url(@"/missing")]
                                 returningResponse:&response error:&error];
    say([NSString stringWithFormat:@"sync missing: %ld '%@', error %@", (long)((NSHTTPURLResponse *)response).statusCode,
         string(data), describe(error)]);

    int closed = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address = {0};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    bind(closed, (struct sockaddr *)&address, sizeof(address));
    socklen_t size = sizeof(address);
    getsockname(closed, (struct sockaddr *)&address, &size);
    close(closed);
    NSURL *refused = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%d/", ntohs(address.sin_port)]];
    response = nil;
    error = nil;
    data = [NSURLConnection sendSynchronousRequest:[NSURLRequest requestWithURL:refused] returningResponse:&response error:&error];
    say([NSString stringWithFormat:@"sync refused: data %@, response %@, error %@", data, response, describe(error)]);

    NSOperationQueue *queue = [NSOperationQueue new];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [NSURLConnection sendAsynchronousRequest:[NSURLRequest requestWithURL:url(@"/json")] queue:queue
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        say([NSString stringWithFormat:@"async: %ld %@, on queue %d, error %@", (long)((NSHTTPURLResponse *)response).statusCode,
             string(data), NSOperationQueue.currentQueue == queue, describe(error)]);
        dispatch_semaphore_signal(done);
    }];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);

    __block BOOL finished = NO;
    [NSURLConnection sendAsynchronousRequest:[NSURLRequest requestWithURL:url(@"/hello")] queue:NSOperationQueue.mainQueue
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        say([NSString stringWithFormat:@"async main: '%@', main thread %d", string(data), NSThread.isMainThread]);
        finished = YES;
    }];
    runUntil(^{ return finished; }, 5);

    Listener *listener = [Listener new];
    NSURLConnection *connection = [NSURLConnection connectionWithRequest:[NSURLRequest requestWithURL:url(@"/redirect")]
                                                                delegate:listener];
    runUntil(^{ return listener.done; }, 5);
    say([NSString stringWithFormat:@"delegate: %@; '%@', main thread %d, original %@, current %@",
         [listener.events componentsJoinedByString:@"; "], string(listener.body), listener.onMain,
         connection.originalRequest.URL.path, connection.currentRequest.URL.path]);

    Listener *queued = [Listener new];
    queued.queue = [NSOperationQueue new];
    NSURLConnection *later = [[NSURLConnection alloc] initWithRequest:[NSURLRequest requestWithURL:url(@"/big")]
                                                             delegate:queued startImmediately:NO];
    [later setDelegateQueue:queued.queue];
    [later start];
    for (int i = 0; i < 500 && !queued.done; i++) usleep(10000);
    say([NSString stringWithFormat:@"delegate queue: %@; %lu bytes, on queue %d, main thread %d",
         [queued.events componentsJoinedByString:@"; "], (unsigned long)queued.body.length, queued.onQueue, queued.onMain]);

    Listener *failing = [Listener new];
    [NSURLConnection connectionWithRequest:[NSURLRequest requestWithURL:refused] delegate:failing];
    runUntil(^{ return failing.done; }, 5);
    say([NSString stringWithFormat:@"delegate failure: %@", [failing.events componentsJoinedByString:@"; "]]);

    Listener *cancelled = [Listener new];
    NSURLConnection *slow = [NSURLConnection connectionWithRequest:[NSURLRequest requestWithURL:url(@"/slow")]
                                                          delegate:cancelled];
    runUntil(^{ return NO; }, 0.1);
    [slow cancel];
    runUntil(^{ return NO; }, 0.3);
    say([NSString stringWithFormat:@"cancelled connection: %@ (%lu events)", [cancelled.events componentsJoinedByString:@"; "],
         (unsigned long)cancelled.events.count]);

    say([NSString stringWithFormat:@"can handle: %d %d %d",
         [NSURLConnection canHandleRequest:[NSURLRequest requestWithURL:url(@"/")]],
         [NSURLConnection canHandleRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/"]]],
         [NSURLConnection canHandleRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"perry-unknown://x"]]]]);
}
#pragma clang diagnostic pop

// MARK: - Tests

static void basics(void) {
    NSURLSession *session = NSURLSession.sharedSession;
    fetch(session, [NSURLRequest requestWithURL:url(@"/hello")], ^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        say([NSString stringWithFormat:@"hello: %ld '%@', %@ %@ %lld, X-Custom %@/%@, path %@, http %d, error %@",
             (long)http.statusCode, string(data), http.MIMEType, http.textEncodingName, http.expectedContentLength,
             http.allHeaderFields[@"X-Custom"], [http valueForHTTPHeaderField:@"x-custom"], http.URL.path,
             [response isKindOfClass:NSHTTPURLResponse.class], describe(error)]);
    });

    NSMutableURLRequest *post = [NSMutableURLRequest requestWithURL:url(@"/echo")];
    post.HTTPMethod = @"POST";
    post.HTTPBody = text(@"{\"ping\":true}");
    [post setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    fetch(session, post, ^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        say([NSString stringWithFormat:@"echo: %@ %@ '%@'", [http valueForHTTPHeaderField:@"X-Method"], http.MIMEType, string(data)]);
    });

    fetch(session, [NSURLRequest requestWithURL:url(@"/json")], ^(NSData *data, NSURLResponse *response, NSError *error) {
        NSDictionary *object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        say([NSString stringWithFormat:@"json: %@ %@", object[@"name"], [object[@"items"] componentsJoinedByString:@"+"]]);
    });

    fetch(session, [NSURLRequest requestWithURL:url(@"/redirect")], ^(NSData *data, NSURLResponse *response, NSError *error) {
        say([NSString stringWithFormat:@"redirect: %ld %@ '%@'", (long)((NSHTTPURLResponse *)response).statusCode,
             response.URL.path, string(data)]);
    });

    fetch(session, [NSURLRequest requestWithURL:url(@"/missing")], ^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = ((NSHTTPURLResponse *)response).statusCode;
        say([NSString stringWithFormat:@"missing: %ld '%@' (%@), error %@", (long)status, string(data),
             [NSHTTPURLResponse localizedStringForStatusCode:status], describe(error)]);
    });

    NSMutableURLRequest *headed = [NSMutableURLRequest requestWithURL:url(@"/headers")];
    [headed addValue:@"one" forHTTPHeaderField:@"X-Request"];
    fetch(session, headed, ^(NSData *data, NSURLResponse *response, NSError *error) {
        say([NSString stringWithFormat:@"headers: %@, request has %@", string(data), headed.allHTTPHeaderFields]);
    });

    fetch(session, [NSURLRequest requestWithURL:[NSURL URLWithString:@"data:text/plain;charset=utf-8,inline%20data"]],
          ^(NSData *data, NSURLResponse *response, NSError *error) {
        say([NSString stringWithFormat:@"data URL: '%@' %@ %@, http %d", string(data), response.MIMEType,
             response.textEncodingName, [response isKindOfClass:NSHTTPURLResponse.class]]);
    });
}

static void errors(void) {
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.timeoutIntervalForRequest = 0.5;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    fetch(session, [NSURLRequest requestWithURL:url(@"/slow")], ^(NSData *data, NSURLResponse *response, NSError *error) {
        say([NSString stringWithFormat:@"timeout: %@, data %@", describe(error), data]);
    });

    int closed = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address = {0};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    bind(closed, (struct sockaddr *)&address, sizeof(address));
    socklen_t size = sizeof(address);
    getsockname(closed, (struct sockaddr *)&address, &size);
    close(closed);
    NSURL *refused = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%d/", ntohs(address.sin_port)]];
    fetch(session, [NSURLRequest requestWithURL:refused], ^(NSData *data, NSURLResponse *response, NSError *error) {
        say([NSString stringWithFormat:@"refused: %@, failing URL matches %d", describe(error),
             [error.userInfo[NSURLErrorFailingURLErrorKey] isEqual:refused]]);
    });

    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url(@"/slow")
                                                           completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        say([NSString stringWithFormat:@"cancelled: %@", describe(error)]);
        dispatch_semaphore_signal(done);
    }];
    [task resume];
    usleep(100000);
    [task cancel];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    usleep(50000);
    say([NSString stringWithFormat:@"cancelled state: %ld", (long)task.state]);
    [session invalidateAndCancel];
}

static void delegates(void) {
    Watcher *watcher = [Watcher new];
    watcher.queue = [NSOperationQueue new];
    watcher.done = dispatch_semaphore_create(0);
    watcher.invalidated = dispatch_semaphore_create(0);
    NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.defaultSessionConfiguration
                                                          delegate:watcher delegateQueue:watcher.queue];
    NSURLSessionDataTask *task = [session dataTaskWithURL:url(@"/big")];
    say([NSString stringWithFormat:@"task: state %ld, original %@, has identifier %d", (long)task.state,
         task.originalRequest.URL.path, task.taskIdentifier >= 0]);
    [task resume];
    dispatch_semaphore_wait(watcher.done, DISPATCH_TIME_FOREVER);
    say([NSString stringWithFormat:@"delegate: status %ld, received %lu, on queue %d, completed %@, state %ld",
         (long)watcher.status, (unsigned long)watcher.received, watcher.onQueue, watcher.completion, (long)task.state]);

    watcher.received = 0;
    [[session dataTaskWithURL:url(@"/redirect")] resume];
    dispatch_semaphore_wait(watcher.done, DISPATCH_TIME_FOREVER);
    say([NSString stringWithFormat:@"delegate redirect: %ld redirects, received %lu", (long)watcher.redirects,
         (unsigned long)watcher.received]);
    [session finishTasksAndInvalidate];
    long invalidated = dispatch_semaphore_wait(watcher.invalidated, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    say([NSString stringWithFormat:@"invalidated: %d", invalidated == 0]);
}

static void transfers(void) {
    NSURLSession *session = NSURLSession.sharedSession;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [[session downloadTaskWithURL:url(@"/big") completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        NSData *data = [NSData dataWithContentsOfURL:location];
        say([NSString stringWithFormat:@"download: file %d, %lu bytes, error %@", location.isFileURL,
             (unsigned long)data.length, describe(error)]);
        dispatch_semaphore_signal(done);
    }] resume];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url(@"/echo")];
    request.HTTPMethod = @"PUT";
    [[session uploadTaskWithRequest:request fromData:text(@"uploaded bytes")
                  completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        say([NSString stringWithFormat:@"upload: %@ '%@'", [(NSHTTPURLResponse *)response valueForHTTPHeaderField:@"X-Method"],
             string(data)]);
        dispatch_semaphore_signal(done);
    }] resume];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
}

static void cookies(void) {
    NSURLSession *session = NSURLSession.sharedSession;
    fetch(session, [NSURLRequest requestWithURL:url(@"/cookie")], ^(NSData *data, NSURLResponse *response, NSError *error) {});
    NSArray<NSHTTPCookie *> *stored = [NSHTTPCookieStorage.sharedHTTPCookieStorage cookiesForURL:url(@"/")];
    fetch(session, [NSURLRequest requestWithURL:url(@"/cookies")], ^(NSData *data, NSURLResponse *response, NSError *error) {
        say([NSString stringWithFormat:@"cookies: stored %lu %@=%@ path %@, sent '%@'", (unsigned long)stored.count,
             stored.firstObject.name, stored.firstObject.value, stored.firstObject.path, string(data)]);
    });
    NSHTTPCookie *made = [NSHTTPCookie cookieWithProperties:@{NSHTTPCookieName: @"theme", NSHTTPCookieValue: @"dark",
                                                              NSHTTPCookieDomain: @"example.com", NSHTTPCookiePath: @"/"}];
    NSDictionary *header = [NSHTTPCookie requestHeaderFieldsWithCookies:@[made]];
    NSArray *parsed = [NSHTTPCookie cookiesWithResponseHeaderFields:@{@"Set-Cookie": @"a=1; Path=/x"}
                                                             forURL:[NSURL URLWithString:@"http://example.com/"]];
    say([NSString stringWithFormat:@"cookie: %@ %@ session %d, header %@, parsed %@=%@ %@", made.name, made.domain,
         made.isSessionOnly, header[@"Cookie"], [parsed.firstObject name], [parsed.firstObject value],
         [parsed.firstObject path]]);
}

static void objects(void) {
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.com/a?b=c"]];
    say([NSString stringWithFormat:@"request: %@ %@ timeout %.0f cache %lu cookies %d body %@ headers %@", request.HTTPMethod,
         request.URL.host, request.timeoutInterval, (unsigned long)request.cachePolicy, request.HTTPShouldHandleCookies,
         request.HTTPBody, request.allHTTPHeaderFields]);
    NSMutableURLRequest *mutable = [request mutableCopy];
    mutable.timeoutInterval = 5;
    [mutable setValue:@"text/html" forHTTPHeaderField:@"Accept"];
    [mutable addValue:@"application/json" forHTTPHeaderField:@"Accept"];
    say([NSString stringWithFormat:@"mutable: %.0f %@, equal %d %d", mutable.timeoutInterval,
         [mutable valueForHTTPHeaderField:@"accept"], [request isEqual:[request copy]], [request isEqual:mutable]]);

    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://example.com/f.json"]
                                                              statusCode:201 HTTPVersion:@"HTTP/1.1"
                                                            headerFields:@{@"Content-Type": @"application/json; charset=utf-8",
                                                                           @"Content-Length": @"42"}];
    say([NSString stringWithFormat:@"response: %ld %@ %@ %lld %@ (%@)", (long)response.statusCode, response.MIMEType,
         response.textEncodingName, response.expectedContentLength, response.suggestedFilename,
         [NSHTTPURLResponse localizedStringForStatusCode:500]]);

    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.defaultSessionConfiguration;
    say([NSString stringWithFormat:@"configuration: request %.0f resource %.0f cookies %d accept %lu cache %d",
         configuration.timeoutIntervalForRequest, configuration.timeoutIntervalForResource,
         configuration.HTTPShouldSetCookies, (unsigned long)configuration.HTTPCookieAcceptPolicy,
         configuration.URLCache != nil]);
    say([NSString stringWithFormat:@"errors: %@ %ld %ld %ld", NSURLErrorDomain, (long)NSURLErrorTimedOut,
         (long)NSURLErrorCancelled, (long)NSURLErrorCannotConnectToHost]);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        startServer();
        basics();
        errors();
        delegates();
        transfers();
        cookies();
        objects();
        connections();
    }
    return 0;
}
