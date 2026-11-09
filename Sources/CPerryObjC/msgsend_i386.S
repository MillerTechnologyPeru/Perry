// objc_msgSend and friends for i386 ELF; see msgsend.S for the cache.
//
// Arguments are on the stack, so eax, ecx and edx are free at a call. A
// structure that does not come back in eax:edx comes back through a pointer
// passed before the receiver, which the method pops with `ret $4`: the _stret
// entry points. Floating point comes back on the x87 stack: objc_msgSend_fpret,
// which differs from a plain send only for nil.

#if defined(__i386__) && defined(__ELF__)

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

// ebx for calls through the PLT, which it must hold in a shared object.
    .hidden perry_i386_objc_pc_ebx
    .type perry_i386_objc_pc_ebx, @function
perry_i386_objc_pc_ebx:
    movl (%esp), %ebx
    ret

// Makes a frame aligned for a call, keeping ebx and the vector registers,
// which some Darwin code passes arguments in.
.macro SAVE_FRAME
    pushl %ebp
    movl %esp, %ebp
    pushl %ebx
    subl $96, %esp
    andl $-16, %esp
    movups %xmm0, 32(%esp)
    movups %xmm1, 48(%esp)
    movups %xmm2, 64(%esp)
    movups %xmm3, 80(%esp)
.endm

.macro RESTORE_FRAME
    movups 32(%esp), %xmm0
    movups 48(%esp), %xmm1
    movups 64(%esp), %xmm2
    movups 80(%esp), %xmm3
    movl -4(%ebp), %ebx
    leave
.endm

// With the class in ecx, and the receiver and selector at these offsets from
// esp: jumps to the method.
.macro LOOKUP receiver, selector
    movl \selector(%esp), %edx
    pushl %ebx
    movl 8(%ecx), %eax              // class->cache
    testl %eax, %eax
    jz 3f
    movl (%eax), %eax               // cache table
    movl %edx, %ebx
    shrl $2, %ebx
1:  andl (%eax), %ebx               // mask
    cmpl %edx, 4(%eax, %ebx, 8)     // buckets are two words, after the mask
    je 2f
    cmpl $0, 4(%eax, %ebx, 8)
    je 3f
    incl %ebx
    jmp 1b
2:  movl 8(%eax, %ebx, 8), %eax
    testl %eax, %eax
    jz 3f
    popl %ebx
    jmp *%eax
3:  popl %ebx
    SAVE_FRAME
    movl %ecx, 8(%esp)
    movl (\selector + 4)(%ebp), %eax
    movl %eax, 4(%esp)
    movl (\receiver + 4)(%ebp), %eax
    movl %eax, 0(%esp)
    call perry_i386_objc_pc_ebx
    addl $_GLOBAL_OFFSET_TABLE_, %ebx
    call perry_objc_lookup_slow@PLT
    RESTORE_FRAME
    jmp *%eax
.endm

// id objc_msgSend(id self, SEL _cmd, ...)
ENTRY _objc_msgSend
.Lmsgsend:
    movl 4(%esp), %eax
    testl %eax, %eax
    jz .Lnil
    movl (%eax), %ecx               // isa
    testl %ecx, %ecx
    jz .Lnil                        // a missing class's placeholder: as nil
.Llookup:
    LOOKUP 4, 8
// Messages to nil return zero in eax:edx.
.Lnil:
    xorl %eax, %eax
    xorl %edx, %edx
    ret
END _objc_msgSend

// void objc_msgSend_stret(void *result, id self, SEL _cmd, ...)
ENTRY _objc_msgSend_stret
.Lmsgsend_stret:
    movl 8(%esp), %eax
    testl %eax, %eax
    jz .Lnil_stret
    movl (%eax), %ecx
    testl %ecx, %ecx
    jz .Lnil_stret
.Llookup_stret:
    LOOKUP 8, 12
.Lnil_stret:                        // the result is left alone, as Darwin's is
    movl 4(%esp), %eax
    ret $4
END _objc_msgSend_stret

// double objc_msgSend_fpret(id self, SEL _cmd, ...)
ENTRY _objc_msgSend_fpret
    movl 4(%esp), %eax
    testl %eax, %eax
    jz 1f
    movl (%eax), %ecx
    testl %ecx, %ecx
    jnz .Llookup
1:  fldz
    ret
END _objc_msgSend_fpret

// id objc_msgSendSuper(struct objc_super *super, SEL _cmd, ...)
// super = { receiver, class to start the search at }: the receiver takes its
// place among the arguments.
ENTRY _objc_msgSendSuper
    movl 4(%esp), %eax
    movl 4(%eax), %ecx
    movl (%eax), %eax
    movl %eax, 4(%esp)
    jmp .Llookup
END _objc_msgSendSuper

ENTRY _objc_msgSendSuper_stret
    movl 8(%esp), %eax
    movl 4(%eax), %ecx
    movl (%eax), %eax
    movl %eax, 8(%esp)
    jmp .Llookup_stret
END _objc_msgSendSuper_stret

// id objc_msgSendSuper2(struct objc_super *super, SEL _cmd, ...)
// super = { receiver, current class }: the search starts at its superclass.
ENTRY _objc_msgSendSuper2
.Lmsgsend_super2:
    movl 4(%esp), %eax
    movl 4(%eax), %ecx
    movl 4(%ecx), %ecx
    movl (%eax), %eax
    movl %eax, 4(%esp)
    jmp .Llookup
END _objc_msgSendSuper2

ENTRY _objc_msgSendSuper2_stret
.Lmsgsend_super2_stret:
    movl 8(%esp), %eax
    movl 4(%eax), %ecx
    movl 4(%ecx), %ecx
    movl (%eax), %eax
    movl %eax, 8(%esp)
    jmp .Llookup_stret
END _objc_msgSendSuper2_stret

// The IMP for selectors a class does not implement. Asks the runtime for a
// forwarding target and resends, or jumps to the forward handler with the
// original arguments. perry_objc_forward aborts when neither exists; its two
// words come back in eax and edx.
.macro FORWARD receiver, selector, resend
    SAVE_FRAME
    movl (\selector + 4)(%ebp), %eax
    movl %eax, 4(%esp)
    movl (\receiver + 4)(%ebp), %eax
    movl %eax, 0(%esp)
    call perry_i386_objc_pc_ebx
    addl $_GLOBAL_OFFSET_TABLE_, %ebx
    call perry_objc_forward@PLT
    RESTORE_FRAME
    testl %eax, %eax
    jz 1f
    movl %eax, \receiver(%esp)
    jmp \resend
1:  jmp *%edx
.endm

ENTRY __objc_msgForward
.Lmsgforward:
    FORWARD 4, 8, .Lmsgsend
END __objc_msgForward

ENTRY __objc_msgForward_stret
    FORWARD 8, 12, .Lmsgsend_stret
END __objc_msgForward_stret

// void perry_objc_i386_longjmp(int *buffer): back to Darwin's setjmp
// (libSystem's thunks_i386.S), returning 1.
ENTRY perry_objc_i386_longjmp
    movl 4(%esp), %ecx
    movl 0(%ecx), %ebx
    movl 4(%ecx), %esi
    movl 8(%ecx), %edi
    movl 12(%ecx), %ebp
    movl 16(%ecx), %esp
    ldmxcsr 24(%ecx)
    fldcw 28(%ecx)
    movl 20(%ecx), %edx
    movl $1, %eax
    jmp *%edx
END perry_objc_i386_longjmp

.macro ADDRESS name, label
    .globl \name
    .type \name, @function
    .p2align 4
\name:
    call 1f
1:  popl %eax
    addl $(\label - 1b), %eax
    ret
    .size \name, . - \name
.endm

ADDRESS perry_objc_msgSend_address, .Lmsgsend
ADDRESS perry_objc_msgSendSuper2_address, .Lmsgsend_super2
ADDRESS perry_objc_msgForward_address, .Lmsgforward
ADDRESS perry_objc_msgSend_stret_address, .Lmsgsend_stret
ADDRESS perry_objc_msgSendSuper2_stret_address, .Lmsgsend_super2_stret

#endif

.section .note.GNU-stack, "", %progbits
