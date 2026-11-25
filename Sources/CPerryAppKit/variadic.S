// Variadic AppKit functions: the alert panels, whose message is a format.
// Each has five fixed arguments (the title, the format and three button
// titles); its entry point passes a Darwin va_list of the rest after them
// and goes to Swift, as CPerryFoundation's variadic.S does for Foundation.

#if defined(__x86_64__) && defined(__ELF__)

// The arguments are in registers, then on the stack: the entry point saves
// the registers and passes a pointer to a va_list over them in the sixth
// argument's register.
.macro ALERT_PANEL name, target
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
    movl $40, 176(%rsp)                 // gp_offset: past five arguments
    movl $48, 180(%rsp)                 // fp_offset
    leaq 16(%rbp), %rax
    movq %rax, 184(%rsp)                // overflow_arg_area
    movq %rsp, 192(%rsp)                // reg_save_area
    leaq 176(%rsp), %r9
    call \target@PLT
    leave
    .cfi_def_cfa %rsp, 8
    ret
    .cfi_endproc
    .size \name, . - \name
.endm

#elif defined(__aarch64__) && defined(__ELF__)

// Apple's arm64 ABI passes every variadic argument in a stack slot from the
// caller's sp, which is a Darwin va_list.
.macro ALERT_PANEL name, target
    .globl \name
    .type \name, %function
    .p2align 2
\name:
    mov x5, sp
    b \target
    .size \name, . - \name
.endm

#elif defined(__i386__) && defined(__ELF__)

// The arguments are on the stack in words, and a Darwin va_list is a pointer
// to the first variadic one: the entry point calls Swift with the fixed
// arguments again and that pointer after them.
    .hidden perry_i386_appkit_pc_ebx
    .type perry_i386_appkit_pc_ebx, @function
perry_i386_appkit_pc_ebx:
    movl (%esp), %ebx
    ret

.macro ALERT_PANEL name, target
    .globl \name
    .type \name, @function
    .p2align 4
\name:
    pushl %ebp
    movl %esp, %ebp
    pushl %ebx
    subl $52, %esp
    andl $-16, %esp
    .set index, 0
    .rept 5
    movl (8 + 4 * index)(%ebp), %eax
    movl %eax, (4 * index)(%esp)
    .set index, index + 1
    .endr
    leal 28(%ebp), %eax
    movl %eax, 20(%esp)
    call perry_i386_appkit_pc_ebx
    addl $_GLOBAL_OFFSET_TABLE_, %ebx
    call \target@PLT
    movl -4(%ebp), %ebx
    leave
    ret
    .size \name, . - \name
.endm

#endif

#if (defined(__aarch64__) || defined(__x86_64__) || defined(__i386__)) && defined(__ELF__)

    .text

// NSInteger NSRunAlertPanel(NSString *title, NSString *format, NSString *defaultButton,
//                           NSString *alternateButton, NSString *otherButton, ...)
ALERT_PANEL _NSRunAlertPanel, perry_appkit_run_alert_panel
ALERT_PANEL _NSRunInformationalAlertPanel, perry_appkit_run_informational_alert_panel
ALERT_PANEL _NSRunCriticalAlertPanel, perry_appkit_run_critical_alert_panel

#endif

.section .note.GNU-stack, "", %progbits
