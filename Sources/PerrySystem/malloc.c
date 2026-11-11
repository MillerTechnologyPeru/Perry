// Darwin's malloc zones and malloc introspection over glibc's heap. Every
// zone allocates from the one heap; a zone is a malloc_zone_t whose leading
// function pointers are where Darwin's are, so code that calls through them
// (zone->malloc(zone, size)) works too. Destroying a zone does not free what
// was allocated in it, which Darwin would.

#define _GNU_SOURCE
#include "PerrySystem.h"

#include <errno.h>
#include <fcntl.h>
#include <malloc.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/uio.h>
#include <unistd.h>

/// malloc_zone_t (malloc/malloc.h), up to the fields code reaches into.
typedef struct darwin_malloc_zone {
    void *reserved1;
    void *reserved2;
    size_t (*size)(struct darwin_malloc_zone *zone, const void *ptr);
    void *(*malloc)(struct darwin_malloc_zone *zone, size_t size);
    void *(*calloc)(struct darwin_malloc_zone *zone, size_t count, size_t size);
    void *(*valloc)(struct darwin_malloc_zone *zone, size_t size);
    void (*free)(struct darwin_malloc_zone *zone, void *ptr);
    void *(*realloc)(struct darwin_malloc_zone *zone, void *ptr, size_t size);
    void (*destroy)(struct darwin_malloc_zone *zone);
    const char *zone_name;
    unsigned (*batch_malloc)(struct darwin_malloc_zone *zone, size_t size, void **results, unsigned count);
    void (*batch_free)(struct darwin_malloc_zone *zone, void **ptrs, unsigned count);
    void *introspect;
    unsigned version;
    void *(*memalign)(struct darwin_malloc_zone *zone, size_t alignment, size_t size);
    void (*free_definite_size)(struct darwin_malloc_zone *zone, void *ptr, size_t size);
    size_t (*pressure_relief)(struct darwin_malloc_zone *zone, size_t goal);
} darwin_malloc_zone;

// MARK: - Sizes

/// The room a request gets, as Darwin's allocator gives it and programs come
/// to lean on without knowing: up to 1008 bytes in 16-byte steps, from there
/// up to 15 KB in 512-byte steps, and beyond that in 16 KB pages. Darwin
/// also keeps nothing of its own between blocks, where glibc keeps the next
/// block's size; so a block in the 512-byte steps gets 64 bytes more here,
/// for a write a little past Darwin's room to land in, as it would land in
/// a neighbor there. (Monopoly copies 144 bytes into the last 72 of a
/// 4560-byte object.)
static size_t block_size(size_t size) {
    if (size <= 1008) return size <= 16 ? 16 : (size + 15) & ~(size_t)15;
    if (size <= 15 * 1024) return ((size + 511) & ~(size_t)511) + 64;
    size_t pages = (size + 16383) & ~(size_t)16383;
    return pages < size ? size : pages;
}

/// Large blocks stay in the heap, among other blocks, where glibc would map
/// each by itself with nothing after it. On Darwin what follows a block is
/// mostly mapped, and programs read a little past a block's end without
/// knowing. (Nanosaur 2 copies a model's arrays from a buffer some
/// kilobytes short.) 32 MB is the most glibc takes; larger blocks are still
/// mapped. A 32-bit program's heaps are too small for it.
__attribute__((constructor)) static void keep_blocks_in_heap(void) {
    if (sizeof(void *) == 8) mallopt(M_MMAP_THRESHOLD, 32 << 20);
}

/// Blocks come zeroed. Darwin's allocator has cleared memory as it is freed
/// since iOS 16.1, so what malloc gives is zero in practice, and programs
/// lean on that too without knowing. (Nanosaur 2 releases the object a
/// structure straight from malloc points to before it first sets it.)
/// A zeroed block aligned to 16 bytes, as Darwin's blocks are. glibc's are
/// to 8 in a 32-bit program, where compiled code stores a 128-bit vector
/// to a structure it takes to be aligned to 16 (and faults when it is not).
static void *zeroed_block(size_t room) {
    if (sizeof(void *) == 8) return calloc(1, room);
    void *block = NULL;
    if (posix_memalign(&block, 16, room) != 0) return NULL;
    memset(block, 0, room);
    return block;
}

void *darwin_malloc(size_t size) DARWIN_SYMBOL(malloc);
void *darwin_malloc(size_t size) { return zeroed_block(block_size(size)); }

/// Clears a block that glibc gave with what was there before.
static void *cleared(void *ptr) {
    if (ptr) memset(ptr, 0, malloc_usable_size(ptr));
    return ptr;
}

void *darwin_calloc(size_t count, size_t size) DARWIN_SYMBOL(calloc);
void *darwin_calloc(size_t count, size_t size) {
    size_t total;
    if (__builtin_mul_overflow(count, size, &total)) return calloc(count, size);
    return zeroed_block(block_size(total));
}

/// A size of zero gives a block of the least size, as Darwin's does, where
/// glibc's frees the block.
/// A block aligned to a page, cleared as the others are. Programs that
/// bring their own allocator look it up beside malloc.
void *darwin_valloc(size_t size) DARWIN_SYMBOL(valloc);
void *darwin_valloc(size_t size) {
    void *block = NULL;
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    if (posix_memalign(&block, page, block_size(size)) != 0) return NULL;
    return cleared(block);
}

void *darwin_realloc(void *ptr, size_t size) DARWIN_SYMBOL(realloc);
/// The room a block gains is cleared, as it is on Darwin.
void *darwin_realloc(void *ptr, size_t size) {
    size_t before = ptr ? malloc_usable_size(ptr) : 0;
    size_t room = block_size(size);
    void *resized = realloc(ptr, room);
    if (resized && sizeof(void *) == 4 && ((uintptr_t)resized & 15) != 0) {
        // The block moved to an address aligned to 8: move it to 16.
        void *moved = NULL;
        if (posix_memalign(&moved, 16, room) == 0) {
            size_t kept = malloc_usable_size(resized);
            memcpy(moved, resized, kept < room ? kept : room);
            free(resized);
            resized = moved;
        }
    }
    if (resized) {
        size_t after = malloc_usable_size(resized);
        if (after > before) memset((char *)resized + before, 0, after - before);
    }
    return resized;
}

int darwin_posix_memalign(void **ptr, size_t alignment, size_t size) DARWIN_SYMBOL(posix_memalign);
int darwin_posix_memalign(void **ptr, size_t alignment, size_t size) {
    int error = posix_memalign(ptr, alignment, block_size(size));
    if (!error) cleared(*ptr);
    return error;
}

/// The size a multiple of the alignment still, as C asks.
void *darwin_aligned_alloc(size_t alignment, size_t size) DARWIN_SYMBOL(aligned_alloc);
void *darwin_aligned_alloc(size_t alignment, size_t size) {
    size_t room = block_size(size);
    if (alignment > 1) room = (room + alignment - 1) / alignment * alignment;
    return cleared(aligned_alloc(alignment, room));
}

// The typed forms, which a type identifier is passed to last for typed
// memory allocation; the identifier is not used here.

void *darwin_malloc_type_malloc(size_t size, uint64_t type_id) DARWIN_SYMBOL(malloc_type_malloc);
void *darwin_malloc_type_malloc(size_t size, uint64_t type_id) { (void)type_id; return darwin_malloc(size); }

void *darwin_malloc_type_calloc(size_t count, size_t size, uint64_t type_id) DARWIN_SYMBOL(malloc_type_calloc);
void *darwin_malloc_type_calloc(size_t count, size_t size, uint64_t type_id) { (void)type_id; return darwin_calloc(count, size); }

void *darwin_malloc_type_realloc(void *ptr, size_t size, uint64_t type_id) DARWIN_SYMBOL(malloc_type_realloc);
void *darwin_malloc_type_realloc(void *ptr, size_t size, uint64_t type_id) { (void)type_id; return darwin_realloc(ptr, size); }

int darwin_malloc_type_posix_memalign(void **ptr, size_t alignment, size_t size, uint64_t type_id)
    DARWIN_SYMBOL(malloc_type_posix_memalign);
int darwin_malloc_type_posix_memalign(void **ptr, size_t alignment, size_t size, uint64_t type_id) {
    (void)type_id;
    return darwin_posix_memalign(ptr, alignment, size);
}

// MARK: - Whose block

// Darwin's malloc_size gives 0 for a pointer malloc did not give out, and
// programs ask it for just that: an engine with heaps of its own (Unity's
// memory manager) takes a block for the system's when its size is not 0,
// and frees it as one. glibc's malloc_usable_size reads the words before
// any pointer as a block's header, and so answers for them all. Here the
// header is looked at first, as glibc's own checks would: the size it
// gives must be a block's, the block after it must say this one is in use,
// and what an arena's or a mapping's own records say must agree.

/// Pages a read has found, so asking the kernel is not needed again: Swift's
/// arrays ask for their blocks' sizes each time they grow. A page unmapped
/// since would fault, for a pointer into it, which no live block is.
enum { KNOWN_PAGES = 1024, KNOWN_PAGE_SHIFT = 12 };
static _Atomic uintptr_t known_pages[KNOWN_PAGES];

static bool read_from_kernel(uintptr_t address, void *out, size_t count);

/// Reads `count` bytes at `address`, if they are there to read: a pointer
/// that is not a block's may have anything around it, or nothing.
static bool read_memory(uintptr_t address, void *out, size_t count) {
    uintptr_t page = address >> KNOWN_PAGE_SHIFT;
    bool one_page = page == (address + count - 1) >> KNOWN_PAGE_SHIFT;
    // Stored one more than the page, so an empty slot is no page.
    _Atomic uintptr_t *known = &known_pages[page % KNOWN_PAGES];
    if (one_page && atomic_load_explicit(known, memory_order_relaxed) == page + 1) {
        memcpy(out, (const void *)address, count);
        return true;
    }
    if (!read_from_kernel(address, out, count)) return false;
    if (one_page) atomic_store_explicit(known, page + 1, memory_order_relaxed);
    return true;
}

static bool read_from_kernel(uintptr_t address, void *out, size_t count) {
    static int cannot_read_self;
    if (!__atomic_load_n(&cannot_read_self, __ATOMIC_RELAXED)) {
        struct iovec local = { out, count }, remote = { (void *)address, count };
        ssize_t got = process_vm_readv(getpid(), &local, 1, &remote, 1, 0);
        if (got == (ssize_t)count) return true;
        if (got >= 0 || (errno != EPERM && errno != ENOSYS)) return false;
        __atomic_store_n(&cannot_read_self, 1, __ATOMIC_RELAXED);
    }
    // Where a process may not read itself that way: through a pipe, which
    // the kernel fills from the address, or fails to.
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    static int ends[2] = { -1, -1 };
    bool ok = false;
    pthread_mutex_lock(&lock);
    if (ends[0] >= 0 || pipe2(ends, O_CLOEXEC | O_NONBLOCK) == 0)
        ok = count <= 4096 && write(ends[1], (const void *)address, count) == (ssize_t)count
            && read(ends[0], out, count) == (ssize_t)count;
    pthread_mutex_unlock(&lock);
    return ok;
}

/// The room in a block glibc's malloc gave out and has not been given
/// back; 0 for any other pointer.
static size_t block_room(const void *ptr) {
    enum { PREVIOUS_IN_USE = 1, MAPPED = 2, OTHER_ARENA = 4, FLAGS = 7, HEADER = 2 * sizeof(size_t) };
    // An arena that is not the main one is made of heaps this large at
    // most, each starting where its size divides the address: the arena,
    // the heap before, then the heap's size and how much of it is in use.
    // Twice the largest mmap threshold: 64 MB with 64-bit words, 32 MB with
    // 32-bit ones.
    const uintptr_t heap_span = (uintptr_t)(8 * sizeof(long)) << 20;
    // No block or offset is larger: 64 TB with 64-bit words, half the
    // address space with 32-bit ones.
    const size_t largest = (size_t)1 << (sizeof(size_t) == 8 ? 46 : 31);
    uintptr_t address = (uintptr_t)ptr;
    if (!address || (address & (HEADER - 1))) return 0;
    int saved = errno;
    size_t room = 0, head[2], next[2];
    uintptr_t chunk = address - HEADER;
    if (!read_memory(chunk, head, sizeof head)) goto done;
    size_t size = head[1] & ~(size_t)FLAGS;
    if (size < 2 * HEADER || (size & (HEADER - 1)) || size > largest) goto done;
    if (head[1] & MAPPED) {
        // A mapping of its own: whole pages, the block some way into them.
        size_t page = (size_t)sysconf(_SC_PAGESIZE), total = head[0] + size;
        uint8_t last;
        if ((head[1] & (PREVIOUS_IN_USE | OTHER_ARENA)) || head[0] > largest || ((chunk - head[0]) | total) & (page - 1))
            goto done;
        if (!read_memory(chunk - head[0] + total - 1, &last, 1)) goto done;
    } else {
        // In an arena: the block after says whether this one is in use,
        // and the one before, if it is free, how long it is.
        if (!read_memory(chunk + size, next, sizeof next)) goto done;
        size_t next_size = next[1] & ~(size_t)FLAGS;
        if (!(next[1] & PREVIOUS_IN_USE) || (next[1] & MAPPED) || next_size < HEADER || (next_size & (HEADER - 1))
            || next_size > largest)
            goto done;
        if (!(head[1] & PREVIOUS_IN_USE)) {
            size_t before[2];
            if (head[0] < 2 * HEADER || (head[0] & (HEADER - 1)) || head[0] > chunk || !read_memory(chunk - head[0], before, sizeof before)
                || (before[1] & ~(size_t)FLAGS) != head[0])
                goto done;
        }
        if (head[1] & OTHER_ARENA) {
            uintptr_t heap = chunk & ~(heap_span - 1);
            size_t record[4];
            if (!read_memory(heap, record, sizeof record) || record[2] > heap_span || record[3] > heap_span || record[2] > record[3]
                || chunk + size > heap + record[2])
                goto done;
        }
    }
    room = malloc_usable_size((void *)ptr);
done:
    errno = saved;
    return room;
}

static size_t zone_size(darwin_malloc_zone *zone, const void *ptr) {
    (void)zone;
    return block_room(ptr);
}

static void *zone_malloc(darwin_malloc_zone *zone, size_t size) { (void)zone; return darwin_malloc(size); }
static void *zone_calloc(darwin_malloc_zone *zone, size_t count, size_t size) { (void)zone; return darwin_calloc(count, size); }
static void *zone_valloc(darwin_malloc_zone *zone, size_t size) { (void)zone; return cleared(valloc(size)); }
static void zone_free(darwin_malloc_zone *zone, void *ptr) { (void)zone; free(ptr); }
static void *zone_realloc(darwin_malloc_zone *zone, void *ptr, size_t size) { (void)zone; return darwin_realloc(ptr, size); }

static void zone_destroy(darwin_malloc_zone *zone) {
    free((void *)zone->zone_name);
    free(zone);
}

static unsigned zone_batch_malloc(darwin_malloc_zone *zone, size_t size, void **results, unsigned count) {
    (void)zone;
    unsigned made = 0;
    while (made < count && (results[made] = darwin_malloc(size))) made++;
    return made;
}

static void zone_batch_free(darwin_malloc_zone *zone, void **ptrs, unsigned count) {
    (void)zone;
    for (unsigned i = 0; i < count; i++) free(ptrs[i]);
}

static void *zone_memalign(darwin_malloc_zone *zone, size_t alignment, size_t size) {
    (void)zone;
    void *ptr = NULL;
    return darwin_posix_memalign(&ptr, alignment, size) == 0 ? ptr : NULL;
}

static void zone_free_definite_size(darwin_malloc_zone *zone, void *ptr, size_t size) { (void)zone; (void)size; free(ptr); }
static size_t zone_pressure_relief(darwin_malloc_zone *zone, size_t goal) { (void)zone; (void)goal; return 0; }

static const darwin_malloc_zone zone_template = {
    .size = zone_size, .malloc = zone_malloc, .calloc = zone_calloc, .valloc = zone_valloc, .free = zone_free,
    .realloc = zone_realloc, .destroy = zone_destroy, .batch_malloc = zone_batch_malloc, .batch_free = zone_batch_free,
    .version = 10, .memalign = zone_memalign, .free_definite_size = zone_free_definite_size,
    .pressure_relief = zone_pressure_relief,
};

static darwin_malloc_zone default_zone = {
    .size = zone_size, .malloc = zone_malloc, .calloc = zone_calloc, .valloc = zone_valloc, .free = zone_free,
    .realloc = zone_realloc, .destroy = NULL, .zone_name = "DefaultMallocZone", .batch_malloc = zone_batch_malloc,
    .batch_free = zone_batch_free, .version = 10, .memalign = zone_memalign,
    .free_definite_size = zone_free_definite_size, .pressure_relief = zone_pressure_relief,
};

// MARK: - Zones

darwin_malloc_zone *darwin_malloc_default_zone(void) DARWIN_SYMBOL(malloc_default_zone);
darwin_malloc_zone *darwin_malloc_default_zone(void) { return &default_zone; }

darwin_malloc_zone *darwin_malloc_default_purgeable_zone(void) DARWIN_SYMBOL(malloc_default_purgeable_zone);
darwin_malloc_zone *darwin_malloc_default_purgeable_zone(void) { return &default_zone; }

darwin_malloc_zone *darwin_malloc_create_zone(size_t start_size, unsigned flags) DARWIN_SYMBOL(malloc_create_zone);
darwin_malloc_zone *darwin_malloc_create_zone(size_t start_size, unsigned flags) {
    (void)start_size; (void)flags;
    darwin_malloc_zone *zone = malloc(sizeof *zone);
    if (zone) *zone = zone_template;
    return zone;
}

void darwin_malloc_destroy_zone(darwin_malloc_zone *zone) DARWIN_SYMBOL(malloc_destroy_zone);
void darwin_malloc_destroy_zone(darwin_malloc_zone *zone) {
    if (zone && zone != &default_zone && zone->destroy) zone->destroy(zone);
}

void darwin_malloc_set_zone_name(darwin_malloc_zone *zone, const char *name) DARWIN_SYMBOL(malloc_set_zone_name);
void darwin_malloc_set_zone_name(darwin_malloc_zone *zone, const char *name) {
    if (!zone || zone == &default_zone) return;
    free((void *)zone->zone_name);
    zone->zone_name = name ? strdup(name) : NULL;
}

const char *darwin_malloc_get_zone_name(darwin_malloc_zone *zone) DARWIN_SYMBOL(malloc_get_zone_name);
const char *darwin_malloc_get_zone_name(darwin_malloc_zone *zone) { return zone ? zone->zone_name : NULL; }

/// Every block is in the default zone; a pointer that is no block's is in
/// none.
darwin_malloc_zone *darwin_malloc_zone_from_ptr(const void *ptr) DARWIN_SYMBOL(malloc_zone_from_ptr);
darwin_malloc_zone *darwin_malloc_zone_from_ptr(const void *ptr) { return block_room(ptr) ? &default_zone : NULL; }

// MARK: - Allocating in a zone

void *darwin_malloc_zone_malloc(darwin_malloc_zone *zone, size_t size) DARWIN_SYMBOL(malloc_zone_malloc);
void *darwin_malloc_zone_malloc(darwin_malloc_zone *zone, size_t size) { return zone->malloc(zone, size); }

void *darwin_malloc_zone_calloc(darwin_malloc_zone *zone, size_t count, size_t size) DARWIN_SYMBOL(malloc_zone_calloc);
void *darwin_malloc_zone_calloc(darwin_malloc_zone *zone, size_t count, size_t size) { return zone->calloc(zone, count, size); }

void *darwin_malloc_zone_valloc(darwin_malloc_zone *zone, size_t size) DARWIN_SYMBOL(malloc_zone_valloc);
void *darwin_malloc_zone_valloc(darwin_malloc_zone *zone, size_t size) { return zone->valloc(zone, size); }

void *darwin_malloc_zone_realloc(darwin_malloc_zone *zone, void *ptr, size_t size) DARWIN_SYMBOL(malloc_zone_realloc);
void *darwin_malloc_zone_realloc(darwin_malloc_zone *zone, void *ptr, size_t size) { return zone->realloc(zone, ptr, size); }

void *darwin_malloc_zone_memalign(darwin_malloc_zone *zone, size_t alignment, size_t size) DARWIN_SYMBOL(malloc_zone_memalign);
void *darwin_malloc_zone_memalign(darwin_malloc_zone *zone, size_t alignment, size_t size) {
    return zone->memalign(zone, alignment, size);
}

void darwin_malloc_zone_free(darwin_malloc_zone *zone, void *ptr) DARWIN_SYMBOL(malloc_zone_free);
void darwin_malloc_zone_free(darwin_malloc_zone *zone, void *ptr) { zone->free(zone, ptr); }

/// malloc_zone_malloc_with_options(zone, alignment, size, options): in
/// `zone` (the default one when NULL), aligned to `alignment` if more than
/// a pointer's, and zeroed with MALLOC_ZONE_MALLOC_OPTION_CLEAR (1). Under
/// memory tagging another option picks the tag, which Linux has no use for.
void *darwin_malloc_zone_malloc_with_options(darwin_malloc_zone *zone, size_t alignment, size_t size, uint64_t options)
    DARWIN_SYMBOL(malloc_zone_malloc_with_options);
void *darwin_malloc_zone_malloc_with_options(darwin_malloc_zone *zone, size_t alignment, size_t size, uint64_t options) {
    if (!zone) zone = &default_zone;
    void *block = alignment > sizeof(void *) ? zone->memalign(zone, alignment, size) : zone->malloc(zone, size);
    if (block && (options & 1)) memset(block, 0, size);
    return block;
}

/// The typed form, which a type identifier is passed to for typed memory
/// allocation; the identifier is not used here.
void *darwin_malloc_type_zone_malloc_with_options(darwin_malloc_zone *zone, size_t alignment, size_t size,
                                                   uint64_t type_id, uint64_t options)
    DARWIN_SYMBOL(malloc_type_zone_malloc_with_options);
void *darwin_malloc_type_zone_malloc_with_options(darwin_malloc_zone *zone, size_t alignment, size_t size,
                                                   uint64_t type_id, uint64_t options) {
    (void)type_id;
    return darwin_malloc_zone_malloc_with_options(zone, alignment, size, options);
}

// MARK: - Introspection

/// The usable size of a block, which may exceed what was asked for; 0 for
/// a pointer that is not a block's.
size_t darwin_malloc_size(const void *ptr) DARWIN_SYMBOL(malloc_size);
size_t darwin_malloc_size(const void *ptr) { return block_room(ptr); }

/// The room a request of `size` bytes gets.
size_t darwin_malloc_good_size(size_t size) DARWIN_SYMBOL(malloc_good_size);
size_t darwin_malloc_good_size(size_t size) { return block_size(size); }
