// URL loading and linguistic analysis, built on a Mac with Xcode: session,
// task, request and cookie properties; a WebSocket task and stream tasks
// against servers this program runs itself on 127.0.0.1; text checking
// results; NSLinguisticTagger's token types and units; NSOrthography.
// Prints to stdout so the test can compare exact text. No other network.
#import <Foundation/Foundation.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static void print(NSString *line) {
    printf("%s\n", line.UTF8String);
}
#define P(...) print([NSString stringWithFormat:__VA_ARGS__])

static NSString *range(NSRange r) {
    return r.location == NSNotFound ? @"{nf}" : [NSString stringWithFormat:@"{%lu,%lu}", (unsigned long)r.location, (unsigned long)r.length];
}

static NSString *err(NSError *e) {
    return e ? [NSString stringWithFormat:@"%@ %ld", e.domain, (long)e.code] : @"nil";
}

static NSString *text(NSData *d) {
    return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : @"(nil)";
}

// MARK: - Servers on 127.0.0.1

static int listener(uint16_t *port) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in a = {0};
    a.sin_family = AF_INET;
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    bind(fd, (struct sockaddr *)&a, sizeof a);
    listen(fd, 4);
    socklen_t n = sizeof a;
    getsockname(fd, (struct sockaddr *)&a, &n);
    *port = ntohs(a.sin_port);
    return fd;
}

static BOOL readFully(int fd, uint8_t *b, size_t n) {
    size_t got = 0;
    while (got < n) {
        ssize_t r = read(fd, b + got, n - got);
        if (r <= 0) return NO;
        got += (size_t)r;
    }
    return YES;
}

static NSString *readLine(int fd) {
    NSMutableData *d = [NSMutableData data];
    uint8_t c;
    while (read(fd, &c, 1) == 1 && c != '\n') [d appendBytes:&c length:1];
    return text(d);
}

static void writeString(int fd, NSString *s) {
    write(fd, s.UTF8String, strlen(s.UTF8String));
}

// SHA-1, for the WebSocket handshake's accept key.
static void sha1(const uint8_t *m, size_t n, uint8_t out[20]) {
    uint32_t h[5] = {0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0};
    size_t total = ((n + 8) / 64 + 1) * 64;
    uint8_t *b = calloc(total, 1);
    memcpy(b, m, n);
    b[n] = 0x80;
    uint64_t bits = (uint64_t)n * 8;
    for (int i = 0; i < 8; i++) b[total - 1 - i] = (uint8_t)(bits >> (8 * i));
    for (size_t off = 0; off < total; off += 64) {
        uint32_t w[80];
        for (int i = 0; i < 16; i++) w[i] = (uint32_t)b[off + 4 * i] << 24 | b[off + 4 * i + 1] << 16 | b[off + 4 * i + 2] << 8 | b[off + 4 * i + 3];
        for (int i = 16; i < 80; i++) { uint32_t x = w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]; w[i] = x << 1 | x >> 31; }
        uint32_t a = h[0], bb = h[1], c = h[2], d = h[3], e = h[4];
        for (int i = 0; i < 80; i++) {
            uint32_t f, k;
            if (i < 20) { f = (bb & c) | (~bb & d); k = 0x5A827999; }
            else if (i < 40) { f = bb ^ c ^ d; k = 0x6ED9EBA1; }
            else if (i < 60) { f = (bb & c) | (bb & d) | (c & d); k = 0x8F1BBCDC; }
            else { f = bb ^ c ^ d; k = 0xCA62C1D6; }
            uint32_t t = (a << 5 | a >> 27) + f + e + k + w[i];
            e = d; d = c; c = bb << 30 | bb >> 2; bb = a; a = t;
        }
        h[0] += a; h[1] += bb; h[2] += c; h[3] += d; h[4] += e;
    }
    free(b);
    for (int i = 0; i < 20; i++) out[i] = (uint8_t)(h[i / 4] >> (24 - 8 * (i % 4)));
}

static NSMutableArray<NSString *> *serverNotes;

static void note(NSString *line) {
    @synchronized (serverNotes) { [serverNotes addObject:line]; }
}

static void sendFrame(int fd, uint8_t opcode, NSData *payload) {
    uint8_t head[4] = {(uint8_t)(0x80 | opcode), 0};
    size_t n = 2;
    if (payload.length < 126) head[1] = (uint8_t)payload.length;
    else { head[1] = 126; head[2] = (uint8_t)(payload.length >> 8); head[3] = (uint8_t)payload.length; n = 4; }
    write(fd, head, n);
    if (payload.length) write(fd, payload.bytes, payload.length);
}

// One WebSocket connection: checks the upgrade, answers with the first
// protocol offered, echoes text as "echo:<text>", binary reversed, pongs a
// ping, closes when asked to ("close-me") and echoes a client's close.
static void serveWebSocket(int fd) {
    NSString *key = nil, *requestLine = readLine(fd);
    NSMutableArray *headers = [NSMutableArray array];
    NSString *protocol = nil;
    for (NSString *line = readLine(fd); line.length > 1; line = readLine(fd)) {
        NSString *h = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSRange colon = [h rangeOfString:@":"];
        NSString *name = [h substringToIndex:colon.location].lowercaseString;
        NSString *value = [[h substringFromIndex:colon.location + 1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([name isEqual:@"sec-websocket-key"]) key = value;
        if ([name isEqual:@"sec-websocket-protocol"]) protocol = [value componentsSeparatedByString:@","].firstObject;
        if ([@[@"upgrade", @"sec-websocket-version", @"sec-websocket-protocol", @"x-fixture"] containsObject:name])
            [headers addObject:[NSString stringWithFormat:@"%@=%@", name, value]];
    }
    [headers sortUsingSelector:@selector(compare:)];
    note([NSString stringWithFormat:@"server: %@ %@", requestLine, [headers componentsJoinedByString:@" "]]);
    NSString *joined = [key stringByAppendingString:@"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"];
    uint8_t digest[20];
    sha1((const uint8_t *)joined.UTF8String, strlen(joined.UTF8String), digest);
    NSString *accept = [[NSData dataWithBytes:digest length:20] base64EncodedStringWithOptions:0];
    NSMutableString *reply = [NSMutableString stringWithFormat:@"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: %@\r\n", accept];
    if (protocol) [reply appendFormat:@"Sec-WebSocket-Protocol: %@\r\n", protocol];
    [reply appendString:@"\r\n"];
    writeString(fd, reply);
    while (YES) {
        uint8_t head[2], mask[4];
        if (!readFully(fd, head, 2)) break;
        uint64_t length = head[1] & 0x7F;
        if (length == 126) { uint8_t l[2]; readFully(fd, l, 2); length = (uint64_t)l[0] << 8 | l[1]; }
        readFully(fd, mask, 4);
        NSMutableData *payload = [NSMutableData dataWithLength:(NSUInteger)length];
        readFully(fd, payload.mutableBytes, (size_t)length);
        uint8_t *p = payload.mutableBytes;
        for (uint64_t i = 0; i < length; i++) p[i] ^= mask[i % 4];
        uint8_t opcode = head[0] & 0x0F;
        note([NSString stringWithFormat:@"server: frame fin=%d masked=%d opcode=%d length=%llu", head[0] >> 7, head[1] >> 7, opcode, length]);
        if (opcode == 1) {
            NSString *s = text(payload);
            if ([s isEqual:@"close-me"]) {
                NSMutableData *close = [NSMutableData dataWithBytes:(uint8_t[]){0x0F, 0xA1} length:2];
                [close appendData:[@"asked" dataUsingEncoding:NSUTF8StringEncoding]];
                sendFrame(fd, 8, close);
            } else {
                sendFrame(fd, 1, [[@"echo:" stringByAppendingString:s] dataUsingEncoding:NSUTF8StringEncoding]);
            }
        } else if (opcode == 2) {
            NSMutableData *reversed = [NSMutableData dataWithLength:payload.length];
            for (NSUInteger i = 0; i < payload.length; i++) ((uint8_t *)reversed.mutableBytes)[i] = p[payload.length - 1 - i];
            sendFrame(fd, 2, reversed);
        } else if (opcode == 9) {
            sendFrame(fd, 10, payload);
        } else if (opcode == 8) {
            unsigned code = length >= 2 ? (unsigned)p[0] << 8 | p[1] : 0;
            NSString *reason = length > 2 ? text([payload subdataWithRange:NSMakeRange(2, payload.length - 2)]) : @"";
            note([NSString stringWithFormat:@"server: close %u %@", code, reason]);
            sendFrame(fd, 8, payload);
            break;
        }
    }
    close(fd);
}

// One stream connection: answers a line with "got:<line>", then waits for
// the client's end and says "bye".
static void serveStream(int fd) {
    NSString *line = readLine(fd);
    writeString(fd, [NSString stringWithFormat:@"got:%@\n", line]);
    uint8_t rest[64];
    ssize_t n, total = 0;
    while ((n = read(fd, rest, sizeof rest)) > 0) total += n;
    note([NSString stringWithFormat:@"server: stream '%@' then %ld more bytes, end", line, (long)total]);
    writeString(fd, @"bye");
    close(fd);
}

// Connections a server has accepted and not yet finished with.
static volatile long serving;

static void serve(int listening, void (*handler)(int)) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        while (YES) {
            int fd = accept(listening, NULL, NULL);
            if (fd < 0) return;
            __sync_fetch_and_add(&serving, 1);
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
                handler(fd);
                __sync_fetch_and_sub(&serving, 1);
            });
        }
    });
}

// Leaves out the server's notes of a close the client started: Darwin
// doesn't always send its close frame before it drops the connection.
static void forgetClientClose(NSString *reason) {
    @synchronized (serverNotes) {
        NSIndexSet *close = [serverNotes indexesOfObjectsPassingTest:^BOOL(NSString *line, NSUInteger index, BOOL *stop) {
            return [line hasPrefix:@"server: frame fin=1 masked=1 opcode=8 "] || [line isEqual:[@"server: close 1000 " stringByAppendingString:reason]];
        }];
        [serverNotes removeObjectsAtIndexes:close];
    }
}

// The servers' notes so far, once each connection they accepted is done
// (for up to five seconds): a server can still be reading a close when the
// client has finished, which makes its notes late on some systems.
static void printNotes(void) {
    for (int i = 0; i < 500 && __sync_fetch_and_add(&serving, 0) > 0; i++) usleep(10000);
    @synchronized (serverNotes) {
        for (NSString *line in serverNotes) print(line);
        [serverNotes removeAllObjects];
    }
}

// MARK: - The session's delegate

@interface Recorder : NSObject <NSURLSessionWebSocketDelegate, NSURLSessionStreamDelegate>
@property NSMutableArray<NSString *> *events;
@property dispatch_semaphore_t completed;
@property dispatch_semaphore_t captured;
@property NSInputStream *input;
@property NSOutputStream *output;
@end

@implementation Recorder
- (instancetype)init {
    if ((self = [super init])) {
        _events = [NSMutableArray array];
        _completed = dispatch_semaphore_create(0);
        _captured = dispatch_semaphore_create(0);
    }
    return self;
}
- (void)URLSession:(NSURLSession *)session webSocketTask:(NSURLSessionWebSocketTask *)task didOpenWithProtocol:(NSString *)protocol {
    [self.events addObject:[NSString stringWithFormat:@"open %@", protocol]];
}
- (void)URLSession:(NSURLSession *)session webSocketTask:(NSURLSessionWebSocketTask *)task didCloseWithCode:(NSURLSessionWebSocketCloseCode)code reason:(NSData *)reason {
    [self.events addObject:[NSString stringWithFormat:@"close %ld %@", (long)code, text(reason)]];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    [self.events addObject:[NSString stringWithFormat:@"complete %@", err(error)]];
    dispatch_semaphore_signal(self.completed);
}
- (void)URLSession:(NSURLSession *)session readClosedForStreamTask:(NSURLSessionStreamTask *)task {
    [self.events addObject:@"read closed"];
}
- (void)URLSession:(NSURLSession *)session writeClosedForStreamTask:(NSURLSessionStreamTask *)task {
    [self.events addObject:@"write closed"];
}
- (void)URLSession:(NSURLSession *)session streamTask:(NSURLSessionStreamTask *)task didBecomeInputStream:(NSInputStream *)input outputStream:(NSOutputStream *)output {
    [self.events addObject:[NSString stringWithFormat:@"streams %d %d", input != nil, output != nil]];
    self.input = input;
    self.output = output;
    dispatch_semaphore_signal(self.captured);
}
- (NSString *)drain {
    NSString *joined = [self.events componentsJoinedByString:@", "];
    [self.events removeAllObjects];
    return joined;
}
@end

static void await(dispatch_semaphore_t s) {
    dispatch_semaphore_wait(s, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
}

// MARK: - Sections

static void configurations(NSURLSession *session) {
    NSURLSessionConfiguration *background = [NSURLSessionConfiguration backgroundSessionConfiguration:@"org.perry.semaphore"];
    P(@"background %@ discretionary=%d launch=%d", background.identifier, background.discretionary, background.sessionSendsLaunchEvents);
    NSURLSessionDataTask *task = [session dataTaskWithURL:[NSURL URLWithString:@"http://127.0.0.1:9/never"]];
    P(@"task begin=%@ send=%lld receive=%lld incremental=%d state=%ld", task.earliestBeginDate, task.countOfBytesClientExpectsToSend,
      task.countOfBytesClientExpectsToReceive, task.prefersIncrementalDelivery, (long)task.state);
    task.earliestBeginDate = [NSDate dateWithTimeIntervalSince1970:86400];
    task.countOfBytesClientExpectsToSend = 100;
    task.countOfBytesClientExpectsToReceive = 2048;
    task.prefersIncrementalDelivery = NO;
    P(@"task begin=%.0f send=%lld receive=%lld incremental=%d", task.earliestBeginDate.timeIntervalSince1970, task.countOfBytesClientExpectsToSend,
      task.countOfBytesClientExpectsToReceive, task.prefersIncrementalDelivery);
    NSProgress *progress = task.progress;
    P(@"progress same=%d cancellable=%d pausable=%d cancelled=%d", progress == task.progress, progress.cancellable, progress.pausable, progress.cancelled);
    [task cancel];
    P(@"progress after cancel cancelled=%d state=%ld", progress.cancelled, (long)task.state);

    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    NSURLSessionDownloadTask *download = [session downloadTaskWithURL:[NSURL URLWithString:@"http://127.0.0.1:9/never"]];
    [download cancelByProducingResumeData:^(NSData *data) {
        P(@"resume data %@", data ? @"some" : @"nil");
        dispatch_semaphore_signal(done);
    }];
    await(done);
    NSURLSessionDownloadTask *resumed = [session downloadTaskWithResumeData:[NSData data] completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        P(@"resumed location=%@ response=%@ error=%@", location, response, err(error));
        dispatch_semaphore_signal(done);
    }];
    P(@"resumed task state=%ld", (long)resumed.state);
    [resumed resume];
    await(done);
    [session flushWithCompletionHandler:^{
        P(@"flushed");
        dispatch_semaphore_signal(done);
    }];
    await(done);
    [session resetWithCompletionHandler:^{
        P(@"reset");
        dispatch_semaphore_signal(done);
    }];
    await(done);
}

static void cookies(NSURLSession *session) {
    NSHTTPCookie *a = [NSHTTPCookie cookieWithProperties:@{NSHTTPCookieName: @"alpha", NSHTTPCookieValue: @"1", NSHTTPCookieDomain: @"example.com",
                                                            NSHTTPCookiePath: @"/", NSHTTPCookieCommentURL: @"https://example.com/why",
                                                            NSHTTPCookiePort: @"8080", NSHTTPCookieVersion: @"1"}];
    NSHTTPCookie *b = [NSHTTPCookie cookieWithProperties:@{NSHTTPCookieName: @"beta", NSHTTPCookieValue: @"2", NSHTTPCookieDomain: @"example.com",
                                                            NSHTTPCookiePath: @"/"}];
    NSHTTPCookie *c = [NSHTTPCookie cookieWithProperties:@{NSHTTPCookieName: @"gamma", NSHTTPCookieValue: @"3", NSHTTPCookieDomain: @"other.org",
                                                            NSHTTPCookiePath: @"/"}];
    P(@"cookie %@ commentURL=%@ ports=%@", a.name, a.commentURL, [a.portList componentsJoinedByString:@","]);
    P(@"cookie %@ commentURL=%@ ports=%lu", b.name, b.commentURL, (unsigned long)b.portList.count);
    NSHTTPCookieStorage *storage = NSHTTPCookieStorage.sharedHTTPCookieStorage;
    for (NSHTTPCookie *cookie in storage.cookies) [storage deleteCookie:cookie];
    NSURLSessionDataTask *task = [session dataTaskWithURL:[NSURL URLWithString:@"https://example.com/page"]];
    [storage storeCookies:@[a, b, c] forTask:task];
    NSArray *sorted = [storage sortedCookiesUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:NO]]];
    NSMutableArray *names = [NSMutableArray array];
    for (NSHTTPCookie *cookie in sorted) [names addObject:cookie.name];
    P(@"stored for task: %@", [names componentsJoinedByString:@","]);
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [storage getCookiesForTask:task completionHandler:^(NSArray<NSHTTPCookie *> *found) {
        P(@"cookies for task: %lu", (unsigned long)found.count);
        dispatch_semaphore_signal(done);
    }];
    await(done);
    for (NSHTTPCookie *cookie in storage.cookies) [storage deleteCookie:cookie];

    NSURLCredentialStorage *credentials = NSURLCredentialStorage.sharedCredentialStorage;
    NSURLProtectionSpace *space = [[NSURLProtectionSpace alloc] initWithHost:@"example.org" port:443 protocol:NSURLProtectionSpaceHTTPS
                                                                       realm:@"fixture" authenticationMethod:NSURLAuthenticationMethodHTTPBasic];
    NSURLCredential *first = [NSURLCredential credentialWithUser:@"ana" password:@"x" persistence:NSURLCredentialPersistenceForSession];
    NSURLCredential *second = [NSURLCredential credentialWithUser:@"ben" password:@"y" persistence:NSURLCredentialPersistenceForSession];
    [credentials setCredential:first forProtectionSpace:space task:task];
    [credentials getCredentialsForProtectionSpace:space task:task completionHandler:^(NSDictionary *found) {
        P(@"credentials for task: %@", [[found.allKeys sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","]);
        dispatch_semaphore_signal(done);
    }];
    await(done);
    [credentials setDefaultCredential:second forProtectionSpace:space task:task];
    [credentials getDefaultCredentialForProtectionSpace:space task:task completionHandler:^(NSURLCredential *credential) {
        P(@"default for task: %@", credential.user);
        dispatch_semaphore_signal(done);
    }];
    await(done);
    [credentials removeCredential:first forProtectionSpace:space options:nil task:task];
    [credentials removeCredential:second forProtectionSpace:space options:nil task:task];
    P(@"after removing: %@", [credentials credentialsForProtectionSpace:space]);
}

static void webSockets(NSURLSession *session, Recorder *recorder) {
    uint16_t port;
    int listening = listener(&port);
    serve(listening, serveWebSocket);
    NSString *base = [NSString stringWithFormat:@"ws://127.0.0.1:%u", port];
    NSURLSessionWebSocketTask *task = [session webSocketTaskWithURL:[NSURL URLWithString:[base stringByAppendingString:@"/chat?room=1"]]
                                                          protocols:@[@"chat", @"superchat"]];
    P(@"ws state=%ld max=%ld code=%ld reason=%@ scheme=%@ method=%@", (long)task.state, (long)task.maximumMessageSize, (long)task.closeCode,
      task.closeReason, task.originalRequest.URL.scheme, task.originalRequest.HTTPMethod);
    task.maximumMessageSize = 4096;
    P(@"ws max=%ld", (long)task.maximumMessageSize);
    [task resume];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    NSURLSessionWebSocketMessage *hello = [[NSURLSessionWebSocketMessage alloc] initWithString:@"hello"];
    P(@"message type=%ld string=%@ data=%@", (long)hello.type, hello.string, hello.data);
    [task sendMessage:hello completionHandler:^(NSError *error) {
        P(@"sent text: %@", err(error));
        dispatch_semaphore_signal(done);
    }];
    await(done);
    [task receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *message, NSError *error) {
        P(@"received type=%ld string=%@ error=%@", (long)message.type, message.string, err(error));
        dispatch_semaphore_signal(done);
    }];
    await(done);
    NSURLSessionWebSocketMessage *bytes = [[NSURLSessionWebSocketMessage alloc] initWithData:[@"abc" dataUsingEncoding:NSUTF8StringEncoding]];
    P(@"message type=%ld string=%@ data=%@", (long)bytes.type, bytes.string, text(bytes.data));
    [task sendMessage:bytes completionHandler:^(NSError *error) {
        P(@"sent data: %@", err(error));
    }];
    [task receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *message, NSError *error) {
        P(@"received type=%ld data=%@ error=%@", (long)message.type, text(message.data), err(error));
        dispatch_semaphore_signal(done);
    }];
    await(done);
    // Its own semaphore: a stray signal on `done` has been seen to let the
    // pong's line come after the next ones.
    dispatch_semaphore_t ponged = dispatch_semaphore_create(0);
    [task sendPingWithPongReceiveHandler:^(NSError *error) {
        P(@"pong: %@", err(error));
        dispatch_semaphore_signal(ponged);
    }];
    await(ponged);
    P(@"ws response %ld protocol=%@ state=%ld", (long)((NSHTTPURLResponse *)task.response).statusCode,
      [(NSHTTPURLResponse *)task.response valueForHTTPHeaderField:@"Sec-WebSocket-Protocol"], (long)task.state);
    [task cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:[@"bye" dataUsingEncoding:NSUTF8StringEncoding]];
    await(recorder.completed);
    usleep(100000);
    P(@"ws closed code=%ld reason=%@ state=%ld error=%@", (long)task.closeCode, text(task.closeReason), (long)task.state, err(task.error));
    [task receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *message, NSError *error) {
        P(@"receive after close: %@ %@", message, err(error));
        dispatch_semaphore_signal(done);
    }];
    await(done);
    P(@"events: %@", [recorder drain]);
    for (int i = 0; i < 500 && __sync_fetch_and_add(&serving, 0) > 0; i++) usleep(10000);
    forgetClientClose(@"bye");
    printNotes();

    // The server closes this one.
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[base stringByAppendingString:@"/other"]]];
    [request setValue:@"yes" forHTTPHeaderField:@"X-Fixture"];
    NSURLSessionWebSocketTask *closing = [session webSocketTaskWithRequest:request];
    [closing resume];
    [closing sendMessage:[[NSURLSessionWebSocketMessage alloc] initWithString:@"close-me"] completionHandler:^(NSError *error) {
        P(@"sent close-me: %@", err(error));
    }];
    [closing receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *message, NSError *error) {
        P(@"received after server close: %@ %@", message.string, err(error));
        dispatch_semaphore_signal(done);
    }];
    await(done);
    await(recorder.completed);
    usleep(100000);
    P(@"server closed code=%ld reason=%@ state=%ld", (long)closing.closeCode, text(closing.closeReason), (long)closing.state);
    P(@"events: %@", [recorder drain]);
    printNotes();

    // Nothing listens on this one.
    uint16_t deadPort;
    int dead = listener(&deadPort);
    close(dead);
    NSURLSessionWebSocketTask *refused = [session webSocketTaskWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"ws://127.0.0.1:%u/", deadPort]]];
    [refused resume];
    [refused receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *message, NSError *error) {
        P(@"refused receive: %@ %@", message, err(error));
        dispatch_semaphore_signal(done);
    }];
    await(done);
    await(recorder.completed);
    P(@"refused state=%ld error=%@ code=%ld", (long)refused.state, err(refused.error), (long)refused.closeCode);
    P(@"events: %@", [recorder drain]);
    close(listening);
}

// Waits for a task's completion, then lets late events arrive.
static void settle(Recorder *recorder) {
    await(recorder.completed);
    usleep(200000);
    while (dispatch_semaphore_wait(recorder.completed, DISPATCH_TIME_NOW) == 0) {}
}

static void streams(NSURLSession *session, Recorder *recorder) {
    uint16_t port;
    int listening = listener(&port);
    serve(listening, serveStream);
    NSURLSessionStreamTask *task = [session streamTaskWithHostName:@"127.0.0.1" port:port];
    P(@"stream state=%ld response=%@", (long)task.state, task.response);
    [task resume];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [task writeData:[@"ping\n" dataUsingEncoding:NSUTF8StringEncoding] timeout:5 completionHandler:^(NSError *error) {
        P(@"wrote: %@", err(error));
    }];
    [task readDataOfMinLength:9 maxLength:64 timeout:5 completionHandler:^(NSData *data, BOOL atEOF, NSError *error) {
        P(@"read '%@' eof=%d error=%@", [text(data) stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"], atEOF, err(error));
        dispatch_semaphore_signal(done);
    }];
    await(done);
    [task closeWrite];
    [task readDataOfMinLength:3 maxLength:3 timeout:5 completionHandler:^(NSData *data, BOOL atEOF, NSError *error) {
        P(@"read '%@' error=%@", text(data), err(error));
        dispatch_semaphore_signal(done);
    }];
    await(done);
    [task readDataOfMinLength:1 maxLength:64 timeout:5 completionHandler:^(NSData *data, BOOL atEOF, NSError *error) {
        P(@"read at end: %lu eof=%d error=%@", (unsigned long)data.length, atEOF, err(error));
        dispatch_semaphore_signal(done);
    }];
    await(done);
    [task writeData:[@"late" dataUsingEncoding:NSUTF8StringEncoding] timeout:5 completionHandler:^(NSError *error) {
        P(@"write after closeWrite: %@", error ? @"error" : @"nil");
        dispatch_semaphore_signal(done);
    }];
    await(done);
    [task cancel];
    settle(recorder);
    P(@"stream state=%ld error=%@", (long)task.state, err(task.error));
    P(@"events: %@", [recorder drain]);
    printNotes();

    NSURLSessionStreamTask *quiet = [session streamTaskWithHostName:@"127.0.0.1" port:port];
    [quiet resume];
    [quiet readDataOfMinLength:1 maxLength:64 timeout:0.3 completionHandler:^(NSData *data, BOOL atEOF, NSError *error) {
        P(@"read with nothing sent: %lu eof=%d error=%@", (unsigned long)data.length, atEOF, err(error));
        dispatch_semaphore_signal(done);
    }];
    await(done);
    [quiet cancel];
    settle(recorder);
    P(@"quiet state=%ld", (long)quiet.state);
    P(@"events: %@", [recorder drain]);
    printNotes();

    NSURLSessionStreamTask *captured = [session streamTaskWithHostName:@"localhost" port:port];
    [captured resume];
    [captured captureStreams];
    await(recorder.captured);
    [recorder.input open];
    [recorder.output open];
    for (int i = 0; i < 500 && (recorder.input.streamStatus != NSStreamStatusOpen || recorder.output.streamStatus != NSStreamStatusOpen); i++) usleep(10000);
    P(@"captured streams open=%d %d", recorder.input.streamStatus == NSStreamStatusOpen, recorder.output.streamStatus == NSStreamStatusOpen);
    P(@"captured wrote %ld", (long)[recorder.output write:(const uint8_t *)"cap\n" maxLength:4]);
    [recorder.output close];
    [recorder.input close];
    usleep(300000);
    P(@"captured state=%ld", (long)captured.state);
    P(@"events: %@", [recorder drain]);
    printNotes();
    close(listening);
}

static void textChecking(void) {
    NSRange r = NSMakeRange(2, 5);
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:1000000000];
    NSArray<NSTextCheckingResult *> *results = @[
        [NSTextCheckingResult addressCheckingResultWithRange:r components:@{NSTextCheckingCityKey: @"Lima", NSTextCheckingCountryKey: @"Peru"}],
        [NSTextCheckingResult correctionCheckingResultWithRange:r replacementString:@"fixed"],
        [NSTextCheckingResult correctionCheckingResultWithRange:r replacementString:@"fixed" alternativeStrings:@[@"fix", @"fixes"]],
        [NSTextCheckingResult dashCheckingResultWithRange:r replacementString:@"-"],
        [NSTextCheckingResult dateCheckingResultWithRange:r date:date],
        [NSTextCheckingResult dateCheckingResultWithRange:r date:date timeZone:[NSTimeZone timeZoneForSecondsFromGMT:3600] duration:90],
        [NSTextCheckingResult grammarCheckingResultWithRange:r details:@[@{@"NSGrammarCorrections": @[@"is"]}]],
        [NSTextCheckingResult linkCheckingResultWithRange:r URL:[NSURL URLWithString:@"https://example.com/a"]],
        [NSTextCheckingResult orthographyCheckingResultWithRange:r orthography:[NSOrthography defaultOrthographyForLanguage:@"ru"]],
        [NSTextCheckingResult phoneNumberCheckingResultWithRange:r phoneNumber:@"555-0100"],
        [NSTextCheckingResult quoteCheckingResultWithRange:r replacementString:@"'"],
        [NSTextCheckingResult replacementCheckingResultWithRange:r replacementString:@"swap"],
        [NSTextCheckingResult spellCheckingResultWithRange:r],
        [NSTextCheckingResult transitInformationCheckingResultWithRange:r components:@{NSTextCheckingAirlineKey: @"LA", NSTextCheckingFlightKey: @"2400"}],
    ];
    for (NSTextCheckingResult *result in results) {
        NSMutableArray *parts = [NSMutableArray arrayWithObject:[NSString stringWithFormat:@"type=%llu range=%@ n=%lu", (unsigned long long)result.resultType,
                                                                 range(result.range), (unsigned long)result.numberOfRanges]];
        NSDictionary *components = result.components;
        for (NSString *key in [components.allKeys sortedArrayUsingSelector:@selector(compare:)]) [parts addObject:[NSString stringWithFormat:@"%@:%@", key, components[key]]];
        if (result.addressComponents) [parts addObject:[NSString stringWithFormat:@"address=%lu", (unsigned long)result.addressComponents.count]];
        if (result.date) [parts addObject:[NSString stringWithFormat:@"date=%.0f", result.date.timeIntervalSince1970]];
        if (result.timeZone) [parts addObject:[NSString stringWithFormat:@"zone=%ld", (long)result.timeZone.secondsFromGMT]];
        if (result.duration) [parts addObject:[NSString stringWithFormat:@"duration=%g", result.duration]];
        if (result.URL) [parts addObject:result.URL.absoluteString];
        if (result.phoneNumber) [parts addObject:result.phoneNumber];
        if (result.replacementString) [parts addObject:[@"replace=" stringByAppendingString:result.replacementString]];
        if (result.alternativeStrings) [parts addObject:[result.alternativeStrings componentsJoinedByString:@"/"]];
        if (result.grammarDetails) [parts addObject:[NSString stringWithFormat:@"details=%lu", (unsigned long)result.grammarDetails.count]];
        if (result.orthography) [parts addObject:result.orthography.dominantScript];
        NSTextCheckingResult *moved = [result resultByAdjustingRangesWithOffset:10];
        [parts addObject:[NSString stringWithFormat:@"moved=%@/%llu/%@ named=%@ copy=%d", range(moved.range), (unsigned long long)moved.resultType,
                          moved.replacementString ?: moved.phoneNumber ?: moved.URL.absoluteString ?: @"-", range([result rangeWithName:@"x"]),
                          [result copy] == result]];
        print([parts componentsJoinedByString:@" "]);
    }
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(?<word>a)(b)?" options:0 error:nil];
    NSRange ranges[3] = {{0, 10}, {1, 2}, {NSNotFound, 0}};
    NSTextCheckingResult *match = [NSTextCheckingResult regularExpressionCheckingResultWithRanges:ranges count:3 regularExpression:regex];
    NSTextCheckingResult *moved = [match resultByAdjustingRangesWithOffset:5];
    P(@"regex type=%llu n=%lu ranges=%@ %@ %@ named=%@ moved=%@ %@ %@ named=%@ pattern=%@", (unsigned long long)match.resultType, (unsigned long)match.numberOfRanges,
      range([match rangeAtIndex:0]), range([match rangeAtIndex:1]), range([match rangeAtIndex:2]), range([match rangeWithName:@"word"]),
      range([moved rangeAtIndex:0]), range([moved rangeAtIndex:1]), range([moved rangeAtIndex:2]), range([moved rangeWithName:@"word"]), moved.regularExpression.pattern);
    NSTextCheckingResult *found = [regex firstMatchInString:@"xab" options:0 range:NSMakeRange(0, 3)];
    P(@"found components=%@ date=%@ replace=%@ n=%lu", found.components, found.date, found.replacementString, (unsigned long)found.numberOfRanges);
    P(@"keys %@ %@ %@ %@ %@ %@ %@ %@ %@ %@ %@", NSTextCheckingNameKey, NSTextCheckingJobTitleKey, NSTextCheckingOrganizationKey, NSTextCheckingStreetKey,
      NSTextCheckingCityKey, NSTextCheckingStateKey, NSTextCheckingZIPKey, NSTextCheckingCountryKey, NSTextCheckingPhoneKey, NSTextCheckingAirlineKey,
      NSTextCheckingFlightKey);
}

static NSString *tokens(NSLinguisticTagger *tagger, NSRange r, NSLinguisticTaggerUnit unit, NSLinguisticTagScheme scheme, NSLinguisticTaggerOptions options) {
    NSMutableArray *parts = [NSMutableArray array];
    NSString *string = tagger.string;
    [tagger enumerateTagsInRange:r unit:unit scheme:scheme options:options usingBlock:^(NSLinguisticTag tag, NSRange token, BOOL *stop) {
        NSString *piece = [[string substringWithRange:token] stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
        [parts addObject:[NSString stringWithFormat:@"<%@>%@", piece, tag ?: @"-"]];
    }];
    return [parts componentsJoinedByString:@" "];
}

static void tagger(void) {
    P(@"schemes fr word: %@", [[NSLinguisticTagger availableTagSchemesForUnit:NSLinguisticTaggerUnitWord language:@"fr"] componentsJoinedByString:@","]);
    P(@"schemes fr sentence: %@", [[NSLinguisticTagger availableTagSchemesForUnit:NSLinguisticTaggerUnitSentence language:@"fr"] componentsJoinedByString:@","]);
    P(@"schemes de: %@", [[NSLinguisticTagger availableTagSchemesForLanguage:@"de"] componentsJoinedByString:@","]);
    for (NSString *s in @[@"The dog is in the house and the cat is over there.", @"Le chat est sur la table avec les enfants.",
                          @"Der Hund ist nicht in dem Haus.", @"12345", @""])
        P(@"dominant '%@' = %@", s, [NSLinguisticTagger dominantLanguageForString:s]);

    NSString *string = @"The cat is on the mat, and it is happy!  Is the dog in the house?\nThe end.";
    NSArray *schemes = @[NSLinguisticTagSchemeTokenType, NSLinguisticTagSchemeLanguage, NSLinguisticTagSchemeScript, NSLinguisticTagSchemeLexicalClass];
    NSLinguisticTagger *t = [[NSLinguisticTagger alloc] initWithTagSchemes:schemes options:0];
    P(@"tagger schemes %@ string=%@ dominant=%@", [t.tagSchemes componentsJoinedByString:@","], t.string, t.dominantLanguage);
    t.string = string;
    P(@"dominant %@", t.dominantLanguage);
    NSRange all = NSMakeRange(0, string.length);
    P(@"words: %@", tokens(t, all, NSLinguisticTaggerUnitWord, NSLinguisticTagSchemeTokenType, 0));
    P(@"words omit whitespace: %@", tokens(t, all, NSLinguisticTaggerUnitWord, NSLinguisticTagSchemeTokenType, NSLinguisticTaggerOmitWhitespace));
    P(@"words omit words+whitespace: %@", tokens(t, all, NSLinguisticTaggerUnitWord, NSLinguisticTagSchemeTokenType,
                                                 NSLinguisticTaggerOmitWords | NSLinguisticTaggerOmitWhitespace));
    P(@"punctuation omitted: %@", tokens(t, NSMakeRange(0, 24), NSLinguisticTaggerUnitWord, NSLinguisticTagSchemeTokenType,
                                         NSLinguisticTaggerOmitPunctuation | NSLinguisticTaggerOmitWhitespace));
    P(@"scripts: %@", tokens(t, NSMakeRange(0, 24), NSLinguisticTaggerUnitWord, NSLinguisticTagSchemeScript, NSLinguisticTaggerOmitWhitespace));
    P(@"languages: %@", tokens(t, NSMakeRange(0, 24), NSLinguisticTaggerUnitWord, NSLinguisticTagSchemeLanguage, NSLinguisticTaggerOmitWhitespace));
    P(@"sentences: %@", tokens(t, all, NSLinguisticTaggerUnitSentence, NSLinguisticTagSchemeTokenType, 0));
    P(@"sentence scripts: %@", tokens(t, all, NSLinguisticTaggerUnitSentence, NSLinguisticTagSchemeScript, 0));
    P(@"paragraphs: %@", tokens(t, all, NSLinguisticTaggerUnitParagraph, NSLinguisticTagSchemeTokenType, 0));
    P(@"document: '%@'", tokens(t, all, NSLinguisticTaggerUnitDocument, NSLinguisticTagSchemeTokenType, 0));
    P(@"partial: %@", tokens(t, NSMakeRange(9, 12), NSLinguisticTaggerUnitWord, NSLinguisticTagSchemeTokenType, 0));
    P(@"partial sentences: %@", tokens(t, NSMakeRange(30, 15), NSLinguisticTaggerUnitSentence, NSLinguisticTagSchemeTokenType, 0));
    P(@"unrequested scheme: '%@'", tokens(t, all, NSLinguisticTaggerUnitWord, NSLinguisticTagSchemeLemma, 0));

    NSMutableArray *old = [NSMutableArray array];
    [t enumerateTagsInRange:NSMakeRange(38, 12) scheme:NSLinguisticTagSchemeTokenType options:NSLinguisticTaggerOmitWhitespace
                 usingBlock:^(NSLinguisticTag tag, NSRange token, NSRange sentence, BOOL *stop) {
        [old addObject:[NSString stringWithFormat:@"%@%@%@", range(token), tag, range(sentence)]];
        if (old.count == 4) *stop = YES;
    }];
    P(@"old enumeration: %@", [old componentsJoinedByString:@" "]);
    for (NSUInteger i = 0; i < string.length; i += 17) {
        NSRange token, sentence, word;
        NSString *tag = [t tagAtIndex:i scheme:NSLinguisticTagSchemeTokenType tokenRange:&token sentenceRange:&sentence];
        NSString *unitTag = [t tagAtIndex:i unit:NSLinguisticTaggerUnitWord scheme:NSLinguisticTagSchemeTokenType tokenRange:&word];
        P(@"at %lu: %@ %@ %@ %@ word=%@ sentence=%@ paragraph=%@ document=%@ script=%@", (unsigned long)i, tag, range(token), range(sentence), unitTag,
          range([t tokenRangeAtIndex:i unit:NSLinguisticTaggerUnitWord]), range([t tokenRangeAtIndex:i unit:NSLinguisticTaggerUnitSentence]),
          range([t tokenRangeAtIndex:i unit:NSLinguisticTaggerUnitParagraph]), range([t tokenRangeAtIndex:i unit:NSLinguisticTaggerUnitDocument]),
          [t tagAtIndex:i scheme:NSLinguisticTagSchemeScript tokenRange:NULL sentenceRange:NULL]);
    }
    P(@"sentence for range %@ %@ %@", range([t sentenceRangeForRange:NSMakeRange(3, 30)]), range([t sentenceRangeForRange:NSMakeRange(41, 0)]),
      range([t sentenceRangeForRange:NSMakeRange(string.length, 0)]));
    NSArray<NSValue *> *tokenRanges = nil;
    NSArray *tags = [t tagsInRange:NSMakeRange(0, 20) unit:NSLinguisticTaggerUnitWord scheme:NSLinguisticTagSchemeTokenType
                           options:NSLinguisticTaggerOmitWhitespace tokenRanges:&tokenRanges];
    NSMutableArray *rangeText = [NSMutableArray array];
    for (NSValue *v in tokenRanges) [rangeText addObject:range(v.rangeValue)];
    P(@"tags %@ ranges %@", [tags componentsJoinedByString:@","], [rangeText componentsJoinedByString:@","]);
    tags = [t tagsInRange:NSMakeRange(0, 8) scheme:NSLinguisticTagSchemeTokenType options:0 tokenRanges:&tokenRanges];
    [rangeText removeAllObjects];
    for (NSValue *v in tokenRanges) [rangeText addObject:range(v.rangeValue)];
    P(@"old tags %@ ranges %@", [tags componentsJoinedByString:@","], [rangeText componentsJoinedByString:@","]);
    NSArray<NSValue *> *scores = nil;
    NSRange token, sentence;
    NSArray *possible = [t possibleTagsAtIndex:4 scheme:NSLinguisticTagSchemeTokenType tokenRange:&token sentenceRange:&sentence scores:&scores];
    P(@"possible %@ scores %@ token %@ sentence %@", [possible componentsJoinedByString:@","], [scores componentsJoinedByString:@","], range(token), range(sentence));

    NSString *french = @"Le chat est sur la table : « oui » (peut-être) - bien ; le 3 $ ?";
    NSLinguisticTagger *f = [[NSLinguisticTagger alloc] initWithTagSchemes:@[NSLinguisticTagSchemeLexicalClass, NSLinguisticTagSchemeNameType,
                                                                             NSLinguisticTagSchemeLemma, NSLinguisticTagSchemeTokenType] options:0];
    f.string = french;
    [f setOrthography:[NSOrthography defaultOrthographyForLanguage:@"fr"] range:NSMakeRange(0, french.length)];
    NSRange whole = NSMakeRange(0, french.length);
    P(@"fr tokens: %@", tokens(f, whole, NSLinguisticTaggerUnitWord, NSLinguisticTagSchemeTokenType, NSLinguisticTaggerOmitWhitespace));
    P(@"fr lexical: %@", tokens(f, whole, NSLinguisticTaggerUnitWord, NSLinguisticTagSchemeLexicalClass, NSLinguisticTaggerOmitWhitespace));
    P(@"fr names: %@", tokens(f, whole, NSLinguisticTaggerUnitWord, NSLinguisticTagSchemeNameType, NSLinguisticTaggerOmitWhitespace));
    P(@"fr lemma: %@", tokens(f, NSMakeRange(0, 12), NSLinguisticTaggerUnitWord, NSLinguisticTagSchemeLemma, 0));
    NSRange effective;
    NSOrthography *o = [f orthographyAtIndex:3 effectiveRange:&effective];
    P(@"fr orthography %@ %@ %@", o.dominantScript, o.dominantLanguage, range(effective));

    P(@"class tag %@", [NSLinguisticTagger tagForString:string atIndex:7 unit:NSLinguisticTaggerUnitWord scheme:NSLinguisticTagSchemeTokenType
                                            orthography:nil tokenRange:&token]);
    tags = [NSLinguisticTagger tagsForString:string range:all unit:NSLinguisticTaggerUnitSentence scheme:NSLinguisticTagSchemeTokenType
                                     options:0 orthography:nil tokenRanges:&tokenRanges];
    P(@"class tags %@ count %lu", [tags componentsJoinedByString:@","], (unsigned long)tokenRanges.count);
    NSMutableArray *classTokens = [NSMutableArray array];
    [NSLinguisticTagger enumerateTagsForString:@"One, two" range:NSMakeRange(0, 8) unit:NSLinguisticTaggerUnitWord scheme:NSLinguisticTagSchemeTokenType
                                       options:0 orthography:nil usingBlock:^(NSLinguisticTag tag, NSRange r, BOOL *stop) {
        [classTokens addObject:[NSString stringWithFormat:@"%@%@", tag, range(r)]];
    }];
    P(@"class enumeration %@", [classTokens componentsJoinedByString:@" "]);
    P(@"class language %@", [NSLinguisticTagger tagForString:@"Hi. Yo" atIndex:4 unit:NSLinguisticTaggerUnitWord scheme:NSLinguisticTagSchemeLanguage
                                                  orthography:[NSOrthography defaultOrthographyForLanguage:@"de"] tokenRange:&token]);

    NSMutableString *edited = [NSMutableString stringWithString:@"One two."];
    NSLinguisticTagger *e = [[NSLinguisticTagger alloc] initWithTagSchemes:@[NSLinguisticTagSchemeTokenType] options:0];
    e.string = edited;
    [edited appendString:@" Three"];
    [e stringEditedInRange:NSMakeRange(8, 6) changeInLength:6];
    P(@"edited: %@", tokens(e, NSMakeRange(0, edited.length), NSLinguisticTaggerUnitWord, NSLinguisticTagSchemeTokenType, NSLinguisticTaggerOmitWhitespace));
}

static void orthographies(void) {
    NSOrthography *o = [NSOrthography orthographyWithDominantScript:@"Latn" languageMap:@{@"Latn": @[@"en", @"fr"], @"Cyrl": @[@"ru"]}];
    P(@"orthography %@ %@ scripts=%@ languages=%@ cyrl=%@ %@ grek=%@", o.dominantScript, o.dominantLanguage, [o.allScripts componentsJoinedByString:@","],
      [o.allLanguages componentsJoinedByString:@","], [[o languagesForScript:@"Cyrl"] componentsJoinedByString:@","], [o dominantLanguageForScript:@"Cyrl"],
      [o dominantLanguageForScript:@"Grek"]);
    for (NSString *language in @[@"en", @"ja", @"zh-Hant", @"ru", @"ar", @"ko", @"el", @"he", @"hi", @"th", @"und"]) {
        NSOrthography *d = [NSOrthography defaultOrthographyForLanguage:language];
        P(@"default %@: %@ %@ %@", language, d.dominantScript, d.dominantLanguage, [[d languagesForScript:d.dominantScript] componentsJoinedByString:@","]);
    }
    NSOrthography *copy = [o copy];
    NSOrthography *same = [[NSOrthography alloc] initWithDominantScript:@"Latn" languageMap:@{@"Latn": @[@"en", @"fr"], @"Cyrl": @[@"ru"]}];
    P(@"copy identical=%d equal=%d hash=%d different=%d", copy == o, [same isEqual:o], same.hash == o.hash,
      [o isEqual:[NSOrthography defaultOrthographyForLanguage:@"en"]]);
    NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:o requiringSecureCoding:YES error:nil];
    NSOrthography *decoded = [NSKeyedUnarchiver unarchivedObjectOfClass:NSOrthography.class fromData:archive error:nil];
    P(@"secure=%d decoded %@ %@ equal=%d", NSOrthography.supportsSecureCoding, decoded.dominantScript,
      [[decoded languagesForScript:@"Latn"] componentsJoinedByString:@","], [decoded isEqual:o]);
    NSOrthography *empty = [NSOrthography orthographyWithDominantScript:@"Zyyy" languageMap:@{}];
    P(@"empty %@ %@ scripts=%@ languages=%lu", empty.dominantScript, empty.dominantLanguage, [empty.allScripts componentsJoinedByString:@","],
      (unsigned long)empty.allLanguages.count);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        signal(SIGPIPE, SIG_IGN);
        serverNotes = [NSMutableArray array];
        Recorder *recorder = [Recorder new];
        NSOperationQueue *queue = [NSOperationQueue new];
        queue.maxConcurrentOperationCount = 1;
        NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration
                                                              delegate:recorder delegateQueue:queue];
        NSURLSession *plain = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];
        configurations(plain);
        cookies(plain);
        [plain invalidateAndCancel];
        webSockets(session, recorder);
        streams(session, recorder);
        [session invalidateAndCancel];
        textChecking();
        tagger();
        orthographies();
    }
    return 0;
}
