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
    .hidden perry_imp_predicateWithFormat
VARIADIC perry_imp_predicateWithFormat, perry_foundation_predicateWithFormat, 3
    .hidden perry_imp_dictionaryWithObjectsAndKeys
VARIADIC perry_imp_dictionaryWithObjectsAndKeys, perry_foundation_dictionaryWithObjectsAndKeys, 3
    .hidden perry_imp_appendFormat
VARIADIC perry_imp_appendFormat, perry_foundation_appendFormat, 3

    .section .note.GNU-stack, "", %progbits

#endif
