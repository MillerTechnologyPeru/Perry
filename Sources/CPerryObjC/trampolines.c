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
// and on ppc, which has no PC-relative load, so finds itself with a branch
// that links and puts the link register back before leaving through ctr:
//
//   mflr  r0
//   bcl   20, 31, .+4        lr is the next instruction's address, code + 8
//   mflr  r12
//   mtlr  r0                 the caller's return address again
//   mr    r4, r3             self becomes the block's first argument
//   lwz   r3, 28(r12)        the block, at code + 36
//   lwz   r12, 12(r3)        its invoke function
//   mtctr r12
//   bctr
//   .long block
//
// Trampolines are made in pages of their own, writable and executable, or
// switched between the two where the host refuses both at once, and never
// freed: a removed one is kept for reuse.

#include "CPerryObjC.h"

#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <sys/mman.h>

#if defined(__powerpc__)
enum { TRAMPOLINE_SIZE = 48, PAGE_SIZE_BYTES = 0x4000 };
#else
enum { TRAMPOLINE_SIZE = 32, PAGE_SIZE_BYTES = 0x4000 };
#endif

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
#elif defined(__i386__)
// Words of the little-endian bytes of:
//   call +0; pop eax         eax is this address, code + 5
//   mov  ecx, [esp + 4]
//   mov  [esp + 8], ecx      self becomes the block's first argument
//   mov  eax, [eax + 23]     the block, at code + 28
//   mov  [esp + 4], eax
//   jmp  [eax + 12]          its invoke function
enum {
    TRAMPOLINE_WORD0 = 0x000000e8,
    TRAMPOLINE_WORD1 = 0x4c8b5800,
    TRAMPOLINE_WORD2 = 0x4c890424,
    TRAMPOLINE_WORD3 = 0x408b0824,
};
// A block that returns through memory has the result pointer first, so
// everything is one word further up.
enum {
    TRAMPOLINE_STRET_WORD2 = 0x4c890824,
    TRAMPOLINE_STRET_WORD3 = 0x408b0c24,
    BLOCK_USE_STRET = 1 << 29,
};
#elif defined(__powerpc__)
enum {
    TRAMPOLINE_WORD0 = 0x7c0802a6,  // mflr r0
    TRAMPOLINE_WORD1 = 0x429f0005,  // bcl 20, 31, .+4
    TRAMPOLINE_WORD2 = 0x7d8802a6,  // mflr r12
    TRAMPOLINE_WORD3 = 0x7c0803a6,  // mtlr r0
};
// A block that returns through memory has the result pointer in r3, so self
// is in r4 and moves to r5, and the block goes in r4.
enum {
    TRAMPOLINE_MOVE_SELF = 0x7c641b78,          // mr r4, r3
    TRAMPOLINE_LOAD_BLOCK = 0x806c001c,         // lwz r3, 28(r12)
    TRAMPOLINE_LOAD_INVOKE = 0x8183000c,        // lwz r12, 12(r3)
    TRAMPOLINE_STRET_MOVE_SELF = 0x7c852378,    // mr r5, r4
    TRAMPOLINE_STRET_LOAD_BLOCK = 0x808c001c,   // lwz r4, 28(r12)
    TRAMPOLINE_STRET_LOAD_INVOKE = 0x8184000c,  // lwz r12, 12(r4)
    TRAMPOLINE_MTCTR = 0x7d8903a6,              // mtctr r12
    TRAMPOLINE_BCTR = 0x4e800420,               // bctr
    BLOCK_USE_STRET = 1 << 29,
};
#else
#error "no block trampolines for this architecture"
#endif

// Which word the block is in.
#if defined(__i386__)
enum { TRAMPOLINE_BLOCK_WORD = 7 };
#elif defined(__powerpc__)
enum { TRAMPOLINE_BLOCK_WORD = 9 };
#else
enum { TRAMPOLINE_BLOCK_WORD = 4 };
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
#if defined(__i386__)
    bool stret = ((const int *)block)[1] & BLOCK_USE_STRET;
    if (stret) {
        code[2] = TRAMPOLINE_STRET_WORD2;
        code[3] = TRAMPOLINE_STRET_WORD3;
    }
    code[4] = 0x24448917;
    code[5] = stret ? 0x0c60ff08 : 0x0c60ff04;
    code[6] = 0xcccccccc;
#elif defined(__powerpc__)
    bool stret = ((const int *)block)[1] & BLOCK_USE_STRET;
    code[4] = stret ? TRAMPOLINE_STRET_MOVE_SELF : TRAMPOLINE_MOVE_SELF;
    code[5] = stret ? TRAMPOLINE_STRET_LOAD_BLOCK : TRAMPOLINE_LOAD_BLOCK;
    code[6] = stret ? TRAMPOLINE_STRET_LOAD_INVOKE : TRAMPOLINE_LOAD_INVOKE;
    code[7] = TRAMPOLINE_MTCTR;
    code[8] = TRAMPOLINE_BCTR;
#endif
    memcpy(&code[TRAMPOLINE_BLOCK_WORD], &block, sizeof(block));
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
    memcpy(&block, &code[TRAMPOLINE_BLOCK_WORD], sizeof(block));
    return block;
}

void perry_objc_trampoline_remove(void *imp) {
    pthread_mutex_lock(&lock);
    if (free_count < (int)(sizeof(free_list) / sizeof(free_list[0])))
        free_list[free_count++] = imp;
    pthread_mutex_unlock(&lock);
}
