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
#endif
    .section .note.GNU-stack,"",%progbits
