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
    .elseif \nfixed == 5
    leaq 176(%rsp), %r9
    .else
    .error "unexpected number of fixed arguments"
    .endif
.endm

.macro VARIADIC name, target, nfixed, nfloat=0
    .globl \name
    .type \name, @function
    .p2align 4
\name:
    // Described to the unwinder, which an exception the Swift function
    // raises passes through on its way to the caller's @catch.
    .cfi_startproc
    pushq %rbp
    .cfi_def_cfa_offset 16
    .cfi_offset %rbp, -16
    movq %rsp, %rbp
    .cfi_def_cfa_register %rbp
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
    .cfi_def_cfa %rsp, 8
    ret
    .cfi_endproc
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

#elif defined(__i386__) && defined(__ELF__)

// On i386 the arguments are on the stack in words, and a Darwin va_list is a
// pointer to the first variadic one: each entry point calls Swift with the
// fixed arguments again and that pointer after them. A fixed double takes two
// words.
    .hidden perry_i386_foundation_pc_ebx
    .type perry_i386_foundation_pc_ebx, @function
perry_i386_foundation_pc_ebx:
    movl (%esp), %ebx
    ret

.macro VARIADIC name, target, nfixed, nfloat=0
    .globl \name
    .type \name, @function
    .p2align 4
\name:
    pushl %ebp
    movl %esp, %ebp
    pushl %ebx
    subl $(4 * (\nfixed + 2 * \nfloat + 1) + 28), %esp
    andl $-16, %esp
    .set index, 0
    .rept \nfixed + 2 * \nfloat
    movl (8 + 4 * index)(%ebp), %eax
    movl %eax, (4 * index)(%esp)
    .set index, index + 1
    .endr
    leal (8 + 4 * (\nfixed + 2 * \nfloat))(%ebp), %eax
    movl %eax, (4 * (\nfixed + 2 * \nfloat))(%esp)
    call perry_i386_foundation_pc_ebx
    addl $_GLOBAL_OFFSET_TABLE_, %ebx
    call \target@PLT
    movl -4(%ebp), %ebx
    leave
    ret
    .size \name, . - \name
.endm

#endif

#if (defined(__aarch64__) || defined(__x86_64__) || defined(__i386__)) && defined(__ELF__)

    .text

// void NSLog(NSString *format, ...)
VARIADIC _NSLog, perry_foundation_log, 1
// void CFLog(CFLogLevel level, CFStringRef format, ...)
VARIADIC _CFLog, perry_foundation_cf_log, 2

// CFStringRef CFStringCreateWithFormat(CFAllocatorRef, CFDictionaryRef, CFStringRef, ...)
VARIADIC _CFStringCreateWithFormat, perry_foundation_cf_create_with_format, 3
// void CFStringAppendFormat(CFMutableStringRef, CFDictionaryRef, CFStringRef, ...)
VARIADIC _CFStringAppendFormat, perry_foundation_cf_append_format, 3
// CFStringRef CFStringCreateStringWithValidatedFormat(CFAllocatorRef, CFDictionaryRef, CFStringRef validFormatSpecifiers,
// CFStringRef format, CFErrorRef *, ...)
VARIADIC _CFStringCreateStringWithValidatedFormat, perry_foundation_cf_create_with_validated_format, 5

// Boolean CFCalendarDecomposeAbsoluteTime(CFCalendarRef, CFAbsoluteTime, const char *, ...):
// the time is in d0, so two fixed arguments are in x registers.
VARIADIC _CFCalendarDecomposeAbsoluteTime, perry_foundation_cf_calendar_decompose, 2, 1
// Boolean CFCalendarComposeAbsoluteTime(CFCalendarRef, CFAbsoluteTime *, const char *, ...)
VARIADIC _CFCalendarComposeAbsoluteTime, perry_foundation_cf_calendar_compose, 3
// Boolean CFCalendarAddComponents(CFCalendarRef, CFAbsoluteTime *, CFOptionFlags, const char *, ...)
VARIADIC _CFCalendarAddComponents, perry_foundation_cf_calendar_add, 4
// Boolean CFCalendarGetComponentDifference(CFCalendarRef, CFAbsoluteTime, CFAbsoluteTime, CFOptionFlags,
// const char *, ...): the two times are in d0 and d1, so three fixed arguments are in x registers.
VARIADIC _CFCalendarGetComponentDifference, perry_foundation_cf_calendar_difference, 3, 2

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
    .hidden perry_imp_expressionWithFormat
VARIADIC perry_imp_expressionWithFormat, perry_foundation_expressionWithFormat, 3
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
    .hidden perry_imp_encodeValuesOfObjCTypes
VARIADIC perry_imp_encodeValuesOfObjCTypes, perry_foundation_encodeValuesOfObjCTypes, 3
    .hidden perry_imp_decodeValuesOfObjCTypes
VARIADIC perry_imp_decodeValuesOfObjCTypes, perry_foundation_decodeValuesOfObjCTypes, 3
    .hidden perry_imp_initWithFormatLocale
VARIADIC perry_imp_initWithFormatLocale, perry_foundation_initWithFormatLocale, 4
    .hidden perry_imp_localizedAttributedStringWithFormat
VARIADIC perry_imp_localizedAttributedStringWithFormat, perry_foundation_localizedAttributedStringWithFormat, 3
    .hidden perry_imp_localizedAttributedStringWithFormatOptions
VARIADIC perry_imp_localizedAttributedStringWithFormatOptions, perry_foundation_localizedAttributedStringWithFormatOptions, 4
    .hidden perry_imp_localizedAttributedStringWithFormatContext
VARIADIC perry_imp_localizedAttributedStringWithFormatContext, perry_foundation_localizedAttributedStringWithFormatContext, 4
    .hidden perry_imp_appendLocalizedFormat
VARIADIC perry_imp_appendLocalizedFormat, perry_foundation_appendLocalizedFormat, 3
    .hidden perry_imp_stringWithValidatedFormat
VARIADIC perry_imp_stringWithValidatedFormat, perry_foundation_stringWithValidatedFormat, 5
    .hidden perry_imp_initWithValidatedFormat
VARIADIC perry_imp_initWithValidatedFormat, perry_foundation_initWithValidatedFormat, 5
    .hidden perry_imp_localizedAttributedStringWithFormatOptionsContext
VARIADIC perry_imp_localizedAttributedStringWithFormatOptionsContext, perry_foundation_localizedAttributedStringWithFormatOptionsContext, 5
    .hidden perry_imp_attributedInitWithFormat
VARIADIC perry_imp_attributedInitWithFormat, perry_foundation_attributedInitWithFormat, 5
// Six fixed arguments leave no register for the va_list on x86_64.
#if !defined(__x86_64__)
    .hidden perry_imp_initWithValidatedFormatLocale
VARIADIC perry_imp_initWithValidatedFormatLocale, perry_foundation_initWithValidatedFormatLocale, 6
    .hidden perry_imp_attributedInitWithFormatContext
VARIADIC perry_imp_attributedInitWithFormatContext, perry_foundation_attributedInitWithFormatContext, 6
#endif

    .section .note.GNU-stack, "", %progbits

#endif

.section .note.GNU-stack, "", %progbits
