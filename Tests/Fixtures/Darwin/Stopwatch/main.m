// Times the calls apps make most, one case at a time, and prints a line
// per case: its name and the nanoseconds an operation takes. Each case
// runs until it has taken a quarter of a second, so a slow Perry and a
// fast Mac both time enough operations to be steady. With the argument
// "startup" it prints nothing and exits at once, so the time a whole run
// takes is the time from the process's start to main
// (Scripts/perry-bench.sh). Its output depends on the machine, so it
// records no reference.
#import <Foundation/Foundation.h>
#import <time.h>

id objc_retain(id object);
void objc_release(id object);

@interface Target : NSObject
- (NSUInteger)value;
@end

@implementation Target
- (NSUInteger)value { return 1; }
@end

static uint64_t now(void) {
    struct timespec time;
    clock_gettime(CLOCK_MONOTONIC, &time);
    return (uint64_t)time.tv_sec * 1000000000 + (uint64_t)time.tv_nsec;
}

// Where results go, so the compiler keeps the work that makes them.
static volatile NSUInteger sink;

/// Runs `body` with a count of operations, doubling it until a run takes a
/// quarter of a second, and prints that run's nanoseconds per operation.
static void measure(const char *name, void (^body)(NSUInteger count)) {
    NSUInteger count = 1000;
    for (;;) {
        uint64_t start = now();
        @autoreleasepool { body(count); }
        uint64_t elapsed = now() - start;
        if (elapsed >= 250000000 || count >= ((NSUInteger)1 << 30)) {
            printf("%s %.1f\n", name, (double)elapsed / (double)count);
            fflush(stdout);
            return;
        }
        count *= 2;
    }
}

int main(int argc, char *argv[]) {
    if (argc > 1 && strcmp(argv[1], "startup") == 0) return 0;
    @autoreleasepool {
        Target *target = [[Target alloc] init];
        measure("send_app", ^(NSUInteger count) {
            for (NSUInteger i = 0; i < count; i++) sink += [target value];
        });

        NSString *text = @"stopwatch";
        measure("send_swift", ^(NSUInteger count) {
            for (NSUInteger i = 0; i < count; i++) sink += text.length;
        });

        NSObject *object = [[NSObject alloc] init];
        measure("retain_release", ^(NSUInteger count) {
            for (NSUInteger i = 0; i < count; i++) objc_release(objc_retain(object));
        });

        measure("alloc_init", ^(NSUInteger count) {
            for (NSUInteger i = 0; i < count; i++) {
                NSObject *made = [[NSObject alloc] init];
                sink += made != nil;
            }
        });

        __weak NSObject *weak = object;
        measure("weak_load", ^(NSUInteger count) {
            for (NSUInteger i = 0; i < count; i++) {
                NSObject *loaded = weak;
                sink += loaded != nil;
            }
        });

        measure("string_bridge", ^(NSUInteger count) {
            for (NSUInteger i = 0; i < count; i++) {
                @autoreleasepool {
                    NSString *made = [NSString stringWithUTF8String:"stopwatch"];
                    sink += (NSUInteger)made.UTF8String[0];
                }
            }
        });
    }
    return 0;
}
