#ifndef PERRY_CONTEXT_H
#define PERRY_CONTEXT_H

// Darwin's machine states of a thread, as signal handlers (a ucontext's
// machine context) and thread_get_state see them, and their conversion from
// and to a Linux signal context. arm64: x0-x28, fp, lr, sp, pc and cpsr; the
// NEON registers; the fault address. armv7: r0-r12, sp, lr, pc and cpsr; the
// VFP registers; the exception, the fault status and address. x86_64: the
// general registers, rip, rflags and segments; the FXSAVE area; the trap,
// its error code and the fault address.

#include <signal.h>
#include <stdint.h>
#include <string.h>
#include <ucontext.h>

#if defined(__aarch64__)

#include <asm/sigcontext.h>

typedef struct { uint64_t x[29], fp, lr, sp, pc; uint32_t cpsr, pad; } darwin_thread_state;
typedef struct { __uint128_t v[32]; uint32_t fpsr, fpcr; } __attribute__((aligned(16))) darwin_float_state;
typedef struct { uint64_t far; uint32_t esr, exception; } darwin_exception_state;

// thread_get_state's flavors: ARM_THREAD_STATE64, ARM_NEON_STATE64 and
// ARM_EXCEPTION_STATE64.
enum { DARWIN_THREAD_FLAVOR = 6, DARWIN_FLOAT_FLAVOR = 17, DARWIN_EXCEPTION_FLAVOR = 7 };

static inline struct fpsimd_context *perry_context_neon(ucontext_t *context) {
    struct _aarch64_ctx *header = (struct _aarch64_ctx *)context->uc_mcontext.__reserved;
    while (header->magic) {
        if (header->magic == FPSIMD_MAGIC)
            return (struct fpsimd_context *)header;
        header = (struct _aarch64_ctx *)((char *)header + header->size);
    }
    return NULL;
}

static inline void perry_context_get_thread(const ucontext_t *context, darwin_thread_state *out) {
    const mcontext_t *machine = &context->uc_mcontext;
    memcpy(out->x, machine->regs, sizeof(out->x));
    out->fp = machine->regs[29];
    out->lr = machine->regs[30];
    out->sp = machine->sp;
    out->pc = machine->pc;
    out->cpsr = (uint32_t)machine->pstate;
    out->pad = 0;
}

static inline void perry_context_set_thread(ucontext_t *context, const darwin_thread_state *in) {
    mcontext_t *machine = &context->uc_mcontext;
    memcpy(machine->regs, in->x, sizeof(in->x));
    machine->regs[29] = in->fp;
    machine->regs[30] = in->lr;
    machine->sp = in->sp;
    machine->pc = in->pc;
}

static inline void perry_context_get_float(ucontext_t *context, darwin_float_state *out) {
    struct fpsimd_context *neon = perry_context_neon(context);
    memset(out, 0, sizeof(*out));
    if (neon) {
        memcpy(out->v, neon->vregs, sizeof(out->v));
        out->fpsr = neon->fpsr;
        out->fpcr = neon->fpcr;
    }
}

static inline void perry_context_set_float(ucontext_t *context, const darwin_float_state *in) {
    struct fpsimd_context *neon = perry_context_neon(context);
    if (neon) {
        memcpy(neon->vregs, in->v, sizeof(in->v));
        neon->fpsr = in->fpsr;
        neon->fpcr = in->fpcr;
    }
}

static inline void perry_context_get_exception(const ucontext_t *context, darwin_exception_state *out) {
    out->far = context->uc_mcontext.fault_address;
    out->esr = 0;
    out->exception = 0;
}

#elif defined(__arm__)

typedef struct { uint32_t r[13], sp, lr, pc, cpsr; } darwin_thread_state;
typedef struct { uint32_t r[64], fpscr; } darwin_float_state;
typedef struct { uint32_t exception, fsr, far; } darwin_exception_state;

// ARM_THREAD_STATE (ARM_THREAD_STATE32, 9, is the same), ARM_VFP_STATE and
// ARM_EXCEPTION_STATE.
enum { DARWIN_THREAD_FLAVOR = 1, DARWIN_FLOAT_FLAVOR = 2, DARWIN_EXCEPTION_FLAVOR = 3 };

// The VFP registers Linux saves in uc_regspace, after a magic word and the
// record's size (arch/arm/include/asm/ucontext.h).
struct perry_vfp_sigframe {
    uint32_t magic, size;
    uint64_t fpregs[32];
    uint32_t fpscr;
};

enum { PERRY_VFP_MAGIC = 0x56465001 };

static inline struct perry_vfp_sigframe *perry_context_vfp(ucontext_t *context) {
    char *record = (char *)context->uc_regspace;
    char *end = record + sizeof(context->uc_regspace);
    while (record + 8 <= end) {
        uint32_t magic, size;
        memcpy(&magic, record, 4);
        memcpy(&size, record + 4, 4);
        if (magic == PERRY_VFP_MAGIC)
            return (struct perry_vfp_sigframe *)record;
        if (!magic || size < 8)
            break;
        record += size;
    }
    return NULL;
}

static inline void perry_context_get_thread(const ucontext_t *context, darwin_thread_state *out) {
    const mcontext_t *machine = &context->uc_mcontext;
    const unsigned long r[13] = {
        machine->arm_r0, machine->arm_r1, machine->arm_r2, machine->arm_r3, machine->arm_r4, machine->arm_r5,
        machine->arm_r6, machine->arm_r7, machine->arm_r8, machine->arm_r9, machine->arm_r10, machine->arm_fp,
        machine->arm_ip,
    };
    for (int i = 0; i < 13; i++)
        out->r[i] = (uint32_t)r[i];
    out->sp = machine->arm_sp;
    out->lr = machine->arm_lr;
    out->pc = machine->arm_pc;
    out->cpsr = machine->arm_cpsr;
}

static inline void perry_context_set_thread(ucontext_t *context, const darwin_thread_state *in) {
    mcontext_t *machine = &context->uc_mcontext;
    unsigned long *r[13] = {
        &machine->arm_r0, &machine->arm_r1, &machine->arm_r2, &machine->arm_r3, &machine->arm_r4, &machine->arm_r5,
        &machine->arm_r6, &machine->arm_r7, &machine->arm_r8, &machine->arm_r9, &machine->arm_r10, &machine->arm_fp,
        &machine->arm_ip,
    };
    for (int i = 0; i < 13; i++)
        *r[i] = in->r[i];
    machine->arm_sp = in->sp;
    machine->arm_lr = in->lr;
    machine->arm_pc = in->pc;
    // The Thumb bit says which state the thread resumes in.
    machine->arm_cpsr = (machine->arm_cpsr & ~0x20UL) | (in->cpsr & 0x20);
}

static inline void perry_context_get_float(ucontext_t *context, darwin_float_state *out) {
    struct perry_vfp_sigframe *vfp = perry_context_vfp(context);
    memset(out, 0, sizeof(*out));
    if (vfp) {
        memcpy(out->r, vfp->fpregs, sizeof(vfp->fpregs));
        out->fpscr = vfp->fpscr;
    }
}

static inline void perry_context_set_float(ucontext_t *context, const darwin_float_state *in) {
    struct perry_vfp_sigframe *vfp = perry_context_vfp(context);
    if (vfp) {
        memcpy(vfp->fpregs, in->r, sizeof(vfp->fpregs));
        vfp->fpscr = in->fpscr;
    }
}

static inline void perry_context_get_exception(const ucontext_t *context, darwin_exception_state *out) {
    out->exception = (uint32_t)context->uc_mcontext.trap_no;
    out->fsr = (uint32_t)context->uc_mcontext.error_code;
    out->far = (uint32_t)context->uc_mcontext.fault_address;
}

#elif defined(__i386__)

typedef struct {
    uint32_t eax, ebx, ecx, edx, edi, esi, ebp, esp, ss, eflags, eip, cs, ds, es, fs, gs;
} darwin_thread_state;
// The FXSAVE area between Darwin's padding, which Linux's context does not
// hold in that form on i386: signal handlers read zeros, and writes are lost.
typedef struct { uint32_t reserved[2]; uint8_t fxsave[512]; uint32_t reserved1; } darwin_float_state;
typedef struct { uint16_t trapno, cpu; uint32_t err, faultvaddr; } darwin_exception_state;

// x86_THREAD_STATE32, x86_FLOAT_STATE32 and x86_EXCEPTION_STATE32.
enum { DARWIN_THREAD_FLAVOR = 1, DARWIN_FLOAT_FLAVOR = 2, DARWIN_EXCEPTION_FLAVOR = 3 };

static inline void perry_context_get_thread(const ucontext_t *context, darwin_thread_state *out) {
    const greg_t *r = context->uc_mcontext.gregs;
    *out = (darwin_thread_state){
        r[REG_EAX], r[REG_EBX], r[REG_ECX], r[REG_EDX], r[REG_EDI], r[REG_ESI], r[REG_EBP], r[REG_ESP],
        r[REG_SS], r[REG_EFL], r[REG_EIP], r[REG_CS], r[REG_DS], r[REG_ES], r[REG_FS], r[REG_GS],
    };
}

static inline void perry_context_set_thread(ucontext_t *context, const darwin_thread_state *in) {
    greg_t *r = context->uc_mcontext.gregs;
    r[REG_EAX] = in->eax; r[REG_EBX] = in->ebx; r[REG_ECX] = in->ecx; r[REG_EDX] = in->edx;
    r[REG_EDI] = in->edi; r[REG_ESI] = in->esi; r[REG_EBP] = in->ebp; r[REG_ESP] = in->esp;
    r[REG_EIP] = in->eip; r[REG_EFL] = in->eflags;
}

static inline void perry_context_get_float(ucontext_t *context, darwin_float_state *out) {
    (void)context;
    memset(out, 0, sizeof(*out));
}

static inline void perry_context_set_float(ucontext_t *context, const darwin_float_state *in) {
    (void)context;
    (void)in;
}

static inline void perry_context_get_exception(const ucontext_t *context, darwin_exception_state *out) {
    const greg_t *r = context->uc_mcontext.gregs;
    out->trapno = (uint16_t)r[REG_TRAPNO];
    out->cpu = 0;
    out->err = (uint32_t)r[REG_ERR];
    out->faultvaddr = (uint32_t)context->uc_mcontext.cr2;
}

#elif defined(__x86_64__)

typedef struct {
    uint64_t rax, rbx, rcx, rdx, rdi, rsi, rbp, rsp, r8, r9, r10, r11, r12, r13, r14, r15, rip, rflags, cs, fs, gs;
} darwin_thread_state;
// The FXSAVE area, which is Linux's _libc_fpstate, between Darwin's padding.
typedef struct { uint32_t reserved[2]; uint8_t fxsave[512]; uint32_t reserved1; } darwin_float_state;
typedef struct { uint16_t trapno, cpu; uint32_t err; uint64_t faultvaddr; } darwin_exception_state;

// x86_THREAD_STATE64, x86_FLOAT_STATE64 and x86_EXCEPTION_STATE64.
enum { DARWIN_THREAD_FLAVOR = 4, DARWIN_FLOAT_FLAVOR = 5, DARWIN_EXCEPTION_FLAVOR = 6 };

static inline void perry_context_get_thread(const ucontext_t *context, darwin_thread_state *out) {
    const greg_t *r = context->uc_mcontext.gregs;
    *out = (darwin_thread_state){
        r[REG_RAX], r[REG_RBX], r[REG_RCX], r[REG_RDX], r[REG_RDI], r[REG_RSI], r[REG_RBP], r[REG_RSP],
        r[REG_R8], r[REG_R9], r[REG_R10], r[REG_R11], r[REG_R12], r[REG_R13], r[REG_R14], r[REG_R15],
        r[REG_RIP], r[REG_EFL],
        // REG_CSGSFS holds cs, gs and fs, 16 bits each from the bottom.
        (uint64_t)r[REG_CSGSFS] & 0xffff, ((uint64_t)r[REG_CSGSFS] >> 32) & 0xffff, ((uint64_t)r[REG_CSGSFS] >> 16) & 0xffff,
    };
}

static inline void perry_context_set_thread(ucontext_t *context, const darwin_thread_state *in) {
    greg_t *r = context->uc_mcontext.gregs;
    r[REG_RAX] = in->rax; r[REG_RBX] = in->rbx; r[REG_RCX] = in->rcx; r[REG_RDX] = in->rdx;
    r[REG_RDI] = in->rdi; r[REG_RSI] = in->rsi; r[REG_RBP] = in->rbp; r[REG_RSP] = in->rsp;
    r[REG_R8] = in->r8; r[REG_R9] = in->r9; r[REG_R10] = in->r10; r[REG_R11] = in->r11;
    r[REG_R12] = in->r12; r[REG_R13] = in->r13; r[REG_R14] = in->r14; r[REG_R15] = in->r15;
    r[REG_RIP] = in->rip;
    r[REG_EFL] = in->rflags;
}

static inline void perry_context_get_float(ucontext_t *context, darwin_float_state *out) {
    memset(out, 0, sizeof(*out));
    if (context->uc_mcontext.fpregs)
        memcpy(out->fxsave, context->uc_mcontext.fpregs, sizeof(out->fxsave));
}

static inline void perry_context_set_float(ucontext_t *context, const darwin_float_state *in) {
    if (context->uc_mcontext.fpregs)
        memcpy(context->uc_mcontext.fpregs, in->fxsave, sizeof(in->fxsave));
}

static inline void perry_context_get_exception(const ucontext_t *context, darwin_exception_state *out) {
    const greg_t *r = context->uc_mcontext.gregs;
    out->trapno = (uint16_t)r[REG_TRAPNO];
    out->cpu = 0;
    out->err = (uint32_t)r[REG_ERR];
    out->faultvaddr = (uint64_t)r[REG_CR2];
}

#endif

enum {
    DARWIN_THREAD_COUNT = sizeof(darwin_thread_state) / 4,
    DARWIN_FLOAT_COUNT = sizeof(darwin_float_state) / 4,
    DARWIN_EXCEPTION_COUNT = sizeof(darwin_exception_state) / 4,
};

#endif
