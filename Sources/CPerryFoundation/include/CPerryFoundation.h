#ifndef CPERRY_FOUNDATION_H
#define CPERRY_FOUNDATION_H

// The parts of libPerryFoundation that must be C or assembly: class storage
// exported under Mach-O names, and entry points for variadic methods and
// functions.

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/eventfd.h>

// objc_class, filled in by the runtime (objc_initializeClassPair).
typedef struct perry_class_storage {
    struct perry_class_storage *isa;
    struct perry_class_storage *superclass;
    void *cache;
    void *vtable;
    uintptr_t bits;
} perry_class_storage;

// NSRange, passed by value in two registers.
typedef struct _NSRange {
    uintptr_t location;
    uintptr_t length;
} NSRange;

typedef enum perry_foundation_class_id {
    PERRY_CLASS_NSString,
    PERRY_CLASS_NSConstantString,   // ___CFConstantStringClassReference
    PERRY_CLASS_NSArray,
    PERRY_CLASS_NSMutableArray,
    PERRY_CLASS_NSNumber,
    PERRY_CLASS_NSConstantIntegerNumber,    // @42: { isa, const char *encoding, int64 value }
    PERRY_CLASS_NSConstantDoubleNumber,     // @2.5: { isa, double value }
    PERRY_CLASS_NSConstantFloatNumber,      // @2.5f: { isa, float value }
    PERRY_CLASS_NSCFBoolean,                // kCFBooleanTrue/False: { isa, uint64 value }
    PERRY_CLASS_NSMutableString,
    PERRY_CLASS_NSDictionary,
    PERRY_CLASS_NSMutableDictionary,
    PERRY_CLASS_NSSet,
    PERRY_CLASS_NSMutableSet,
    PERRY_CLASS_NSConstantArray,            // @[...]: { isa, uint64 count, id *objects }
    PERRY_CLASS_NSConstantDictionary,       // @{...}: { isa, uint64 options, uint64 count, id *keys, id *objects }
    PERRY_CLASS_NSDate,
    PERRY_CLASS_NSTimer,
    PERRY_CLASS_NSRunLoop,
    PERRY_CLASS_NSNotification,
    PERRY_CLASS_NSNotificationCenter,
    PERRY_CLASS_NSData,
    PERRY_CLASS_NSMutableData,
    PERRY_CLASS_NSURL,
    PERRY_CLASS_NSUUID,
    PERRY_CLASS_NSNull,
    PERRY_CLASS_NSJSONSerialization,
    PERRY_CLASS_NSProcessInfo,
    PERRY_CLASS_NSBundle,
    PERRY_CLASS_NSError,
    PERRY_CLASS_NSThread,
    PERRY_CLASS_NSUserDefaults,
    PERRY_CLASS_NSFileManager,
    PERRY_CLASS_NSUserActivity,
    PERRY_CLASS_COUNT,
} perry_foundation_class_id;

perry_class_storage *perry_foundation_class(perry_foundation_class_id which);

// The storage for the class named `name`, or NULL; sets `*metaclass`.
perry_class_storage *perry_foundation_class_named(const char *name, perry_class_storage **metaclass);
perry_class_storage *perry_foundation_metaclass(perry_foundation_class_id which);

// kCFBooleanTrue and kCFBooleanFalse: the objects behind @YES and @NO.
void *perry_foundation_boolean(int value);

// CoreFoundation's value types.
typedef struct {
    long location;
    long length;
} CFRange;

typedef struct {
    uint8_t byte0, byte1, byte2, byte3, byte4, byte5, byte6, byte7;
    uint8_t byte8, byte9, byte10, byte11, byte12, byte13, byte14, byte15;
} CFUUIDBytes;

// Key-value observing's setter for any argument type (kvo.S): it calls
// perry_foundation_kvo_will, which returns the setter it replaces, then
// perry_foundation_kvo_did.
void perry_kvo_setter(void);

// Calls a getter that may return a structure: x8 is `indirect`; x0, x1
// and d0 to d3 are saved in `registers` afterwards.
void perry_foundation_call_getter(void *object, const char *selector, const void *imp, void *indirect,
                                  uint64_t registers[6]);

// Calls a setter with x2, x3 and d0 to d3 from `registers`.
void perry_foundation_call_setter(void *object, const char *selector, const void *imp, const uint64_t registers[6]);

// -[NSProcessInfo operatingSystemVersion]. Larger than 16 bytes, so it is
// returned through x8 and passed by reference.
typedef struct NSOperatingSystemVersion {
    intptr_t majorVersion;
    intptr_t minorVersion;
    intptr_t patchVersion;
} NSOperatingSystemVersion;

// The calling thread's kernel id, for NSLog lines.
int perry_foundation_thread_id(void);

// Runs an NSThread's body, from which perry_foundation_thread_exit jumps
// back out; false if the calling thread is not running one.
void perry_foundation_thread_run(void (*body)(void *), void *context);
bool perry_foundation_thread_exit(void);

// The usable size of a malloc'd block (malloc_usable_size).
size_t perry_foundation_usable_size(void *block);

// Gives the empty @[] and @{} singletons their classes.
void perry_foundation_set_empty_array_class(void *cls);

// The predefined allocators: 0 system default, 1 malloc, 2 malloc zone,
// 3 null, 4 use context.
const void *perry_foundation_cf_allocator(int which);
void perry_foundation_set_empty_dictionary_class(void *cls);

// Variadic entry points (variadic.S). Apple's arm64 ABI passes variadic
// arguments in 8-byte stack slots; each entry point passes a pointer to
// them (a Darwin va_list) after the fixed arguments and branches to Swift.
// Declared without parameters: only their addresses are used.
void perry_imp_stringWithFormat(void);      // + (id)stringWithFormat:(NSString *)format, ...
void perry_imp_initWithFormat(void);        // - (id)initWithFormat:(NSString *)format, ...
void perry_imp_stringByAppendingFormat(void);
void perry_imp_arrayWithObjects(void);      // + (id)arrayWithObjects:(id)first, ... nil
void perry_imp_setWithObjects(void);        // + (id)setWithObjects:(id)first, ... nil
void perry_imp_dictionaryWithObjectsAndKeys(void); // + (id)dictionaryWithObjectsAndKeys:(id)first, ... nil
void perry_imp_predicateWithFormat(void);   // + (NSPredicate *)predicateWithFormat:(NSString *)format, ...
void perry_imp_appendFormat(void);          // - (void)appendFormat:(NSString *)format, ...
void perry_imp_initArrayWithObjects(void);  // - (id)initWithObjects:(id)first, ... nil, for arrays
void perry_imp_initSetWithObjects(void);    // - (id)initWithObjects:(id)first, ... nil, for sets
void perry_imp_initWithObjectsAndKeys(void); // - (id)initWithObjectsAndKeys:(id)first, ... nil
void perry_imp_raiseFormat(void);          // + (void)raise:(NSString *)name format:(NSString *)format, ...

/// A file's birth time, where its file system keeps one.
bool perry_foundation_birth_time(const char *path, int64_t *seconds, uint32_t *nanoseconds);

#endif
