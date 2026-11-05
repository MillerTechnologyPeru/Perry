// Variadic Foundation functions and methods for armv7 ELF, Darwin's calling
// convention.
//
// Darwin's armv7 lays variadic arguments out contiguously from the first
// register after the fixed arguments: r0-r3, then the caller's stack. A
// Darwin va_list is a pointer into that area. Each entry point stores r0-r3
// just below the caller's stack arguments, which makes the area contiguous,
// and calls Swift with a pointer to the first variadic word after its fixed
// arguments: in the next register, or for four fixed arguments on the stack.
// Darwin's stack is 4-byte aligned at calls and Linux's 8, so the call
// realigns it.

#if defined(__arm__) && defined(__ELF__)

    .syntax unified
    .arm
    .text

.macro VARIADIC name, target, nfixed
    .globl \name
    .type \name, %function
    .p2align 2
\name:
    push {r0-r3}                    // the register arguments, below the stack ones
    push {r4, lr}
    mov r4, sp
    add r12, sp, #(8 + 4 * \nfixed) // the first variadic word
    sub sp, sp, #8                  // a slot for a fifth argument
    bic sp, sp, #7
  .if \nfixed == 4
    str r12, [sp]
  .else
    mov r\nfixed, r12
  .endif
    bl \target
    mov sp, r4
    pop {r4, lr}
    add sp, sp, #16
    bx lr
    .size \name, . - \name
.endm

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
