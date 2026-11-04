// Assertions, signals, sysctl, interface addresses and memory helpers that
// Darwin's libSystem has and glibc lacks or defines differently. Signal
// handlers get Darwin's signal frames.

#define _GNU_SOURCE
#include "PerrySystem.h"

#include <errno.h>
#include <math.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/auxv.h>
#include <ucontext.h>
#include <unistd.h>

// MARK: - Assertions

// assert() on Darwin calls __assert_rtn(function, file, line, expression).
_Noreturn void darwin_assert_rtn(const char *function, const char *file, int line, const char *expression)
    DARWIN_SYMBOL(__assert_rtn);
_Noreturn void darwin_assert_rtn(const char *function, const char *file, int line, const char *expression) {
    fflush(stdout);
    if (function)
        fprintf(stderr, "Assertion failed: (%s), function %s, file %s, line %d.\n", expression, function, file, line);
    else
        fprintf(stderr, "Assertion failed: (%s), file %s, line %d.\n", expression, file, line);
    abort();
}

// MARK: - Memory

// realloc that frees the block when it cannot grow it.
void *darwin_reallocf(void *pointer, size_t size) DARWIN_SYMBOL(reallocf);
void *darwin_reallocf(void *pointer, size_t size) {
    void *resized = realloc(pointer, size);
    if (!resized && size)
        free(pointer);
    return resized;
}

// Fills `length` bytes with a repeated 16-byte pattern; a partial copy of it at the end.
void darwin_memset_pattern16(void *bytes, const void *pattern, size_t length) DARWIN_SYMBOL(memset_pattern16);
void darwin_memset_pattern16(void *bytes, const void *pattern, size_t length) {
    uint8_t *out = bytes;
    while (length >= 16) {
        memcpy(out, pattern, 16);
        out += 16;
        length -= 16;
    }
    memcpy(out, pattern, length);
}

// C11's memset that the compiler may not drop: sets min(count, size)
// bytes, and fails when count exceeds the destination.
int darwin_memset_s(void *bytes, size_t size, int value, size_t count) DARWIN_SYMBOL(memset_s);
int darwin_memset_s(void *bytes, size_t size, int value, size_t count) {
    if (!bytes)
        return EINVAL;
    volatile uint8_t *out = bytes;
    for (size_t i = 0; i < (count < size ? count : size); i++)
        out[i] = (uint8_t)value;
    return count > size ? 84 /* Darwin EOVERFLOW */ : 0;
}

void darwin_memset_pattern8(void *bytes, const void *pattern, size_t length) DARWIN_SYMBOL(memset_pattern8);
void darwin_memset_pattern8(void *bytes, const void *pattern, size_t length) {
    uint8_t *out = bytes;
    while (length >= 8) {
        memcpy(out, pattern, 8);
        out += 8;
        length -= 8;
    }
    memcpy(out, pattern, length);
}

void darwin_memset_pattern4(void *bytes, const void *pattern, size_t length) DARWIN_SYMBOL(memset_pattern4);
void darwin_memset_pattern4(void *bytes, const void *pattern, size_t length) {
    uint8_t *out = bytes;
    while (length >= 4) {
        memcpy(out, pattern, 4);
        out += 4;
        length -= 4;
    }
    memcpy(out, pattern, length);
}

// MARK: - Floating point

// fpclassify's out-of-line forms, in Darwin's numbering: FP_NAN 1,
// FP_INFINITE 2, FP_ZERO 3, FP_NORMAL 4, FP_SUBNORMAL 5.
static int darwin_fp_class(int linux_class) {
    switch (linux_class) {
    case FP_NAN: return 1;
    case FP_INFINITE: return 2;
    case FP_ZERO: return 3;
    case FP_SUBNORMAL: return 5;
    default: return 4;
    }
}

int darwin_fpclassifyd(double x) DARWIN_SYMBOL(__fpclassifyd);
int darwin_fpclassifyd(double x) { return darwin_fp_class(fpclassify(x)); }

int darwin_fpclassifyf(float x) DARWIN_SYMBOL(__fpclassifyf);
int darwin_fpclassifyf(float x) { return darwin_fp_class(fpclassify(x)); }

// MARK: - Credentials

// Whether the process runs with privileges it was not started with.
int darwin_issetugid(void) DARWIN_SYMBOL(issetugid);
int darwin_issetugid(void) { return getauxval(AT_SECURE) != 0; }

// MARK: - Signals

typedef struct darwin_sigaction {
    void *handler;
    uint32_t mask;
    int flags;
} darwin_sigaction;

enum {
    DARWIN_SA_ONSTACK = 0x1, DARWIN_SA_RESTART = 0x2, DARWIN_SA_RESETHAND = 0x4, DARWIN_SA_NODEFER = 0x10,
    DARWIN_SA_SIGINFO = 0x40,
};

// Darwin's arm64 signal frame: siginfo_t, ucontext_t and the machine
// context it points to.
// (Fields named without si_, which glibc defines as macros.)
typedef struct {
    int signo, error, code;
    pid_t pid;
    uid_t uid;
    int status;
    void *address;
    void *value;
    long band;
    unsigned long pad[7];
} darwin_siginfo;

typedef struct {
    struct { uint64_t far; uint32_t esr, exception; } es;
    struct { uint64_t x[29], fp, lr, sp, pc; uint32_t cpsr, pad; } ss;
    struct { __uint128_t v[32]; uint32_t fpsr, fpcr; } __attribute__((aligned(16))) ns;
} darwin_mcontext;

typedef struct {
    int uc_onstack;
    uint32_t uc_sigmask;
    struct { void *ss_sp; size_t ss_size; int ss_flags; } uc_stack;
    void *uc_link;
    size_t uc_mcsize;
    darwin_mcontext *uc_mcontext;
} darwin_ucontext;

// The apps' handlers, by Linux signal number.
static darwin_sigaction handlers[65];

static struct fpsimd_context *fpsimd(ucontext_t *context) {
    struct _aarch64_ctx *header = (struct _aarch64_ctx *)context->uc_mcontext.__reserved;
    while (header->magic) {
        if (header->magic == FPSIMD_MAGIC)
            return (struct fpsimd_context *)header;
        header = (struct _aarch64_ctx *)((char *)header + header->size);
    }
    return NULL;
}

// Calls the app's handler with Darwin's signal frame, made from Linux's,
// then copies back the registers it changed: runtimes such as Mono turn
// a fault into an exception by sending the thread elsewhere.
static void deliver(int linux_signal, siginfo_t *info, void *raw_context) {
    darwin_sigaction action = handlers[linux_signal];
    int darwin_signal = 0;
    for (int candidate = 1; candidate <= 31; candidate++)
        if (perry_signal_to_linux(candidate) == linux_signal)
            darwin_signal = candidate;
    if (!(action.flags & DARWIN_SA_SIGINFO)) {
        ((void (*)(int))action.handler)(darwin_signal);
        return;
    }
    ucontext_t *context = raw_context;
    mcontext_t *machine = &context->uc_mcontext;
    darwin_siginfo darwin_info;
    memset(&darwin_info, 0, sizeof(darwin_info));
    darwin_info.signo = darwin_signal;
    darwin_info.error = info->si_errno;
    darwin_info.code = info->si_code;
    darwin_info.pid = info->si_pid;
    darwin_info.uid = info->si_uid;
    darwin_info.address = info->si_addr;
    darwin_mcontext darwin_machine;
    memset(&darwin_machine, 0, sizeof(darwin_machine));
    darwin_machine.es.far = machine->fault_address;
    memcpy(darwin_machine.ss.x, machine->regs, sizeof(darwin_machine.ss.x));
    darwin_machine.ss.fp = machine->regs[29];
    darwin_machine.ss.lr = machine->regs[30];
    darwin_machine.ss.sp = machine->sp;
    darwin_machine.ss.pc = machine->pc;
    darwin_machine.ss.cpsr = (uint32_t)machine->pstate;
    struct fpsimd_context *neon = fpsimd(context);
    if (neon) {
        memcpy(darwin_machine.ns.v, neon->vregs, sizeof(darwin_machine.ns.v));
        darwin_machine.ns.fpsr = neon->fpsr;
        darwin_machine.ns.fpcr = neon->fpcr;
    }
    darwin_ucontext darwin_context;
    memset(&darwin_context, 0, sizeof(darwin_context));
    darwin_context.uc_mcsize = sizeof(darwin_machine);
    darwin_context.uc_mcontext = &darwin_machine;
    ((void (*)(int, darwin_siginfo *, darwin_ucontext *))action.handler)(darwin_signal, &darwin_info, &darwin_context);
    memcpy(machine->regs, darwin_machine.ss.x, sizeof(darwin_machine.ss.x));
    machine->regs[29] = darwin_machine.ss.fp;
    machine->regs[30] = darwin_machine.ss.lr;
    machine->sp = darwin_machine.ss.sp;
    machine->pc = darwin_machine.ss.pc;
    if (neon) {
        memcpy(neon->vregs, darwin_machine.ns.v, sizeof(darwin_machine.ns.v));
        neon->fpsr = darwin_machine.ns.fpsr;
        neon->fpcr = darwin_machine.ns.fpcr;
    }
}

// An app's handler is installed behind a translation of the signal frame.
int darwin_sigaction_function(int signal, const darwin_sigaction *action, darwin_sigaction *previous) DARWIN_SYMBOL(sigaction);
int darwin_sigaction_function(int signal, const darwin_sigaction *action, darwin_sigaction *previous) {
    int linux_signal = perry_signal_to_linux(signal);
    if (linux_signal <= 0) {
        errno = EINVAL;
        return -1;
    }
    if (previous)
        *previous = handlers[linux_signal];
    if (!action)
        return 0;
    // PERRY_KEEP_CRASH_HANDLERS keeps the crash signals' handlers Perry
    // started with, so a crash reporter in the app does not hide where a
    // crash happened: the app's handler is recorded but not installed.
    static int keep = -1;
    if (keep < 0)
        keep = getenv("PERRY_KEEP_CRASH_HANDLERS") != NULL;
    if (keep && (linux_signal == SIGSEGV || linux_signal == SIGBUS || linux_signal == SIGILL ||
                 linux_signal == SIGABRT || linux_signal == SIGTRAP || linux_signal == SIGFPE)) {
        handlers[linux_signal] = *action;
        return 0;
    }
    struct sigaction linux_action;
    memset(&linux_action, 0, sizeof(linux_action));
    for (int darwin = 1; darwin <= 31; darwin++)
        if (action->mask & (1u << (darwin - 1)) && perry_signal_to_linux(darwin) > 0)
            sigaddset(&linux_action.sa_mask, perry_signal_to_linux(darwin));
    if (action->handler == (void *)SIG_IGN || action->handler == (void *)SIG_DFL) {
        linux_action.sa_handler = (void (*)(int))action->handler;
    } else {
        linux_action.sa_sigaction = deliver;
        linux_action.sa_flags = SA_SIGINFO;
    }
    if (action->flags & DARWIN_SA_ONSTACK) linux_action.sa_flags |= SA_ONSTACK;
    if (action->flags & DARWIN_SA_RESTART) linux_action.sa_flags |= SA_RESTART;
    if (action->flags & DARWIN_SA_NODEFER) linux_action.sa_flags |= SA_NODEFER;
    if (action->flags & DARWIN_SA_RESETHAND) linux_action.sa_flags |= SA_RESETHAND;
    handlers[linux_signal] = *action;
    return sigaction(linux_signal, &linux_action, NULL);
}

// MARK: - sysctl

static int sysctl_value(void *old, size_t *old_length, const void *value, size_t length) {
    if (!old_length) {
        errno = EINVAL;
        return -1;
    }
    if (old) {
        if (*old_length < length) {
            *old_length = length;
            errno = ENOMEM;
            return -1;
        }
        memcpy(old, value, length);
    }
    *old_length = length;
    return 0;
}

static int sysctl_string(void *old, size_t *old_length, const char *value) {
    return sysctl_value(old, old_length, value, strlen(value) + 1);
}

// The names apps read to identify the device: an iPhone 14 running iOS 15,
// as UIDevice reports, with this machine's processors and memory.
int darwin_sysctlbyname(const char *name, void *old, size_t *old_length, const void *new_value, size_t new_length)
    DARWIN_SYMBOL(sysctlbyname);
int darwin_sysctlbyname(const char *name, void *old, size_t *old_length, const void *new_value, size_t new_length) {
    (void)new_value;
    (void)new_length;
    if (!name) {
        errno = EINVAL;
        return -1;
    }
    if (strcmp(name, "hw.machine") == 0)
        return sysctl_string(old, old_length, "iPhone14,7");
    if (strcmp(name, "hw.model") == 0)
        return sysctl_string(old, old_length, "D27AP");
    if (strcmp(name, "kern.ostype") == 0)
        return sysctl_string(old, old_length, "Darwin");
    if (strcmp(name, "kern.osrelease") == 0)
        return sysctl_string(old, old_length, "21.0.0");
    if (strcmp(name, "kern.osversion") == 0)
        return sysctl_string(old, old_length, "19A346");
    if (strcmp(name, "kern.hostname") == 0) {
        char host[256] = "localhost";
        gethostname(host, sizeof(host) - 1);
        return sysctl_string(old, old_length, host);
    }
    if (strcmp(name, "hw.ncpu") == 0 || strcmp(name, "hw.activecpu") == 0 || strcmp(name, "hw.physicalcpu") == 0 ||
        strcmp(name, "hw.logicalcpu") == 0 || strcmp(name, "hw.physicalcpu_max") == 0 ||
        strcmp(name, "hw.logicalcpu_max") == 0) {
        int32_t count = (int32_t)sysconf(_SC_NPROCESSORS_ONLN);
        return sysctl_value(old, old_length, &count, sizeof(count));
    }
    if (strcmp(name, "hw.memsize") == 0 || strcmp(name, "hw.physmem") == 0) {
        uint64_t bytes = (uint64_t)sysconf(_SC_PHYS_PAGES) * (uint64_t)sysconf(_SC_PAGESIZE);
        if (strcmp(name, "hw.physmem") == 0) {
            uint32_t clamped = bytes > UINT32_MAX ? UINT32_MAX : (uint32_t)bytes;
            return sysctl_value(old, old_length, &clamped, sizeof(clamped));
        }
        return sysctl_value(old, old_length, &bytes, sizeof(bytes));
    }
    if (strcmp(name, "hw.pagesize") == 0) {
        int64_t size = 16384;
        return sysctl_value(old, old_length, &size, sizeof(size));
    }
    if (strcmp(name, "hw.cpufrequency") == 0 || strcmp(name, "hw.cpufrequency_max") == 0) {
        uint64_t hertz = 3230000000u;
        return sysctl_value(old, old_length, &hertz, sizeof(hertz));
    }
    errno = ENOENT;
    return -1;
}

// MARK: - Interface addresses

// No interfaces are listed: Darwin's sockaddrs differ from Linux's (they
// begin with a length byte), and apps read them for analytics.
int darwin_getifaddrs(void **list) DARWIN_SYMBOL(getifaddrs);
int darwin_getifaddrs(void **list) {
    if (list)
        *list = NULL;
    return 0;
}

void darwin_freeifaddrs(void *list) DARWIN_SYMBOL(freeifaddrs);
void darwin_freeifaddrs(void *list) { (void)list; }
