// pthread synchronization with Darwin's ABI over glibc's.
//
// Darwin's objects are bigger and start with a signature word, which the
// static initializers set (PTHREAD_MUTEX_INITIALIZER is {0x32AAABA7}). Each
// Darwin object holds the glibc one after its signature (a condition, whose
// Darwin size leaves no room, holds a pointer to one), set up by the
// *_init functions or, for statically initialized objects, on first use.
// Error numbers come back in Darwin's numbering.

#define _GNU_SOURCE
#include "PerrySystem.h"

#include <errno.h>
#include <linux/futex.h>
#include <pthread.h>
#include <sched.h>
#include <stdbool.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

enum {
    // The signatures Darwin's static initializers set.
    SIG_MUTEX = 0x32AAABA7,
    SIG_MUTEX_RECURSIVE = 0x32AAABA2,
    SIG_MUTEX_ERRORCHECK = 0x32AAABA1,
    SIG_COND = 0x3CB0B1BB,
    SIG_RWLOCK = 0x2DA8B3B4,
    // Perry's: set up, and being set up, in a signature word.
#if __LP64__
    SIG_READY = 0x5045525259524459,     // "PERRYRDY"
    SIG_BUSY = 0x5045525259425359,      // "PERRYBSY"
#else
    SIG_READY = 0x50524459,             // "PRDY"
    SIG_BUSY = 0x50425359,              // "PBSY"
#endif
    // Darwin's attribute values that differ.
    DARWIN_DETACHED = 2,
    DARWIN_JOINABLE = 1,
    DARWIN_PROCESS_PRIVATE = 2,
    DARWIN_PROCESS_SHARED = 1,
};

// Darwin's sizes: a signature word, then the opaque bytes
// (sys/_pthread/_pthread_types.h), for 64-bit and 32-bit Darwin.
#if __LP64__
enum { MUTEX_SIZE = 64, MUTEXATTR_SIZE = 16, COND_SIZE = 48, CONDATTR_SIZE = 16,
       RWLOCK_SIZE = 200, RWLOCKATTR_SIZE = 24, ONCE_SIZE = 16 };
#else
enum { MUTEX_SIZE = 44, MUTEXATTR_SIZE = 12, COND_SIZE = 28, CONDATTR_SIZE = 8,
       RWLOCK_SIZE = 128, RWLOCKATTR_SIZE = 16, ONCE_SIZE = 8 };
#endif

typedef struct {
    _Atomic long sig;
    pthread_mutex_t value;
    char rest[MUTEX_SIZE - sizeof(long) - sizeof(pthread_mutex_t)];
} darwin_mutex;
typedef struct {
    long sig;
    pthread_mutexattr_t value;
    char rest[MUTEXATTR_SIZE - sizeof(long) - sizeof(pthread_mutexattr_t)];
} darwin_mutexattr;
typedef struct { _Atomic long sig; pthread_cond_t *_Atomic value; char rest[COND_SIZE - 2 * sizeof(long)]; } darwin_cond;
typedef struct {
    long sig;
    pthread_condattr_t value;
    char rest[CONDATTR_SIZE - sizeof(long) - sizeof(pthread_condattr_t)];
} darwin_condattr;
// A read-write lock also keeps the thread holding it for writing.
typedef struct {
    _Atomic long sig;
    pthread_rwlock_t value;
    _Atomic(pthread_t) writer;
    char rest[RWLOCK_SIZE - sizeof(long) - sizeof(pthread_rwlock_t) - sizeof(pthread_t)];
} darwin_rwlock;
typedef struct {
    long sig;
    pthread_rwlockattr_t value;
    char rest[RWLOCKATTR_SIZE - sizeof(long) - sizeof(pthread_rwlockattr_t)];
} darwin_rwlockattr;
typedef struct { long sig; _Atomic long state; } darwin_once;

_Static_assert(sizeof(darwin_mutex) == MUTEX_SIZE, "pthread_mutex_t has Darwin's size");
_Static_assert(sizeof(darwin_mutexattr) == MUTEXATTR_SIZE, "pthread_mutexattr_t has Darwin's size");
_Static_assert(sizeof(darwin_cond) == COND_SIZE, "pthread_cond_t has Darwin's size");
_Static_assert(sizeof(darwin_condattr) == CONDATTR_SIZE, "pthread_condattr_t has Darwin's size");
_Static_assert(sizeof(darwin_rwlock) == RWLOCK_SIZE, "pthread_rwlock_t has Darwin's size");
_Static_assert(sizeof(darwin_rwlockattr) == RWLOCKATTR_SIZE, "pthread_rwlockattr_t has Darwin's size");
_Static_assert(sizeof(darwin_once) == ONCE_SIZE, "pthread_once_t has Darwin's size");
// Darwin's pthread_attr_t is glibc's, which fits in it.
_Static_assert(sizeof(pthread_attr_t) <= (sizeof(long) == 8 ? 64 : 40), "pthread_attr_t fits Darwin's");

static int result(int linux_error) {
    return perry_darwin_errno_from_linux(linux_error);
}

// Runs `setup` once for an object whose signature is a static
// initializer's, while other threads wait. False if the object was never
// initialized.
static int ensure(_Atomic long *sig, long expected_static, void (*setup)(void *, long), void *object) {
    for (;;) {
        long current = atomic_load_explicit(sig, memory_order_acquire);
        if (current == SIG_READY)
            return 1;
        if (current == SIG_BUSY) {
            sched_yield();
            continue;
        }
        if (current != expected_static && !(expected_static == SIG_MUTEX &&
            (current == SIG_MUTEX_RECURSIVE || current == SIG_MUTEX_ERRORCHECK)))
            return 0;
        if (atomic_compare_exchange_strong(sig, &current, SIG_BUSY)) {
            setup(object, current);
            atomic_store_explicit(sig, SIG_READY, memory_order_release);
            return 1;
        }
    }
}

// MARK: - Mutexes

static void setup_static_mutex(void *object, long sig) {
    darwin_mutex *mutex = object;
    pthread_mutexattr_t attributes;
    pthread_mutexattr_init(&attributes);
    if (sig == SIG_MUTEX_RECURSIVE)
        pthread_mutexattr_settype(&attributes, PTHREAD_MUTEX_RECURSIVE);
    else if (sig == SIG_MUTEX_ERRORCHECK)
        pthread_mutexattr_settype(&attributes, PTHREAD_MUTEX_ERRORCHECK);
    pthread_mutex_init(&mutex->value, &attributes);
    pthread_mutexattr_destroy(&attributes);
}

static pthread_mutex_t *mutex_value(darwin_mutex *mutex) {
    return mutex && ensure(&mutex->sig, SIG_MUTEX, setup_static_mutex, mutex) ? &mutex->value : NULL;
}

int darwin_pthread_mutex_init(darwin_mutex *mutex, const darwin_mutexattr *attributes) DARWIN_SYMBOL(pthread_mutex_init);
int darwin_pthread_mutex_init(darwin_mutex *mutex, const darwin_mutexattr *attributes) {
    int error = pthread_mutex_init(&mutex->value, attributes ? &attributes->value : NULL);
    if (!error)
        atomic_store_explicit(&mutex->sig, SIG_READY, memory_order_release);
    return result(error);
}

int darwin_pthread_mutex_destroy(darwin_mutex *mutex) DARWIN_SYMBOL(pthread_mutex_destroy);
int darwin_pthread_mutex_destroy(darwin_mutex *mutex) {
    long sig = atomic_load(&mutex->sig);
    if (sig != SIG_READY)
        return sig == SIG_MUTEX || sig == SIG_MUTEX_RECURSIVE || sig == SIG_MUTEX_ERRORCHECK ? 0 : 22;
    int error = pthread_mutex_destroy(&mutex->value);
    if (!error)
        atomic_store(&mutex->sig, 0);
    return result(error);
}

int darwin_pthread_mutex_lock(darwin_mutex *mutex) DARWIN_SYMBOL(pthread_mutex_lock);
int darwin_pthread_mutex_lock(darwin_mutex *mutex) {
    pthread_mutex_t *value = mutex_value(mutex);
    return value ? result(pthread_mutex_lock(value)) : 22;
}

int darwin_pthread_mutex_trylock(darwin_mutex *mutex) DARWIN_SYMBOL(pthread_mutex_trylock);
int darwin_pthread_mutex_trylock(darwin_mutex *mutex) {
    pthread_mutex_t *value = mutex_value(mutex);
    return value ? result(pthread_mutex_trylock(value)) : 22;
}

int darwin_pthread_mutex_unlock(darwin_mutex *mutex) DARWIN_SYMBOL(pthread_mutex_unlock);
int darwin_pthread_mutex_unlock(darwin_mutex *mutex) {
    pthread_mutex_t *value = mutex_value(mutex);
    return value ? result(pthread_mutex_unlock(value)) : 22;
}

int darwin_pthread_mutexattr_init(darwin_mutexattr *attributes) DARWIN_SYMBOL(pthread_mutexattr_init);
int darwin_pthread_mutexattr_init(darwin_mutexattr *attributes) {
    attributes->sig = SIG_READY;
    return result(pthread_mutexattr_init(&attributes->value));
}

int darwin_pthread_mutexattr_destroy(darwin_mutexattr *attributes) DARWIN_SYMBOL(pthread_mutexattr_destroy);
int darwin_pthread_mutexattr_destroy(darwin_mutexattr *attributes) {
    attributes->sig = 0;
    return result(pthread_mutexattr_destroy(&attributes->value));
}

// Darwin's PTHREAD_MUTEX_ERRORCHECK is 1 and _RECURSIVE 2; glibc's are
// the other way round. NORMAL and DEFAULT are 0 on both.
enum { DARWIN_MUTEX_ERRORCHECK = 1, DARWIN_MUTEX_RECURSIVE = 2 };

int darwin_pthread_mutexattr_settype(darwin_mutexattr *attributes, int type) DARWIN_SYMBOL(pthread_mutexattr_settype);
int darwin_pthread_mutexattr_settype(darwin_mutexattr *attributes, int type) {
    int linux_type = type == DARWIN_MUTEX_ERRORCHECK ? PTHREAD_MUTEX_ERRORCHECK
        : type == DARWIN_MUTEX_RECURSIVE ? PTHREAD_MUTEX_RECURSIVE : type;
    return result(pthread_mutexattr_settype(&attributes->value, linux_type));
}

int darwin_pthread_mutexattr_gettype(const darwin_mutexattr *attributes, int *type) DARWIN_SYMBOL(pthread_mutexattr_gettype);
int darwin_pthread_mutexattr_gettype(const darwin_mutexattr *attributes, int *type) {
    int linux_type = 0;
    int error = pthread_mutexattr_gettype(&attributes->value, &linux_type);
    if (!error)
        *type = linux_type == PTHREAD_MUTEX_ERRORCHECK ? DARWIN_MUTEX_ERRORCHECK
            : linux_type == PTHREAD_MUTEX_RECURSIVE ? DARWIN_MUTEX_RECURSIVE : linux_type;
    return result(error);
}

// The policy (fair share or first fit) is how Darwin's mutexes hand over;
// glibc's have one way.
int darwin_pthread_mutexattr_setpolicy_np(darwin_mutexattr *attributes, int policy) DARWIN_SYMBOL(pthread_mutexattr_setpolicy_np);
int darwin_pthread_mutexattr_setpolicy_np(darwin_mutexattr *attributes, int policy) {
    (void)attributes;
    return policy >= 1 && policy <= 3 ? 0 : EINVAL;
}

int darwin_pthread_mutexattr_getpolicy_np(const darwin_mutexattr *attributes, int *policy) DARWIN_SYMBOL(pthread_mutexattr_getpolicy_np);
int darwin_pthread_mutexattr_getpolicy_np(const darwin_mutexattr *attributes, int *policy) {
    (void)attributes;
    *policy = 1;    // PTHREAD_MUTEX_POLICY_FAIRSHARE_NP
    return 0;
}

int darwin_pthread_mutexattr_setpshared(darwin_mutexattr *attributes, int shared) DARWIN_SYMBOL(pthread_mutexattr_setpshared);
int darwin_pthread_mutexattr_setpshared(darwin_mutexattr *attributes, int shared) {
    return result(pthread_mutexattr_setpshared(&attributes->value,
        shared == DARWIN_PROCESS_SHARED ? PTHREAD_PROCESS_SHARED : PTHREAD_PROCESS_PRIVATE));
}

int darwin_pthread_mutexattr_setprotocol(darwin_mutexattr *attributes, int protocol) DARWIN_SYMBOL(pthread_mutexattr_setprotocol);
int darwin_pthread_mutexattr_setprotocol(darwin_mutexattr *attributes, int protocol) {
    (void)attributes;
    (void)protocol;
    return 0;
}

// MARK: - Unfair locks

// os_unfair_lock: a 32-bit word, 0 when unlocked, which Darwin code
// initializes itself (OS_UNFAIR_LOCK_INIT). A futex lock over it: 1 when
// held, 2 when held with waiters.
static void unfair_wait(_Atomic uint32_t *word) {
    syscall(SYS_futex, word, FUTEX_WAIT_PRIVATE, 2, NULL, NULL, 0);
}

void darwin_os_unfair_lock_lock(_Atomic uint32_t *lock) DARWIN_SYMBOL(os_unfair_lock_lock);
void darwin_os_unfair_lock_lock(_Atomic uint32_t *lock) {
    uint32_t expected = 0;
    if (atomic_compare_exchange_strong_explicit(lock, &expected, 1, memory_order_acquire, memory_order_relaxed))
        return;
    while (atomic_exchange_explicit(lock, 2, memory_order_acquire) != 0)
        unfair_wait(lock);
}

// Darwin's options (spinning, data synchronization) only tune waiting.
void darwin_os_unfair_lock_lock_with_options(_Atomic uint32_t *lock, uint32_t options) DARWIN_SYMBOL(os_unfair_lock_lock_with_options);
void darwin_os_unfair_lock_lock_with_options(_Atomic uint32_t *lock, uint32_t options) {
    (void)options;
    darwin_os_unfair_lock_lock(lock);
}

bool darwin_os_unfair_lock_trylock(_Atomic uint32_t *lock) DARWIN_SYMBOL(os_unfair_lock_trylock);
bool darwin_os_unfair_lock_trylock(_Atomic uint32_t *lock) {
    uint32_t expected = 0;
    return atomic_compare_exchange_strong_explicit(lock, &expected, 1, memory_order_acquire, memory_order_relaxed);
}

void darwin_os_unfair_lock_unlock(_Atomic uint32_t *lock) DARWIN_SYMBOL(os_unfair_lock_unlock);
void darwin_os_unfair_lock_unlock(_Atomic uint32_t *lock) {
    if (atomic_exchange_explicit(lock, 0, memory_order_release) == 2)
        syscall(SYS_futex, lock, FUTEX_WAKE_PRIVATE, 1, NULL, NULL, 0);
}

// The word records no owner, so ownership cannot be checked.
void darwin_os_unfair_lock_assert_owner(_Atomic uint32_t *lock) DARWIN_SYMBOL(os_unfair_lock_assert_owner);
void darwin_os_unfair_lock_assert_owner(_Atomic uint32_t *lock) { (void)lock; }

void darwin_os_unfair_lock_assert_not_owner(_Atomic uint32_t *lock) DARWIN_SYMBOL(os_unfair_lock_assert_not_owner);
void darwin_os_unfair_lock_assert_not_owner(_Atomic uint32_t *lock) { (void)lock; }

// os_unfair_recursive_lock: an unfair lock and a count of how many times
// its owner holds it. The unfair lock records no owner, so the owning
// thread's ID is kept beside it here, in the count's word's upper half;
// Darwin keeps it in the lock word, which nothing else reads.
typedef struct {
    _Atomic uint32_t lock;
    _Atomic uint32_t count;
} darwin_unfair_recursive_lock;

static _Thread_local uint32_t recursive_owner_id;
static _Atomic uint32_t recursive_owner_ids;

static uint32_t recursive_self(void) {
    if (!recursive_owner_id)
        recursive_owner_id = atomic_fetch_add(&recursive_owner_ids, 1) + 1;
    return recursive_owner_id;
}

// Owner in the upper 16 bits, depth in the lower 16.
static bool recursive_owned(darwin_unfair_recursive_lock *lock) {
    uint32_t value = atomic_load_explicit(&lock->count, memory_order_relaxed);
    return value && (value >> 16) == (recursive_self() & 0xffff);
}

void darwin_os_unfair_recursive_lock_lock_with_options(darwin_unfair_recursive_lock *lock, uint32_t options)
    DARWIN_SYMBOL(os_unfair_recursive_lock_lock_with_options);
void darwin_os_unfair_recursive_lock_lock_with_options(darwin_unfair_recursive_lock *lock, uint32_t options) {
    (void)options;
    if (recursive_owned(lock)) {
        atomic_fetch_add_explicit(&lock->count, 1, memory_order_relaxed);
        return;
    }
    darwin_os_unfair_lock_lock(&lock->lock);
    atomic_store_explicit(&lock->count, ((recursive_self() & 0xffff) << 16) | 1, memory_order_relaxed);
}

bool darwin_os_unfair_recursive_lock_trylock(darwin_unfair_recursive_lock *lock) DARWIN_SYMBOL(os_unfair_recursive_lock_trylock);
bool darwin_os_unfair_recursive_lock_trylock(darwin_unfair_recursive_lock *lock) {
    if (recursive_owned(lock)) {
        atomic_fetch_add_explicit(&lock->count, 1, memory_order_relaxed);
        return true;
    }
    if (!darwin_os_unfair_lock_trylock(&lock->lock))
        return false;
    atomic_store_explicit(&lock->count, ((recursive_self() & 0xffff) << 16) | 1, memory_order_relaxed);
    return true;
}

void darwin_os_unfair_recursive_lock_unlock(darwin_unfair_recursive_lock *lock) DARWIN_SYMBOL(os_unfair_recursive_lock_unlock);
void darwin_os_unfair_recursive_lock_unlock(darwin_unfair_recursive_lock *lock) {
    uint32_t value = atomic_load_explicit(&lock->count, memory_order_relaxed);
    if ((value & 0xffff) > 1) {
        atomic_store_explicit(&lock->count, value - 1, memory_order_relaxed);
        return;
    }
    atomic_store_explicit(&lock->count, 0, memory_order_relaxed);
    darwin_os_unfair_lock_unlock(&lock->lock);
}

// Whether the calling thread holds the lock, as libobjc's fork handling asks.
bool darwin_os_unfair_recursive_lock_tryunlock4objc(darwin_unfair_recursive_lock *lock)
    DARWIN_SYMBOL(os_unfair_recursive_lock_tryunlock4objc);
bool darwin_os_unfair_recursive_lock_tryunlock4objc(darwin_unfair_recursive_lock *lock) {
    if (!recursive_owned(lock))
        return false;
    darwin_os_unfair_recursive_lock_unlock(lock);
    return true;
}

void darwin_os_unfair_recursive_lock_assert_owner(darwin_unfair_recursive_lock *lock)
    DARWIN_SYMBOL(os_unfair_recursive_lock_assert_owner);
void darwin_os_unfair_recursive_lock_assert_owner(darwin_unfair_recursive_lock *lock) { (void)lock; }

void darwin_os_unfair_recursive_lock_assert_not_owner(darwin_unfair_recursive_lock *lock)
    DARWIN_SYMBOL(os_unfair_recursive_lock_assert_not_owner);
void darwin_os_unfair_recursive_lock_assert_not_owner(darwin_unfair_recursive_lock *lock) { (void)lock; }

// MARK: - Conditions

static void setup_static_cond(void *object, long sig) {
    (void)sig;
    darwin_cond *cond = object;
    pthread_cond_t *value = malloc(sizeof(*value));
    pthread_cond_init(value, NULL);
    atomic_store(&cond->value, value);
}

static pthread_cond_t *cond_value(darwin_cond *cond) {
    return cond && ensure(&cond->sig, SIG_COND, setup_static_cond, cond) ? atomic_load(&cond->value) : NULL;
}

int darwin_pthread_cond_init(darwin_cond *cond, const darwin_condattr *attributes) DARWIN_SYMBOL(pthread_cond_init);
int darwin_pthread_cond_init(darwin_cond *cond, const darwin_condattr *attributes) {
    pthread_cond_t *value = malloc(sizeof(*value));
    if (!value)
        return 12;
    int error = pthread_cond_init(value, attributes ? &attributes->value : NULL);
    if (error) {
        free(value);
        return result(error);
    }
    atomic_store(&cond->value, value);
    atomic_store_explicit(&cond->sig, SIG_READY, memory_order_release);
    return 0;
}

int darwin_pthread_cond_destroy(darwin_cond *cond) DARWIN_SYMBOL(pthread_cond_destroy);
int darwin_pthread_cond_destroy(darwin_cond *cond) {
    if (atomic_load(&cond->sig) != SIG_READY)
        return atomic_load(&cond->sig) == SIG_COND ? 0 : 22;
    pthread_cond_t *value = atomic_load(&cond->value);
    int error = pthread_cond_destroy(value);
    if (error)
        return result(error);
    free(value);
    atomic_store(&cond->value, NULL);
    atomic_store(&cond->sig, 0);
    return 0;
}

int darwin_pthread_cond_wait(darwin_cond *cond, darwin_mutex *mutex) DARWIN_SYMBOL(pthread_cond_wait);
int darwin_pthread_cond_wait(darwin_cond *cond, darwin_mutex *mutex) {
    pthread_cond_t *value = cond_value(cond);
    pthread_mutex_t *lock = mutex_value(mutex);
    return value && lock ? result(pthread_cond_wait(value, lock)) : 22;
}

int darwin_pthread_cond_timedwait(darwin_cond *cond, darwin_mutex *mutex, const struct timespec *deadline)
    DARWIN_SYMBOL(pthread_cond_timedwait);
int darwin_pthread_cond_timedwait(darwin_cond *cond, darwin_mutex *mutex, const struct timespec *deadline) {
    pthread_cond_t *value = cond_value(cond);
    pthread_mutex_t *lock = mutex_value(mutex);
    return value && lock ? result(pthread_cond_timedwait(value, lock, deadline)) : 22;
}

// Darwin's wait for a time from now, on the condition's realtime clock.
int darwin_pthread_cond_timedwait_relative_np(darwin_cond *cond, darwin_mutex *mutex, const struct timespec *interval)
    DARWIN_SYMBOL(pthread_cond_timedwait_relative_np);
int darwin_pthread_cond_timedwait_relative_np(darwin_cond *cond, darwin_mutex *mutex, const struct timespec *interval) {
    struct timespec deadline;
    clock_gettime(CLOCK_REALTIME, &deadline);
    deadline.tv_sec += interval->tv_sec;
    deadline.tv_nsec += interval->tv_nsec;
    if (deadline.tv_nsec >= 1000000000) {
        deadline.tv_sec++;
        deadline.tv_nsec -= 1000000000;
    }
    return darwin_pthread_cond_timedwait(cond, mutex, &deadline);
}

int darwin_pthread_cond_signal(darwin_cond *cond) DARWIN_SYMBOL(pthread_cond_signal);
int darwin_pthread_cond_signal(darwin_cond *cond) {
    pthread_cond_t *value = cond_value(cond);
    return value ? result(pthread_cond_signal(value)) : 22;
}

int darwin_pthread_cond_broadcast(darwin_cond *cond) DARWIN_SYMBOL(pthread_cond_broadcast);
int darwin_pthread_cond_broadcast(darwin_cond *cond) {
    pthread_cond_t *value = cond_value(cond);
    return value ? result(pthread_cond_broadcast(value)) : 22;
}

// Wakes the thread given, if it waits: waking every waiter instead is one
// of the spurious wakeups condition variables allow.
int darwin_pthread_cond_signal_thread_np(darwin_cond *cond, pthread_t thread)
    DARWIN_SYMBOL(pthread_cond_signal_thread_np);
int darwin_pthread_cond_signal_thread_np(darwin_cond *cond, pthread_t thread) {
    return thread ? darwin_pthread_cond_broadcast(cond) : darwin_pthread_cond_signal(cond);
}

int darwin_pthread_condattr_init(darwin_condattr *attributes) DARWIN_SYMBOL(pthread_condattr_init);
int darwin_pthread_condattr_init(darwin_condattr *attributes) {
    attributes->sig = SIG_READY;
    return result(pthread_condattr_init(&attributes->value));
}

int darwin_pthread_condattr_destroy(darwin_condattr *attributes) DARWIN_SYMBOL(pthread_condattr_destroy);
int darwin_pthread_condattr_destroy(darwin_condattr *attributes) {
    return result(pthread_condattr_destroy(&attributes->value));
}

// MARK: - Read-write locks

static void setup_static_rwlock(void *object, long sig) {
    (void)sig;
    pthread_rwlock_init(&((darwin_rwlock *)object)->value, NULL);
}

static pthread_rwlock_t *rwlock_value(darwin_rwlock *lock) {
    return lock && ensure(&lock->sig, SIG_RWLOCK, setup_static_rwlock, lock) ? &lock->value : NULL;
}

int darwin_pthread_rwlock_init(darwin_rwlock *lock, const darwin_rwlockattr *attributes) DARWIN_SYMBOL(pthread_rwlock_init);
int darwin_pthread_rwlock_init(darwin_rwlock *lock, const darwin_rwlockattr *attributes) {
    int error = pthread_rwlock_init(&lock->value, attributes ? &attributes->value : NULL);
    if (!error)
        atomic_store_explicit(&lock->sig, SIG_READY, memory_order_release);
    return result(error);
}

int darwin_pthread_rwlock_destroy(darwin_rwlock *lock) DARWIN_SYMBOL(pthread_rwlock_destroy);
int darwin_pthread_rwlock_destroy(darwin_rwlock *lock) {
    if (atomic_load(&lock->sig) != SIG_READY)
        return 0;
    int error = pthread_rwlock_destroy(&lock->value);
    if (!error)
        atomic_store(&lock->sig, 0);
    return result(error);
}

// Darwin reports EDEADLK to the thread holding the lock for writing when
// it asks again, where glibc's try functions report EBUSY.
static int holds_for_writing(darwin_rwlock *lock) {
    pthread_t writer = atomic_load(&lock->writer);
    return writer && pthread_equal(writer, pthread_self());
}

#define RWLOCK_CALL(darwin_name, glibc_name, writes)                            \
    int darwin_##darwin_name(darwin_rwlock *lock) DARWIN_SYMBOL(darwin_name);  \
    int darwin_##darwin_name(darwin_rwlock *lock) {                             \
        pthread_rwlock_t *value = rwlock_value(lock);                           \
        if (!value)                                                             \
            return 22;                                                          \
        if (holds_for_writing(lock))                                            \
            return 11;                                                          \
        int error = glibc_name(value);                                          \
        if (!error && (writes))                                                 \
            atomic_store(&lock->writer, pthread_self());                        \
        return result(error);                                                   \
    }

RWLOCK_CALL(pthread_rwlock_rdlock, pthread_rwlock_rdlock, 0)
RWLOCK_CALL(pthread_rwlock_wrlock, pthread_rwlock_wrlock, 1)
RWLOCK_CALL(pthread_rwlock_tryrdlock, pthread_rwlock_tryrdlock, 0)
RWLOCK_CALL(pthread_rwlock_trywrlock, pthread_rwlock_trywrlock, 1)

int darwin_pthread_rwlock_unlock(darwin_rwlock *lock) DARWIN_SYMBOL(pthread_rwlock_unlock);
int darwin_pthread_rwlock_unlock(darwin_rwlock *lock) {
    pthread_rwlock_t *value = rwlock_value(lock);
    if (!value)
        return 22;
    if (holds_for_writing(lock))
        atomic_store(&lock->writer, (pthread_t)0);
    return result(pthread_rwlock_unlock(value));
}

int darwin_pthread_rwlockattr_init(darwin_rwlockattr *attributes) DARWIN_SYMBOL(pthread_rwlockattr_init);
int darwin_pthread_rwlockattr_init(darwin_rwlockattr *attributes) {
    attributes->sig = SIG_READY;
    return result(pthread_rwlockattr_init(&attributes->value));
}

int darwin_pthread_rwlockattr_destroy(darwin_rwlockattr *attributes) DARWIN_SYMBOL(pthread_rwlockattr_destroy);
int darwin_pthread_rwlockattr_destroy(darwin_rwlockattr *attributes) {
    return result(pthread_rwlockattr_destroy(&attributes->value));
}

// MARK: - Once

static pthread_mutex_t once_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t once_done = PTHREAD_COND_INITIALIZER;

// The state word after the signature: 0 pending, 1 running, 2 done.
int darwin_pthread_once(darwin_once *once, void (*routine)(void)) DARWIN_SYMBOL(pthread_once);
int darwin_pthread_once(darwin_once *once, void (*routine)(void)) {
    if (atomic_load_explicit(&once->state, memory_order_acquire) == 2)
        return 0;
    long expected = 0;
    if (atomic_compare_exchange_strong(&once->state, &expected, 1)) {
        routine();
        pthread_mutex_lock(&once_lock);
        atomic_store_explicit(&once->state, 2, memory_order_release);
        pthread_cond_broadcast(&once_done);
        pthread_mutex_unlock(&once_lock);
        return 0;
    }
    pthread_mutex_lock(&once_lock);
    while (atomic_load_explicit(&once->state, memory_order_acquire) != 2)
        pthread_cond_wait(&once_done, &once_lock);
    pthread_mutex_unlock(&once_lock);
    return 0;
}

// MARK: - Threads

int darwin_pthread_attr_setdetachstate(pthread_attr_t *attributes, int state) DARWIN_SYMBOL(pthread_attr_setdetachstate);
int darwin_pthread_attr_setdetachstate(pthread_attr_t *attributes, int state) {
    if (state != DARWIN_DETACHED && state != DARWIN_JOINABLE)
        return 22;
    return result(pthread_attr_setdetachstate(attributes,
        state == DARWIN_DETACHED ? PTHREAD_CREATE_DETACHED : PTHREAD_CREATE_JOINABLE));
}

// Cancellation states and types, which Darwin numbers differently:
// PTHREAD_CANCEL_ENABLE 1, DISABLE 0; DEFERRED 2, ASYNCHRONOUS 0.
enum { DARWIN_CANCEL_ENABLE = 0x01, DARWIN_CANCEL_DISABLE = 0x00, DARWIN_CANCEL_DEFERRED = 0x02,
       DARWIN_CANCEL_ASYNCHRONOUS = 0x00 };

int darwin_pthread_setcancelstate(int state, int *old_state) DARWIN_SYMBOL(pthread_setcancelstate);
int darwin_pthread_setcancelstate(int state, int *old_state) {
    if (state != DARWIN_CANCEL_ENABLE && state != DARWIN_CANCEL_DISABLE)
        return 22;
    int linux_old = 0;
    int error = pthread_setcancelstate(state == DARWIN_CANCEL_ENABLE ? PTHREAD_CANCEL_ENABLE : PTHREAD_CANCEL_DISABLE,
                                       &linux_old);
    if (!error && old_state)
        *old_state = linux_old == PTHREAD_CANCEL_ENABLE ? DARWIN_CANCEL_ENABLE : DARWIN_CANCEL_DISABLE;
    return result(error);
}

int darwin_pthread_setcanceltype(int type, int *old_type) DARWIN_SYMBOL(pthread_setcanceltype);
int darwin_pthread_setcanceltype(int type, int *old_type) {
    if (type != DARWIN_CANCEL_DEFERRED && type != DARWIN_CANCEL_ASYNCHRONOUS)
        return 22;
    int linux_old = 0;
    int error = pthread_setcanceltype(type == DARWIN_CANCEL_DEFERRED ? PTHREAD_CANCEL_DEFERRED
                                                                      : PTHREAD_CANCEL_ASYNCHRONOUS,
                                      &linux_old);
    if (!error && old_type)
        *old_type = linux_old == PTHREAD_CANCEL_DEFERRED ? DARWIN_CANCEL_DEFERRED : DARWIN_CANCEL_ASYNCHRONOUS;
    return result(error);
}

void darwin_pthread_testcancel(void) DARWIN_SYMBOL(pthread_testcancel);
void darwin_pthread_testcancel(void) {
    pthread_testcancel();
}

// Darwin's smallest stack is 16 KB; the host's is larger (128 KB on arm64),
// and its threads keep their thread-local storage on the stack too. A size
// Darwin accepts is raised to one the host does.
int darwin_pthread_attr_setstacksize(pthread_attr_t *attributes, size_t size) DARWIN_SYMBOL(pthread_attr_setstacksize);
int darwin_pthread_attr_setstacksize(pthread_attr_t *attributes, size_t size) {
    if (size < 16384)
        return 22;
    size_t minimum = (size_t)sysconf(_SC_THREAD_STACK_MIN) + 65536;
    return result(pthread_attr_setstacksize(attributes, size < minimum ? minimum : size));
}

int darwin_pthread_attr_setstack(pthread_attr_t *attributes, void *stack, size_t size) DARWIN_SYMBOL(pthread_attr_setstack);
int darwin_pthread_attr_setstack(pthread_attr_t *attributes, void *stack, size_t size) {
    return result(pthread_attr_setstack(attributes, stack, size));
}

int darwin_pthread_attr_getdetachstate(const pthread_attr_t *attributes, int *state) DARWIN_SYMBOL(pthread_attr_getdetachstate);
int darwin_pthread_attr_getdetachstate(const pthread_attr_t *attributes, int *state) {
    int linux_state = 0;
    int error = pthread_attr_getdetachstate(attributes, &linux_state);
    if (!error)
        *state = linux_state == PTHREAD_CREATE_DETACHED ? DARWIN_DETACHED : DARWIN_JOINABLE;
    return result(error);
}

// pthread_key_t is 8 bytes on Darwin and 4 on Linux: write all 8.
// Darwin keeps a thread's values in an array of words in its pthread_t,
// and runtimes such as Mono read another thread's values there directly,
// at an offset they find by probing: thread + offset + key * 8. glibc
// keeps its first 32 keys' values in its pthread_t too, as {sequence,
// value} pairs of 16 bytes. So Darwin keys are numbered from where their
// values are: key_base + 2 * the glibc key, key_base found at startup so
// that the offset such reading needs is iOS's on arm64, 0xe0, which Mono
// tries first.
//
// Only glibc's first 32 keys live in its pthread_t, and the process's own
// libraries take keys before Darwin code runs, so the low keys still free
// are kept back as early as can be, for Darwin code first. Each is made with a
// destructor of its own that calls the one Darwin code gives.
enum { RESERVED_KEYS = 30 };
static pthread_key_t reserved_keys[RESERVED_KEYS];
static void (*reserved_destructors[RESERVED_KEYS])(void *);
static int reserved_state[RESERVED_KEYS];   // 0 missing, 1 free, 2 in use
static pthread_mutex_t reserved_lock = PTHREAD_MUTEX_INITIALIZER;
static long key_base;

enum { DARWIN_TSD_OFFSET = 0xe0 };

static unsigned long key_to_darwin(pthread_key_t key) { return (unsigned long)(key_base + 2 * (long)key); }
static pthread_key_t key_to_linux(unsigned long key) { return (pthread_key_t)(((long)key - key_base) / 2); }

#define RESERVED_DESTRUCTOR(n) \
    static void reserved_destructor_##n(void *value) { \
        if (reserved_destructors[n]) \
            PERRY_KEEP_R9(reserved_destructors[n](value)); \
    }
RESERVED_DESTRUCTOR(0) RESERVED_DESTRUCTOR(1) RESERVED_DESTRUCTOR(2) RESERVED_DESTRUCTOR(3)
RESERVED_DESTRUCTOR(4) RESERVED_DESTRUCTOR(5) RESERVED_DESTRUCTOR(6) RESERVED_DESTRUCTOR(7)
RESERVED_DESTRUCTOR(8) RESERVED_DESTRUCTOR(9) RESERVED_DESTRUCTOR(10) RESERVED_DESTRUCTOR(11)
RESERVED_DESTRUCTOR(12) RESERVED_DESTRUCTOR(13) RESERVED_DESTRUCTOR(14) RESERVED_DESTRUCTOR(15)
RESERVED_DESTRUCTOR(16) RESERVED_DESTRUCTOR(17) RESERVED_DESTRUCTOR(18) RESERVED_DESTRUCTOR(19)
RESERVED_DESTRUCTOR(20) RESERVED_DESTRUCTOR(21) RESERVED_DESTRUCTOR(22) RESERVED_DESTRUCTOR(23)
RESERVED_DESTRUCTOR(24) RESERVED_DESTRUCTOR(25) RESERVED_DESTRUCTOR(26) RESERVED_DESTRUCTOR(27)
RESERVED_DESTRUCTOR(28) RESERVED_DESTRUCTOR(29)

static void (*const reserved_trampolines[RESERVED_KEYS])(void *) = {
    reserved_destructor_0, reserved_destructor_1, reserved_destructor_2, reserved_destructor_3,
    reserved_destructor_4, reserved_destructor_5, reserved_destructor_6, reserved_destructor_7,
    reserved_destructor_8, reserved_destructor_9, reserved_destructor_10, reserved_destructor_11,
    reserved_destructor_12, reserved_destructor_13, reserved_destructor_14, reserved_destructor_15,
    reserved_destructor_16, reserved_destructor_17, reserved_destructor_18, reserved_destructor_19,
    reserved_destructor_20, reserved_destructor_21, reserved_destructor_22, reserved_destructor_23,
    reserved_destructor_24, reserved_destructor_25, reserved_destructor_26, reserved_destructor_27,
    reserved_destructor_28, reserved_destructor_29,
};

__attribute__((constructor(101)))
static void reserve_keys(void) {
    for (int i = 0; i < RESERVED_KEYS; i++) {
        pthread_key_t key;
        if (pthread_key_create(&key, reserved_trampolines[i]) != 0)
            break;
        // Past the first block it is no use for this.
        if (key >= 32) {
            pthread_key_delete(key);
            break;
        }
        reserved_keys[i] = key;
        reserved_state[i] = 1;
    }
    // Where the first reserved key's value is, in words from the pthread_t.
    if (reserved_state[0]) {
        static int canary;
        pthread_setspecific(reserved_keys[0], &canary);
        void **words = (void **)pthread_self();
        for (unsigned long word = 0; word < 512; word++) {
            // The value's word is DARWIN_TSD_OFFSET in words + its Darwin
            // key. glibc's {sequence, value} pairs are two words on armv7 too.
            if (words[word] == &canary) {
                key_base = (long)word - DARWIN_TSD_OFFSET / (long)sizeof(void *) - 2 * (long)reserved_keys[0];
                break;
            }
        }
        pthread_setspecific(reserved_keys[0], NULL);
    }
}

// Darwin also reserves fixed keys for its own libraries, below the first
// key pthread_key_create makes: Swift's runtime has 100 to 109, and other
// frameworks the keys up to 119. Each gets a key here when first used or set
// up with pthread_key_init_np (which gives its destructor), and
// pthread_key_create never numbers a key in their range.
enum { FIXED_RANGE_START = 100, FIXED_RANGE_END = 120 };

static bool is_fixed_number(unsigned long key) { return key >= FIXED_RANGE_START && key < FIXED_RANGE_END; }

static pthread_key_t fixed_keys[FIXED_RANGE_END];
static _Atomic bool fixed_keys_made[FIXED_RANGE_END];

// glibc calls a fixed key's destructor through one of these, which keeps r9
// (see PERRY_KEEP_R9).
static void (*fixed_destructors[FIXED_RANGE_END])(void *);
#define FIXED_DESTRUCTOR(n) \
    static void fixed_destructor_##n(void *value) { PERRY_KEEP_R9(fixed_destructors[n](value)); }
FIXED_DESTRUCTOR(100) FIXED_DESTRUCTOR(101) FIXED_DESTRUCTOR(102) FIXED_DESTRUCTOR(103)
FIXED_DESTRUCTOR(104) FIXED_DESTRUCTOR(105) FIXED_DESTRUCTOR(106) FIXED_DESTRUCTOR(107)
FIXED_DESTRUCTOR(108) FIXED_DESTRUCTOR(109) FIXED_DESTRUCTOR(110) FIXED_DESTRUCTOR(111)
FIXED_DESTRUCTOR(112) FIXED_DESTRUCTOR(113) FIXED_DESTRUCTOR(114) FIXED_DESTRUCTOR(115)
FIXED_DESTRUCTOR(116) FIXED_DESTRUCTOR(117) FIXED_DESTRUCTOR(118) FIXED_DESTRUCTOR(119)

static void (*const fixed_trampolines[FIXED_RANGE_END - FIXED_RANGE_START])(void *) = {
    fixed_destructor_100, fixed_destructor_101, fixed_destructor_102, fixed_destructor_103,
    fixed_destructor_104, fixed_destructor_105, fixed_destructor_106, fixed_destructor_107,
    fixed_destructor_108, fixed_destructor_109, fixed_destructor_110, fixed_destructor_111,
    fixed_destructor_112, fixed_destructor_113, fixed_destructor_114, fixed_destructor_115,
    fixed_destructor_116, fixed_destructor_117, fixed_destructor_118, fixed_destructor_119,
};

int darwin_pthread_key_init_np(int key, void (*destructor)(void *)) DARWIN_SYMBOL(pthread_key_init_np);
int darwin_pthread_key_init_np(int key, void (*destructor)(void *)) {
    if (key < 0 || !is_fixed_number((unsigned long)key))
        return result(EINVAL);
    pthread_mutex_lock(&reserved_lock);
    int error = 0;
    if (!fixed_keys_made[key]) {
        fixed_destructors[key] = destructor;
        error = pthread_key_create(&fixed_keys[key], destructor ? fixed_trampolines[key - FIXED_RANGE_START] : NULL);
        if (!error)
            atomic_store_explicit(&fixed_keys_made[key], true, memory_order_release);
    }
    pthread_mutex_unlock(&reserved_lock);
    return result(error);
}

// A fixed key exists whether or not it was initialized, as on Darwin: Swift
// uses its own without pthread_key_init_np when they need no destructor.
static pthread_key_t key_to_linux_or_fixed(unsigned long key) {
    if (!is_fixed_number(key))
        return key_to_linux(key);
    if (!atomic_load_explicit(&fixed_keys_made[key], memory_order_acquire))
        darwin_pthread_key_init_np((int)key, NULL);
    return fixed_keys[key];
}

int darwin_pthread_key_create(unsigned long *key, void (*destructor)(void *)) DARWIN_SYMBOL(pthread_key_create);
int darwin_pthread_key_create(unsigned long *key, void (*destructor)(void *)) {
    pthread_mutex_lock(&reserved_lock);
    for (int i = 0; i < RESERVED_KEYS; i++) {
        if (reserved_state[i] == 1 && !is_fixed_number(key_to_darwin(reserved_keys[i]))) {
            reserved_state[i] = 2;
            reserved_destructors[i] = destructor;
            pthread_mutex_unlock(&reserved_lock);
            *key = key_to_darwin(reserved_keys[i]);
            return 0;
        }
    }
    pthread_mutex_unlock(&reserved_lock);
    // A key numbered in the fixed range is kept, unused, so it is not made again.
    // glibc calls these keys' destructors itself, which on armv7 does not keep
    // r9 for it as the reserved keys' do.
    pthread_key_t linux_key;
    int error;
    while (!(error = pthread_key_create(&linux_key, destructor)) && is_fixed_number(key_to_darwin(linux_key))) {}
    if (!error)
        *key = key_to_darwin(linux_key);
    return result(error);
}

int darwin_pthread_key_delete(unsigned long key) DARWIN_SYMBOL(pthread_key_delete);
int darwin_pthread_key_delete(unsigned long key) {
    pthread_mutex_lock(&reserved_lock);
    for (int i = 0; i < RESERVED_KEYS; i++) {
        if (reserved_state[i] == 2 && reserved_keys[i] == key_to_linux(key)) {
            // Kept for reuse: the calling thread's value goes, as with deletion.
            reserved_state[i] = 1;
            reserved_destructors[i] = NULL;
            pthread_setspecific(reserved_keys[i], NULL);
            pthread_mutex_unlock(&reserved_lock);
            return 0;
        }
    }
    pthread_mutex_unlock(&reserved_lock);
    return result(pthread_key_delete(key_to_linux(key)));
}

void *darwin_pthread_getspecific(unsigned long key) DARWIN_SYMBOL(pthread_getspecific);
void *darwin_pthread_getspecific(unsigned long key) {
    return pthread_getspecific(key_to_linux_or_fixed(key));
}

int darwin_pthread_setspecific(unsigned long key, const void *value) DARWIN_SYMBOL(pthread_setspecific);
int darwin_pthread_setspecific(unsigned long key, const void *value) {
    return result(pthread_setspecific(key_to_linux_or_fixed(key), value));
}

// Darwin names only the calling thread. Linux keeps 15 bytes of a name.
int darwin_pthread_setname_np(const char *name) DARWIN_SYMBOL(pthread_setname_np);
int darwin_pthread_setname_np(const char *name) {
    char truncated[16];
    strncpy(truncated, name ? name : "", sizeof(truncated) - 1);
    truncated[sizeof(truncated) - 1] = 0;
    return result(pthread_setname_np(pthread_self(), truncated));
}

int darwin_pthread_getname_np(pthread_t thread, char *name, size_t size) DARWIN_SYMBOL(pthread_getname_np);
int darwin_pthread_getname_np(pthread_t thread, char *name, size_t size) {
    // Darwin answers a null thread with ESRCH; glibc would dereference it.
    if (!thread) return ESRCH;
    thread = perry_pthread_to_linux(thread);
    char buffer[16] = {0};
    int error = pthread_getname_np(thread, buffer, sizeof(buffer));
    if (!error && size) {
        strncpy(name, buffer, size - 1);
        name[size - 1] = 0;
    }
    return result(error);
}

// Apple silicon makes JIT memory writable or executable per thread. Linux
// maps it both at once, so there is nothing to switch, and none supported.
int darwin_pthread_jit_write_protect_supported_np(void) DARWIN_SYMBOL(pthread_jit_write_protect_supported_np);
int darwin_pthread_jit_write_protect_supported_np(void) {
    return 0;
}

void darwin_pthread_jit_write_protect_np(int enabled) DARWIN_SYMBOL(pthread_jit_write_protect_np);
void darwin_pthread_jit_write_protect_np(int enabled) {
    (void)enabled;
}

// The main thread is the one whose thread ID is the process ID.
int darwin_pthread_main_np(void) DARWIN_SYMBOL(pthread_main_np);
int darwin_pthread_main_np(void) {
    return gettid() == getpid();
}

// The main thread, recorded as the library loads, which the loader does on it.
static pthread_t main_thread;

__attribute__((constructor))
static void record_main_thread(void) {
    main_thread = pthread_self();
}

pthread_t darwin_pthread_main_thread_np(void) DARWIN_SYMBOL(pthread_main_thread_np);
pthread_t darwin_pthread_main_thread_np(void) {
    return perry_pthread_to_darwin(main_thread);
}

int darwin_pthread_threadid_np(pthread_t thread, uint64_t *id) DARWIN_SYMBOL(pthread_threadid_np);
int darwin_pthread_threadid_np(pthread_t thread, uint64_t *id) {
    thread = perry_pthread_to_linux(thread);
    if (thread && !pthread_equal(thread, pthread_self()))
        *id = (uint64_t)thread;
    else
        *id = (uint64_t)gettid();
    return 0;
}

// Scheduling is the host's: a thread's policy, priority and inheritance
// are hints, taken and kept for the getters.

int darwin_pthread_attr_setschedpolicy(pthread_attr_t *attributes, int policy) DARWIN_SYMBOL(pthread_attr_setschedpolicy);
int darwin_pthread_attr_setschedpolicy(pthread_attr_t *attributes, int policy) {
    (void)attributes;
    return policy >= 1 && policy <= 4 ? 0 : 22;
}

int darwin_pthread_attr_setinheritsched(pthread_attr_t *attributes, int inherit) DARWIN_SYMBOL(pthread_attr_setinheritsched);
int darwin_pthread_attr_setinheritsched(pthread_attr_t *attributes, int inherit) {
    (void)attributes;
    return inherit == 1 || inherit == 2 ? 0 : 22;
}

// The getters answer Darwin's defaults: PTHREAD_INHERIT_SCHED (1) and
// SCHED_OTHER (1).
int darwin_pthread_attr_getinheritsched(const pthread_attr_t *attributes, int *inherit) DARWIN_SYMBOL(pthread_attr_getinheritsched);
int darwin_pthread_attr_getinheritsched(const pthread_attr_t *attributes, int *inherit) {
    if (!attributes || !inherit) return 22;
    *inherit = 1;
    return 0;
}

int darwin_pthread_attr_getschedpolicy(const pthread_attr_t *attributes, int *policy) DARWIN_SYMBOL(pthread_attr_getschedpolicy);
int darwin_pthread_attr_getschedpolicy(const pthread_attr_t *attributes, int *policy) {
    if (!attributes || !policy) return 22;
    *policy = 1;
    return 0;
}

int darwin_pthread_attr_setschedparam(pthread_attr_t *attributes, const void *parameters) DARWIN_SYMBOL(pthread_attr_setschedparam);
int darwin_pthread_attr_setschedparam(pthread_attr_t *attributes, const void *parameters) {
    (void)attributes;
    return parameters ? 0 : 22;
}

// Quality-of-service classes, which Linux has no counterpart for: accepted
// and ignored, as a thread's priority already is.
int darwin_pthread_set_qos_class_self_np(unsigned int qos, int relative_priority) DARWIN_SYMBOL(pthread_set_qos_class_self_np);
int darwin_pthread_set_qos_class_self_np(unsigned int qos, int relative_priority) {
    (void)qos;
    return relative_priority > 0 || relative_priority < -15 ? 22 : 0;
}

int darwin_pthread_attr_set_qos_class_np(pthread_attr_t *attributes, unsigned int qos, int relative_priority)
    DARWIN_SYMBOL(pthread_attr_set_qos_class_np);
int darwin_pthread_attr_set_qos_class_np(pthread_attr_t *attributes, unsigned int qos, int relative_priority) {
    (void)attributes;
    (void)qos;
    return relative_priority > 0 || relative_priority < -15 ? 22 : 0;
}

// MARK: - Darwin's pthread_t on x86

#if defined(__i386__) || defined(__x86_64__)

// Darwin code is given a thread of its own shape for each of glibc's: its
// `sig`, then the cleanup handlers pthread_cleanup_push links there, then
// glibc's thread. A thread's is made the first time Darwin code is given it,
// and kept, as glibc keeps a thread's descriptor to reuse for a later one.
enum { DARWIN_PTHREAD_SIG = 0x54485244 };   // 'THRD', as Darwin's own

struct darwin_thread {
    long sig;
    void *cleanup_stack;
    pthread_t thread;
    struct darwin_thread *next;
};

static struct darwin_thread *darwin_threads;
static pthread_mutex_t darwin_threads_lock = PTHREAD_MUTEX_INITIALIZER;
static __thread struct darwin_thread *current_darwin_thread;

pthread_t perry_pthread_to_darwin(pthread_t thread) {
    if (!thread)
        return 0;
    pthread_mutex_lock(&darwin_threads_lock);
    struct darwin_thread *found = darwin_threads;
    while (found && !pthread_equal(found->thread, thread))
        found = found->next;
    if (!found && (found = calloc(1, sizeof(*found)))) {
        found->sig = DARWIN_PTHREAD_SIG;
        found->thread = thread;
        found->next = darwin_threads;
        darwin_threads = found;
    }
    pthread_mutex_unlock(&darwin_threads_lock);
    return (pthread_t)found;
}

pthread_t perry_pthread_to_linux(pthread_t thread) {
    // A glibc pthread_t's first word is its own address, never the sig.
    const struct darwin_thread *darwin = (const struct darwin_thread *)thread;
    return darwin && darwin->sig == DARWIN_PTHREAD_SIG ? darwin->thread : thread;
}

pthread_t darwin_pthread_self(void) DARWIN_SYMBOL(pthread_self);
pthread_t darwin_pthread_self(void) {
    if (!current_darwin_thread)
        current_darwin_thread = (struct darwin_thread *)perry_pthread_to_darwin(pthread_self());
    return (pthread_t)current_darwin_thread;
}

int darwin_pthread_equal(pthread_t first, pthread_t second) DARWIN_SYMBOL(pthread_equal);
int darwin_pthread_equal(pthread_t first, pthread_t second) {
    return pthread_equal(perry_pthread_to_linux(first), perry_pthread_to_linux(second));
}

int darwin_pthread_join(pthread_t thread, void **value) DARWIN_SYMBOL(pthread_join);
int darwin_pthread_join(pthread_t thread, void **value) {
    return result(pthread_join(perry_pthread_to_linux(thread), value));
}

int darwin_pthread_detach(pthread_t thread) DARWIN_SYMBOL(pthread_detach);
int darwin_pthread_detach(pthread_t thread) {
    return result(pthread_detach(perry_pthread_to_linux(thread)));
}

int darwin_pthread_cancel(pthread_t thread) DARWIN_SYMBOL(pthread_cancel);
int darwin_pthread_cancel(pthread_t thread) {
    return result(pthread_cancel(perry_pthread_to_linux(thread)));
}

#if defined(__x86_64__)
// i386's goes through the trampoline armv7's does.
int darwin_pthread_create(pthread_t *thread, const pthread_attr_t *attributes, void *(*function)(void *), void *argument)
    DARWIN_SYMBOL(pthread_create);
int darwin_pthread_create(pthread_t *thread, const pthread_attr_t *attributes, void *(*function)(void *), void *argument) {
    pthread_t made;
    int error = pthread_create(&made, attributes, function, argument);
    if (!error && thread)
        *thread = perry_pthread_to_darwin(made);
    return result(error);
}
#endif

#endif
