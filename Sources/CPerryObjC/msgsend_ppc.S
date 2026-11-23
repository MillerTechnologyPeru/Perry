// objc_msgSend and friends for 32-bit PowerPC ELF, Darwin's calling
// convention.
//
// The same design as msgsend.S: probe the receiver class's cache, and on a
// miss save the argument registers and call perry_objc_lookup_slow (Swift).
// The layouts are 32-bit:
//
//   class->cache  (offset 8) -> perry_class_header { cache table, info }
//   cache table   = { mask, buckets[mask + 1] of { sel, imp } }   (8-byte buckets)
//
// Darwin passes self in r3 and the selector in r4, the other arguments in
// r5-r10, f1-f13 and the caller's parameter area, and returns a structure
// through a pointer in r3, which moves self to r4 and the selector to r5: the
// _stret entry points. Floating point comes back in f1, so there is no
// _fpret.
//
// r0, r11, r12 and ctr are free at a call in both ABIs; the probe uses only
// them, keeping the class in ctr until the IMP replaces it. r2 is left alone:
// Darwin code reaches these entry points through the loader's stubs, which
// have set it to the thread pointer that perry_objc_lookup_slow needs.
//
// Calls into C go through a word in .data.rel.ro rather than the PLT, whose
// stubs in a shared object need r30, which belongs to the caller here.

#if defined(__powerpc__) && !defined(__powerpc64__) && defined(__ELF__)

    .text

.macro ENTRY name
    .globl \name
    .type \name, @function
    .p2align 4
\name:
.endm

.macro END name
    .size \name, . - \name
.endm

// The frame for calls into C: the back chain and the callee's lr word, two
// words of result, r3-r10, f1-f13, then lr.
FRAME = 176
RESULT = 8
GPRS = 16
FPRS = 48
LR_SAVE = 152

.macro SAVE_ARGUMENTS
    mflr %r0
    stwu %r1, -FRAME(%r1)
    stw %r0, LR_SAVE(%r1)
    stw %r3, GPRS + 0(%r1)
    stw %r4, GPRS + 4(%r1)
    stw %r5, GPRS + 8(%r1)
    stw %r6, GPRS + 12(%r1)
    stw %r7, GPRS + 16(%r1)
    stw %r8, GPRS + 20(%r1)
    stw %r9, GPRS + 24(%r1)
    stw %r10, GPRS + 28(%r1)
    stfd %f1, FPRS + 0(%r1)
    stfd %f2, FPRS + 8(%r1)
    stfd %f3, FPRS + 16(%r1)
    stfd %f4, FPRS + 24(%r1)
    stfd %f5, FPRS + 32(%r1)
    stfd %f6, FPRS + 40(%r1)
    stfd %f7, FPRS + 48(%r1)
    stfd %f8, FPRS + 56(%r1)
    stfd %f9, FPRS + 64(%r1)
    stfd %f10, FPRS + 72(%r1)
    stfd %f11, FPRS + 80(%r1)
    stfd %f12, FPRS + 88(%r1)
    stfd %f13, FPRS + 96(%r1)
.endm

// Restores what SAVE_ARGUMENTS saved and pops the frame; leaves r11, r12 and
// ctr alone.
.macro RESTORE_ARGUMENTS
    lfd %f1, FPRS + 0(%r1)
    lfd %f2, FPRS + 8(%r1)
    lfd %f3, FPRS + 16(%r1)
    lfd %f4, FPRS + 24(%r1)
    lfd %f5, FPRS + 32(%r1)
    lfd %f6, FPRS + 40(%r1)
    lfd %f7, FPRS + 48(%r1)
    lfd %f8, FPRS + 56(%r1)
    lfd %f9, FPRS + 64(%r1)
    lfd %f10, FPRS + 72(%r1)
    lfd %f11, FPRS + 80(%r1)
    lfd %f12, FPRS + 88(%r1)
    lfd %f13, FPRS + 96(%r1)
    lwz %r3, GPRS + 0(%r1)
    lwz %r4, GPRS + 4(%r1)
    lwz %r5, GPRS + 8(%r1)
    lwz %r6, GPRS + 12(%r1)
    lwz %r7, GPRS + 16(%r1)
    lwz %r8, GPRS + 20(%r1)
    lwz %r9, GPRS + 24(%r1)
    lwz %r10, GPRS + 28(%r1)
    lwz %r0, LR_SAVE(%r1)
    mtlr %r0
    addi %r1, %r1, FRAME
.endm

// Calls the C function whose address is in the word at \slot.
.macro CALL_C slot
    bcl 20, 31, 1f
1:  mflr %r12
    addis %r12, %r12, (\slot - 1b)@ha
    lwz %r12, (\slot - 1b)@l(%r12)
    mtctr %r12
    bctrl
.endm

// LOOKUP sel, label, slow, stret: \sel is the selector's register number.
//
// r11 = the class to search. Probes its cache for the selector in \sel and
// jumps to the IMP with the arguments as the caller left them.
.macro LOOKUP selreg, label, slow, stret=0
    mtctr %r11
    lwz %r12, 8(%r11)               // class->cache
    cmpwi %r12, 0
    beq .Lmiss_\label
    lwz %r12, 0(%r12)               // the cache table
    addi %r12, %r12, 4              // its buckets, after the mask
    srwi %r11, \selreg, 2
.Lprobe_\label:
    lwz %r0, -4(%r12)               // mask
    and %r11, %r11, %r0
    slwi %r0, %r11, 3
    lwzx %r0, %r12, %r0             // the bucket's selector
    cmpw %r0, \selreg
    beq .Lhit_\label
    cmpwi %r0, 0
    beq .Lmiss_\label
    addi %r11, %r11, 1
    b .Lprobe_\label
.Lhit_\label:
    slwi %r0, %r11, 3
    addi %r12, %r12, 4              // the buckets' IMPs
    lwzx %r0, %r12, %r0             // its IMP
    cmpwi %r0, 0
    beq .Lmiss_\label
    mtctr %r0
    bctr
.Lmiss_\label:
    mfctr %r11                      // the class
    SAVE_ARGUMENTS
.if \stret
    mr %r3, %r4
    mr %r4, %r5
.endif
    mr %r5, %r11
    CALL_C \slow
    mtctr %r3
    RESTORE_ARGUMENTS
    bctr
.endm

// id objc_msgSend(id self, SEL _cmd, ...)
ENTRY _objc_msgSend
.Lmsgsend:
    cmpwi %r3, 0
    beq .Lnil
    lwz %r11, 0(%r3)                // isa
    cmpwi %r11, 0
    beq .Lnil                       // a missing class's placeholder: as nil
.Llookup:
    LOOKUP 4, send, .Lslow_slot
// Messages to nil return zero in r3 and r4, and in f1 and f2.
.Lnil:
    mflr %r0
    bcl 20, 31, 1f
1:  mflr %r12
    mtlr %r0
    addis %r12, %r12, (.Lzero - 1b)@ha
    addi %r12, %r12, (.Lzero - 1b)@l
    lfd %f1, 0(%r12)
    fmr %f2, %f1
    li %r3, 0
    li %r4, 0
    blr
END _objc_msgSend

// void objc_msgSend_stret(void *result, id self, SEL _cmd, ...)
ENTRY _objc_msgSend_stret
.Lmsgsend_stret:
    cmpwi %r4, 0
    beq .Lnil_stret
    lwz %r11, 0(%r4)
    cmpwi %r11, 0
    beq .Lnil_stret
.Llookup_stret:
    LOOKUP 5, stret, .Lslow_stret_slot, 1
.Lnil_stret:                        // the result is left alone, as Darwin's is
    blr
END _objc_msgSend_stret

// id objc_msgSendSuper(struct objc_super *super, SEL _cmd, ...)
// super = { receiver, class to start the search at }: the receiver takes its
// place among the arguments.
ENTRY _objc_msgSendSuper
    lwz %r11, 4(%r3)
    lwz %r3, 0(%r3)
    b .Llookup
END _objc_msgSendSuper

ENTRY _objc_msgSendSuper_stret
    lwz %r11, 4(%r4)
    lwz %r4, 0(%r4)
    b .Llookup_stret
END _objc_msgSendSuper_stret

// id objc_msgSendSuper2(struct objc_super *super, SEL _cmd, ...)
// super = { receiver, current class }: the search starts at its superclass.
ENTRY _objc_msgSendSuper2
.Lmsgsend_super2:
    lwz %r11, 4(%r3)
    lwz %r11, 4(%r11)
    lwz %r3, 0(%r3)
    b .Llookup
END _objc_msgSendSuper2

ENTRY _objc_msgSendSuper2_stret
.Lmsgsend_super2_stret:
    lwz %r11, 4(%r4)
    lwz %r11, 4(%r11)
    lwz %r4, 0(%r4)
    b .Llookup_stret
END _objc_msgSendSuper2_stret

// The IMP for selectors a class does not implement. Asks the runtime for a
// forwarding target and resends, or jumps to the forward handler with the
// original arguments. perry_objc_forward returns two words, which Linux's
// ppc returns through a pointer in r3, so the arguments move up a register;
// the caller's address goes last.
ENTRY __objc_msgForward
.Lmsgforward:
    SAVE_ARGUMENTS
    lwz %r6, LR_SAVE(%r1)
    mr %r5, %r4                     // the selector
    mr %r4, %r3                     // the receiver
    addi %r3, %r1, RESULT
    CALL_C .Lforward_slot
    lwz %r11, RESULT(%r1)           // target
    lwz %r12, RESULT + 4(%r1)       // handler
    RESTORE_ARGUMENTS
    cmpwi %r11, 0
    beq 1f
    mr %r3, %r11                    // resend to the new target
    b .Lmsgsend
1:  mtctr %r12
    bctr
END __objc_msgForward

// The same for a message that returns a structure through a pointer in r3:
// the receiver is in r4 and the selector in r5, where perry_objc_forward_stret
// takes them after its own result pointer.
ENTRY __objc_msgForward_stret
.Lmsgforward_stret:
    SAVE_ARGUMENTS
    addi %r3, %r1, RESULT
    CALL_C .Lforward_stret_slot
    lwz %r11, RESULT(%r1)
    lwz %r12, RESULT + 4(%r1)
    RESTORE_ARGUMENTS
    cmpwi %r11, 0
    beq 1f
    mr %r4, %r11
    b .Lmsgsend_stret
1:  mtctr %r12
    bctr
END __objc_msgForward_stret

// void perry_objc_ppc_longjmp(int *buffer): back to Darwin's setjmp
// (libSystem's thunks_ppc.S), returning 1.
ENTRY perry_objc_ppc_longjmp
    lfd %f0, 240(%r3)
    mtfsf 0xff, %f0
    lfd %f14, 96(%r3)
    lfd %f15, 104(%r3)
    lfd %f16, 112(%r3)
    lfd %f17, 120(%r3)
    lfd %f18, 128(%r3)
    lfd %f19, 136(%r3)
    lfd %f20, 144(%r3)
    lfd %f21, 152(%r3)
    lfd %f22, 160(%r3)
    lfd %f23, 168(%r3)
    lfd %f24, 176(%r3)
    lfd %f25, 184(%r3)
    lfd %f26, 192(%r3)
    lfd %f27, 200(%r3)
    lfd %f28, 208(%r3)
    lfd %f29, 216(%r3)
    lfd %f30, 224(%r3)
    lfd %f31, 232(%r3)
    lmw %r13, 12(%r3)
    lwz %r0, 8(%r3)
    mtcr %r0
    lwz %r0, 4(%r3)
    mtlr %r0
    lwz %r1, 0(%r3)
    li %r3, 1
    blr
END perry_objc_ppc_longjmp

.macro ADDRESS name, label
    .globl \name
    .type \name, @function
    .p2align 2
\name:
    mflr %r0
    bcl 20, 31, 1f
1:  mflr %r3
    mtlr %r0
    addis %r3, %r3, (\label - 1b)@ha
    addi %r3, %r3, (\label - 1b)@l
    blr
    .size \name, . - \name
.endm

ADDRESS perry_objc_msgSend_address, .Lmsgsend
ADDRESS perry_objc_msgSendSuper2_address, .Lmsgsend_super2
ADDRESS perry_objc_msgForward_address, .Lmsgforward
ADDRESS perry_objc_msgSend_stret_address, .Lmsgsend_stret
ADDRESS perry_objc_msgSendSuper2_stret_address, .Lmsgsend_super2_stret
ADDRESS perry_objc_msgForward_stret_address, .Lmsgforward_stret

    .section .rodata
    .p2align 3
.Lzero:
    .long 0, 0

    .section .data.rel.ro, "aw"
    .p2align 2
.Lslow_slot:
    .long perry_objc_lookup_slow
.Lslow_stret_slot:
    .long perry_objc_lookup_slow_stret
.Lforward_slot:
    .long perry_objc_forward
.Lforward_stret_slot:
    .long perry_objc_forward_stret

#endif

    .section .note.GNU-stack, "", %progbits
