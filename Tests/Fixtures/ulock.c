// Run on Darwin or link against PerrySystem on Linux. In addition to timeout
// and mismatch handling, exercise upper-word changes and address-specific wake.
#include <assert.h>
#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#ifdef __linux__
extern int __ulock_wait(uint32_t, void *, uint64_t, uint32_t) __asm__("___ulock_wait");
extern int __ulock_wake(uint32_t, void *, uint64_t) __asm__("___ulock_wake");
#else
extern int __ulock_wait(uint32_t, void *, uint64_t, uint32_t);
extern int __ulock_wake(uint32_t, void *, uint64_t);
#endif
#define NO_ERRNO 0x01000000
static _Atomic uint64_t words[2];
static _Atomic unsigned completed[2];
static void *wait_for_change(void *argument) {
    size_t index = (size_t)argument;
    while (atomic_load(&words[index]) == 0) {
        int result = __ulock_wait(5 | NO_ERRNO, &words[index], 0, 1000000);
        assert(result >= 0);
    }
    atomic_fetch_add(&completed[index], 1);
    return NULL;
}
int main(void) {
    uint64_t wide = UINT64_C(1) << 32;
    uint32_t narrow = 1;
    assert(__ulock_wait(5, &wide, 0, 1000) == 0);
    assert(__ulock_wait(1, &narrow, 0, 1000) == 0);
    assert(__ulock_wait(5 | NO_ERRNO, &wide, wide, 1000) == -60); // Darwin ETIMEDOUT
    assert(__ulock_wake(5 | NO_ERRNO, &wide, 0) == -2); // no waiter
    pthread_t a, b, c;
    assert(pthread_create(&a, NULL, wait_for_change, (void *)0) == 0);
    assert(pthread_create(&b, NULL, wait_for_change, (void *)0) == 0);
    assert(pthread_create(&c, NULL, wait_for_change, (void *)1) == 0);
    usleep(20000);
    atomic_store(&words[0], UINT64_C(1) << 32);
    __ulock_wake(5 | 0x100 | NO_ERRNO, &words[0], 0);
    assert(pthread_join(a, NULL) == 0);
    assert(pthread_join(b, NULL) == 0);
    assert(atomic_load(&completed[0]) == 2);
    assert(atomic_load(&completed[1]) == 0);
    atomic_store(&words[1], UINT64_C(1) << 32);
    __ulock_wake(5 | NO_ERRNO, &words[1], 0);
    assert(pthread_join(c, NULL) == 0);
    assert(atomic_load(&completed[1]) == 1);
    puts("ulock: mismatch, timeout, wake-all, wake-one, and address isolation passed");
}
