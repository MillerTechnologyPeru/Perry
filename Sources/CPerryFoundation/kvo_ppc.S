// Key-value observing's setter for 32-bit PowerPC ELF, Darwin's calling
// convention.
//
// A setter of any argument type, for the classes KVO makes: it asks
// Foundation for the setter it replaces (which also sends
// -willChangeValueForKey:), calls it with r3-r10 and f1-f13 as they came and
// the first 16 words of the caller's parameter area copied into its own, then
// lets Foundation send -didChangeValueForKey:. Darwin passes a structure in
// words, so 16 words hold the argument of any setter up to a 56-byte
// structure. The setter is Darwin code, so the loader gives it no argument
// moves (KeyValueObserving.swift marks it); r2, which Darwin code may change,
// is kept for Foundation's calls after it.
//
// Calls into Foundation go through words in .data.rel.ro rather than the
// PLT, whose stubs in a shared object need r30, the caller's here.

#if defined(__powerpc__) && !defined(__powerpc64__) && defined(__ELF__)

    .text

// The frame: Darwin's linkage area and a parameter area of 16 words for the
// setter, then r3-r10, f1-f13 and r2.
FRAME = 240
PARAMS = 24
GPRS = 88
FPRS = 120
R2_SAVE = 224

.macro CALL_C slot
    bcl 20, 31, 1f
1:  mflr %r12
    addis %r12, %r12, (\slot - 1b)@ha
    lwz %r12, (\slot - 1b)@l(%r12)
    mtctr %r12
    bctrl
.endm

// void perry_kvo_setter(id self, SEL _cmd, ...)
    .globl perry_kvo_setter
    .hidden perry_kvo_setter
    .type perry_kvo_setter, @function
    .p2align 4
perry_kvo_setter:
    mflr %r0
    stw %r0, 8(%r1)                 // in the caller's frame, as Darwin keeps it
    stwu %r1, -FRAME(%r1)
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
    stw %r2, R2_SAVE(%r1)
    // The caller's parameter area, at 24 in its frame, into this one's.
    li %r0, 16
    mtctr %r0
    addi %r11, %r1, FRAME + 24 - 4
    addi %r12, %r1, PARAMS - 4
2:  lwzu %r0, 4(%r11)
    stwu %r0, 4(%r12)
    bdnz 2b
    CALL_C .Lwill_slot              // self and _cmd are still in r3 and r4
    mtctr %r3                       // the setter it replaces
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
    bctrl
    lwz %r2, R2_SAVE(%r1)
    lwz %r3, GPRS + 0(%r1)
    lwz %r4, GPRS + 4(%r1)
    CALL_C .Ldid_slot
    addi %r1, %r1, FRAME
    lwz %r0, 8(%r1)
    mtlr %r0
    blr
    .size perry_kvo_setter, . - perry_kvo_setter

    .section .data.rel.ro, "aw"
    .p2align 2
.Lwill_slot:
    .long perry_foundation_kvo_will
.Ldid_slot:
    .long perry_foundation_kvo_did

#endif

    .section .note.GNU-stack, "", %progbits
