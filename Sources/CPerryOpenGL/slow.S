// perry_gl_slow: entered from an entry point (entry.c) with the host's
// function in x16 and the call's arguments in place. Keeps the argument
// registers, has UIKit give the thread its context, and goes on to the
// function.

    .text
    .globl perry_gl_slow
    .hidden perry_gl_slow
    .type perry_gl_slow, %function
perry_gl_slow:
    stp x29, x30, [sp, #-224]!
    mov x29, sp
    stp x0, x1, [sp, #16]
    stp x2, x3, [sp, #32]
    stp x4, x5, [sp, #48]
    stp x6, x7, [sp, #64]
    stp x8, x16, [sp, #80]
    stp q0, q1, [sp, #96]
    stp q2, q3, [sp, #128]
    stp q4, q5, [sp, #160]
    stp q6, q7, [sp, #192]
    bl perry_gl_call_before
    ldp q6, q7, [sp, #192]
    ldp q4, q5, [sp, #160]
    ldp q2, q3, [sp, #128]
    ldp q0, q1, [sp, #96]
    ldp x8, x16, [sp, #80]
    ldp x6, x7, [sp, #64]
    ldp x4, x5, [sp, #48]
    ldp x2, x3, [sp, #32]
    ldp x0, x1, [sp, #16]
    ldp x29, x30, [sp], #224
    br x16
    .size perry_gl_slow, .-perry_gl_slow

    .section .note.GNU-stack,"",%progbits
