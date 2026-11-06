// perry_align_call: where 32-bit Darwin code's calls to imported functions
// go first (see perry_aligned_entry), with the function in r12.
//
// Darwin's armv7 code keeps its stack 4-byte aligned; Linux's keeps 8, and
// its libraries rely on it (Mesa and glibc store NEON registers to the
// stack with aligned instructions, which fault otherwise). So a call that
// arrives with the stack misaligned is made on an aligned copy of the
// caller's stack arguments: 32 words, more than functions take, and what
// their variadic arguments run to. A call that arrives aligned goes
// straight on.

#if defined(__arm__)

    .syntax unified
    .arm
    .text
    .globl perry_align_call
    .hidden perry_align_call
    .type perry_align_call, %function
    .p2align 2
perry_align_call:
    tst sp, #7
    bxeq r12
    push {r4, r5, r6, lr}
    mov r4, sp
    sub sp, sp, #128
    bic sp, sp, #7
    add r5, r4, #16                 // the caller's stack arguments
    mov r6, #0
1:  ldr lr, [r5, r6]
    str lr, [sp, r6]
    add r6, r6, #4
    cmp r6, #128
    blt 1b
    blx r12
    mov sp, r4
    pop {r4, r5, r6, pc}
    .size perry_align_call, . - perry_align_call

#endif

    .section .note.GNU-stack,"",%progbits
