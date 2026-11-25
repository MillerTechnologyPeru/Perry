// Variadic CoreServices functions for 64-bit ELF: AEBuild's.
//
// Each entry point saves the variadic arguments as a Darwin va_list and
// calls Swift with the fixed arguments and that va_list after them, as
// CPerryFoundation's variadic.S does for Foundation (whose macros these are).

#if defined(__x86_64__) && defined(__ELF__)

// On x86_64 the arguments are in registers, then on the stack: each entry
// point saves the registers and passes a pointer to a va_list over them,
// as a Darwin va_list is there. `nfloat` counts fixed floating-point
// arguments.
.macro VA_LIST_ARGUMENT nfixed
    .if \nfixed == 1
    leaq 176(%rsp), %rsi
    .elseif \nfixed == 2
    leaq 176(%rsp), %rdx
    .elseif \nfixed == 3
    leaq 176(%rsp), %rcx
    .elseif \nfixed == 4
    leaq 176(%rsp), %r8
    .elseif \nfixed == 5
    leaq 176(%rsp), %r9
    .else
    .error "unexpected number of fixed arguments"
    .endif
.endm

.macro VARIADIC name, target, nfixed, nfloat=0
    .globl \name
    .type \name, @function
    .p2align 4
\name:
    // Described to the unwinder, which an exception the Swift function
    // raises passes through on its way to the caller's @catch.
    .cfi_startproc
    pushq %rbp
    .cfi_def_cfa_offset 16
    .cfi_offset %rbp, -16
    movq %rsp, %rbp
    .cfi_def_cfa_register %rbp
    subq $208, %rsp
    movq %rdi, 0(%rsp)
    movq %rsi, 8(%rsp)
    movq %rdx, 16(%rsp)
    movq %rcx, 24(%rsp)
    movq %r8, 32(%rsp)
    movq %r9, 40(%rsp)
    movups %xmm0, 48(%rsp)
    movups %xmm1, 64(%rsp)
    movups %xmm2, 80(%rsp)
    movups %xmm3, 96(%rsp)
    movups %xmm4, 112(%rsp)
    movups %xmm5, 128(%rsp)
    movups %xmm6, 144(%rsp)
    movups %xmm7, 160(%rsp)
    movl $(\nfixed * 8), 176(%rsp)      // gp_offset
    movl $(48 + \nfloat * 16), 180(%rsp) // fp_offset
    leaq 16(%rbp), %rax
    movq %rax, 184(%rsp)                // overflow_arg_area
    movq %rsp, 192(%rsp)                // reg_save_area
    VA_LIST_ARGUMENT \nfixed
    call \target@PLT
    leave
    .cfi_def_cfa %rsp, 8
    ret
    .cfi_endproc
    .size \name, . - \name
.endm

#elif defined(__aarch64__) && defined(__ELF__)

.macro VARIADIC name, target, nfixed, nfloat=0
    .globl \name
    .type \name, %function
    .p2align 2
\name:
    mov x\nfixed, sp
    b \target
    .size \name, . - \name
.endm

#endif

#if (defined(__aarch64__) || defined(__x86_64__)) && defined(__ELF__)

    .text

// OSStatus AEBuildDesc(AEDesc *, AEBuildError *, const char *, ...)
VARIADIC _AEBuildDesc, perry_ae_build_desc, 3
// OSStatus AEBuildParameters(AppleEvent *, AEBuildError *, const char *, ...)
VARIADIC _AEBuildParameters, perry_ae_build_parameters, 3

#endif

.section .note.GNU-stack, "", %progbits
