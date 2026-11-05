// Darwin's malloc zones and malloc introspection over glibc's heap. Every
// zone allocates from the one heap; a zone is a malloc_zone_t whose leading
// function pointers are where Darwin's are, so code that calls through them
// (zone->malloc(zone, size)) works too. Destroying a zone does not free what
// was allocated in it, which Darwin would.

#define _GNU_SOURCE
#include "PerrySystem.h"

#include <malloc.h>
#include <stdlib.h>
#include <string.h>

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

static size_t zone_size(darwin_malloc_zone *zone, const void *ptr) {
    (void)zone;
    return ptr ? malloc_usable_size((void *)ptr) : 0;
}

static void *zone_malloc(darwin_malloc_zone *zone, size_t size) { (void)zone; return malloc(size); }
static void *zone_calloc(darwin_malloc_zone *zone, size_t count, size_t size) { (void)zone; return calloc(count, size); }
static void *zone_valloc(darwin_malloc_zone *zone, size_t size) { (void)zone; return valloc(size); }
static void zone_free(darwin_malloc_zone *zone, void *ptr) { (void)zone; free(ptr); }
static void *zone_realloc(darwin_malloc_zone *zone, void *ptr, size_t size) { (void)zone; return realloc(ptr, size); }

static void zone_destroy(darwin_malloc_zone *zone) {
    free((void *)zone->zone_name);
    free(zone);
}

static unsigned zone_batch_malloc(darwin_malloc_zone *zone, size_t size, void **results, unsigned count) {
    (void)zone;
    unsigned made = 0;
    while (made < count && (results[made] = malloc(size))) made++;
    return made;
}

static void zone_batch_free(darwin_malloc_zone *zone, void **ptrs, unsigned count) {
    (void)zone;
    for (unsigned i = 0; i < count; i++) free(ptrs[i]);
}

static void *zone_memalign(darwin_malloc_zone *zone, size_t alignment, size_t size) {
    (void)zone;
    void *ptr = NULL;
    return posix_memalign(&ptr, alignment, size) == 0 ? ptr : NULL;
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

/// Every block is in the default zone, as far as anyone can tell.
darwin_malloc_zone *darwin_malloc_zone_from_ptr(const void *ptr) DARWIN_SYMBOL(malloc_zone_from_ptr);
darwin_malloc_zone *darwin_malloc_zone_from_ptr(const void *ptr) { return ptr ? &default_zone : NULL; }

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

/// The usable size of a block, which may exceed what was asked for.
size_t darwin_malloc_size(const void *ptr) DARWIN_SYMBOL(malloc_size);
size_t darwin_malloc_size(const void *ptr) { return ptr ? malloc_usable_size((void *)ptr) : 0; }

/// The size a request of `size` bytes gets: glibc's chunks are 16-byte
/// multiples, less their 8-byte header, and at least 24 bytes.
size_t darwin_malloc_good_size(size_t size) DARWIN_SYMBOL(malloc_good_size);
size_t darwin_malloc_good_size(size_t size) {
    if (size <= 24) return 24;
    return ((size + 8 + 15) & ~(size_t)15) - 8;
}
