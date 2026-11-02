// Class storage Mach-O images bind to, under Darwin's symbol names.

#define _GNU_SOURCE
#include "CPerryFoundation.h"

#include <unistd.h>

int perry_foundation_thread_id(void) { return (int)gettid(); }

#define DARWIN_SYMBOL(name) __asm__(name) __attribute__((visibility("default"), used))

perry_class_storage ns_string DARWIN_SYMBOL("_OBJC_CLASS_$_NSString");
perry_class_storage ns_string_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSString");
// String literals' isa. CoreFoundation exports it as an array; it is the
// class of constant strings.
perry_class_storage cf_constant_string DARWIN_SYMBOL("___CFConstantStringClassReference");
static perry_class_storage cf_constant_string_meta;
perry_class_storage ns_array DARWIN_SYMBOL("_OBJC_CLASS_$_NSArray");
perry_class_storage ns_array_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSArray");
perry_class_storage ns_mutable_array DARWIN_SYMBOL("_OBJC_CLASS_$_NSMutableArray");
perry_class_storage ns_mutable_array_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSMutableArray");
perry_class_storage ns_number DARWIN_SYMBOL("_OBJC_CLASS_$_NSNumber");
perry_class_storage ns_number_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSNumber");
// Number literals the compiler emits as static objects.
perry_class_storage ns_constant_integer DARWIN_SYMBOL("_OBJC_CLASS_$_NSConstantIntegerNumber");
perry_class_storage ns_constant_integer_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSConstantIntegerNumber");
perry_class_storage ns_constant_double DARWIN_SYMBOL("_OBJC_CLASS_$_NSConstantDoubleNumber");
perry_class_storage ns_constant_double_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSConstantDoubleNumber");
perry_class_storage ns_constant_float DARWIN_SYMBOL("_OBJC_CLASS_$_NSConstantFloatNumber");
perry_class_storage ns_constant_float_meta DARWIN_SYMBOL("_OBJC_METACLASS_$_NSConstantFloatNumber");
static perry_class_storage cf_boolean, cf_boolean_meta;

// The boolean objects, which @YES and @NO reference directly, and
// kCFBooleanTrue/False, which point at them.
struct perry_boolean { perry_class_storage *isa; uint64_t value; };
struct perry_boolean boolean_true DARWIN_SYMBOL("___kCFBooleanTrue") = { &cf_boolean, 1 };
struct perry_boolean boolean_false DARWIN_SYMBOL("___kCFBooleanFalse") = { &cf_boolean, 0 };
const struct perry_boolean *const cf_boolean_true DARWIN_SYMBOL("_kCFBooleanTrue") = &boolean_true;
const struct perry_boolean *const cf_boolean_false DARWIN_SYMBOL("_kCFBooleanFalse") = &boolean_false;

static perry_class_storage *const classes[PERRY_CLASS_COUNT][2] = {
    [PERRY_CLASS_NSString] = { &ns_string, &ns_string_meta },
    [PERRY_CLASS_NSConstantString] = { &cf_constant_string, &cf_constant_string_meta },
    [PERRY_CLASS_NSArray] = { &ns_array, &ns_array_meta },
    [PERRY_CLASS_NSMutableArray] = { &ns_mutable_array, &ns_mutable_array_meta },
    [PERRY_CLASS_NSNumber] = { &ns_number, &ns_number_meta },
    [PERRY_CLASS_NSConstantIntegerNumber] = { &ns_constant_integer, &ns_constant_integer_meta },
    [PERRY_CLASS_NSConstantDoubleNumber] = { &ns_constant_double, &ns_constant_double_meta },
    [PERRY_CLASS_NSConstantFloatNumber] = { &ns_constant_float, &ns_constant_float_meta },
    [PERRY_CLASS_NSCFBoolean] = { &cf_boolean, &cf_boolean_meta },
};

perry_class_storage *perry_foundation_class(perry_foundation_class_id which) { return classes[which][0]; }
perry_class_storage *perry_foundation_metaclass(perry_foundation_class_id which) { return classes[which][1]; }
