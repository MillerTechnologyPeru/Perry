#ifndef CPERRY_FOUNDATION_H
#define CPERRY_FOUNDATION_H

// The parts of libPerryFoundation that must be C or assembly: class storage
// exported under Mach-O names, and entry points for variadic methods and
// functions.

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
    PERRY_CLASS_COUNT,
} perry_foundation_class_id;

perry_class_storage *perry_foundation_class(perry_foundation_class_id which);

// The storage for the class named `name`, or NULL; sets `*metaclass`.
perry_class_storage *perry_foundation_class_named(const char *name, perry_class_storage **metaclass);
perry_class_storage *perry_foundation_metaclass(perry_foundation_class_id which);

// kCFBooleanTrue and kCFBooleanFalse: the objects behind @YES and @NO.
void *perry_foundation_boolean(int value);

// -[NSProcessInfo operatingSystemVersion]. Larger than 16 bytes, so it is
// returned through x8 and passed by reference.
typedef struct NSOperatingSystemVersion {
    intptr_t majorVersion;
    intptr_t minorVersion;
    intptr_t patchVersion;
} NSOperatingSystemVersion;

// The calling thread's kernel id, for NSLog lines.
int perry_foundation_thread_id(void);

// Gives the empty @[] and @{} singletons their classes.
void perry_foundation_set_empty_array_class(void *cls);
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

#endif
