// Key-value observing's setter for armv7 ELF, Darwin's calling convention.
//
// A setter of any argument type, for the classes KVO makes: it asks
// Foundation for the setter it replaces (which also sends
// -willChangeValueForKey:), calls it with r0-r3 as they came and the first
// 16 words of the caller's stack arguments copied below its own frame, then
// lets Foundation send -didChangeValueForKey:. Darwin passes floating point
// and structures in core registers and then on the stack, so 16 words hold
// the argument of any setter up to a 72-byte structure. Darwin's stack is
// 4-byte aligned at calls and Linux's 8, so the calls realign it.
//
// KVC's calls to accessors with structures need nothing here on armv7: they
// pass and return words, which Swift calls through C function types.

#if defined(__arm__) && defined(__ELF__)

    .syntax unified
    .arm
    .text

// void perry_kvo_setter(id self, SEL _cmd, ...)
    .globl perry_kvo_setter
    .hidden perry_kvo_setter
    .type perry_kvo_setter, %function
    .p2align 2
perry_kvo_setter:
    push {r0-r3}
    push {r4, r5, r7, lr}
    add r7, sp, #8
    mov r4, sp                      // r4 + 16 = the register arguments
    add r5, sp, #32                 // the caller's stack arguments
    sub sp, sp, #64
    bic sp, sp, #7
    bl perry_foundation_kvo_will    // self and _cmd are still in r0 and r1
    mov r12, r0
    mov r0, #0
1:  ldr r1, [r5, r0]
    str r1, [sp, r0]
    add r0, r0, #4
    cmp r0, #64
    blo 1b
    add r0, r4, #16
    ldm r0, {r0-r3}
    blx r12
    ldr r0, [r4, #16]
    ldr r1, [r4, #20]
    bl perry_foundation_kvo_did
    mov sp, r4
    pop {r4, r5, r7, lr}
    add sp, sp, #16
    bx lr
    .size perry_kvo_setter, . - perry_kvo_setter

    .section .note.GNU-stack, "", %progbits

#endif
