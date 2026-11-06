// objc_msgSend and friends for armv7 ELF, Darwin's calling convention.
//
// The same design as msgsend.S, in ARM state: probe the receiver class's cache,
// and on a miss save the argument registers and call perry_objc_lookup_slow
// (Swift). The layouts are 32-bit:
//
//   class->cache  (offset 8) -> perry_class_header { cache table, info }
//   cache table   = { mask, buckets[mask + 1] of { sel, imp } }   (8-byte buckets)
//
// Darwin passes the first four words in r0-r3, and returns a structure too big
// for r0 through a pointer in r0, which moves self to r1 and the selector to
// r2: the _stret entry points. Floating point travels in core registers, so no
// _fpret entry point exists. Only r12 is free of Darwin's calling convention,
// so the probe borrows r4-r7 and restores them before jumping to the IMP. The
// stack stays as the caller left it at the jump.

#if defined(__arm__) && defined(__ELF__)

    .syntax unified
    .arm
    .text

.macro ENTRY name
    .globl \name
    .type \name, %function
    .p2align 2
\name:
.endm

.macro END name
    .size \name, . - \name
.endm

// LOOKUP self, sel, stret
//
// r12 = the class to search. Probes its cache for the selector in \sel and
// jumps to the IMP, with r0-r3 and lr as the caller had them.
.macro LOOKUP selfreg, selreg, label
    push {r4-r7}
    mov r4, r12                     // the class, for the slow path
    ldr r5, [r4, #8]                // class->cache
    cmp r5, #0
    beq .Lmiss_\label
    ldr r5, [r5]                    // the cache table
    ldr r6, [r5], #4                // mask; r5 = buckets
    mov r12, \selreg, lsr #2
.Lprobe_\label:
    and r12, r12, r6
    ldr r7, [r5, r12, lsl #3]       // bucket's selector
    cmp r7, \selreg
    bne .Lnext_\label
    add r7, r5, r12, lsl #3
    ldr r7, [r7, #4]                // its IMP
    cmp r7, #0
    beq .Lmiss_\label
    mov r12, r7
    pop {r4-r7}
    bx r12
.Lnext_\label:
    cmp r7, #0
    beq .Lmiss_\label
    add r12, r12, #1
    b .Lprobe_\label
.Lmiss_\label:                      // r4 = class
    push {r0-r3, lr}
    mov r5, sp
    bic sp, sp, #7                  // Darwin keeps its stack four-byte aligned
    mov r0, \selfreg
    mov r1, \selreg
    mov r2, r4
    bl perry_objc_lookup_slow
    mov r12, r0
    mov sp, r5
    pop {r0-r3, lr}
    pop {r4-r7}
    bx r12
.endm

// id objc_msgSend(id self, SEL _cmd, ...)
ENTRY _objc_msgSend
.Lmsgsend:
    cmp r0, #0
    beq .Lnil
    ldr r12, [r0]                   // isa
    cmp r12, #0
    beq .Lnil                       // a missing class's placeholder: as nil
    LOOKUP r0, r1, send
.Lnil:                              // messages to nil return zero in r0 and r1
    mov r0, #0
    mov r1, #0
    bx lr
END _objc_msgSend

// void objc_msgSend_stret(void *result, id self, SEL _cmd, ...)
ENTRY _objc_msgSend_stret
.Lmsgsend_stret:
    cmp r1, #0
    beq .Lnil_stret
    ldr r12, [r1]
    cmp r12, #0
    beq .Lnil_stret
    LOOKUP r1, r2, stret
.Lnil_stret:
    bx lr
END _objc_msgSend_stret

// id objc_msgSendSuper(struct objc_super *super, SEL _cmd, ...)
// super = { receiver, class to start the search at }
ENTRY _objc_msgSendSuper
    ldr r12, [r0, #4]
    ldr r0, [r0]
    LOOKUP r0, r1, super
END _objc_msgSendSuper

// id objc_msgSendSuper2(struct objc_super *super, SEL _cmd, ...)
// super = { receiver, current class }: the search starts at its superclass.
ENTRY _objc_msgSendSuper2
.Lmsgsend_super2:
    ldr r12, [r0, #4]
    ldr r12, [r12, #4]
    ldr r0, [r0]
    LOOKUP r0, r1, super2
END _objc_msgSendSuper2

ENTRY _objc_msgSendSuper_stret
    ldr r12, [r1, #4]
    ldr r1, [r1]
    LOOKUP r1, r2, super_stret
END _objc_msgSendSuper_stret

ENTRY _objc_msgSendSuper2_stret
.Lmsgsend_super2_stret:
    ldr r12, [r1, #4]
    ldr r12, [r12, #4]
    ldr r1, [r1]
    LOOKUP r1, r2, super2_stret
END _objc_msgSendSuper2_stret

// The IMP for selectors a class does not implement. Asks the runtime for a
// forwarding target and resends, or jumps to the forward handler with the
// original arguments. perry_objc_forward returns two words, which AAPCS
// returns through a pointer in r0, so the arguments move up one register.
ENTRY __objc_msgForward
.Lmsgforward:
    push {r0-r3, r4, lr}            // 24 bytes
    mov r4, sp
    sub sp, sp, #8                  // the result
    bic sp, sp, #7
    mov r2, r1                      // the selector
    mov r1, r0                      // the receiver
    mov r0, sp
    bl perry_objc_forward
    ldr r12, [sp]                   // target
    ldr lr, [sp, #4]                // handler
    mov sp, r4
    cmp r12, #0
    beq 1f
    pop {r0-r3, r4, lr}
    mov r0, r12                     // resend to the new target
    b .Lmsgsend
1:  mov r12, lr                     // the handler, in the one free scratch register
    pop {r0-r3, r4, lr}
    bx r12
END __objc_msgForward

    .globl perry_objc_msgSend_address
    .type perry_objc_msgSend_address, %function
    .p2align 2
perry_objc_msgSend_address:
    adr r0, .Lmsgsend
    bx lr
    .size perry_objc_msgSend_address, . - perry_objc_msgSend_address

    .globl perry_objc_msgSendSuper2_address
    .type perry_objc_msgSendSuper2_address, %function
    .p2align 2
perry_objc_msgSendSuper2_address:
    adr r0, .Lmsgsend_super2
    bx lr
    .size perry_objc_msgSendSuper2_address, . - perry_objc_msgSendSuper2_address

    .globl perry_objc_msgSend_stret_address
    .type perry_objc_msgSend_stret_address, %function
    .p2align 2
perry_objc_msgSend_stret_address:
    adr r0, .Lmsgsend_stret
    bx lr
    .size perry_objc_msgSend_stret_address, . - perry_objc_msgSend_stret_address

    .globl perry_objc_msgSendSuper2_stret_address
    .type perry_objc_msgSendSuper2_stret_address, %function
    .p2align 2
perry_objc_msgSendSuper2_stret_address:
    adr r0, .Lmsgsend_super2_stret
    bx lr
    .size perry_objc_msgSendSuper2_stret_address, . - perry_objc_msgSendSuper2_stret_address

    .globl perry_objc_msgForward_address
    .type perry_objc_msgForward_address, %function
    .p2align 2
perry_objc_msgForward_address:
    adr r0, .Lmsgforward
    bx lr
    .size perry_objc_msgForward_address, . - perry_objc_msgForward_address

#endif

    .section .note.GNU-stack,"",%progbits
