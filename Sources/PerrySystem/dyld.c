// dyld's image list: the Mach-O images the loader has mapped, recorded as
// each initializes, which is how the loader tells providers about them.
// Callbacks registered for added images hear of those already loaded at
// once, then of each new one.

#define _GNU_SOURCE
#include "PerrySystem.h"
#include "perry_interface.h"

#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef void (*image_callback)(const void *header, intptr_t slide);

static struct { const void *header; intptr_t slide; char *path; } *images;
static uint32_t image_count;
static image_callback *added, *removed;
static uint32_t added_count, removed_count;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;

__attribute__((visibility("default")))
void perry_provider_image_init(const perry_image_info *image) {
    pthread_mutex_lock(&lock);
    images = realloc(images, sizeof(*images) * (image_count + 1));
    images[image_count].header = image->header;
    images[image_count].slide = image->slide;
    images[image_count].path = strdup(image->path ? image->path : "");
    image_count++;
    uint32_t count = added_count;
    image_callback *callbacks = malloc(sizeof(*callbacks) * (count ? count : 1));
    memcpy(callbacks, added, sizeof(*callbacks) * count);
    pthread_mutex_unlock(&lock);
    for (uint32_t i = 0; i < count; i++)
        callbacks[i](image->header, image->slide);
    free(callbacks);
}

uint32_t darwin_dyld_image_count(void) DARWIN_SYMBOL(_dyld_image_count);
uint32_t darwin_dyld_image_count(void) { return image_count; }

const void *darwin_dyld_get_image_header(uint32_t index) DARWIN_SYMBOL(_dyld_get_image_header);
const void *darwin_dyld_get_image_header(uint32_t index) { return index < image_count ? images[index].header : NULL; }

intptr_t darwin_dyld_get_image_vmaddr_slide(uint32_t index) DARWIN_SYMBOL(_dyld_get_image_vmaddr_slide);
intptr_t darwin_dyld_get_image_vmaddr_slide(uint32_t index) { return index < image_count ? images[index].slide : 0; }

const char *darwin_dyld_get_image_name(uint32_t index) DARWIN_SYMBOL(_dyld_get_image_name);
const char *darwin_dyld_get_image_name(uint32_t index) { return index < image_count ? images[index].path : NULL; }

void darwin_dyld_register_func_for_add_image(image_callback callback) DARWIN_SYMBOL(_dyld_register_func_for_add_image);
void darwin_dyld_register_func_for_add_image(image_callback callback) {
    pthread_mutex_lock(&lock);
    added = realloc(added, sizeof(*added) * (added_count + 1));
    added[added_count++] = callback;
    uint32_t count = image_count;
    const void **headers = malloc(sizeof(*headers) * (count ? count : 1));
    intptr_t *slides = malloc(sizeof(*slides) * (count ? count : 1));
    for (uint32_t i = 0; i < count; i++) {
        headers[i] = images[i].header;
        slides[i] = images[i].slide;
    }
    pthread_mutex_unlock(&lock);
    for (uint32_t i = 0; i < count; i++)
        callback(headers[i], slides[i]);
    free(headers);
    free(slides);
}

// Images are never unloaded, so these callbacks are never called.
void darwin_dyld_register_func_for_remove_image(image_callback callback) DARWIN_SYMBOL(_dyld_register_func_for_remove_image);
void darwin_dyld_register_func_for_remove_image(image_callback callback) {
    pthread_mutex_lock(&lock);
    removed = realloc(removed, sizeof(*removed) * (removed_count + 1));
    removed[removed_count++] = callback;
    pthread_mutex_unlock(&lock);
}

// The executable's header: the image whose file type is MH_EXECUTE.
const void *darwin_NSGetMachExecuteHeader(void) DARWIN_SYMBOL(_NSGetMachExecuteHeader);
const void *darwin_NSGetMachExecuteHeader(void) {
    for (uint32_t i = 0; i < image_count; i++) {
        const uint32_t *header = images[i].header;
        if (header && header[3] == 2) return header;
    }
    return image_count ? images[0].header : NULL;
}
