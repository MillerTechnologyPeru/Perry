// Assertions, signals, sysctl, interface addresses and memory helpers that
// Darwin's libSystem has and glibc lacks or defines differently.

#define _GNU_SOURCE
#include "PerrySystem.h"

#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
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

// MARK: - Signals

// Darwin's numbers for the signals whose Linux numbers differ.
static int signal_to_linux(int signal) {
    switch (signal) {
    case 7: return -1;          // SIGEMT
    case 10: return SIGBUS;
    case 12: return SIGSYS;
    case 16: return SIGURG;
    case 17: return SIGSTOP;
    case 18: return SIGTSTP;
    case 19: return SIGCONT;
    case 20: return SIGCHLD;
    case 23: return SIGIO;
    case 29: return -1;         // SIGINFO
    case 30: return SIGUSR1;
    case 31: return SIGUSR2;
    default: return signal >= 1 && signal <= 31 ? signal : -1;
    }
}

typedef struct darwin_sigaction {
    void *handler;
    uint32_t mask;
    int flags;
} darwin_sigaction;

// Ignoring a signal, or restoring its default, takes effect. Handlers are
// not installed: Darwin apps' handlers are crash reporters, which would
// stand in the way of Perry's own report. The previous action is reported
// as the default.
int darwin_sigaction_function(int signal, const darwin_sigaction *action, darwin_sigaction *previous) DARWIN_SYMBOL(sigaction);
int darwin_sigaction_function(int signal, const darwin_sigaction *action, darwin_sigaction *previous) {
    int linux_signal = signal_to_linux(signal);
    if (linux_signal < 0) {
        errno = EINVAL;
        return -1;
    }
    if (previous)
        memset(previous, 0, sizeof(*previous));
    if (action && (action->handler == (void *)SIG_IGN || action->handler == (void *)SIG_DFL)) {
        struct sigaction linux_action;
        memset(&linux_action, 0, sizeof(linux_action));
        linux_action.sa_handler = (void (*)(int))action->handler;
        return sigaction(linux_signal, &linux_action, NULL);
    }
    return 0;
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
