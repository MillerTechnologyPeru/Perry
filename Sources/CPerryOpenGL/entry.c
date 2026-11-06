#define _GNU_SOURCE
#include "CPerryOpenGL.h"

#include <pthread.h>
#include <stdint.h>
#include <string.h>
#include <sys/mman.h>

static int perry_gl_contended;
static void (*perry_gl_before_call)(void);

void perry_gl_set_contended(int contended) { __atomic_store_n(&perry_gl_contended, contended, __ATOMIC_RELEASE); }
void perry_gl_set_before_call(void (*before)(void)) { perry_gl_before_call = before; }

/// slow.S: calls perry_gl_before_call with the arguments kept, then goes on
/// to the function in x16.
void perry_gl_slow(void);

__attribute__((visibility("hidden")))
void perry_gl_call_before(void) {
    if (perry_gl_before_call)
        perry_gl_before_call();
}

// An entry point: x16 and x17 are the linker's scratch registers, free at
// a function's entry.
//
//     ldr  x16, contended        the flag's address
//     ldr  w17, [x16]
//     ldr  x16, function
//     cbnz w17, 1f
//     br   x16
//  1: ldr  x17, slow
//     br   x17
//     nop
//  contended: .quad   function: .quad   slow: .quad
enum { ENTRY_SIZE = 56, ARENA_SIZE = 256 * 1024 };

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static uint8_t *arena;
static size_t used;

void *perry_gl_entry(void *function) {
    if (!function)
        return NULL;
    static const uint32_t code[8] = {
        0x58000110,     // ldr x16, #32
        0xb9400211,     // ldr w17, [x16]
        0x58000110,     // ldr x16, #32
        0x35000051,     // cbnz w17, #8
        0xd61f0200,     // br x16
        0x580000f1,     // ldr x17, #28
        0xd61f0220,     // br x17
        0xd503201f,     // nop
    };
    pthread_mutex_lock(&lock);
    if (!arena || used + ENTRY_SIZE > ARENA_SIZE) {
        void *memory = mmap(NULL, ARENA_SIZE, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (memory == MAP_FAILED) {
            pthread_mutex_unlock(&lock);
            return function;
        }
        arena = memory;
        used = 0;
    }
    uint8_t *entry = arena + used;
    used += ENTRY_SIZE;
    const void *literals[3] = { &perry_gl_contended, function, (void *)perry_gl_slow };
    memcpy(entry, code, sizeof(code));
    memcpy(entry + sizeof(code), literals, sizeof(literals));
    __builtin___clear_cache((char *)entry, (char *)entry + ENTRY_SIZE);
    pthread_mutex_unlock(&lock);
    return entry;
}
