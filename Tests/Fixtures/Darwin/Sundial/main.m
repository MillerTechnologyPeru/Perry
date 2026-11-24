// Calendars, time, locale, process info, progress, undo, notification
// queues, threads, operations, values and serialization, built on a Mac
// with Xcode. Dates are fixed, in GMT and the Gregorian calendar; the run
// loop runs briefly to post queued notifications. Prints to stdout so the
// test can compare exact text.
#import <Foundation/Foundation.h>

static void print(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static NSMutableArray<NSString *> *events;

@interface Listener : NSObject
@end

@implementation Listener
- (void)heard:(NSNotification *)note {
    NSString *tag = note.userInfo[@"tag"];
    [events addObject:tag ? [NSString stringWithFormat:@"%@:%@", note.name, tag] : note.name];
}
- (void)fired:(NSTimer *)timer { [events addObject:@"timer"]; }
- (void)performed { [events addObject:@"perform"]; }
- (NSInteger)add:(NSInteger)a to:(NSInteger)b { return a + b; }
- (NSString *)echo:(NSString *)text { return [text uppercaseString]; }
- (void)setValue:(NSInteger)value { [events addObject:[NSString stringWithFormat:@"undo set %ld", (long)value]]; }
@end

static NSString *gmt(NSDate *date) {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss EEE";
    return date ? [formatter stringFromDate:date] : @"nil";
}

static void runLoopBriefly(void) {
    // A timer keeps Darwin's run loop running: with no source or timer it returns at once.
    [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:NO block:^(NSTimer *timer) { [events addObject:@"timer"]; }];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.15]];
}

static void calendars(void) {
    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    calendar.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    NSDateComponents *parts = [[NSDateComponents alloc] init];
    parts.year = 2024; parts.month = 2; parts.day = 29; parts.hour = 13; parts.minute = 45; parts.second = 30;
    NSDate *leap = [calendar dateFromComponents:parts];
    print([@"leap " stringByAppendingString:gmt(leap)]);

    NSInteger era = 0, year = 0, month = 0, day = 0, weekYear = 0, week = 0, weekday = 0;
    NSInteger hour = 0, minute = 0, second = 0, nanosecond = 0;
    [calendar getEra:&era year:&year month:&month day:&day fromDate:leap];
    [calendar getEra:NULL yearForWeekOfYear:&weekYear weekOfYear:&week weekday:&weekday fromDate:leap];
    [calendar getHour:&hour minute:&minute second:&second nanosecond:&nanosecond fromDate:leap];
    print([NSString stringWithFormat:@"era %ld %ld-%ld-%ld week %ld/%ld day %ld time %ld:%ld:%ld.%ld", (long)era, (long)year,
           (long)month, (long)day, (long)weekYear, (long)week, (long)weekday, (long)hour, (long)minute, (long)second,
           (long)nanosecond]);
    NSDate *weekly = [calendar dateWithEra:1 yearForWeekOfYear:2024 weekOfYear:9 weekday:5 hour:8 minute:30 second:0 nanosecond:0];
    print([@"week date " stringByAppendingString:gmt(weekly)]);

    NSDateComponents *leapDay = [[NSDateComponents alloc] init];
    leapDay.month = 2; leapDay.day = 29;
    NSDateComponents *other = [[NSDateComponents alloc] init];
    other.day = 28;
    print([NSString stringWithFormat:@"matches %d %d", [calendar date:leap matchesComponents:leapDay],
           [calendar date:leap matchesComponents:other]]);

    print([@"next leap day " stringByAppendingString:gmt([calendar nextDateAfterDate:leap matchingComponents:leapDay
                                                                                options:NSCalendarMatchStrictly])]);
    print([@"previous leap day " stringByAppendingString:gmt([calendar nextDateAfterDate:leap matchingComponents:leapDay
                                                                                    options:NSCalendarMatchStrictly | NSCalendarSearchBackwards])]);
    print([@"next monday " stringByAppendingString:gmt([calendar nextDateAfterDate:leap matchingUnit:NSCalendarUnitWeekday
                                                                              value:2 options:NSCalendarMatchNextTime])]);
    print([@"next 9:15 " stringByAppendingString:gmt([calendar nextDateAfterDate:leap matchingHour:9 minute:15 second:0
                                                                         options:NSCalendarMatchNextTime])]);

    NSDateComponents *thirtyFirst = [[NSDateComponents alloc] init];
    thirtyFirst.day = 31;
    __block NSInteger found = 0;
    [calendar enumerateDatesStartingAfterDate:leap matchingComponents:thirtyFirst options:NSCalendarMatchStrictly
                                   usingBlock:^(NSDate *date, BOOL exact, BOOL *stop) {
        print([NSString stringWithFormat:@"31st %@ exact %d", gmt(date), exact]);
        if (++found == 3) *stop = YES;
    }];

    NSDate *weekendStart = nil;
    NSTimeInterval length = 0;
    NSDate *saturday = [leap dateByAddingTimeInterval:2 * 86400];
    BOOL inWeekend = [calendar rangeOfWeekendStartDate:&weekendStart interval:&length containingDate:saturday];
    print([NSString stringWithFormat:@"weekend %d %@ %.0f", inWeekend, gmt(weekendStart), length]);
    inWeekend = [calendar rangeOfWeekendStartDate:&weekendStart interval:&length containingDate:leap];
    print([NSString stringWithFormat:@"weekday weekend %d", inWeekend]);
    BOOL next = [calendar nextWeekendStartDate:&weekendStart interval:&length options:0 afterDate:saturday];
    print([NSString stringWithFormat:@"next weekend %d %@ %.0f", next, gmt(weekendStart), length]);
    next = [calendar nextWeekendStartDate:&weekendStart interval:&length options:NSCalendarSearchBackwards afterDate:leap];
    print([NSString stringWithFormat:@"previous weekend %d %@ %.0f", next, gmt(weekendStart), length]);

    print([calendar.standaloneQuarterSymbols componentsJoinedByString:@","]);
    print([calendar.shortStandaloneQuarterSymbols componentsJoinedByString:@","]);
    print([calendar.shortStandaloneWeekdaySymbols componentsJoinedByString:@","]);
    print([calendar.veryShortStandaloneMonthSymbols componentsJoinedByString:@","]);
    print([calendar.veryShortStandaloneWeekdaySymbols componentsJoinedByString:@","]);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSDateComponents *weekParts = [[NSDateComponents alloc] init];
    print([NSString stringWithFormat:@"week unset %d", weekParts.week == NSDateComponentUndefined]);
    weekParts.week = 7;
    print([NSString stringWithFormat:@"week %ld %d %ld", (long)weekParts.week,
           [weekParts valueForComponent:NSCalendarUnitWeekOfYear] == NSDateComponentUndefined,
           (long)[weekParts valueForComponent:(NSCalendarUnit)(1 << 8)]]);
    print([NSString stringWithFormat:@"week of leap day %ld",
           (long)[calendar components:(NSCalendarUnit)(1 << 8) | NSCalendarUnitYear fromDate:leap].week]);
#pragma clang diagnostic pop

    NSDate *start = [calendar dateWithEra:1 year:2024 month:1 day:1 hour:0 minute:0 second:0 nanosecond:0];
    NSDateInterval *january = [[NSDateInterval alloc] initWithStartDate:start duration:31 * 86400];
    NSDateInterval *midJanuary = [[NSDateInterval alloc] initWithStartDate:[start dateByAddingTimeInterval:20 * 86400] duration:20 * 86400];
    NSDateInterval *march = [[NSDateInterval alloc] initWithStartDate:[start dateByAddingTimeInterval:61 * 86400] duration:86400];
    NSDateInterval *overlap = [january intersectionWithDateInterval:midJanuary];
    print([NSString stringWithFormat:@"intervals %ld %ld %d %d %@ %.0f %@", (long)[january compare:midJanuary],
           (long)[march compare:january], [january intersectsDateInterval:midJanuary], [january intersectsDateInterval:march],
           gmt(overlap.startDate), overlap.duration, [january intersectionWithDateInterval:march] ? @"some" : @"none"]);

    [NSTimeZone setDefaultTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    print([leap descriptionWithLocale:nil]);
    print([leap descriptionWithLocale:[NSLocale localeWithLocaleIdentifier:@"en_US"]]);

    NSMutableDictionary *abbreviations = [[NSTimeZone abbreviationDictionary] mutableCopy];
    abbreviations[@"SDL"] = @"Europe/Paris";
    [NSTimeZone setAbbreviationDictionary:abbreviations];
    print([NSString stringWithFormat:@"abbreviation %@ %@", [NSTimeZone timeZoneWithAbbreviation:@"SDL"].name,
           [NSTimeZone abbreviationDictionary][@"SDL"]]);
}

static void locales(void) {
    NSLocale *locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    NSCharacterSet *exemplar = locale.exemplarCharacterSet;
    print([NSString stringWithFormat:@"locale %@ exemplar %d %d %d", locale.collatorIdentifier, [exemplar characterIsMember:'q'],
           [exemplar characterIsMember:'Q'], [exemplar characterIsMember:0xE9]]);
    print([NSString stringWithFormat:@"collation %@ / %@", [locale localizedStringForCollationIdentifier:@"phonebook"],
           [locale localizedStringForCollatorIdentifier:@"de"]]);
    print([NSString stringWithFormat:@"directions %lu %lu", (unsigned long)[NSLocale lineDirectionForLanguage:@"en"],
           (unsigned long)[NSLocale lineDirectionForLanguage:@"ar"]]);
    print([NSString stringWithFormat:@"windows %u %@ %u", [NSLocale windowsLocaleCodeFromLocaleIdentifier:@"en_US"],
           [NSLocale localeIdentifierFromWindowsLocaleCode:1031], [NSLocale windowsLocaleCodeFromLocaleIdentifier:@"xx_YY"]]);
}

static void queues(void) {
    Listener *listener = [[Listener alloc] init];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    for (NSString *name in @[@"Now", @"Soon", @"Idle", @"Dropped", @"Twice", @"Sender"]) {
        [center addObserver:listener selector:@selector(heard:) name:name object:nil];
    }
    NSNotificationQueue *queue = [NSNotificationQueue defaultQueue];
    print([NSString stringWithFormat:@"default queue same %d", queue == [NSNotificationQueue defaultQueue]]);

    [queue enqueueNotification:[NSNotification notificationWithName:@"Now" object:nil] postingStyle:NSPostNow];
    print([NSString stringWithFormat:@"after now: %@", [events componentsJoinedByString:@" "]]);
    [events removeAllObjects];

    [queue enqueueNotification:[NSNotification notificationWithName:@"Idle" object:nil userInfo:@{@"tag": @"1"}]
                  postingStyle:NSPostWhenIdle];
    for (NSString *tag in @[@"a", @"b", @"c"]) {
        [queue enqueueNotification:[NSNotification notificationWithName:@"Soon" object:listener userInfo:@{@"tag": tag}]
                      postingStyle:NSPostASAP];
    }
    for (NSString *tag in @[@"x", @"y"]) {
        [queue enqueueNotification:[NSNotification notificationWithName:@"Twice" object:nil userInfo:@{@"tag": tag}]
                      postingStyle:NSPostASAP coalesceMask:NSNotificationNoCoalescing forModes:nil];
    }
    [queue enqueueNotification:[NSNotification notificationWithName:@"Dropped" object:nil] postingStyle:NSPostASAP];
    [queue dequeueNotificationsMatching:[NSNotification notificationWithName:@"Dropped" object:nil]
                           coalesceMask:NSNotificationCoalescingOnName];
    [queue enqueueNotification:[NSNotification notificationWithName:@"Sender" object:center userInfo:@{@"tag": @"first"}]
                  postingStyle:NSPostWhenIdle coalesceMask:NSNotificationCoalescingOnSender forModes:nil];
    [queue enqueueNotification:[NSNotification notificationWithName:@"Idle" object:center userInfo:@{@"tag": @"2"}]
                  postingStyle:NSPostWhenIdle coalesceMask:NSNotificationCoalescingOnSender forModes:@[NSDefaultRunLoopMode]];
    [listener performSelector:@selector(performed) withObject:nil afterDelay:0];
    print([NSString stringWithFormat:@"before run: %lu", (unsigned long)events.count]);
    runLoopBriefly();
    print([NSString stringWithFormat:@"after run: %@", [events componentsJoinedByString:@" "]]);
    [events removeAllObjects];

    // A posting of the same name and sender now replaces one queued.
    [queue enqueueNotification:[NSNotification notificationWithName:@"Soon" object:nil userInfo:@{@"tag": @"queued"}]
                  postingStyle:NSPostASAP];
    [queue enqueueNotification:[NSNotification notificationWithName:@"Soon" object:nil userInfo:@{@"tag": @"now"}]
                  postingStyle:NSPostNow];
    runLoopBriefly();
    print([NSString stringWithFormat:@"now coalesces: %@", [events componentsJoinedByString:@" "]]);
    [events removeAllObjects];

    NSNotificationCenter *own = [[NSNotificationCenter alloc] init];
    [own addObserver:listener selector:@selector(heard:) name:@"Own" object:nil];
    NSNotificationQueue *ownQueue = [[NSNotificationQueue alloc] initWithNotificationCenter:own];
    [ownQueue enqueueNotification:[NSNotification notificationWithName:@"Own" object:nil] postingStyle:NSPostASAP];
    [ownQueue enqueueNotification:[NSNotification notificationWithName:@"Soon" object:nil] postingStyle:NSPostASAP];
    runLoopBriefly();
    print([NSString stringWithFormat:@"own center: %@", [events componentsJoinedByString:@" "]]);
    [events removeAllObjects];
    [center removeObserver:listener];
}

static void progress(void) {
    NSProgress *progress = [NSProgress discreteProgressWithTotalUnitCount:10];
    progress.kind = NSProgressKindFile;
    progress.fileOperationKind = NSProgressFileOperationKindDownloading;
    progress.fileURL = [NSURL fileURLWithPath:@"/tmp/sundial.dat"];
    progress.fileTotalCount = @4;
    progress.fileCompletedCount = @1;
    progress.estimatedTimeRemaining = @120;
    progress.throughput = @2048;
    print([NSString stringWithFormat:@"progress %@ %@ %@ %@ %@ %@", progress.fileOperationKind, progress.fileURL.path,
           progress.fileTotalCount, progress.fileCompletedCount, progress.estimatedTimeRemaining, progress.throughput]);
    print([[progress.userInfo.allKeys sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","]);
    print([NSString stringWithFormat:@"user info %@", progress.userInfo[@"NSProgressFileTotalCountKey"]]);
    progress.fileURL = nil;
    progress.throughput = nil;
    print([NSString stringWithFormat:@"cleared %@ %@ %lu", progress.fileURL, progress.throughput,
           (unsigned long)progress.userInfo.count]);
}

static void stores(void) {
    NSUbiquitousKeyValueStore *store = [NSUbiquitousKeyValueStore defaultStore];
    print([NSString stringWithFormat:@"store same %d defaults %d", store == [NSUbiquitousKeyValueStore defaultStore],
           [store isKindOfClass:[NSUserDefaults class]]]);
    // Without iCloud (or its entitlement, as this fixture has none) nothing set is read back on Darwin.
    print([NSString stringWithFormat:@"missing %@ %@ %@ %@ %@ %d %.1f %lld", [store objectForKey:@"sundial.missing"],
           [store stringForKey:@"sundial.missing"], [store arrayForKey:@"sundial.missing"], [store dictionaryForKey:@"sundial.missing"],
           [store dataForKey:@"sundial.missing"], [store boolForKey:@"sundial.missing"], [store doubleForKey:@"sundial.missing"],
           [store longLongForKey:@"sundial.missing"]]);
    [store removeObjectForKey:@"sundial.missing"];
    [store synchronize];

    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"org.perry.fixture.sundial.suite"];
    [defaults addSuiteNamed:@"org.perry.fixture.sundial.other"];
    print([NSString stringWithFormat:@"defaults forced %d %d", [defaults objectIsForcedForKey:@"anything"],
           [defaults objectIsForcedForKey:@"anything" inDomain:@"org.perry.fixture.sundial.suite"]]);
    [defaults removeSuiteNamed:@"org.perry.fixture.sundial.other"];
}

static void undo(void) {
    NSUndoManager *manager = [[NSUndoManager alloc] init];
    manager.groupsByEvent = NO;
    Listener *listener = [[Listener alloc] init];
    [manager beginUndoGrouping];
    [[manager prepareWithInvocationTarget:listener] setValue:1];
    [manager registerUndoWithTarget:listener selector:@selector(performed) object:nil];
    [manager setActionName:@"First"];
    [manager setActionIsDiscardable:YES];
    if (@available(iOS 18.0, macOS 15.0, *)) [manager setActionUserInfoValue:@"one" forKey:@"note"];
    [manager endUndoGrouping];
    [manager beginUndoGrouping];
    [manager registerUndoWithTarget:listener selector:@selector(performed) object:nil];
    [manager setActionName:@"Second"];
    [manager endUndoGrouping];
    NSString *counts = @"counts 2 0";
    if (@available(iOS 17.4, macOS 14.4, *)) {
        counts = [NSString stringWithFormat:@"counts %lu %lu", (unsigned long)manager.undoCount, (unsigned long)manager.redoCount];
    }
    print([NSString stringWithFormat:@"%@ discardable %d %d", counts, manager.undoActionIsDiscardable, manager.redoActionIsDiscardable]);
    [manager undo];
    NSString *info = @"info (null)";
    if (@available(iOS 18.0, macOS 15.0, *)) info = [NSString stringWithFormat:@"info %@", [manager undoActionUserInfoValueForKey:@"note"]];
    print([NSString stringWithFormat:@"%@ %@ discardable %d %d", manager.undoActionName, info, manager.undoActionIsDiscardable,
           manager.redoActionIsDiscardable]);
    [manager undo];
    if (@available(iOS 17.4, macOS 14.4, *)) {
        counts = [NSString stringWithFormat:@"counts %lu %lu", (unsigned long)manager.undoCount, (unsigned long)manager.redoCount];
    } else {
        counts = @"counts 0 0";
    }
    if (@available(iOS 18.0, macOS 15.0, *)) info = [NSString stringWithFormat:@"info %@", [manager redoActionUserInfoValueForKey:@"note"]];
    print([NSString stringWithFormat:@"%@ %@ %@ discardable %d", counts, manager.redoActionName, info, manager.redoActionIsDiscardable]);
    print([events componentsJoinedByString:@" "]);
    [events removeAllObjects];
}

static void process(void) {
    NSProcessInfo *info = [NSProcessInfo processInfo];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    print([NSString stringWithFormat:@"os %lu %@", (unsigned long)info.operatingSystem, info.operatingSystemName]);
#pragma clang diagnostic pop
    NSString *old = info.processName;
    info.processName = @"Sundial-renamed";
    print([NSString stringWithFormat:@"process %@ catalyst %d", info.processName, info.isMacCatalystApp]);
    info.processName = old;
    print([NSString stringWithFormat:@"versions %d %d", [info isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){1, 0, 0}],
           info.operatingSystemVersionString.length > 0]);
}

static void threads(void) {
    print([NSString stringWithFormat:@"priority set %d", [NSThread setThreadPriority:0.5]]);
    __block NSString *exited = @"no";
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    NSThread *thread = [[NSThread alloc] initWithBlock:^{ [NSThread sleepForTimeInterval:0.01]; }];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    id token = [[NSNotificationCenter defaultCenter] addObserverForName:NSThreadWillExitNotification object:thread queue:nil
                                                             usingBlock:^(NSNotification *note) {
        exited = [NSString stringWithFormat:@"yes current %d", note.object == [NSThread currentThread]];
        dispatch_semaphore_signal(done);
    }];
#pragma clang diagnostic pop
    [thread start];
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    [[NSNotificationCenter defaultCenter] removeObserver:token];
    print([@"thread will exit " stringByAppendingString:exited]);

    Listener *listener = [[Listener alloc] init];
    NSMethodSignature *signature = [listener methodSignatureForSelector:@selector(add:to:)];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = listener;
    invocation.selector = @selector(add:to:);
    NSInteger a = 20, b = 22, sum = 0;
    [invocation setArgument:&a atIndex:2];
    [invocation setArgument:&b atIndex:3];
    [invocation invokeUsingIMP:[listener methodForSelector:@selector(add:to:)]];
    [invocation getReturnValue:&sum];
    print([NSString stringWithFormat:@"invoke using IMP %ld", (long)sum]);

    NSInvocation *echo = [NSInvocation invocationWithMethodSignature:[listener methodSignatureForSelector:@selector(echo:)]];
    echo.target = listener;
    echo.selector = @selector(echo:);
    NSString *word = @"sundial";
    [echo setArgument:&word atIndex:2];
    NSInvocationOperation *operation = [[NSInvocationOperation alloc] initWithInvocation:echo];
    [operation start];
    print([NSString stringWithFormat:@"operation %@ same %d", operation.result, operation.invocation == echo]);
    NSInvocationOperation *made = [[NSInvocationOperation alloc] initWithTarget:listener selector:@selector(echo:) object:@"dial"];
    NSInvocation *madeInvocation = made.invocation;
    print([NSString stringWithFormat:@"made invocation %@ %lu", NSStringFromSelector(madeInvocation.selector),
           (unsigned long)madeInvocation.methodSignature.numberOfArguments]);
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    print([NSString stringWithFormat:@"queue progress %lld", queue.progress.totalUnitCount]);

    NSInvocation *timed = [NSInvocation invocationWithMethodSignature:[listener methodSignatureForSelector:@selector(performed)]];
    timed.target = listener;
    timed.selector = @selector(performed);
    NSTimer *timer = [NSTimer timerWithTimeInterval:0.01 invocation:timed repeats:NO];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
    NSDate *limit = [[NSRunLoop currentRunLoop] limitDateForMode:NSDefaultRunLoopMode];
    print([NSString stringWithFormat:@"limit date is fire date %d", [limit isEqualToDate:timer.fireDate]]);
    [NSTimer scheduledTimerWithTimeInterval:0.02 invocation:timed repeats:NO];
    runLoopBriefly();
    print([NSString stringWithFormat:@"timers: %@", [events componentsJoinedByString:@" "]]);
    [events removeAllObjects];
}

static void values(void) {
    NSLocale *german = [NSLocale localeWithLocaleIdentifier:@"de_DE"];
    print([NSString stringWithFormat:@"numbers %@ %@ %@ %@ %@ %@", [@2.5 descriptionWithLocale:german], [@2.5 descriptionWithLocale:nil],
           [@1234 descriptionWithLocale:german], [@(-1234567.25) descriptionWithLocale:german], [@YES descriptionWithLocale:german],
           [@2.5 descriptionWithLocale:@{}]]);
    NSUUID *low = [[NSUUID alloc] initWithUUIDString:@"00000000-0000-0000-0000-000000000001"];
    NSUUID *high = [[NSUUID alloc] initWithUUIDString:@"10000000-0000-0000-0000-000000000000"];
    print([NSString stringWithFormat:@"uuid compare %ld %ld %ld", (long)[low compare:high], (long)[high compare:low],
           (long)[low compare:[low copy]]]);
    NSError *error = [NSError errorWithDomain:@"Sundial" code:7 userInfo:@{
        NSLocalizedRecoveryOptionsErrorKey: @[@"Retry", @"Cancel"], NSHelpAnchorErrorKey: @"anchor",
        NSRecoveryAttempterErrorKey: @"attempter"}];
    print([NSString stringWithFormat:@"error %@ %@ %@", [error.localizedRecoveryOptions componentsJoinedByString:@"/"],
           error.helpAnchor, error.recoveryAttempter]);
    NSError *plain = [NSError errorWithDomain:@"Sundial" code:8 userInfo:nil];
    print([NSString stringWithFormat:@"plain %@ %@ %@", plain.localizedRecoveryOptions, plain.helpAnchor, plain.recoveryAttempter]);

    NSOutputStream *output = [NSOutputStream outputStreamToMemory];
    [output open];
    NSError *writeError = nil;
    NSInteger written = [NSJSONSerialization writeJSONObject:@{@"a": @[@1, @2]} toStream:output options:0 error:&writeError];
    NSData *json = [output propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
    [output close];
    print([NSString stringWithFormat:@"json %ld %@", (long)written, [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]]);

    NSData *xml = [@"<root><item>one</item><item>two</item></root>" dataUsingEncoding:NSUTF8StringEncoding];
    NSXMLParser *parser = [[NSXMLParser alloc] initWithStream:[NSInputStream inputStreamWithData:xml]];
    BOOL parsed = [parser parse];
    print([NSString stringWithFormat:@"xml stream %d %@", parsed, parser.parserError ? @"error" : @"ok"]);
    NSXMLParser *policy = [[NSXMLParser alloc] initWithData:xml];
    if (@available(iOS 13.0, macOS 10.15, *)) {
        print([NSString stringWithFormat:@"xml policy %lu %@", (unsigned long)policy.externalEntityResolvingPolicy,
               policy.allowedExternalEntityURLs]);
    }
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        events = [NSMutableArray array];
        calendars();
        locales();
        queues();
        progress();
        stores();
        undo();
        process();
        threads();
        values();
    }
    return 0;
}
