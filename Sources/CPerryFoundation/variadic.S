// Variadic Foundation functions and methods for arm64 ELF.
//
// Apple's arm64 ABI passes every variadic argument in an 8-byte stack slot
// starting at the caller's sp, which is a Darwin va_list. Each entry point
// passes that pointer after its fixed arguments and branches to Swift.

#if defined(__aarch64__) && defined(__ELF__)

.macro VARIADIC name, target, nfixed
    .globl \name
    .type \name, %function
    .p2align 2
\name:
    mov x\nfixed, sp
    b \target
    .size \name, . - \name
.endm

    .text

// void NSLog(NSString *format, ...)
VARIADIC _NSLog, perry_foundation_log, 1

// CFStringRef CFStringCreateWithFormat(CFAllocatorRef, CFDictionaryRef, CFStringRef, ...)
VARIADIC _CFStringCreateWithFormat, perry_foundation_cf_create_with_format, 3
// void CFStringAppendFormat(CFMutableStringRef, CFDictionaryRef, CFStringRef, ...)
VARIADIC _CFStringAppendFormat, perry_foundation_cf_append_format, 3

// Boolean CFCalendarDecomposeAbsoluteTime(CFCalendarRef, CFAbsoluteTime, const char *, ...):
// the time is in d0, so two fixed arguments are in x registers.
VARIADIC _CFCalendarDecomposeAbsoluteTime, perry_foundation_cf_calendar_decompose, 2
// Boolean CFCalendarComposeAbsoluteTime(CFCalendarRef, CFAbsoluteTime *, const char *, ...)
VARIADIC _CFCalendarComposeAbsoluteTime, perry_foundation_cf_calendar_compose, 3

// NSDictionary *_NSDictionaryOfVariableBindings(NSString *keys, id first, ...),
// which Auto Layout's NSDictionaryOfVariableBindings expands to.
VARIADIC __NSDictionaryOfVariableBindings, perry_foundation_dictionary_of_variable_bindings, 2

// Method implementations: self, _cmd, then the fixed arguments.
    .hidden perry_imp_stringWithFormat
VARIADIC perry_imp_stringWithFormat, perry_foundation_stringWithFormat, 3
    .hidden perry_imp_initWithFormat
VARIADIC perry_imp_initWithFormat, perry_foundation_initWithFormat, 3
    .hidden perry_imp_stringByAppendingFormat
VARIADIC perry_imp_stringByAppendingFormat, perry_foundation_stringByAppendingFormat, 3
    .hidden perry_imp_arrayWithObjects
VARIADIC perry_imp_arrayWithObjects, perry_foundation_arrayWithObjects, 3
    .hidden perry_imp_setWithObjects
VARIADIC perry_imp_setWithObjects, perry_foundation_setWithObjects, 3
    .hidden perry_imp_orderedSetWithObjects
VARIADIC perry_imp_orderedSetWithObjects, perry_foundation_orderedSetWithObjects, 3
    .hidden perry_imp_initOrderedSetWithObjects
VARIADIC perry_imp_initOrderedSetWithObjects, perry_foundation_initOrderedSetWithObjects, 3
    .hidden perry_imp_predicateWithFormat
VARIADIC perry_imp_predicateWithFormat, perry_foundation_predicateWithFormat, 3
    .hidden perry_imp_dictionaryWithObjectsAndKeys
VARIADIC perry_imp_dictionaryWithObjectsAndKeys, perry_foundation_dictionaryWithObjectsAndKeys, 3
    .hidden perry_imp_appendFormat
VARIADIC perry_imp_appendFormat, perry_foundation_appendFormat, 3
    .hidden perry_imp_initArrayWithObjects
VARIADIC perry_imp_initArrayWithObjects, perry_foundation_initArrayWithObjects, 3
    .hidden perry_imp_initSetWithObjects
VARIADIC perry_imp_initSetWithObjects, perry_foundation_initSetWithObjects, 3
    .hidden perry_imp_initWithObjectsAndKeys
VARIADIC perry_imp_initWithObjectsAndKeys, perry_foundation_initWithObjectsAndKeys, 3
    .hidden perry_imp_raiseFormat
VARIADIC perry_imp_raiseFormat, perry_foundation_raiseFormat, 4

    .section .note.GNU-stack, "", %progbits

#endif
