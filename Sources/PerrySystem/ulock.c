// Process-local Darwin compare-and-wait, used by libc++ atomics. Linux futexes
// compare only 32 bits; serialize full-width comparison and registration with
// wakeup to avoid losing changes in the upper word. Conditions are per waiter.
#define _GNU_SOURCE
#include "PerrySystem.h"
#include <errno.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <time.h>

enum { COMPARE32 = 1, COMPARE64 = 5, WAKE_ALL = 0x100, NO_ERRNO = 0x01000000 };
struct waiter {
    void *address;
    uint32_t opcode;
    bool notified;
    pthread_cond_t condition;
    struct waiter *next;
};
static pthread_mutex_t wait_lock = PTHREAD_MUTEX_INITIALIZER;
static struct waiter *waiters;

static int fail(uint32_t operation, int error) {
    if (operation & NO_ERRNO) return -perry_darwin_errno_from_linux(error);
    errno = error;
    return -1;
}

static bool valid_address(uint32_t opcode, void *address) {
    size_t alignment = opcode == COMPARE64 ? 8 : 4;
    return address && ((uintptr_t)address % alignment) == 0;
}

int darwin_ulock_wait(uint32_t operation, void *address, uint64_t value, uint32_t timeout)
    DARWIN_SYMBOL(__ulock_wait);
int darwin_ulock_wait(uint32_t operation, void *address, uint64_t value, uint32_t timeout) {
    uint32_t opcode = operation & 0xff;
    // Shared waits, ownership and cancellation flags need separate semantics.
    if ((opcode != COMPARE32 && opcode != COMPARE64) || (operation & ~(0xffu | NO_ERRNO)))
        return fail(operation, EINVAL);
    if (!valid_address(opcode, address)) return fail(operation, EINVAL);
    int cancellation;
    pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &cancellation);
    pthread_mutex_lock(&wait_lock);
    uint64_t actual = opcode == COMPARE64 ? __atomic_load_n((uint64_t *)address, __ATOMIC_ACQUIRE)
                                         : __atomic_load_n((uint32_t *)address, __ATOMIC_ACQUIRE);
    if (actual != (opcode == COMPARE64 ? value : (uint32_t)value)) {
        pthread_mutex_unlock(&wait_lock);
        pthread_setcancelstate(cancellation, NULL);
        return 0;
    }
    struct waiter waiter = { .address = address, .opcode = opcode, .next = waiters };
    pthread_condattr_t attributes;
    pthread_condattr_init(&attributes);
    pthread_condattr_setclock(&attributes, CLOCK_MONOTONIC);
    int error = pthread_cond_init(&waiter.condition, &attributes);
    pthread_condattr_destroy(&attributes);
    if (error) {
        pthread_mutex_unlock(&wait_lock);
        pthread_setcancelstate(cancellation, NULL);
        return fail(operation, error);
    }
    struct timespec deadline;
    if (timeout) {
        clock_gettime(CLOCK_MONOTONIC, &deadline);
        deadline.tv_sec += timeout / 1000000;
        deadline.tv_nsec += (long)(timeout % 1000000) * 1000;
        if (deadline.tv_nsec >= 1000000000) { deadline.tv_sec++; deadline.tv_nsec -= 1000000000; }
    }
    waiters = &waiter;
    while (!waiter.notified && !error) {
        error = timeout ? pthread_cond_timedwait(&waiter.condition, &wait_lock, &deadline)
                        : pthread_cond_wait(&waiter.condition, &wait_lock);
    }
    struct waiter **link = &waiters;
    while (*link != &waiter) link = &(*link)->next;
    *link = waiter.next;
    pthread_cond_destroy(&waiter.condition);
    pthread_mutex_unlock(&wait_lock);
    pthread_setcancelstate(cancellation, NULL);
    return error ? fail(operation, error) : 0;
}

int darwin_ulock_wake(uint32_t operation, void *address, uint64_t wake_value) DARWIN_SYMBOL(__ulock_wake);
int darwin_ulock_wake(uint32_t operation, void *address, uint64_t wake_value) {
    (void)wake_value;
    uint32_t opcode = operation & 0xff;
    if ((opcode != COMPARE32 && opcode != COMPARE64) || (operation & ~(0xffu | NO_ERRNO | WAKE_ALL)))
        return fail(operation, EINVAL);
    if (!valid_address(opcode, address)) return fail(operation, EINVAL);
    bool found = false;
    pthread_mutex_lock(&wait_lock);
    for (struct waiter *waiter = waiters; waiter; waiter = waiter->next) {
        if (waiter->address != address || waiter->opcode != opcode || waiter->notified) continue;
        waiter->notified = found = true;
        pthread_cond_signal(&waiter->condition);
        if (!(operation & WAKE_ALL)) break;
    }
    pthread_mutex_unlock(&wait_lock);
    return found ? 0 : fail(operation, ENOENT);
}
