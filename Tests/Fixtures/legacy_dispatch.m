// Dynamic dispatch on i386's stack-based convention: methods added at run time,
// blocks as methods, and messages handed to another object. Each case returns
// a different way, since each way has its own entry point.
#include "darwin.h"

typedef struct objc_class *Class;
typedef struct objc_selector *SEL;
typedef id (*IMP)(id, SEL, ...);
typedef signed char BOOL;

@interface NSObject { Class isa; }
+ (id)alloc;
- (id)init;
- (void)release;
@end

BOOL class_addMethod(Class, SEL, IMP, const char *);
IMP imp_implementationWithBlock(id);
id imp_getBlock(IMP);
BOOL imp_removeBlock(IMP);
Class objc_getClass(const char *);
SEL sel_registerName(const char *);

typedef struct { double a, b, c; } Large;

@interface Target : NSObject
- (int)forwardedInt:(int)a :(double)b;
- (double)forwardedDouble:(double)a;
- (Large)forwardedLarge:(int)a;
@end

@implementation Target
- (int)forwardedInt:(int)a :(double)b { return a * 2 + (int)b; }
- (double)forwardedDouble:(double)a { return a / 2; }
- (Large)forwardedLarge:(int)a { Large l = { a, a + 1, a + 2 }; return l; }
@end

@interface Front : NSObject { Target *target; }
- (int)forwardedInt:(int)a :(double)b;
- (double)forwardedDouble:(double)a;
- (Large)forwardedLarge:(int)a;
- (int)resolved:(int)a;
- (int)fromBlock:(int)a :(int)b;
- (double)doubleFromBlock:(double)a;
- (Large)largeFromBlock:(int)a;
@end

static int resolved_imp(id self, SEL _cmd, int a) { return a + 40; }

@implementation Front
- (id)init { if ((self = [super init])) target = [[Target alloc] init]; return self; }
+ (BOOL)resolveInstanceMethod:(SEL)selector {
    if (selector == @selector(resolved:))
        return class_addMethod(self, selector, (IMP)resolved_imp, "i@:i");
    return 0;
}
- (id)forwardingTargetForSelector:(SEL)selector {
    return target;
}
@end

int main(void) {
    Front *front = [[Front alloc] init];
    printf("resolved %d\n", [front resolved:2]);
    printf("forward int %d\n", [front forwardedInt:4 :1.0]);
    printf("forward double %.2f\n", [front forwardedDouble:5.0]);
    Large forwarded = [front forwardedLarge:7];
    printf("forward large %.0f %.0f %.0f\n", forwarded.a, forwarded.b, forwarded.c);

    Class cls = objc_getClass("Front");
    int offset = 100;
    IMP sum = imp_implementationWithBlock(^int(id self, int a, int b) { return offset + a + b; });
    class_addMethod(cls, sel_registerName("fromBlock::"), sum, "i@:ii");
    printf("block %d\n", [front fromBlock:1 :2]);
    IMP twice = imp_implementationWithBlock(^double(id self, double a) { return a * 2; });
    class_addMethod(cls, sel_registerName("doubleFromBlock:"), twice, "d@:d");
    printf("block double %.2f\n", [front doubleFromBlock:1.25]);
    IMP large = imp_implementationWithBlock(^Large(id self, int a) { Large l = { a, a * 2.0, offset }; return l; });
    class_addMethod(cls, sel_registerName("largeFromBlock:"), large, "{?=ddd}@:i");
    Large fromBlock = [front largeFromBlock:6];
    printf("block large %.0f %.0f %.0f\n", fromBlock.a, fromBlock.b, fromBlock.c);
    printf("block kept %d\n", imp_getBlock(sum) != (id)0);
    printf("removed %d\n", imp_removeBlock(sum));
    [front release];
    return 0;
}
