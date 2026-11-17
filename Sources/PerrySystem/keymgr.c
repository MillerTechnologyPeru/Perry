// keymgr and the startup hooks of programs built before Leopard.
//
// keymgr: Darwin's process-wide pointers, each under its own lock, that
// programs built before Leopard use from their startup code and from
// libgcc's unwinder (the list of objects with frame data, the C++ runtime's
// per-thread globals). A key is locked by get-and-lock and unlocked by
// set-and-unlock or unlock; the lock is recursive, as keymgr's default mode.
//
// __keymgr_dwarf2_register_sections, which such a program's startup code
// calls with each image's frame data, has nothing to do here: the loader
// registers every image's __eh_frame with the unwinder as it maps it.

#include "PerrySystem.h"

#include <errno.h>
#include <pthread.h>
#include <stdlib.h>

typedef struct key_entry {
    unsigned key;
    void *pointer;
    pthread_mutex_t lock;
    struct key_entry *next;
} key_entry;

static pthread_mutex_t table_lock = PTHREAD_MUTEX_INITIALIZER;
static key_entry *entries;

static key_entry *entry(unsigned key) {
    pthread_mutex_lock(&table_lock);
    key_entry *found = entries;
    while (found && found->key != key)
        found = found->next;
    if (!found && (found = calloc(1, sizeof *found))) {
        pthread_mutexattr_t attributes;
        pthread_mutexattr_init(&attributes);
        pthread_mutexattr_settype(&attributes, PTHREAD_MUTEX_RECURSIVE);
        pthread_mutex_init(&found->lock, &attributes);
        pthread_mutexattr_destroy(&attributes);
        found->key = key;
        found->next = entries;
        entries = found;
    }
    pthread_mutex_unlock(&table_lock);
    return found;
}

int darwin_keymgr_get_and_lock_processwide_ptr_2(unsigned key, void **result)
    DARWIN_SYMBOL(_keymgr_get_and_lock_processwide_ptr_2);
int darwin_keymgr_get_and_lock_processwide_ptr_2(unsigned key, void **result) {
    key_entry *found = entry(key);
    if (!found) return ENOMEM;
    pthread_mutex_lock(&found->lock);
    if (result) *result = found->pointer;
    return 0;
}

void *darwin_keymgr_get_and_lock_processwide_ptr(unsigned key) DARWIN_SYMBOL(_keymgr_get_and_lock_processwide_ptr);
void *darwin_keymgr_get_and_lock_processwide_ptr(unsigned key) {
    void *pointer = NULL;
    darwin_keymgr_get_and_lock_processwide_ptr_2(key, &pointer);
    return pointer;
}

int darwin_keymgr_set_and_unlock_processwide_ptr(unsigned key, void *pointer)
    DARWIN_SYMBOL(_keymgr_set_and_unlock_processwide_ptr);
int darwin_keymgr_set_and_unlock_processwide_ptr(unsigned key, void *pointer) {
    key_entry *found = entry(key);
    if (!found) return ENOMEM;
    found->pointer = pointer;
    // Setting a key that isn't locked by this thread fails to unlock it,
    // which leaves it as it was.
    pthread_mutex_unlock(&found->lock);
    return 0;
}

int darwin_keymgr_unlock_processwide_ptr(unsigned key) DARWIN_SYMBOL(_keymgr_unlock_processwide_ptr);
int darwin_keymgr_unlock_processwide_ptr(unsigned key) {
    key_entry *found = entry(key);
    if (!found) return ENOMEM;
    return pthread_mutex_unlock(&found->lock);
}

void darwin_keymgr_dwarf2_register_sections(const void *header) DARWIN_SYMBOL(__keymgr_dwarf2_register_sections);
void darwin_keymgr_dwarf2_register_sections(const void *header) { (void)header; }

// The hooks that startup code built before Leopard (crt1.o's _start) calls
// if set, for Mach and cthreads to initialize: libSystem initializes both
// itself, so neither is set.
void (*darwin_mach_init_routine)(void) DARWIN_SYMBOL(mach_init_routine) = NULL;
void (*darwin_cthread_init_routine)(void) DARWIN_SYMBOL(_cthread_init_routine) = NULL;
