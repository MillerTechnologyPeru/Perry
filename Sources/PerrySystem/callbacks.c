// Functions whose Darwin callbacks glibc calls: qsort's comparator, a
// thread's start routine and exit handlers. On armv7 Darwin's code may change
// r9, and on ppc r2, which glibc's keeps across calls, so each callback is
// called through a function that keeps it. Elsewhere they pass straight
// through (thunks.S).

#define _GNU_SOURCE
#include "PerrySystem.h"

#if defined(__arm__) || defined(__i386__) || defined(__powerpc__)

#include <dlfcn.h>
#include <errno.h>
#include <pthread.h>
#include <stdlib.h>

#if defined(__powerpc__)
void *perry_darwin_callable(void *function) {
    // The loader's, which perry exports: RTLD_DEFAULT finds it.
    static void *(*callable)(void *);
    if (!callable)
        callable = (void *(*)(void *))dlsym(RTLD_DEFAULT, "perry_ppc_linux_callable");
    return callable ? callable(function) : function;
}

void *perry_signal_entry(void *handler) {
    void *(*stub)(void *) = (void *(*)(void *))dlsym(RTLD_DEFAULT, "perry_ppc_thread_stub");
    return stub ? stub(handler) : handler;
}

void perry_note_signal_stack(void *low, size_t size) {
    void (*note)(void *, size_t) = (void (*)(void *, size_t))dlsym(RTLD_DEFAULT, "perry_ppc_note_stack");
    if (note)
        note(low, size);
}
#endif

typedef int (*comparator)(const void *, const void *);

static int compare(const void *a, const void *b, void *function) {
    int order;
    PERRY_KEEP_R9(order = ((comparator)function)(a, b));
    return order;
}

void darwin_qsort(void *base, size_t count, size_t size, comparator function) DARWIN_SYMBOL(qsort);
void darwin_qsort(void *base, size_t count, size_t size, comparator function) {
    qsort_r(base, count, size, compare, (void *)PERRY_DARWIN_FUNCTION(function));
}

// Here, so glibc's code is not between it and the comparator.
void *darwin_bsearch(const void *key, const void *base, size_t count, size_t size, comparator function)
    DARWIN_SYMBOL(bsearch);
void *darwin_bsearch(const void *key, const void *base, size_t count, size_t size, comparator function) {
    const char *low = base;
    function = PERRY_DARWIN_FUNCTION(function);
    while (count > 0) {
        const char *middle = low + (count / 2) * size;
        int order = function(key, middle);
        if (order == 0)
            return (void *)middle;
        if (order > 0) {
            low = middle + size;
            count -= count / 2 + 1;
        } else {
            count /= 2;
        }
    }
    return NULL;
}

struct call {
    void *(*function)(void *);
    void *argument;
};

static void *start(void *pointer) {
    struct call call = *(struct call *)pointer;
    free(pointer);
    void *result;
    PERRY_KEEP_R9(result = PERRY_DARWIN_FUNCTION(call.function)(call.argument));
    return result;
}

int darwin_pthread_create(pthread_t *thread, const pthread_attr_t *attributes, void *(*function)(void *),
                          void *argument) DARWIN_SYMBOL(pthread_create);
int darwin_pthread_create(pthread_t *thread, const pthread_attr_t *attributes, void *(*function)(void *),
                          void *argument) {
    struct call *call = malloc(sizeof *call);
    if (!call)
        return perry_darwin_errno_from_linux(EAGAIN);
    call->function = function;
    call->argument = argument;
    int error = pthread_create(thread, attributes, start, call);
    if (error)
        free(call);
    else if (thread)
        *thread = perry_pthread_to_darwin(*thread);
    return perry_darwin_errno_from_linux(error);
}

// Exit handlers run once, so each frees its call.
static void finish(void *pointer) {
    struct call call = *(struct call *)pointer;
    free(pointer);
    PERRY_KEEP_R9(PERRY_DARWIN_FUNCTION(call.function)(call.argument));
}

int __cxa_atexit(void (*)(void *), void *, void *);

int darwin___cxa_atexit(void (*function)(void *), void *argument, void *image) DARWIN_SYMBOL(__cxa_atexit);
int darwin___cxa_atexit(void (*function)(void *), void *argument, void *image) {
    struct call *call = malloc(sizeof *call);
    if (!call)
        return -1;
    call->function = (void *(*)(void *))function;
    call->argument = argument;
    return __cxa_atexit(finish, call, image);
}

int darwin_atexit(void (*function)(void)) DARWIN_SYMBOL(atexit);
int darwin_atexit(void (*function)(void)) {
    return darwin___cxa_atexit((void (*)(void *))function, NULL, NULL);
}

#endif
