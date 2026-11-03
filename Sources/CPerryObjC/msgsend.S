// objc_msgSend and friends for arm64 ELF.
//
// Message sends pass the method's arguments in registers untouched, so
// these entry points cannot be written in C or Swift. The fast path probes
// the receiver class's cache:
//
//   class->cache -> perry_class_header { cache table, info }
//   cache table   = { mask, buckets[mask + 1] of { sel, imp } }
//
// Unrealized classes point `cache` at _objc_empty_cache, whose table is one
// empty bucket, so they miss. A miss saves every argument register and calls
// perry_objc_lookup_slow (Swift), then jumps to the IMP it returns.
//
// Buckets are filled IMP first, then selector, and never change after; a
// bucket whose selector matches but whose IMP reads as 0 is treated as a miss.

#if defined(__aarch64__) && defined(__ELF__)

    .text

.macro ENTRY name
    .globl \name
    .type \name, %function
    .p2align 4
\name:
.endm

.macro END name
    .size \name, . - \name
.endm

// Saves x0-x8 and q0-q7 below a frame record. 208 bytes keeps sp 16-aligned.
.macro SAVE_ARGUMENTS
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #208
    stp x0, x1, [sp, #0]
    stp x2, x3, [sp, #16]
    stp x4, x5, [sp, #32]
    stp x6, x7, [sp, #48]
    str x8, [sp, #64]
    stp q0, q1, [sp, #80]
    stp q2, q3, [sp, #112]
    stp q4, q5, [sp, #144]
    stp q6, q7, [sp, #176]
.endm

.macro RESTORE_ARGUMENTS
    ldp q6, q7, [sp, #176]
    ldp q4, q5, [sp, #144]
    ldp q2, q3, [sp, #112]
    ldp q0, q1, [sp, #80]
    ldr x8, [sp, #64]
    ldp x6, x7, [sp, #48]
    ldp x4, x5, [sp, #32]
    ldp x2, x3, [sp, #16]
    ldp x0, x1, [sp, #0]
    mov sp, x29
    ldp x29, x30, [sp], #16
.endm

// id objc_msgSend(id self, SEL _cmd, ...)
ENTRY _objc_msgSend
.Lmsgsend:
    cbz x0, .Lnil
    ldr x16, [x0]                   // isa
    cbz x16, .Lnil                  // a missing class's placeholder: as nil
.Llookup:                           // x0 = receiver, x1 = SEL, x16 = class
    ldr x9, [x16, #16]              // class->cache
    cbz x9, .Lmiss
    ldr x9, [x9]                    // cache table
    ldr x10, [x9]                   // mask
    add x11, x9, #8                 // buckets
    lsr x12, x1, #3
.Lprobe:
    and x12, x12, x10
    add x13, x11, x12, lsl #4
    ldp x14, x15, [x13]             // sel, imp
    cmp x14, x1
    b.ne .Lnext
    cbz x15, .Lmiss
    br x15
.Lnext:
    cbz x14, .Lmiss
    add x12, x12, #1
    b .Lprobe

.Lmiss:
    SAVE_ARGUMENTS
    mov x2, x16
    bl perry_objc_lookup_slow
    mov x17, x0
    RESTORE_ARGUMENTS
    br x17

// Messages to nil return zero in every result register.
.Lnil:
    mov x0, #0                      // a placeholder receiver is not returned
    mov x1, #0
    movi d0, #0
    movi d1, #0
    movi d2, #0
    movi d3, #0
    ret
END _objc_msgSend

// id objc_msgSendSuper(struct objc_super *super, SEL _cmd, ...)
// super = { receiver, class to start the search at }
ENTRY _objc_msgSendSuper
    ldp x0, x16, [x0]
    b .Llookup
END _objc_msgSendSuper

// id objc_msgSendSuper2(struct objc_super *super, SEL _cmd, ...)
// super = { receiver, current class }: the search starts at its superclass.
ENTRY _objc_msgSendSuper2
.Lmsgsend_super2:
    ldp x0, x16, [x0]
    ldr x16, [x16, #8]
    b .Llookup
END _objc_msgSendSuper2

// The IMP for selectors a class does not implement. Asks the runtime for a
// forwarding target and resends, or jumps to the forward handler with the
// original arguments. perry_objc_forward aborts when neither exists.
ENTRY __objc_msgForward
.Lmsgforward:
    SAVE_ARGUMENTS
    bl perry_objc_forward           // x0 = target, x1 = handler
    mov x16, x0
    mov x17, x1
    RESTORE_ARGUMENTS
    cbz x16, 1f
    mov x0, x16
    b .Lmsgsend
1:  br x17
END __objc_msgForward

// Outlined ARC calls that take the object in another register (Xcode 15+).
.macro RETAIN_RELEASE_VARIANT reg
ENTRY _objc_retain_\reg
    mov x0, \reg
    b _objc_retain
END _objc_retain_\reg
ENTRY _objc_release_\reg
    mov x0, \reg
    b _objc_release
END _objc_release_\reg
.endm

    RETAIN_RELEASE_VARIANT x1
    RETAIN_RELEASE_VARIANT x2
    RETAIN_RELEASE_VARIANT x3
    RETAIN_RELEASE_VARIANT x4
    RETAIN_RELEASE_VARIANT x5
    RETAIN_RELEASE_VARIANT x6
    RETAIN_RELEASE_VARIANT x7
    RETAIN_RELEASE_VARIANT x8
    RETAIN_RELEASE_VARIANT x9
    RETAIN_RELEASE_VARIANT x10
    RETAIN_RELEASE_VARIANT x11
    RETAIN_RELEASE_VARIANT x12
    RETAIN_RELEASE_VARIANT x13
    RETAIN_RELEASE_VARIANT x14
    RETAIN_RELEASE_VARIANT x15
    RETAIN_RELEASE_VARIANT x19
    RETAIN_RELEASE_VARIANT x20
    RETAIN_RELEASE_VARIANT x21
    RETAIN_RELEASE_VARIANT x22
    RETAIN_RELEASE_VARIANT x23
    RETAIN_RELEASE_VARIANT x24
    RETAIN_RELEASE_VARIANT x25
    RETAIN_RELEASE_VARIANT x26
    RETAIN_RELEASE_VARIANT x27
    RETAIN_RELEASE_VARIANT x28

    .text
    .p2align 2
    .globl perry_objc_msgSend_address
    .type perry_objc_msgSend_address, %function
perry_objc_msgSend_address:
    adrp x0, .Lmsgsend
    add x0, x0, :lo12:.Lmsgsend
    ret
    .size perry_objc_msgSend_address, . - perry_objc_msgSend_address

    .globl perry_objc_msgSendSuper2_address
    .type perry_objc_msgSendSuper2_address, %function
perry_objc_msgSendSuper2_address:
    adrp x0, .Lmsgsend_super2
    add x0, x0, :lo12:.Lmsgsend_super2
    ret
    .size perry_objc_msgSendSuper2_address, . - perry_objc_msgSendSuper2_address

    .globl perry_objc_msgForward_address
    .type perry_objc_msgForward_address, %function
perry_objc_msgForward_address:
    adrp x0, .Lmsgforward
    add x0, x0, :lo12:.Lmsgforward
    ret
    .size perry_objc_msgForward_address, . - perry_objc_msgForward_address

    .section .note.GNU-stack, "", %progbits

#endif
