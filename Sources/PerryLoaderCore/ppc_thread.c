// The thread pointer on ppc. Linux keeps it in r2, which glibc reads for
// every thread-local variable (errno, malloc's caches) and compilers never
// reload; Darwin's code uses r2 as a scratch register. So a call from Darwin
// code into Linux code first sets r2 again, from the stack pointer: a table
// with a word for each 4 KB page of the address space holds the thread
// pointer of the thread whose stack is there. Every thread notes its stack
// when it starts (the pthread_create here takes the place of glibc's for the
// whole process), and the main thread when the loader starts.
//
// What the loader binds a Darwin import to is a stub that does that, then
// jumps to the Linux function, unless the import is data:
//
//     rlwinm r11, r1, 22, 10, 29      // the stack page's word
//     lis    r12, table@h
//     ori    r12, r12, table@l
//     lwzx   r0, r11, r12
//     cmpwi  r0, 0                    // no thread noted there: r2 stays
//     beq    1f
//     mr     r2, r0
//  1: lis    r12, function@h
//     ori    r12, r12, function@l
//     mtctr  r12
//     bctr
//
// r0, r11, r12 and cr0 are scratch at a call in both ABIs.

#define _GNU_SOURCE

#if defined(__powerpc__) && !defined(__powerpc64__)

#include "image.h"
#include "log.h"

#include <dlfcn.h>
#include <errno.h>
#include <elf.h>
#include <link.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>

enum { PAGE_SHIFT = 12, PAGE_COUNT = 1u << (32 - PAGE_SHIFT) };

// The main thread's stack is noted up to this far below its top: with an
// unlimited stack limit, glibc reports all of the address space below it.
enum { MAIN_STACK_LIMIT = 64u << 20 };

static uint32_t *thread_pointers;

static uint32_t *table(void) {
    if (!thread_pointers) {
        void *map = mmap(NULL, PAGE_COUNT * sizeof(uint32_t), PROT_READ | PROT_WRITE,
                         MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
        if (map == MAP_FAILED)
            perry_fatal("cannot reserve the thread pointer table");
        thread_pointers = map;
    }
    return thread_pointers;
}

static void note_stack(uintptr_t low, uintptr_t high) {
    uint32_t *pages = table();
    uint32_t pointer;
    __asm__("mr %0, 2" : "=r"(pointer));
    for (uintptr_t page = low >> PAGE_SHIFT; page < (high + (1u << PAGE_SHIFT) - 1) >> PAGE_SHIFT; page++)
        pages[page] = pointer;
}

void perry_ppc_note_thread(void) {
    pthread_attr_t attr;
    void *stack;
    size_t size;
    if (pthread_getattr_np(pthread_self(), &attr) != 0)
        perry_fatal("cannot find this thread's stack");
    if (pthread_attr_getstack(&attr, &stack, &size) != 0)
        perry_fatal("cannot find this thread's stack");
    pthread_attr_destroy(&attr);
    uintptr_t high = (uintptr_t)stack + size;
    uintptr_t low = (uintptr_t)stack;
    if (size > MAIN_STACK_LIMIT)
        low = high - MAIN_STACK_LIMIT;
    note_stack(low, high);
}

void perry_ppc_note_stack(void *low, size_t size) {
    note_stack((uintptr_t)low, (uintptr_t)low + size);
}

int perry_ppc_emit_thread_pointer(uint32_t *code) {
    uint32_t pages = (uint32_t)(uintptr_t)table();
    code[0] = 0x542bb2bau;                      // rlwinm r11, r1, 22, 10, 29
    code[1] = 0x3d800000u | (pages >> 16);      // lis r12, table@h
    code[2] = 0x618c0000u | (pages & 0xffff);   // ori r12, r12, table@l
    code[3] = 0x7c0b602eu;                      // lwzx r0, r11, r12
    code[4] = 0x2c000000u;                      // cmpwi r0, 0
    code[5] = 0x41820008u;                      // beq 1f
    code[6] = 0x7c020378u;                      // mr r2, r0
    return 7;
}

// MARK: - Stubs

enum { STUB_WORDS = 12, STUBS_PER_PAGE = 0x4000 / (STUB_WORDS * 4) };

static pthread_mutex_t stub_lock = PTHREAD_MUTEX_INITIALIZER;
static struct { void *function; uint32_t *stub; } *stub_map;
static size_t stub_map_size, stub_map_count;
static uint32_t *stub_page;
static size_t stub_page_used;

static void **find_slot(void *function, uint32_t ***stub_out) {
    size_t mask = stub_map_size - 1;
    for (size_t i = ((uintptr_t)function >> 2) & mask;; i = (i + 1) & mask) {
        if (stub_map[i].function == function || !stub_map[i].function) {
            *stub_out = &stub_map[i].stub;
            return &stub_map[i].function;
        }
    }
}

static void grow_map(void) {
    size_t old_size = stub_map_size;
    __typeof__(stub_map) old = stub_map;
    stub_map_size = old_size ? old_size * 2 : 1024;
    stub_map = calloc(stub_map_size, sizeof(*stub_map));
    for (size_t i = 0; i < old_size; i++) {
        if (!old[i].function)
            continue;
        uint32_t **stub;
        void **slot = find_slot(old[i].function, &stub);
        *slot = old[i].function;
        *stub = old[i].stub;
    }
    free(old);
}

static uint32_t *make_stub(void *function) {
    if (!stub_page || stub_page_used == STUBS_PER_PAGE) {
        stub_page = mmap(NULL, 0x4000, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (stub_page == MAP_FAILED)
            perry_fatal("cannot allocate a page of thread pointer stubs");
        stub_page_used = 0;
    }
    uint32_t *code = stub_page + stub_page_used++ * STUB_WORDS;
    int n = perry_ppc_emit_thread_pointer(code);
    uint32_t target = (uint32_t)(uintptr_t)function;
    code[n++] = 0x3d800000u | (target >> 16);       // lis r12, function@h
    code[n++] = 0x618c0000u | (target & 0xffff);    // ori r12, r12, function@l
    code[n++] = 0x7d8903a6u;                        // mtctr r12
    code[n++] = 0x4e800420u;                        // bctr
    __builtin___clear_cache((char *)code, (char *)(code + n));
    return code;
}

// Whether an address is a function of a Linux library or of perry itself,
// rather than data or Darwin code.
static bool is_linux_function(void *address) {
    Dl_info info;
    const ElfW(Sym) *symbol = NULL;
    if (!dladdr1(address, &info, (void **)&symbol, RTLD_DL_SYMENT) || !symbol || info.dli_saddr != address)
        return false;
    unsigned type = ELF32_ST_TYPE(symbol->st_info);
    return type == STT_FUNC || type == STT_GNU_IFUNC;
}

void *perry_ppc_linux_entry(void *address) {
    if (!address || !is_linux_function(address))
        return address;
    return perry_ppc_thread_stub(address);
}

void *perry_ppc_thread_stub(void *address) {
    pthread_mutex_lock(&stub_lock);
    if (stub_map_count * 2 >= stub_map_size)
        grow_map();
    uint32_t **stub;
    void **slot = find_slot(address, &stub);
    if (!*slot) {
        *slot = address;
        *stub = make_stub(address);
        stub_map_count++;
        perry_trace(PERRY_TRACE_BIND, "r2 stub %p for %p", (void *)*stub, address);
    }
    uint32_t *result = *stub;
    pthread_mutex_unlock(&stub_lock);
    return result;
}

// MARK: - Threads

struct thread_start {
    void *(*start)(void *);
    void *argument;
};

static void *start_thread(void *context) {
    struct thread_start start = *(struct thread_start *)context;
    free(context);
    perry_ppc_note_thread();
    return start.start(start.argument);
}

// Every library's threads start here, libdispatch's and the program's
// alike, so each notes its stack before it runs anything.
__attribute__((visibility("default")))
int pthread_create(pthread_t *thread, const pthread_attr_t *attr, void *(*start)(void *), void *argument) {
    static int (*glibc_create)(pthread_t *, const pthread_attr_t *, void *(*)(void *), void *);
    if (!glibc_create)
        glibc_create = (__typeof__(glibc_create))dlsym(RTLD_NEXT, "pthread_create");
    if (!glibc_create)
        perry_fatal("cannot find glibc's pthread_create");
    struct thread_start *context = malloc(sizeof(*context));
    if (!context)
        return EAGAIN;
    context->start = start;
    context->argument = argument;
    int result = glibc_create(thread, attr, start_thread, context);
    if (result != 0)
        free(context);
    return result;
}

#endif
