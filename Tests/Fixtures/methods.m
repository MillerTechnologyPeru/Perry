// Changes methods after messages have cached them: each change must reach
// the next send, through class_addMethod, method_setImplementation,
// method_exchangeImplementations and class_replaceMethod, and a release
// added after objects were released must be called.
int printf(const char *, ...);
typedef struct objc_object *id;
typedef struct objc_class *Class;
typedef struct objc_selector *SEL;
typedef struct objc_method *Method;
typedef void (*IMP)(void);
typedef _Bool BOOL;

Class objc_getClass(const char *name);
SEL sel_registerName(const char *name);
Method class_getInstanceMethod(Class cls, SEL name);
BOOL class_addMethod(Class cls, SEL name, IMP imp, const char *types);
IMP class_replaceMethod(Class cls, SEL name, IMP imp, const char *types);
IMP method_setImplementation(Method method, IMP imp);
IMP method_getImplementation(Method method);
void method_exchangeImplementations(Method first, Method second);
// As plain pointers, so ARC adds no retains and releases of its own.
void *objc_retain(void *object);
void objc_release(void *object);

__attribute__((objc_root_class))
@interface NSObject { Class isa; }
+ (instancetype)new;
- (void)release;
@end

@interface Base : NSObject
- (int)value;
- (int)other;
@end

@implementation Base
- (int)value { return 1; }
- (int)other { return 10; }
@end

@interface Derived : Base
@end

@implementation Derived
@end

static int two(id self, SEL _cmd) { return 2; }
static int three(id self, SEL _cmd) { return 3; }
static int four(id self, SEL _cmd) { return 4; }

static IMP plainRelease;
static int customReleases;
static void customRelease(id self, SEL _cmd) {
    customReleases++;
    ((void (*)(id, SEL))plainRelease)(self, _cmd);
}

int main(void) {
    Class base = objc_getClass("Base"), derived = objc_getClass("Derived");
    SEL value = sel_registerName("value"), other = sel_registerName("other");
    Base *b = [Base new];
    Derived *d = [Derived new];
    // Each send caches what it finds.
    printf("cached %d %d %d\n", [b value], [d value], [b other]);

    class_addMethod(derived, value, (IMP)two, "i16@0:8");
    printf("added %d %d\n", [b value], [d value]);

    method_setImplementation(class_getInstanceMethod(base, value), (IMP)three);
    printf("set %d %d\n", [b value], [d value]);

    method_exchangeImplementations(class_getInstanceMethod(base, value), class_getInstanceMethod(base, other));
    printf("exchanged %d %d\n", [b value], [b other]);

    class_replaceMethod(derived, value, (IMP)four, "i16@0:8");
    printf("replaced %d %d\n", [b value], [d value]);

    // Releases that used NSObject's, then one the class adds.
    objc_release(objc_retain((__bridge void *)d));
    SEL release = sel_registerName("release");
    plainRelease = method_getImplementation(class_getInstanceMethod(objc_getClass("NSObject"), release));
    class_addMethod(derived, release, (IMP)customRelease, "v16@0:8");
    objc_release(objc_retain((__bridge void *)d));
    printf("custom releases %d\n", customReleases);
    return 0;
}
