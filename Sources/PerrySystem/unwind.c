// libunwind's local unwinding API, which programs walk their own stack with
// to report where an exception or error came from (Xojo apps do). Darwin's
// steps with compact unwind and DWARF information; here a cursor follows
// the frame-pointer chain, which Darwin x86_64 code keeps: from a frame's
// rbp, the caller's rbp is at [rbp] and the return address at [rbp + 8].
// Only x86_64 is covered; other architectures report no frames.

#include "PerrySystem.h"

#include <stdint.h>
#include <string.h>

enum { UNW_ESUCCESS = 0, UNW_EUNSPEC = -6540, UNW_EBADREG = -6542, UNW_EINVAL = -6547 };
enum { UNW_REG_IP = -1, UNW_REG_SP = -2, UNW_X86_64_RBP = 6, UNW_X86_64_RSP = 7 };

// A cursor's own words, inside Darwin's larger unw_cursor_t: the frame's
// instruction pointer, stack pointer and frame pointer, and a mark that
// unw_init_local set it up.
enum { CURSOR_IP, CURSOR_SP, CURSOR_BP, CURSOR_MARK };
#define CURSOR_MAGIC 0x7065727279756e77ull

#if defined(__x86_64__)

// int unw_getcontext(unw_context_t *): the registers in libunwind's x86_64
// order (rax, rbx, rcx, rdx, rdi, rsi, rbp, rsp, r8-r15, rip), as the
// caller has them: rsp after the return, rip the return address.
__asm__(
    ".text\n"
    ".globl _unw_getcontext\n"
    ".type _unw_getcontext, @function\n"
    "_unw_getcontext:\n"
    "    movq %rax, 0(%rdi)\n"
    "    movq %rbx, 8(%rdi)\n"
    "    movq %rcx, 16(%rdi)\n"
    "    movq %rdx, 24(%rdi)\n"
    "    movq %rdi, 32(%rdi)\n"
    "    movq %rsi, 40(%rdi)\n"
    "    movq %rbp, 48(%rdi)\n"
    "    leaq 8(%rsp), %rax\n"
    "    movq %rax, 56(%rdi)\n"
    "    movq %r8, 64(%rdi)\n"
    "    movq %r9, 72(%rdi)\n"
    "    movq %r10, 80(%rdi)\n"
    "    movq %r11, 88(%rdi)\n"
    "    movq %r12, 96(%rdi)\n"
    "    movq %r13, 104(%rdi)\n"
    "    movq %r14, 112(%rdi)\n"
    "    movq %r15, 120(%rdi)\n"
    "    movq (%rsp), %rax\n"
    "    movq %rax, 128(%rdi)\n"
    "    xorl %eax, %eax\n"
    "    ret\n"
    ".size _unw_getcontext, . - _unw_getcontext\n");

// int unw_init_local(unw_cursor_t *, unw_context_t *): the cursor at the
// frame unw_getcontext was called from.
int darwin_unw_init_local(uint64_t *cursor, const uint64_t *context) DARWIN_SYMBOL(unw_init_local);
int darwin_unw_init_local(uint64_t *cursor, const uint64_t *context) {
    if (!cursor || !context)
        return UNW_EINVAL;
    cursor[CURSOR_IP] = context[16];
    cursor[CURSOR_SP] = context[7];
    cursor[CURSOR_BP] = context[6];
    cursor[CURSOR_MARK] = CURSOR_MAGIC;
    return UNW_ESUCCESS;
}

// int unw_step(unw_cursor_t *): 1 at the caller's frame, 0 at the end of
// the chain (a frame pointer that is null, unaligned or doesn't go up the
// stack), as at the outermost frame.
int darwin_unw_step(uint64_t *cursor) DARWIN_SYMBOL(unw_step);
int darwin_unw_step(uint64_t *cursor) {
    if (!cursor || cursor[CURSOR_MARK] != CURSOR_MAGIC)
        return UNW_EUNSPEC;
    uint64_t bp = cursor[CURSOR_BP];
    if (!bp || (bp & 7) || bp < cursor[CURSOR_SP] || bp - cursor[CURSOR_SP] > (64u << 20))
        return 0;
    const uint64_t *frame = (const uint64_t *)(uintptr_t)bp;
    uint64_t caller_bp = frame[0], return_address = frame[1];
    if (!return_address)
        return 0;
    cursor[CURSOR_IP] = return_address;
    cursor[CURSOR_SP] = bp + 16;
    cursor[CURSOR_BP] = caller_bp;
    return 1;
}

// int unw_get_reg(unw_cursor_t *, unw_regnum_t, unw_word_t *): the frame's
// instruction, stack and frame pointers; other registers aren't tracked.
int darwin_unw_get_reg(const uint64_t *cursor, int reg, uint64_t *value) DARWIN_SYMBOL(unw_get_reg);
int darwin_unw_get_reg(const uint64_t *cursor, int reg, uint64_t *value) {
    if (!cursor || !value || cursor[CURSOR_MARK] != CURSOR_MAGIC)
        return UNW_EUNSPEC;
    switch (reg) {
    case UNW_REG_IP: *value = cursor[CURSOR_IP]; return UNW_ESUCCESS;
    case UNW_REG_SP: case UNW_X86_64_RSP: *value = cursor[CURSOR_SP]; return UNW_ESUCCESS;
    case UNW_X86_64_RBP: *value = cursor[CURSOR_BP]; return UNW_ESUCCESS;
    default: return UNW_EBADREG;
    }
}

#endif
