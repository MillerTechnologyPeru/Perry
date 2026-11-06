// perry_gl_slow: entered from an entry point (entry.c) with the host's
// function in x16 and the call's arguments in place. Keeps the argument
// registers, has UIKit give the thread its context, and goes on to the
// function.

#if defined(__arm__)
// armv7: the function is in r12, the arguments in r0 to r3 and on the
// stack, which 32-bit Darwin code keeps 4-byte aligned.
    .syntax unified
    .arm
    .fpu vfpv3
    .text

// Calls the function on a stack aligned to 8 bytes, as the host's code
// expects, with the caller's first eight stack words copied there: enough
// for twelve arguments, more than any OpenGL ES function takes.
    .globl perry_gl_aligned
    .hidden perry_gl_aligned
    .type perry_gl_aligned, %function
perry_gl_aligned:
    push {r4, r5, r6, lr}
    mov r4, sp
    sub sp, sp, #32
    bic sp, sp, #7
    add r5, r4, #16                 // the caller's stack arguments
    mov r6, #0
1:  ldr lr, [r5, r6]
    str lr, [sp, r6]
    add r6, r6, #4
    cmp r6, #32
    blt 1b
    blx r12
    mov sp, r4
    pop {r4, r5, r6, pc}
    .size perry_gl_aligned, . - perry_gl_aligned

// Has UIKit give the thread its context first, keeping the arguments.
    .globl perry_gl_slow
    .hidden perry_gl_slow
    .type perry_gl_slow, %function
perry_gl_slow:
    push {r0-r3, r4, r12, lr}
    mov r4, sp
    bic sp, sp, #7
    vpush {d0-d7}
    bl perry_gl_call_before
    vpop {d0-d7}
    mov sp, r4
    pop {r0-r3, r4, r12, lr}
    b perry_gl_aligned
    .size perry_gl_slow, . - perry_gl_slow
#else
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
#endif

    .section .note.GNU-stack,"",%progbits
