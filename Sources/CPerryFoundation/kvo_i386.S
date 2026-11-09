// Key-value observing's setter and NSInvocation's call, for i386 ELF.
//
// Arguments are on the stack in words, so a setter of any argument type copies
// its caller's words: self, _cmd and 16 more, which hold any setter's argument
// up to a 64-byte structure.

#if defined(__i386__) && defined(__ELF__)

    .text

    .hidden perry_i386_kvo_pc_ebx
    .type perry_i386_kvo_pc_ebx, @function
perry_i386_kvo_pc_ebx:
    movl (%esp), %ebx
    ret

// void perry_kvo_setter(id self, SEL _cmd, ...)
    .globl perry_kvo_setter
    .hidden perry_kvo_setter
    .type perry_kvo_setter, @function
    .p2align 4
perry_kvo_setter:
    pushl %ebp
    movl %esp, %ebp
    pushl %ebx
    subl $92, %esp
    andl $-16, %esp
    call perry_i386_kvo_pc_ebx
    addl $_GLOBAL_OFFSET_TABLE_, %ebx
    movl 12(%ebp), %eax
    movl %eax, 4(%esp)
    movl 8(%ebp), %eax
    movl %eax, 0(%esp)
    call perry_foundation_kvo_will@PLT
    movl %eax, %ecx
    xorl %edx, %edx
1:  movl 8(%ebp, %edx, 4), %eax
    movl %eax, (%esp, %edx, 4)
    incl %edx
    cmpl $18, %edx
    jb 1b
    call *%ecx
    movl 12(%ebp), %eax
    movl %eax, 4(%esp)
    movl 8(%ebp), %eax
    movl %eax, 0(%esp)
    call perry_foundation_kvo_did@PLT
    movl -4(%ebp), %ebx
    leave
    ret
    .size perry_kvo_setter, . - perry_kvo_setter

// void perry_foundation_invoke_i386(const void *imp, const uint32_t *stack,
//                                   size_t words, uint32_t out[2], double *floating)
    .globl perry_foundation_invoke_i386
    .hidden perry_foundation_invoke_i386
    .type perry_foundation_invoke_i386, @function
    .p2align 4
perry_foundation_invoke_i386:
    pushl %ebp
    movl %esp, %ebp
    pushl %esi
    pushl %edi
    movl 16(%ebp), %ecx             // words
    leal (,%ecx,4), %eax
    subl %eax, %esp
    andl $-16, %esp
    movl 12(%ebp), %esi
    movl %esp, %edi
    cld
    rep movsl
    call *8(%ebp)
    movl 20(%ebp), %ecx
    movl %eax, 0(%ecx)
    movl %edx, 4(%ecx)
    movl 24(%ebp), %ecx
    testl %ecx, %ecx
    jz 2f
    fstpl (%ecx)
2:  leal -8(%ebp), %esp
    popl %edi
    popl %esi
    popl %ebp
    ret
    .size perry_foundation_invoke_i386, . - perry_foundation_invoke_i386

#endif

.section .note.GNU-stack, "", %progbits
