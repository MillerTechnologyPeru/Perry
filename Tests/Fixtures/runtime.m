// Exercises the Objective-C runtime without Foundation: +initialize, super
// sends, introspection, ARC deallocation, __weak, associated objects and
// autorelease pools. With an argument, sends an unimplemented message.
int printf(const char *, ...);
typedef struct objc_object *id;
typedef struct objc_class *Class;
typedef struct objc_selector *SEL;
typedef _Bool BOOL;
#define nil ((id)0)

const char *object_getClassName(id object);
void objc_setAssociatedObject(id object, const void *key, id value, unsigned long policy);

__attribute__((objc_root_class))
@interface NSObject { Class isa; }
+ (instancetype)alloc;
+ (instancetype)new;
+ (Class)class;
- (instancetype)init;
- (BOOL)respondsToSelector:(SEL)selector;
- (BOOL)isKindOfClass:(Class)cls;
- (BOOL)isMemberOfClass:(Class)cls;
@end

@interface NSObject (Missing)
- (void)missingMethod;
@end

@interface Base : NSObject
@property (nonatomic, strong) id child;
+ (instancetype)make;
- (const char *)name;
@end

@implementation Base
+ (void)initialize { printf("+initialize %s\n", object_getClassName((id)self)); }
+ (instancetype)make { return [self new]; }
- (const char *)name { return "base"; }
- (void)dealloc { printf("dealloc %s\n", [self name]); }
@end

@interface Derived : Base
- (const char *)superName;
@end

@implementation Derived
- (const char *)name { return "derived"; }
- (const char *)superName { return [super name]; }
@end

static char key;

int main(int argc, char **argv) {
    @autoreleasepool {
        __attribute__((objc_precise_lifetime)) Derived *derived = [Derived new];
        printf("%s %s\n", [derived name], [derived superName]);
        printf("responds %d %d\n", [derived respondsToSelector:@selector(superName)],
               [derived respondsToSelector:@selector(missingMethod)]);
        printf("kind %d %d\n", [derived isKindOfClass:[Base class]], [derived isMemberOfClass:[Base class]]);

        __weak Base *weak;
        {
            __attribute__((objc_precise_lifetime)) Base *base = [Base new];
            weak = base;
            printf("weak %s\n", weak ? "set" : "nil");
        }
        printf("weak %s\n", weak ? "set" : "nil");

        Base *parent = [Base new];
        parent.child = [Derived new];
        parent = nil;

        Base *owner = [Base new];
        objc_setAssociatedObject(owner, &key, [Derived new], 1);
        owner = nil;

        @autoreleasepool {
            [Base make];
            printf("in pool\n");
        }
        printf("after pool\n");

        if (argc > 1)
            [derived missingMethod];
    }
    return 0;
}
