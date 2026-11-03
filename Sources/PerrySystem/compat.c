// More of libSystem where Darwin's numbering or layouts differ from glibc's:
// signal masks and numbers, locale categories, resource limits, password
// entries, scheduling priorities, sysctl names, ioctl requests; and
// Darwin's own functions (asl_log, OSAtomic, __maskrune); UUIDs, and POSIX
// regular expressions in Darwin's layouts.

#define _GNU_SOURCE
#include "PerrySystem.h"

#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <locale.h>
#include <pthread.h>
#include <pwd.h>
#include <regex.h>
#include <sched.h>
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/resource.h>
#include <unistd.h>

// MARK: - Signals

// Linux's number for a Darwin signal, or -1 where Linux has none.
int perry_signal_to_linux(int signal) {
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
    default: return signal >= 0 && signal <= 31 ? signal : -1;
    }
}

static int signal_to_darwin(int signal) {
    for (int darwin = 1; darwin <= 31; darwin++)
        if (perry_signal_to_linux(darwin) == signal)
            return darwin;
    return -1;
}

// SIG_BLOCK 1, SIG_UNBLOCK 2, SIG_SETMASK 3; a mask is a word, bit n-1 for signal n.
int darwin_sigprocmask(int how, const uint32_t *set, uint32_t *old) DARWIN_SYMBOL(sigprocmask);
int darwin_sigprocmask(int how, const uint32_t *set, uint32_t *old) {
    sigset_t linux_set, linux_old;
    sigemptyset(&linux_set);
    if (set)
        for (int signal = 1; signal <= 31; signal++)
            if (*set & (1u << (signal - 1)) && perry_signal_to_linux(signal) > 0)
                sigaddset(&linux_set, perry_signal_to_linux(signal));
    int linux_how = how == 1 ? SIG_BLOCK : how == 2 ? SIG_UNBLOCK : SIG_SETMASK;
    if (pthread_sigmask(linux_how, set ? &linux_set : NULL, &linux_old) != 0) {
        errno = EINVAL;
        return -1;
    }
    if (old) {
        *old = 0;
        for (int signal = 1; signal < 32; signal++)
            if (sigismember(&linux_old, signal) == 1 && signal_to_darwin(signal) > 0)
                *old |= 1u << (signal_to_darwin(signal) - 1);
    }
    return 0;
}

int darwin_pthread_sigmask(int how, const uint32_t *set, uint32_t *old) DARWIN_SYMBOL(pthread_sigmask);
int darwin_pthread_sigmask(int how, const uint32_t *set, uint32_t *old) {
    return darwin_sigprocmask(how, set, old) == 0 ? 0 : EINVAL;
}

// signal(): sigaction with SA_RESTART, as BSD's has it.
struct darwin_sigaction_struct { void *handler; uint32_t mask; int flags; };
int darwin_sigaction(int signal, const struct darwin_sigaction_struct *action, struct darwin_sigaction_struct *previous)
    __asm__("_sigaction");

void *darwin_signal(int signal, void *handler) DARWIN_SYMBOL(signal);
void *darwin_signal(int number, void *handler) {
    struct darwin_sigaction_struct action = { handler, 0, 0x2 }, previous;
    if (darwin_sigaction(number, &action, &previous) != 0)
        return SIG_ERR;
    return previous.handler;
}

int darwin_raise(int signal) DARWIN_SYMBOL(raise);
int darwin_raise(int signal) {
    int linux_signal = perry_signal_to_linux(signal);
    if (linux_signal < 0) {
        errno = EINVAL;
        return -1;
    }
    return raise(linux_signal);
}

int darwin_kill(pid_t pid, int signal) DARWIN_SYMBOL(kill);
int darwin_kill(pid_t pid, int signal) {
    int linux_signal = perry_signal_to_linux(signal);
    if (linux_signal < 0) {
        errno = EINVAL;
        return -1;
    }
    return kill(pid, linux_signal);
}

int darwin_pthread_kill(pthread_t thread, int signal) DARWIN_SYMBOL(pthread_kill);
int darwin_pthread_kill(pthread_t thread, int signal) {
    int linux_signal = perry_signal_to_linux(signal);
    return linux_signal < 0 ? EINVAL : pthread_kill(thread, linux_signal);
}

// MARK: - Threads

// Darwin gives a stack's top, the address it grows down from.
void *darwin_pthread_get_stackaddr_np(pthread_t thread) DARWIN_SYMBOL(pthread_get_stackaddr_np);
void *darwin_pthread_get_stackaddr_np(pthread_t thread) {
    pthread_attr_t attributes;
    void *bottom = NULL;
    size_t size = 0;
    if (pthread_getattr_np(thread, &attributes) == 0) {
        pthread_attr_getstack(&attributes, &bottom, &size);
        pthread_attr_destroy(&attributes);
    }
    return (char *)bottom + size;
}

size_t darwin_pthread_get_stacksize_np(pthread_t thread) DARWIN_SYMBOL(pthread_get_stacksize_np);
size_t darwin_pthread_get_stacksize_np(pthread_t thread) {
    pthread_attr_t attributes;
    void *bottom = NULL;
    size_t size = 0;
    if (pthread_getattr_np(thread, &attributes) == 0) {
        pthread_attr_getstack(&attributes, &bottom, &size);
        pthread_attr_destroy(&attributes);
    }
    return size;
}

// Darwin's policies (SCHED_OTHER 1, SCHED_RR 2, SCHED_FIFO 4) share its
// priorities, 15 to 47, 31 by default. Threads keep Linux's scheduling.
int darwin_sched_get_priority_min(int policy) DARWIN_SYMBOL(sched_get_priority_min);
int darwin_sched_get_priority_min(int policy) { (void)policy; return 15; }

int darwin_sched_get_priority_max(int policy) DARWIN_SYMBOL(sched_get_priority_max);
int darwin_sched_get_priority_max(int policy) { (void)policy; return 47; }

struct darwin_sched_param { int priority; char opaque[4]; };

int darwin_pthread_getschedparam(pthread_t thread, int *policy, struct darwin_sched_param *param) DARWIN_SYMBOL(pthread_getschedparam);
int darwin_pthread_getschedparam(pthread_t thread, int *policy, struct darwin_sched_param *param) {
    (void)thread;
    if (policy)
        *policy = 1;
    if (param)
        param->priority = 31;
    return 0;
}

int darwin_pthread_setschedparam(pthread_t thread, int policy, const struct darwin_sched_param *param) DARWIN_SYMBOL(pthread_setschedparam);
int darwin_pthread_setschedparam(pthread_t thread, int policy, const struct darwin_sched_param *param) {
    (void)thread; (void)policy; (void)param;
    return 0;
}

// MARK: - Locale

// Darwin: LC_ALL 0, LC_COLLATE 1, LC_CTYPE 2, LC_MONETARY 3, LC_NUMERIC 4, LC_TIME 5, LC_MESSAGES 6.
char *darwin_setlocale(int category, const char *locale) DARWIN_SYMBOL(setlocale);
char *darwin_setlocale(int category, const char *locale) {
    static const int categories[] = { LC_ALL, LC_COLLATE, LC_CTYPE, LC_MONETARY, LC_NUMERIC, LC_TIME, LC_MESSAGES };
    if (category < 0 || category > 6) {
        errno = EINVAL;
        return NULL;
    }
    char *result = setlocale(categories[category], locale);
    // A locale this system lacks is the C locale's, as on a device without it.
    return result ? result : (locale && *locale ? setlocale(categories[category], "C") : NULL);
}

// MARK: - Resources

// Darwin: RLIMIT_AS 5, RLIMIT_MEMLOCK 6, RLIMIT_NPROC 7, RLIMIT_NOFILE 8.
static int resource_to_linux(int resource) {
    switch (resource) {
    case 5: return RLIMIT_AS;
    case 6: return RLIMIT_MEMLOCK;
    case 7: return RLIMIT_NPROC;
    case 8: return RLIMIT_NOFILE;
    default: return resource >= 0 && resource <= 4 ? resource : -1;
    }
}

int darwin_getrlimit(int resource, struct rlimit *limit) DARWIN_SYMBOL(getrlimit);
int darwin_getrlimit(int resource, struct rlimit *limit) {
    int linux_resource = resource_to_linux(resource);
    if (linux_resource < 0) {
        errno = EINVAL;
        return -1;
    }
    return getrlimit(linux_resource, limit);
}

int darwin_setrlimit(int resource, const struct rlimit *limit) DARWIN_SYMBOL(setrlimit);
int darwin_setrlimit(int resource, const struct rlimit *limit) {
    int linux_resource = resource_to_linux(resource);
    if (linux_resource < 0) {
        errno = EINVAL;
        return -1;
    }
    return setrlimit(linux_resource, limit);
}

// MARK: - Users

struct darwin_passwd {
    char *pw_name, *pw_passwd;
    uid_t pw_uid;
    gid_t pw_gid;
    long pw_change;
    char *pw_class, *pw_gecos, *pw_dir, *pw_shell;
    long pw_expire;
};

static struct darwin_passwd *passwd_to_darwin(const struct passwd *entry) {
    static __thread struct darwin_passwd result;
    if (!entry)
        return NULL;
    result = (struct darwin_passwd){ entry->pw_name, entry->pw_passwd, entry->pw_uid, entry->pw_gid, 0, "",
                                     entry->pw_gecos, entry->pw_dir, entry->pw_shell, 0 };
    return &result;
}

struct darwin_passwd *darwin_getpwuid(uid_t uid) DARWIN_SYMBOL(getpwuid);
struct darwin_passwd *darwin_getpwuid(uid_t uid) { return passwd_to_darwin(getpwuid(uid)); }

struct darwin_passwd *darwin_getpwnam(const char *name) DARWIN_SYMBOL(getpwnam);
struct darwin_passwd *darwin_getpwnam(const char *name) { return passwd_to_darwin(getpwnam(name)); }

// MARK: - Strings

// The XSI form, returning an error number.
int darwin_strerror_r(int error, char *buffer, size_t length) DARWIN_SYMBOL(strerror_r);
int darwin_strerror_r(int error, char *buffer, size_t length) {
    const char *message = strerror(perry_linux_errno_from_darwin(error));
    if (!buffer || length == 0)
        return ERANGE;
    snprintf(buffer, length, "%s", message);
    return strlen(message) < length ? 0 : ERANGE;
}

// Darwin's ctype: a character's class bits, from _DefaultRuneLocale.
extern struct { char magic[8]; char encoding[32]; void *get, *put; int32_t invalid; uint32_t runetype[256]; }
    darwin_DefaultRuneLocale __asm__("__DefaultRuneLocale");

unsigned long darwin_maskrune(int c, unsigned long mask) DARWIN_SYMBOL(__maskrune);
unsigned long darwin_maskrune(int c, unsigned long mask) {
    return c >= 0 && c < 256 ? darwin_DefaultRuneLocale.runetype[c] & mask : 0;
}

int darwin___tolower(int c) DARWIN_SYMBOL(__tolower);
int darwin___tolower(int c) { return c >= 0 && c < 256 ? tolower(c) : c; }

int darwin___toupper(int c) DARWIN_SYMBOL(__toupper);
int darwin___toupper(int c) { return c >= 0 && c < 256 ? toupper(c) : c; }

// The fortified strlcpy and strlcat: abort if the size given exceeds the
// destination's.
size_t darwin_strlcpy_chk(char *destination, const char *source, size_t size, size_t destination_size)
    DARWIN_SYMBOL(__strlcpy_chk);
size_t darwin_strlcpy_chk(char *destination, const char *source, size_t size, size_t destination_size) {
    if (size > destination_size) abort();
    return strlcpy(destination, source, size);
}

size_t darwin_strlcat_chk(char *destination, const char *source, size_t size, size_t destination_size)
    DARWIN_SYMBOL(__strlcat_chk);
size_t darwin_strlcat_chk(char *destination, const char *source, size_t size, size_t destination_size) {
    if (size > destination_size) abort();
    return strlcat(destination, source, size);
}

// MARK: - Configuration strings

enum {
    DARWIN_CS_PATH = 1,
    DARWIN_CS_DARWIN_USER_DIR = 65536,
    DARWIN_CS_DARWIN_USER_TEMP_DIR = 65537,
    DARWIN_CS_DARWIN_USER_CACHE_DIR = 65538,
};

// The per-user directories are the temporary directory, as NSTemporaryDirectory
// gives it, and its caches; each ends in a slash, as on Darwin.
size_t darwin_confstr(int name, char *buffer, size_t length) DARWIN_SYMBOL(confstr);
size_t darwin_confstr(int name, char *buffer, size_t length) {
    char value[PATH_MAX];
    const char *temporary = getenv("TMPDIR");
    if (!temporary || !*temporary) temporary = "/tmp/";
    const char *slash = temporary[strlen(temporary) - 1] == '/' ? "" : "/";
    switch (name) {
    case DARWIN_CS_PATH:
        return confstr(_CS_PATH, buffer, length);
    case DARWIN_CS_DARWIN_USER_DIR:
    case DARWIN_CS_DARWIN_USER_TEMP_DIR:
        snprintf(value, sizeof value, "%s%s", temporary, slash);
        break;
    case DARWIN_CS_DARWIN_USER_CACHE_DIR:
        snprintf(value, sizeof value, "%s%sCaches/", temporary, slash);
        break;
    default:
        errno = EINVAL;
        return 0;
    }
    if (buffer && length) snprintf(buffer, length, "%s", value);
    return strlen(value) + 1;
}

// MARK: - Random numbers

void darwin_srandomdev(void) DARWIN_SYMBOL(srandomdev);
void darwin_srandomdev(void) { srandom(arc4random()); }

// MARK: - sysctl

enum { CTL_KERN = 1, CTL_HW = 6, KERN_OSTYPE = 1, KERN_OSRELEASE = 2, KERN_PROC = 14, KERN_OSVERSION = 65,
       HW_MACHINE = 1, HW_MODEL = 2, HW_NCPU = 3, HW_PHYSMEM = 5, HW_PAGESIZE = 7, HW_MEMSIZE = 24, HW_AVAILCPU = 25 };

int darwin_sysctlbyname(const char *name, void *old, size_t *old_length, const void *new_value, size_t new_length)
    __asm__("_sysctlbyname");

// The names sysctlbyname answers, by number; a process's information is
// all zeros (no flags: not being debugged).
int darwin_sysctl(const int *names, unsigned count, void *old, size_t *old_length, void *new_value, size_t new_length)
    DARWIN_SYMBOL(sysctl);
int darwin_sysctl(const int *names, unsigned count, void *old, size_t *old_length, void *new_value, size_t new_length) {
    if (count < 2) {
        errno = EINVAL;
        return -1;
    }
    const char *name = NULL;
    if (names[0] == CTL_KERN) {
        switch (names[1]) {
        case KERN_OSTYPE: name = "kern.ostype"; break;
        case KERN_OSRELEASE: name = "kern.osrelease"; break;
        case KERN_OSVERSION: name = "kern.osversion"; break;
        case KERN_PROC: {
            // struct kinfo_proc is 648 bytes on arm64.
            if (!old_length)
                return -1;
            if (old)
                memset(old, 0, *old_length < 648 ? *old_length : 648);
            *old_length = 648;
            return 0;
        }
        }
    } else if (names[0] == CTL_HW) {
        switch (names[1]) {
        case HW_MACHINE: name = "hw.machine"; break;
        case HW_MODEL: name = "hw.model"; break;
        case HW_NCPU: case HW_AVAILCPU: name = "hw.ncpu"; break;
        case HW_PHYSMEM: name = "hw.physmem"; break;
        case HW_MEMSIZE: name = "hw.memsize"; break;
        case HW_PAGESIZE: {
            int32_t size = 16384;
            if (!old_length)
                return -1;
            if (old && *old_length >= sizeof(size))
                memcpy(old, &size, sizeof(size));
            *old_length = sizeof(size);
            return 0;
        }
        }
    }
    if (!name) {
        errno = ENOENT;
        return -1;
    }
    return darwin_sysctlbyname(name, old, old_length, new_value, new_length);
}

// MARK: - ioctl

// The requests whose numbers differ, called through a variadic thunk.
int perry_ioctl(int fd, unsigned long request, va_list arguments) {
    void *argument = va_arg(arguments, void *);
    unsigned long linux_request;
    switch (request) {
    case 0x4004667f: linux_request = FIONREAD; break;
    case 0x8004667e: linux_request = FIONBIO; break;
    case 0x8004667d: linux_request = FIOASYNC; break;
    case 0x20006601: linux_request = FIOCLEX; break;
    case 0x20006602: linux_request = FIONCLEX; break;
    case 0x40087468: linux_request = TIOCGWINSZ; break;
    case 0x80087467: linux_request = TIOCSWINSZ; break;
    default:
        errno = ENOTTY;
        return -1;
    }
    return ioctl(fd, linux_request, argument);
}

// MARK: - Logging and atomics

// The Apple System Log: messages go to stderr.
int perry_asl_log(void *client, void *message, int level, const char *format, va_list arguments) {
    (void)client; (void)message; (void)level;
    vfprintf(stderr, format, arguments);
    fputc('\n', stderr);
    return 0;
}

// A client only identifies the caller; its messages go to stderr too, and
// files added as outputs get nothing more.
void *darwin_asl_open(const char *ident, const char *facility, uint32_t options) DARWIN_SYMBOL(asl_open);
void *darwin_asl_open(const char *ident, const char *facility, uint32_t options) {
    (void)ident; (void)facility; (void)options;
    return calloc(1, 16);
}

void darwin_asl_close(void *client) DARWIN_SYMBOL(asl_close);
void darwin_asl_close(void *client) { free(client); }

// Every level passes the filter; the previous filter is reported as that.
int darwin_asl_set_filter(void *client, int filter) DARWIN_SYMBOL(asl_set_filter);
int darwin_asl_set_filter(void *client, int filter) {
    (void)client; (void)filter;
    return 0xff;
}

int darwin_asl_add_output_file(void *client, int fd, const char *message_format, const char *time_format, int filter,
                               int encoding) DARWIN_SYMBOL(asl_add_output_file);
int darwin_asl_add_output_file(void *client, int fd, const char *message_format, const char *time_format, int filter,
                               int encoding) {
    (void)client; (void)fd; (void)message_format; (void)time_format; (void)filter; (void)encoding;
    return 0;
}

int darwin_asl_add_log_file(void *client, int fd) DARWIN_SYMBOL(asl_add_log_file);
int darwin_asl_add_log_file(void *client, int fd) {
    (void)client; (void)fd;
    return 0;
}

int darwin_asl_remove_log_file(void *client, int fd) DARWIN_SYMBOL(asl_remove_log_file);
int darwin_asl_remove_log_file(void *client, int fd) {
    (void)client; (void)fd;
    return 0;
}

int32_t darwin_OSAtomicAdd32(int32_t amount, volatile int32_t *value) DARWIN_SYMBOL(OSAtomicAdd32);
int32_t darwin_OSAtomicAdd32(int32_t amount, volatile int32_t *value) { return __atomic_add_fetch(value, amount, __ATOMIC_RELAXED); }

int32_t darwin_OSAtomicAdd32Barrier(int32_t amount, volatile int32_t *value) DARWIN_SYMBOL(OSAtomicAdd32Barrier);
int32_t darwin_OSAtomicAdd32Barrier(int32_t amount, volatile int32_t *value) { return __atomic_add_fetch(value, amount, __ATOMIC_SEQ_CST); }

int64_t darwin_OSAtomicAdd64(int64_t amount, volatile int64_t *value) DARWIN_SYMBOL(OSAtomicAdd64);
int64_t darwin_OSAtomicAdd64(int64_t amount, volatile int64_t *value) { return __atomic_add_fetch(value, amount, __ATOMIC_RELAXED); }

int64_t darwin_OSAtomicAdd64Barrier(int64_t amount, volatile int64_t *value) DARWIN_SYMBOL(OSAtomicAdd64Barrier);
int64_t darwin_OSAtomicAdd64Barrier(int64_t amount, volatile int64_t *value) { return __atomic_add_fetch(value, amount, __ATOMIC_SEQ_CST); }

// OSAtomicCompareAndSwap: whether *value was old and is now new.
#define COMPARE_AND_SWAP(name, type, order) \
    bool darwin_##name(type old, type new, type volatile *value) DARWIN_SYMBOL(name); \
    bool darwin_##name(type old, type new, type volatile *value) { \
        return __atomic_compare_exchange_n(value, &old, new, false, order, __ATOMIC_RELAXED); \
    }

COMPARE_AND_SWAP(OSAtomicCompareAndSwap32, int32_t, __ATOMIC_RELAXED)
COMPARE_AND_SWAP(OSAtomicCompareAndSwap32Barrier, int32_t, __ATOMIC_SEQ_CST)
COMPARE_AND_SWAP(OSAtomicCompareAndSwapInt, int, __ATOMIC_RELAXED)
COMPARE_AND_SWAP(OSAtomicCompareAndSwapIntBarrier, int, __ATOMIC_SEQ_CST)
COMPARE_AND_SWAP(OSAtomicCompareAndSwap64, int64_t, __ATOMIC_RELAXED)
COMPARE_AND_SWAP(OSAtomicCompareAndSwap64Barrier, int64_t, __ATOMIC_SEQ_CST)
COMPARE_AND_SWAP(OSAtomicCompareAndSwapLong, long, __ATOMIC_RELAXED)
COMPARE_AND_SWAP(OSAtomicCompareAndSwapLongBarrier, long, __ATOMIC_SEQ_CST)
COMPARE_AND_SWAP(OSAtomicCompareAndSwapPtr, void *, __ATOMIC_RELAXED)
COMPARE_AND_SWAP(OSAtomicCompareAndSwapPtrBarrier, void *, __ATOMIC_SEQ_CST)

// MARK: - Feature flags and tracing

// Feature flags are as they ship: each one's default.
bool darwin_os_feature_enabled_simple_impl(const char *domain, const char *feature, bool enabled)
    DARWIN_SYMBOL(_os_feature_enabled_simple_impl);
bool darwin_os_feature_enabled_simple_impl(const char *domain, const char *feature, bool enabled) {
    (void)domain;
    (void)feature;
    return enabled;
}

// Swift's runtime traces through os_log once the tracing system has
// started, which it never does here.
bool darwin_os_trace_lazy_init_completed_4swift(void) DARWIN_SYMBOL(_os_trace_lazy_init_completed_4swift);
bool darwin_os_trace_lazy_init_completed_4swift(void) { return false; }

// MARK: - UUIDs

int darwin_digittoint(int c) DARWIN_SYMBOL(digittoint);

// uuid_t is 16 bytes. Darwin unparses in upper case.
void darwin_uuid_generate_random(uint8_t *uuid) DARWIN_SYMBOL(uuid_generate_random);
void darwin_uuid_generate_random(uint8_t *uuid) {
    arc4random_buf(uuid, 16);
    uuid[6] = (uuid[6] & 0x0f) | 0x40;      // version 4
    uuid[8] = (uuid[8] & 0x3f) | 0x80;      // RFC 4122 variant
}

void darwin_uuid_generate(uint8_t *uuid) DARWIN_SYMBOL(uuid_generate);
void darwin_uuid_generate(uint8_t *uuid) { darwin_uuid_generate_random(uuid); }

static void uuid_format(const uint8_t *uuid, char *out, const char *digits) {
    for (int i = 0, j = 0; i < 16; i++) {
        if (i == 4 || i == 6 || i == 8 || i == 10)
            out[j++] = '-';
        out[j++] = digits[uuid[i] >> 4];
        out[j++] = digits[uuid[i] & 15];
        out[j] = 0;
    }
}

void darwin_uuid_unparse_upper(const uint8_t *uuid, char *out) DARWIN_SYMBOL(uuid_unparse_upper);
void darwin_uuid_unparse_upper(const uint8_t *uuid, char *out) { uuid_format(uuid, out, "0123456789ABCDEF"); }

void darwin_uuid_unparse_lower(const uint8_t *uuid, char *out) DARWIN_SYMBOL(uuid_unparse_lower);
void darwin_uuid_unparse_lower(const uint8_t *uuid, char *out) { uuid_format(uuid, out, "0123456789abcdef"); }

void darwin_uuid_unparse(const uint8_t *uuid, char *out) DARWIN_SYMBOL(uuid_unparse);
void darwin_uuid_unparse(const uint8_t *uuid, char *out) { darwin_uuid_unparse_upper(uuid, out); }

// 0 for a string in the 8-4-4-4-12 form, else -1.
int darwin_uuid_parse(const char *in, uint8_t *uuid) DARWIN_SYMBOL(uuid_parse);
int darwin_uuid_parse(const char *in, uint8_t *uuid) {
    if (strlen(in) != 36)
        return -1;
    for (int i = 0, j = 0; i < 16; i++) {
        if (j == 8 || j == 13 || j == 18 || j == 23) {
            if (in[j] != '-')
                return -1;
            j++;
        }
        int high = darwin_digittoint(in[j]), low = darwin_digittoint(in[j + 1]);
        if (!isxdigit((unsigned char)in[j]) || !isxdigit((unsigned char)in[j + 1]))
            return -1;
        uuid[i] = (uint8_t)(high << 4 | low);
        j += 2;
    }
    return 0;
}

void darwin_uuid_copy(uint8_t *destination, const uint8_t *source) DARWIN_SYMBOL(uuid_copy);
void darwin_uuid_copy(uint8_t *destination, const uint8_t *source) { memcpy(destination, source, 16); }

void darwin_uuid_clear(uint8_t *uuid) DARWIN_SYMBOL(uuid_clear);
void darwin_uuid_clear(uint8_t *uuid) { memset(uuid, 0, 16); }

int darwin_uuid_compare(const uint8_t *a, const uint8_t *b) DARWIN_SYMBOL(uuid_compare);
int darwin_uuid_compare(const uint8_t *a, const uint8_t *b) { return memcmp(a, b, 16); }

int darwin_uuid_is_null(const uint8_t *uuid) DARWIN_SYMBOL(uuid_is_null);
int darwin_uuid_is_null(const uint8_t *uuid) {
    static const uint8_t zero[16];
    return memcmp(uuid, zero, 16) == 0;
}

// MARK: - Regular expressions

// Darwin's regex_t is { re_magic, re_nsub, re_endp, re_g }, 32 bytes,
// smaller than glibc's: re_g holds a glibc regex_t. Match offsets are
// 64-bit on Darwin and 32-bit in glibc.
struct darwin_regex {
    int magic;
    size_t nsub;
    const char *endp;
    regex_t *linux_regex;
};

struct darwin_regmatch { int64_t so, eo; };

enum { DARWIN_REGEX_MAGIC = 0xf265 };

int darwin_regcomp(struct darwin_regex *regex, const char *pattern, int flags) DARWIN_SYMBOL(regcomp);
int darwin_regcomp(struct darwin_regex *regex, const char *pattern, int flags) {
    int linux_flags = (flags & 1 ? REG_EXTENDED : 0) | (flags & 2 ? REG_ICASE : 0) | (flags & 4 ? REG_NOSUB : 0) |
                      (flags & 8 ? REG_NEWLINE : 0);
    regex_t *compiled = calloc(1, sizeof(*compiled));
    int error = regcomp(compiled, pattern, linux_flags);
    if (error) {
        free(compiled);
        return error;
    }
    regex->magic = DARWIN_REGEX_MAGIC;
    regex->nsub = compiled->re_nsub;
    regex->endp = NULL;
    regex->linux_regex = compiled;
    return 0;
}

int darwin_regexec(const struct darwin_regex *regex, const char *string, size_t count, struct darwin_regmatch *matches,
                   int flags) DARWIN_SYMBOL(regexec);
int darwin_regexec(const struct darwin_regex *regex, const char *string, size_t count, struct darwin_regmatch *matches,
                   int flags) {
    if (regex->magic != DARWIN_REGEX_MAGIC)
        return REG_BADPAT;
    regmatch_t *linux_matches = count ? calloc(count, sizeof(*linux_matches)) : NULL;
    // REG_STARTEND reads the range from the first match.
    if (count && (flags & REG_STARTEND)) {
        linux_matches[0].rm_so = (regoff_t)matches[0].so;
        linux_matches[0].rm_eo = (regoff_t)matches[0].eo;
    }
    int result = regexec(regex->linux_regex, string, count, linux_matches, flags & (REG_NOTBOL | REG_NOTEOL | REG_STARTEND));
    for (size_t i = 0; result == 0 && i < count; i++) {
        matches[i].so = linux_matches[i].rm_so;
        matches[i].eo = linux_matches[i].rm_eo;
    }
    free(linux_matches);
    return result;
}

void darwin_regfree(struct darwin_regex *regex) DARWIN_SYMBOL(regfree);
void darwin_regfree(struct darwin_regex *regex) {
    if (regex->magic != DARWIN_REGEX_MAGIC)
        return;
    regfree(regex->linux_regex);
    free(regex->linux_regex);
    regex->magic = 0;
    regex->linux_regex = NULL;
}

size_t darwin_regerror(int error, const struct darwin_regex *regex, char *buffer, size_t size) DARWIN_SYMBOL(regerror);
size_t darwin_regerror(int error, const struct darwin_regex *regex, char *buffer, size_t size) {
    return regerror(error, regex && regex->magic == DARWIN_REGEX_MAGIC ? regex->linux_regex : NULL, buffer, size);
}

// MARK: - Tracing and OS variants

// kdebug: kernel trace points, which nothing records here.
bool darwin_kdebug_is_enabled(uint32_t debugid) DARWIN_SYMBOL(kdebug_is_enabled);
bool darwin_kdebug_is_enabled(uint32_t debugid) {
    (void)debugid;
    return false;
}

int darwin_kdebug_trace(uint32_t debugid, uint64_t arg1, uint64_t arg2, uint64_t arg3, uint64_t arg4)
    DARWIN_SYMBOL(kdebug_trace);
int darwin_kdebug_trace(uint32_t debugid, uint64_t arg1, uint64_t arg2, uint64_t arg3, uint64_t arg4) {
    (void)debugid, (void)arg1, (void)arg2, (void)arg3, (void)arg4;
    return 0;
}

uint64_t darwin_kdebug_trace_string(uint32_t debugid, uint64_t string_id, const char *string)
    DARWIN_SYMBOL(kdebug_trace_string);
uint64_t darwin_kdebug_trace_string(uint32_t debugid, uint64_t string_id, const char *string) {
    (void)debugid, (void)string;
    return string_id;
}

// A customer build of the OS: no internal content or policies.
bool darwin_os_variant_has_internal_content(const char *subsystem) DARWIN_SYMBOL(os_variant_has_internal_content);
bool darwin_os_variant_has_internal_content(const char *subsystem) {
    (void)subsystem;
    return false;
}

bool darwin_os_variant_allows_internal_security_policies(const char *subsystem)
    DARWIN_SYMBOL(os_variant_allows_internal_security_policies);
bool darwin_os_variant_allows_internal_security_policies(const char *subsystem) {
    (void)subsystem;
    return false;
}

// MARK: - Crash reports

void darwin_abort_report_np(const char *format, ...) DARWIN_SYMBOL(abort_report_np);
void darwin_abort_report_np(const char *format, ...) {
    va_list args;
    va_start(args, format);
    vfprintf(stderr, format, args);
    va_end(args);
    fputc('\n', stderr);
    abort();
}

// Each address's image UUID and offset, which crash reports use; none here.
struct darwin_image_offset {
    uint8_t uuid[16];
    uint32_t offset;
};

void darwin_backtrace_image_offsets(void *const *array, struct darwin_image_offset *offsets, int size)
    DARWIN_SYMBOL(backtrace_image_offsets);
void darwin_backtrace_image_offsets(void *const *array, struct darwin_image_offset *offsets, int size) {
    (void)array;
    if (size > 0)
        memset(offsets, 0, (size_t)size * sizeof(*offsets));
}

// dyld's thread-local variable bootstrap, which descriptors are bound to
// until the loader points them at its own (PerryLoaderCore's tlv.c).
void darwin_tlv_bootstrap(void) DARWIN_SYMBOL(_tlv_bootstrap);
void darwin_tlv_bootstrap(void) {
    fprintf(stderr, "perry: thread-local variable used before its image was set up\n");
    abort();
}
