// ppc Mac code that Linux's libraries and Perry's providers call: qsort's
// and bsearch's comparators, threads' start routines, a thread-specific
// value's destructor, pthread_once's and dispatch_once's initializers,
// atexit's handler, dispatch's blocks and functions, and a signal handler,
// each of which changes r2 (Linux's thread pointer, which Apple's GCC uses as
// a scratch register); a signal that arrives while r2 is changed; and
// NSInvocation and key-value coding with doubles, floats, long longs and
// structures, which Darwin's ppc ABI passes in its own places.
//
// Built by Xcode 3.2.6's ppc GCC against the 10.6 SDK
// (Scripts/build-ppc-fixtures.sh ppc_runtime.m).
#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/time.h>

// Later than the 10.6 SDK's headers; Perry's libdispatch has it.
void dispatch_barrier_sync_f(dispatch_queue_t queue, void *context, dispatch_function_t work);

// What Apple's GCC may leave in r2.
#define SCRATCH_R2() __asm__ volatile("li r2, 0x5a5a" : : : "r2")

static int compare(const void *a, const void *b) {
    SCRATCH_R2();
    int x = *(const int *)a, y = *(const int *)b;
    return x < y ? -1 : x > y;
}

static void *start(void *argument) {
    SCRATCH_R2();
    return (char *)argument + 1;
}

static int destroyed;
static void destroy(void *value) {
    SCRATCH_R2();
    destroyed += *(int *)value;
}

static pthread_key_t specific;
static void *keep(void *value) {
    pthread_setspecific(specific, value);
    return 0;
}

static int initialized;
static void initialize(void) {
    SCRATCH_R2();
    initialized++;
}

static void finish(void) {
    SCRATCH_R2();
    printf("atexit\n");
}

static volatile int work;
static void count(void *context) {
    SCRATCH_R2();
    __sync_fetch_and_add(&work, *(int *)context);
}

static void countIndex(void *context, size_t index) {
    SCRATCH_R2();
    __sync_fetch_and_add((int *)context, (int)index);
}

static volatile int signalled;
static volatile double signalled_value;
static void handler(int signal, siginfo_t *info, void *context) {
    SCRATCH_R2();
    signalled_value = signal * 1.5;
    signalled++;
}

static volatile int alarmed;
static void alarm_handler(int signal) {
    alarmed++;
}

// Arguments and results in each of Darwin's places.
@interface Target : NSObject {
    double weight;
    float ratio;
    long long big;
    NSRect frame;
}
- (double)scale:(double)a by:(int)b plus:(float)c rect:(NSRect)r big:(long long)q;
- (float)halve:(float)a;
- (NSRect)rectScaled:(float)s;
- (double)weight;
- (void)setWeight:(double)value;
- (float)ratio;
- (void)setRatio:(float)value;
- (long long)big;
- (void)setBig:(long long)value;
- (NSRect)frame;
- (void)setFrame:(NSRect)value;
@end

@implementation Target
- (double)scale:(double)a by:(int)b plus:(float)c rect:(NSRect)r big:(long long)q {
    return a * b + c + r.origin.x + r.origin.y + r.size.width + r.size.height + (double)q;
}
- (float)halve:(float)a { return a / 2; }
- (NSRect)rectScaled:(float)s { return NSMakeRect(s, 2 * s, 3 * s, 4 * s); }
- (double)weight { return weight; }
- (void)setWeight:(double)value { weight = value; }
- (float)ratio { return ratio; }
- (void)setRatio:(float)value { ratio = value; }
- (long long)big { return big; }
- (void)setBig:(long long)value { big = value; }
- (NSRect)frame { return frame; }
- (void)setFrame:(NSRect)value { frame = value; }
@end

static void invocations(void) {
    Target *target = [[Target alloc] init];
    NSInvocation *invocation =
        [NSInvocation invocationWithMethodSignature:[target methodSignatureForSelector:@selector(scale:by:plus:rect:big:)]];
    [invocation setTarget:target];
    [invocation setSelector:@selector(scale:by:plus:rect:big:)];
    double a = 1.5;
    int b = 4;
    float c = 0.25f;
    NSRect r = NSMakeRect(1, 2, 3, 4);
    long long q = 1000;
    [invocation setArgument:&a atIndex:2];
    [invocation setArgument:&b atIndex:3];
    [invocation setArgument:&c atIndex:4];
    [invocation setArgument:&r atIndex:5];
    [invocation setArgument:&q atIndex:6];
    [invocation invoke];
    double scaled = 0;
    [invocation getReturnValue:&scaled];

    invocation = [NSInvocation invocationWithMethodSignature:[target methodSignatureForSelector:@selector(halve:)]];
    [invocation setTarget:target];
    [invocation setSelector:@selector(halve:)];
    float five = 5;
    [invocation setArgument:&five atIndex:2];
    [invocation invoke];
    float half = 0;
    [invocation getReturnValue:&half];

    invocation = [NSInvocation invocationWithMethodSignature:[target methodSignatureForSelector:@selector(rectScaled:)]];
    [invocation setTarget:target];
    [invocation setSelector:@selector(rectScaled:)];
    float s = 1.5f;
    [invocation setArgument:&s atIndex:2];
    [invocation invoke];
    NSRect rect = NSZeroRect;
    [invocation getReturnValue:&rect];
    printf("invoke %g %g {%g %g %g %g}\n", scaled, half, rect.origin.x, rect.origin.y, rect.size.width,
           rect.size.height);

    [target setValue:[NSNumber numberWithDouble:2.5] forKey:@"weight"];
    [target setValue:[NSNumber numberWithFloat:0.125f] forKey:@"ratio"];
    [target setValue:[NSNumber numberWithLongLong:123456789012LL] forKey:@"big"];
    [target setValue:[NSValue valueWithRect:NSMakeRect(5, 6, 7, 8)] forKey:@"frame"];
    printf("set %g %g %lld {%g %g %g %g}\n", [target weight], [target ratio], [target big], [target frame].origin.x,
           [target frame].origin.y, [target frame].size.width, [target frame].size.height);
    NSRect got = [[target valueForKey:@"frame"] rectValue];
    printf("get %g %g %lld {%g %g %g %g}\n", [[target valueForKey:@"weight"] doubleValue],
           [[target valueForKey:@"ratio"] floatValue], [[target valueForKey:@"big"] longLongValue], got.origin.x,
           got.origin.y, got.size.width, got.size.height);
    [target release];
}

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int numbers[200];
    for (int i = 0, n = 0; i < 200; i++, n = (n + 119) % 200)
        numbers[i] = n;
    qsort(numbers, 200, sizeof(int), compare);
    int sorted = 1;
    for (int i = 0; i < 200; i++)
        sorted &= numbers[i] == i;
    int key = 123;
    int *found = bsearch(&key, numbers, 200, sizeof(int), compare);
    printf("qsort %d bsearch %d\n", sorted, found ? (int)(found - numbers) : -1);

    char text[] = "thread";
    pthread_t threads[4];
    for (int i = 0; i < 4; i++)
        pthread_create(&threads[i], NULL, start, text + i);
    for (int i = 0; i < 4; i++) {
        void *result;
        pthread_join(threads[i], &result);
        printf(i ? " %s" : "%s", (char *)result);
    }
    printf("\n");

    pthread_key_create(&specific, destroy);
    static int values[4] = { 1, 2, 3, 4 };
    for (int i = 0; i < 4; i++) {
        pthread_t thread;
        pthread_create(&thread, NULL, keep, &values[i]);
        pthread_join(thread, NULL);
    }
    printf("destroyed %d\n", destroyed);

    static pthread_once_t once = PTHREAD_ONCE_INIT;
    pthread_once(&once, initialize);
    pthread_once(&once, initialize);
    static dispatch_once_t dispatched;
    dispatch_once(&dispatched, ^{
        SCRATCH_R2();
        initialized += 10;
    });
    dispatch_once(&dispatched, ^{ initialized += 100; });
    printf("once %d\n", initialized);
    atexit(finish);

    dispatch_queue_t serial = dispatch_queue_create("serial", NULL);
    dispatch_queue_t global = dispatch_get_global_queue(0, 0);
    int one = 1, ten = 10, hundred = 100;
    dispatch_sync_f(serial, &one, count);
    dispatch_barrier_sync_f(serial, &ten, count);
    dispatch_sync(serial, ^{
        SCRATCH_R2();
        work += 1000;
    });
    for (int i = 0; i < 50; i++)
        dispatch_async_f(serial, &hundred, count);
    for (int i = 0; i < 50; i++)
        dispatch_async(global, ^{
            SCRATCH_R2();
            __sync_fetch_and_add(&work, 10000);
        });
    dispatch_group_t group = dispatch_group_create();
    for (int i = 0; i < 20; i++) {
        dispatch_group_async(group, global, ^{
            SCRATCH_R2();
            __sync_fetch_and_add(&work, 1000000);
        });
        dispatch_group_async_f(group, serial, &one, count);
    }
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    __block int indexes = 0;
    dispatch_apply(10, global, ^(size_t index) {
        SCRATCH_R2();
        __sync_fetch_and_add(&indexes, (int)index);
    });
    dispatch_apply_f(10, global, &indexes, countIndex);
    dispatch_sync(serial, ^{});
    while (work != 1 + 10 + 1000 + 5000 + 500000 + 20000000 + 20)
        ;
    printf("work %d indexes %d\n", work, indexes);

    struct sigaction action;
    action.sa_sigaction = handler;
    action.sa_flags = SA_SIGINFO;
    sigemptyset(&action.sa_mask);
    sigaction(SIGUSR1, &action, NULL);
    raise(SIGUSR1);
    // A signal that comes while this code has changed r2.
    signal(SIGALRM, alarm_handler);
    struct itimerval timer = { { 0, 0 }, { 0, 20000 } };
    setitimer(ITIMER_REAL, &timer, NULL);
    while (!alarmed)
        SCRATCH_R2();
    printf("signal %d %g alarm %d\n", signalled, signalled_value, alarmed);

    invocations();
    [pool release];
    return 0;
}
