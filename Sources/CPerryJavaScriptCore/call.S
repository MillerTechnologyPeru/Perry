// perry_jsc_call: see CPerryJavaScriptCore.h.

#if defined(__x86_64__) && defined(__ELF__)

// x86_64: x[0] to x[5] in registers, x[6] and x[7] on the stack.
    .text
    .globl perry_jsc_call
    .type perry_jsc_call, @function
    .p2align 4
perry_jsc_call:
    pushq %rbp
    movq %rsp, %rbp
    pushq %rcx                      // where d0 goes
    subq $8, %rsp
    movq %rdi, %r11
    movq %rsi, %r10
    movsd 0(%rdx), %xmm0
    movsd 8(%rdx), %xmm1
    movsd 16(%rdx), %xmm2
    movsd 24(%rdx), %xmm3
    movsd 32(%rdx), %xmm4
    movsd 40(%rdx), %xmm5
    movsd 48(%rdx), %xmm6
    movsd 56(%rdx), %xmm7
    pushq 56(%r10)
    pushq 48(%r10)
    movq 0(%r10), %rdi
    movq 8(%r10), %rsi
    movq 16(%r10), %rdx
    movq 24(%r10), %rcx
    movq 32(%r10), %r8
    movq 40(%r10), %r9
    movl $8, %eax
    call *%r11
    addq $24, %rsp
    popq %rcx
    movsd %xmm0, (%rcx)
    popq %rbp
    ret
    .size perry_jsc_call, . - perry_jsc_call

    .section .note.GNU-stack, "", @progbits

#elif defined(__aarch64__) && defined(__ELF__)

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

.section .note.GNU-stack, "", %progbits
