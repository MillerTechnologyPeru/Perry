// URL protocols and authentication: an NSURLProtocol subclass answering
// its own scheme and stepping in for HTTP requests it marks, through
// sessions, configurations and connections; HTTP Basic challenges with
// their protection spaces, credentials and each disposition.

#import <Foundation/Foundation.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <pthread.h>
#include <stdio.h>
#include <sys/socket.h>
#include <unistd.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static NSData *text(NSString *string) {
    return [string dataUsingEncoding:NSUTF8StringEncoding];
}

static NSString *string(NSData *data) {
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"(null)";
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
    NSString *path = [lines[0] componentsSeparatedByString:@" "][1];
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    for (NSString *line in [lines subarrayWithRange:NSMakeRange(1, lines.count - 1)]) {
        NSRange colon = [line rangeOfString:@": "];
        if (colon.location != NSNotFound) {
            headers[[line substringToIndex:colon.location].lowercaseString] = [line substringFromIndex:NSMaxRange(colon)];
        }
    }
    if ([path isEqualToString:@"/secret"]) {
        NSString *expected = [@"Basic " stringByAppendingString:[text(@"perry:open sesame") base64EncodedStringWithOptions:0]];
        if ([headers[@"authorization"] isEqualToString:expected]) {
            reply(client, 200, @"OK", @{@"Content-Type": @"text/plain"}, text(@"the treasure"));
        } else {
            reply(client, 401, @"Unauthorized", @{@"Content-Type": @"text/plain", @"WWW-Authenticate": @"Basic realm=\"Vault\""},
                  text(@"go away"));
        }
    } else {
        reply(client, 200, @"OK", @{@"Content-Type": @"text/plain"},
              text([NSString stringWithFormat:@"server %@ marked %@", path, headers[@"x-marked"] ?: @"no"]));
    }
}

static void *accepting(void *unused) {
    while (1) {
        int client = accept(listener, NULL, NULL);
        if (client < 0) continue;
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            @autoreleasepool { serve(client); }
            close(client);
        });
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
    if (bind(listener, (struct sockaddr *)&address, sizeof(address)) != 0) perror("bind");
    if (listen(listener, 16) != 0) perror("listen");
    socklen_t size = sizeof(address);
    getsockname(listener, (struct sockaddr *)&address, &size);
    port = ntohs(address.sin_port);
    pthread_t thread;
    pthread_create(&thread, NULL, accepting, NULL);
}

static NSURL *url(NSString *path) {
    return [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%d%@", port, path]];
}

// MARK: - A protocol

static NSString *const handledKey = @"PerryHandled";

@interface EchoProtocol : NSURLProtocol
@end

@implementation EchoProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if ([request.URL.scheme isEqualToString:@"echo"]) return YES;
    // HTTP requests asking for it, once: the protocol's own load passes.
    return [request valueForHTTPHeaderField:@"X-Intercept"] != nil
        && [NSURLProtocol propertyForKey:handledKey inRequest:request] == nil;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    NSURL *url = self.request.URL;
    id<NSURLProtocolClient> client = self.client;
    if ([url.scheme isEqualToString:@"echo"]) {
        if ([url.host isEqualToString:@"fail"]) {
            [client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotFindHost userInfo:nil]];
            return;
        }
        if ([url.host isEqualToString:@"moved"]) {
            NSHTTPURLResponse *moved = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:302 HTTPVersion:@"HTTP/1.1"
                                                                 headerFields:@{@"Location": @"echo://there/"}];
            [client URLProtocol:self wasRedirectedToRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"echo://there/"]]
                 redirectResponse:moved];
            return;
        }
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200 HTTPVersion:@"HTTP/1.1"
                                                                headerFields:@{@"Content-Type": @"text/plain", @"X-Echo": @"1"}];
        [client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        [client URLProtocol:self didLoadData:text(@"echo of ")];
        [client URLProtocol:self didLoadData:text(url.absoluteString)];
        [client URLProtocolDidFinishLoading:self];
        return;
    }
    // Load the HTTP request itself, marked, and pass on what comes back.
    NSMutableURLRequest *marked = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:handledKey inRequest:marked];
    [marked setValue:@"yes" forHTTPHeaderField:@"X-Marked"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:marked
                                     completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            [client URLProtocol:self didFailWithError:error];
            return;
        }
        [client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        [client URLProtocol:self didLoadData:data];
        [client URLProtocolDidFinishLoading:self];
    }] resume];
}

- (void)stopLoading {
}
@end

// MARK: - A delegate answering challenges

@interface Answerer : NSObject <NSURLSessionTaskDelegate, NSURLSessionDataDelegate>
@property NSInteger mode;
@property (strong) NSMutableData *body;
@property (strong) dispatch_semaphore_t done;
@end

@implementation Answerer
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
      completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {
    NSURLProtectionSpace *space = challenge.protectionSpace;
    NSHTTPURLResponse *failure = (NSHTTPURLResponse *)challenge.failureResponse;
    say([NSString stringWithFormat:@"challenge: %@ port %d %@ realm %@ method %@, proxy %d secure %d, failures %ld, proposed %@, response %ld, error %@",
         space.host, space.port == port, space.protocol, space.realm, space.authenticationMethod, space.isProxy,
         space.receivesCredentialSecurely, (long)challenge.previousFailureCount, challenge.proposedCredential.user,
         (long)failure.statusCode, challenge.error]);
    switch (self.mode) {
    case 0:
        completionHandler(NSURLSessionAuthChallengeUseCredential,
                          [NSURLCredential credentialWithUser:@"perry" password:challenge.previousFailureCount ? @"open sesame" : @"wrong"
                                                  persistence:NSURLCredentialPersistenceNone]);
        break;
    case 1:
        completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
        break;
    case 2:
        completionHandler(NSURLSessionAuthChallengeRejectProtectionSpace, nil);
        break;
    default:
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
        break;
    }
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    [self.body appendData:data];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    say([NSString stringWithFormat:@"  done: %ld %@, error %@ %ld", (long)((NSHTTPURLResponse *)task.response).statusCode,
         string(self.body), error.domain, (long)error.code]);
    dispatch_semaphore_signal(self.done);
}
@end

@interface ConnectionAnswerer : NSObject <NSURLConnectionDataDelegate>
@property (strong) NSMutableData *body;
@property BOOL finished;
@end

@implementation ConnectionAnswerer
- (void)connection:(NSURLConnection *)connection willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    say([NSString stringWithFormat:@"connection challenge: %@ realm %@, failures %ld, sender %d",
         challenge.protectionSpace.authenticationMethod, challenge.protectionSpace.realm, (long)challenge.previousFailureCount,
         challenge.sender != nil]);
    [challenge.sender useCredential:[NSURLCredential credentialWithUser:@"perry" password:@"open sesame"
                                                             persistence:NSURLCredentialPersistenceNone]
         forAuthenticationChallenge:challenge];
}
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    say([NSString stringWithFormat:@"connection response: %ld", (long)((NSHTTPURLResponse *)response).statusCode]);
}
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [self.body appendData:data];
}
- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    say([NSString stringWithFormat:@"connection finished: %@", string(self.body)]);
    self.finished = YES;
}
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    say([NSString stringWithFormat:@"connection failed: %@ %ld", error.domain, (long)error.code]);
    self.finished = YES;
}
@end

// MARK: - Loads

static void load(NSURLSession *session, NSURLRequest *request, NSString *label) {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        say([NSString stringWithFormat:@"%@: %ld %@ %@ [%@], type %@ echo %@, error %@ %ld", label, (long)http.statusCode,
             [response.URL.absoluteString stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@":%d/", port]
                                                                    withString:@":PORT/"], response.MIMEType, string(data), http.allHeaderFields[@"Content-Type"],
             http.allHeaderFields[@"X-Echo"], error.domain, (long)error.code]);
        dispatch_semaphore_signal(done);
    }] resume];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
}

static void protocols(void) {
    NSURLSession *shared = [NSURLSession sharedSession];
    load(shared, [NSURLRequest requestWithURL:[NSURL URLWithString:@"echo://before/"]], @"unregistered");
    say([NSString stringWithFormat:@"register: %d", [NSURLProtocol registerClass:EchoProtocol.class]]);
    load(shared, [NSURLRequest requestWithURL:[NSURL URLWithString:@"echo://hello/path?q=1"]], @"echo");
    load(shared, [NSURLRequest requestWithURL:[NSURL URLWithString:@"echo://fail/"]], @"fail");
    load(shared, [NSURLRequest requestWithURL:[NSURL URLWithString:@"echo://moved/"]], @"moved");
    NSMutableURLRequest *intercepted = [NSMutableURLRequest requestWithURL:url(@"/page")];
    [intercepted setValue:@"1" forHTTPHeaderField:@"X-Intercept"];
    load(shared, intercepted, @"intercepted");
    load(shared, [NSURLRequest requestWithURL:url(@"/plain")], @"plain");

    // Properties ride on requests and their copies.
    NSMutableURLRequest *carrier = [NSMutableURLRequest requestWithURL:url(@"/x")];
    [NSURLProtocol setProperty:@"value" forKey:@"key" inRequest:carrier];
    NSURLRequest *copy = [carrier copy];
    say([NSString stringWithFormat:@"properties: %@ %@ %@", [NSURLProtocol propertyForKey:@"key" inRequest:copy],
         [NSURLProtocol propertyForKey:@"missing" inRequest:copy], [NSURLProtocol propertyForKey:@"key" inRequest:[NSURLRequest requestWithURL:url(@"/x")]]]);
    [NSURLProtocol removePropertyForKey:@"key" inRequest:carrier];
    say([NSString stringWithFormat:@"removed: %@, equal %d", [NSURLProtocol propertyForKey:@"key" inRequest:carrier], [carrier isEqual:copy]]);

    // Unregistered, it still serves a session configured with it.
    [NSURLProtocol unregisterClass:EchoProtocol.class];
    load(shared, [NSURLRequest requestWithURL:[NSURL URLWithString:@"echo://gone/"]], @"unregistered again");
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.protocolClasses = [@[EchoProtocol.class] arrayByAddingObjectsFromArray:configuration.protocolClasses];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    load(session, [NSURLRequest requestWithURL:[NSURL URLWithString:@"echo://configured/"]], @"configured");
    [session finishTasksAndInvalidate];

    // A connection, with the protocol registered again.
    [NSURLProtocol registerClass:EchoProtocol.class];
    NSURLResponse *response = nil;
    NSError *error = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSData *data = [NSURLConnection sendSynchronousRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"echo://connection/"]]
                                         returningResponse:&response error:&error];
#pragma clang diagnostic pop
    say([NSString stringWithFormat:@"connection: %@ %@, error %@", string(data), response.MIMEType, error]);
    [NSURLProtocol unregisterClass:EchoProtocol.class];
}

static void challenges(void) {
    NSURLCredential *credential = [NSURLCredential credentialWithUser:@"perry" password:@"pw" persistence:NSURLCredentialPersistenceForSession];
    say([NSString stringWithFormat:@"credential: %@ %@ has %d persistence %lu", credential.user, credential.password,
         credential.hasPassword, (unsigned long)credential.persistence]);
    NSURLProtectionSpace *space = [[NSURLProtectionSpace alloc] initWithHost:@"example.com" port:443 protocol:NSURLProtectionSpaceHTTPS
                                                                       realm:@"Realm" authenticationMethod:NSURLAuthenticationMethodDefault];
    NSURLProtectionSpace *same = [[NSURLProtectionSpace alloc] initWithHost:@"example.com" port:443 protocol:@"https"
                                                                      realm:@"Realm" authenticationMethod:NSURLAuthenticationMethodDefault];
    say([NSString stringWithFormat:@"space: %@ %ld %@ %@ %@ proxy %d secure %d type %@, equal %d", space.host, (long)space.port,
         space.protocol, space.realm, space.authenticationMethod, space.isProxy, space.receivesCredentialSecurely, space.proxyType,
         [space isEqual:same]]);
    say([NSString stringWithFormat:@"methods: %@ %@ %@ %@ %@", NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest,
         NSURLAuthenticationMethodServerTrust, NSURLAuthenticationMethodClientCertificate, NSURLAuthenticationMethodHTMLForm]);
    NSURLCredentialStorage *storage = [NSURLCredentialStorage sharedCredentialStorage];
    [storage setCredential:credential forProtectionSpace:space];
    say([NSString stringWithFormat:@"storage: %@, default %@", [[storage credentialsForProtectionSpace:space][@"perry"] password],
         [storage defaultCredentialForProtectionSpace:space].user]);
    [storage removeCredential:credential forProtectionSpace:space];
    say([NSString stringWithFormat:@"removed: %lu", (unsigned long)[storage credentialsForProtectionSpace:space].count]);

    NSArray *labels = @[@"wrong then right", @"cancel", @"reject", @"default"];
    for (NSInteger mode = 0; mode < 4; mode++) {
        say([NSString stringWithFormat:@"session %@:", labels[mode]]);
        Answerer *answerer = [Answerer new];
        answerer.mode = mode;
        answerer.body = [NSMutableData data];
        answerer.done = dispatch_semaphore_create(0);
        NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]
                                                              delegate:answerer delegateQueue:nil];
        [[session dataTaskWithURL:url(@"/secret")] resume];
        dispatch_semaphore_wait(answerer.done, DISPATCH_TIME_FOREVER);
        [session finishTasksAndInvalidate];
    }

    ConnectionAnswerer *answerer = [ConnectionAnswerer new];
    answerer.body = [NSMutableData data];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSURLConnection *connection = [NSURLConnection connectionWithRequest:[NSURLRequest requestWithURL:url(@"/secret")] delegate:answerer];
#pragma clang diagnostic pop
    [connection start];
    while (!answerer.finished) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        startServer();
        say([NSString stringWithFormat:@"constants: %lld %.2f %.2f %.2f", NSURLSessionTransferSizeUnknown,
             NSURLSessionTaskPriorityDefault, NSURLSessionTaskPriorityLow, NSURLSessionTaskPriorityHigh]);
        protocols();
        challenges();
    }
    return 0;
}
