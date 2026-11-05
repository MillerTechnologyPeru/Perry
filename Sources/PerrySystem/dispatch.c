// libdispatch's once functions, which libSystem exports. A finished
// predicate holds ~0, as on Darwin: callers' inline fast path (the
// DISPATCH_EXPECT test in <dispatch/once.h>) skips the call once it is set.

#include "PerrySystem.h"

#include <sched.h>
#include <stdatomic.h>
#include <stdint.h>

typedef _Atomic intptr_t once_predicate;

enum { ONCE_PENDING = 0, ONCE_RUNNING = 1, ONCE_DONE = ~0 };

// The block's invoke function takes the block itself.
struct once_block {
    void *isa;
    int32_t flags;
    int32_t reserved;
    void (*invoke)(void *block);
};

static void run_once(once_predicate *predicate, void *context, void (*function)(void *)) {
    if (atomic_load_explicit(predicate, memory_order_acquire) == ONCE_DONE)
        return;
    intptr_t expected = ONCE_PENDING;
    if (atomic_compare_exchange_strong(predicate, &expected, ONCE_RUNNING)) {
        function(context);
        atomic_store_explicit(predicate, ONCE_DONE, memory_order_release);
        return;
    }
    // Another thread is running it: wait until it finishes.
    while (atomic_load_explicit(predicate, memory_order_acquire) != ONCE_DONE)
        sched_yield();
}

void darwin_dispatch_once_f(once_predicate *predicate, void *context, void (*function)(void *))
    DARWIN_SYMBOL(dispatch_once_f);

void darwin_dispatch_once_f(once_predicate *predicate, void *context, void (*function)(void *)) {
    run_once(predicate, context, function);
}

static void invoke_block(void *block) {
    ((struct once_block *)block)->invoke(block);
}

void darwin_dispatch_once(once_predicate *predicate, void *block) DARWIN_SYMBOL(dispatch_once);

void darwin_dispatch_once(once_predicate *predicate, void *block) {
    run_once(predicate, block, invoke_block);
}
