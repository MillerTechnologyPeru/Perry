// Objective-C exceptions: @throw and @catch by class, in order, and by id;
// @finally on the way out either way; nested handlers that do not match;
// rethrowing; leaving a function whose ARC objects stay (without
// -fobjc-arc-exceptions ARC does not release them); and NSException raised
// by Foundation, caught with its name and reason; with an argument, one no
// handler catches. Built against the real
// Foundation where an SDK has it, to record the expected output on a Mac.
#if __has_include(<Foundation/Foundation.h>)
#import <Foundation/Foundation.h>
#include <stdio.h>
#else
#include "darwin.h"
typedef struct objc_class *Class;
typedef signed char BOOL;
#define nil ((id)0)

@class NSString;

__attribute__((objc_root_class))
@interface NSObject { Class isa; }
+ (instancetype)alloc;
+ (instancetype)new;
+ (Class)class;
- (instancetype)init;
- (BOOL)isKindOfClass:(Class)cls;
@end

@interface NSString : NSObject
- (const char *)UTF8String;
@end

@interface NSException : NSObject
+ (void)raise:(NSString *)name format:(NSString *)format, ...;
+ (NSException *)exceptionWithName:(NSString *)name reason:(NSString *)reason userInfo:(id)userInfo;
- (NSString *)name;
- (NSString *)reason;
- (void)raise;
@end
#endif

@interface Failure : NSObject
@property (nonatomic) int code;
@end
@implementation Failure
@end

@interface Other : NSObject
@end
@implementation Other
@end

@interface Tracked : NSObject
@property (nonatomic) const char *label;
@end
@implementation Tracked
- (void)dealloc { printf("dealloc %s\n", self.label); }
@end

static void fail(int code) {
    Failure *failure = [Failure new];
    failure.code = code;
    @throw failure;
}

// An object ARC does not release as the exception leaves: it is never
// deallocated, on Darwin either.
static void fail_holding(int code) {
    Tracked *tracked = [Tracked new];
    tracked.label = "held";
    fail(code);
    printf("not reached %s\n", tracked.label);
}

static int nested(void) {
    @try {
        @try {
            fail(2);
        } @catch (Other *other) {
            printf("wrong handler\n");
        } @finally {
            printf("inner finally\n");
        }
    } @catch (Failure *failure) {
        return failure.code;
    }
    return 0;
}

static void rethrows(void) {
    @try {
        fail(3);
    } @catch (Failure *failure) {
        printf("caught %d, rethrowing\n", failure.code);
        @throw;
    }
}

int main(int argc, char **argv) {
    (void)argv;
    @autoreleasepool {
        // With an argument, an exception no handler catches.
        if (argc > 1)
            [NSException raise:@"PerryError" format:@"uncaught %d", 6];

        @try {
            fail(1);
        } @catch (Other *other) {
            printf("wrong handler\n");
        } @catch (Failure *failure) {
            printf("caught failure %d\n", failure.code);
        } @catch (id anything) {
            printf("wrong handler\n");
        } @finally {
            printf("finally after catch\n");
        }

        @try {
            printf("no exception\n");
        } @finally {
            printf("finally without one\n");
        }

        printf("nested %d\n", nested());

        @try {
            rethrows();
        } @catch (Failure *failure) {
            printf("caught rethrown %d\n", failure.code);
        }

        @try {
            fail_holding(4);
        } @catch (Failure *failure) {
            printf("caught after unwinding %d\n", failure.code);
        }

        @try {
            @throw [Other new];
        } @catch (id anything) {
            printf("caught any %s\n", [anything isKindOfClass:[Other class]] ? "Other" : "?");
        }

        @try {
            [NSException raise:@"PerryError" format:@"code %d", 5];
        } @catch (Failure *failure) {
            printf("wrong handler\n");
        } @catch (NSException *exception) {
            printf("caught %s: %s\n", [[exception name] UTF8String], [[exception reason] UTF8String]);
        }

        @try {
            [[NSException exceptionWithName:@"Second" reason:@"raised" userInfo:nil] raise];
        } @catch (NSException *exception) {
            printf("caught %s: %s\n", [[exception name] UTF8String], [[exception reason] UTF8String]);
        }
        printf("done\n");
    }
    return 0;
}
