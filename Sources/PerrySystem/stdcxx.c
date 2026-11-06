// libstdc++'s functions that armv7 C++ code built with GCC 4.2 calls rather
// than has inline, beyond operator new and delete (compiler.c): the list's
// and the red-black tree's, which Linux's libstdc++ still has with that
// ABI, the copy-on-write string's assign, and the guards of function-local
// statics.
//
// Linux's are found by name in its libstdc++, which the Swift runtime
// brings. Those that throw end the program there: Linux's exceptions do not
// unwind Darwin's frames.

#include "PerrySystem.h"

#if defined(__arm__)

#include <dlfcn.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static void *stdcxx(const char *name) {
    static void *library;
    if (!library)
        library = dlopen("libstdc++.so.6", RTLD_NOW | RTLD_GLOBAL);
    void *function = library ? dlsym(library, name) : NULL;
    if (!function)
        abort();
    return function;
}

// A function of up to four words of arguments and one of result, which
// these all are.
#define FORWARD(function, darwin, linux_name) \
    uintptr_t function(uintptr_t a, uintptr_t b, uintptr_t c, uintptr_t d) __asm__(darwin) \
        __attribute__((visibility("default"), used)); \
    uintptr_t function(uintptr_t a, uintptr_t b, uintptr_t c, uintptr_t d) { \
        static uintptr_t (*host)(uintptr_t, uintptr_t, uintptr_t, uintptr_t); \
        if (!host) \
            host = (uintptr_t (*)(uintptr_t, uintptr_t, uintptr_t, uintptr_t))stdcxx(linux_name); \
        return host(a, b, c, d); \
    }

// std::string::assign(const char *, size_t), made here rather than Linux's:
// Apple's libstdc++ is built with fully dynamic strings, every one with a
// representation of its own from operator new, where Linux's gives an
// empty string a static one that the program's inline code would free.
// The representation is a length, a capacity and a count of the other
// strings sharing it, before the characters.
struct string_rep {
    size_t length, capacity;
    int shared;
};

void **perry_string_assign(void **string, const char *characters, size_t length) __asm__("__ZNSs6assignEPKcm")
    __attribute__((visibility("default"), used));
void **perry_string_assign(void **string, const char *characters, size_t length) {
    struct string_rep *old = (struct string_rep *)*string - 1;
    char *held = (char *)(old + 1);
    int aliases = characters >= held && characters <= held + old->length;
    if (old->shared <= 0 && old->capacity >= length) {
        // Its own, with the room: in place, which the characters may be in.
        if (length)
            memmove(held, characters, length);
        old->length = length;
        held[length] = 0;
        return string;
    }
    struct string_rep *made = malloc(sizeof(*made) + length + 1);
    if (!made)
        abort();
    made->length = made->capacity = length;
    made->shared = 0;
    if (length)
        memcpy(made + 1, characters, length);
    ((char *)(made + 1))[length] = 0;
    *string = made + 1;
    // The old one goes when no other string has it.
    (void)aliases;
    if (__atomic_fetch_sub(&old->shared, 1, __ATOMIC_ACQ_REL) <= 0)
        free(old);
    return string;
}
FORWARD(perry_list_hook, "__ZNSt15_List_node_base4hookEPS_", "_ZNSt15_List_node_base4hookEPS_")
FORWARD(perry_list_unhook, "__ZNSt15_List_node_base6unhookEv", "_ZNSt15_List_node_base6unhookEv")
FORWARD(perry_tree_decrement_const, "__ZSt18_Rb_tree_decrementPKSt18_Rb_tree_node_base", "_ZSt18_Rb_tree_decrementPKSt18_Rb_tree_node_base")
FORWARD(perry_tree_decrement, "__ZSt18_Rb_tree_decrementPSt18_Rb_tree_node_base", "_ZSt18_Rb_tree_decrementPSt18_Rb_tree_node_base")
FORWARD(perry_tree_increment_const, "__ZSt18_Rb_tree_incrementPKSt18_Rb_tree_node_base", "_ZSt18_Rb_tree_incrementPKSt18_Rb_tree_node_base")
FORWARD(perry_tree_increment, "__ZSt18_Rb_tree_incrementPSt18_Rb_tree_node_base", "_ZSt18_Rb_tree_incrementPSt18_Rb_tree_node_base")
FORWARD(perry_tree_rebalance_for_erase, "__ZSt28_Rb_tree_rebalance_for_erasePSt18_Rb_tree_node_baseRS_",
        "_ZSt28_Rb_tree_rebalance_for_erasePSt18_Rb_tree_node_baseRS_")
FORWARD(perry_tree_insert_and_rebalance, "__ZSt29_Rb_tree_insert_and_rebalancebPSt18_Rb_tree_node_baseS0_RS_",
        "_ZSt29_Rb_tree_insert_and_rebalancebPSt18_Rb_tree_node_baseS0_RS_")
FORWARD(perry_throw_bad_alloc, "__ZSt17__throw_bad_allocv", "_ZSt17__throw_bad_allocv")
FORWARD(perry_throw_length_error, "__ZSt20__throw_length_errorPKc", "_ZSt20__throw_length_errorPKc")
FORWARD(perry_throw_out_of_range, "__ZSt20__throw_out_of_rangePKc", "_ZSt20__throw_out_of_rangePKc")

// A function-local static's guard, 64 bits whose first byte says the static
// is made, as Darwin's 32-bit code reads it before it calls here. One lock
// for them all, held while a static is made, which a static made while
// making another takes again.
static pthread_mutex_t guards;
static pthread_once_t guards_once = PTHREAD_ONCE_INIT;
static void make_guards(void) {
    pthread_mutexattr_t attributes;
    pthread_mutexattr_init(&attributes);
    pthread_mutexattr_settype(&attributes, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&guards, &attributes);
}

int perry_cxa_guard_acquire(uint8_t *guard) __asm__("___cxa_guard_acquire") __attribute__((visibility("default"), used));
int perry_cxa_guard_acquire(uint8_t *guard) {
    pthread_once(&guards_once, make_guards);
    pthread_mutex_lock(&guards);
    if (*guard) {
        pthread_mutex_unlock(&guards);
        return 0;
    }
    return 1;
}

void perry_cxa_guard_release(uint8_t *guard) __asm__("___cxa_guard_release") __attribute__((visibility("default"), used));
void perry_cxa_guard_release(uint8_t *guard) {
    *guard = 1;
    pthread_mutex_unlock(&guards);
}

void perry_cxa_guard_abort(uint8_t *guard) __asm__("___cxa_guard_abort") __attribute__((visibility("default"), used));
void perry_cxa_guard_abort(uint8_t *guard) {
    (void)guard;
    pthread_mutex_unlock(&guards);
}

#endif
