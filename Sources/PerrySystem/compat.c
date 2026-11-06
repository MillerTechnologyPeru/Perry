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
#include <semaphore.h>
#include <signal.h>
#include <stdarg.h>
#include <time.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <stdatomic.h>
#include <sys/resource.h>
#include <sys/xattr.h>
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

// A thread attribute's priority: threads all run at the default one, 31,
// whatever is asked for.
int darwin_pthread_attr_getschedparam(const pthread_attr_t *attributes, struct darwin_sched_param *param)
    DARWIN_SYMBOL(pthread_attr_getschedparam);
int darwin_pthread_attr_getschedparam(const pthread_attr_t *attributes, struct darwin_sched_param *param) {
    (void)attributes;
    if (param)
        param->priority = 31;
    return 0;
}

// MARK: - Sorting with a block

// qsort_b: the comparator is a block, whose invoke function takes the
// block and then the two elements.
struct compare_block {
    void *isa;
    int flags;
    int reserved;
    int (*invoke)(void *block, const void *a, const void *b);
};

static int compare_with_block(const void *a, const void *b, void *context) {
    struct compare_block *block = context;
    int order;
    PERRY_KEEP_R9(order = block->invoke(block, a, b));
    return order;
}

void darwin_qsort_b(void *base, size_t count, size_t size, void *block) DARWIN_SYMBOL(qsort_b);
void darwin_qsort_b(void *base, size_t count, size_t size, void *block) {
    qsort_r(base, count, size, compare_with_block, block);
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

/// The entry in the caller's storage: the host's strings in the buffer.
static int passwd_r_to_darwin(int status, const struct passwd *entry, struct darwin_passwd *out, struct darwin_passwd **result) {
    *result = NULL;
    if (status || !entry) return status;
    *out = (struct darwin_passwd){ entry->pw_name, entry->pw_passwd, entry->pw_uid, entry->pw_gid, 0, "",
                                   entry->pw_gecos, entry->pw_dir, entry->pw_shell, 0 };
    *result = out;
    return 0;
}

int darwin_getpwuid_r(uid_t uid, struct darwin_passwd *out, char *buffer, size_t size, struct darwin_passwd **result)
    DARWIN_SYMBOL(getpwuid_r);
int darwin_getpwuid_r(uid_t uid, struct darwin_passwd *out, char *buffer, size_t size, struct darwin_passwd **result) {
    struct passwd entry, *found = NULL;
    return passwd_r_to_darwin(getpwuid_r(uid, &entry, buffer, size, &found), found, out, result);
}

int darwin_getpwnam_r(const char *name, struct darwin_passwd *out, char *buffer, size_t size, struct darwin_passwd **result)
    DARWIN_SYMBOL(getpwnam_r);
int darwin_getpwnam_r(const char *name, struct darwin_passwd *out, char *buffer, size_t size, struct darwin_passwd **result) {
    struct passwd entry, *found = NULL;
    return passwd_r_to_darwin(getpwnam_r(name, &entry, buffer, size, &found), found, out, result);
}

// A locale object: glibc's, opaque to the program. Darwin's category masks
// are bits 0 to 5 for collate, ctype, messages, monetary, numeric and time.
locale_t darwin_newlocale(int mask, const char *name, locale_t base) DARWIN_SYMBOL(newlocale);
locale_t darwin_newlocale(int mask, const char *name, locale_t base) {
    static const int masks[] = { LC_COLLATE_MASK, LC_CTYPE_MASK, LC_MESSAGES_MASK, LC_MONETARY_MASK, LC_NUMERIC_MASK, LC_TIME_MASK };
    int linux_mask = 0;
    for (int i = 0; i < 6; i++)
        if (mask & (1 << i))
            linux_mask |= masks[i];
    locale_t made = newlocale(linux_mask, name ? name : "C", base);
    // A locale this system lacks is the C locale's, as with setlocale.
    return made ? made : newlocale(linux_mask, "C", base);
}

void darwin_freelocale(locale_t locale) DARWIN_SYMBOL(freelocale);
void darwin_freelocale(locale_t locale) {
    if (locale)
        freelocale(locale);
}

locale_t darwin_duplocale(locale_t locale) DARWIN_SYMBOL(duplocale);
locale_t darwin_duplocale(locale_t locale) { return duplocale(locale ? locale : LC_GLOBAL_LOCALE); }

locale_t darwin_uselocale(locale_t locale) DARWIN_SYMBOL(uselocale);
locale_t darwin_uselocale(locale_t locale) { return uselocale(locale); }

// MARK: - Locale conventions

/// Darwin's lconv: glibc's, but with the international fields ordered
/// p_cs_precedes, n_cs_precedes, p_sep_by_space, n_sep_by_space.
struct darwin_lconv {
    char *decimal_point, *thousands_sep, *grouping, *int_curr_symbol, *currency_symbol;
    char *mon_decimal_point, *mon_thousands_sep, *mon_grouping, *positive_sign, *negative_sign;
    char int_frac_digits, frac_digits, p_cs_precedes, p_sep_by_space, n_cs_precedes, n_sep_by_space, p_sign_posn, n_sign_posn;
    char int_p_cs_precedes, int_n_cs_precedes, int_p_sep_by_space, int_n_sep_by_space, int_p_sign_posn, int_n_sign_posn;
};

struct darwin_lconv *darwin_localeconv(void) DARWIN_SYMBOL(localeconv);
struct darwin_lconv *darwin_localeconv(void) {
    static __thread struct darwin_lconv result;
    const struct lconv *l = localeconv();
    result = (struct darwin_lconv){
        l->decimal_point, l->thousands_sep, l->grouping, l->int_curr_symbol, l->currency_symbol,
        l->mon_decimal_point, l->mon_thousands_sep, l->mon_grouping, l->positive_sign, l->negative_sign,
        l->int_frac_digits, l->frac_digits, l->p_cs_precedes, l->p_sep_by_space, l->n_cs_precedes, l->n_sep_by_space,
        l->p_sign_posn, l->n_sign_posn,
        l->int_p_cs_precedes, l->int_n_cs_precedes, l->int_p_sep_by_space, l->int_n_sep_by_space,
        l->int_p_sign_posn, l->int_n_sign_posn,
    };
    return &result;
}

// MARK: - Terminals

/// An app has no terminal: Darwin's termios differs from Linux's, and the
/// standard streams are the launcher's log.
int darwin_tcgetattr(int fd, void *attributes) DARWIN_SYMBOL(tcgetattr);
int darwin_tcgetattr(int fd, void *attributes) {
    (void)fd; (void)attributes;
    errno = ENOTTY;
    return -1;
}

int darwin_tcsetattr(int fd, int action, const void *attributes) DARWIN_SYMBOL(tcsetattr);
int darwin_tcsetattr(int fd, int action, const void *attributes) {
    (void)fd; (void)action; (void)attributes;
    errno = ENOTTY;
    return -1;
}

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

enum { CTL_KERN = 1, CTL_HW = 6, CTL_USER = 8, USER_CS_PATH = 1, KERN_OSTYPE = 1, KERN_OSRELEASE = 2, KERN_PROC = 14, KERN_OSVERSION = 65,
       HW_MACHINE = 1, HW_MODEL = 2, HW_NCPU = 3, HW_PHYSMEM = 5, HW_PAGESIZE = 7, HW_MEMSIZE = 24, HW_AVAILCPU = 25 };

int darwin_sysctlbyname(const char *name, void *old, size_t *old_length, const void *new_value, size_t new_length)
    __asm__("_sysctlbyname");

// The names sysctlbyname answers, by number, and the standard utilities'
// path (user.cs_path); a process's information is all zeros (no flags: not
// being debugged).
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
            // struct kinfo_proc is 648 bytes on arm64, 492 on armv7.
            if (!old_length)
                return -1;
            if (old)
                memset(old, 0, *old_length < PERRY_KINFO_PROC_SIZE ? *old_length : PERRY_KINFO_PROC_SIZE);
            *old_length = PERRY_KINFO_PROC_SIZE;
            return 0;
        }
        }
    } else if (names[0] == CTL_USER && names[1] == USER_CS_PATH) {
        // The standard utilities' search path, as confstr gives it.
        if (!old_length)
            return -1;
        size_t length = confstr(_CS_PATH, NULL, 0);
        if (old && *old_length < length) {
            errno = ENOMEM;
            return -1;
        }
        if (old)
            confstr(_CS_PATH, old, length);
        *old_length = length;
        return 0;
    } else if (names[0] == CTL_HW) {
        switch (names[1]) {
        case HW_MACHINE: name = "hw.machine"; break;
        case HW_MODEL: name = "hw.model"; break;
        case HW_NCPU: case HW_AVAILCPU: name = "hw.ncpu"; break;
        case HW_PHYSMEM: name = "hw.physmem"; break;
        case HW_MEMSIZE: name = "hw.memsize"; break;
        case HW_PAGESIZE: {
            int32_t size = PERRY_PAGE_SIZE;
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

int32_t darwin_OSAtomicOr32Barrier(uint32_t mask, volatile uint32_t *value) DARWIN_SYMBOL(OSAtomicOr32Barrier);
int32_t darwin_OSAtomicOr32Barrier(uint32_t mask, volatile uint32_t *value) { return (int32_t)__atomic_or_fetch(value, mask, __ATOMIC_SEQ_CST); }

// Bit n counts from the most significant bit of the first byte, as Darwin's.
bool darwin_OSAtomicTestAndClearBarrier(uint32_t n, volatile void *address) DARWIN_SYMBOL(OSAtomicTestAndClearBarrier);
bool darwin_OSAtomicTestAndClearBarrier(uint32_t n, volatile void *address) {
    volatile uint8_t *byte = (volatile uint8_t *)address + (n >> 3);
    uint8_t mask = (uint8_t)(0x80u >> (n & 7));
    return (__atomic_fetch_and(byte, (uint8_t)~mask, __ATOMIC_SEQ_CST) & mask) != 0;
}

// No library has a link-time version here: -1, as for one not linked.
int32_t darwin_NSVersionOfLinkTimeLibrary(const char *name) DARWIN_SYMBOL(NSVersionOfLinkTimeLibrary);
int32_t darwin_NSVersionOfLinkTimeLibrary(const char *name) { (void)name; return -1; }

const char *darwin_mach_error_string(int error) DARWIN_SYMBOL(mach_error_string);
const char *darwin_mach_error_string(int error) { return error == 0 ? "(os/kern) successful" : "(os/kern) failure"; }

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

// C++ thread_local destructors: dyld runs them when the thread exits, or at
// exit for the main thread, in reverse order, as glibc's
// __cxa_thread_atexit_impl does. glibc runs them before pthread keys'
// destructors, so the thread's copy of the variable (tlv.c) is still there.
extern int __cxa_thread_atexit_impl(void (*func)(void *), void *object, void *dso_symbol);
extern void *__dso_handle;
void darwin_tlv_atexit(void (*func)(void *), void *object) DARWIN_SYMBOL(_tlv_atexit);
void darwin_tlv_atexit(void (*func)(void *), void *object) {
    __cxa_thread_atexit_impl(func, object, &__dso_handle);
}

// MARK: - More atomics

int32_t darwin_OSAtomicIncrement32(volatile int32_t *value) DARWIN_SYMBOL(OSAtomicIncrement32);
int32_t darwin_OSAtomicIncrement32(volatile int32_t *value) { return __atomic_add_fetch(value, 1, __ATOMIC_RELAXED); }

int32_t darwin_OSAtomicIncrement32Barrier(volatile int32_t *value) DARWIN_SYMBOL(OSAtomicIncrement32Barrier);
int32_t darwin_OSAtomicIncrement32Barrier(volatile int32_t *value) { return __atomic_add_fetch(value, 1, __ATOMIC_SEQ_CST); }

int32_t darwin_OSAtomicDecrement32(volatile int32_t *value) DARWIN_SYMBOL(OSAtomicDecrement32);
int32_t darwin_OSAtomicDecrement32(volatile int32_t *value) { return __atomic_sub_fetch(value, 1, __ATOMIC_RELAXED); }

int32_t darwin_OSAtomicDecrement32Barrier(volatile int32_t *value) DARWIN_SYMBOL(OSAtomicDecrement32Barrier);
int32_t darwin_OSAtomicDecrement32Barrier(volatile int32_t *value) { return __atomic_sub_fetch(value, 1, __ATOMIC_SEQ_CST); }

void darwin_OSMemoryBarrier(void) DARWIN_SYMBOL(OSMemoryBarrier);
void darwin_OSMemoryBarrier(void) { __atomic_thread_fence(__ATOMIC_SEQ_CST); }

// OSSpinLock: an int, 0 when unlocked.
bool darwin_OSSpinLockTry(volatile int32_t *lock) DARWIN_SYMBOL(OSSpinLockTry);
bool darwin_OSSpinLockTry(volatile int32_t *lock) {
    int32_t expected = 0;
    return __atomic_compare_exchange_n(lock, &expected, 1, false, __ATOMIC_ACQUIRE, __ATOMIC_RELAXED);
}

void darwin_OSSpinLockLock(volatile int32_t *lock) DARWIN_SYMBOL(OSSpinLockLock);
void darwin_OSSpinLockLock(volatile int32_t *lock) {
    while (!darwin_OSSpinLockTry(lock))
        sched_yield();
}

void darwin_OSSpinLockUnlock(volatile int32_t *lock) DARWIN_SYMBOL(OSSpinLockUnlock);
void darwin_OSSpinLockUnlock(volatile int32_t *lock) { __atomic_store_n(lock, 0, __ATOMIC_RELEASE); }

// MARK: - More of the Apple System Log

// A message: its keys and values. Searching the log finds nothing, as it
// keeps nothing; sending a message writes its text to stderr.
typedef struct { char **keys, **values; size_t count; } darwin_asl_message;

void *darwin_asl_new(uint32_t type) DARWIN_SYMBOL(asl_new);
void *darwin_asl_new(uint32_t type) { (void)type; return calloc(1, sizeof(darwin_asl_message)); }

void darwin_asl_free(darwin_asl_message *message) DARWIN_SYMBOL(asl_free);
void darwin_asl_free(darwin_asl_message *message) {
    if (!message)
        return;
    for (size_t i = 0; i < message->count; i++) {
        free(message->keys[i]);
        free(message->values[i]);
    }
    free(message->keys);
    free(message->values);
    free(message);
}

int darwin_asl_set(darwin_asl_message *message, const char *key, const char *value) DARWIN_SYMBOL(asl_set);
int darwin_asl_set(darwin_asl_message *message, const char *key, const char *value) {
    if (!message || !key)
        return -1;
    for (size_t i = 0; i < message->count; i++) {
        if (strcmp(message->keys[i], key) == 0) {
            free(message->values[i]);
            message->values[i] = value ? strdup(value) : NULL;
            return 0;
        }
    }
    message->keys = realloc(message->keys, (message->count + 1) * sizeof(char *));
    message->values = realloc(message->values, (message->count + 1) * sizeof(char *));
    message->keys[message->count] = strdup(key);
    message->values[message->count] = value ? strdup(value) : NULL;
    message->count++;
    return 0;
}

int darwin_asl_set_query(darwin_asl_message *message, const char *key, const char *value, uint32_t op) DARWIN_SYMBOL(asl_set_query);
int darwin_asl_set_query(darwin_asl_message *message, const char *key, const char *value, uint32_t op) {
    (void)op;
    return darwin_asl_set(message, key, value);
}

const char *darwin_asl_get(darwin_asl_message *message, const char *key) DARWIN_SYMBOL(asl_get);
const char *darwin_asl_get(darwin_asl_message *message, const char *key) {
    if (!message || !key)
        return NULL;
    for (size_t i = 0; i < message->count; i++)
        if (strcmp(message->keys[i], key) == 0)
            return message->values[i];
    return NULL;
}

int darwin_asl_send(void *client, darwin_asl_message *message) DARWIN_SYMBOL(asl_send);
int darwin_asl_send(void *client, darwin_asl_message *message) {
    (void)client;
    const char *text = darwin_asl_get(message, "Message");
    if (text)
        fprintf(stderr, "%s\n", text);
    return 0;
}

// A search's response, which has no messages.
void *darwin_asl_search(void *client, void *query) DARWIN_SYMBOL(asl_search);
void *darwin_asl_search(void *client, void *query) { (void)client; (void)query; return calloc(1, 1); }

void *darwin_aslresponse_next(void *response) DARWIN_SYMBOL(aslresponse_next);
void *darwin_aslresponse_next(void *response) { (void)response; return NULL; }

void darwin_aslresponse_free(void *response) DARWIN_SYMBOL(aslresponse_free);
void darwin_aslresponse_free(void *response) { free(response); }

// asl_next and asl_release: aslresponse_next and the freeing of any ASL
// object, as macOS 10.10 renamed them.
void *darwin_asl_next(void *response) DARWIN_SYMBOL(asl_next);
void *darwin_asl_next(void *response) { (void)response; return NULL; }

void darwin_asl_release(void *object) DARWIN_SYMBOL(asl_release);
void darwin_asl_release(void *object) { free(object); }

// MARK: - Notifications

// notify(3): a registration gets a token, and no notification comes.
static _Atomic int notify_tokens;

uint32_t darwin_notify_register_dispatch(const char *name, int *token, void *queue, void *handler)
    DARWIN_SYMBOL(notify_register_dispatch);
uint32_t darwin_notify_register_dispatch(const char *name, int *token, void *queue, void *handler) {
    (void)name, (void)queue, (void)handler;
    if (token)
        *token = atomic_fetch_add(&notify_tokens, 1) + 1;
    return 0;
}

uint32_t darwin_notify_cancel(int token) DARWIN_SYMBOL(notify_cancel);
uint32_t darwin_notify_cancel(int token) { (void)token; return 0; }

// MARK: - Extended attributes

// Darwin's take a position and options (XATTR_NOFOLLOW 1); Linux keeps an
// app's attributes in its user namespace.
static void xattr_name(const char *name, char *out, size_t size) { snprintf(out, size, "user.%s", name); }

ssize_t darwin_getxattr(const char *path, const char *name, void *value, size_t size, uint32_t position, int options)
    DARWIN_SYMBOL(getxattr);
ssize_t darwin_getxattr(const char *path, const char *name, void *value, size_t size, uint32_t position, int options) {
    (void)position;
    char linux_name[512];
    xattr_name(name, linux_name, sizeof(linux_name));
    ssize_t length = (options & 1) ? lgetxattr(path, linux_name, value, size) : getxattr(path, linux_name, value, size);
    if (length < 0 && errno == ENODATA)
        errno = 93;    // ENOATTR
    return length;
}

int darwin_setxattr(const char *path, const char *name, const void *value, size_t size, uint32_t position, int options)
    DARWIN_SYMBOL(setxattr);
int darwin_setxattr(const char *path, const char *name, const void *value, size_t size, uint32_t position, int options) {
    (void)position;
    char linux_name[512];
    xattr_name(name, linux_name, sizeof(linux_name));
    // XATTR_CREATE 2 and XATTR_REPLACE 4 are Linux's 1 and 2.
    int flags = ((options & 2) ? XATTR_CREATE : 0) | ((options & 4) ? XATTR_REPLACE : 0);
    return (options & 1) ? lsetxattr(path, linux_name, value, size, flags) : setxattr(path, linux_name, value, size, flags);
}

int darwin_removexattr(const char *path, const char *name, int options) DARWIN_SYMBOL(removexattr);
int darwin_removexattr(const char *path, const char *name, int options) {
    char linux_name[512];
    xattr_name(name, linux_name, sizeof(linux_name));
    int result = (options & 1) ? lremovexattr(path, linux_name) : removexattr(path, linux_name);
    if (result < 0 && errno == ENODATA)
        errno = 93;
    return result;
}

ssize_t darwin_fgetxattr(int fd, const char *name, void *value, size_t size, uint32_t position, int options)
    DARWIN_SYMBOL(fgetxattr);
ssize_t darwin_fgetxattr(int fd, const char *name, void *value, size_t size, uint32_t position, int options) {
    (void)position, (void)options;
    char linux_name[512];
    xattr_name(name, linux_name, sizeof(linux_name));
    ssize_t length = fgetxattr(fd, linux_name, value, size);
    if (length < 0 && errno == ENODATA)
        errno = 93;
    return length;
}

int darwin_fsetxattr(int fd, const char *name, const void *value, size_t size, uint32_t position, int options)
    DARWIN_SYMBOL(fsetxattr);
int darwin_fsetxattr(int fd, const char *name, const void *value, size_t size, uint32_t position, int options) {
    (void)position;
    char linux_name[512];
    xattr_name(name, linux_name, sizeof(linux_name));
    int flags = ((options & 2) ? XATTR_CREATE : 0) | ((options & 4) ? XATTR_REPLACE : 0);
    return fsetxattr(fd, linux_name, value, size, flags);
}

int darwin_fremovexattr(int fd, const char *name, int options) DARWIN_SYMBOL(fremovexattr);
int darwin_fremovexattr(int fd, const char *name, int options) {
    (void)options;
    char linux_name[512];
    xattr_name(name, linux_name, sizeof(linux_name));
    int result = fremovexattr(fd, linux_name);
    if (result < 0 && errno == ENODATA)
        errno = 93;
    return result;
}

// MARK: - Signal stacks and the rest

// Darwin's stack_t is { ss_sp, ss_size, ss_flags }; Linux's { ss_sp,
// ss_flags, ss_size }. SS_ONSTACK and SS_DISABLE are 1 and 4 on both.
struct darwin_stack { void *sp; size_t size; int flags; };

int darwin_sigaltstack(const struct darwin_stack *stack, struct darwin_stack *previous) DARWIN_SYMBOL(sigaltstack);
int darwin_sigaltstack(const struct darwin_stack *stack, struct darwin_stack *previous) {
    stack_t linux_stack, linux_previous;
    if (stack) {
        linux_stack.ss_sp = stack->sp;
        linux_stack.ss_size = stack->size;
        linux_stack.ss_flags = stack->flags & SS_DISABLE;
    }
    int result = sigaltstack(stack ? &linux_stack : NULL, previous ? &linux_previous : NULL);
    if (result == 0 && previous) {
        previous->sp = linux_previous.ss_sp;
        previous->size = linux_previous.ss_size;
        previous->flags = linux_previous.ss_flags;
    }
    return result;
}

const char *darwin_getprogname(void) DARWIN_SYMBOL(getprogname);
const char *darwin_getprogname(void) { return program_invocation_short_name; }

// MARK: - Semaphores

// Darwin's sem_t is an int, too small for glibc's: each semaphore sem_init
// makes is glibc's, found by the address of the app's. (Darwin itself
// fails sem_init, but games written against other systems' semaphores
// count on them.) Named ones, from sem_open, are glibc's pointers.

typedef struct semaphore_entry { const void *key; sem_t *semaphore; } semaphore_entry;
static pthread_mutex_t semaphores_lock = PTHREAD_MUTEX_INITIALIZER;
static semaphore_entry *semaphore_table;
static size_t semaphore_count, semaphore_capacity;

static sem_t *unnamed(const void *key) {
    sem_t *found = NULL;
    pthread_mutex_lock(&semaphores_lock);
    for (size_t i = 0; i < semaphore_count && !found; i++)
        if (semaphore_table[i].key == key) found = semaphore_table[i].semaphore;
    pthread_mutex_unlock(&semaphores_lock);
    return found;
}

int darwin_sem_init(void *semaphore, int shared, unsigned value) DARWIN_SYMBOL(sem_init);
int darwin_sem_init(void *semaphore, int shared, unsigned value) {
    (void)shared;
    if (!semaphore) { errno = EINVAL; return -1; }
    sem_t *existing = unnamed(semaphore);
    if (existing) return sem_init(existing, 0, value);
    sem_t *made = malloc(sizeof *made);
    if (!made || sem_init(made, 0, value) != 0) { free(made); errno = ENOSPC; return -1; }
    pthread_mutex_lock(&semaphores_lock);
    if (semaphore_count == semaphore_capacity) {
        size_t capacity = semaphore_capacity ? semaphore_capacity * 2 : 16;
        semaphore_entry *grown = realloc(semaphore_table, capacity * sizeof *grown);
        if (!grown) { pthread_mutex_unlock(&semaphores_lock); sem_destroy(made); free(made); errno = ENOSPC; return -1; }
        semaphore_table = grown;
        semaphore_capacity = capacity;
    }
    semaphore_table[semaphore_count++] = (semaphore_entry){ semaphore, made };
    pthread_mutex_unlock(&semaphores_lock);
    *(int *)semaphore = 0;
    return 0;
}

int darwin_sem_destroy(void *semaphore) DARWIN_SYMBOL(sem_destroy);
int darwin_sem_destroy(void *semaphore) {
    sem_t *found = NULL;
    pthread_mutex_lock(&semaphores_lock);
    for (size_t i = 0; i < semaphore_count; i++) {
        if (semaphore_table[i].key == semaphore) {
            found = semaphore_table[i].semaphore;
            semaphore_table[i] = semaphore_table[--semaphore_count];
            break;
        }
    }
    pthread_mutex_unlock(&semaphores_lock);
    if (!found) { errno = EINVAL; return -1; }
    sem_destroy(found);
    free(found);
    return 0;
}

/// The glibc semaphore for an app's: an unnamed one's, or a named one's own.
static sem_t *semaphore_for(void *semaphore) {
    sem_t *found = unnamed(semaphore);
    return found ? found : semaphore;
}

int darwin_sem_post(void *semaphore) DARWIN_SYMBOL(sem_post);
int darwin_sem_post(void *semaphore) { return sem_post(semaphore_for(semaphore)); }

int darwin_sem_wait(void *semaphore) DARWIN_SYMBOL(sem_wait);
int darwin_sem_wait(void *semaphore) { return sem_wait(semaphore_for(semaphore)); }

int darwin_sem_trywait(void *semaphore) DARWIN_SYMBOL(sem_trywait);
int darwin_sem_trywait(void *semaphore) { return sem_trywait(semaphore_for(semaphore)); }

// Compares in time that depends only on the length: 0 when equal.
int darwin_timingsafe_bcmp(const void *a, const void *b, size_t length) DARWIN_SYMBOL(timingsafe_bcmp);
int darwin_timingsafe_bcmp(const void *a, const void *b, size_t length) {
    const unsigned char *x = a, *y = b;
    unsigned char difference = 0;
    for (size_t i = 0; i < length; i++)
        difference |= x[i] ^ y[i];
    return difference != 0;
}

// MARK: - Atomic queues

// OSAtomicEnqueue and OSAtomicDequeue: a last-in, first-out list threaded
// through its elements, `offset` bytes into each. Darwin's are lock-free;
// here one lock guards every list, as the calls are short.
typedef struct {
    void *first;
    long unused;
} darwin_queue_head;

static pthread_mutex_t queue_lock = PTHREAD_MUTEX_INITIALIZER;

void darwin_OSAtomicEnqueue(darwin_queue_head *list, void *element, size_t offset) DARWIN_SYMBOL(OSAtomicEnqueue);
void darwin_OSAtomicEnqueue(darwin_queue_head *list, void *element, size_t offset) {
    pthread_mutex_lock(&queue_lock);
    *(void **)((char *)element + offset) = list->first;
    list->first = element;
    pthread_mutex_unlock(&queue_lock);
}

void *darwin_OSAtomicDequeue(darwin_queue_head *list, size_t offset) DARWIN_SYMBOL(OSAtomicDequeue);
void *darwin_OSAtomicDequeue(darwin_queue_head *list, size_t offset) {
    pthread_mutex_lock(&queue_lock);
    void *element = list->first;
    if (element)
        list->first = *(void **)((char *)element + offset);
    pthread_mutex_unlock(&queue_lock);
    return element;
}

// MARK: - The floating-point environment

// Darwin's arm64 fenv_t is the status and control registers as two 64-bit
// words, status first; glibc's is two 32-bit words, control first.
typedef struct {
    uint64_t status;
    uint64_t control;
} darwin_fenv;

/// FE_DFL_ENV: nothing raised, round to nearest.
const darwin_fenv darwin_FE_DFL_ENV DARWIN_SYMBOL(_FE_DFL_ENV) = { 0, 0 };

int darwin_fegetenv(darwin_fenv *environment) DARWIN_SYMBOL(fegetenv);
int darwin_fegetenv(darwin_fenv *environment) {
#if defined(__aarch64__)
    uint64_t status, control;
    __asm__("mrs %0, fpsr" : "=r"(status));
    __asm__("mrs %0, fpcr" : "=r"(control));
    environment->status = status;
    environment->control = control;
#else
    environment->status = environment->control = 0;
#endif
    return 0;
}

int darwin_fesetenv(const darwin_fenv *environment) DARWIN_SYMBOL(fesetenv);
int darwin_fesetenv(const darwin_fenv *environment) {
#if defined(__aarch64__)
    uint64_t status = environment->status, control = environment->control;
    __asm__("msr fpsr, %0" : : "r"(status));
    __asm__("msr fpcr, %0" : : "r"(control));
#else
    (void)environment;
#endif
    return 0;
}

/// math.h's isfinite of a float, as its macro calls it.
int darwin_isfinitef(float value) DARWIN_SYMBOL(__isfinitef);
int darwin_isfinitef(float value) { return __builtin_isfinite(value); }

// MARK: - System calls by number

// syscall(2) with Darwin's numbers: the few that ask who is calling are
// answered; any other fails with ENOSYS, as one the kernel lacks does.
long darwin_syscall(long number) DARWIN_SYMBOL(syscall);
long darwin_syscall(long number) {
    switch (number) {
    case 20: return getpid();           // SYS_getpid
    case 24: return getuid();           // SYS_getuid
    case 25: return geteuid();          // SYS_geteuid
    case 39: return getppid();          // SYS_getppid
    case 286:                           // SYS_gettid: the thread's, as thread_selfid
    case 372: return gettid();          // SYS_thread_selfid
    default: break;
    }
    static _Atomic int warned;
    if (!atomic_exchange(&warned, 1))
        fprintf(stderr, "perry: warning: syscall %ld is not implemented\n", number);
    errno = ENOSYS;
    return -1;
}

// MARK: - Time zones

// time.h's zone globals, Darwin's own: tzset fills them from Linux's.
char *darwin_tzname[2] DARWIN_SYMBOL(tzname) = { "GMT", "GMT" };
long darwin_timezone DARWIN_SYMBOL(timezone) = 0;
int darwin_daylight DARWIN_SYMBOL(daylight) = 0;

void darwin_tzset(void) DARWIN_SYMBOL(tzset);
void darwin_tzset(void) {
    tzset();
    darwin_tzname[0] = tzname[0];
    darwin_tzname[1] = tzname[1];
    darwin_timezone = timezone;
    darwin_daylight = daylight;
}
