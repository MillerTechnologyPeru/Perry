// tlv_get_addr for Mach-O code: called with a thread-local variable's
// descriptor in x0, it returns the variable's address in x0 and, as dyld's
// does, preserves every other register but x16 and x17, since compilers
// call it without saving any.
#if defined(__aarch64__)
    .text
    .globl perry_tlv_get_addr
    .type perry_tlv_get_addr, %function
    .p2align 2
perry_tlv_get_addr:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    sub sp, sp, #256
    stp x1, x2, [sp, #0]
    stp x3, x4, [sp, #16]
    stp x5, x6, [sp, #32]
    stp x7, x8, [sp, #48]
    stp x9, x10, [sp, #64]
    stp x11, x12, [sp, #80]
    stp x13, x14, [sp, #96]
    stp x15, x18, [sp, #112]
    stp q0, q1, [sp, #128]
    stp q2, q3, [sp, #160]
    stp q4, q5, [sp, #192]
    stp q6, q7, [sp, #224]
    bl perry_tlv_address
    ldp q6, q7, [sp, #224]
    ldp q4, q5, [sp, #192]
    ldp q2, q3, [sp, #160]
    ldp q0, q1, [sp, #128]
    ldp x15, x18, [sp, #112]
    ldp x13, x14, [sp, #96]
    ldp x11, x12, [sp, #80]
    ldp x9, x10, [sp, #64]
    ldp x7, x8, [sp, #48]
    ldp x5, x6, [sp, #32]
    ldp x3, x4, [sp, #16]
    ldp x1, x2, [sp, #0]
    add sp, sp, #256
    ldp x29, x30, [sp], #16
    ret
    .size perry_tlv_get_addr, .-perry_tlv_get_addr
#elif defined(__arm__)
// The same for Darwin's armv7, which keeps its stack four-byte aligned where
// C on Linux expects eight, so the thunk aligns it for perry_tlv_address.
    .text
    .arm
    .globl perry_tlv_get_addr
    .type perry_tlv_get_addr, %function
    .p2align 2
perry_tlv_get_addr:
    push {r1-r4, r12, lr}
    mov r4, sp
    bic sp, sp, #7
    vpush {d0-d7}
    bl perry_tlv_address
    vpop {d0-d7}
    mov sp, r4
    pop {r1-r4, r12, lr}
    bx lr
    .size perry_tlv_get_addr, .-perry_tlv_get_addr
#elif defined(__x86_64__)
// The same for x86_64: the descriptor comes in rdi, the address goes out in
// rax, and every register but those two is preserved.
    .text
    .globl perry_tlv_get_addr
    .type perry_tlv_get_addr, @function
    .p2align 4
perry_tlv_get_addr:
    pushq %rbp
    movq %rsp, %rbp
    pushq %rcx
    pushq %rdx
    pushq %rsi
    pushq %r8
    pushq %r9
    pushq %r10
    pushq %r11
    subq $136, %rsp
    movups %xmm0, 0(%rsp)
    movups %xmm1, 16(%rsp)
    movups %xmm2, 32(%rsp)
    movups %xmm3, 48(%rsp)
    movups %xmm4, 64(%rsp)
    movups %xmm5, 80(%rsp)
    movups %xmm6, 96(%rsp)
    movups %xmm7, 112(%rsp)
    call perry_tlv_address@PLT
    movups 112(%rsp), %xmm7
    movups 96(%rsp), %xmm6
    movups 80(%rsp), %xmm5
    movups 64(%rsp), %xmm4
    movups 48(%rsp), %xmm3
    movups 32(%rsp), %xmm2
    movups 16(%rsp), %xmm1
    movups 0(%rsp), %xmm0
    addq $136, %rsp
    popq %r11
    popq %r10
    popq %r9
    popq %r8
    popq %rsi
    popq %rdx
    popq %rcx
    popq %rbp
    ret
    .size perry_tlv_get_addr, .-perry_tlv_get_addr
#endif
    .section .note.GNU-stack,"",%progbits
