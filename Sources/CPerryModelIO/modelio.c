#include "CPerryModelIO.h"

__attribute__((visibility("hidden"))) perry_mdl_vector_getter perry_mdl_vector_getter_function;

void perry_mdl_set_vector_getter(perry_mdl_vector_getter getter) { perry_mdl_vector_getter_function = getter; }

#if defined(__x86_64__) && defined(__ELF__)
// Each calls the getter with a 32-byte buffer on its own (16-byte aligned)
// stack frame, the receiver and selector as they came, and the time still
// in xmm0, then loads the lanes into the registers Darwin returns them in.
__asm__(
    ".text\n"
    ".globl perry_mdl_double4_return\n"
    ".type perry_mdl_double4_return, @function\n"
    "perry_mdl_double4_return:\n"
    "    pushq %rbp\n"
    "    movq %rsp, %rbp\n"
    "    subq $32, %rsp\n"
    "    movq %rsp, %rdx\n"
    "    movq perry_mdl_vector_getter_function(%rip), %rax\n"
    "    call *%rax\n"
    "    movupd (%rsp), %xmm0\n"
    "    movupd 16(%rsp), %xmm1\n"
    "    leave\n"
    "    ret\n"
    ".size perry_mdl_double4_return, .-perry_mdl_double4_return\n"
    ".globl perry_mdl_double3_return\n"
    ".type perry_mdl_double3_return, @function\n"
    "perry_mdl_double3_return:\n"
    "    pushq %rbp\n"
    "    movq %rsp, %rbp\n"
    "    subq $32, %rsp\n"
    "    movq %rsp, %rdx\n"
    "    movq perry_mdl_vector_getter_function(%rip), %rax\n"
    "    call *%rax\n"
    "    movsd (%rsp), %xmm0\n"
    "    movsd 8(%rsp), %xmm1\n"
    "    fldl 16(%rsp)\n"
    "    leave\n"
    "    ret\n"
    ".size perry_mdl_double3_return, .-perry_mdl_double3_return\n");
#else
// Elsewhere these vectors return as the methods' own C signatures say.
void perry_mdl_double3_return(void) {}
void perry_mdl_double4_return(void) {}
#endif
