// Calls across Darwin's ppc ABI and Linux's (SysV), for ppc_abi.c, which
// decides where each argument goes.
//
// perry_ppc_darwin_trampoline is where Darwin code enters a Linux function
// that needs its arguments moved: the stub for it (ppc_abi.c) sets r2, puts
// the function's plan in r11 and branches here. It saves Darwin's argument
// registers and calls perry_ppc_from_darwin, which calls the function and
// leaves Darwin's result registers in the frame.
//
// perry_ppc_invoke_sysv and perry_ppc_invoke_darwin call a function with
// argument registers and stack words already laid out for its ABI.

#if defined(__powerpc__) && !defined(__powerpc64__) && defined(__ELF__)

    .text

// The trampoline's frame: the back chain and lr word, r3-r10, f1-f13, the
// result (r3, r4, f1), then the saved lr.
TFRAME = 176
T_GPRS = 16
T_FPRS = 48
T_RESULT = 152
T_LR = 172

    .globl perry_ppc_darwin_trampoline
    .hidden perry_ppc_darwin_trampoline
    .type perry_ppc_darwin_trampoline, @function
    .p2align 4
perry_ppc_darwin_trampoline:
    mflr %r0
    stwu %r1, -TFRAME(%r1)
    stw %r0, T_LR(%r1)
    stw %r3, T_GPRS + 0(%r1)
    stw %r4, T_GPRS + 4(%r1)
    stw %r5, T_GPRS + 8(%r1)
    stw %r6, T_GPRS + 12(%r1)
    stw %r7, T_GPRS + 16(%r1)
    stw %r8, T_GPRS + 20(%r1)
    stw %r9, T_GPRS + 24(%r1)
    stw %r10, T_GPRS + 28(%r1)
    stfd %f1, T_FPRS + 0(%r1)
    stfd %f2, T_FPRS + 8(%r1)
    stfd %f3, T_FPRS + 16(%r1)
    stfd %f4, T_FPRS + 24(%r1)
    stfd %f5, T_FPRS + 32(%r1)
    stfd %f6, T_FPRS + 40(%r1)
    stfd %f7, T_FPRS + 48(%r1)
    stfd %f8, T_FPRS + 56(%r1)
    stfd %f9, T_FPRS + 64(%r1)
    stfd %f10, T_FPRS + 72(%r1)
    stfd %f11, T_FPRS + 80(%r1)
    stfd %f12, T_FPRS + 88(%r1)
    stfd %f13, T_FPRS + 96(%r1)
    mr %r3, %r11                    // the plan
    addi %r4, %r1, T_GPRS
    addi %r5, %r1, T_FPRS
    addi %r6, %r1, TFRAME           // the caller's stack: its parameter area is at 24
    addi %r7, %r1, T_RESULT
    bl perry_ppc_from_darwin
    lwz %r3, T_RESULT + 0(%r1)
    lwz %r4, T_RESULT + 4(%r1)
    lfd %f1, T_RESULT + 8(%r1)
    lwz %r0, T_LR(%r1)
    mtlr %r0
    addi %r1, %r1, TFRAME
    blr
    .size perry_ppc_darwin_trampoline, . - perry_ppc_darwin_trampoline

// void perry_ppc_invoke_sysv(void *function, const uint32_t gprs[8],
//                            const double fprs[8], const uint32_t *stack,
//                            uint32_t stack_words, perry_ppc_registers *result)
//
// The stack words go at 8(r1), where SysV's callee finds its arguments past
// r10 and f8.
    .globl perry_ppc_invoke_sysv
    .hidden perry_ppc_invoke_sysv
    .type perry_ppc_invoke_sysv, @function
    .p2align 4
perry_ppc_invoke_sysv:
    mflr %r0
    stw %r0, 4(%r1)
    stwu %r1, -32(%r1)
    stw %r31, 28(%r1)
    stw %r30, 24(%r1)
    mr %r31, %r1
    mr %r30, %r8
    mr %r11, %r3                    // the function
    mr %r12, %r4                    // the registers
    lfd %f1, 0(%r5)
    lfd %f2, 8(%r5)
    lfd %f3, 16(%r5)
    lfd %f4, 24(%r5)
    lfd %f5, 32(%r5)
    lfd %f6, 40(%r5)
    lfd %f7, 48(%r5)
    lfd %f8, 56(%r5)
    slwi %r9, %r7, 2
    addi %r9, %r9, 8 + 15
    rlwinm %r9, %r9, 0, 0, 27
    neg %r9, %r9
    stwux %r1, %r1, %r9             // room for the stack words, with the back chain
    cmpwi %r7, 0
    beq 2f
    mtctr %r7
    addi %r9, %r1, 8 - 4
    addi %r10, %r6, -4
1:  lwzu %r0, 4(%r10)
    stwu %r0, 4(%r9)
    bdnz 1b
2:  mtctr %r11
    lwz %r3, 0(%r12)
    lwz %r4, 4(%r12)
    lwz %r5, 8(%r12)
    lwz %r6, 12(%r12)
    lwz %r7, 16(%r12)
    lwz %r8, 20(%r12)
    lwz %r9, 24(%r12)
    lwz %r10, 28(%r12)
    bctrl
    stw %r3, 0(%r30)
    stw %r4, 4(%r30)
    stfd %f1, 8(%r30)
    mr %r1, %r31
    lwz %r30, 24(%r1)
    lwz %r31, 28(%r1)
    addi %r1, %r1, 32
    lwz %r0, 4(%r1)
    mtlr %r0
    blr
    .size perry_ppc_invoke_sysv, . - perry_ppc_invoke_sysv

// void perry_ppc_invoke_darwin(void *function, const uint32_t gprs[8],
//                              const double fprs[13], const uint32_t *words,
//                              uint32_t word_count, perry_ppc_registers *result)
//
// words are all of the call's argument words, the first eight of which are
// also in r3-r10: Darwin's parameter area, at 24(r1) after the linkage area,
// holds every one. Darwin code may change r2, Linux's thread pointer, which
// is kept here.
    .globl perry_ppc_invoke_darwin
    .hidden perry_ppc_invoke_darwin
    .type perry_ppc_invoke_darwin, @function
    .p2align 4
perry_ppc_invoke_darwin:
    mflr %r0
    stw %r0, 4(%r1)
    stwu %r1, -32(%r1)
    stw %r31, 28(%r1)
    stw %r30, 24(%r1)
    stw %r29, 20(%r1)
    mr %r31, %r1
    mr %r30, %r8
    mr %r29, %r2
    mr %r11, %r3                    // the function
    mr %r12, %r4                    // the registers
    // The parameter area has at least the eight words of r3-r10.
    cmpwi %r7, 8
    bge 3f
    li %r7, 8
3:  slwi %r9, %r7, 2
    addi %r9, %r9, 24 + 15
    rlwinm %r9, %r9, 0, 0, 27
    neg %r9, %r9
    stwux %r1, %r1, %r9
    mtctr %r7
    addi %r9, %r1, 24 - 4
    addi %r10, %r6, -4
1:  lwzu %r0, 4(%r10)
    stwu %r0, 4(%r9)
    bdnz 1b
    lfd %f1, 0(%r5)
    lfd %f2, 8(%r5)
    lfd %f3, 16(%r5)
    lfd %f4, 24(%r5)
    lfd %f5, 32(%r5)
    lfd %f6, 40(%r5)
    lfd %f7, 48(%r5)
    lfd %f8, 56(%r5)
    lfd %f9, 64(%r5)
    lfd %f10, 72(%r5)
    lfd %f11, 80(%r5)
    lfd %f12, 88(%r5)
    lfd %f13, 96(%r5)
    mtctr %r11
    lwz %r3, 0(%r12)
    lwz %r4, 4(%r12)
    lwz %r5, 8(%r12)
    lwz %r6, 12(%r12)
    lwz %r7, 16(%r12)
    lwz %r8, 20(%r12)
    lwz %r9, 24(%r12)
    lwz %r10, 28(%r12)
    bctrl
    mr %r2, %r29
    stw %r3, 0(%r30)
    stw %r4, 4(%r30)
    stfd %f1, 8(%r30)
    mr %r1, %r31
    lwz %r29, 20(%r1)
    lwz %r30, 24(%r1)
    lwz %r31, 28(%r1)
    addi %r1, %r1, 32
    lwz %r0, 4(%r1)
    mtlr %r0
    blr
    .size perry_ppc_invoke_darwin, . - perry_ppc_invoke_darwin

// perry_ppc_darwin_from_linux calls the Darwin function in r11 with the
// words in r3-r10 for Linux code: the stubs perry_ppc_linux_callable makes
// branch here (a block's invoke, a work function, a comparator). Darwin's
// callee saves its lr at 8(r1) of its caller's frame, and may store r3-r10
// at 24(r1) on, where a Linux caller keeps its own registers and locals: so
// the call is made from this frame, laid out as a Darwin caller's (the
// linkage area, then a parameter area holding the words), and r2, Linux's
// thread pointer, is kept. The results (r3, r3:r4, f1) come back as they
// are, and so do f1-f8, which Darwin reads as Linux passes them when they
// follow every word argument.
WFRAME = 80
W_R2 = 64
    .globl perry_ppc_darwin_from_linux
    .hidden perry_ppc_darwin_from_linux
    .type perry_ppc_darwin_from_linux, @function
    .p2align 4
perry_ppc_darwin_from_linux:
    mflr %r0
    stw %r0, 4(%r1)
    stwu %r1, -WFRAME(%r1)
    stw %r2, W_R2(%r1)
    stw %r3, 24(%r1)
    stw %r4, 28(%r1)
    stw %r5, 32(%r1)
    stw %r6, 36(%r1)
    stw %r7, 40(%r1)
    stw %r8, 44(%r1)
    stw %r9, 48(%r1)
    stw %r10, 52(%r1)
    mtctr %r11
    bctrl
    lwz %r2, W_R2(%r1)
    addi %r1, %r1, WFRAME
    lwz %r0, 4(%r1)
    mtlr %r0
    blr
    .size perry_ppc_darwin_from_linux, . - perry_ppc_darwin_from_linux

// uint32_t perry_ppc_call_darwin_words(void *function, uint32_t a, ...)
//
// The same, for a call of up to seven words that names the function.
    .globl perry_ppc_call_darwin_words
    .type perry_ppc_call_darwin_words, @function
    .p2align 4
perry_ppc_call_darwin_words:
    mr %r11, %r3
    mr %r3, %r4
    mr %r4, %r5
    mr %r5, %r6
    mr %r6, %r7
    mr %r7, %r8
    mr %r8, %r9
    mr %r9, %r10
    b perry_ppc_darwin_from_linux
    .size perry_ppc_call_darwin_words, . - perry_ppc_call_darwin_words

// Sends from Linux code (the Swift providers), with the arguments as Linux
// passes their C signature: perry_ppc_send_from_linux finds the method and
// calls it as Darwin code would, by its type encoding. A provider's own
// method is reached through its Darwin entry (perry_ppc_darwin_entry), so
// it gets them back as Linux passes them.
.macro SEND name, kind
    .globl \name
    .type \name, @function
    .p2align 4
\name:
    mflr %r0
    stw %r0, 4(%r1)
    stwu %r1, -128(%r1)
    stw %r3, 16(%r1)
    stw %r4, 20(%r1)
    stw %r5, 24(%r1)
    stw %r6, 28(%r1)
    stw %r7, 32(%r1)
    stw %r8, 36(%r1)
    stw %r9, 40(%r1)
    stw %r10, 44(%r1)
    stfd %f1, 48(%r1)
    stfd %f2, 56(%r1)
    stfd %f3, 64(%r1)
    stfd %f4, 72(%r1)
    stfd %f5, 80(%r1)
    stfd %f6, 88(%r1)
    stfd %f7, 96(%r1)
    stfd %f8, 104(%r1)
    li %r3, \kind
    addi %r4, %r1, 16
    addi %r5, %r1, 48
    addi %r6, %r1, 128              // the caller's stack: its arguments past r10 are at 8
    addi %r7, %r1, 112
    bl perry_ppc_send_from_linux
    lwz %r3, 112(%r1)
    lwz %r4, 116(%r1)
    lfd %f1, 120(%r1)
    addi %r1, %r1, 128
    lwz %r0, 4(%r1)
    mtlr %r0
    blr
    .size \name, . - \name
.endm

SEND perry_ppc_send, 0
SEND perry_ppc_send_stret, 1
SEND perry_ppc_send_super2, 2
SEND perry_ppc_send_super2_stret, 3

#endif

    .section .note.GNU-stack, "", %progbits
