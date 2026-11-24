// Variadic Foundation functions and methods for 32-bit PowerPC ELF,
// Darwin's calling convention.
//
// Darwin's caller reserves a word for each of r3-r10 at 24(r1), before its
// stack arguments, so storing the registers there makes the arguments one
// run of words, the variadic ones after the fixed: a Darwin va_list is a
// pointer into it. Each entry point stores them and goes to Swift with a
// pointer to the first variadic word in the register after the fixed
// arguments. Swift returns straight to the caller. These are Darwin code in
// a Linux library, so Foundation marks them for the loader, which then moves
// no arguments for them (variadicEntry).
//
// Swift is reached through a word in .data.rel.ro rather than the PLT, whose
// stubs in a shared object need r30, the caller's here.

#if defined(__powerpc__) && !defined(__powerpc64__) && defined(__ELF__)

    .text

.macro VARIADIC name, target, nfixed
    .pushsection .data.rel.ro, "aw"
    .p2align 2
.Lslot_\name:
    .long \target
    .popsection
    .globl \name
    .type \name, @function
    .p2align 2
\name:
    stw %r3, 24(%r1)
    stw %r4, 28(%r1)
    stw %r5, 32(%r1)
    stw %r6, 36(%r1)
    stw %r7, 40(%r1)
    stw %r8, 44(%r1)
    stw %r9, 48(%r1)
    stw %r10, 52(%r1)
    addi \nfixed + 3, %r1, 24 + 4 * \nfixed // the first variadic word
    mflr %r0
    bcl 20, 31, 1f
1:  mflr %r12
    mtlr %r0
    addis %r12, %r12, (.Lslot_\name - 1b)@ha
    lwz %r12, (.Lslot_\name - 1b)@l(%r12)
    mtctr %r12
    bctr
    .size \name, . - \name
.endm

// void NSLog(NSString *format, ...)
VARIADIC _NSLog, perry_foundation_log, 1
// CFStringRef CFStringCreateStringWithValidatedFormat(CFAllocatorRef, CFDictionaryRef, CFStringRef, CFStringRef, CFErrorRef *, ...)
VARIADIC _CFStringCreateStringWithValidatedFormat, perry_foundation_cf_create_with_validated_format, 5
// void CFLog(CFLogLevel level, CFStringRef format, ...)
VARIADIC _CFLog, perry_foundation_cf_log, 2

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
    .hidden perry_imp_initWithValidatedFormatLocale
VARIADIC perry_imp_initWithValidatedFormatLocale, perry_foundation_initWithValidatedFormatLocale, 6
    .hidden perry_imp_attributedInitWithFormatContext
VARIADIC perry_imp_attributedInitWithFormatContext, perry_foundation_attributedInitWithFormatContext, 6

#endif

    .section .note.GNU-stack, "", %progbits
