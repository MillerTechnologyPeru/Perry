#define _GNU_SOURCE

// libPerryCXX: the provider for /usr/lib/libc++.1.dylib and
// /usr/lib/libc++abi.dylib, over LLVM's libc++ and libc++abi built as
// Apple builds them for arm64 (libperry-c++, see the Dockerfile).
//
// Darwin's libc++ is LLVM's, with the same Itanium mangling and the same
// std::__1 inline namespace, so its imports bind by name ("__ZNSt3__1…" is
// "_ZNSt3__1…"). Each library is opened on its own: the process already
// has libstdc++, whose __cxa functions and type_info vtables share
// libc++abi's names but are not the same objects.

#include "PerryCXX.h"
#include "perry_wrapped.h"

#include <dlfcn.h>
#include <errno.h>
#include <limits.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static perry_wrapped_library cxx = PERRY_WRAPPED_SONAME("libperry-c++.so.1");
static perry_wrapped_library cxxabi = PERRY_WRAPPED_SONAME("libperry-c++abi.so.1");

// Darwin's typed operator new and delete take the allocated type's
// descriptor as an extra last argument, for its allocator to sort memory
// by; the plain operators, which ignore it, stand in for them.
static const char type_descriptor[] = "St19__type_descriptor_t";

static void *library_symbol(const char *name) {
    void *symbol = perry_wrapped_symbol(&cxx, name, NULL);
    return symbol ? symbol : perry_wrapped_symbol(&cxxabi, name, NULL);
}

// MARK: Locks

// A std::mutex, recursive_mutex or condition_variable that Darwin code
// declares is a Darwin pthread_mutex_t or pthread_cond_t, laid out as
// Darwin's and initialized in place by inlined constructors; libperry-c++'s
// own members would hand it to glibc. These members take it to Perry's
// Darwin pthread functions in libPerrySystem instead.

typedef struct { int64_t signature; char opaque[56]; } darwin_mutex;
typedef struct { int64_t signature; char opaque[40]; } darwin_cond;
typedef struct { int64_t signature; char opaque[8]; } darwin_mutexattr;
/// std::unique_lock<std::mutex>: the mutex, and whether it is held.
typedef struct { darwin_mutex *mutex; _Bool owns; } unique_lock;

static struct {
    int (*mutex_init)(darwin_mutex *, const darwin_mutexattr *);
    int (*mutex_destroy)(darwin_mutex *);
    int (*mutex_lock)(darwin_mutex *);
    int (*mutex_trylock)(darwin_mutex *);
    int (*mutex_unlock)(darwin_mutex *);
    int (*mutexattr_init)(darwin_mutexattr *);
    int (*mutexattr_settype)(darwin_mutexattr *, int);
    int (*mutexattr_destroy)(darwin_mutexattr *);
    int (*cond_destroy)(darwin_cond *);
    int (*cond_wait)(darwin_cond *, darwin_mutex *);
    int (*cond_timedwait)(darwin_cond *, darwin_mutex *, const struct timespec *);
    int (*cond_signal)(darwin_cond *);
    int (*cond_broadcast)(darwin_cond *);
} darwin;

/// libPerrySystem, which the loader has opened beside this library.
static void *system_symbol(const char *name) {
    static void *system;
    if (!system) {
        Dl_info info;
        char path[PATH_MAX];
        if (!dladdr((void *)&system_symbol, &info) || !info.dli_fname) abort();
        snprintf(path, sizeof(path), "%s", info.dli_fname);
        char *slash = strrchr(path, '/');
        snprintf(slash ? slash + 1 : path, sizeof(path) - (size_t)(slash ? slash + 1 - path : 0), "libPerrySystem.so");
        system = dlopen(path, RTLD_NOW | RTLD_LOCAL);
        if (!system) { fprintf(stderr, "perry: libc++: %s\n", dlerror()); abort(); }
    }
    void *symbol = dlsym(system, name);
    if (!symbol) { fprintf(stderr, "perry: libc++: no %s in libPerrySystem\n", name); abort(); }
    return symbol;
}

static void load_darwin(void) {
    static _Bool loaded;
    if (loaded) return;
    darwin.mutex_init = system_symbol("_pthread_mutex_init");
    darwin.mutex_destroy = system_symbol("_pthread_mutex_destroy");
    darwin.mutex_lock = system_symbol("_pthread_mutex_lock");
    darwin.mutex_trylock = system_symbol("_pthread_mutex_trylock");
    darwin.mutex_unlock = system_symbol("_pthread_mutex_unlock");
    darwin.mutexattr_init = system_symbol("_pthread_mutexattr_init");
    darwin.mutexattr_settype = system_symbol("_pthread_mutexattr_settype");
    darwin.mutexattr_destroy = system_symbol("_pthread_mutexattr_destroy");
    darwin.cond_destroy = system_symbol("_pthread_cond_destroy");
    darwin.cond_wait = system_symbol("_pthread_cond_wait");
    darwin.cond_timedwait = system_symbol("_pthread_cond_timedwait");
    darwin.cond_signal = system_symbol("_pthread_cond_signal");
    darwin.cond_broadcast = system_symbol("_pthread_cond_broadcast");
    loaded = 1;
}

/// libc++ reports a failed lock as std::system_error, which nothing here
/// can throw; Darwin's would end the process all the same.
static void lock_failed(const char *what, int error) {
    fprintf(stderr, "perry: libc++: %s failed: %s\n", what, strerror(error));
    abort();
}

static void mutex_lock(darwin_mutex *mutex) {
    load_darwin();
    int error = darwin.mutex_lock(mutex);
    if (error) lock_failed("mutex lock", error);
}
static _Bool mutex_try_lock(darwin_mutex *mutex) { load_darwin(); return darwin.mutex_trylock(mutex) == 0; }
static void mutex_unlock(darwin_mutex *mutex) { load_darwin(); darwin.mutex_unlock(mutex); }
static void mutex_destroy(darwin_mutex *mutex) { load_darwin(); darwin.mutex_destroy(mutex); }

static void recursive_mutex_init(darwin_mutex *mutex) {
    load_darwin();
    darwin_mutexattr attributes;
    darwin.mutexattr_init(&attributes);
    darwin.mutexattr_settype(&attributes, 2); // PTHREAD_MUTEX_RECURSIVE on Darwin
    int error = darwin.mutex_init(mutex, &attributes);
    darwin.mutexattr_destroy(&attributes);
    if (error) lock_failed("recursive_mutex constructor", error);
}

static void cond_notify_one(darwin_cond *cond) { load_darwin(); darwin.cond_signal(cond); }
static void cond_notify_all(darwin_cond *cond) { load_darwin(); darwin.cond_broadcast(cond); }
static void cond_destroy(darwin_cond *cond) { load_darwin(); darwin.cond_destroy(cond); }

static void cond_wait(darwin_cond *cond, unique_lock *lock) {
    load_darwin();
    if (!lock->owns) lock_failed("condition_variable::wait: mutex not locked", EPERM);
    int error = darwin.cond_wait(cond, lock->mutex);
    if (error) lock_failed("condition_variable wait", error);
}

/// __do_timed_wait: the deadline is nanoseconds of the system clock.
static void cond_timed_wait(darwin_cond *cond, unique_lock *lock, int64_t deadline) {
    load_darwin();
    if (!lock->owns) lock_failed("condition_variable::timed wait: mutex not locked", EPERM);
    struct timespec time = { .tv_sec = deadline / 1000000000, .tv_nsec = deadline % 1000000000 };
    if (time.tv_nsec < 0) { time.tv_sec -= 1; time.tv_nsec += 1000000000; }
    int error = darwin.cond_timedwait(cond, lock->mutex, &time);
    if (error && error != ETIMEDOUT) lock_failed("condition_variable timed wait", error);
}

static const struct { const char *name; void *function; } locks[] = {
    { "__ZNSt3__15mutex4lockEv", (void *)mutex_lock },
    { "__ZNSt3__15mutex8try_lockEv", (void *)mutex_try_lock },
    { "__ZNSt3__15mutex6unlockEv", (void *)mutex_unlock },
    { "__ZNSt3__15mutexD1Ev", (void *)mutex_destroy },
    { "__ZNSt3__15mutexD2Ev", (void *)mutex_destroy },
    { "__ZNSt3__115recursive_mutexC1Ev", (void *)recursive_mutex_init },
    { "__ZNSt3__115recursive_mutexC2Ev", (void *)recursive_mutex_init },
    { "__ZNSt3__115recursive_mutexD1Ev", (void *)mutex_destroy },
    { "__ZNSt3__115recursive_mutexD2Ev", (void *)mutex_destroy },
    { "__ZNSt3__115recursive_mutex4lockEv", (void *)mutex_lock },
    { "__ZNSt3__115recursive_mutex8try_lockEv", (void *)mutex_try_lock },
    { "__ZNSt3__115recursive_mutex6unlockEv", (void *)mutex_unlock },
    { "__ZNSt3__118condition_variable10notify_oneEv", (void *)cond_notify_one },
    { "__ZNSt3__118condition_variable10notify_allEv", (void *)cond_notify_all },
    { "__ZNSt3__118condition_variableD1Ev", (void *)cond_destroy },
    { "__ZNSt3__118condition_variableD2Ev", (void *)cond_destroy },
    { "__ZNSt3__118condition_variable4waitERNS_11unique_lockINS_5mutexEEE", (void *)cond_wait },
    { "__ZNSt3__118condition_variable15__do_timed_waitERNS_11unique_lockINS_5mutexEEENS_6chrono10time_pointINS5_12system_clockENS5_8durationIxNS_5ratioILl1ELl1000000000EEEEEEE",
      (void *)cond_timed_wait },
};

__attribute__((visibility("default")))
void *perry_provider_symbol(const char *name) {
    for (size_t i = 0; i < sizeof(locks) / sizeof(locks[0]); i++) {
        if (strcmp(name, locks[i].name) == 0) return locks[i].function;
    }
    void *symbol = library_symbol(name);
    const char *typed = strstr(name, type_descriptor);
    if (!symbol && typed && (strncmp(name, "__Znw", 5) == 0 || strncmp(name, "__Zna", 5) == 0 ||
                             strncmp(name, "__Zdl", 5) == 0 || strncmp(name, "__Zda", 5) == 0)) {
        char plain[256];
        snprintf(plain, sizeof(plain), "%.*s%s", (int)(typed - name), name, typed + strlen(type_descriptor));
        symbol = library_symbol(plain);
    }
    return symbol;
}
