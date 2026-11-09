// objc_msgSend and friends for x86_64 ELF; see msgsend.S for the cache.
//
// Only r10 and r11 are free at a call, and al holds a variadic call's count
// of vector registers, so the probe keeps rax below the stack pointer.
// x86_64 returns structures over 16 bytes through a pointer in rdi, moving
// the receiver to rsi and the selector to rdx: the _stret entry points. long
// double results come back on the x87 stack: the _fpret entry points, which
// differ from a plain send only for nil.

#if defined(__x86_64__) && defined(__ELF__)

    .text

.macro ENTRY name
    .globl \name
    .type \name, @function
    .p2align 4
\name:
.endm

.macro END name
    .size \name, . - \name
.endm

// Saves the argument registers: leaves the stack 16-aligned.
.macro SAVE_ARGUMENTS
    pushq %rbp
    movq %rsp, %rbp
    subq $192, %rsp
    movq %rdi, 0(%rsp)
    movq %rsi, 8(%rsp)
    movq %rdx, 16(%rsp)
    movq %rcx, 24(%rsp)
    movq %r8, 32(%rsp)
    movq %r9, 40(%rsp)
    movq %rax, 48(%rsp)
    movups %xmm0, 64(%rsp)
    movups %xmm1, 80(%rsp)
    movups %xmm2, 96(%rsp)
    movups %xmm3, 112(%rsp)
    movups %xmm4, 128(%rsp)
    movups %xmm5, 144(%rsp)
    movups %xmm6, 160(%rsp)
    movups %xmm7, 176(%rsp)
.endm

.macro RESTORE_ARGUMENTS
    movups 176(%rsp), %xmm7
    movups 160(%rsp), %xmm6
    movups 144(%rsp), %xmm5
    movups 128(%rsp), %xmm4
    movups 112(%rsp), %xmm3
    movups 96(%rsp), %xmm2
    movups 80(%rsp), %xmm1
    movups 64(%rsp), %xmm0
    movq 48(%rsp), %rax
    movq 40(%rsp), %r9
    movq 32(%rsp), %r8
    movq 24(%rsp), %rcx
    movq 16(%rsp), %rdx
    movq 8(%rsp), %rsi
    movq 0(%rsp), %rdi
    leave
.endm

// With the receiver in \receiver, the selector in \selector and the class
// in r11: jumps to the method.
.macro LOOKUP receiver, selector
    movq %rax, -8(%rsp)
    movq 16(%r11), %r10             // class->cache
    testq %r10, %r10
    jz 3f
    movq (%r10), %r10               // cache table
    movq \selector, %rax
    shrq $3, %rax
1:  andq (%r10), %rax               // mask
    addq %rax, %rax                 // buckets are two words, after the mask
    cmpq \selector, 8(%r10, %rax, 8)
    je 2f
    cmpq $0, 8(%r10, %rax, 8)
    je 3f
    shrq $1, %rax
    incq %rax
    jmp 1b
2:  movq 16(%r10, %rax, 8), %r10
    testq %r10, %r10
    jz 3f
    movq -8(%rsp), %rax
    jmp *%r10
3:  movq -8(%rsp), %rax
    SAVE_ARGUMENTS
    // In this order, since \selector may be rsi or rdx.
    movq \receiver, %rdi
    movq \selector, %rsi
    movq %r11, %rdx
    call perry_objc_lookup_slow@PLT
    movq %rax, %r11
    RESTORE_ARGUMENTS
    jmp *%r11
.endm

// id objc_msgSend(id self, SEL _cmd, ...)
ENTRY _objc_msgSend
.Lmsgsend:
    testq %rdi, %rdi
    jz .Lnil
    movq (%rdi), %r11               // isa
    testq %r11, %r11
    jz .Lnil                        // a missing class's placeholder: as nil
.Llookup:
    LOOKUP %rdi, %rsi
// Messages to nil return zero in every result register.
.Lnil:
    xorl %eax, %eax                 // a placeholder receiver is not returned
    xorl %edx, %edx
    xorps %xmm0, %xmm0
    xorps %xmm1, %xmm1
    ret
END _objc_msgSend

// void objc_msgSend_stret(void *result, id self, SEL _cmd, ...)
ENTRY _objc_msgSend_stret
.Lmsgsend_stret:
    testq %rsi, %rsi
    jz .Lnil_stret
    movq (%rsi), %r11
    testq %r11, %r11
    jz .Lnil_stret
.Llookup_stret:
    LOOKUP %rsi, %rdx
.Lnil_stret:                        // the result is left alone, as Darwin's is
    movq %rdi, %rax
    ret
END _objc_msgSend_stret

// long double objc_msgSend_fpret(id self, SEL _cmd, ...)
ENTRY _objc_msgSend_fpret
    testq %rdi, %rdi
    jz 1f
    movq (%rdi), %r11
    testq %r11, %r11
    jnz .Llookup
1:  fldz
    xorl %eax, %eax
    ret
END _objc_msgSend_fpret

// long double _Complex objc_msgSend_fp2ret(id self, SEL _cmd, ...)
ENTRY _objc_msgSend_fp2ret
    testq %rdi, %rdi
    jz 1f
    movq (%rdi), %r11
    testq %r11, %r11
    jnz .Llookup
1:  fldz
    fldz
    xorl %eax, %eax
    ret
END _objc_msgSend_fp2ret

// id objc_msgSendSuper(struct objc_super *super, SEL _cmd, ...)
// super = { receiver, class to start the search at }
ENTRY _objc_msgSendSuper
    movq 8(%rdi), %r11
    movq (%rdi), %rdi
    jmp .Llookup
END _objc_msgSendSuper

ENTRY _objc_msgSendSuper_stret
    movq 8(%rsi), %r11
    movq (%rsi), %rsi
    jmp .Llookup_stret
END _objc_msgSendSuper_stret

// id objc_msgSendSuper2(struct objc_super *super, SEL _cmd, ...)
// super = { receiver, current class }: the search starts at its superclass.
ENTRY _objc_msgSendSuper2
.Lmsgsend_super2:
    movq 8(%rdi), %r11
    movq 8(%r11), %r11
    movq (%rdi), %rdi
    jmp .Llookup
END _objc_msgSendSuper2

ENTRY _objc_msgSendSuper2_stret
.Lmsgsend_super2_stret:
    movq 8(%rsi), %r11
    movq 8(%r11), %r11
    movq (%rsi), %rsi
    jmp .Llookup_stret
END _objc_msgSendSuper2_stret

// The IMP for selectors a class does not implement. Asks the runtime for a
// forwarding target and resends, or jumps to the forward handler with the
// original arguments. perry_objc_forward aborts when neither exists; its
// two words come back in rax and rdx.
ENTRY __objc_msgForward
.Lmsgforward:
    SAVE_ARGUMENTS
    call perry_objc_forward@PLT
    movq %rax, %r10
    movq %rdx, %r11
    RESTORE_ARGUMENTS
    testq %r10, %r10
    jz 1f
    movq %r10, %rdi
    jmp .Lmsgsend
1:  jmp *%r11
END __objc_msgForward

ENTRY __objc_msgForward_stret
    SAVE_ARGUMENTS
    movq %rsi, %rdi
    movq %rdx, %rsi
    call perry_objc_forward@PLT
    movq %rax, %r10
    movq %rdx, %r11
    RESTORE_ARGUMENTS
    testq %r10, %r10
    jz 1f
    movq %r10, %rsi
    jmp .Lmsgsend_stret
1:  jmp *%r11
END __objc_msgForward_stret

.macro ADDRESS name, label
    .globl \name
    .type \name, @function
    .p2align 4
\name:
    leaq \label(%rip), %rax
    ret
    .size \name, . - \name
.endm

ADDRESS perry_objc_msgSend_address, .Lmsgsend
ADDRESS perry_objc_msgSendSuper2_address, .Lmsgsend_super2
ADDRESS perry_objc_msgForward_address, .Lmsgforward
ADDRESS perry_objc_msgSend_stret_address, .Lmsgsend_stret
ADDRESS perry_objc_msgSendSuper2_stret_address, .Lmsgsend_super2_stret

    .section .note.GNU-stack, "", @progbits

#endif

.section .note.GNU-stack, "", %progbits
