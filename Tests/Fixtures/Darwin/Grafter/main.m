// CFPlugIn, built on a Mac with Xcode: the app is its own plug-in, its
// Info.plist naming a factory in its executable and the type it makes, and
// factories registered by function and by name.
#import <Foundation/Foundation.h>
#include <CoreFoundation/CFPlugInCOM.h>

static void print(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

typedef struct {
    IUNKNOWN_C_GUTS;
    int (*speak)(void *self);
} Greeter;

static ULONG addRef(void *self) { return 1; }
static ULONG release(void *self) { return 0; }
static HRESULT query(void *self, REFIID iid, LPVOID *out) { *out = self; return S_OK; }
static int speak(void *self) { return 42; }
static Greeter table = {NULL, query, addRef, release, speak};
static Greeter *instance = &table;

static NSString *name(CFUUIDRef uuid) { return CFBridgingRelease(CFUUIDCreateString(NULL, uuid)); }

/// The factory the Info.plist names, found in the executable by name.
__attribute__((visibility("default"))) void *GreeterFactory(CFAllocatorRef allocator, CFUUIDRef type) {
    print([NSString stringWithFormat:@"factory called for %@", name(type)]);
    return &instance;
}

static void *SecondFactory(CFAllocatorRef allocator, CFUUIDRef type) {
    print(@"second factory called");
    return &instance;
}

static NSString *factories(CFArrayRef array) {
    if (!array) return @"none";
    NSMutableArray *names = [NSMutableArray array];
    for (CFIndex i = 0; i < CFArrayGetCount(array); i++) [names addObject:name(CFArrayGetValueAtIndex(array, i))];
    CFRelease(array);
    return [names componentsJoinedByString:@","];
}

int main(void) {
    @autoreleasepool {
        CFUUIDRef type = CFUUIDCreateFromString(NULL, CFSTR("B2B2B2B2-0000-0000-0000-000000000002"));
        CFUUIDRef factory = CFUUIDCreateFromString(NULL, CFSTR("A1A1A1A1-0000-0000-0000-000000000001"));
        CFUUIDRef second = CFUUIDCreateFromString(NULL, CFSTR("C3C3C3C3-0000-0000-0000-000000000003"));
        CFUUIDRef other = CFUUIDCreateFromString(NULL, CFSTR("D4D4D4D4-0000-0000-0000-000000000004"));

        print([NSString stringWithFormat:@"before %@", factories(CFPlugInFindFactoriesForPlugInType(type))]);
        CFURLRef url = CFBundleCopyBundleURL(CFBundleGetMainBundle());
        CFPlugInRef plugIn = CFPlugInCreate(NULL, url);
        print([NSString stringWithFormat:@"plug-in %d main %d type %d bundle %d on demand %d", plugIn != NULL,
               plugIn == CFBundleGetMainBundle(), CFPlugInGetTypeID() == CFBundleGetTypeID(), CFPlugInGetBundle(plugIn) == plugIn,
               CFPlugInIsLoadOnDemand(plugIn)]);
        print([NSString stringWithFormat:@"after %@ in plug-in %@", factories(CFPlugInFindFactoriesForPlugInType(type)),
               factories(CFPlugInFindFactoriesForPlugInTypeInPlugIn(type, plugIn))]);

        void **made = CFPlugInInstanceCreate(NULL, factory, type);
        print([NSString stringWithFormat:@"instance %d speaks %d", made != NULL, made ? (*(Greeter **)made)->speak(made) : -1]);
        IUnknownVTbl **unknown = (IUnknownVTbl **)made;
        void *interface = NULL;
        HRESULT queried = (*unknown)->QueryInterface(unknown, CFUUIDGetUUIDBytes(type), &interface);
        print([NSString stringWithFormat:@"query %d same %d", (int)queried, interface == made]);

        Boolean registered = CFPlugInRegisterFactoryFunction(second, SecondFactory);
        Boolean typed = CFPlugInRegisterPlugInType(second, type);
        print([NSString stringWithFormat:@"registered %d %d factories %@", registered, typed, factories(CFPlugInFindFactoriesForPlugInType(type))]);
        print([NSString stringWithFormat:@"second instance %d", CFPlugInInstanceCreate(NULL, second, type) != NULL]);
        print([NSString stringWithFormat:@"in plug-in %@", factories(CFPlugInFindFactoriesForPlugInTypeInPlugIn(type, plugIn))]);
        CFPlugInUnregisterPlugInType(second, type);
        print([NSString stringWithFormat:@"type unregistered %@", factories(CFPlugInFindFactoriesForPlugInType(type))]);
        CFPlugInRegisterPlugInType(second, type);
        CFPlugInUnregisterFactory(second);
        print([NSString stringWithFormat:@"factory unregistered %@ instance %d", factories(CFPlugInFindFactoriesForPlugInType(type)),
               CFPlugInInstanceCreate(NULL, second, type) != NULL]);

        print([NSString stringWithFormat:@"other type %@ instance %d", factories(CFPlugInFindFactoriesForPlugInType(other)),
               CFPlugInInstanceCreate(NULL, factory, other) != NULL]);
        Boolean byName = CFPlugInRegisterFactoryFunctionByName(other, plugIn, CFSTR("GreeterFactory"));
        CFPlugInRegisterPlugInType(other, other);
        print([NSString stringWithFormat:@"by name %d", byName]);
        print([NSString stringWithFormat:@"by name instance %d", CFPlugInInstanceCreate(NULL, other, other) != NULL]);

        CFPlugInAddInstanceForFactory(factory);
        CFPlugInRemoveInstanceForFactory(factory);
        CFPlugInSetLoadOnDemand(plugIn, false);
        print([NSString stringWithFormat:@"on demand %d", CFPlugInIsLoadOnDemand(plugIn)]);
        CFPlugInSetLoadOnDemand(plugIn, true);
        print([NSString stringWithFormat:@"on demand again %d", CFPlugInIsLoadOnDemand(plugIn)]);
    }
    return 0;
}
