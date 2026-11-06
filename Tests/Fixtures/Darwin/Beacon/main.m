// NSNetService and NSNetServiceBrowser: TXT record conversions, publishing
// a service, finding it with a browser, resolving its host, port, TXT
// record and addresses, a resolution that times out, a search with a bad
// type, and stopping, in one strict order. Every line is the same on
// Darwin and under Perry, whatever the machine's name and addresses.

#import <Foundation/Foundation.h>
#if TARGET_OS_IPHONE
#import <CFNetwork/CFNetwork.h>
#else
#import <CoreServices/CoreServices.h>
#endif
#include <stdio.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static NSString *hex(NSData *data) {
    NSMutableString *string = [NSMutableString string];
    const uint8_t *bytes = data.bytes;
    for (NSUInteger index = 0; index < data.length; index++) [string appendFormat:@"%02x", bytes[index]];
    return string;
}

static NSString *errorNumbers(NSDictionary *errorDict) {
    return [NSString stringWithFormat:@"code %@ domain %@", errorDict[@"NSNetServicesErrorCode"],
            errorDict[@"NSNetServicesErrorDomain"]];
}

static NSString *txtSummary(NSData *data) {
    NSDictionary *txt = [NSNetService dictionaryFromTXTRecordData:data];
    NSData *key = txt[@"key"];
    return [NSString stringWithFormat:@"count %lu, key '%@', n null %d", (unsigned long)txt.count,
            [[NSString alloc] initWithData:key encoding:NSUTF8StringEncoding], txt[@"n"] == [NSNull null]];
}

@interface Beacon : NSObject <NSNetServiceDelegate, NSNetServiceBrowserDelegate>
@property (strong) NSNetService *published, *found, *ghost;
@end
static void cfTests(Beacon *beacon);
@interface Beacon ()
@property (strong) NSNetServiceBrowser *browser, *badBrowser;
@property BOOL resolved, done;
@end

@implementation Beacon

- (void)netServiceWillPublish:(NSNetService *)service {
    say([NSString stringWithFormat:@"willPublish '%@' '%@' '%@' port %ld", service.name, service.type,
         service.domain, (long)service.port]);
}

- (void)netServiceDidPublish:(NSNetService *)service {
    say([NSString stringWithFormat:@"didPublish '%@' '%@' '%@' port %ld", service.name, service.type,
         service.domain, (long)service.port]);
    self.browser = [[NSNetServiceBrowser alloc] init];
    self.browser.delegate = self;
    [self.browser searchForServicesOfType:@"_perry7b3f._tcp." inDomain:@""];
}

- (void)netService:(NSNetService *)service didNotPublish:(NSDictionary *)errorDict {
    say([NSString stringWithFormat:@"didNotPublish %@", errorNumbers(errorDict)]);
    self.done = YES;
}

- (void)netServiceBrowserWillSearch:(NSNetServiceBrowser *)browser {
    say(@"willSearch");
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didFindService:(NSNetService *)service moreComing:(BOOL)moreComing {
    if (![service.name isEqual:@"Beacon Fixture"] || self.found) return;
    say([NSString stringWithFormat:@"didFind '%@' '%@' '%@' port %ld, hostName null %d", service.name, service.type,
         service.domain, (long)service.port, service.hostName == nil]);
    self.found = service;
    service.delegate = self;
    [service resolveWithTimeout:10.0];
}

- (void)netServiceWillResolve:(NSNetService *)service {
    say([NSString stringWithFormat:@"willResolve '%@'", service.name]);
}

- (void)netServiceDidResolveAddress:(NSNetService *)service {
    if (self.resolved) return;
    self.resolved = YES;
    NSData *ipv4 = nil;
    for (NSData *address in service.addresses) {
        const uint8_t *bytes = address.bytes;
        if (address.length >= 2 && bytes[1] == 2) { ipv4 = address; break; }
    }
    NSString *sockaddr = @"none";
    if (ipv4) {
        const uint8_t *bytes = ipv4.bytes;
        sockaddr = [NSString stringWithFormat:@"len %u family %u port %u", bytes[0], bytes[1],
                    (bytes[2] << 8) | bytes[3]];
    }
    say([NSString stringWithFormat:@"didResolve '%@' port %ld, host in local. %d, txt %@, ipv4 %d, sockaddr %@",
         service.name, (long)service.port, [service.hostName hasSuffix:@".local."], txtSummary(service.TXTRecordData),
         ipv4 != nil, sockaddr]);
    self.ghost = [[NSNetService alloc] initWithDomain:@"local." type:@"_perry7b3f._tcp." name:@"Ghost 7b3f"];
    self.ghost.delegate = self;
    [self.ghost resolveWithTimeout:1.0];
}

- (void)netService:(NSNetService *)service didNotResolve:(NSDictionary *)errorDict {
    say([NSString stringWithFormat:@"didNotResolve %@", errorNumbers(errorDict)]);
    self.badBrowser = [[NSNetServiceBrowser alloc] init];
    self.badBrowser.delegate = self;
    [self.badBrowser searchForServicesOfType:@"not a type" inDomain:@"local."];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didNotSearch:(NSDictionary *)errorDict {
    say([NSString stringWithFormat:@"didNotSearch %@", errorNumbers(errorDict)]);
    [self.browser stop];
}

- (void)netServiceBrowserDidStopSearch:(NSNetServiceBrowser *)browser {
    say(@"didStopSearch");
    cfTests(self);
}

- (void)netServiceDidStop:(NSNetService *)service {
    say([NSString stringWithFormat:@"serviceDidStop '%@'", service.name]);
    self.done = YES;
}

@end

// MARK: - CFNetService

static Beacon *cfBeacon;
static CFNetServiceBrowserRef cfBrowser;
static BOOL cfFound;

static NSString *cfError(CFStreamError error) {
    return [NSString stringWithFormat:@"code %d domain %ld", (int)error.error, (long)error.domain];
}

static void cfBrowseReply(CFNetServiceBrowserRef browser, CFOptionFlags flags, CFTypeRef domainOrService,
                          CFStreamError *error, void *info) {
    if (!domainOrService) {
        // The stop's acknowledgement.
        say([NSString stringWithFormat:@"cf didStopSearch flags %lu %@", (unsigned long)flags,
             error ? cfError(*error) : @"no error"]);
        CFNetServiceBrowserInvalidate(browser);
        CFRelease(browser);
        [cfBeacon.published stop];
        return;
    }
    if (flags & kCFNetServiceFlagRemove || flags & kCFNetServiceFlagIsDomain) return;
    CFNetServiceRef service = (CFNetServiceRef)domainOrService;
    NSString *name = (__bridge NSString *)CFNetServiceGetName(service);
    if (![name isEqual:@"Beacon Fixture"] || cfFound) return;
    cfFound = YES;
    say([NSString stringWithFormat:@"cf found '%@' '%@' '%@' port %d", name,
         (__bridge NSString *)CFNetServiceGetType(service), (__bridge NSString *)CFNetServiceGetDomain(service),
         (int)CFNetServiceGetPortNumber(service)]);
    CFStreamError stopError = {0, 0};
    CFNetServiceBrowserStopSearch(browser, &stopError);
}

static void cfTests(Beacon *beacon) {
    cfBeacon = beacon;
    // TXT records through CFNetwork's conversions.
    NSDictionary *txt = @{@"key": [@"value" dataUsingEncoding:NSUTF8StringEncoding], @"n": [NSData data]};
    NSData *data = CFBridgingRelease(CFNetServiceCreateTXTDataWithDictionary(NULL, (__bridge CFDictionaryRef)txt));
    say([NSString stringWithFormat:@"cf txt data %@", hex(data)]);
    NSDictionary *decoded = CFBridgingRelease(CFNetServiceCreateDictionaryWithTXTData(NULL, (__bridge CFDataRef)data));
    NSData *key = decoded[@"key"];
    say([NSString stringWithFormat:@"cf txt dict count %lu, key '%@', n null %d", (unsigned long)decoded.count,
         [[NSString alloc] initWithData:key encoding:NSUTF8StringEncoding], decoded[@"n"] == (id)kCFNull]);

    // A blocking resolution of the published service.
    CFNetServiceRef service = CFNetServiceCreate(NULL, CFSTR("local."), CFSTR("_perry7b3f._tcp."),
                                                 CFSTR("Beacon Fixture"), 0);
    CFStreamError error = {0, 0};
    Boolean resolved = CFNetServiceResolveWithTimeout(service, 10.0, &error);
    NSArray *addresses = (__bridge NSArray *)CFNetServiceGetAddressing(service);
    NSData *ipv4 = nil;
    for (NSData *address in addresses) {
        const uint8_t *bytes = address.bytes;
        if (address.length >= 2 && bytes[1] == 2) { ipv4 = address; break; }
    }
    NSString *host = (__bridge NSString *)CFNetServiceGetTargetHost(service);
    NSDictionary *resolvedTXT = CFBridgingRelease(CFNetServiceCreateDictionaryWithTXTData(NULL,
        CFNetServiceGetTXTData(service)));
    say([NSString stringWithFormat:@"cf resolve %d %@, port %d, host in local. %d, txt count %lu, ipv4 %d",
         resolved, cfError(error), (int)CFNetServiceGetPortNumber(service), [host hasSuffix:@".local."],
         (unsigned long)resolvedTXT.count, ipv4 != nil]);
    CFRelease(service);

    // An asynchronous search, stopped at the first find.
    CFNetServiceClientContext context = {0, NULL, NULL, NULL, NULL};
    cfBrowser = CFNetServiceBrowserCreate(NULL, cfBrowseReply, &context);
    CFNetServiceBrowserScheduleWithRunLoop(cfBrowser, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    CFStreamError searchError = {0, 0};
    Boolean searching = CFNetServiceBrowserSearchForServices(cfBrowser, CFSTR(""), CFSTR("_perry7b3f._tcp."),
                                                             &searchError);
    say([NSString stringWithFormat:@"cf searching %d %@", searching, cfError(searchError)]);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // TXT records, with no network: a dictionary encoded and decoded,
        // an empty one, and a bare key.
        NSDictionary *txt = @{@"key": [@"value" dataUsingEncoding:NSUTF8StringEncoding], @"n": [NSData data]};
        NSData *data = [NSNetService dataFromTXTRecordDictionary:txt];
        say([NSString stringWithFormat:@"txt data %@", hex(data)]);
        say([NSString stringWithFormat:@"txt dict %@", txtSummary(data)]);
        say([NSString stringWithFormat:@"txt empty data null %d, dict null %d",
             [NSNetService dataFromTXTRecordDictionary:@{}] == nil,
             [NSNetService dictionaryFromTXTRecordData:[NSData data]] == nil]);
        uint8_t bare[] = {3, 'a', 'b', 'c'};
        NSDictionary *bareDict = [NSNetService dictionaryFromTXTRecordData:[NSData dataWithBytes:bare length:4]];
        say([NSString stringWithFormat:@"txt bare count %lu, abc null %d", (unsigned long)bareDict.count,
             bareDict[@"abc"] == [NSNull null]]);

        Beacon *beacon = [Beacon new];
        NSNetService *service = [[NSNetService alloc] initWithDomain:@"" type:@"_perry7b3f._tcp."
                                                                name:@"Beacon Fixture" port:7777];
        say([NSString stringWithFormat:@"initial '%@' '%@' '%@' port %ld, hostName null %d, addresses %lu",
             service.name, service.type, service.domain, (long)service.port, service.hostName == nil,
             (unsigned long)service.addresses.count]);
        service.delegate = beacon;
        beacon.published = service;
        [service setTXTRecordData:data];
        [service publish];

        NSDate *guard = [NSDate dateWithTimeIntervalSinceNow:25];
        while (!beacon.done && guard.timeIntervalSinceNow > 0)
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        say(beacon.done ? @"end" : @"timed out");
    }
    return 0;
}
