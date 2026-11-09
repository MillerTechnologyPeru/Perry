// Key-value observing's setter, and calls to getters returning structures,
// for arm64 ELF.
//
// A setter of any argument type, for the classes KVO makes: it keeps every
// argument register, asks Foundation for the setter it replaces (which
// also sends -willChangeValueForKey:), calls it with the arguments
// untouched, then lets Foundation send -didChangeValueForKey:.

#if defined(__x86_64__) && defined(__ELF__)

    .text

// void perry_kvo_setter(id self, SEL _cmd, ...)
    .globl perry_kvo_setter
    .hidden perry_kvo_setter
    .type perry_kvo_setter, @function
    .p2align 4
perry_kvo_setter:
    pushq %rbp
    movq %rsp, %rbp
    subq $112, %rsp
    movq %rdi, 0(%rsp)
    movq %rsi, 8(%rsp)
    movq %rdx, 16(%rsp)
    movq %rcx, 24(%rsp)
    movq %r8, 32(%rsp)
    movq %r9, 40(%rsp)
    movups %xmm0, 48(%rsp)
    movups %xmm1, 64(%rsp)
    call perry_foundation_kvo_will@PLT
    movq %rax, %r11
    movq 0(%rsp), %rdi
    movq 8(%rsp), %rsi
    movq 16(%rsp), %rdx
    movq 24(%rsp), %rcx
    movq 32(%rsp), %r8
    movq 40(%rsp), %r9
    movups 48(%rsp), %xmm0
    movups 64(%rsp), %xmm1
    call *%r11
    movq 0(%rsp), %rdi
    movq 8(%rsp), %rsi
    call perry_foundation_kvo_did@PLT
    leave
    ret
    .size perry_kvo_setter, . - perry_kvo_setter

// void perry_foundation_call_getter(id self, SEL _cmd, IMP imp, void *indirect,
//                                   uint64_t registers[6])
// Calls a getter. A result over 16 bytes goes to `indirect`, which is NULL
// otherwise; rax, rdx, xmm0 and xmm1 are saved to `registers` for the rest.
    .globl perry_foundation_call_getter
    .hidden perry_foundation_call_getter
    .type perry_foundation_call_getter, @function
    .p2align 4
perry_foundation_call_getter:
    pushq %rbp
    movq %rsp, %rbp
    subq $16, %rsp
    movq %r8, 0(%rsp)
    movq %rdx, %r11
    testq %rcx, %rcx
    jz 1f
    movq %rsi, %rdx
    movq %rdi, %rsi
    movq %rcx, %rdi
1:  call *%r11
    movq 0(%rsp), %rcx
    movq %rax, 0(%rcx)
    movq %rdx, 8(%rcx)
    movsd %xmm0, 16(%rcx)
    movsd %xmm1, 24(%rcx)
    leave
    ret
    .size perry_foundation_call_getter, . - perry_foundation_call_getter

// void perry_foundation_call_setter(id self, SEL _cmd, IMP imp,
//                                   const uint64_t registers[6])
// Calls a setter whose argument is 16 bytes or less: rdx, rcx, xmm0 and xmm1
// come from `registers`.
    .globl perry_foundation_call_setter
    .hidden perry_foundation_call_setter
    .type perry_foundation_call_setter, @function
    .p2align 4
perry_foundation_call_setter:
    movq %rdx, %r11
    movq %rcx, %r10
    movq 0(%r10), %rdx
    movq 8(%r10), %rcx
    movsd 16(%r10), %xmm0
    movsd 24(%r10), %xmm1
    jmp *%r11
    .size perry_foundation_call_setter, . - perry_foundation_call_setter

// void perry_foundation_call_setter_memory(id self, SEL _cmd, IMP imp,
//                                          const void *bytes, size_t size)
// Calls a setter whose argument is a structure over 16 bytes, which is passed
// by value on the stack.
    .globl perry_foundation_call_setter_memory
    .hidden perry_foundation_call_setter_memory
    .type perry_foundation_call_setter_memory, @function
    .p2align 4
perry_foundation_call_setter_memory:
    pushq %rbp
    movq %rsp, %rbp
    movq %rdx, %r11
    movq %rdi, %r9
    movq %rsi, %r10
    leaq 15(%r8), %rax
    andq $-16, %rax
    subq %rax, %rsp
    movq %rsp, %rdi
    movq %rcx, %rsi
    movq %r8, %rcx
    rep movsb
    movq %r9, %rdi
    movq %r10, %rsi
    call *%r11
    leave
    ret
    .size perry_foundation_call_setter_memory, . - perry_foundation_call_setter_memory

    .section .note.GNU-stack, "", @progbits

#elif defined(__aarch64__) && defined(__ELF__)

    .text

// void perry_kvo_setter(id self, SEL _cmd, ...)
    .globl perry_kvo_setter
    .hidden perry_kvo_setter
    .type perry_kvo_setter, %function
    .p2align 2
perry_kvo_setter:
    stp x29, x30, [sp, #-176]!
    mov x29, sp
    stp x0, x1, [sp, #16]
    stp x2, x3, [sp, #32]
    stp x4, x5, [sp, #48]
    stp x6, x7, [sp, #64]
    str x8, [sp, #80]
    stp q0, q1, [sp, #96]
    stp q2, q3, [sp, #128]
    bl perry_foundation_kvo_will
    str x0, [sp, #160]
    ldp x0, x1, [sp, #16]
    ldp x2, x3, [sp, #32]
    ldp x4, x5, [sp, #48]
    ldp x6, x7, [sp, #64]
    ldr x8, [sp, #80]
    ldp q0, q1, [sp, #96]
    ldp q2, q3, [sp, #128]
    ldr x16, [sp, #160]
    blr x16
    ldp x0, x1, [sp, #16]
    bl perry_foundation_kvo_did
    ldp x29, x30, [sp], #176
    ret
    .size perry_kvo_setter, . - perry_kvo_setter

// void perry_foundation_call_getter(id self, SEL _cmd, IMP imp, void *indirect,
//                                   uint64_t registers[6])
// Calls a getter whose result may be a structure: x8 points at `indirect`
// for large ones; x0, x1 and d0 to d3 are saved to `registers` for the rest.
    .globl perry_foundation_call_getter
    .hidden perry_foundation_call_getter
    .type perry_foundation_call_getter, %function
    .p2align 2
perry_foundation_call_getter:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x4, [sp, #16]
    mov x8, x3
    blr x2
    ldr x9, [sp, #16]
    stp x0, x1, [x9]
    stp d0, d1, [x9, #16]
    stp d2, d3, [x9, #32]
    ldp x29, x30, [sp], #32
    ret
    .size perry_foundation_call_getter, . - perry_foundation_call_getter

// void perry_foundation_call_setter(id self, SEL _cmd, IMP imp,
//                                   const uint64_t registers[6])
// Calls a setter whose argument may be a structure: x2, x3 and d0 to d3
// come from `registers` (a large structure's address is in x2).
    .globl perry_foundation_call_setter
    .hidden perry_foundation_call_setter
    .type perry_foundation_call_setter, %function
    .p2align 2
perry_foundation_call_setter:
    mov x16, x2
    mov x9, x3
    ldp x2, x3, [x9]
    ldp d0, d1, [x9, #16]
    ldp d2, d3, [x9, #32]
    br x16
    .size perry_foundation_call_setter, . - perry_foundation_call_setter

    .section .note.GNU-stack, "", %progbits

#endif

.section .note.GNU-stack, "", %progbits
