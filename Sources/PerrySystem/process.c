// Assertions, signals, sysctl, interface addresses and memory helpers that
// Darwin's libSystem has and glibc lacks or defines differently. Signal
// handlers get Darwin's signal frames.

#define _GNU_SOURCE
#include "PerrySystem.h"
#include "PerryContext.h"

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

void *darwin_realloc(void *ptr, size_t size) DARWIN_SYMBOL(realloc);

// realloc that frees the block when it cannot grow it.
void *darwin_reallocf(void *pointer, size_t size) DARWIN_SYMBOL(reallocf);
void *darwin_reallocf(void *pointer, size_t size) {
    void *resized = darwin_realloc(pointer, size);
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

DARWIN_FLOAT_ABI int darwin_fpclassifyd(double x) DARWIN_SYMBOL(__fpclassifyd);
int darwin_fpclassifyd(double x) { return darwin_fp_class(fpclassify(x)); }

DARWIN_FLOAT_ABI int darwin_fpclassifyf(float x) DARWIN_SYMBOL(__fpclassifyf);
int darwin_fpclassifyf(float x) { return darwin_fp_class(fpclassify(x)); }

// MARK: - Credentials

// Whether the process runs with privileges it was not started with.
int darwin_issetugid(void) DARWIN_SYMBOL(issetugid);
int darwin_issetugid(void) { return getauxval(AT_SECURE) != 0; }

// csops(pid, ops, buffer, size), the code signing status Darwin keeps for a
// process, which Swift's runtime reads at startup. CS_OPS_STATUS (0)
// reports a valid signature that allows debugging (CS_VALID |
// CS_GET_TASK_ALLOW), as for an app built for development; other
// operations fail.
int darwin_csops(int pid, unsigned int ops, void *buffer, size_t size) DARWIN_SYMBOL(csops);
int darwin_csops(int pid, unsigned int ops, void *buffer, size_t size) {
    (void)pid;
    if (ops == 0 && buffer && size >= sizeof(uint32_t)) {
        memset(buffer, 0, size);
        *(uint32_t *)buffer = 0x1 | 0x4;
        return 0;
    }
    errno = EINVAL;
    return -1;
}

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

// Darwin's signal frame: siginfo_t, ucontext_t and the machine context it
// points to (PerryContext.h's states, for arm64 or armv7).
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
    darwin_exception_state es;
    darwin_thread_state ss;
    darwin_float_state fs;
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
    perry_context_get_exception(context, &darwin_machine.es);
    perry_context_get_thread(context, &darwin_machine.ss);
    perry_context_get_float(context, &darwin_machine.fs);
    darwin_ucontext darwin_context;
    memset(&darwin_context, 0, sizeof(darwin_context));
    darwin_context.uc_mcsize = sizeof(darwin_machine);
    darwin_context.uc_mcontext = &darwin_machine;
    ((void (*)(int, darwin_siginfo *, darwin_ucontext *))action.handler)(darwin_signal, &darwin_info, &darwin_context);
    perry_context_set_thread(context, &darwin_machine.ss);
    perry_context_set_float(context, &darwin_machine.fs);
}

// MARK: - Instructions the core lacks

#if defined(__aarch64__)
// Perry owns SIGILL: an instruction Apple silicon has and this core lacks
// is rewritten the first time it runs (isa.c), and runs again; every other
// SIGILL goes to the app's handler, or to the handler before Perry's (the
// crash reporter), or the default.
int perry_isa_rewrite(void *context);

static struct sigaction previous_illegal;
static int illegal_kept;

static void illegal_instruction(int linux_signal, siginfo_t *info, void *raw_context) {
    // PERRY_ISA_TRACE names each instruction rewritten.
    if (getenv("PERRY_ISA_TRACE")) {
        char line[160];
        int n = snprintf(line, sizeof(line), "perry: SIGILL at %p: %08x\n", (void *)((ucontext_t *)raw_context)->uc_mcontext.pc,
                         *(const uint32_t *)((ucontext_t *)raw_context)->uc_mcontext.pc);
        write(2, line, (size_t)n);
    }
    if (perry_isa_rewrite(raw_context))
        return;
    void *app = handlers[SIGILL].handler;
    if (!illegal_kept && app && app != (void *)SIG_DFL && app != (void *)SIG_IGN) {
        deliver(linux_signal, info, raw_context);
        return;
    }
    if (app == (void *)SIG_IGN && !illegal_kept)
        return;
    if (previous_illegal.sa_flags & SA_SIGINFO) {
        previous_illegal.sa_sigaction(linux_signal, info, raw_context);
        return;
    }
    if (previous_illegal.sa_handler != SIG_DFL && previous_illegal.sa_handler != SIG_IGN) {
        previous_illegal.sa_handler(linux_signal);
        return;
    }
    // The default: the instruction runs again, and the process ends.
    signal(SIGILL, SIG_DFL);
}

__attribute__((constructor)) static void own_illegal_instruction(void) {
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_sigaction = illegal_instruction;
    action.sa_flags = SA_SIGINFO | SA_ONSTACK | SA_NODEFER;
    sigemptyset(&action.sa_mask);
    sigaction(SIGILL, &action, &previous_illegal);
}
#endif

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
    // crash happened: the app's handler is recorded but not installed. Its
    // value may name the signals kept (segv,bus,ill,abrt,trap,fpe), leaving
    // the others to the app, as OpenSSL needs SIGILL to probe the CPU;
    // otherwise all of them are kept.
    static int kept = -1;
    if (kept < 0) {
        kept = 0;
        const char *setting = getenv("PERRY_KEEP_CRASH_HANDLERS");
        if (setting) {
            static const struct { const char *name; int signal; } names[] = {
                { "segv", SIGSEGV }, { "bus", SIGBUS }, { "ill", SIGILL }, { "abrt", SIGABRT }, { "trap", SIGTRAP }, { "fpe", SIGFPE },
            };
            for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++)
                if (strstr(setting, names[i].name))
                    kept |= 1 << names[i].signal;
            if (!kept)
                for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++)
                    kept |= 1 << names[i].signal;
        }
    }
    if (kept & (1 << linux_signal)) {
        handlers[linux_signal] = *action;
#if defined(__aarch64__)
        if (linux_signal == SIGILL)
            illegal_kept = 1;
#endif
        return 0;
    }
#if defined(__aarch64__)
    // Perry's SIGILL handler stays, and calls the app's.
    if (linux_signal == SIGILL) {
        handlers[linux_signal] = *action;
        return 0;
    }
#endif
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

// A macOS program's system, from its LC_BUILD_VERSION: the Darwin release
// of the macOS its SDK is (macOS 26 is Darwin 25, macOS 11 to 15 Darwin
// 20 to 24) and an Apple-silicon Mac, as apps that check the OS read it
// from kern.osrelease. Zero for other programs.
perry_macos_release perry_system_macos_release(void) {
    const uint8_t *header = perry_system_main_header;
    if (!header) return (perry_macos_release){ 0, 0 };
    uint32_t count = *(const uint32_t *)(header + 16);
    // The load commands follow the header: 32 bytes, or 28 in a 32-bit image
    // (MH_MAGIC), which has no reserved word.
    const uint8_t *command = header + (*(const uint32_t *)header == 0xfeedface ? 28 : 32);
    for (uint32_t i = 0; i < count; i++) {
        uint32_t cmd = *(const uint32_t *)command, size = *(const uint32_t *)(command + 4);
        // LC_BUILD_VERSION: platform, minos, sdk (xxxx.yy.zz in nibbles).
        if (cmd == 0x32 && *(const uint32_t *)(command + 8) == 1) {   // PLATFORM_MACOS
            uint32_t sdk = *(const uint32_t *)(command + 16);
            int major = (int)(sdk >> 16), minor = (int)((sdk >> 8) & 0xff);
            return (perry_macos_release){ major >= 26 ? major - 1 : major + 9, minor };
        }
        if (size == 0) break;
        command += size;
    }
    return (perry_macos_release){ 0, 0 };
}

// The names apps read to identify the device: an iPhone 14 running iOS 15,
// as UIDevice reports, or for a macOS program an Apple-silicon Mac running
// the macOS of its SDK; with this machine's processors and memory.
int darwin_sysctlbyname(const char *name, void *old, size_t *old_length, const void *new_value, size_t new_length)
    DARWIN_SYMBOL(sysctlbyname);
int darwin_sysctlbyname(const char *name, void *old, size_t *old_length, const void *new_value, size_t new_length) {
    (void)new_value;
    (void)new_length;
    if (!name) {
        errno = EINVAL;
        return -1;
    }
    perry_macos_release mac = perry_system_macos_release();
    if (strcmp(name, "hw.machine") == 0)
        return sysctl_string(old, old_length, mac.darwin ? "arm64" : PERRY_HW_MACHINE);
    if (strcmp(name, "hw.model") == 0)
        return sysctl_string(old, old_length, mac.darwin ? "Mac14,2" : PERRY_HW_MODEL);
    if (strcmp(name, "kern.ostype") == 0)
        return sysctl_string(old, old_length, "Darwin");
    if (strcmp(name, "kern.osrelease") == 0) {
        if (!mac.darwin) return sysctl_string(old, old_length, "21.0.0");
        char release[16];
        snprintf(release, sizeof(release), "%d.%d.0", mac.darwin, mac.minor);
        return sysctl_string(old, old_length, release);
    }
    if (strcmp(name, "kern.osversion") == 0) {
        if (!mac.darwin) return sysctl_string(old, old_length, "19A346");
        // A build number of that release: its Darwin major, a letter for its
        // minor version, and a build.
        char build[16];
        snprintf(build, sizeof(build), "%d%c100", mac.darwin, 'A' + (mac.minor % 26));
        return sysctl_string(old, old_length, build);
    }
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
        // A 32-bit app keeps the size in 32 bits, often signed, and scales
        // what it loads by it: more than any 32-bit device had (1 GB) would
        // read as little or less than none.
        if (sizeof(void *) == 4 && bytes > (1ull << 30))
            bytes = 1ull << 30;
        if (strcmp(name, "hw.physmem") == 0) {
            uint32_t clamped = bytes > UINT32_MAX ? UINT32_MAX : (uint32_t)bytes;
            return sysctl_value(old, old_length, &clamped, sizeof(clamped));
        }
        return sysctl_value(old, old_length, &bytes, sizeof(bytes));
    }
    if (strcmp(name, "hw.pagesize") == 0) {
        int64_t size = PERRY_PAGE_SIZE;
        return sysctl_value(old, old_length, &size, sizeof(size));
    }
    if (strcmp(name, "hw.cpufrequency") == 0 || strcmp(name, "hw.cpufrequency_max") == 0) {
        uint64_t hertz = PERRY_CPU_FREQUENCY;
        return sysctl_value(old, old_length, &hertz, sizeof(hertz));
    }
    errno = ENOENT;
    return -1;
}

// getifaddrs and freeifaddrs are in sockets.c, with the address conversions.

// MARK: - The host's UUID

// gethostuuid: the machine's ID, /etc/machine-id (or D-Bus's copy of it):
// 32 hexadecimal digits, the UUID's 16 bytes. EINVAL without one.
int darwin_gethostuuid(unsigned char uuid[16], const void *wait) DARWIN_SYMBOL(gethostuuid);
int darwin_gethostuuid(unsigned char uuid[16], const void *wait) {
    (void)wait;
    static const char *const paths[] = { "/etc/machine-id", "/var/lib/dbus/machine-id" };
    for (size_t p = 0; p < sizeof(paths) / sizeof(paths[0]); p++) {
        FILE *file = fopen(paths[p], "r");
        if (!file)
            continue;
        char text[64] = { 0 };
        size_t length = fread(text, 1, sizeof(text) - 1, file);
        fclose(file);
        if (length < 32)
            continue;
        int valid = 1;
        for (int i = 0; i < 16 && valid; i++) {
            unsigned int byte;
            valid = sscanf(text + 2 * i, "%2x", &byte) == 1;
            uuid[i] = (unsigned char)byte;
        }
        if (valid)
            return 0;
    }
    errno = EINVAL;
    return -1;
}
