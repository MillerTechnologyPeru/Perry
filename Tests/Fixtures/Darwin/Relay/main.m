// Grand Central Dispatch: serial and concurrent queues, the main queue
// with the run loop, sync, barriers, groups, semaphores, dispatch_after,
// dispatch_apply, queue-specific data, target queues, suspension, sources
// (timers, data merging, cancellation), dispatch blocks and dispatch data.

#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include <stdio.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static NSString *label(void) {
    const char *name = dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL);
    return name ? @(name) : @"(null)";
}

static void countUp(void *context) {
    (*(int *)context)++;
}

static void serialQueues(void) {
    dispatch_queue_t queue = dispatch_queue_create("org.perry.serial", DISPATCH_QUEUE_SERIAL);
    NSMutableArray *order = [NSMutableArray array];
    for (int i = 0; i < 5; i++) {
        dispatch_async(queue, ^{ [order addObject:@(i)]; });
    }
    __block NSString *inside = nil;
    __block BOOL main = YES;
    dispatch_sync(queue, ^{
        inside = label();
        main = NSThread.isMainThread;
    });
    say([NSString stringWithFormat:@"serial: %@, label %@, main thread %d",
         [order componentsJoinedByString:@","], inside, main]);
    say([NSString stringWithFormat:@"outside label: %@", label()]);

    int counter = 0;
    dispatch_sync_f(queue, &counter, countUp);
    dispatch_async_f(queue, &counter, countUp);
    dispatch_sync(queue, ^{});
    say([NSString stringWithFormat:@"function variants: %d", counter]);
}

static void concurrentQueues(void) {
    dispatch_queue_t queue = dispatch_queue_create("org.perry.concurrent", DISPATCH_QUEUE_CONCURRENT);
    NSMutableArray *values = [NSMutableArray array];
    NSLock *lock = [NSLock new];
    for (int i = 0; i < 20; i++) {
        dispatch_async(queue, ^{
            [lock lock];
            [values addObject:@(i)];
            [lock unlock];
        });
    }
    __block NSUInteger atBarrier = 0;
    dispatch_barrier_async(queue, ^{ atBarrier = values.count; });
    dispatch_barrier_sync(queue, ^{});
    NSArray *sorted = [values sortedArrayUsingSelector:@selector(compare:)];
    say([NSString stringWithFormat:@"concurrent: %lu values, sum %@, barrier saw %lu",
         (unsigned long)values.count, [sorted valueForKeyPath:@"@sum.self"], (unsigned long)atBarrier]);
}

static void globalQueues(void) {
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    dispatch_queue_t same = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    dispatch_queue_t priority = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    __block NSString *inside = nil;
    dispatch_sync(queue, ^{ inside = label(); });
    say([NSString stringWithFormat:@"global: %@, same object %d, default %s, qos %d",
         inside, queue == same, dispatch_queue_get_label(priority),
         dispatch_queue_get_qos_class(dispatch_queue_create("q", dispatch_queue_attr_make_with_qos_class(
             DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0)), NULL) == QOS_CLASS_USER_INITIATED]);
}

static void groups(void) {
    dispatch_group_t group = dispatch_group_create();
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0);
    __block int done = 0;
    NSLock *lock = [NSLock new];
    for (int i = 0; i < 8; i++) {
        dispatch_group_async(group, queue, ^{
            usleep(1000);
            [lock lock];
            done++;
            [lock unlock];
        });
    }
    dispatch_group_enter(group);
    dispatch_async(queue, ^{
        usleep(5000);
        [lock lock];
        done += 10;
        [lock unlock];
        dispatch_group_leave(group);
    });
    long waited = dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    say([NSString stringWithFormat:@"group: waited %ld, done %d", waited, done]);

    dispatch_group_enter(group);
    long timedOut = dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_MSEC));
    dispatch_semaphore_t notified = dispatch_semaphore_create(0);
    dispatch_group_notify(group, queue, ^{ dispatch_semaphore_signal(notified); });
    dispatch_group_leave(group);
    dispatch_semaphore_wait(notified, DISPATCH_TIME_FOREVER);
    say([NSString stringWithFormat:@"group: timed out %d, notified", timedOut != 0]);
}

static void semaphores(void) {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(2);
    long first = dispatch_semaphore_wait(semaphore, DISPATCH_TIME_NOW);
    long second = dispatch_semaphore_wait(semaphore, DISPATCH_TIME_NOW);
    long third = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_MSEC));
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        usleep(2000);
        dispatch_semaphore_signal(semaphore);
    });
    long fourth = dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    dispatch_semaphore_signal(semaphore);
    dispatch_semaphore_signal(semaphore);
    say([NSString stringWithFormat:@"semaphore: %ld %ld %d %ld", first, second, third != 0, fourth]);
}

static void applying(void) {
    __block long total = 0;
    NSLock *lock = [NSLock new];
    dispatch_apply(100, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^(size_t index) {
        [lock lock];
        total += (long)index;
        [lock unlock];
    });
    __block long serial = 0;
    dispatch_apply(10, DISPATCH_APPLY_AUTO, ^(size_t index) {
        [lock lock];
        serial += (long)index;
        [lock unlock];
    });
    say([NSString stringWithFormat:@"apply: %ld, %ld", total, serial]);
}

static char queueKey;
static char otherKey;

static void releaseString(void *context) {
    CFRelease(context);
}

static void specifics(void) {
    dispatch_queue_t target = dispatch_queue_create("org.perry.target", DISPATCH_QUEUE_SERIAL);
    dispatch_queue_set_specific(target, &queueKey, (void *)CFBridgingRetain(@"target value"), releaseString);
    dispatch_queue_t child = dispatch_queue_create("org.perry.child", DISPATCH_QUEUE_SERIAL);
    dispatch_set_target_queue(child, target);
    __block NSString *fromChild = nil, *missing = nil;
    dispatch_sync(child, ^{
        fromChild = (__bridge NSString *)dispatch_get_specific(&queueKey);
        missing = (__bridge NSString *)dispatch_get_specific(&otherKey);
    });
    NSString *direct = (__bridge NSString *)dispatch_queue_get_specific(target, &queueKey);
    NSString *onChild = (__bridge NSString *)dispatch_queue_get_specific(child, &queueKey);
    say([NSString stringWithFormat:@"specific: through target %@, missing %@, direct %@, child's own %@",
         fromChild, missing, direct, onChild]);

    dispatch_set_context(child, (void *)0x1234);
    say([NSString stringWithFormat:@"context: %p", dispatch_get_context(child)]);
}

static void suspension(void) {
    dispatch_queue_t queue = dispatch_queue_create("org.perry.suspended", DISPATCH_QUEUE_SERIAL);
    __block int ran = 0;
    dispatch_suspend(queue);
    dispatch_async(queue, ^{ ran++; });
    usleep(10000);
    int beforeResume = ran;
    dispatch_resume(queue);
    dispatch_sync(queue, ^{});
    int afterResume = ran;

    dispatch_queue_t inactive = dispatch_queue_create("org.perry.inactive",
        dispatch_queue_attr_make_initially_inactive(DISPATCH_QUEUE_SERIAL));
    dispatch_async(inactive, ^{ ran += 10; });
    usleep(10000);
    int beforeActivate = ran;
    dispatch_activate(inactive);
    dispatch_sync(inactive, ^{});
    say([NSString stringWithFormat:@"suspend: %d then %d, inactive %d then %d", beforeResume, afterResume, beforeActivate, ran]);
}

static void sources(void) {
    dispatch_queue_t queue = dispatch_queue_create("org.perry.sources", DISPATCH_QUEUE_SERIAL);

    dispatch_source_t adder = dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_ADD, 0, 0, queue);
    __block unsigned long added = 0;
    __block int events = 0;
    dispatch_semaphore_t handled = dispatch_semaphore_create(0);
    dispatch_source_set_event_handler(adder, ^{
        added += dispatch_source_get_data(adder);
        events++;
        if (added == 15) dispatch_semaphore_signal(handled);
    });
    dispatch_suspend(queue);
    dispatch_resume(adder);
    for (unsigned long i = 1; i <= 5; i++) dispatch_source_merge_data(adder, i);
    dispatch_resume(queue);
    dispatch_semaphore_wait(handled, DISPATCH_TIME_FOREVER);
    say([NSString stringWithFormat:@"data add: %lu in %d event", added, events]);

    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    __block int fired = 0;
    dispatch_semaphore_t cancelled = dispatch_semaphore_create(0);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_MSEC), 5 * NSEC_PER_MSEC, 0);
    dispatch_source_set_event_handler(timer, ^{
        if (++fired == 3) dispatch_source_cancel(timer);
    });
    dispatch_source_set_cancel_handler(timer, ^{ dispatch_semaphore_signal(cancelled); });
    dispatch_resume(timer);
    dispatch_semaphore_wait(cancelled, DISPATCH_TIME_FOREVER);
    say([NSString stringWithFormat:@"timer: fired %d, cancelled %ld", fired, dispatch_source_testcancel(timer)]);
}

static void blocks(void) {
    dispatch_queue_t queue = dispatch_queue_create("org.perry.blocks", DISPATCH_QUEUE_SERIAL);
    __block int ran = 0;
    dispatch_block_t first = dispatch_block_create(0, ^{ ran += 1; });
    dispatch_block_t second = dispatch_block_create(0, ^{ ran += 100; });
    dispatch_suspend(queue);
    dispatch_async(queue, first);
    dispatch_async(queue, second);
    dispatch_block_cancel(second);
    dispatch_resume(queue);
    long waited = dispatch_block_wait(first, DISPATCH_TIME_FOREVER);
    dispatch_sync(queue, ^{});
    __block BOOL notified = NO;
    dispatch_block_notify(first, queue, ^{ notified = YES; });
    dispatch_sync(queue, ^{});
    say([NSString stringWithFormat:@"dispatch blocks: ran %d, waited %ld, cancelled %ld, notified %d",
         ran, waited, dispatch_block_testcancel(second), notified]);
}

static void data(void) {
    const char *hello = "Hello, ";
    dispatch_data_t first = dispatch_data_create(hello, strlen(hello), NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    dispatch_data_t second = dispatch_data_create("world", 5, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    dispatch_data_t joined = dispatch_data_create_concat(first, second);
    __block int regions = 0;
    dispatch_data_apply(joined, ^bool(dispatch_data_t region, size_t offset, const void *buffer, size_t size) {
        regions++;
        return true;
    });
    const void *bytes = NULL;
    size_t size = 0;
    dispatch_data_t mapped = dispatch_data_create_map(joined, &bytes, &size);
    NSString *text = [[NSString alloc] initWithBytes:bytes length:size encoding:NSUTF8StringEncoding];
    dispatch_data_t sub = dispatch_data_create_subrange(joined, 7, 5);
    say([NSString stringWithFormat:@"data: '%@', %zu bytes, %d regions, sub %zu, empty %zu, mapped %d",
         text, dispatch_data_get_size(joined), regions, dispatch_data_get_size(sub),
         dispatch_data_get_size(dispatch_data_empty), mapped != nil]);
}

static void once(void) {
    static dispatch_once_t token;
    __block int count = 0;
    for (int i = 0; i < 3; i++) dispatch_once(&token, ^{ count++; });
    say([NSString stringWithFormat:@"once: %d", count]);
}

static void objects(void) {
    dispatch_queue_t queue = dispatch_queue_create("org.perry.object", NULL);
    say([NSString stringWithFormat:@"objects: queue %d, main %d, group %d, semaphore %d",
         [queue isKindOfClass:NSClassFromString(@"OS_dispatch_queue")],
         [dispatch_get_main_queue() isKindOfClass:NSClassFromString(@"OS_dispatch_queue_main")],
         [dispatch_group_create() isKindOfClass:NSClassFromString(@"OS_dispatch_group")],
         [dispatch_semaphore_create(0) conformsToProtocol:NSProtocolFromString(@"OS_dispatch_semaphore")]]);
}

// The main queue, run by the main run loop.
static void mainQueue(void) {
    say([NSString stringWithFormat:@"main queue label: %s", dispatch_queue_get_label(dispatch_get_main_queue())]);
    NSMutableArray *order = [NSMutableArray array];
    dispatch_async(dispatch_get_main_queue(), ^{
        [order addObject:@"async"];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            dispatch_sync(dispatch_get_main_queue(), ^{
                [order addObject:[NSString stringWithFormat:@"sync from background, main %d, label %@",
                                  NSThread.isMainThread, label()]];
            });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                [order addObject:@"after"];
                [NSTimer scheduledTimerWithTimeInterval:0.01 repeats:NO block:^(NSTimer *timer) {
                    [order addObject:@"timer"];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        say([NSString stringWithFormat:@"main queue: %@", [order componentsJoinedByString:@"; "]]);
                        exit(0);
                    });
                }];
            });
        });
    });
    [order addObject:@"before run"];
    [[NSRunLoop mainRunLoop] run];
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        serialQueues();
        concurrentQueues();
        globalQueues();
        groups();
        semaphores();
        applying();
        specifics();
        suspension();
        sources();
        blocks();
        data();
        once();
        objects();
        mainQueue();
    }
    return 1;
}
