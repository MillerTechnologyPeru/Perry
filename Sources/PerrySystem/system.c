// Clocks, Mach time, memory mapping and system information with Darwin's
// ABI over glibc's: clock IDs, mmap and msync flags, struct utsname and
// sysconf names differ.

#define _GNU_SOURCE
#include "PerrySystem.h"

#include <errno.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/utsname.h>
#include <time.h>
#include <unistd.h>

// MARK: - Clocks

enum {
    DARWIN_CLOCK_REALTIME = 0,
    DARWIN_CLOCK_MONOTONIC_RAW = 4,
    DARWIN_CLOCK_MONOTONIC_RAW_APPROX = 5,
    DARWIN_CLOCK_MONOTONIC = 6,
    DARWIN_CLOCK_UPTIME_RAW = 8,
    DARWIN_CLOCK_UPTIME_RAW_APPROX = 9,
    DARWIN_CLOCK_PROCESS_CPUTIME_ID = 12,
    DARWIN_CLOCK_THREAD_CPUTIME_ID = 16,
};

// Darwin's monotonic clock counts sleep (Linux's boot time); its uptime
// clocks do not (Linux's monotonic ones).
static int clock_to_linux(int clock) {
    switch (clock) {
    case DARWIN_CLOCK_REALTIME: return CLOCK_REALTIME;
    case DARWIN_CLOCK_MONOTONIC: return CLOCK_BOOTTIME;
    case DARWIN_CLOCK_MONOTONIC_RAW:
    case DARWIN_CLOCK_MONOTONIC_RAW_APPROX: return CLOCK_MONOTONIC_RAW;
    case DARWIN_CLOCK_UPTIME_RAW:
    case DARWIN_CLOCK_UPTIME_RAW_APPROX: return CLOCK_MONOTONIC;
    case DARWIN_CLOCK_PROCESS_CPUTIME_ID: return CLOCK_PROCESS_CPUTIME_ID;
    case DARWIN_CLOCK_THREAD_CPUTIME_ID: return CLOCK_THREAD_CPUTIME_ID;
    default: return -1;
    }
}

int darwin_clock_gettime(int clock, struct timespec *time) DARWIN_SYMBOL(clock_gettime);
int darwin_clock_gettime(int clock, struct timespec *time) {
    int linux_clock = clock_to_linux(clock);
    if (linux_clock < 0) {
        errno = EINVAL;
        return -1;
    }
    return clock_gettime(linux_clock, time);
}

int darwin_clock_getres(int clock, struct timespec *resolution) DARWIN_SYMBOL(clock_getres);
int darwin_clock_getres(int clock, struct timespec *resolution) {
    int linux_clock = clock_to_linux(clock);
    if (linux_clock < 0) {
        errno = EINVAL;
        return -1;
    }
    return clock_getres(linux_clock, resolution);
}

static uint64_t nanoseconds(int linux_clock) {
    struct timespec time;
    clock_gettime(linux_clock, &time);
    return (uint64_t)time.tv_sec * 1000000000ull + (uint64_t)time.tv_nsec;
}

uint64_t darwin_clock_gettime_nsec_np(int clock) DARWIN_SYMBOL(clock_gettime_nsec_np);
uint64_t darwin_clock_gettime_nsec_np(int clock) {
    int linux_clock = clock_to_linux(clock);
    if (linux_clock < 0) {
        errno = EINVAL;
        return 0;
    }
    return nanoseconds(linux_clock);
}

// MARK: - Mach time

// Mach time ticks in nanoseconds here: a timebase of 1/1.
typedef struct {
    uint32_t numer;
    uint32_t denom;
} darwin_timebase_info;

uint64_t darwin_mach_absolute_time(void) DARWIN_SYMBOL(mach_absolute_time);
uint64_t darwin_mach_absolute_time(void) {
    return nanoseconds(CLOCK_MONOTONIC);
}

uint64_t darwin_mach_approximate_time(void) DARWIN_SYMBOL(mach_approximate_time);
uint64_t darwin_mach_approximate_time(void) {
    return nanoseconds(CLOCK_MONOTONIC_COARSE);
}

uint64_t darwin_mach_continuous_time(void) DARWIN_SYMBOL(mach_continuous_time);
uint64_t darwin_mach_continuous_time(void) {
    return nanoseconds(CLOCK_BOOTTIME);
}

uint64_t darwin_mach_continuous_approximate_time(void) DARWIN_SYMBOL(mach_continuous_approximate_time);
uint64_t darwin_mach_continuous_approximate_time(void) {
    return nanoseconds(CLOCK_BOOTTIME);
}

int darwin_mach_timebase_info(darwin_timebase_info *info) DARWIN_SYMBOL(mach_timebase_info);
int darwin_mach_timebase_info(darwin_timebase_info *info) {
    info->numer = 1;
    info->denom = 1;
    return 0;   // KERN_SUCCESS
}

// MARK: - Memory mapping

enum {
    DARWIN_MAP_NOCACHE = 0x400,
    DARWIN_MAP_JIT = 0x800,
    DARWIN_MAP_ANON = 0x1000,
    DARWIN_MAP_NORESERVE = 0x40,
    DARWIN_MAP_RESILIENT_CODESIGN = 0x2000,
    DARWIN_MAP_RESILIENT_MEDIA = 0x4000,
    DARWIN_MS_SYNC = 0x10,
    DARWIN_MS_KILLPAGES = 0x4,
    DARWIN_MS_DEACTIVATE = 0x8,
    DARWIN_MADV_FREE = 5,
    DARWIN_MADV_ZERO_WIRED_PAGES = 6,
    DARWIN_MADV_FREE_REUSABLE = 7,
    DARWIN_MADV_FREE_REUSE = 8,
    DARWIN_MADV_CAN_REUSE = 9,
};

#if defined(__arm__)
// Darwin's armv7 passes mmap's 64-bit offset differently from glibc's ABI,
// so the exported _mmap is an adapter (thunks_arm.S) that calls this.
#define MMAP_SYMBOL __asm__("perry_mmap") __attribute__((visibility("hidden"), used))
#else
#define MMAP_SYMBOL DARWIN_SYMBOL(mmap)
#endif

void *darwin_mmap(void *address, size_t length, int protection, int flags, int fd, off_t offset) MMAP_SYMBOL;
void *darwin_mmap(void *address, size_t length, int protection, int flags, int fd, off_t offset) {
    int linux_flags = flags & (MAP_SHARED | MAP_PRIVATE | MAP_FIXED);
    if (flags & DARWIN_MAP_ANON) {
        linux_flags |= MAP_ANONYMOUS;
        // Anonymous maps may carry a VM tag where the descriptor goes.
        fd = -1;
    }
    if (flags & DARWIN_MAP_NORESERVE)
        linux_flags |= MAP_NORESERVE;
    return mmap(address, length, protection, linux_flags, fd, offset);
}

int darwin_msync(void *address, size_t length, int flags) DARWIN_SYMBOL(msync);
int darwin_msync(void *address, size_t length, int flags) {
    int linux_flags = flags & (MS_ASYNC | MS_INVALIDATE);
    if (flags & DARWIN_MS_SYNC)
        linux_flags |= MS_SYNC;
    if (!(linux_flags & (MS_SYNC | MS_ASYNC)))
        linux_flags |= MS_ASYNC;
    return msync(address, length, linux_flags);
}

int darwin_madvise(void *address, size_t length, int advice) DARWIN_SYMBOL(madvise);
int darwin_madvise(void *address, size_t length, int advice) {
    switch (advice) {
    case DARWIN_MADV_FREE:
    case DARWIN_MADV_FREE_REUSABLE:
        return madvise(address, length, MADV_FREE);
    case DARWIN_MADV_ZERO_WIRED_PAGES:
    case DARWIN_MADV_FREE_REUSE:
    case DARWIN_MADV_CAN_REUSE:
        return 0;
    default:
        return madvise(address, length, advice);  // NORMAL through DONTNEED agree
    }
}

// MARK: - System information

struct darwin_utsname {
    char sysname[256];
    char nodename[256];
    char release[256];
    char version[256];
    char machine[256];
};

// The device the program believes it runs on: an iPhone, unless
// PERRY_DEVICE_MODEL names another.
const char *perry_device_model(void) {
    const char *model = getenv("PERRY_DEVICE_MODEL");
    return model && *model ? model : "iPhone17,1";
}

int darwin_uname(struct darwin_utsname *out) DARWIN_SYMBOL(uname);
int darwin_uname(struct darwin_utsname *out) {
    struct utsname names;
    if (uname(&names) != 0)
        return -1;
    memset(out, 0, sizeof(*out));
    strncpy(out->sysname, "Darwin", sizeof(out->sysname) - 1);
    strncpy(out->nodename, names.nodename, sizeof(out->nodename) - 1);
    strncpy(out->release, "24.0.0", sizeof(out->release) - 1);
    strncpy(out->version, "Darwin Kernel Version 24.0.0: Perry on Linux", sizeof(out->version) - 1);
    strncpy(out->machine, perry_device_model(), sizeof(out->machine) - 1);
    return 0;
}

// Darwin's sysconf names as glibc's.
static int sysconf_name_to_linux(int name) {
    switch (name) {
    case 1: return _SC_ARG_MAX;
    case 2: return _SC_CHILD_MAX;
    case 3: return _SC_CLK_TCK;
    case 4: return _SC_NGROUPS_MAX;
    case 5: return _SC_OPEN_MAX;
    case 6: return _SC_JOB_CONTROL;
    case 7: return _SC_SAVED_IDS;
    case 8: return _SC_VERSION;
    case 29: return _SC_PAGESIZE;
    case 56: return _SC_IOV_MAX;
    case 57: return _SC_NPROCESSORS_CONF;
    case 58: return _SC_NPROCESSORS_ONLN;
    case 70: return _SC_GETGR_R_SIZE_MAX;
    case 71: return _SC_GETPW_R_SIZE_MAX;
    case 72: return _SC_HOST_NAME_MAX;
    case 73: return _SC_LOGIN_NAME_MAX;
    case 93: return _SC_THREAD_STACK_MIN;
    case 101: return _SC_TTY_NAME_MAX;
    case 200: return _SC_PHYS_PAGES;
    default: return -1;
    }
}

long darwin_sysconf(int name) DARWIN_SYMBOL(sysconf);
long darwin_sysconf(int name) {
    int linux_name = sysconf_name_to_linux(name);
    if (linux_name < 0) {
        errno = EINVAL;
        return -1;
    }
    return sysconf(linux_name);
}
