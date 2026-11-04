// Mach-O thread-local variables, which dyld implements: each descriptor in an
// image's __thread_vars section is { thunk, key, offset }, and code reads a
// variable by calling thunk with the descriptor, which returns the address
// of this thread's copy. The thunk is perry_tlv_get_addr (tlv_thunk.S); each
// image has a pthread key whose value on a thread is that thread's copy of
// the image's thread-local storage, allocated on first use from the image's
// template: its __thread_data contents followed by zeros (__thread_bss).
#include "image.h"
#include "log.h"
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    void *(*thunk)(void *);
    unsigned long key;
    unsigned long offset;
} tlv_descriptor;

typedef struct {
    pthread_key_t key;
    const uint8_t *start;       // the template, in the mapped image
    size_t initial_size;        // bytes copied from it; the rest are zero
    size_t size;
} tlv_image;

static tlv_image *tlv_images;
static size_t tlv_image_count;
static pthread_rwlock_t tlv_lock = PTHREAD_RWLOCK_INITIALIZER;

void perry_tlv_get_addr(void);

// Called by perry_tlv_get_addr, which saves the registers C may change.
void *perry_tlv_address(tlv_descriptor *descriptor) {
    pthread_key_t key = (pthread_key_t)descriptor->key;
    uint8_t *storage = pthread_getspecific(key);
    if (!storage) {
        tlv_image image = {0};
        pthread_rwlock_rdlock(&tlv_lock);
        for (size_t i = 0; i < tlv_image_count; i++)
            if (tlv_images[i].key == key)
                image = tlv_images[i];
        pthread_rwlock_unlock(&tlv_lock);
        if (!image.size)
            perry_fatal("thread-local variable with unknown key %lu", descriptor->key);
        storage = calloc(1, image.size);
        if (!storage)
            perry_fatal("cannot allocate %zu bytes of thread-local storage", image.size);
        memcpy(storage, image.start, image.initial_size);
        pthread_setspecific(key, storage);
    }
    return storage + descriptor->offset;
}

void perry_setup_thread_locals(perry_image *image) {
    uint64_t start = UINT64_MAX, end = 0, initial_end = 0;
    for (uint32_t s = 0; s < image->segment_count; s++) {
        const perry_segment *seg = &image->segments[s];
        for (uint32_t j = 0; j < seg->nsects; j++) {
            const section_t *sect = &seg->sections[j];
            uint32_t type = sect->flags & SECTION_TYPE;
            if (type != S_THREAD_LOCAL_REGULAR && type != S_THREAD_LOCAL_ZEROFILL)
                continue;
            if (sect->addr < start)
                start = sect->addr;
            if (sect->addr + sect->size > end)
                end = sect->addr + sect->size;
            if (type == S_THREAD_LOCAL_REGULAR && sect->addr + sect->size > initial_end)
                initial_end = sect->addr + sect->size;
        }
    }

    pthread_key_t key = 0;
    bool keyed = false;
    for (uint32_t s = 0; s < image->segment_count; s++) {
        const perry_segment *seg = &image->segments[s];
        for (uint32_t j = 0; j < seg->nsects; j++) {
            const section_t *sect = &seg->sections[j];
            uint32_t type = sect->flags & SECTION_TYPE;
            if (type == S_THREAD_LOCAL_INIT_FUNCTION_POINTERS && sect->size)
                perry_warn("%s: thread-local initializers are not run", image->path);
            if (type != S_THREAD_LOCAL_VARIABLES || !sect->size)
                continue;
            if (end <= start)
                perry_fatal("%s: thread-local variables without thread-local data", image->path);
            if (!keyed) {
                if (pthread_key_create(&key, free) != 0)
                    perry_fatal("%s: no pthread key for thread-local variables", image->path);
                tlv_image entry = {
                    key, perry_image_vmaddr(image, start),
                    initial_end > start ? (size_t)(initial_end - start) : 0, (size_t)(end - start),
                };
                pthread_rwlock_wrlock(&tlv_lock);
                tlv_images = realloc(tlv_images, (tlv_image_count + 1) * sizeof(*tlv_images));
                tlv_images[tlv_image_count++] = entry;
                pthread_rwlock_unlock(&tlv_lock);
                keyed = true;
            }
            tlv_descriptor *descriptors = perry_image_vmaddr(image, sect->addr);
            for (size_t i = 0; i < sect->size / sizeof(tlv_descriptor); i++) {
                descriptors[i].thunk = (void *(*)(void *))perry_tlv_get_addr;
                descriptors[i].key = key;
            }
        }
    }
}
