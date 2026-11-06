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

#if defined(__arm__)
/// slow.S: calls the function in r12 with the stack aligned to 8 bytes and
/// the caller's first eight stack words copied to it.
void perry_gl_aligned(void);
#endif

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
//
// On armv7 r12 is the one such register, and either way the call goes
// through slow.S: 32-bit Darwin code keeps its stack 4-byte aligned, where
// the host's library expects 8 (Mesa stores NEON registers to it aligned),
// so perry_gl_aligned calls the function on an aligned copy of the stack
// arguments.
//
//     ldr   r12, contended
//     ldr   r12, [r12]
//     cmp   r12, #0
//     ldr   r12, function
//     ldreq pc, aligned
//     ldr   pc, slow
//  contended: .long   function: .long   aligned: .long   slow: .long
#if defined(__arm__)
enum { ENTRY_SIZE = 40, ARENA_SIZE = 256 * 1024 };
#else
enum { ENTRY_SIZE = 56, ARENA_SIZE = 256 * 1024 };
#endif

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static uint8_t *arena;
static size_t used;

void *perry_gl_entry(void *function) {
    if (!function)
        return NULL;
#if defined(__arm__)
    static const uint32_t code[6] = {
        0xe59fc010,     // ldr r12, [pc, #16]
        0xe59cc000,     // ldr r12, [r12]
        0xe35c0000,     // cmp r12, #0
        0xe59fc008,     // ldr r12, [pc, #8]
        0x059ff008,     // ldreq pc, [pc, #8]
        0xe59ff008,     // ldr pc, [pc, #8]
    };
#else
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
#endif
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
#if defined(__arm__)
    const void *literals[4] = { &perry_gl_contended, function, (void *)perry_gl_aligned, (void *)perry_gl_slow };
#else
    const void *literals[3] = { &perry_gl_contended, function, (void *)perry_gl_slow };
#endif
    memcpy(entry, code, sizeof(code));
    memcpy(entry + sizeof(code), literals, sizeof(literals));
    __builtin___clear_cache((char *)entry, (char *)entry + ENTRY_SIZE);
    pthread_mutex_unlock(&lock);
    return entry;
}
