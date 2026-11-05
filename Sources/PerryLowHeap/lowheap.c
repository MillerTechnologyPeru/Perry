#define _GNU_SOURCE

// libPerryLowHeap: the process's malloc, from a window just above 4 GB, as
// iOS's heap is. Some games keep pointers in 32 bits and restore them by
// setting bit 32 (Sonic 4 Episode II does), which only works for memory
// between 4 GB and 8 GB; glibc's heap is far above that.
//
// Loaded with LD_PRELOAD, it replaces malloc for everything in the process,
// as glibc documents, so memory may be freed by any library whichever
// allocated it. Small sizes come from per-size-class free lists, carved
// from the window; large ones are runs of pages, coalesced when freed and
// given back to the kernel. Without the window (or once it is full),
// allocations are glibc's.

#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

extern void *__libc_malloc(size_t);
extern void __libc_free(void *);
extern void *__libc_calloc(size_t, size_t);
extern void *__libc_realloc(void *, size_t);
extern void *__libc_memalign(size_t, size_t);

#define EXPORT __attribute__((visibility("default")))

#define WINDOW_START 0x140000000ull
#define WINDOW_END   0x200000000ull
#define PAGE         4096ull
#define HEADER       16ull
#define MAGIC        0x50455259u     // "PERY"
#define ALIGNED      0x414C4E44u     // "ALND"
#define SMALL_MAX    32768ull
#define LARGE_SPLIT  65536ull

/// Before each block: what it is, and how much it holds.
typedef struct header {
    uint32_t magic;
    uint32_t size_class;        // small blocks' class; large blocks' is CLASS_LARGE
    uint64_t size;              // usable bytes, or an aligned block's offset
} header;

#define CLASS_LARGE 0xFFFFFFFFu

// MARK: - The window

static _Atomic int state;           // 0 untried, 1 initializing, 2 ready, 3 unavailable
static pthread_mutex_t top_lock = PTHREAD_MUTEX_INITIALIZER;
static uint64_t top = WINDOW_START;  // the window above here is unused

static bool ready(void) {
    int s = atomic_load_explicit(&state, memory_order_acquire);
    if (s == 2) return true;
    if (s == 3) return false;
    int expected = 0;
    if (atomic_compare_exchange_strong(&state, &expected, 1)) {
        void *p = mmap((void *)WINDOW_START, WINDOW_END - WINDOW_START, PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE | MAP_FIXED_NOREPLACE, -1, 0);
        bool ok = p == (void *)WINDOW_START;
        if (!ok && p != MAP_FAILED) munmap(p, WINDOW_END - WINDOW_START);
        if (!ok) {
            static const char message[] = "perry: low heap: the window above 4 GB is taken; using glibc's heap\n";
            (void)!write(2, message, sizeof message - 1);
        }
        atomic_store_explicit(&state, ok ? 2 : 3, memory_order_release);
        return ok;
    }
    while ((s = atomic_load_explicit(&state, memory_order_acquire)) == 1) sched_yield();
    return s == 2;
}

static bool in_window(const void *p) { return (uint64_t)(uintptr_t)p >= WINDOW_START && (uint64_t)(uintptr_t)p < WINDOW_END; }

/// Fresh, zeroed memory from the window; NULL once it's used up.
static void *carve(uint64_t bytes) {
    pthread_mutex_lock(&top_lock);
    void *p = NULL;
    if (top + bytes <= WINDOW_END) {
        p = (void *)(uintptr_t)top;
        top += bytes;
    }
    pthread_mutex_unlock(&top_lock);
    return p;
}

// MARK: - Small blocks

// Classes: 16-byte steps to 512, then four to each doubling, to 32 KB.
#define CLASSES 72
static uint64_t class_sizes[CLASSES];
static int class_count;
static struct { pthread_mutex_t lock; void *free; } classes[CLASSES];
static pthread_once_t classes_once = PTHREAD_ONCE_INIT;

static void make_classes(void) {
    int n = 0;
    for (uint64_t s = 16; s <= 512; s += 16) class_sizes[n++] = s;
    for (uint64_t base = 512; base < SMALL_MAX; base *= 2)
        for (int q = 1; q <= 4 && n < CLASSES; q++) class_sizes[n++] = base + base / 4 * q;
    class_count = n;
    for (int i = 0; i < n; i++) pthread_mutex_init(&classes[i].lock, NULL);
}

static int class_for(uint64_t size) {
    if (size <= 512) return size ? (int)((size + 15) / 16) - 1 : 0;
    int low = 32, high = class_count - 1;
    while (low < high) {
        int mid = (low + high) / 2;
        if (class_sizes[mid] >= size) high = mid; else low = mid + 1;
    }
    return low;
}

static void *small_alloc(uint64_t size) {
    pthread_once(&classes_once, make_classes);
    int c = class_for(size);
    uint64_t block = class_sizes[c] + HEADER;
    pthread_mutex_lock(&classes[c].lock);
    header *h = classes[c].free;
    if (h) {
        classes[c].free = *(void **)(h + 1);
    } else {
        // A run of blocks: 64 KB, or eight of the class's size.
        uint64_t run = block * 8 > LARGE_SPLIT ? block * 8 : LARGE_SPLIT / block * block;
        uint8_t *span = carve((run + PAGE - 1) & ~(PAGE - 1));
        if (!span) { pthread_mutex_unlock(&classes[c].lock); return NULL; }
        uint64_t count = run / block;
        for (uint64_t i = 1; i < count; i++) {
            header *rest = (header *)(span + i * block);
            *rest = (header){ MAGIC, (uint32_t)c, class_sizes[c] };
            *(void **)(rest + 1) = classes[c].free;
            classes[c].free = rest;
        }
        h = (header *)span;
    }
    pthread_mutex_unlock(&classes[c].lock);
    *h = (header){ MAGIC, (uint32_t)c, class_sizes[c] };
    return h + 1;
}

static void small_free(header *h) {
    int c = (int)h->size_class;
    pthread_mutex_lock(&classes[c].lock);
    *(void **)(h + 1) = classes[c].free;
    classes[c].free = h;
    pthread_mutex_unlock(&classes[c].lock);
}

// MARK: - Large blocks

/// A free run of pages, in a list sorted by address so neighbors merge.
typedef struct run { struct run *next; uint64_t bytes; } run;
static pthread_mutex_t large_lock = PTHREAD_MUTEX_INITIALIZER;
static run *free_runs;

static void *large_alloc(uint64_t size) {
    uint64_t bytes = (size + HEADER + PAGE - 1) & ~(PAGE - 1);
    pthread_mutex_lock(&large_lock);
    run **best = NULL;
    for (run **r = &free_runs; *r; r = &(*r)->next)
        if ((*r)->bytes >= bytes && (!best || (*r)->bytes < (*best)->bytes)) best = r;
    uint8_t *p = NULL;
    if (best) {
        run *found = *best;
        if (found->bytes - bytes >= LARGE_SPLIT) {
            run *rest = (run *)((uint8_t *)found + bytes);
            rest->next = found->next;
            rest->bytes = found->bytes - bytes;
            *best = rest;
        } else {
            bytes = found->bytes;
            *best = found->next;
        }
        p = (uint8_t *)found;
    }
    pthread_mutex_unlock(&large_lock);
    if (!p && !(p = carve(bytes))) return NULL;
    header *h = (header *)p;
    *h = (header){ MAGIC, CLASS_LARGE, bytes - HEADER };
    return h + 1;
}

static void large_free(header *h) {
    uint64_t bytes = h->size + HEADER;
    // The pages after the first go back to the kernel, and read as zero.
    if (bytes > PAGE) madvise((uint8_t *)h + PAGE, bytes - PAGE, MADV_DONTNEED);
    run *freed = (run *)h;
    freed->bytes = bytes;
    pthread_mutex_lock(&large_lock);
    run **r = &free_runs;
    while (*r && *r < freed) r = &(*r)->next;
    freed->next = *r;
    *r = freed;
    if (freed->next && (uint8_t *)freed + freed->bytes == (uint8_t *)freed->next) {
        freed->bytes += freed->next->bytes;
        freed->next = freed->next->next;
    }
    // And the one before, found again from the start.
    for (run *prev = free_runs; prev && prev != freed; prev = prev->next) {
        if (prev->next == freed && (uint8_t *)prev + prev->bytes == (uint8_t *)freed) {
            prev->bytes += freed->bytes;
            prev->next = freed->next;
            break;
        }
    }
    pthread_mutex_unlock(&large_lock);
}

// MARK: - Blocks

static header *header_of(void *p) {
    header *h = (header *)p - 1;
    if (h->magic == ALIGNED) h = (header *)((uint8_t *)p - h->size) - 1;
    return h->magic == MAGIC ? h : NULL;
}

static void *allocate(size_t size) {
    if (!ready()) return __libc_malloc(size);
    if (size > WINDOW_END - WINDOW_START) { errno = ENOMEM; return NULL; }
    void *p = size <= SMALL_MAX ? small_alloc(size) : large_alloc(size);
    if (p) return p;
    static _Atomic bool warned;
    if (!atomic_exchange(&warned, true)) {
        static const char message[] = "perry: low heap: the window above 4 GB is full; using glibc's heap\n";
        (void)!write(2, message, sizeof message - 1);
    }
    return __libc_malloc(size);
}

static size_t usable(void *p) {
    header *h = (header *)p - 1;
    if (h->magic == ALIGNED) {
        header *real = header_of(p);
        return real ? real->size - h->size : 0;
    }
    return h->magic == MAGIC ? h->size : 0;
}

EXPORT void *malloc(size_t size) { return allocate(size); }

EXPORT void free(void *p) {
    if (!p) return;
    if (!in_window(p)) { __libc_free(p); return; }
    header *h = header_of(p);
    if (!h) return;     // not a block: Darwin's free would stop; leaving it is safer than corrupting lists
    if (h->size_class == CLASS_LARGE) large_free(h); else small_free(h);
}

EXPORT void *calloc(size_t count, size_t size) {
    size_t bytes;
    if (__builtin_mul_overflow(count, size, &bytes)) { errno = ENOMEM; return NULL; }
    if (!ready()) return __libc_calloc(count, size);
    void *p = allocate(bytes);
    if (p) memset(p, 0, bytes);
    return p;
}

EXPORT void *realloc(void *p, size_t size) {
    if (!p) return allocate(size);
    if (!size) { free(p); return NULL; }
    if (!in_window(p)) return __libc_realloc(p, size);
    size_t have = usable(p);
    if (size <= have && (have <= SMALL_MAX || size > have / 2)) return p;
    void *q = allocate(size);
    if (!q) return NULL;
    memcpy(q, p, have < size ? have : size);
    free(p);
    return q;
}

EXPORT void *reallocarray(void *p, size_t count, size_t size) {
    size_t bytes;
    if (__builtin_mul_overflow(count, size, &bytes)) { errno = ENOMEM; return NULL; }
    return realloc(p, bytes);
}

static void *aligned(size_t alignment, size_t size) {
    if (alignment <= HEADER) return allocate(size);
    if (!ready()) return __libc_memalign(alignment, size);
    uint8_t *raw = allocate(size + alignment + HEADER);
    if (!raw || !in_window(raw)) {
        if (raw) __libc_free(raw);
        return __libc_memalign(alignment, size);
    }
    uintptr_t at = ((uintptr_t)raw + HEADER + alignment - 1) & ~(uintptr_t)(alignment - 1);
    if (at == (uintptr_t)raw) return raw;
    header *h = (header *)at - 1;
    *h = (header){ ALIGNED, 0, at - (uintptr_t)raw };
    return (void *)at;
}

static bool power_of_two(size_t n) { return n && !(n & (n - 1)); }

EXPORT int posix_memalign(void **out, size_t alignment, size_t size) {
    if (!power_of_two(alignment) || alignment % sizeof(void *)) return EINVAL;
    void *p = aligned(alignment, size);
    if (!p) return ENOMEM;
    *out = p;
    return 0;
}

EXPORT void *aligned_alloc(size_t alignment, size_t size) {
    if (!power_of_two(alignment)) { errno = EINVAL; return NULL; }
    return aligned(alignment, size);
}

EXPORT void *memalign(size_t alignment, size_t size) {
    if (!power_of_two(alignment)) { errno = EINVAL; return NULL; }
    return aligned(alignment, size);
}

EXPORT void *valloc(size_t size) { return aligned(PAGE, size); }
EXPORT void *pvalloc(size_t size) { return aligned(PAGE, (size + PAGE - 1) & ~(PAGE - 1)); }

/// Blocks outside the window are glibc's, which has no exported name for
/// its own; they are only those made before the window was reserved.
EXPORT size_t malloc_usable_size(void *p) { return p && in_window(p) ? usable(p) : 0; }

// MARK: - fork

static void prepare(void) {
    pthread_mutex_lock(&large_lock);
    pthread_mutex_lock(&top_lock);
    for (int i = 0; i < class_count; i++) pthread_mutex_lock(&classes[i].lock);
}

static void resume(void) {
    for (int i = class_count - 1; i >= 0; i--) pthread_mutex_unlock(&classes[i].lock);
    pthread_mutex_unlock(&top_lock);
    pthread_mutex_unlock(&large_lock);
}

__attribute__((constructor)) static void install(void) {
    pthread_once(&classes_once, make_classes);
    pthread_atfork(prepare, resume, resume);
}
