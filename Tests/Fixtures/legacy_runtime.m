// The Objective-C runtime as 32-bit Mac programs use it: the old ABI, whose
// classes name their superclasses and whose instance variables are at fixed
// offsets, and setjmp-based exceptions. Not ARC, which that ABI does not have.
#include "darwin.h"

typedef struct objc_class *Class;
typedef struct objc_selector *SEL;
#define nil ((id)0)
typedef signed char BOOL;

@class Protocol;

@interface NSObject { Class isa; }
+ (id)alloc;
+ (Class)class;
+ (Class)superclass;
- (id)init;
- (void)release;
- (BOOL)isKindOfClass:(Class)cls;
- (BOOL)respondsToSelector:(SEL)selector;
- (BOOL)conformsToProtocol:(Protocol *)protocol;
@end

typedef struct { float x, y; } Small;
typedef struct { double a, b, c; } Large;

@protocol Named
- (int)number;
@end

@interface Base : NSObject <Named> {
@public
    int first;
    char middle;
    double last;
}
+ (int)classValue;
- (id)initWithFirst:(int)value;
- (int)number;
- (double)half;
- (float)quarter;
- (long long)wide;
- (Small)small;
- (Large)large;
- (int)sum:(int)a :(double)b :(long long)c :(float)d;
@end

@implementation Base
+ (void)load { printf("load Base\n"); }
+ (int)classValue { return 10; }
- (id)initWithFirst:(int)value {
    if ((self = [super init])) {
        first = value;
        middle = 'm';
        last = 2.5;
    }
    return self;
}
- (int)number { return first; }
- (double)half { return first / 2.0; }
- (float)quarter { return first / 4.0f; }
- (long long)wide { return 0x100000000ll * first; }
- (Small)small { Small s = { first, 2 }; return s; }
- (Large)large { Large l = { first, last, 3 }; return l; }
- (int)sum:(int)a :(double)b :(long long)c :(float)d { return a + (int)b + (int)c + (int)d; }
@end

@interface Derived : Base { @public int extra; }
@end

@implementation Derived
+ (int)classValue { return [super classValue] + 1; }
- (id)initWithFirst:(int)value {
    if ((self = [super initWithFirst:value])) extra = value * 2;
    return self;
}
- (int)number { return [super number] + 100; }
- (Large)large { Large l = [super large]; l.c = 4; return l; }
@end

@interface Base (Added)
- (int)added;
@end

@implementation Base (Added)
+ (void)load { printf("load Added\n"); }
- (int)added { return first + 1; }
@end

@interface Thrown : NSObject
@end
@implementation Thrown
@end

@interface OtherThrown : NSObject
@end
@implementation OtherThrown
@end

static void thrower(id object) { @throw object; }

static int caught_kind(id object) {
    int result = 0;
    @try {
        @try {
            thrower(object);
            result = -1;
        } @catch (OtherThrown *other) {
            result = 2;
        } @finally {
            result += 10;
        }
    } @catch (Thrown *thrown) {
        result += 100;
    } @catch (id anything) {
        result += 1000;
    }
    return result;
}

int main(void) {
    Derived *d = [[Derived alloc] initWithFirst:8];
    printf("ivars %d %c %.1f %d\n", d->first, d->middle, d->last, d->extra);
    printf("numbers %d %d\n", [d number], [Derived classValue]);
    printf("fp %.2f %.2f\n", [d half], [d quarter]);
    printf("wide %llx\n", [d wide]);
    Small s = [d small];
    Large l = [d large];
    printf("structs %.0f %.0f %.0f %.1f %.0f\n", s.x, s.y, l.a, l.b, l.c);
    printf("sum %d\n", [d sum:1 :2.0 :3ll :4.0f]);
    printf("added %d\n", [d added]);
    printf("kind %d %d %d\n", [d isKindOfClass:[Base class]], [d isKindOfClass:[Thrown class]],
           [Derived superclass] == [Base class]);
    printf("responds %d %d\n", [d respondsToSelector:@selector(added)], [d respondsToSelector:@selector(missing)]);
    printf("protocol %d %d\n", [d conformsToProtocol:@protocol(Named)], [[Thrown alloc] conformsToProtocol:@protocol(Named)]);
    Base *none = nil;
    printf("nil %d %.1f %lld\n", [none number], [none half], [none wide]);
    printf("caught %d %d %d\n", caught_kind([[Thrown alloc] init]), caught_kind([[OtherThrown alloc] init]),
           caught_kind([[NSObject alloc] init]));
    [d release];
    return 0;
}
