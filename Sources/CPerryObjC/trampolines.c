// Trampolines for imp_implementationWithBlock: each is an IMP that calls a
// block, moving the receiver into the block's first argument, where the
// selector was:
//
//   mov  x1, x0              self becomes the block's first argument
//   ldr  x0, block           the block
//   ldr  x16, [x0, #16]      its invoke function
//   br   x16
//   .quad block
//
// and on armv7, in ARM state:
//
//   mov  r1, r0
//   ldr  r0, [pc, #4]        the block
//   ldr  pc, [r0, #12]       its invoke function (ldr to pc switches state)
//   nop
//   .long block
//
// Trampolines are made in pages of their own, writable and executable, or
// switched between the two where the host refuses both at once, and never
// freed: a removed one is kept for reuse.

#include "CPerryObjC.h"

#include <pthread.h>
#include <stdint.h>
#include <string.h>
#include <sys/mman.h>

enum { TRAMPOLINE_SIZE = 32, PAGE_SIZE_BYTES = 0x4000 };

#if defined(__aarch64__)
enum {
    TRAMPOLINE_WORD0 = 0xaa0003e1,  // mov x1, x0
    TRAMPOLINE_WORD1 = 0x58000060,  // ldr x0, #12 (the block, at code + 16)
    TRAMPOLINE_WORD2 = 0xf9400810,  // ldr x16, [x0, #16]
    TRAMPOLINE_WORD3 = 0xd61f0200,  // br x16
};
#elif defined(__arm__)
enum {
    TRAMPOLINE_WORD0 = 0xe1a01000,  // mov r1, r0
    TRAMPOLINE_WORD1 = 0xe59f0004,  // ldr r0, [pc, #4] (the block, at code + 16)
    TRAMPOLINE_WORD2 = 0xe590f00c,  // ldr pc, [r0, #12]
    TRAMPOLINE_WORD3 = 0xe320f000,  // nop
};
#elif defined(__x86_64__)
// Words of the little-endian bytes of:
//   mov  rsi, rdi            self becomes the block's first argument
//   mov  rdi, [rip + 6]      the block, at code + 16
//   jmp  [rdi + 16]          its invoke function
//   int3 (padding)
enum {
    TRAMPOLINE_WORD0 = 0x48fe8948,
    TRAMPOLINE_WORD1 = 0x00063d8b,
    TRAMPOLINE_WORD2 = 0x67ff0000,
    TRAMPOLINE_WORD3 = 0xcccccc10,
};
#else
#error "no block trampolines for this architecture"
#endif

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static uint8_t *page;
static size_t used = PAGE_SIZE_BYTES;
static int writable_exec;
static uint32_t *free_list[64];
static int free_count;

static void make_writable(uint8_t *start) {
    if (!writable_exec)
        mprotect((void *)((uintptr_t)start & ~(uintptr_t)(PAGE_SIZE_BYTES - 1)), PAGE_SIZE_BYTES, PROT_READ | PROT_WRITE);
}

static void make_executable(uint8_t *start) {
    if (!writable_exec)
        mprotect((void *)((uintptr_t)start & ~(uintptr_t)(PAGE_SIZE_BYTES - 1)), PAGE_SIZE_BYTES, PROT_READ | PROT_EXEC);
}

void *perry_objc_trampoline_create(void *block) {
    pthread_mutex_lock(&lock);
    uint32_t *code;
    if (free_count > 0) {
        code = free_list[--free_count];
    } else {
        if (used + TRAMPOLINE_SIZE > PAGE_SIZE_BYTES) {
            page = mmap(NULL, PAGE_SIZE_BYTES, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
            writable_exec = page != MAP_FAILED;
            if (!writable_exec)
                page = mmap(NULL, PAGE_SIZE_BYTES, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
            if (page == MAP_FAILED) {
                pthread_mutex_unlock(&lock);
                return NULL;
            }
            used = 0;
        }
        code = (uint32_t *)(page + used);
        used += TRAMPOLINE_SIZE;
    }
    make_writable((uint8_t *)code);
    code[0] = TRAMPOLINE_WORD0;
    code[1] = TRAMPOLINE_WORD1;
    code[2] = TRAMPOLINE_WORD2;
    code[3] = TRAMPOLINE_WORD3;
    memcpy(&code[4], &block, sizeof(block));
    __builtin___clear_cache((char *)code, (char *)code + TRAMPOLINE_SIZE);
    make_executable((uint8_t *)code);
    pthread_mutex_unlock(&lock);
    return code;
}

void *perry_objc_trampoline_block(const void *imp) {
    const uint32_t *code = imp;
    if (!code || code[0] != TRAMPOLINE_WORD0 || code[1] != TRAMPOLINE_WORD1)
        return NULL;
    void *block;
    memcpy(&block, &code[4], sizeof(block));
    return block;
}

void perry_objc_trampoline_remove(void *imp) {
    pthread_mutex_lock(&lock);
    if (free_count < (int)(sizeof(free_list) / sizeof(free_list[0])))
        free_list[free_count++] = imp;
    pthread_mutex_unlock(&lock);
}
