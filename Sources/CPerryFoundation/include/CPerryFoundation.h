#ifndef CPERRY_FOUNDATION_H
#define CPERRY_FOUNDATION_H

// The parts of libPerryFoundation that must be C or assembly: class storage
// exported under Mach-O names, and entry points for variadic methods and
// functions.

#include <stdint.h>

// objc_class, filled in by the runtime (objc_initializeClassPair).
typedef struct perry_class_storage {
    struct perry_class_storage *isa;
    struct perry_class_storage *superclass;
    void *cache;
    void *vtable;
    uintptr_t bits;
} perry_class_storage;

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
    PERRY_CLASS_COUNT,
} perry_foundation_class_id;

perry_class_storage *perry_foundation_class(perry_foundation_class_id which);
perry_class_storage *perry_foundation_metaclass(perry_foundation_class_id which);

// The calling thread's kernel id, for NSLog lines.
int perry_foundation_thread_id(void);

// Variadic entry points (variadic.S). Apple's arm64 ABI passes variadic
// arguments in 8-byte stack slots; each entry point passes a pointer to
// them (a Darwin va_list) after the fixed arguments and branches to Swift.
// Declared without parameters: only their addresses are used.
void perry_imp_stringWithFormat(void);      // + (id)stringWithFormat:(NSString *)format, ...
void perry_imp_initWithFormat(void);        // - (id)initWithFormat:(NSString *)format, ...
void perry_imp_stringByAppendingFormat(void);
void perry_imp_arrayWithObjects(void);      // + (id)arrayWithObjects:(id)first, ... nil

#endif
