// Functions a program expects to run once per process.
//
// Some programs run work in an app extension, a process of its own on
// Darwin that starts for one request: a compiler that registers its classes
// when it is set up, and stops if it is set up again. Perry runs an
// extension in the app's process, where one library can be set up by
// several requests, so these set-up functions are made to run only the
// first time they are called and to return at once after that.

#define _GNU_SOURCE
#include "image.h"
#include "log.h"

#include <errno.h>
#include <unistd.h>
#include <stdint.h>
#include <string.h>
#include <sys/mman.h>

#if defined(__aarch64__)

// Set-up functions of the Swift compiler's libraries, which have no
// arguments and no result.
static const char *const once_functions[] = {
    "_initializeSwiftModules",
    NULL,
};

// A symbol table entry of a 64-bit image.
struct nlist_64 {
    uint32_t n_strx;
    uint8_t n_type;
    uint8_t n_sect;
    uint16_t n_desc;
    uint64_t n_value;
};

// Whether an instruction's meaning depends on where it is, so that it cannot
// run from somewhere else: branches, adr and adrp, loads from a literal.
static bool is_pc_relative(uint32_t i) {
    return (i & 0x7c000000u) == 0x14000000u       // b, bl
        || (i & 0xff000010u) == 0x54000000u       // b.cond
        || (i & 0x7e000000u) == 0x34000000u       // cbz, cbnz
        || (i & 0x7e000000u) == 0x36000000u       // tbz, tbnz
        || (i & 0x1f000000u) == 0x10000000u       // adr, adrp
        || (i & 0x3b000000u) == 0x18000000u;      // ldr literal
}

// The function's first four instructions are replaced by a jump to a
// trampoline that does what they did, if the function has not run yet, and
// otherwise returns. A branch with link among them, as a prologue's first
// call, is redone from the trampoline.
static void make_once(perry_image *image, const char *name, uint32_t *function) {
    enum { Prologue = 4, Flag = 48, Return = 50, Targets = 52 };
    int calls = 0;
    for (int k = 0; k < Prologue; k++) {
        uint32_t i = function[k];
        bool is_call = (i & 0xfc000000u) == 0x94000000u;
        if (is_call) {
            calls++;
        } else if (is_pc_relative(i)) {
            perry_trace(PERRY_TRACE_LOAD, "%s starts with a position-dependent instruction (%08x)", name, i);
            return;
        }
    }
    uint32_t *t = mmap(NULL, 4096, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (t == MAP_FAILED) {
        perry_trace(PERRY_TRACE_LOAD, "no memory for %s's trampoline", name);
        return;
    }
    size_t n = 0;
    t[n++] = 0x10000010u | (uint32_t)(((Flag * 4) & 3) << 29) | (uint32_t)((((Flag * 4) >> 2) & 0x7ffff) << 5); // adr x16, flag
    size_t retry = n;
    t[n++] = 0x085ffe11u;                                  // ldaxrb w17, [x16]
    size_t early = n++;                                    // cbnz w17, return
    t[n++] = 0x52800031u;                                  // mov w17, #1
    t[n++] = 0x080ffe11u;                                  // stlxrb w15, w17, [x16]
    t[n] = 0x35000000u | (uint32_t)(((retry - n) & 0x7ffff) << 5) | 15;   // cbnz w15, retry
    n++;
    int target = 0;
    for (int k = 0; k < Prologue; k++) {
        uint32_t i = function[k];
        if ((i & 0xfc000000u) == 0x94000000u) {
            int32_t offset = (int32_t)(i << 6) >> 6;
            uint64_t destination = (uint64_t)(uintptr_t)(function + k) + (int64_t)offset * 4;
            size_t slot = Targets + 2 * (size_t)target++;
            memcpy(&t[slot], &destination, 8);
            t[n] = 0x58000010u | (uint32_t)(((slot - n) & 0x7ffff) << 5);   // ldr x16, destination
            n++;
            t[n++] = 0xd63f0200u;                          // blr x16
        } else {
            t[n++] = i;
        }
    }
    uint64_t resume = (uint64_t)(uintptr_t)(function + Prologue);
    memcpy(&t[Return], &resume, 8);
    t[n] = 0x58000010u | (uint32_t)(((Return - n) & 0x7ffff) << 5);         // ldr x16, resume
    n++;
    t[n++] = 0xd61f0200u;                                  // br x16
    t[early] = 0x35000000u | (uint32_t)(((n - early) & 0x7ffff) << 5) | 17;  // cbnz w17, ret
    t[n++] = 0xd65f03c0u;                                  // ret
    t[Flag] = 0;
    __builtin___clear_cache((char *)t, (char *)(t + 64));

    uintptr_t page = (uintptr_t)function & ~(uintptr_t)0xfff;
    if (mprotect((void *)page, 8192, PROT_READ | PROT_WRITE | PROT_EXEC) != 0) {
        perry_trace(PERRY_TRACE_LOAD, "cannot write to %s: %s", name, strerror(errno));
        return;
    }
    uint64_t entry = (uint64_t)(uintptr_t)t;
    function[0] = 0x58000050u;                             // ldr x16, #8
    function[1] = 0xd61f0200u;                             // br x16
    memcpy(&function[2], &entry, 8);
    __builtin___clear_cache((char *)function, (char *)(function + 4));
    mprotect((void *)page, 8192, PROT_READ | PROT_EXEC);
    perry_trace(PERRY_TRACE_LOAD, "%s runs once (%s)", name,
                strrchr(image->path, '/') ? strrchr(image->path, '/') + 1 : image->path);
}

void perry_make_calls_once(perry_image *image) {
    const struct symtab_command *st = image->symtab;
    if (!st)
        return;
    const struct nlist_64 *syms = perry_image_fileoff(image, st->symoff);
    const char *strings = perry_image_fileoff(image, st->stroff);
    if (!syms || !strings) {
        perry_trace(PERRY_TRACE_LOAD, "%s: no symbol table to look for once-only functions in", image->path);
        return;
    }
    for (uint32_t i = 0; i < st->nsyms; i++) {
        const struct nlist_64 *sym = &syms[i];
        if ((sym->n_type & N_STAB) || (sym->n_type & N_TYPE) != N_SECT || sym->n_strx >= st->strsize)
            continue;
        const char *symbol = strings + sym->n_strx;
        if (symbol[0] != '_' || symbol[1] != 'i')
            continue;
        for (const char *const *name = once_functions; *name; name++)
            if (strcmp(symbol, *name) == 0)
                make_once(image, *name, perry_image_vmaddr(image, sym->n_value));
    }
}

#else

void perry_make_calls_once(perry_image *image) {}

#endif

// An app extension is a process that ends when its work is done, and says so
// by calling exit. Run inside its host's, it has nothing left to do and
// must not end the host: the thread that called waits for good. Ending the
// thread instead would unwind its frames, which Perry cannot do through
// Mach-O code.
void perry_extension_exit(int status) {
    perry_trace(PERRY_TRACE_LOAD, "an app extension exits (status %d)", status);
    for (;;)
        pause();
}
