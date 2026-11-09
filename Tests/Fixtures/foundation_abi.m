// Exercises Foundation's variadic entry points and key-value coding and
// observing with structures: format strings mixing word-sized and 64-bit
// arguments, nil-terminated collection methods, predicates, CF formats, KVC
// through accessors that pass and return structures, and KVO's setter for
// scalar and structure properties. And floating point both ways across the
// boundary, which 32-bit Darwin passes in core registers: numbers, dates and
// CF functions Foundation implements, and accessors of this program's
// double, float and BOOL properties that Foundation calls.
//
// Built against the real Foundation where an SDK has it (to record the
// expected output on a Mac), and otherwise against the declarations below.
#if __has_include(<Foundation/Foundation.h>)
#import <Foundation/Foundation.h>
#include <stdio.h>
#else
#include "darwin.h"
typedef struct objc_object *id;
typedef struct objc_class *Class;
typedef struct objc_selector *SEL;
typedef signed char BOOL;
typedef unsigned long NSUInteger;
typedef long NSInteger;
#define nil ((id)0)
typedef struct _NSRange { NSUInteger location, length; } NSRange;
static inline NSRange NSMakeRange(NSUInteger location, NSUInteger length) { return (NSRange){location, length}; }
typedef const struct __CFString *CFStringRef;
typedef const struct __CFAllocator *CFAllocatorRef;
typedef const struct __CFDictionary *CFDictionaryRef;
typedef const void *CFTypeRef;
typedef const struct __CFDate *CFDateRef;
typedef double CFAbsoluteTime;
CFDateRef CFDateCreate(CFAllocatorRef, CFAbsoluteTime);
CFAbsoluteTime CFDateGetAbsoluteTime(CFDateRef);
CFAbsoluteTime CFAbsoluteTimeGetCurrent(void);
#define CFSTR(s) ((CFStringRef)__builtin___CFStringMakeConstantString(s))
CFStringRef CFStringCreateWithFormat(CFAllocatorRef, CFDictionaryRef, CFStringRef, ...);
void CFRelease(CFTypeRef);
enum { NSKeyValueObservingOptionNew = 1, NSKeyValueObservingOptionOld = 2 };
typedef NSUInteger NSKeyValueObservingOptions;

@class NSString, NSArray, NSDictionary, NSPredicate;

__attribute__((objc_root_class))
@interface NSObject { Class isa; }
+ (instancetype)alloc;
+ (instancetype)new;
+ (Class)class;
- (instancetype)init;
- (BOOL)isKindOfClass:(Class)cls;
- (NSString *)description;
- (id)valueForKey:(NSString *)key;
- (void)setValue:(id)value forKey:(NSString *)key;
- (void)addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath
            options:(NSKeyValueObservingOptions)options context:(void *)context;
- (void)removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath;
@end

@interface NSString : NSObject
+ (instancetype)stringWithFormat:(NSString *)format, ...;
+ (instancetype)stringWithString:(NSString *)string;
- (instancetype)initWithFormat:(NSString *)format, ...;
- (NSString *)stringByAppendingFormat:(NSString *)format, ...;
- (const char *)UTF8String;
@end
@interface NSMutableString : NSString
- (void)appendFormat:(NSString *)format, ...;
@end
@interface NSArray : NSObject
+ (instancetype)arrayWithObjects:(id)first, ...;
+ (instancetype)arrayWithObjects:(const id [])objects count:(NSUInteger)count;
- (NSString *)componentsJoinedByString:(NSString *)separator;
- (NSArray *)filteredArrayUsingPredicate:(NSPredicate *)predicate;
@end
@interface NSDictionary : NSObject
+ (instancetype)dictionaryWithObjectsAndKeys:(id)first, ...;
- (id)objectForKey:(id)key;
- (id)objectForKeyedSubscript:(id)key;
- (NSUInteger)count;
@end
@interface NSSet : NSObject
+ (instancetype)setWithObjects:(id)first, ...;
- (NSUInteger)count;
@end
@interface NSPredicate : NSObject
+ (NSPredicate *)predicateWithFormat:(NSString *)format, ...;
@end
@interface NSValue : NSObject
+ (NSValue *)valueWithRange:(NSRange)range;
+ (NSValue *)valueWithBytes:(const void *)value objCType:(const char *)type;
- (NSRange)rangeValue;
- (void)getValue:(void *)value;
- (const char *)objCType;
@end
@interface NSNumber : NSValue
+ (NSNumber *)numberWithInt:(int)value;
+ (NSNumber *)numberWithLongLong:(long long)value;
+ (NSNumber *)numberWithDouble:(double)value;
+ (NSNumber *)numberWithFloat:(float)value;
+ (NSNumber *)numberWithBool:(BOOL)value;
- (long long)longLongValue;
- (double)doubleValue;
- (float)floatValue;
- (BOOL)boolValue;
@end
@interface NSDate : NSObject
+ (instancetype)dateWithTimeIntervalSinceReferenceDate:(double)interval;
- (double)timeIntervalSinceReferenceDate;
- (instancetype)dateByAddingTimeInterval:(double)interval;
@end
@interface NSString (Numbers)
- (double)doubleValue;
- (float)floatValue;
@end
void NSLog(NSString *format, ...);
extern NSString *const NSKeyValueChangeNewKey;
extern NSString *const NSKeyValueChangeOldKey;
#endif

// 16 bytes: r2, r3 and two words of the stack on armv7.
typedef struct { double x, y; } Pair;

@interface Item : NSObject
#if defined(__i386__) && !__OBJC2__
{ int count; double weight; float ratio; BOOL flag; long long big; NSRange range; Pair pair; }
#endif
@property (nonatomic) int count;
@property (nonatomic) double weight;
@property (nonatomic) float ratio;
@property (nonatomic) BOOL flag;
@property (nonatomic) long long big;
@property (nonatomic) NSRange range;
@property (nonatomic) Pair pair;
@end
@implementation Item
#if defined(__i386__) && !__OBJC2__
// The old ABI synthesizes nothing by itself, and needs the variables declared.
@synthesize count, weight, ratio, flag, big, range, pair;
#endif
@end

static void show(NSString *string) { printf("%s\n", [string UTF8String]); }

// A KVC or KVO value: a number's integer, a structure's fields.
static void describe(const char *label, id value) {
    char type = [value isKindOfClass:[NSNumber class]] ? [(NSNumber *)value objCType][0] : 0;
    if (type == 'd' || type == 'f') {
        printf("%s %.3f\n", label, [(NSNumber *)value doubleValue]);
    } else if ([value isKindOfClass:[NSNumber class]]) {
        printf("%s %lld\n", label, [(NSNumber *)value longLongValue]);
    } else if ([value isKindOfClass:[NSValue class]] && [(NSValue *)value objCType][1] == '_') {
        NSRange range = [(NSValue *)value rangeValue];
        printf("%s range %lu %lu\n", label, (unsigned long)range.location, (unsigned long)range.length);
    } else if ([value isKindOfClass:[NSValue class]]) {
        Pair pair;
        [(NSValue *)value getValue:&pair];
        printf("%s pair %.2f %.2f\n", label, pair.x, pair.y);
    } else {
        printf("%s %s\n", label, value ? "?" : "nil");
    }
}

@interface Watcher : NSObject
@end
@implementation Watcher
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context {
    printf("changed %s\n", [keyPath UTF8String]);
    describe("  old", [change objectForKey:NSKeyValueChangeOldKey]);
    describe("  new", [change objectForKey:NSKeyValueChangeNewKey]);
}
@end

int main(void) {
    @autoreleasepool {
        show([NSString stringWithFormat:@"int %d long %ld llong %lld unsigned %u", -7, -123456L, -9876543210LL, 4000000000u]);
        show([NSString stringWithFormat:@"double %.3f float %g mixed %d %f %lld %@ %s", 3.14159, 2.5f, 1, 0.5,
              1LL << 40, @"object", "cstring"]);
        show([NSString stringWithFormat:@"%5.2f|%-4d|%x|%llx|%lu|%c|%*d", 1.5, 42, 255u, 0x123456789abcULL,
              (unsigned long)77, 'Z', 5, 3]);
        NSMutableString *mutable = (NSMutableString *)[NSMutableString stringWithString:@"mutable"];
        [mutable appendFormat:@" %d %.1f %lld", 2, 3.0, 4LL];
        show(mutable);
        show([@"prefix" stringByAppendingFormat:@" %lld %d", 5000000000LL, 6]);
        show([[NSString alloc] initWithFormat:@"%@ %d %.2f", @"init", 9, 0.25]);
        NSLog(@"NSLog %d %lld %.1f %@", 1, 2LL, 3.0, @"four");

        NSArray *letters = [NSArray arrayWithObjects:@"a", @"b", @"c", nil];
        show([letters componentsJoinedByString:@","]);
        NSDictionary *names = [NSDictionary dictionaryWithObjectsAndKeys:@"1", @"one", @"2", @"two", nil];
        show([NSString stringWithFormat:@"%@ %@ %lu", names[@"one"], names[@"two"], (unsigned long)[names count]]);
        printf("set %lu\n", (unsigned long)[[NSSet setWithObjects:@"x", @"y", @"x", nil] count]);

        NSArray *numbers = @[ @1, @5, @10, @5000000000LL ];
        NSPredicate *between = [NSPredicate predicateWithFormat:@"self > %d AND self < %lld", 2, 6000000000LL];
        show([[numbers filteredArrayUsingPredicate:between] componentsJoinedByString:@","]);
        NSPredicate *above = [NSPredicate predicateWithFormat:@"self >= %f AND self != %ld", 4.5, 10L];
        show([[numbers filteredArrayUsingPredicate:above] componentsJoinedByString:@","]);

        CFStringRef cf = CFStringCreateWithFormat(NULL, NULL, CFSTR("cf %d %lld %.2f %@"), 1, 2LL, 3.0, @"four");
        show((__bridge NSString *)cf);
        CFRelease(cf);

        Item *item = [Item new];
        [item setValue:@3 forKey:@"count"];
        [item setValue:@123456789012LL forKey:@"big"];
        [item setValue:[NSValue valueWithRange:NSMakeRange(4, 7)] forKey:@"range"];
        Pair pair = {1.5, -2.25};
        [item setValue:[NSValue valueWithBytes:&pair objCType:@encode(Pair)] forKey:@"pair"];
        printf("set %d %lld %lu %lu %.2f %.2f\n", item.count, item.big, (unsigned long)item.range.location,
               (unsigned long)item.range.length, item.pair.x, item.pair.y);
        describe("count", [item valueForKey:@"count"]);
        describe("big", [item valueForKey:@"big"]);
        describe("range", [item valueForKey:@"range"]);
        describe("pair", [item valueForKey:@"pair"]);

        NSNumber *d = [NSNumber numberWithDouble:-2.5];
        NSNumber *f = [NSNumber numberWithFloat:0.75f];
        printf("numbers %.3f %.3f %.3f %.3f %.3f %lld\n", [d doubleValue], [d floatValue], [f doubleValue], [f floatValue],
               [@1.25 doubleValue], [@7.5 longLongValue]);
        printf("strings %.3f %.3f\n", [@"3.25" doubleValue], [@"-0.5" floatValue]);
        NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:1000.25];
        printf("date %.3f %.3f\n", [date timeIntervalSinceReferenceDate],
               [[date dateByAddingTimeInterval:-0.5] timeIntervalSinceReferenceDate]);
        CFDateRef cfDate = CFDateCreate(NULL, 12345.5);
        printf("cf date %.3f now %d\n", CFDateGetAbsoluteTime(cfDate), CFAbsoluteTimeGetCurrent() > 7e8);
        CFRelease(cfDate);
        [item setValue:@2.5 forKey:@"weight"];
        [item setValue:[NSNumber numberWithFloat:0.125f] forKey:@"ratio"];
        [item setValue:[NSNumber numberWithBool:1] forKey:@"flag"];
        printf("floats %.3f %.3f %d\n", item.weight, item.ratio, item.flag);
        describe("weight", [item valueForKey:@"weight"]);
        describe("ratio", [item valueForKey:@"ratio"]);
        printf("flag %d\n", [[item valueForKey:@"flag"] boolValue]);

        Watcher *watcher = [Watcher new];
        NSString *keys[] = { @"count", @"big", @"range", @"pair", @"weight", @"ratio" };
        for (int i = 0; i < 6; i++)
            [item addObserver:watcher forKeyPath:keys[i]
                      options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld context:NULL];
        item.count = 4;
        item.big = 1LL << 35;
        item.range = NSMakeRange(1, 2);
        item.pair = (Pair){3.5, 4.75};
        item.weight = -1.5;
        item.ratio = 3.25f;
        for (int i = 0; i < 6; i++)
            [item removeObserver:watcher forKeyPath:keys[i]];
        item.count = 5;
        printf("after %d %lld %lu %.2f\n", item.count, item.big, (unsigned long)item.range.length, item.pair.y);
    }
    return 0;
}
