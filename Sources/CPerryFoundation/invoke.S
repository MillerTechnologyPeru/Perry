// NSInvocation's call, for x86_64 ELF.

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

.section .note.GNU-stack, "", %progbits
