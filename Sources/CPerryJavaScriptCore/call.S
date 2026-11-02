// perry_jsc_call: see CPerryJavaScriptCore.h.

#if defined(__aarch64__) && defined(__ELF__)

    .text
    .globl perry_jsc_call
    .type perry_jsc_call, %function
    .p2align 2
perry_jsc_call:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x3, [sp, #16]
    mov x16, x0
    mov x9, x1
    mov x10, x2
    ldp d0, d1, [x10]
    ldp d2, d3, [x10, #16]
    ldp d4, d5, [x10, #32]
    ldp d6, d7, [x10, #48]
    ldp x0, x1, [x9]
    ldp x2, x3, [x9, #16]
    ldp x4, x5, [x9, #32]
    ldp x6, x7, [x9, #48]
    blr x16
    ldr x3, [sp, #16]
    str d0, [x3]
    ldp x29, x30, [sp], #32
    ret
    .size perry_jsc_call, . - perry_jsc_call

    .section .note.GNU-stack, "", %progbits

#endif
