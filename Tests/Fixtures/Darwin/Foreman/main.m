// NSOperation and NSOperationQueue: block operations, subclasses (plain and
// asynchronous), dependencies, priorities, cancellation, completion blocks,
// concurrency limits, barriers, waiting, the current and main queues.

#import <Foundation/Foundation.h>
#include <stdio.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

@interface Recorder : NSObject
@property (readonly) NSMutableArray<NSString *> *items;
- (void)add:(NSString *)item;
- (NSString *)joined;
@end

@implementation Recorder {
    NSLock *_lock;
}
- (instancetype)init {
    if ((self = [super init])) {
        _items = [NSMutableArray array];
        _lock = [NSLock new];
    }
    return self;
}
- (void)add:(NSString *)item {
    [_lock lock];
    [_items addObject:item];
    [_lock unlock];
}
- (NSString *)joined {
    [_lock lock];
    NSString *text = [_items componentsJoinedByString:@","];
    [_lock unlock];
    return text;
}
@end

// A subclass that does its work in -main.
@interface Squarer : NSOperation
@property NSInteger input;
@property NSInteger output;
@end

@implementation Squarer
- (void)main {
    if (self.isCancelled) return;
    self.output = self.input * self.input;
}
@end

// An asynchronous operation: -start begins work that finishes later on
// another queue, reporting its state through key-value observing.
@interface Download : NSOperation
@property (readonly) Recorder *recorder;
- (instancetype)initWithRecorder:(Recorder *)recorder;
@end

@implementation Download {
    BOOL _executing;
    BOOL _finished;
}
- (instancetype)initWithRecorder:(Recorder *)recorder {
    if ((self = [super init])) _recorder = recorder;
    return self;
}
- (BOOL)isAsynchronous { return YES; }
- (BOOL)isExecuting { return _executing; }
- (BOOL)isFinished { return _finished; }
- (void)start {
    if (self.isCancelled) {
        [self willChangeValueForKey:@"isFinished"];
        _finished = YES;
        [self didChangeValueForKey:@"isFinished"];
        return;
    }
    [self willChangeValueForKey:@"isExecuting"];
    _executing = YES;
    [self didChangeValueForKey:@"isExecuting"];
    [self.recorder add:@"started"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC), dispatch_get_global_queue(0, 0), ^{
        [self.recorder add:@"downloaded"];
        [self willChangeValueForKey:@"isExecuting"];
        [self willChangeValueForKey:@"isFinished"];
        self->_executing = NO;
        self->_finished = YES;
        [self didChangeValueForKey:@"isExecuting"];
        [self didChangeValueForKey:@"isFinished"];
    });
}
@end

static void serial(void) {
    NSOperationQueue *queue = [NSOperationQueue new];
    queue.maxConcurrentOperationCount = 1;
    Recorder *recorder = [Recorder new];
    for (int i = 0; i < 5; i++) {
        [queue addOperationWithBlock:^{ [recorder add:[NSString stringWithFormat:@"%d", i]]; }];
    }
    [queue waitUntilAllOperationsAreFinished];
    say([NSString stringWithFormat:@"serial: %@, count %lu, max %ld", recorder.joined,
         (unsigned long)queue.operationCount, (long)queue.maxConcurrentOperationCount]);
}

static void dependencies(void) {
    NSOperationQueue *queue = [NSOperationQueue new];
    Recorder *recorder = [Recorder new];
    NSBlockOperation *a = [NSBlockOperation blockOperationWithBlock:^{ usleep(5000); [recorder add:@"a"]; }];
    NSBlockOperation *b = [NSBlockOperation blockOperationWithBlock:^{ usleep(2000); [recorder add:@"b"]; }];
    NSBlockOperation *c = [NSBlockOperation blockOperationWithBlock:^{ [recorder add:@"c"]; }];
    [c addDependency:b];
    [b addDependency:a];
    say([NSString stringWithFormat:@"before: c ready %d, c depends on %lu, a ready %d",
         c.isReady, (unsigned long)c.dependencies.count, a.isReady]);
    [queue addOperations:@[c, b, a] waitUntilFinished:YES];
    say([NSString stringWithFormat:@"dependencies: %@, c finished %d, c ready %d", recorder.joined, c.isFinished, c.isReady]);

    // A dependency on an operation that is never queued, run by hand.
    NSBlockOperation *manual = [NSBlockOperation blockOperationWithBlock:^{ [recorder add:@"manual"]; }];
    NSBlockOperation *after = [NSBlockOperation blockOperationWithBlock:^{ [recorder add:@"after"]; }];
    [after addDependency:manual];
    [queue addOperation:after];
    usleep(10000);
    BOOL waited = !after.isFinished;
    [manual start];
    [after waitUntilFinished];
    say([NSString stringWithFormat:@"manual dependency: waited %d, %@", waited, recorder.joined]);
}

static void priorities(void) {
    NSOperationQueue *queue = [NSOperationQueue new];
    queue.maxConcurrentOperationCount = 1;
    queue.suspended = YES;
    Recorder *recorder = [Recorder new];
    NSDictionary *levels = @{@"low": @(NSOperationQueuePriorityLow), @"normal": @(NSOperationQueuePriorityNormal),
                             @"high": @(NSOperationQueuePriorityHigh), @"veryHigh": @(NSOperationQueuePriorityVeryHigh),
                             @"veryLow": @(NSOperationQueuePriorityVeryLow)};
    for (NSString *name in @[@"low", @"normal", @"veryLow", @"high", @"veryHigh", @"normal2"]) {
        NSBlockOperation *operation = [NSBlockOperation blockOperationWithBlock:^{ [recorder add:name]; }];
        NSNumber *level = levels[name];
        if (level) operation.queuePriority = level.integerValue;
        [queue addOperation:operation];
    }
    say([NSString stringWithFormat:@"suspended: %d, count %lu", queue.isSuspended, (unsigned long)queue.operationCount]);
    queue.suspended = NO;
    [queue waitUntilAllOperationsAreFinished];
    say([NSString stringWithFormat:@"priorities: %@", recorder.joined]);
}

static void cancellation(void) {
    NSOperationQueue *queue = [NSOperationQueue new];
    queue.suspended = YES;
    Recorder *recorder = [Recorder new];
    NSMutableArray *operations = [NSMutableArray array];
    for (NSString *name in @[@"first", @"second", @"third"]) {
        NSBlockOperation *operation = [NSBlockOperation blockOperationWithBlock:^{ [recorder add:name]; }];
        operation.completionBlock = ^{ [recorder add:[name stringByAppendingString:@" done"]]; };
        [operations addObject:operation];
        [queue addOperation:operation];
    }
    NSBlockOperation *second = operations[1];
    [second cancel];
    queue.suspended = NO;
    [queue waitUntilAllOperationsAreFinished];
    usleep(20000);
    NSArray *sorted = [recorder.items sortedArrayUsingSelector:@selector(compare:)];
    say([NSString stringWithFormat:@"cancel: %@; second cancelled %d finished %d executing %d",
         [sorted componentsJoinedByString:@","], second.isCancelled, second.isFinished, second.isExecuting]);

    queue.suspended = YES;
    for (int i = 0; i < 4; i++) [queue addOperationWithBlock:^{ [recorder add:@"never"]; }];
    [queue cancelAllOperations];
    queue.suspended = NO;
    [queue waitUntilAllOperationsAreFinished];
    say([NSString stringWithFormat:@"cancel all: ran %d", [recorder.items containsObject:@"never"]]);
}

static void subclasses(void) {
    NSOperationQueue *queue = [NSOperationQueue new];
    NSMutableArray *squarers = [NSMutableArray array];
    for (NSInteger i = 1; i <= 4; i++) {
        Squarer *squarer = [Squarer new];
        squarer.input = i;
        [squarers addObject:squarer];
    }
    [queue addOperations:squarers waitUntilFinished:YES];
    say([NSString stringWithFormat:@"squares: %@, asynchronous %d", [squarers valueForKey:@"output"],
         [squarers[0] isAsynchronous]]);

    Recorder *recorder = [Recorder new];
    Download *download = [[Download alloc] initWithRecorder:recorder];
    NSBlockOperation *after = [NSBlockOperation blockOperationWithBlock:^{ [recorder add:@"processed"]; }];
    [after addDependency:download];
    [queue addOperations:@[download, after] waitUntilFinished:NO];
    [queue waitUntilAllOperationsAreFinished];
    say([NSString stringWithFormat:@"asynchronous: %@, finished %d, executing %d", recorder.joined,
         download.isFinished, download.isExecuting]);

    // Started by hand, without a queue.
    Squarer *direct = [Squarer new];
    direct.input = 9;
    [direct start];
    say([NSString stringWithFormat:@"started directly: %ld, finished %d", (long)direct.output, direct.isFinished]);
}

static void blockOperations(void) {
    Recorder *recorder = [Recorder new];
    NSBlockOperation *operation = [NSBlockOperation blockOperationWithBlock:^{ [recorder add:@"one"]; }];
    [operation addExecutionBlock:^{ [recorder add:@"two"]; }];
    [operation addExecutionBlock:^{ [recorder add:@"three"]; }];
    operation.name = @"triple";
    NSOperationQueue *queue = [NSOperationQueue new];
    [queue addOperations:@[operation] waitUntilFinished:YES];
    NSArray *sorted = [recorder.items sortedArrayUsingSelector:@selector(compare:)];
    say([NSString stringWithFormat:@"block operation: %@ ran %@, %lu blocks, priority %ld, qos %ld", operation.name,
         [sorted componentsJoinedByString:@","], (unsigned long)operation.executionBlocks.count,
         (long)operation.queuePriority, (long)operation.qualityOfService]);
}

static void limits(void) {
    NSOperationQueue *queue = [NSOperationQueue new];
    queue.maxConcurrentOperationCount = 2;
    NSLock *lock = [NSLock new];
    __block int running = 0, highest = 0;
    for (int i = 0; i < 6; i++) {
        [queue addOperationWithBlock:^{
            [lock lock];
            running++;
            if (running > highest) highest = running;
            [lock unlock];
            usleep(20000);
            [lock lock];
            running--;
            [lock unlock];
        }];
    }
    [queue waitUntilAllOperationsAreFinished];
    say([NSString stringWithFormat:@"limit: at most %d at once", highest]);
}

static void barriers(void) {
    NSOperationQueue *queue = [NSOperationQueue new];
    Recorder *recorder = [Recorder new];
    for (int i = 0; i < 3; i++) {
        [queue addOperationWithBlock:^{ usleep(5000 * (3 - i)); [recorder add:@"before"]; }];
    }
    [queue addBarrierBlock:^{ [recorder add:[NSString stringWithFormat:@"barrier after %lu", (unsigned long)recorder.items.count]]; }];
    [queue addOperationWithBlock:^{ [recorder add:@"after"]; }];
    [queue waitUntilAllOperationsAreFinished];
    say([NSString stringWithFormat:@"barrier: %@", recorder.joined]);
}

static void currentQueues(void) {
    NSOperationQueue *queue = [NSOperationQueue new];
    queue.name = @"org.perry.workers";
    __block NSOperationQueue *inside = nil;
    __block BOOL main = YES;
    [queue addOperations:@[[NSBlockOperation blockOperationWithBlock:^{
        inside = NSOperationQueue.currentQueue;
        main = NSThread.isMainThread;
    }]] waitUntilFinished:YES];
    say([NSString stringWithFormat:@"current: inside %d (%@), main thread %d, outside is main queue %d",
         inside == queue, inside.name, main, NSOperationQueue.currentQueue == NSOperationQueue.mainQueue]);
    say([NSString stringWithFormat:@"main queue: max %ld, name %@", (long)NSOperationQueue.mainQueue.maxConcurrentOperationCount,
         NSOperationQueue.mainQueue.name]);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        serial();
        dependencies();
        priorities();
        cancellation();
        subclasses();
        blockOperations();
        limits();
        barriers();
        currentQueues();

        // The main queue's operations run on the main thread, from the run loop.
        Recorder *recorder = [Recorder new];
        NSBlockOperation *first = [NSBlockOperation blockOperationWithBlock:^{
            [recorder add:[NSString stringWithFormat:@"first on main %d", NSThread.isMainThread]];
        }];
        [NSOperationQueue.mainQueue addOperation:first];
        [NSOperationQueue.mainQueue addOperationWithBlock:^{
            [recorder add:@"second"];
            say([NSString stringWithFormat:@"main queue ran: %@; current is main %d", recorder.joined,
                 NSOperationQueue.currentQueue == NSOperationQueue.mainQueue]);
            exit(0);
        }];
        [recorder add:@"queued"];
        [[NSRunLoop mainRunLoop] run];
    }
    return 1;
}
