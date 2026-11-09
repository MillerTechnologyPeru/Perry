// NSInvocation's call, for x86_64 and arm64 ELF.

#if defined(__x86_64__) && defined(__ELF__)

    .text

// void perry_foundation_invoke(const void *imp, const uint64_t gp[6],
//                              const uint64_t fp[8], const uint64_t *stack,
//                              size_t words, uint64_t out[4])
// Calls imp with those integer registers, vector registers and stack words,
// and keeps rax, rdx, xmm0 and xmm1 in `out`.
    .globl perry_foundation_invoke
    .hidden perry_foundation_invoke
    .type perry_foundation_invoke, @function
    .p2align 4
perry_foundation_invoke:
    pushq %rbp
    movq %rsp, %rbp
    pushq %r12
    subq $8, %rsp
    movq %r9, %r12
    movq %rdi, %r11
    movq %rsi, %r10
    leaq 1(%r8), %rax               // an even number of words, for alignment
    andq $-2, %rax
    shlq $3, %rax
    subq %rax, %rsp
    movq %rcx, %rsi
    movq %rsp, %rdi
    movq %r8, %rcx
    rep movsq
    movsd 0(%rdx), %xmm0
    movsd 8(%rdx), %xmm1
    movsd 16(%rdx), %xmm2
    movsd 24(%rdx), %xmm3
    movsd 32(%rdx), %xmm4
    movsd 40(%rdx), %xmm5
    movsd 48(%rdx), %xmm6
    movsd 56(%rdx), %xmm7
    movq 0(%r10), %rdi
    movq 8(%r10), %rsi
    movq 16(%r10), %rdx
    movq 24(%r10), %rcx
    movq 32(%r10), %r8
    movq 40(%r10), %r9
    movl $8, %eax
    call *%r11
    movq %rax, 0(%r12)
    movq %rdx, 8(%r12)
    movsd %xmm0, 16(%r12)
    movsd %xmm1, 24(%r12)
    movq -8(%rbp), %r12
    leave
    ret
    .size perry_foundation_invoke, . - perry_foundation_invoke

#endif

#if defined(__aarch64__) && defined(__ELF__)

    .text

// void perry_foundation_invoke(const void *imp, const uint64_t gp[9],
//                              const uint64_t fp[8], const uint64_t *stack,
//                              size_t words, uint64_t out[6])
// Calls imp with x0-x7 and x8 (gp), d0-d7 (fp) and those stack words, and
// keeps x0, x1 and d0-d3 in `out`.
    .globl perry_foundation_invoke
    .hidden perry_foundation_invoke
    .type perry_foundation_invoke, @function
    .p2align 2
perry_foundation_invoke:
    .cfi_startproc
    stp x29, x30, [sp, #-32]!
    .cfi_def_cfa_offset 32
    .cfi_offset 29, -32
    .cfi_offset 30, -24
    str x19, [sp, #16]
    .cfi_offset 19, -16
    mov x29, sp
    .cfi_def_cfa_register 29
    mov x19, x5
    mov x16, x0
    mov x17, x1
    add x9, x4, #1                  // an even number of words, for alignment
    and x9, x9, #-2
    lsl x9, x9, #3
    sub sp, sp, x9
    mov x10, #0
1:  cmp x10, x4
    b.hs 2f
    ldr x11, [x3, x10, lsl #3]
    str x11, [sp, x10, lsl #3]
    add x10, x10, #1
    b 1b
2:  ldp d0, d1, [x2]
    ldp d2, d3, [x2, #16]
    ldp d4, d5, [x2, #32]
    ldp d6, d7, [x2, #48]
    ldp x0, x1, [x17]
    ldp x2, x3, [x17, #16]
    ldp x4, x5, [x17, #32]
    ldp x6, x7, [x17, #48]
    ldr x8, [x17, #64]
    blr x16
    stp x0, x1, [x19]
    stp d0, d1, [x19, #16]
    stp d2, d3, [x19, #32]
    mov sp, x29
    ldr x19, [sp, #16]
    ldp x29, x30, [sp], #32
    .cfi_def_cfa_offset 0
    .cfi_restore 19
    .cfi_restore 29
    .cfi_restore 30
    ret
    .cfi_endproc
    .size perry_foundation_invoke, . - perry_foundation_invoke

#endif

.section .note.GNU-stack, "", %progbits
