// A thread's end, and Linux's libdispatch's state for the thread.
//
// libdispatch keeps what it knows of a thread (its cache of continuations
// among it) in thread-local storage, registered under a pthread key whose
// destructor frees it when the thread ends. The destructor leaves the
// storage's pointers as they were, and a libdispatch call made later on
// the same thread takes the storage up again as it is: its continuations
// then come out of freed memory, and the destructor, run once more, frees
// the cache a second time. Such calls are made by the destructors of keys
// made after libdispatch's, which is one of the first a process makes: the
// Objective-C runtime's releases what is left in the thread's autorelease
// pools, and an object's -dealloc releases a queue or cancels a source.
//
// So libdispatch's destructor is held back until the others have run. Its
// key's value, which libdispatch itself never reads, is taken off a thread
// that comes through here and kept under a key of this library's, whose
// destructor puts it back after two rounds of destructors: glibc runs up to
// four, and libdispatch's then runs in the third, with nothing left to
// call it afterwards.

#define _GNU_SOURCE
#include "CPerryDispatch.h"

#include <limits.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

static pthread_key_t libdispatch_key;
static pthread_key_t held_key;
static bool holding;

// On a thread just made no key has a value; the first libdispatch call
// gives libdispatch's key one.
static void *find_key(void *found) {
    static bool had[PTHREAD_KEYS_MAX];
    for (int key = 0; key < PTHREAD_KEYS_MAX; key++)
        had[key] = pthread_getspecific((pthread_key_t)key) != NULL;
    (void)linux_dispatch_get_specific(&libdispatch_key);
    int count = 0;
    for (int key = 0; key < PTHREAD_KEYS_MAX; key++) {
        if (had[key] || pthread_getspecific((pthread_key_t)key) == NULL)
            continue;
        libdispatch_key = (pthread_key_t)key;
        count++;
    }
    *(bool *)found = count == 1;
    return NULL;
}

// The first round re-arms the key, its value marked; the second gives
// libdispatch its state back, for its destructor to run in the next.
static void put_back(void *value) {
    uintptr_t state = (uintptr_t)value;
    if (state & 1)
        pthread_setspecific(libdispatch_key, (void *)(state & ~(uintptr_t)1));
    else
        pthread_setspecific(held_key, (void *)(state | 1));
}

bool perry_dispatch_hold_thread_states(void) {
    // PERRY_DISPATCH_THREAD_CLEANUP=libdispatch leaves libdispatch's
    // destructor where it is, to tell what this changes.
    const char *setting = getenv("PERRY_DISPATCH_THREAD_CLEANUP");
    if (setting && strcmp(setting, "libdispatch") == 0)
        return false;
    pthread_t thread;
    bool found = false;
    if (pthread_create(&thread, NULL, find_key, &found) != 0)
        return false;
    pthread_join(thread, NULL);
    if (!found || pthread_key_create(&held_key, put_back) != 0)
        return false;
    holding = true;
    return true;
}

void perry_dispatch_hold_thread_state(void) {
    if (!holding)
        return;
    void *state = pthread_getspecific(libdispatch_key);
    if (!state)
        return;
    pthread_setspecific(held_key, state);
    pthread_setspecific(libdispatch_key, NULL);
}
