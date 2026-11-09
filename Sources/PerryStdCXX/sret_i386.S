// void *perry_stdcxx_sret(void *function, void *a, void *b, void *c)
//
// Calls a Linux i386 function that returns a small structure through a hidden
// pointer before its arguments, which it pops itself, and returns that
// structure's word. Arguments it does not take are harmless.

#if defined(__i386__) && defined(__ELF__)

    .text
    .globl perry_stdcxx_sret
    .hidden perry_stdcxx_sret
    .type perry_stdcxx_sret, @function
    .p2align 4
perry_stdcxx_sret:
    pushl %ebp
    movl %esp, %ebp
    subl $32, %esp
    andl $-16, %esp
    movl 20(%ebp), %eax
    movl %eax, 12(%esp)
    movl 16(%ebp), %eax
    movl %eax, 8(%esp)
    movl 12(%ebp), %eax
    movl %eax, 4(%esp)
    leal -4(%ebp), %eax
    movl %eax, 0(%esp)
    call *8(%ebp)
    movl -4(%ebp), %eax
    leave
    ret
    .size perry_stdcxx_sret, . - perry_stdcxx_sret

#endif

    .section .note.GNU-stack, "", %progbits
