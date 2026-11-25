// Exceptions Foundation raises, caught with @try and @catch: +raise:format:,
// an index past an array's end and a decimal number divided by zero. Also
// one raised in a method of the app's own, which a @finally block on the
// way out sees, a rethrow from a @catch block, a clause for another class
// that lets one by, a subclass of the app's caught by its own class and by
// NSException's, and @catch (id). And ones that unwind through the runtime's
// and Foundation's own frames: an unrecognized selector, an observer that
// raises from a KVO setter, and a method -[NSInvocation invoke] calls.

#import <Foundation/Foundation.h>
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

int main(void) {
    @autoreleasepool {
        raised();
        array();
        divided();
        method();
        rethrown();
        classes();
        runtime();
        say(@"done");
    }
    return 0;
}
