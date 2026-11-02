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

// Method implementations: self, _cmd, then the fixed arguments.
    .hidden perry_imp_stringWithFormat
VARIADIC perry_imp_stringWithFormat, perry_foundation_stringWithFormat, 3
    .hidden perry_imp_initWithFormat
VARIADIC perry_imp_initWithFormat, perry_foundation_initWithFormat, 3
    .hidden perry_imp_stringByAppendingFormat
VARIADIC perry_imp_stringByAppendingFormat, perry_foundation_stringByAppendingFormat, 3
    .hidden perry_imp_arrayWithObjects
VARIADIC perry_imp_arrayWithObjects, perry_foundation_arrayWithObjects, 3

    .section .note.GNU-stack, "", %progbits

#endif
