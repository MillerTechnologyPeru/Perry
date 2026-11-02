// Run loops, timers, dates and notifications, built on a Mac with Xcode.
// Timer intervals are spaced so the order of events is deterministic.
#import <Foundation/Foundation.h>

static void print(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static NSString *const ClockDidTickNotification = @"ClockDidTick";

@interface Ticker : NSObject
@property (nonatomic) NSInteger ticks;
@property (nonatomic) NSInteger observed;
@end

@implementation Ticker

- (void)tick:(NSTimer *)timer {
    self.ticks += 1;
    print([NSString stringWithFormat:@"tick %ld (%@)", (long)self.ticks, timer.userInfo]);
    [[NSNotificationCenter defaultCenter] postNotificationName:ClockDidTickNotification
                                                        object:self
                                                      userInfo:@{@"tick": @(self.ticks)}];
    if (self.ticks == 3) {
        [timer invalidate];
        print([NSString stringWithFormat:@"invalidated %d", timer.isValid]);
        [self performSelector:@selector(finish:) withObject:@"done" afterDelay:0.02];
        [self performSelector:@selector(finish:) withObject:@"cancelled" afterDelay:0.01];
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(finish:) object:@"cancelled"];
    }
}

- (void)tickDidHappen:(NSNotification *)notification {
    self.observed += 1;
}

- (void)finish:(NSString *)word {
    print([NSString stringWithFormat:@"finish %@", word]);
    CFRunLoopStop(CFRunLoopGetCurrent());
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSDate *epoch = [NSDate dateWithTimeIntervalSince1970:0];
        NSDate *reference = [NSDate dateWithTimeIntervalSinceReferenceDate:0];
        NSDate *later = [reference dateByAddingTimeInterval:86400 * 365 + 3723];
        print([NSString stringWithFormat:@"%@ | %@ | %@", epoch, reference, later]);
        print([NSString stringWithFormat:@"since 1970 %.0f, between %.0f, compare %ld, later %@",
               reference.timeIntervalSince1970, [later timeIntervalSinceDate:reference],
               (long)[epoch compare:reference], [epoch laterDate:reference]]);
        NSDate *now = [NSDate date];
        print([NSString stringWithFormat:@"now is recent %d, future %d",
               fabs(now.timeIntervalSinceNow) < 5, [[NSDate distantFuture] compare:now] == NSOrderedDescending]);

        Ticker *ticker = [Ticker new];
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:ticker selector:@selector(tickDidHappen:) name:ClockDidTickNotification object:nil];
        __block NSInteger blockTicks = 0;
        id token = [center addObserverForName:ClockDidTickNotification object:ticker queue:nil
                                   usingBlock:^(NSNotification *note) {
            blockTicks += [note.userInfo[@"tick"] integerValue];
        }];
        [center postNotificationName:@"Unrelated" object:nil];

        [NSTimer scheduledTimerWithTimeInterval:0.01 repeats:NO block:^(NSTimer *timer) {
            print(@"block timer");
        }];
        NSTimer *repeating = [NSTimer scheduledTimerWithTimeInterval:0.03 target:ticker selector:@selector(tick:)
                                                            userInfo:@"info" repeats:YES];
        print([NSString stringWithFormat:@"repeating valid %d interval %.2f", repeating.isValid, repeating.timeInterval]);
        print([NSString stringWithFormat:@"main %d", [NSRunLoop currentRunLoop] == [NSRunLoop mainRunLoop]]);

        CFRunLoopRun();
        print([NSString stringWithFormat:@"stopped: ticks %ld observed %ld block %ld",
               (long)ticker.ticks, (long)ticker.observed, (long)blockTicks]);

        [center removeObserver:token];
        [center removeObserver:ticker];
        [center postNotificationName:ClockDidTickNotification object:ticker];
        print([NSString stringWithFormat:@"after removal observed %ld block %ld",
               (long)ticker.observed, (long)blockTicks]);

        __block BOOL fired = NO;
        [NSTimer scheduledTimerWithTimeInterval:0.01 repeats:NO block:^(NSTimer *timer) {
            fired = YES;
        }];
        NSDate *start = [NSDate date];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        print([NSString stringWithFormat:@"runUntilDate fired %d waited %d", fired,
               [[NSDate date] timeIntervalSinceDate:start] >= 0.045]);
    }
    return 0;
}
