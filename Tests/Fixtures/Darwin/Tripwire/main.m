// Exceptions Foundation raises, caught with @try and @catch: +raise:format:,
// an index past an array's end and a decimal number divided by zero. Also
// one raised in a method of the app's own, which a @finally block on the
// way out sees, a rethrow from a @catch block, a clause for another class
// that lets one by, a subclass of the app's caught by its own class and by
// NSException's, and @catch (id). And ones that unwind through the runtime's
// and Foundation's own frames: an unrecognized selector, an observer that
// raises from a KVO setter, and a method -[NSInvocation invoke] calls. And
// ones the app's own code raises while Foundation is working on a
// collection: a sort comparator, -isEqual: during -removeObject:, an
// enumeration block and a notification observer. Each is followed by more
// calls on the same objects, which must work as before. And ones the app's
// code raises while Foundation holds a lock of the object's: a regular
// expression's enumeration block and a queued notification's -name. The calls after those are made on another
// thread, where a lock the exception left locked would keep them waiting.
// A cache's delegate and a key's -isEqual: raise too, but Darwin's cache
// can't be used after either.
// And an element's -hash or -isEqual: while a set, a dictionary, a
// counted set or an ordered set adds, finds or removes it, followed by
// more use of the same collection.

#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include <stdio.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

@interface TripwireException : NSException
@end

@implementation TripwireException
@end

@interface Thrower : NSObject
@property (nonatomic) NSInteger level;
- (void)raiseNamed:(NSString *)name;
@end

@implementation Thrower
- (void)raiseNamed:(NSString *)name {
    [NSException raise:name format:@"raised by %@", NSStringFromClass(self.class)];
}
@end

// A method Thrower doesn't have.
@interface Thrower (Missing)
- (void)vanish;
@end

// Raises when the level it observes goes past 1.
// Raises from -isEqual:, when compared with another of its class.
@interface Prickly : NSObject <NSCopying>
@end

@implementation Prickly
- (BOOL)isEqual:(id)other {
    if ([other isKindOfClass:[Prickly class]])
        [NSException raise:@"Prickly" format:@"compared with %@", NSStringFromClass([other class])];
    return self == other;
}
- (NSUInteger)hash { return 7; }
- (id)copyWithZone:(NSZone *)zone { return self; }
- (NSString *)description { return @"prickly"; }
@end

// Raises from -hash.
@interface Hasty : NSObject <NSCopying>
@end

@implementation Hasty
- (NSUInteger)hash {
    [NSException raise:@"Hasty" format:@"hashed"];
    return 0;
}
- (id)copyWithZone:(NSZone *)zone { return self; }
@end

// A notification whose -name raises while `bellRaises` is set.
static BOOL bellRaises;

@interface Bell : NSNotification
- (instancetype)initRinging;
@end

@implementation Bell
- (instancetype)initRinging { return self; }
- (NSNotificationName)name {
    if (bellRaises)
        [NSException raise:@"Bell" format:@"asked its name"];
    return @"Bell";
}
- (id)object { return nil; }
- (NSDictionary *)userInfo { return nil; }
@end

// Raises as a cache evicts an object.
@interface Evictor : NSObject <NSCacheDelegate>
@end

@implementation Evictor
- (void)cache:(NSCache *)cache willEvictObject:(id)object {
    [NSException raise:@"Evictor" format:@"evicting"];
}
@end

@interface Watcher : NSObject
@end

@implementation Watcher
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([change[NSKeyValueChangeNewKey] integerValue] > 1)
        [NSException raise:@"Overflow" format:@"%@ is %@", keyPath, change[NSKeyValueChangeNewKey]];
}
@end

static void raised(void) {
    @try {
        [NSException raise:@"Tripwire" format:@"count %d of %@", 3, @"three"];
        say(@"raise: not raised");
    } @catch (NSException *exception) {
        say([NSString stringWithFormat:@"raise: %@: %@", exception.name, exception.reason]);
    }
}

static void array(void) {
    // Made at run time, so not a constant literal.
    NSArray *letters = [@"a b c" componentsSeparatedByString:@" "];
    NSUInteger index = letters.count + 2;
    @try {
        id letter = letters[index];
        say([NSString stringWithFormat:@"array: not raised, %@", letter]);
    } @catch (NSException *exception) {
        // Darwin's reason names the array's private class.
        say([NSString stringWithFormat:@"array: %@, ends \"%@\"", exception.name,
             [exception.reason substringFromIndex:[exception.reason rangeOfString:@"index"].location]]);
    }
    NSMutableArray *mutable = [letters mutableCopy];
    @try {
        [mutable removeObjectAtIndex:7];
        say(@"remove: not raised");
    } @catch (NSException *exception) {
        say([NSString stringWithFormat:@"remove: %@, count %lu", exception.name, (unsigned long)mutable.count]);
    }
}

static void divided(void) {
    @try {
        NSDecimalNumber *quotient = [[NSDecimalNumber one] decimalNumberByDividingBy:[NSDecimalNumber zero]];
        say([NSString stringWithFormat:@"decimal: not raised, %@", quotient]);
    } @catch (NSException *exception) {
        say([NSString stringWithFormat:@"decimal: %@: %@", exception.name, exception.reason]);
    }
}

static void method(void) {
    @try {
        @try {
            [[Thrower new] raiseNamed:@"Inner"];
        } @finally {
            say(@"finally: ran");
        }
    } @catch (id thrown) {
        say([NSString stringWithFormat:@"method: %@: %@", [thrown name], [thrown reason]]);
    }
}

static void rethrown(void) {
    @try {
        @try {
            [NSException raise:NSInvalidArgumentException format:@"first"];
        } @catch (NSException *exception) {
            say(@"rethrow: caught once");
            @throw;
        }
    } @catch (NSException *exception) {
        say([NSString stringWithFormat:@"rethrow: caught again, %@: %@", exception.name, exception.reason]);
    }
}

static void classes(void) {
    @try {
        @try {
            [NSException raise:@"Passing" format:@"by"];
        } @catch (NSString *string) {
            say(@"classes: the string clause caught it");
        }
    } @catch (NSException *exception) {
        say([NSString stringWithFormat:@"classes: passed the string clause, %@", exception.name]);
    }
    @try {
        @throw [TripwireException exceptionWithName:@"Own" reason:@"made here" userInfo:@{ @"key": @"value" }];
    } @catch (TripwireException *exception) {
        say([NSString stringWithFormat:@"classes: own class, %@: %@ %@ %@", NSStringFromClass(exception.class),
             exception.name, exception.reason, exception.userInfo[@"key"]]);
    }
    @try {
        @throw [TripwireException exceptionWithName:@"Super" reason:@"by its superclass" userInfo:nil];
    } @catch (NSException *exception) {
        say([NSString stringWithFormat:@"classes: superclass, %@: %@", NSStringFromClass(exception.class), exception.reason]);
    }
    @try {
        @try {
            [NSException raise:@"Plain" format:@"not the subclass"];
        } @catch (TripwireException *exception) {
            say(@"classes: the subclass clause caught it");
        }
    } @catch (NSException *exception) {
        say([NSString stringWithFormat:@"classes: passed the subclass clause, %@", exception.name]);
    }
}

static void runtime(void) {
    Thrower *thrower = [Thrower new];
    @try {
        [thrower vanish];
        say(@"unrecognized: not raised");
    } @catch (NSException *exception) {
        // The reason ends with the receiver's address.
        say([NSString stringWithFormat:@"unrecognized: %@: %@", exception.name,
             [exception.reason componentsSeparatedByString:@" sent to "].firstObject]);
    }
    Watcher *watcher = [Watcher new];
    [thrower addObserver:watcher forKeyPath:@"level" options:NSKeyValueObservingOptionNew context:NULL];
    thrower.level = 1;
    @try {
        thrower.level = 2;
        say(@"observer: not raised");
    } @catch (NSException *exception) {
        say([NSString stringWithFormat:@"observer: %@: %@, level %ld", exception.name, exception.reason, (long)thrower.level]);
    }
    [thrower removeObserver:watcher forKeyPath:@"level"];
    SEL selector = @selector(raiseNamed:);
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[thrower methodSignatureForSelector:selector]];
    invocation.target = thrower;
    invocation.selector = selector;
    NSString *name = @"Invoked";
    [invocation setArgument:&name atIndex:2];
    @try {
        [invocation invoke];
        say(@"invocation: not raised");
    } @catch (NSException *exception) {
        say([NSString stringWithFormat:@"invocation: %@: %@", exception.name, exception.reason]);
    }
}

static void callbacks(void) {
    NSMutableArray *letters = [[@"d b a c" componentsSeparatedByString:@" "] mutableCopy];
    @try {
        [letters sortUsingComparator:^NSComparisonResult(id a, id b) {
            if ([a isEqual:@"a"] || [b isEqual:@"a"])
                [NSException raise:@"Comparator" format:@"compared %@ with %@", a, b];
            return [a compare:b];
        }];
        say(@"comparator: not raised");
    } @catch (NSException *exception) {
        say([NSString stringWithFormat:@"comparator: %@", exception.name]);
    }
    [letters addObject:@"e"];
    [letters sortUsingSelector:@selector(compare:)];
    say([NSString stringWithFormat:@"comparator after: %@", [letters componentsJoinedByString:@" "]]);

    Prickly *prickly = [Prickly new];
    NSMutableArray *mixed = [NSMutableArray arrayWithObjects:@"x", prickly, @"y", nil];
    @try {
        [mixed removeObject:[Prickly new]];
        say(@"isEqual: not raised");
    } @catch (NSException *exception) {
        say([NSString stringWithFormat:@"isEqual: %@: %@", exception.name, exception.reason]);
    }
    [mixed removeObjectIdenticalTo:prickly];
    [mixed removeObject:@"x"];
    [mixed addObject:@"z"];
    say([NSString stringWithFormat:@"isEqual after: %@", [mixed componentsJoinedByString:@" "]]);

    @try {
        [letters enumerateObjectsUsingBlock:^(id letter, NSUInteger index, BOOL *stop) {
            if (index == 2)
                [NSException raise:@"Enumeration" format:@"stopped at %@", letter];
        }];
        say(@"enumeration: not raised");
    } @catch (NSException *exception) {
        say([NSString stringWithFormat:@"enumeration: %@: %@", exception.name, exception.reason]);
    }
    NSMutableArray *seen = [NSMutableArray array];
    [letters enumerateObjectsUsingBlock:^(id letter, NSUInteger index, BOOL *stop) { [seen addObject:letter]; }];
    say([NSString stringWithFormat:@"enumeration after: %@", [seen componentsJoinedByString:@" "]]);

    NSNotificationCenter *center = [NSNotificationCenter new];
    id raising = [center addObserverForName:@"Ring" object:nil queue:nil usingBlock:^(NSNotification *note) {
        [NSException raise:@"Observer" format:@"heard %@", note.name];
    }];
    __block NSUInteger heard = 0;
    id counting = [center addObserverForName:@"Knock" object:nil queue:nil usingBlock:^(NSNotification *note) { heard++; }];
    @try {
        [center postNotificationName:@"Ring" object:nil];
        say(@"observer: not raised");
    } @catch (NSException *exception) {
        say([NSString stringWithFormat:@"observer: %@: %@", exception.name, exception.reason]);
    }
    [center removeObserver:raising];
    [center postNotificationName:@"Knock" object:nil];
    [center postNotificationName:@"Ring" object:nil];
    [center postNotificationName:@"Knock" object:nil];
    [center removeObserver:counting];
    say([NSString stringWithFormat:@"observer after: heard %lu", (unsigned long)heard]);
}

// Caches the app's code raised in, which Darwin's can't be used again.
static NSMutableArray *abandoned;

// What `work` returns on another thread, or "timed out" if it waits
// there for more than five seconds.
static NSString *elsewhere(NSString *(^work)(void)) {
    __block NSString *result = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            NSString *value = work();
            result = value;
        }
        dispatch_semaphore_signal(done);
    });
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) != 0)
        return @"timed out";
    return result;
}

static void locks(void) {
    NSRegularExpression *digits = [NSRegularExpression regularExpressionWithPattern:@"[0-9]+" options:0 error:NULL];
    NSString *text = [@[@"a1", @"b22", @"c333"] componentsJoinedByString:@" "];
    NSRange all = NSMakeRange(0, text.length);
    @try {
        [digits enumerateMatchesInString:text options:0 range:all usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
            if (match.range.length == 2)
                [NSException raise:@"Match" format:@"found %@", [text substringWithRange:match.range]];
        }];
        say(@"regex: not raised");
    } @catch (NSException *exception) {
        say([NSString stringWithFormat:@"regex: %@: %@", exception.name, exception.reason]);
    }
    NSMutableArray *found = [NSMutableArray array];
    [digits enumerateMatchesInString:text options:0 range:all usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
        // The same expression, used again inside its own enumeration.
        [found addObject:[NSString stringWithFormat:@"%@/%lu", [text substringWithRange:match.range],
                          (unsigned long)[digits numberOfMatchesInString:text options:0 range:all]]];
    }];
    say([NSString stringWithFormat:@"regex nested: %@", [found componentsJoinedByString:@" "]]);
    say([NSString stringWithFormat:@"regex after: %@", elsewhere(^{
        return [NSString stringWithFormat:@"%lu matches", (unsigned long)[digits numberOfMatchesInString:text options:0 range:all]];
    })]);

    NSCache *cache = [NSCache new];
    Evictor *evictor = [Evictor new];
    cache.delegate = evictor;
    cache.countLimit = 1;
    [cache setObject:@"one" forKey:@"1"];
    @try {
        [cache setObject:@"two" forKey:@"2"];
        say(@"cache: not raised");
    } @catch (NSException *exception) {
        say([NSString stringWithFormat:@"cache: %@: %@", exception.name, exception.reason]);
    }
    // Darwin's cache refuses any further call after its delegate raises
    // ("invalid re-entrancy") and stays locked after a key's -isEqual:
    // does, and doesn't survive its -dealloc either: each is kept, and
    // not used again.
    abandoned = [NSMutableArray arrayWithObject:cache];
    cache = [NSCache new];
    [abandoned addObject:cache];
    Prickly *prickly = [Prickly new];
    [cache setObject:@"thorn" forKey:prickly];
    @try {
        id object = [cache objectForKey:[Prickly new]];
        say([NSString stringWithFormat:@"cache isEqual: not raised, %@", object]);
    } @catch (NSException *exception) {
        say([NSString stringWithFormat:@"cache isEqual: %@: %@", exception.name, exception.reason]);
    }

    NSNotificationCenter *center = [NSNotificationCenter new];
    __block NSUInteger chimes = 0;
    id observer = [center addObserverForName:@"Chime" object:nil queue:nil usingBlock:^(NSNotification *note) { chimes++; }];
    NSNotificationQueue *queue = [[NSNotificationQueue alloc] initWithNotificationCenter:center];
    Bell *bell = [[Bell alloc] initRinging];
    [queue enqueueNotification:bell postingStyle:NSPostWhenIdle coalesceMask:NSNotificationNoCoalescing forModes:nil];
    bellRaises = YES;
    @try {
        [queue dequeueNotificationsMatching:[NSNotification notificationWithName:@"Chime" object:nil]
                               coalesceMask:NSNotificationCoalescingOnName];
        say(@"queue: not raised");
    } @catch (NSException *exception) {
        say([NSString stringWithFormat:@"queue: %@: %@", exception.name, exception.reason]);
    }
    bellRaises = NO;
    say([NSString stringWithFormat:@"queue after: %@", elsewhere(^{
        [queue dequeueNotificationsMatching:bell coalesceMask:NSNotificationCoalescingOnName];
        [queue enqueueNotification:[NSNotification notificationWithName:@"Chime" object:nil] postingStyle:NSPostNow];
        return [NSString stringWithFormat:@"chimed %lu", (unsigned long)chimes];
    })]);
    [center removeObserver:observer];
}

// The descriptions of a collection's members, sorted.
static NSString *sorted(id<NSFastEnumeration> collection) {
    NSMutableArray *names = [NSMutableArray array];
    for (id member in collection) [names addObject:[member description]];
    return [[names sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@" "];
}

// Runs a call that should raise, saying what it raised.
static void attempt(NSString *label, void (^call)(void)) {
    @try {
        call();
        say([NSString stringWithFormat:@"%@: not raised", label]);
    } @catch (NSException *exception) {
        say([NSString stringWithFormat:@"%@: %@: %@", label, exception.name, exception.reason]);
    }
}

static void keyed(void) {
    Prickly *prickly = [Prickly new];

    NSMutableSet *set = [NSMutableSet setWithArray:[@"a b" componentsSeparatedByString:@" "]];
    [set addObject:prickly];
    attempt(@"set add, -hash", ^{ [set addObject:[Hasty new]]; });
    attempt(@"set add, -isEqual:", ^{ [set addObject:[Prickly new]]; });
    attempt(@"set member, -hash", ^{ [set containsObject:[Hasty new]]; });
    attempt(@"set remove, -hash", ^{ [set removeObject:[Hasty new]]; });
    attempt(@"set remove, -isEqual:", ^{ [set removeObject:[Prickly new]]; });
    [set addObject:@"c"];
    [set removeObject:@"a"];
    say([NSString stringWithFormat:@"set after: %@, count %lu, prickly %d", sorted(set),
         (unsigned long)set.count, [set containsObject:prickly]]);
    [set removeObject:prickly];
    [set addObject:@"d"];
    say([NSString stringWithFormat:@"set after removing prickly: %@", sorted(set)]);

    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    dictionary[@"one"] = @1;
    dictionary[prickly] = @"p";
    attempt(@"dictionary set, -hash", ^{ dictionary[[Hasty new]] = @2; });
    attempt(@"dictionary set, -isEqual:", ^{ dictionary[[Prickly new]] = @"q"; });
    attempt(@"dictionary get, -hash", ^{ [dictionary objectForKey:[Hasty new]]; });
    attempt(@"dictionary remove, -hash", ^{ [dictionary removeObjectForKey:[Hasty new]]; });
    attempt(@"dictionary remove, -isEqual:", ^{ [dictionary removeObjectForKey:[Prickly new]]; });
    dictionary[@"two"] = @2;
    dictionary[@"one"] = @11;
    [dictionary removeObjectForKey:@"two"];
    dictionary[@"three"] = @3;
    say([NSString stringWithFormat:@"dictionary after: %@, one %@, three %@, prickly %@, count %lu", sorted(dictionary),
         dictionary[@"one"], dictionary[@"three"], dictionary[prickly], (unsigned long)dictionary.count]);

    NSCountedSet *counted = [[NSCountedSet alloc] initWithArray:[@"a a b" componentsSeparatedByString:@" "]];
    [counted addObject:prickly];
    attempt(@"counted add, -hash", ^{ [counted addObject:[Hasty new]]; });
    attempt(@"counted add, -isEqual:", ^{ [counted addObject:[Prickly new]]; });
    attempt(@"counted remove, -isEqual:", ^{ [counted removeObject:[Prickly new]]; });
    [counted addObject:@"a"];
    [counted addObject:prickly];
    [counted removeObject:@"b"];
    say([NSString stringWithFormat:@"counted after: %@, a %lu, b %lu, prickly %lu", sorted(counted),
         (unsigned long)[counted countForObject:@"a"], (unsigned long)[counted countForObject:@"b"],
         (unsigned long)[counted countForObject:prickly]]);

    NSMutableOrderedSet *ordered = [NSMutableOrderedSet orderedSetWithArray:[@"a b" componentsSeparatedByString:@" "]];
    [ordered addObject:prickly];
    attempt(@"ordered add, -isEqual:", ^{ [ordered addObject:[Prickly new]]; });
    attempt(@"ordered insert, -hash", ^{ [ordered insertObject:[Hasty new] atIndex:0]; });
    attempt(@"ordered remove, -isEqual:", ^{ [ordered removeObject:[Prickly new]]; });
    [ordered insertObject:@"c" atIndex:1];
    [ordered removeObject:@"a"];
    [ordered exchangeObjectAtIndex:0 withObjectAtIndex:2];
    say([NSString stringWithFormat:@"ordered after: %@, prickly at %lu, b at %lu",
         [[ordered.array valueForKey:@"description"] componentsJoinedByString:@" "],
         (unsigned long)[ordered indexOfObject:prickly], (unsigned long)[ordered indexOfObject:@"b"]]);
}

int main(void) {
    @autoreleasepool {
        raised();
        array();
        divided();
        method();
        rethrown();
        classes();
        runtime();
        callbacks();
        locks();
        keyed();
        say(@"done");
    }
    return 0;
}
