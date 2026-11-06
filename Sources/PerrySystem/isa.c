// Instructions Apple silicon has and older arm64 cores lack, rewritten the
// first time they run.
//
// macOS programs are built for Apple's cores, which have ARMv8.4 and later
// extensions; a Cortex-A76 or A55 (ARMv8.2) raises SIGILL on them. When
// one does, the instruction is replaced in place with a branch to an
// island: a few ARMv8.2 instructions that do the same, then a branch back.
// Only instructions that run are rewritten, so data in code sections is
// never touched, and after the first time they cost a branch each way.
//
//   SHA3 (ARMv8.2-SHA3): EOR3, BCAX, RAX1, XAR, with scratch vector
//     registers saved below the 128-byte red zone Darwin allows leaf
//     functions.
//   LRCPC2 (ARMv8.4): LDAPUR* as LDUR* then DMB ISHLD; STLUR* as DMB ISH
//     then STUR*.
//   FHM (ARMv8.2-FHM): FMLAL, FMLAL2, FMLSL, FMLSL2, vector and by element,
//     as FCVTL of the half-precision operands then FMLA or FMLS.
//   MRS CNTPCT_EL0 / CNTPCTSS_EL0, which Linux traps unless the core has
//     ECV: MRS CNTVCT_EL0, in place.

#include "PerrySystem.h"

#include <stdint.h>
#include <string.h>
#include <sys/mman.h>
#include <ucontext.h>
#include <unistd.h>

#if defined(__aarch64__)

// MARK: - Encodings

enum { RED_ZONE = 128, SPILL = 32 };

static uint32_t branch(const uint32_t *from, const uint32_t *to) {
    return 0x14000000u | ((uint32_t)((to - from) & 0x3ffffff));
}
static uint32_t vector_eor(int d, int n, int m) { return 0x6e201c00u | m << 16 | n << 5 | d; }
static uint32_t vector_bic(int d, int n, int m) { return 0x4e601c00u | m << 16 | n << 5 | d; }
static uint32_t vector_orr(int d, int n, int m) { return 0x4ea01c00u | m << 16 | n << 5 | d; }
// SHL Vd.2D, Vn.2D, #shift and SRI Vd.2D, Vn.2D, #shift.
static uint32_t shl_2d(int d, int n, int shift) { return 0x4f405400u | (uint32_t)shift << 16 | n << 5 | d; }
static uint32_t sri_2d(int d, int n, int shift) { return 0x6f404400u | (uint32_t)(64 - shift) << 16 | n << 5 | d; }
// SUB/ADD SP, SP, #imm; STR/LDR Qt, [SP, #offset].
static uint32_t sub_sp(int imm) { return 0xd10003ffu | (uint32_t)imm << 10; }
static uint32_t add_sp(int imm) { return 0x910003ffu | (uint32_t)imm << 10; }
static uint32_t str_q(int t, int offset) { return 0x3d8003e0u | (uint32_t)(offset / 16) << 10 | t; }
static uint32_t ldr_q(int t, int offset) { return 0x3dc003e0u | (uint32_t)(offset / 16) << 10 | t; }
static const uint32_t dmb_ishld = 0xd50339bfu, dmb_ish = 0xd5033bbfu;

/// Up to two vector registers outside `used` (a mask of v0–v31).
static void scratch(uint32_t used, int *first, int *second) {
    *first = *second = -1;
    for (int v = 31; v >= 0; v--) {
        if (used & 1u << v)
            continue;
        if (*first < 0)
            *first = v;
        else if (*second < 0) {
            *second = v;
            return;
        }
    }
}

/// The island for an instruction, into `island`; its length in words, 0
/// if it isn't one this file rewrites.
static int rewrite(uint32_t instruction, uint32_t *island) {
    int d = instruction & 31, n = instruction >> 5 & 31, m = instruction >> 16 & 31, a = instruction >> 10 & 31;
    int words = 0, s, t;

    // SHA3: EOR3 and BCAX (four registers), RAX1, XAR.
    int eor3 = (instruction & 0xffe08000u) == 0xce000000u, bcax = (instruction & 0xffe08000u) == 0xce200000u;
    int rax1 = (instruction & 0xffe0fc00u) == 0xce608c00u, xar = (instruction & 0xffe00000u) == 0xce800000u;
    if (eor3 || bcax || rax1 || xar) {
        scratch(1u << d | 1u << n | 1u << m | ((eor3 || bcax) ? 1u << a : 0), &s, &t);
        island[words++] = sub_sp(RED_ZONE + SPILL);
        island[words++] = str_q(s, 0);
        if (eor3) {
            island[words++] = vector_eor(s, n, m);
            island[words++] = vector_eor(d, s, a);
        } else if (bcax) {
            island[words++] = vector_bic(s, m, a);
            island[words++] = vector_eor(d, n, s);
        } else if (rax1) {
            // n ^ (m rotated left by 1 in each 64-bit lane).
            island[words++] = shl_2d(s, m, 1);
            island[words++] = sri_2d(s, m, 63);
            island[words++] = vector_eor(d, n, s);
        } else {
            // (n ^ m) rotated right by imm6 in each 64-bit lane.
            int rotate = instruction >> 10 & 63;
            island[words++] = vector_eor(s, n, m);
            if (rotate == 0) {
                island[words++] = vector_orr(d, s, s);
            } else {
                island[words++] = shl_2d(d, s, 64 - rotate);
                island[words++] = sri_2d(d, s, rotate);
            }
        }
        island[words++] = ldr_q(s, 0);
        island[words++] = add_sp(RED_ZONE + SPILL);
        return words;
    }

    // LRCPC2: LDAPUR* and STLUR* (size 011001 opc 0 imm9 00 Rn Rt), as the
    // unscaled LDUR*/STUR* with the same size, opc and offset.
    if ((instruction & 0x3f200c00u) == 0x19000000u) {
        uint32_t plain = (instruction & ~0x3f000000u) | 0x38000000u;
        int store = (instruction >> 22 & 3) == 0;
        if (store) {
            island[words++] = dmb_ish;
            island[words++] = plain;
        } else {
            island[words++] = plain;
            island[words++] = dmb_ishld;
        }
        return words;
    }

    // FHM: FMLAL/FMLSL (vector and by element), second-half forms with U.
    int q = instruction >> 30 & 1, upper = instruction >> 29 & 1;
    int vector = (instruction & 0x9f20ac00u) == 0x0e20ac00u && (instruction & 0xff200000u) != 0;
    int fmlal_vector = (instruction & 0xbfe0fc00u) == 0x0e20ec00u || (instruction & 0xbfe0fc00u) == 0x2e20cc00u;
    int fmlsl_vector = (instruction & 0xbfe0fc00u) == 0x0ea0ec00u || (instruction & 0xbfe0fc00u) == 0x2ea0cc00u;
    uint32_t element_kind = instruction & 0xbfc0f400u;
    int fmlal_element = element_kind == 0x0f800000u || element_kind == 0x2f808000u;
    int fmlsl_element = element_kind == 0x0f804000u || element_kind == 0x2f80c000u;
    (void)vector;
    if (fmlal_vector || fmlsl_vector || fmlal_element || fmlsl_element) {
        int element = fmlal_element || fmlsl_element, subtract = fmlsl_vector || fmlsl_element;
        int rm = element ? (int)(instruction >> 16 & 15) : m;
        scratch(1u << d | 1u << n | 1u << rm, &s, &t);
        island[words++] = sub_sp(RED_ZONE + SPILL);
        island[words++] = str_q(s, 0);
        island[words++] = str_q(t, 16);
        // The half-precision lanes the instruction reads, widened: for Q=1
        // the low or high four; for Q=0 the low two or the next two.
        uint32_t fcvtl = 0x0e217800u, fcvtl2 = 0x4e217800u;
        if (q) {
            island[words++] = (upper ? fcvtl2 : fcvtl) | n << 5 | s;
        } else {
            island[words++] = fcvtl | n << 5 | s;
            if (upper)
                island[words++] = 0x6e000000u | s << 16 | 8u << 11 | s << 5 | s;    // EXT s, s, s, #8
        }
        if (element) {
            int index = (int)(instruction >> 11 & 1) << 2 | (int)(instruction >> 21 & 1) << 1 | (int)(instruction >> 20 & 1);
            island[words++] = (index >= 4 ? fcvtl2 : fcvtl) | rm << 5 | t;
            island[words++] = 0x4e000400u | (uint32_t)((index & 3) << 3 | 4) << 16 | t << 5 | t;   // DUP t.4S, t.S[i]
        } else if (q) {
            island[words++] = (upper ? fcvtl2 : fcvtl) | rm << 5 | t;
        } else {
            island[words++] = fcvtl | rm << 5 | t;
            if (upper)
                island[words++] = 0x6e000000u | t << 16 | 8u << 11 | t << 5 | t;
        }
        // FMLA/FMLS Vd.2S or .4S, s, t.
        island[words++] = (subtract ? 0x0ea0cc00u : 0x0e20cc00u) | (uint32_t)q << 30 | t << 16 | s << 5 | d;
        island[words++] = ldr_q(t, 16);
        island[words++] = ldr_q(s, 0);
        island[words++] = add_sp(RED_ZONE + SPILL);
        return words;
    }
    return 0;
}

// MARK: - Islands

// Islands live in executable pages within a branch's reach (±128 MB) of
// the code that jumps to them.
typedef struct {
    uint32_t *base, *next, *end;
} island_pool;

static island_pool pools[32];
static int pool_count;
static volatile int patch_lock;

static uint32_t *island_near(const uint32_t *pc, int words) {
    for (int i = 0; i < pool_count; i++) {
        island_pool *pool = &pools[i];
        long distance = (long)((const char *)pool->base - (const char *)pc);
        if (distance < -(100L << 20) || distance > (100L << 20) || pool->next + words > pool->end)
            continue;
        uint32_t *island = pool->next;
        pool->next += words;
        return island;
    }
    if (pool_count == (int)(sizeof(pools) / sizeof(pools[0])))
        return NULL;
    size_t size = 1 << 16;
    for (long offset = 1L << 20; offset < (96L << 20); offset += 1L << 20) {
        for (int sign = -1; sign <= 1; sign += 2) {
            uintptr_t hint = ((uintptr_t)pc + sign * offset) & ~(uintptr_t)0xffff;
            void *map = mmap((void *)hint, size, PROT_READ | PROT_WRITE | PROT_EXEC,
                             MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE, -1, 0);
            if (map == MAP_FAILED)
                continue;
            island_pool *pool = &pools[pool_count++];
            pool->base = pool->next = map;
            pool->end = (uint32_t *)((char *)map + size);
            uint32_t *island = pool->next;
            pool->next += words;
            return island;
        }
    }
    return NULL;
}

/// Writes one instruction word of code, which is mapped read and execute.
static int write_code(uint32_t *at, uint32_t word) {
    long page = sysconf(_SC_PAGESIZE);
    uintptr_t start = (uintptr_t)at & ~(uintptr_t)(page - 1);
    if (mprotect((void *)start, (size_t)page, PROT_READ | PROT_WRITE | PROT_EXEC) != 0)
        return 0;
    __atomic_store_n(at, word, __ATOMIC_SEQ_CST);
    mprotect((void *)start, (size_t)page, PROT_READ | PROT_EXEC);
    __builtin___clear_cache((char *)at, (char *)(at + 1));
    return 1;
}

static int counter_read(uint32_t instruction) {
    // MRS Xt, CNTPCT_EL0 (S3_3_C14_C0_1) or CNTPCTSS_EL0 (S3_3_C14_C0_5).
    return (instruction & 0xffffffe0u) == 0xd53be020u || (instruction & 0xffffffe0u) == 0xd53be0a0u;
}

int perry_isa_rewrite(void *raw_context) {
    ucontext_t *context = raw_context;
    uint32_t *pc = (uint32_t *)context->uc_mcontext.pc;
    while (__atomic_exchange_n(&patch_lock, 1, __ATOMIC_ACQUIRE))
        ;
    uint32_t instruction = *pc;
    int handled = 0;
    if ((instruction & 0xfc000000u) == 0x14000000u) {
        // Another thread rewrote it first: run the branch.
        handled = 1;
    } else if (counter_read(instruction)) {
        // MRS Xt, CNTVCT_EL0, which apps may read.
        handled = write_code(pc, 0xd53be040u | (instruction & 31));
        if (!handled) {
            uint64_t value;
            __asm__ volatile("isb\n mrs %0, cntvct_el0" : "=r"(value));
            if ((instruction & 31) != 31)
                context->uc_mcontext.regs[instruction & 31] = value;
            context->uc_mcontext.pc += 4;
            handled = 1;
        }
    } else {
        uint32_t code[32];
        int words = rewrite(instruction, code);
        uint32_t *island = words ? island_near(pc, words + 1) : NULL;
        if (island) {
            memcpy(island, code, (size_t)words * 4);
            island[words] = branch(&island[words], pc + 1);
            __builtin___clear_cache((char *)island, (char *)(island + words + 1));
            handled = write_code(pc, branch(pc, island));
        }
    }
    __atomic_store_n(&patch_lock, 0, __ATOMIC_RELEASE);
    return handled;
}

#endif
