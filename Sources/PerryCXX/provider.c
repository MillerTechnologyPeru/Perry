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
#include <pthread.h>
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

enum { DARWIN_ETIMEDOUT = 60 };

/// libc++ reports a failed lock as std::system_error, which nothing here
/// can throw; Darwin's would end the process all the same.
static void lock_failed(const char *what, int error) {
    fprintf(stderr, "perry: libc++: %s failed: Darwin error %d\n", what, error);
    abort();
}

static void mutex_lock(darwin_mutex *mutex) {
    load_darwin();
    int error = darwin.mutex_lock(mutex);
    if (error) lock_failed("mutex lock", error);
}
static _Bool mutex_try_lock(darwin_mutex *mutex) { load_darwin(); return darwin.mutex_trylock(mutex) == 0; }
static void mutex_unlock(darwin_mutex *mutex) { load_darwin(); darwin.mutex_unlock(mutex); }
// Apple's arm64 C++ ABI has constructors and destructors return this,
// which callers use: these return the object they were given.
static darwin_mutex *mutex_destroy(darwin_mutex *mutex) { load_darwin(); darwin.mutex_destroy(mutex); return mutex; }

static darwin_mutex *recursive_mutex_init(darwin_mutex *mutex) {
    load_darwin();
    darwin_mutexattr attributes;
    darwin.mutexattr_init(&attributes);
    darwin.mutexattr_settype(&attributes, 2); // PTHREAD_MUTEX_RECURSIVE on Darwin
    int error = darwin.mutex_init(mutex, &attributes);
    darwin.mutexattr_destroy(&attributes);
    if (error) lock_failed("recursive_mutex constructor", error);
    return mutex;
}

static void cond_notify_one(darwin_cond *cond) { load_darwin(); darwin.cond_signal(cond); }
static void cond_notify_all(darwin_cond *cond) { load_darwin(); darwin.cond_broadcast(cond); }
static darwin_cond *cond_destroy(darwin_cond *cond) { load_darwin(); darwin.cond_destroy(cond); return cond; }

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
    // Darwin's pthread_cond_timedwait answers in Darwin's errno values:
    // ETIMEDOUT is 60 there, not Linux's 110.
    int error = darwin.cond_timedwait(cond, lock->mutex, &time);
    if (error && error != DARWIN_ETIMEDOUT) lock_failed("condition_variable timed wait", error);
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

// MARK: std::thread's per-thread data

// std::thread's start-up, which Darwin code inlines from <thread>, keeps the
// new thread's __thread_struct in std::__thread_local_data()'s
// __thread_specific_ptr: it reads the pointer's key and calls Darwin's
// pthread_setspecific with it. libperry-c++'s own pointer holds a glibc key
// (4 bytes, numbered as glibc numbers them), which Darwin's functions read as
// another Darwin key, one some other library was given: OpenSSL's per-thread
// random generators ended up overwritten. Darwin code gets a pointer of its
// own here, with a Darwin key (8 bytes) from libPerrySystem, whose destructor
// deletes the thread's __thread_struct as libc++'s does.

/// __thread_specific_ptr<__thread_struct> as Darwin lays it out: its key.
typedef struct { unsigned long key; } darwin_thread_specific_ptr;

static darwin_thread_specific_ptr thread_data;
static pthread_once_t thread_data_once = PTHREAD_ONCE_INIT;
static void *(*thread_struct_destroy)(void *);
static void (*operator_delete)(void *);

/// A thread's __thread_struct, deleted as it exits.
static void thread_struct_at_exit(void *value) {
    if (!value) return;
    thread_struct_destroy(value);
    operator_delete(value);
}

static void make_thread_data(void) {
    int (*key_create)(unsigned long *, void (*)(void *)) =
        (int (*)(unsigned long *, void (*)(void *)))system_symbol("_pthread_key_create");
    thread_struct_destroy = (void *(*)(void *))library_symbol("__ZNSt3__115__thread_structD1Ev");
    operator_delete = (void (*)(void *))library_symbol("__ZdlPv");
    if (!thread_struct_destroy || !operator_delete || key_create(&thread_data.key, thread_struct_at_exit) != 0) {
        fprintf(stderr, "perry: libc++: no thread data key for Darwin code\n");
        abort();
    }
}

static darwin_thread_specific_ptr *thread_local_data(void) {
    pthread_once(&thread_data_once, make_thread_data);
    return &thread_data;
}

// MARK: std::thread's join and detach

// std::thread's constructor, which Darwin code inlines from <thread>, makes
// its thread with Darwin's pthread_create and keeps the pthread_t that one
// returns: on x86 not glibc's, but one of Darwin's layout (libPerrySystem's
// perry_pthread_to_darwin). libperry-c++'s join and detach would hand that to
// glibc, which waits on what it finds there for ever (Batman: Arkham City's
// thread pool, at exit); these hand it to Perry's Darwin pthread_join and
// pthread_detach. A failure, which libc++ reports as std::system_error,
// ends the process, as the locks' do.

/// std::thread: its pthread_t, 0 when it isn't joinable.
typedef struct { pthread_t handle; } darwin_thread;

static int (*darwin_join)(pthread_t, void **);
static int (*darwin_detach)(pthread_t);

static void load_threads(void) {
    if (darwin_join) return;
    darwin_detach = (int (*)(pthread_t))system_symbol("_pthread_detach");
    darwin_join = (int (*)(pthread_t, void **))system_symbol("_pthread_join");
}

static void thread_join(darwin_thread *thread) {
    load_threads();
    int error = thread->handle ? darwin_join(thread->handle, NULL) : EINVAL;
    if (error) lock_failed("thread::join", error);
    thread->handle = 0;
}

static void thread_detach(darwin_thread *thread) {
    load_threads();
    int error = thread->handle ? darwin_detach(thread->handle) : EINVAL;
    if (error) lock_failed("thread::detach", error);
    thread->handle = 0;
}

// MARK: std::future<void>'s shared state

// A promise<void>'s and future<void>'s shared state, __assoc_sub_state, holds
// a std::mutex and condition_variable: Darwin's sizes in Darwin code, whose
// inlined <future> reads its state word after them, and glibc's in
// libperry-c++'s own members, which also lock them with glibc. Darwin code
// gets these members instead, over Darwin's layout and Perry's Darwin
// pthread functions; subclasses the code makes itself (std::async's,
// packaged_task's) are laid out the same way. A promise broken before it
// is satisfied makes its future ready with no exception, and the misuse
// libc++ reports as future_error (a value set twice, a future taken twice,
// no state) ends the process.

/// __assoc_sub_state on arm64 Darwin: __shared_count's vtable and owner
/// count, then the exception, mutex, condition variable and state bits.
typedef struct {
    void **vtable;
    long shared_owners;     // owners - 1
    void *exception;        // std::exception_ptr
    darwin_mutex mutex;
    darwin_cond cond;
    unsigned state;
} assoc_sub_state;

enum { STATE_CONSTRUCTED = 1, STATE_FUTURE_ATTACHED = 2, STATE_READY = 4, STATE_DEFERRED = 8 };

static int (*darwin_cond_init)(darwin_cond *, const void *);
static void *(*operator_new)(size_t);
static void (*exception_increment)(void *);
static void (*exception_decrement)(void *);

static void load_future(void) {
    static _Bool loaded;
    if (loaded) return;
    load_darwin();
    darwin_cond_init = (int (*)(darwin_cond *, const void *))system_symbol("_pthread_cond_init");
    operator_new = (void *(*)(size_t))library_symbol("__Znwm");
    operator_delete = (void (*)(void *))library_symbol("__ZdlPv");
    exception_increment = (void (*)(void *))library_symbol("___cxa_increment_exception_refcount");
    exception_decrement = (void (*)(void *))library_symbol("___cxa_decrement_exception_refcount");
    if (!darwin_cond_init || !operator_new || !operator_delete || !exception_increment || !exception_decrement) {
        fprintf(stderr, "perry: libc++: std::future's state is missing a function\n");
        abort();
    }
    loaded = 1;
}

static void future_failed(const char *what) {
    fprintf(stderr, "perry: libc++: std::future: %s\n", what);
    abort();
}

static assoc_sub_state *state_destroy(assoc_sub_state *state) {
    load_future();
    darwin.cond_destroy(&state->cond);
    darwin.mutex_destroy(&state->mutex);
    if (state->exception) exception_decrement(state->exception);
    return state;
}

static void state_delete(assoc_sub_state *state) { operator_delete(state_destroy(state)); }

/// __on_zero_shared: delete this, through the object's own deleting
/// destructor.
static void state_on_zero_shared(assoc_sub_state *state) { ((void (*)(void *))state->vtable[1])(state); }

static void state_execute(assoc_sub_state *state) { (void)state; future_failed("no state to run"); }

/// vtable for __assoc_sub_state: offset to top, type info, then the
/// complete and deleting destructors, __on_zero_shared and __execute.
static void *state_vtable[6] = {
    0, 0, (void *)state_destroy, (void *)state_delete, (void *)state_on_zero_shared, (void *)state_execute,
};

static void *state_vtable_symbol(void) {
    if (!state_vtable[1]) state_vtable[1] = library_symbol("__ZTINSt3__117__assoc_sub_stateE");
    return state_vtable;
}

static void state_add_shared(assoc_sub_state *state) { __atomic_add_fetch(&state->shared_owners, 1, __ATOMIC_RELAXED); }

static void state_release_shared(assoc_sub_state *state) {
    if (__atomic_add_fetch(&state->shared_owners, -1, __ATOMIC_ACQ_REL) == -1)
        ((void (*)(void *))state->vtable[2])(state);
}

static void state_make_ready(assoc_sub_state *state, unsigned bits) {
    load_future();
    darwin.mutex_lock(&state->mutex);
    state->state |= bits;
    darwin.cond_broadcast(&state->cond);
    darwin.mutex_unlock(&state->mutex);
}

/// __sub_wait: runs a deferred function, else waits until ready, with the
/// lock held.
static void state_sub_wait(assoc_sub_state *state, unique_lock *lock) {
    load_future();
    if (state->state & STATE_READY) return;
    if (state->state & STATE_DEFERRED) {
        state->state &= ~(unsigned)STATE_DEFERRED;
        if (lock->owns) { darwin.mutex_unlock(lock->mutex); lock->owns = 0; }
        ((void (*)(void *))state->vtable[3])(state);
        return;
    }
    while (!(state->state & STATE_READY)) darwin.cond_wait(&state->cond, lock->mutex);
}

static void state_wait(assoc_sub_state *state) {
    load_future();
    darwin.mutex_lock(&state->mutex);
    unique_lock lock = { &state->mutex, 1 };
    state_sub_wait(state, &lock);
    if (lock.owns) darwin.mutex_unlock(&state->mutex);
}

/// set_exception(exception_ptr), which arm64 passes by reference.
static void state_set_exception(assoc_sub_state *state, void **exception) {
    load_future();
    darwin.mutex_lock(&state->mutex);
    if ((state->state & STATE_CONSTRUCTED) || state->exception) future_failed("promise already satisfied");
    state->exception = *exception;
    if (state->exception) exception_increment(state->exception);
    state->state |= STATE_READY;
    darwin.cond_broadcast(&state->cond);
    darwin.mutex_unlock(&state->mutex);
}

/// promise<void>: its state.
typedef struct { assoc_sub_state *state; } promise_void;

static promise_void *promise_init(promise_void *promise) {
    load_future();
    assoc_sub_state *state = operator_new(sizeof(assoc_sub_state));
    memset(state, 0, sizeof(*state));
    state->vtable = (void **)state_vtable_symbol() + 2;
    darwin.mutex_init(&state->mutex, NULL);
    darwin_cond_init(&state->cond, NULL);
    promise->state = state;
    return promise;
}

static promise_void *promise_destroy(promise_void *promise) {
    assoc_sub_state *state = promise->state;
    if (state) {
        if (!(state->state & STATE_CONSTRUCTED) && !state->exception && state->shared_owners > 0)
            state_make_ready(state, STATE_READY);
        state_release_shared(state);
    }
    return promise;
}

static void promise_set_value(promise_void *promise) {
    assoc_sub_state *state = promise->state;
    if (!state) future_failed("no state");
    load_future();
    darwin.mutex_lock(&state->mutex);
    if ((state->state & STATE_CONSTRUCTED) || state->exception) future_failed("promise already satisfied");
    state->state |= STATE_CONSTRUCTED | STATE_READY;
    darwin.cond_broadcast(&state->cond);
    darwin.mutex_unlock(&state->mutex);
}

/// get_future(): the future<void>, returned through x8 as a class with a
/// destructor is.
__attribute__((used)) static void promise_get_future_into(promise_void *promise, assoc_sub_state **future) {
    assoc_sub_state *state = promise->state;
    if (!state) future_failed("no state");
    load_future();
    darwin.mutex_lock(&state->mutex);
    if (state->state & STATE_FUTURE_ATTACHED) future_failed("future already retrieved");
    state_add_shared(state);
    state->state |= STATE_FUTURE_ATTACHED;
    darwin.mutex_unlock(&state->mutex);
    *future = state;
}

#if defined(__aarch64__)
__attribute__((naked)) static void promise_get_future(void) {
    __asm__("mov x1, x8\n\tb promise_get_future_into");
}
#endif

/// ~future<void>() and ~shared_future<void>(): the state let go.
static void *future_destroy(assoc_sub_state **future) {
    if (*future) state_release_shared(*future);
    return future;
}

static const struct { const char *name; void *function; } futures[] = {
    { "__ZNSt3__117__assoc_sub_state10__sub_waitERNS_11unique_lockINS_5mutexEEE", (void *)state_sub_wait },
    { "__ZNSt3__117__assoc_sub_state13set_exceptionESt13exception_ptr", (void *)state_set_exception },
    { "__ZNSt3__117__assoc_sub_state4waitEv", (void *)state_wait },
    { "__ZNSt3__117__assoc_sub_state9__executeEv", (void *)state_execute },
    { "__ZNSt3__117__assoc_sub_state16__on_zero_sharedEv", (void *)state_on_zero_shared },
    { "__ZNSt3__17promiseIvEC1Ev", (void *)promise_init },
    { "__ZNSt3__17promiseIvEC2Ev", (void *)promise_init },
    { "__ZNSt3__17promiseIvED1Ev", (void *)promise_destroy },
    { "__ZNSt3__17promiseIvED2Ev", (void *)promise_destroy },
    { "__ZNSt3__17promiseIvE9set_valueEv", (void *)promise_set_value },
#if defined(__aarch64__)
    { "__ZNSt3__17promiseIvE10get_futureEv", (void *)promise_get_future },
#endif
    { "__ZNSt3__16futureIvED1Ev", (void *)future_destroy },
    { "__ZNSt3__16futureIvED2Ev", (void *)future_destroy },
    { "__ZNSt3__113shared_futureIvED1Ev", (void *)future_destroy },
    { "__ZNSt3__113shared_futureIvED2Ev", (void *)future_destroy },
};

// MARK: ctype<char>'s table

// Darwin code's inlined ctype<char>::is reads its facet's table as Darwin's:
// 32-bit entries with <runetype.h>'s bits (_CTYPE_S for a space). Linux's
// libc++ builds the classic facet over glibc's 16-bit table with glibc's
// bits, where Darwin's space bit is something else, so a game's XML reader
// sees "\n\t" as text. The table is libPerrySystem's _DefaultRuneLocale's
// __runetype, which Darwin's classic_table is too; the classic facet is
// pointed at it before the program runs.

/// _DefaultRuneLocale.__runetype: after an 8-byte magic, a 32-byte encoding
/// name, two function pointers and the invalid rune.
static const uint32_t *darwin_ctype_table(void) {
    static const uint32_t *table;
    if (!table) {
        const uint8_t *locale = system_symbol("__DefaultRuneLocale");
        if (!locale) { fprintf(stderr, "perry: libc++: libPerrySystem has no _DefaultRuneLocale\n"); abort(); }
        table = (const uint32_t *)(locale + 60);
    }
    return table;
}

static const uint32_t *classic_table(void) { return darwin_ctype_table(); }

/// The classic locale's ctype<char>, whose table follows the facet's vtable
/// pointer and reference count, takes Darwin's table.
static void use_darwin_ctype_table(void) {
    static _Bool done;
    if (done) return;
    done = 1;
    const void *(*classic)(void) = (const void *(*)(void))library_symbol("__ZNSt3__16locale7classicEv");
    void *(*use_facet)(const void *, void *) = (void *(*)(const void *, void *))library_symbol("__ZNKSt3__16locale9use_facetERNS0_2idE");
    void *id = library_symbol("__ZNSt3__15ctypeIcE2idE");
    if (!classic || !use_facet || !id) return;
    void *facet = use_facet(classic(), id);
    if (facet) *(const uint32_t **)((uint8_t *)facet + 16) = darwin_ctype_table();
}

__attribute__((visibility("default")))
void *perry_provider_symbol(const char *name) {
    // Before Darwin code reads a locale's ctype<char>.
    if (strstr(name, "5ctypeIc") || strstr(name, "6locale7classic")) use_darwin_ctype_table();
    if (strcmp(name, "__ZNSt3__15ctypeIcE13classic_tableEv") == 0) return (void *)classic_table;
    if (strcmp(name, "__ZNSt3__119__thread_local_dataEv") == 0) return (void *)thread_local_data;
    if (strcmp(name, "__ZNSt3__16thread4joinEv") == 0) return (void *)thread_join;
    if (strcmp(name, "__ZNSt3__16thread6detachEv") == 0) return (void *)thread_detach;
    if (strcmp(name, "__ZTVNSt3__117__assoc_sub_stateE") == 0) return state_vtable_symbol();
    for (size_t i = 0; i < sizeof(futures) / sizeof(futures[0]); i++) {
        if (strcmp(name, futures[i].name) == 0) return futures[i].function;
    }
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
