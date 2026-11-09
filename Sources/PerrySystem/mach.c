// The Mach calls runtimes such as Mono make: task and thread ports,
// semaphores, clocks, memory, and suspending threads to read and set their
// registers, which garbage collectors do. A thread's port is its Linux
// thread ID. Suspending a thread sends it a signal whose handler records
// the interrupted context and waits until the thread is resumed; its
// registers are read from and written to that context, in Darwin's
// layouts. Also dlopen and dlsym, which find symbols as the loader does,
// and the Mach-O section lookup.

#define _GNU_SOURCE
#include "PerrySystem.h"
#include "PerryContext.h"
#include "MachO.h"

#include <dirent.h>
#include <errno.h>
#include <linux/futex.h>
#include <pthread.h>
#include <semaphore.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/uio.h>
#include <sys/syscall.h>
#include <time.h>
#include <ucontext.h>
#include <unistd.h>

typedef uint32_t mach_port_t;
typedef int kern_return_t;

enum {
    KERN_SUCCESS = 0,
    KERN_INVALID_ADDRESS = 1,
    KERN_INVALID_ARGUMENT = 4,
    KERN_FAILURE = 5,
    KERN_RESOURCE_SHORTAGE = 6,
    KERN_ABORTED = 14,
    KERN_OPERATION_TIMED_OUT = 49,
    TASK_PORT = 0x103,
    HOST_PORT = 0x203,
};

static pid_t thread_id(void) { return (pid_t)syscall(SYS_gettid); }

// MARK: - Ports

mach_port_t darwin_mach_task_self DARWIN_SYMBOL(mach_task_self_) = TASK_PORT;

mach_port_t darwin_mach_thread_self(void) DARWIN_SYMBOL(mach_thread_self);
mach_port_t darwin_mach_thread_self(void) { return (mach_port_t)thread_id(); }

mach_port_t darwin_mach_host_self(void) DARWIN_SYMBOL(mach_host_self);
mach_port_t darwin_mach_host_self(void) { return HOST_PORT; }

mach_port_t darwin_pthread_mach_thread_np(pthread_t thread) DARWIN_SYMBOL(pthread_mach_thread_np);
mach_port_t darwin_pthread_mach_thread_np(pthread_t thread) {
    // glibc keeps the kernel thread ID in its thread descriptor; only the
    // calling thread's is asked for in practice.
    return pthread_equal(thread, pthread_self()) ? (mach_port_t)thread_id() : 0;
}

kern_return_t darwin_mach_port_deallocate(mach_port_t task, mach_port_t port) DARWIN_SYMBOL(mach_port_deallocate);
kern_return_t darwin_mach_port_deallocate(mach_port_t task, mach_port_t port) { (void)task; (void)port; return KERN_SUCCESS; }

kern_return_t darwin_task_for_pid(mach_port_t task, int pid, mach_port_t *target) DARWIN_SYMBOL(task_for_pid);
kern_return_t darwin_task_for_pid(mach_port_t task, int pid, mach_port_t *target) {
    (void)task;
    if (pid != getpid())
        return KERN_FAILURE;
    *target = TASK_PORT;
    return KERN_SUCCESS;
}

// MARK: - Memory

kern_return_t darwin_vm_allocate(mach_port_t task, uintptr_t *address, size_t size, int flags) DARWIN_SYMBOL(vm_allocate);
kern_return_t darwin_vm_allocate(mach_port_t task, uintptr_t *address, size_t size, int flags) {
    (void)task;
    // VM_FLAGS_ANYWHERE is 1; otherwise at the address given.
    void *hint = (flags & 1) ? NULL : (void *)*address;
    void *memory = hint ? mmap(hint, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE, -1, 0)
                        : perry_map_pages(size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (memory == MAP_FAILED)
        return KERN_RESOURCE_SHORTAGE;
    *address = (uintptr_t)memory;
    return KERN_SUCCESS;
}

kern_return_t darwin_vm_deallocate(mach_port_t task, uintptr_t address, size_t size) DARWIN_SYMBOL(vm_deallocate);
kern_return_t darwin_vm_deallocate(mach_port_t task, uintptr_t address, size_t size) {
    (void)task;
    if (size && munmap((void *)address, size) != 0)
        return KERN_INVALID_ADDRESS;
    return KERN_SUCCESS;
}

// Maps `size` bytes from `source_address` again at `*address` (fixed, or
// anywhere with VM_FLAGS_ANYWHERE): as a copy, which is the same for what
// is remapped here, read-only code such as Mono's trampoline pages. The
// copy keeps the source's protection.
kern_return_t darwin_vm_remap(mach_port_t target, uintptr_t *address, size_t size, uintptr_t mask, int flags, mach_port_t source,
                              uintptr_t source_address, int copy, int *current, int *maximum, unsigned inheritance)
    DARWIN_SYMBOL(vm_remap);
kern_return_t darwin_vm_remap(mach_port_t target, uintptr_t *address, size_t size, uintptr_t mask, int flags, mach_port_t source,
                              uintptr_t source_address, int copy, int *current, int *maximum, unsigned inheritance) {
    (void)target; (void)mask; (void)source; (void)copy; (void)inheritance;
    int protection = PROT_READ;
    FILE *maps = fopen("/proc/self/maps", "r");
    if (maps) {
        char line[512];
        while (fgets(line, sizeof(line), maps)) {
            unsigned long start, end;
            char perms[5];
            if (sscanf(line, "%lx-%lx %4s", &start, &end, perms) == 3 && source_address >= start && source_address < end) {
                protection = (perms[0] == 'r' ? PROT_READ : 0) | (perms[1] == 'w' ? PROT_WRITE : 0) | (perms[2] == 'x' ? PROT_EXEC : 0);
                break;
            }
        }
        fclose(maps);
    }
    void *hint = (flags & 1) ? NULL : (void *)*address;
    void *memory = mmap(hint, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | (hint ? MAP_FIXED : 0), -1, 0);
    if (memory == MAP_FAILED)
        return KERN_RESOURCE_SHORTAGE;
    memcpy(memory, (const void *)source_address, size);
    if (mprotect(memory, size, protection) != 0) {
        munmap(memory, size);
        return KERN_FAILURE;
    }
    if (protection & PROT_EXEC)
        __builtin___clear_cache((char *)memory, (char *)memory + size);
    *address = (uintptr_t)memory;
    // VM_PROT_READ 1, VM_PROT_WRITE 2, VM_PROT_EXECUTE 4, as Linux's.
    if (current)
        *current = protection;
    if (maximum)
        *maximum = protection;
    return KERN_SUCCESS;
}

kern_return_t darwin_mach_vm_allocate(mach_port_t task, uintptr_t *address, size_t size, int flags) DARWIN_SYMBOL(mach_vm_allocate);
kern_return_t darwin_mach_vm_allocate(mach_port_t task, uintptr_t *address, size_t size, int flags) {
    return darwin_vm_allocate(task, address, size, flags);
}

kern_return_t darwin_mach_vm_deallocate(mach_port_t task, uintptr_t address, size_t size) DARWIN_SYMBOL(mach_vm_deallocate);
kern_return_t darwin_mach_vm_deallocate(mach_port_t task, uintptr_t address, size_t size) {
    return darwin_vm_deallocate(task, address, size);
}

// VM_PROT_READ 1, VM_PROT_WRITE 2, VM_PROT_EXECUTE 4, as Linux's PROT_*.
// Setting the maximum protection has nothing to change here.
kern_return_t darwin_vm_protect(mach_port_t task, uintptr_t address, size_t size, int set_maximum, int protection)
    DARWIN_SYMBOL(vm_protect);
kern_return_t darwin_vm_protect(mach_port_t task, uintptr_t address, size_t size, int set_maximum, int protection) {
    (void)task;
    if (set_maximum)
        return KERN_SUCCESS;
    uintptr_t page = (uintptr_t)sysconf(_SC_PAGESIZE);
    uintptr_t start = address & ~(page - 1);
    if (mprotect((void *)start, size + (address - start), protection & 7) != 0)
        return errno == ENOMEM ? KERN_INVALID_ADDRESS : KERN_FAILURE;
    return KERN_SUCCESS;
}

// vm_region_basic_info_64, packed to 4 bytes as Darwin's.
#pragma pack(push, 4)
typedef struct {
    int protection;
    int max_protection;
    unsigned inheritance;
    unsigned shared;
    unsigned reserved;
    uint64_t offset;
    int behavior;
    unsigned short user_wired_count;
} darwin_vm_region_basic_info_64;
#pragma pack(pop)

enum {
    VM_REGION_BASIC_INFO_64 = 9,
    VM_REGION_BASIC_INFO_COUNT_64 = sizeof(darwin_vm_region_basic_info_64) / sizeof(int),
    VM_INHERIT_COPY = 1,
};

// The region that holds *address, or else the first one above it, from
// /proc/self/maps: its start and size, and VM_REGION_BASIC_INFO_64.
// Linux splits a region where Darwin might not, which callers walking the
// address space don't mind.
kern_return_t darwin_vm_region_64(mach_port_t task, uintptr_t *address, size_t *size, int flavor, int *info,
                                  uint32_t *count, mach_port_t *object_name) DARWIN_SYMBOL(vm_region_64);
kern_return_t darwin_vm_region_64(mach_port_t task, uintptr_t *address, size_t *size, int flavor, int *info,
                                  uint32_t *count, mach_port_t *object_name) {
    (void)task;
    if (flavor != VM_REGION_BASIC_INFO_64 || !count || *count < VM_REGION_BASIC_INFO_COUNT_64)
        return KERN_INVALID_ARGUMENT;
    FILE *maps = fopen("/proc/self/maps", "r");
    if (!maps)
        return KERN_FAILURE;
    kern_return_t result = KERN_INVALID_ADDRESS;
    char line[512];
    while (fgets(line, sizeof(line), maps)) {
        unsigned long start, end, offset;
        char perms[5];
        if (sscanf(line, "%lx-%lx %4s %lx", &start, &end, perms, &offset) != 4 || end <= *address)
            continue;
        int protection = (perms[0] == 'r' ? 1 : 0) | (perms[1] == 'w' ? 2 : 0) | (perms[2] == 'x' ? 4 : 0);
        darwin_vm_region_basic_info_64 basic = {
            .protection = protection,
            .max_protection = 7,
            .inheritance = VM_INHERIT_COPY,
            .shared = perms[3] == 's',
            .offset = offset,
        };
        memcpy(info, &basic, sizeof(basic));
        *count = VM_REGION_BASIC_INFO_COUNT_64;
        *address = start;
        *size = end - start;
        if (object_name)
            *object_name = 0;
        result = KERN_SUCCESS;
        break;
    }
    fclose(maps);
    return result;
}

// mach_vm_address_t and mach_vm_size_t are 64 bits, as vm_address_t is on arm64.
kern_return_t darwin_mach_vm_region(mach_port_t task, uintptr_t *address, size_t *size, int flavor, int *info,
                                    uint32_t *count, mach_port_t *object_name) DARWIN_SYMBOL(mach_vm_region);
kern_return_t darwin_mach_vm_region(mach_port_t task, uintptr_t *address, size_t *size, int flavor, int *info,
                                    uint32_t *count, mach_port_t *object_name) {
    return darwin_vm_region_64(task, address, size, flavor, info, count, object_name);
}

void darwin_sys_icache_invalidate(void *start, size_t length) DARWIN_SYMBOL(sys_icache_invalidate);
void darwin_sys_icache_invalidate(void *start, size_t length) {
    __builtin___clear_cache((char *)start, (char *)start + length);
}

// MARK: - Clocks

typedef struct { uint32_t tv_sec; int32_t tv_nsec; } mach_timespec;

kern_return_t darwin_host_get_clock_service(mach_port_t host, int clock, mach_port_t *service) DARWIN_SYMBOL(host_get_clock_service);
kern_return_t darwin_host_get_clock_service(mach_port_t host, int clock, mach_port_t *service) {
    (void)host;
    // SYSTEM_CLOCK 0 counts from boot; CALENDAR_CLOCK 1 is the time of day.
    *service = (mach_port_t)clock + 1;
    return KERN_SUCCESS;
}

kern_return_t darwin_clock_get_time(mach_port_t service, mach_timespec *time) DARWIN_SYMBOL(clock_get_time);
kern_return_t darwin_clock_get_time(mach_port_t service, mach_timespec *time) {
    struct timespec now;
    clock_gettime(service == 2 ? CLOCK_REALTIME : CLOCK_MONOTONIC, &now);
    time->tv_sec = (uint32_t)now.tv_sec;
    time->tv_nsec = (int32_t)now.tv_nsec;
    return KERN_SUCCESS;
}

// TIME_ABSOLUTE 0 sleeps until a time of the clock; TIME_RELATIVE 1 for a while.
kern_return_t darwin_clock_sleep(mach_port_t service, int type, mach_timespec time, mach_timespec *remaining) DARWIN_SYMBOL(clock_sleep);
kern_return_t darwin_clock_sleep(mach_port_t service, int type, mach_timespec time, mach_timespec *remaining) {
    struct timespec request = { time.tv_sec, time.tv_nsec };
    int result = type == 0 ? clock_nanosleep(service == 2 ? CLOCK_REALTIME : CLOCK_MONOTONIC, TIMER_ABSTIME, &request, NULL)
                           : nanosleep(&request, NULL);
    if (remaining)
        darwin_clock_get_time(service, remaining);
    return result == 0 ? KERN_SUCCESS : KERN_ABORTED;
}

// MARK: - Host statistics

// The host's memory is counted in iOS's 16 KB pages, read from Linux's
// /proc/meminfo, and its processor time from /proc/stat.
#if defined(__x86_64__)
enum { HOST_PAGE_SIZE = 0x1000 };     // an Intel Mac's
#else
enum { HOST_PAGE_SIZE = 0x4000 };
#endif

kern_return_t darwin_host_page_size(mach_port_t host, uintptr_t *size) DARWIN_SYMBOL(host_page_size);
kern_return_t darwin_host_page_size(mach_port_t host, uintptr_t *size) {
    (void)host;
    *size = HOST_PAGE_SIZE;
    return KERN_SUCCESS;
}

// A /proc/meminfo field, in host pages.
static uint32_t meminfo_pages(const char *field) {
    FILE *file = fopen("/proc/meminfo", "r");
    if (!file)
        return 0;
    char line[256];
    unsigned long long kilobytes = 0;
    size_t length = strlen(field);
    while (fgets(line, sizeof(line), file)) {
        if (strncmp(line, field, length) == 0 && line[length] == ':') {
            sscanf(line + length + 1, "%llu", &kilobytes);
            break;
        }
    }
    fclose(file);
    return (uint32_t)(kilobytes * 1024 / HOST_PAGE_SIZE);
}

enum { HOST_LOAD_INFO = 1, HOST_VM_INFO = 2, HOST_CPU_LOAD_INFO = 3, HOST_VM_INFO64 = 4 };

kern_return_t darwin_host_statistics(mach_port_t host, int flavor, uint32_t *info, uint32_t *count)
    DARWIN_SYMBOL(host_statistics);
kern_return_t darwin_host_statistics(mach_port_t host, int flavor, uint32_t *info, uint32_t *count) {
    (void)host;
    switch (flavor) {
    case HOST_VM_INFO:
    case HOST_VM_INFO64: {
        uint32_t needed = flavor == HOST_VM_INFO ? 15 : 38;
        if (*count < needed)
            return KERN_FAILURE;
        memset(info, 0, needed * sizeof(uint32_t));
        // free, active, inactive and wired, first in both layouts.
        info[0] = meminfo_pages("MemFree");
        info[1] = meminfo_pages("Active");
        info[2] = meminfo_pages("Inactive");
        info[3] = meminfo_pages("Unevictable") + meminfo_pages("Mlocked");
        *count = needed;
        return KERN_SUCCESS;
    }
    case HOST_CPU_LOAD_INFO: {
        if (*count < 4)
            return KERN_FAILURE;
        // Darwin's order: user, system, idle, nice.
        unsigned long long user = 0, nice = 0, system = 0, idle = 0;
        FILE *file = fopen("/proc/stat", "r");
        if (file) {
            if (fscanf(file, "cpu %llu %llu %llu %llu", &user, &nice, &system, &idle) != 4)
                user = nice = system = idle = 0;
            fclose(file);
        }
        info[0] = (uint32_t)user;
        info[1] = (uint32_t)system;
        info[2] = (uint32_t)idle;
        info[3] = (uint32_t)nice;
        *count = 4;
        return KERN_SUCCESS;
    }
    case HOST_LOAD_INFO: {
        if (*count < 6)
            return KERN_FAILURE;
        double loads[3] = {0, 0, 0};
        getloadavg(loads, 3);
        for (int i = 0; i < 3; i++) {
            info[i] = (uint32_t)(loads[i] * 1000);     // LOAD_SCALE
            info[3 + i] = 0;
        }
        *count = 6;
        return KERN_SUCCESS;
    }
    default:
        return KERN_INVALID_ARGUMENT;
    }
}

kern_return_t darwin_host_statistics64(mach_port_t host, int flavor, uint32_t *info, uint32_t *count)
    DARWIN_SYMBOL(host_statistics64);
kern_return_t darwin_host_statistics64(mach_port_t host, int flavor, uint32_t *info, uint32_t *count) {
    return darwin_host_statistics(host, flavor, info, count);
}

// MARK: - Semaphores

// A semaphore's port indexes this table; ports start at 1.
static sem_t *semaphores[4096];
static pthread_mutex_t semaphore_lock = PTHREAD_MUTEX_INITIALIZER;

static sem_t *semaphore(mach_port_t port) { return port > 0 && port <= 4096 ? semaphores[port - 1] : NULL; }

kern_return_t darwin_semaphore_create(mach_port_t task, mach_port_t *port, int policy, int value) DARWIN_SYMBOL(semaphore_create);
kern_return_t darwin_semaphore_create(mach_port_t task, mach_port_t *port, int policy, int value) {
    (void)task; (void)policy;
    sem_t *created = malloc(sizeof(sem_t));
    if (!created || sem_init(created, 0, (unsigned)value) != 0) {
        free(created);
        return KERN_INVALID_ARGUMENT;
    }
    pthread_mutex_lock(&semaphore_lock);
    for (mach_port_t i = 0; i < 4096; i++) {
        if (!semaphores[i]) {
            semaphores[i] = created;
            pthread_mutex_unlock(&semaphore_lock);
            *port = i + 1;
            return KERN_SUCCESS;
        }
    }
    pthread_mutex_unlock(&semaphore_lock);
    sem_destroy(created);
    free(created);
    return KERN_RESOURCE_SHORTAGE;
}

kern_return_t darwin_semaphore_destroy(mach_port_t task, mach_port_t port) DARWIN_SYMBOL(semaphore_destroy);
kern_return_t darwin_semaphore_destroy(mach_port_t task, mach_port_t port) {
    (void)task;
    pthread_mutex_lock(&semaphore_lock);
    sem_t *destroyed = semaphore(port);
    if (destroyed)
        semaphores[port - 1] = NULL;
    pthread_mutex_unlock(&semaphore_lock);
    if (!destroyed)
        return KERN_INVALID_ARGUMENT;
    sem_destroy(destroyed);
    free(destroyed);
    return KERN_SUCCESS;
}

kern_return_t darwin_semaphore_signal(mach_port_t port) DARWIN_SYMBOL(semaphore_signal);
kern_return_t darwin_semaphore_signal(mach_port_t port) {
    sem_t *target = semaphore(port);
    return target && sem_post(target) == 0 ? KERN_SUCCESS : KERN_INVALID_ARGUMENT;
}

kern_return_t darwin_semaphore_wait(mach_port_t port) DARWIN_SYMBOL(semaphore_wait);
kern_return_t darwin_semaphore_wait(mach_port_t port) {
    sem_t *target = semaphore(port);
    if (!target)
        return KERN_INVALID_ARGUMENT;
    return sem_wait(target) == 0 ? KERN_SUCCESS : KERN_ABORTED;
}

// Waits for at most `wait`, a relative time.
kern_return_t darwin_semaphore_timedwait(mach_port_t port, mach_timespec wait) DARWIN_SYMBOL(semaphore_timedwait);
kern_return_t darwin_semaphore_timedwait(mach_port_t port, mach_timespec wait) {
    sem_t *target = semaphore(port);
    if (!target)
        return KERN_INVALID_ARGUMENT;
    struct timespec deadline;
    clock_gettime(CLOCK_REALTIME, &deadline);
    deadline.tv_sec += wait.tv_sec;
    deadline.tv_nsec += wait.tv_nsec;
    if (deadline.tv_nsec >= 1000000000) {
        deadline.tv_sec++;
        deadline.tv_nsec -= 1000000000;
    }
    if (sem_timedwait(target, &deadline) == 0)
        return KERN_SUCCESS;
    return errno == ETIMEDOUT ? KERN_OPERATION_TIMED_OUT : KERN_ABORTED;
}

// MARK: - Suspending threads

// What a suspended thread's signal handler shares with the threads that
// suspend and resume it.
typedef struct suspension {
    pid_t thread;
    int count;                  // suspends not yet resumed
    ucontext_t *_Atomic context;  // while stopped in the handler
    sem_t stopped;
    _Atomic int resume;         // futex word: 1 lets the handler return
    _Atomic int inside;         // futex word: 1 while the thread is in the handler
    struct suspension *next;
} suspension;

static suspension *suspensions;
static pthread_mutex_t suspension_lock = PTHREAD_MUTEX_INITIALIZER;
static int suspend_signal;

static suspension *find_suspension(pid_t thread, int create) {
    for (suspension *entry = suspensions; entry; entry = entry->next)
        if (entry->thread == thread)
            return entry;
    if (!create)
        return NULL;
    suspension *entry = calloc(1, sizeof(*entry));
    entry->thread = thread;
    sem_init(&entry->stopped, 0, 0);
    entry->next = suspensions;
    suspensions = entry;
    return entry;
}

static void stop_here(int signal, siginfo_t *info, void *context) {
    (void)signal; (void)info;
    int saved = errno;
    // Entries are only added, never removed, so the list may be read here.
    suspension *entry = suspensions;
    pid_t self = thread_id();
    while (entry && entry->thread != self)
        entry = entry->next;
    if (entry) {
        atomic_store(&entry->inside, 1);
        atomic_store(&entry->context, (ucontext_t *)context);
        sem_post(&entry->stopped);
        while (!atomic_load(&entry->resume))
            syscall(SYS_futex, &entry->resume, FUTEX_WAIT_PRIVATE, 0, NULL, NULL, 0);
        atomic_store(&entry->context, NULL);
        atomic_store(&entry->inside, 0);
        syscall(SYS_futex, &entry->inside, FUTEX_WAKE_PRIVATE, 1, NULL, NULL, 0);
    }
    errno = saved;
}

// Lets a stopped thread go, and waits, for a second at most, until it is
// out of the handler: suspended again at once, as a garbage collector does
// between its phases, a thread still in the handler would take the new
// stop for the old one's wait and never say it had stopped. With the lock
// held.
static void release_stopped(suspension *entry) {
    atomic_store(&entry->resume, 1);
    syscall(SYS_futex, &entry->resume, FUTEX_WAKE_PRIVATE, 1, NULL, NULL, 0);
    struct timespec wait = { 0, 1000000 };
    for (int tries = 0; tries < 1000 && atomic_load(&entry->inside); tries++)
        syscall(SYS_futex, &entry->inside, FUTEX_WAIT_PRIVATE, 1, &wait, NULL, 0);
}

static void install_suspend_handler(void) {
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_sigaction = stop_here;
    action.sa_flags = SA_SIGINFO | SA_RESTART;
    sigfillset(&action.sa_mask);
    suspend_signal = SIGRTMIN + 4;
    sigaction(suspend_signal, &action, NULL);
}

kern_return_t darwin_thread_suspend(mach_port_t port) DARWIN_SYMBOL(thread_suspend);
kern_return_t darwin_thread_suspend(mach_port_t port) {
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    pthread_once(&once, install_suspend_handler);
    pid_t thread = (pid_t)port;
    if (thread == thread_id())
        return KERN_INVALID_ARGUMENT;
    pthread_mutex_lock(&suspension_lock);
    suspension *entry = find_suspension(thread, 1);
    if (entry->count++ > 0) {
        pthread_mutex_unlock(&suspension_lock);
        return KERN_SUCCESS;
    }
    atomic_store(&entry->resume, 0);
    if (syscall(SYS_tgkill, getpid(), thread, suspend_signal) != 0) {
        entry->count = 0;
        pthread_mutex_unlock(&suspension_lock);
        if (getenv("PERRY_TRACE_THREADS"))
            fprintf(stderr, "perry: thread_suspend: thread %d is gone: %s\n", thread, strerror(errno));
        return KERN_INVALID_ARGUMENT;
    }
    pthread_mutex_unlock(&suspension_lock);
    // A thread that blocks the signal never stops: give up on it after a
    // second, resumed already, so a signal it takes later doesn't stop it.
    struct timespec deadline;
    clock_gettime(CLOCK_REALTIME, &deadline);
    deadline.tv_sec += 1;
    int waited;
    while ((waited = sem_timedwait(&entry->stopped, &deadline)) != 0 && errno == EINTR) {}
    if (waited != 0) {
        if (getenv("PERRY_TRACE_THREADS")) {
            char path[64], name[32] = "?";
            snprintf(path, sizeof(path), "/proc/self/task/%d/comm", thread);
            FILE *file = fopen(path, "r");
            if (file) {
                if (fgets(name, sizeof(name), file))
                    name[strcspn(name, "\n")] = 0;
                fclose(file);
            }
            fprintf(stderr, "perry: thread_suspend: thread %d (%s) did not stop within a second\n", thread, name);
            char line[256];
            snprintf(path, sizeof(path), "/proc/self/task/%d/status", thread);
            if ((file = fopen(path, "r"))) {
                while (fgets(line, sizeof(line), file))
                    if (!strncmp(line, "State:", 6) || !strncmp(line, "SigPnd:", 7) || !strncmp(line, "SigBlk:", 7))
                        fprintf(stderr, "perry:   %s", line);
                fclose(file);
            }
            snprintf(path, sizeof(path), "/proc/self/task/%d/syscall", thread);
            if ((file = fopen(path, "r"))) {
                if (fgets(line, sizeof(line), file))
                    fprintf(stderr, "perry:   in system call: %s", line);
                fclose(file);
            }
        }
        pthread_mutex_lock(&suspension_lock);
        entry->count = 0;
        release_stopped(entry);
        pthread_mutex_unlock(&suspension_lock);
        return KERN_FAILURE;
    }
    return KERN_SUCCESS;
}

kern_return_t darwin_thread_resume(mach_port_t port) DARWIN_SYMBOL(thread_resume);
kern_return_t darwin_thread_resume(mach_port_t port) {
    pthread_mutex_lock(&suspension_lock);
    suspension *entry = find_suspension((pid_t)port, 0);
    if (!entry || entry->count == 0) {
        pthread_mutex_unlock(&suspension_lock);
        return KERN_FAILURE;
    }
    if (--entry->count == 0)
        release_stopped(entry);
    pthread_mutex_unlock(&suspension_lock);
    return KERN_SUCCESS;
}

// Interrupting a thread's system call: the suspension's signal already does.
// A thread's scheduling policy (its time constraints, its affinity) is
// taken and not acted on: Linux schedules the thread as it would.
kern_return_t darwin_thread_policy_set(mach_port_t thread, int flavor, const int32_t *policy, uint32_t count)
    DARWIN_SYMBOL(thread_policy_set);
kern_return_t darwin_thread_policy_set(mach_port_t thread, int flavor, const int32_t *policy, uint32_t count) {
    (void)thread, (void)flavor, (void)policy, (void)count;
    return KERN_SUCCESS;
}

kern_return_t darwin_thread_abort(mach_port_t port) DARWIN_SYMBOL(thread_abort);
kern_return_t darwin_thread_abort(mach_port_t port) { (void)port; return KERN_SUCCESS; }

kern_return_t darwin_thread_abort_safely(mach_port_t port) DARWIN_SYMBOL(thread_abort_safely);
kern_return_t darwin_thread_abort_safely(mach_port_t port) { (void)port; return KERN_SUCCESS; }

static ucontext_t *stopped_context(mach_port_t port) {
    pthread_mutex_lock(&suspension_lock);
    suspension *entry = find_suspension((pid_t)port, 0);
    ucontext_t *context = entry && entry->count > 0 ? atomic_load(&entry->context) : NULL;
    pthread_mutex_unlock(&suspension_lock);
    return context;
}

// The states are PerryContext.h's, for arm64 or armv7. 32-bit Darwin's
// ARM_THREAD_STATE32 is its ARM_THREAD_STATE.
static int is_thread_flavor(int flavor) {
    return flavor == DARWIN_THREAD_FLAVOR || (sizeof(void *) == 4 && flavor == 9);
}

static kern_return_t get_stopped_state(mach_port_t port, ucontext_t *context, int flavor, uint32_t *state, uint32_t *count);

// A thread that isn't suspended is stopped for the moment the registers are
// read, as Darwin does, which a collector that asks for the state of a
// thread it has not suspended counts on.
kern_return_t darwin_thread_get_state(mach_port_t port, int flavor, uint32_t *state, uint32_t *count) DARWIN_SYMBOL(thread_get_state);
kern_return_t darwin_thread_get_state(mach_port_t port, int flavor, uint32_t *state, uint32_t *count) {
    ucontext_t *context = stopped_context(port);
    if (context)
        return get_stopped_state(port, context, flavor, state, count);
    if (darwin_thread_suspend(port) != KERN_SUCCESS)
        return KERN_FAILURE;
    kern_return_t result = KERN_FAILURE;
    if ((context = stopped_context(port)))
        result = get_stopped_state(port, context, flavor, state, count);
    darwin_thread_resume(port);
    return result;
}

static kern_return_t get_stopped_state(mach_port_t port, ucontext_t *context, int flavor, uint32_t *state, uint32_t *count) {
    (void)port;
    if (is_thread_flavor(flavor) && *count >= DARWIN_THREAD_COUNT) {
        perry_context_get_thread(context, (darwin_thread_state *)state);
        *count = DARWIN_THREAD_COUNT;
        return KERN_SUCCESS;
    }
    if (flavor == DARWIN_FLOAT_FLAVOR && *count >= DARWIN_FLOAT_COUNT) {
        perry_context_get_float(context, (darwin_float_state *)state);
        *count = DARWIN_FLOAT_COUNT;
        return KERN_SUCCESS;
    }
    if (flavor == DARWIN_EXCEPTION_FLAVOR && *count >= DARWIN_EXCEPTION_COUNT) {
        perry_context_get_exception(context, (darwin_exception_state *)state);
        *count = DARWIN_EXCEPTION_COUNT;
        return KERN_SUCCESS;
    }
    return KERN_INVALID_ARGUMENT;
}

// The registers take effect when the thread resumes.
kern_return_t darwin_thread_set_state(mach_port_t port, int flavor, const uint32_t *state, uint32_t count) DARWIN_SYMBOL(thread_set_state);
kern_return_t darwin_thread_set_state(mach_port_t port, int flavor, const uint32_t *state, uint32_t count) {
    ucontext_t *context = stopped_context(port);
    if (!context)
        return KERN_FAILURE;
    if (is_thread_flavor(flavor) && count >= DARWIN_THREAD_COUNT) {
        perry_context_set_thread(context, (const darwin_thread_state *)state);
        return KERN_SUCCESS;
    }
    if (flavor == DARWIN_FLOAT_FLAVOR && count >= DARWIN_FLOAT_COUNT) {
        perry_context_set_float(context, (const darwin_float_state *)state);
        return KERN_SUCCESS;
    }
    return KERN_INVALID_ARGUMENT;
}

// MARK: - Threads and the task

// Whether a thread blocks the signal threads are suspended with: one of
// the host's own, as Mesa's and libdispatch's service threads are, which
// block every signal. They run none of the program's code, and can't be
// stopped.
static bool blocks_suspension(pid_t thread) {
    char path[64], line[256];
    snprintf(path, sizeof(path), "/proc/self/task/%d/status", thread);
    FILE *file = fopen(path, "r");
    if (!file)
        return false;
    unsigned long long blocked = 0;
    while (fgets(line, sizeof(line), file)) {
        if (strncmp(line, "SigBlk:", 7) == 0) {
            blocked = strtoull(line + 7, NULL, 16);
            break;
        }
    }
    fclose(file);
    return (blocked >> (SIGRTMIN + 4 - 1)) & 1;
}

// The process's threads, in memory vm_deallocate frees: those that can be
// suspended, which a garbage collector that lists them goes on to do to
// each.
kern_return_t darwin_task_threads(mach_port_t task, mach_port_t **list, uint32_t *count) DARWIN_SYMBOL(task_threads);
kern_return_t darwin_task_threads(mach_port_t task, mach_port_t **list, uint32_t *count) {
    (void)task;
    DIR *directory = opendir("/proc/self/task");
    if (!directory)
        return KERN_FAILURE;
    uint32_t capacity = 64, found = 0;
    mach_port_t *ports = malloc(capacity * sizeof(*ports));
    struct dirent *entry;
    while ((entry = readdir(directory))) {
        if (entry->d_name[0] < '0' || entry->d_name[0] > '9')
            continue;
        pid_t thread = (pid_t)atoi(entry->d_name);
        if (blocks_suspension(thread))
            continue;
        if (found == capacity)
            ports = realloc(ports, (capacity *= 2) * sizeof(*ports));
        ports[found++] = (mach_port_t)thread;
    }
    closedir(directory);
    uintptr_t address = 0;
    if (darwin_vm_allocate(TASK_PORT, &address, found * sizeof(*ports) + 1, 1) != KERN_SUCCESS) {
        free(ports);
        return KERN_RESOURCE_SHORTAGE;
    }
    memcpy((void *)address, ports, found * sizeof(*ports));
    free(ports);
    *list = (mach_port_t *)address;
    *count = found;
    return KERN_SUCCESS;
}

// THREAD_BASIC_INFO 3: times, a running or stopped state, the suspend count.
kern_return_t darwin_thread_info(mach_port_t port, int flavor, int32_t *info, uint32_t *count) DARWIN_SYMBOL(thread_info);
kern_return_t darwin_thread_info(mach_port_t port, int flavor, int32_t *info, uint32_t *count) {
    if (flavor != 3 || *count < 10)
        return KERN_INVALID_ARGUMENT;
    memset(info, 0, 10 * sizeof(int32_t));
    pthread_mutex_lock(&suspension_lock);
    suspension *entry = find_suspension((pid_t)port, 0);
    int suspended = entry ? entry->count : 0;
    pthread_mutex_unlock(&suspension_lock);
    info[6] = 1;                            // policy: POLICY_TIMESHARE
    info[7] = suspended ? 2 : 1;            // run_state: TH_STATE_STOPPED or RUNNING
    info[9] = suspended;                    // suspend_count
    *count = 10;
    return KERN_SUCCESS;
}

// TASK_VM_INFO 22's revisions grow by appending; the newest has 93
// natural_t's, the first 38 (up to phys_footprint).
enum { TASK_VM_INFO_FLAVOR = 22, TASK_VM_INFO_REV0_COUNT = 38, TASK_VM_INFO_MAX_COUNT = 93 };

// The process's virtual size, resident size and its peak, in bytes.
static void process_memory(uint64_t *virtual_size, uint64_t *resident, uint64_t *peak) {
    long pages = 0, resident_pages = 0;
    FILE *statm = fopen("/proc/self/statm", "r");
    if (statm) {
        if (fscanf(statm, "%ld %ld", &pages, &resident_pages) != 2)
            pages = resident_pages = 0;
        fclose(statm);
    }
    long page = sysconf(_SC_PAGESIZE);
    *virtual_size = (uint64_t)(pages * page);
    *resident = (uint64_t)(resident_pages * page);
    *peak = *resident;
    FILE *status = fopen("/proc/self/status", "r");
    if (status) {
        char line[256];
        unsigned long long kilobytes;
        while (fgets(line, sizeof(line), status))
            if (sscanf(line, "VmHWM: %llu kB", &kilobytes) == 1)
                *peak = kilobytes * 1024;
        fclose(status);
    }
}

// TASK_VM_INFO: the sizes, with the resident memory as the physical
// footprint (internal memory), which is what iOS limits a process by.
static kern_return_t task_vm_info(int32_t *info, uint32_t *count) {
    if (*count < TASK_VM_INFO_REV0_COUNT)
        return KERN_INVALID_ARGUMENT;
    uint32_t filled = *count < TASK_VM_INFO_MAX_COUNT ? *count : TASK_VM_INFO_MAX_COUNT;
    memset(info, 0, filled * sizeof(int32_t));
    uint64_t virtual_size, resident, peak;
    process_memory(&virtual_size, &resident, &peak);
    uint8_t *bytes = (uint8_t *)info;
    int32_t page = (int32_t)sysconf(_SC_PAGESIZE);
    memcpy(bytes + 0, &virtual_size, 8);        // virtual_size
    memcpy(bytes + 12, &page, 4);               // page_size
    memcpy(bytes + 16, &resident, 8);           // resident_size
    memcpy(bytes + 24, &peak, 8);               // resident_size_peak
    memcpy(bytes + 48, &resident, 8);           // internal
    memcpy(bytes + 56, &peak, 8);               // internal_peak
    memcpy(bytes + 144, &resident, 8);          // phys_footprint
    if (filled >= 42) {
        uint64_t min_address = 0x100000000, max_address = 0x1000000000000;
        memcpy(bytes + 152, &min_address, 8);
        memcpy(bytes + 160, &max_address, 8);
    }
    if (filled >= 44)
        memcpy(bytes + 168, &peak, 8);          // ledger_phys_footprint_peak
    *count = filled;
    return KERN_SUCCESS;
}

/// What the process may still allocate before the system would end it:
/// here the memory Linux counts as available.
size_t darwin_os_proc_available_memory(void) DARWIN_SYMBOL(os_proc_available_memory);
size_t darwin_os_proc_available_memory(void) {
    unsigned long long kilobytes = 0;
    FILE *meminfo = fopen("/proc/meminfo", "r");
    if (meminfo) {
        char line[256];
        while (fgets(line, sizeof(line), meminfo))
            if (sscanf(line, "MemAvailable: %llu kB", &kilobytes) == 1)
                break;
        fclose(meminfo);
    }
    return (size_t)(kilobytes * 1024);
}

// MACH_TASK_BASIC_INFO 20 and TASK_BASIC_INFO_64 5: the memory used. On
// arm64 TASK_BASIC_INFO_64 is TASK_BASIC_INFO_64_2, 18, laid out as 5.
kern_return_t darwin_task_info(mach_port_t task, int flavor, int32_t *info, uint32_t *count) DARWIN_SYMBOL(task_info);
kern_return_t darwin_task_info(mach_port_t task, int flavor, int32_t *info, uint32_t *count) {
    (void)task;
    if (flavor == TASK_VM_INFO_FLAVOR)
        return task_vm_info(info, count);
    if (flavor == 18)
        flavor = 5;
    if ((flavor != 20 && flavor != 5) || *count < 10)
        return KERN_INVALID_ARGUMENT;
    long pages = 0, resident = 0;
    FILE *statm = fopen("/proc/self/statm", "r");
    if (statm) {
        if (fscanf(statm, "%ld %ld", &pages, &resident) != 2)
            pages = resident = 0;
        fclose(statm);
    }
    long page = sysconf(_SC_PAGESIZE);
    memset(info, 0, *count * sizeof(int32_t));
    if (flavor == 20) {
        // virtual_size, resident_size, resident_size_max (64-bit), then times.
        uint64_t values[3] = { (uint64_t)(pages * page), (uint64_t)(resident * page), (uint64_t)(resident * page) };
        memcpy(info, values, sizeof(values));
        *count = 12;
    } else {
        // suspend_count, then virtual and resident sizes (64-bit, packed).
        uint64_t values[2] = { (uint64_t)(pages * page), (uint64_t)(resident * page) };
        memcpy(info + 1, values, sizeof(values));
        *count = 10;
    }
    return KERN_SUCCESS;
}

// MARK: - Mach-O sections

static const void *find_section(const void *header, const char *segment, const char *section);

// The section's header in the image's load commands, or NULL.
const struct darwin_section_64 *darwin_getsectbynamefromheader_64(const void *header, const char *segment, const char *section) {
    if (!header)
        return NULL;
    return perry_macho_is64(header) ? find_section(header, segment, section) : NULL;
}

// A section's header, either size, by segment and section name.
static const void *find_section(const void *header, const char *segment, const char *section) {
    const uint8_t *command = perry_macho_commands(header);
    for (uint32_t i = 0; i < perry_macho_command_count(header); i++, command = perry_macho_next(command)) {
        perry_macho_segment found;
        if (!perry_macho_segment_at(command, &found) || strncmp(found.name, segment, 16) != 0)
            continue;
        for (uint32_t j = 0; j < found.section_count; j++) {
            uint64_t addr, size;
            const uint8_t *entry = perry_macho_section(&found, j, &addr, &size);
            if (strncmp((const char *)entry, section, 16) == 0)
                return entry;
        }
    }
    return NULL;
}

// MARK: - dlopen

// A handle names a library by install name; the program's own is NULL.
typedef struct { char *name; } library_handle;

static __thread char *dl_error;

enum { DARWIN_RTLD_NEXT = -1, DARWIN_RTLD_DEFAULT = -2, DARWIN_RTLD_SELF = -3, DARWIN_RTLD_MAIN_ONLY = -5 };

void *darwin_dlopen(const char *path, int mode) DARWIN_SYMBOL(dlopen);
void *darwin_dlopen(const char *path, int mode) {
    (void)mode;
    library_handle *handle = calloc(1, sizeof(*handle));
    // The program, and libraries such as Mono's "__Internal" in it.
    if (path && *path && strcmp(path, "__Internal") != 0) {
        handle->name = strdup(path);
        // A Mach-O library of the app's own that isn't loaded yet is, with
        // what it links. Anything else is one of the system's, by name.
        if (path[0] == '/' && perry_system_load_library)
            perry_system_load_library(path);
    }
    return handle;
}

int darwin_dlclose(void *handle) DARWIN_SYMBOL(dlclose);
int darwin_dlclose(void *handle) {
    if ((intptr_t)handle < 0)
        return 0;
    library_handle *library = handle;
    if (library) {
        free(library->name);
        free(library);
    }
    return 0;
}

const char *darwin_dlerror(void) DARWIN_SYMBOL(dlerror);
const char *darwin_dlerror(void) {
    char *error = dl_error;
    dl_error = NULL;
    return error;
}

#if defined(__arm__)
// On armv7 a call from Darwin code that finds its stack misaligned reaches
// dlsym through perry_align_call (the loader's align_arm.S), which calls it
// with `blx r12`: the return address is then the trampoline's, and the
// program's own is the lr the trampoline pushed, above its saved r4, r5
// and r6, at the stack pointer r4 still holds. thunks_arm.S's _dlsym
// passes the return address and r4 here.
void *perry_dlsym_from(void *handle, const char *symbol, void *returned, const uint32_t *trampoline_frame);
static const void *dlsym_caller(void *returned, const uint32_t *frame) {
    const uint32_t *call = (const uint32_t *)((uintptr_t)returned & ~(uintptr_t)1) - 1;
    if (*call == 0xe12fff3c && frame)    // blx r12
        return (const void *)(uintptr_t)frame[3];
    return returned;
}
#define DLSYM_CALLER dlsym_caller(returned, trampoline_frame)
void *perry_dlsym_from(void *handle, const char *symbol, void *returned, const uint32_t *trampoline_frame) {
#else
void *darwin_dlsym(void *handle, const char *symbol) DARWIN_SYMBOL(dlsym);
#define DLSYM_CALLER __builtin_return_address(0)
void *darwin_dlsym(void *handle, const char *symbol) {
#endif
    if (!symbol || !perry_system_lookup)
        return NULL;
    size_t length = strlen(symbol);
    char *name = malloc(length + 2);
    name[0] = '_';
    memcpy(name + 1, symbol, length + 1);
    const char *library = (intptr_t)handle < 0 || !handle ? NULL : ((library_handle *)handle)->name;
    // RTLD_NEXT: what comes after the caller's own image, which may define
    // the symbol itself to wrap the one it is looking for.
    void *address = (intptr_t)handle == DARWIN_RTLD_NEXT && perry_system_lookup_after
        ? perry_system_lookup_after(DLSYM_CALLER, name) : perry_system_lookup(library, name);
    // A library's handle also finds what it re-exports and depends on.
    if (!address && library)
        address = perry_system_lookup(NULL, name);
    free(name);
    if (!address) {
        static __thread char message[256];
        snprintf(message, sizeof(message), "dlsym(%p, %s): symbol not found", handle, symbol);
        dl_error = message;
    }
    return address;
}

// MARK: - Hosts, exceptions and memory

// The host's basic information (HOST_BASIC_INFO, 1): its processors and
// memory, as the device PERRY_HW_MACHINE names reports them.
typedef struct {
    int32_t max_cpus, avail_cpus;
    uint32_t memory_size;
    int32_t cpu_type, cpu_subtype, cpu_threadtype, physical_cpu, physical_cpu_max, logical_cpu, logical_cpu_max;
    uint64_t max_mem;
} darwin_host_basic_info;

kern_return_t darwin_host_info(mach_port_t host, int flavor, int32_t *info, uint32_t *count) DARWIN_SYMBOL(host_info);
kern_return_t darwin_host_info(mach_port_t host, int flavor, int32_t *info, uint32_t *count) {
    (void)host;
    uint32_t words = sizeof(darwin_host_basic_info) / sizeof(int32_t);
    if (flavor != 1 || !info || !count || *count < words)
        return KERN_INVALID_ARGUMENT;
    long cpus = sysconf(_SC_NPROCESSORS_ONLN);
    uint64_t memory = (uint64_t)sysconf(_SC_PHYS_PAGES) * (uint64_t)sysconf(_SC_PAGESIZE);
    darwin_host_basic_info basic = {
        (int32_t)cpus, (int32_t)cpus, memory > UINT32_MAX ? UINT32_MAX : (uint32_t)memory,
        PERRY_CPU_TYPE, PERRY_CPU_SUBTYPE, 0, (int32_t)cpus, (int32_t)cpus, (int32_t)cpus, (int32_t)cpus, memory,
    };
    memcpy(info, &basic, sizeof(basic));
    *count = words;
    return KERN_SUCCESS;
}

// Exception ports: there are none, and none can be set. Crash reporters
// that find so fall back to signal handlers.
kern_return_t darwin_task_get_exception_ports(mach_port_t task, uint32_t mask, uint32_t *masks, uint32_t *count,
                                              mach_port_t *ports, int *behaviors, int *flavors)
    DARWIN_SYMBOL(task_get_exception_ports);
kern_return_t darwin_task_get_exception_ports(mach_port_t task, uint32_t mask, uint32_t *masks, uint32_t *count,
                                              mach_port_t *ports, int *behaviors, int *flavors) {
    (void)task, (void)mask, (void)masks, (void)ports, (void)behaviors, (void)flavors;
    if (count)
        *count = 0;
    return KERN_SUCCESS;
}

kern_return_t darwin_thread_get_exception_ports(mach_port_t thread, uint32_t mask, uint32_t *masks, uint32_t *count,
                                                mach_port_t *ports, int *behaviors, int *flavors)
    DARWIN_SYMBOL(thread_get_exception_ports);
kern_return_t darwin_thread_get_exception_ports(mach_port_t thread, uint32_t mask, uint32_t *masks, uint32_t *count,
                                                mach_port_t *ports, int *behaviors, int *flavors) {
    return darwin_task_get_exception_ports(thread, mask, masks, count, ports, behaviors, flavors);
}

#define MACH_FAILS(name, ...) \
    kern_return_t darwin_##name(__VA_ARGS__) DARWIN_SYMBOL(name); \
    kern_return_t darwin_##name(__VA_ARGS__) { return KERN_FAILURE; }

MACH_FAILS(task_set_exception_ports, mach_port_t task, uint32_t mask, mach_port_t port, int behavior, int flavor)
MACH_FAILS(task_swap_exception_ports, mach_port_t task, uint32_t mask, mach_port_t port, int behavior, int flavor,
           uint32_t *masks, uint32_t *count, mach_port_t *ports, int *behaviors, int *flavors)
MACH_FAILS(thread_swap_exception_ports, mach_port_t thread, uint32_t mask, mach_port_t port, int behavior, int flavor,
           uint32_t *masks, uint32_t *count, mach_port_t *ports, int *behaviors, int *flavors)
MACH_FAILS(exception_raise, mach_port_t port, mach_port_t thread, mach_port_t task, int exception, void *code, uint32_t count)
MACH_FAILS(exception_raise_state, mach_port_t port, int exception, void *code, uint32_t count, int *flavor,
           void *old_state, uint32_t old_count, void *new_state, uint32_t *new_count)
MACH_FAILS(exception_raise_state_identity, mach_port_t port, mach_port_t thread, mach_port_t task, int exception,
           void *code, uint32_t count, int *flavor, void *old_state, uint32_t old_count, void *new_state, uint32_t *new_count)
MACH_FAILS(mach_port_insert_right, mach_port_t task, mach_port_t name, mach_port_t port, int disposition)
MACH_FAILS(mach_port_mod_refs, mach_port_t task, mach_port_t name, int right, int delta)
MACH_FAILS(mach_port_move_member, mach_port_t task, mach_port_t member, mach_port_t after)
MACH_FAILS(mach_port_request_notification, mach_port_t task, mach_port_t name, int message_id, uint32_t sync,
           mach_port_t notify, int disposition, mach_port_t *previous)
MACH_FAILS(mach_make_memory_entry_64, mach_port_t task, uint64_t *size, uint64_t offset, int permission,
           mach_port_t *entry, mach_port_t parent)
MACH_FAILS(vm_map, mach_port_t task, uintptr_t *address, uintptr_t size, uintptr_t mask, int flags, mach_port_t object,
           uintptr_t offset, int copy, int current, int maximum, int inheritance)

// No ports can be made: there is no Mach IPC.
kern_return_t darwin_mach_port_allocate(mach_port_t task, int right, mach_port_t *name) DARWIN_SYMBOL(mach_port_allocate);
kern_return_t darwin_mach_port_allocate(mach_port_t task, int right, mach_port_t *name) {
    (void)task, (void)right;
    if (name)
        *name = 0;
    return KERN_RESOURCE_SHORTAGE;
}

// MACH_SEND_INVALID_DEST, MACH_RCV_INVALID_NAME: no port names anything.
int darwin_mach_msg(void *message, int option, uint32_t send_size, uint32_t receive_size, mach_port_t receive_name,
                    uint32_t timeout, mach_port_t notify) DARWIN_SYMBOL(mach_msg);
int darwin_mach_msg(void *message, int option, uint32_t send_size, uint32_t receive_size, mach_port_t receive_name,
                    uint32_t timeout, mach_port_t notify) {
    (void)message, (void)send_size, (void)receive_size, (void)receive_name, (void)timeout, (void)notify;
    return (option & 1) ? 0x10000003 : 0x10004002;
}

// MIG's NDR record, which marshalled messages begin with: little-endian,
// ASCII, IEEE floats.
const uint8_t darwin_NDR_record[8] DARWIN_SYMBOL(NDR_record) = { 0, 0, 0, 0, 1, 0, 0, 0 };

// iOS's 16 KB pages.
// arm64 iOS's pages are 16 KB, armv7's 4 KB.
uintptr_t darwin_vm_page_size DARWIN_SYMBOL(vm_page_size) = PERRY_PAGE_SIZE;
uintptr_t darwin_vm_page_mask DARWIN_SYMBOL(vm_page_mask) = PERRY_PAGE_SIZE - 1;

// Copies another address's memory, failing rather than faulting where none
// is mapped.
kern_return_t darwin_vm_read_overwrite(mach_port_t task, uintptr_t address, uintptr_t size, uintptr_t data,
                                       uintptr_t *out_size) DARWIN_SYMBOL(vm_read_overwrite);
kern_return_t darwin_vm_read_overwrite(mach_port_t task, uintptr_t address, uintptr_t size, uintptr_t data,
                                       uintptr_t *out_size) {
    (void)task;
    struct iovec local = { (void *)data, size }, remote = { (void *)address, size };
    ssize_t copied = syscall(SYS_process_vm_readv, getpid(), &local, 1UL, &remote, 1UL, 0UL);
    if (copied < 0 || (uintptr_t)copied != size)
        return KERN_INVALID_ADDRESS;
    if (out_size)
        *out_size = size;
    return KERN_SUCCESS;
}

// mach_vm_read_overwrite: the same, with 64-bit addresses, which
// vm_address_t is on arm64.
kern_return_t darwin_mach_vm_read_overwrite(mach_port_t task, uintptr_t address, uintptr_t size, uintptr_t data,
                                            uintptr_t *out_size) DARWIN_SYMBOL(mach_vm_read_overwrite);
kern_return_t darwin_mach_vm_read_overwrite(mach_port_t task, uintptr_t address, uintptr_t size, uintptr_t data,
                                            uintptr_t *out_size) {
    return darwin_vm_read_overwrite(task, address, size, data, out_size);
}

// The pthread for a thread port; only the calling thread's is known.
pthread_t darwin_pthread_from_mach_thread_np(mach_port_t port) DARWIN_SYMBOL(pthread_from_mach_thread_np);
pthread_t darwin_pthread_from_mach_thread_np(mach_port_t port) {
    return port == (mach_port_t)thread_id() ? pthread_self() : 0;
}

// The architecture, as NXGetLocalArchInfo describes it.
typedef struct { const char *name; int cputype; int cpusubtype; int byteorder; const char *description; } darwin_arch_info;
#if defined(__arm__)
static const darwin_arch_info local_arch_info = { "armv7", PERRY_CPU_TYPE, PERRY_CPU_SUBTYPE, 1, "arm v7" };
#else
static const darwin_arch_info local_arch_info = { "arm64", PERRY_CPU_TYPE, PERRY_CPU_SUBTYPE, 1, "ARM64" };
#endif

const darwin_arch_info *darwin_NXGetLocalArchInfo(void) DARWIN_SYMBOL(NXGetLocalArchInfo);
const darwin_arch_info *darwin_NXGetLocalArchInfo(void) { return &local_arch_info; }

const darwin_arch_info *darwin_NXGetArchInfoFromCpuType(int type, int subtype) DARWIN_SYMBOL(NXGetArchInfoFromCpuType);
const darwin_arch_info *darwin_NXGetArchInfoFromCpuType(int type, int subtype) {
    (void)subtype;
    return type == local_arch_info.cputype ? &local_arch_info : NULL;
}

// The 32-bit header's lookup: a 64-bit image has no 32-bit segments, so
// nothing is found there, as on 64-bit Darwin.
const void *darwin_getsectbynamefromheader(const void *header, const char *segment, const char *section)
    DARWIN_SYMBOL(getsectbynamefromheader);
const void *darwin_getsectbynamefromheader(const void *header, const char *segment, const char *section) {
    return header && !perry_macho_is64(header) ? find_section(header, segment, section) : NULL;
}
