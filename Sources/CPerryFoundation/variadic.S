// Variadic Foundation functions and methods for arm64 ELF.
//
// Apple's arm64 ABI passes every variadic argument in an 8-byte stack slot
// starting at the caller's sp, which is a Darwin va_list. Each entry point
// passes that pointer after its fixed arguments and branches to Swift.

#if defined(__x86_64__) && defined(__ELF__)

// On x86_64 the arguments are in registers, then on the stack: each entry
// point saves the registers and passes a pointer to a va_list over them,
// as a Darwin va_list is there. `nfloat` counts fixed floating-point
// arguments.
.macro VA_LIST_ARGUMENT nfixed
    .if \nfixed == 1
    leaq 176(%rsp), %rsi
    .elseif \nfixed == 2
    leaq 176(%rsp), %rdx
    .elseif \nfixed == 3
    leaq 176(%rsp), %rcx
    .elseif \nfixed == 4
    leaq 176(%rsp), %r8
    .else
    .error "unexpected number of fixed arguments"
    .endif
.endm

.macro VARIADIC name, target, nfixed, nfloat=0
    .globl \name
    .type \name, @function
    .p2align 4
\name:
    pushq %rbp
    movq %rsp, %rbp
    subq $208, %rsp
    movq %rdi, 0(%rsp)
    movq %rsi, 8(%rsp)
    movq %rdx, 16(%rsp)
    movq %rcx, 24(%rsp)
    movq %r8, 32(%rsp)
    movq %r9, 40(%rsp)
    movups %xmm0, 48(%rsp)
    movups %xmm1, 64(%rsp)
    movups %xmm2, 80(%rsp)
    movups %xmm3, 96(%rsp)
    movups %xmm4, 112(%rsp)
    movups %xmm5, 128(%rsp)
    movups %xmm6, 144(%rsp)
    movups %xmm7, 160(%rsp)
    movl $(\nfixed * 8), 176(%rsp)      // gp_offset
    movl $(48 + \nfloat * 16), 180(%rsp) // fp_offset
    leaq 16(%rbp), %rax
    movq %rax, 184(%rsp)                // overflow_arg_area
    movq %rsp, 192(%rsp)                // reg_save_area
    VA_LIST_ARGUMENT \nfixed
    call \target@PLT
    leave
    ret
    .size \name, . - \name
.endm

#elif defined(__aarch64__) && defined(__ELF__)

.macro VARIADIC name, target, nfixed, nfloat=0
    .globl \name
    .type \name, %function
    .p2align 2
\name:
    mov x\nfixed, sp
    b \target
    .size \name, . - \name
.endm

#endif

#if (defined(__aarch64__) || defined(__x86_64__)) && defined(__ELF__)

    .text

// void NSLog(NSString *format, ...)
VARIADIC _NSLog, perry_foundation_log, 1

// CFStringRef CFStringCreateWithFormat(CFAllocatorRef, CFDictionaryRef, CFStringRef, ...)
VARIADIC _CFStringCreateWithFormat, perry_foundation_cf_create_with_format, 3
// void CFStringAppendFormat(CFMutableStringRef, CFDictionaryRef, CFStringRef, ...)
VARIADIC _CFStringAppendFormat, perry_foundation_cf_append_format, 3

// Boolean CFCalendarDecomposeAbsoluteTime(CFCalendarRef, CFAbsoluteTime, const char *, ...):
// the time is in d0, so two fixed arguments are in x registers.
VARIADIC _CFCalendarDecomposeAbsoluteTime, perry_foundation_cf_calendar_decompose, 2, 1
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

.section .note.GNU-stack, "", %progbits
