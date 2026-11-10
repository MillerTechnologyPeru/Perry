// perry_foundation_invoke_armv7: calls an IMP with the words of an NSInvocation's
// arguments as Darwin's armv7 passes them: the first four in r0-r3 and the
// rest on the stack, in order. Darwin's ABI does not pad 8-byte arguments to
// even registers or stack addresses, so the words are the arguments' bytes
// one after another. The result's r0 and r1 are stored in `out`.
//
// void perry_foundation_invoke_armv7(const void *imp, const uint32_t *words,
//                                    size_t count, uint32_t out[2])
// `words` holds at least four words.

#if defined(__arm__)

    .syntax unified
    .arm
    .text
    .globl perry_foundation_invoke_armv7
    .hidden perry_foundation_invoke_armv7
    .type perry_foundation_invoke_armv7, %function
    .p2align 2
perry_foundation_invoke_armv7:
    push {r4, r5, r6, r7, lr}
    mov r4, r3                      // out
    mov r5, r0                      // the IMP
    mov r6, r1                      // the words
    mov r7, sp
    subs r12, r2, #4                // the words that go on the stack
    movle r12, #0
    sub sp, sp, r12, lsl #2
    bic sp, sp, #7
    mov r3, #0
1:  cmp r3, r12
    bge 2f
    add lr, r6, #16
    ldr lr, [lr, r3, lsl #2]
    str lr, [sp, r3, lsl #2]
    add r3, r3, #1
    b 1b
2:  ldm r6, {r0-r3}
    blx r5
    str r0, [r4]
    str r1, [r4, #4]
    mov sp, r7
    pop {r4, r5, r6, r7, pc}
    .size perry_foundation_invoke_armv7, . - perry_foundation_invoke_armv7

#endif

    .section .note.GNU-stack,"",%progbits
