// dyld's image list: the Mach-O images the loader has mapped, recorded as
// each initializes, which is how the loader tells providers about them.
// Callbacks registered for added images hear of those already loaded at
// once, then of each new one. Also what dyld finds in images for the Swift
// runtime: sections, the image holding an address, and the SDK the program
// was built with.

#define _GNU_SOURCE
#include "PerrySystem.h"
#include "MachO.h"
#include "perry_interface.h"

#include <dlfcn.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
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

// MARK: - Sections

// How far an image moved from where it was linked: its header's address
// less its __TEXT segment's.
static intptr_t image_slide(const void *header) {
    const uint8_t *command = perry_macho_commands(header);
    for (uint32_t i = 0; i < perry_macho_command_count(header); i++, command = perry_macho_next(command)) {
        perry_macho_segment segment;
        if (perry_macho_segment_at(command, &segment) && strncmp(segment.name, "__TEXT", 16) == 0)
            return (intptr_t)header - (intptr_t)segment.vmaddr;
    }
    return 0;
}

// A section's contents in a mapped image, and their size.
uint8_t *darwin_getsectiondata(const void *header, const char *segment, const char *section, unsigned long *size)
    DARWIN_SYMBOL(getsectiondata);
uint8_t *darwin_getsectiondata(const void *header, const char *segment, const char *section, unsigned long *size) {
    *size = 0;
    if (!header)
        return NULL;
    const uint8_t *command = perry_macho_commands(header);
    for (uint32_t i = 0; i < perry_macho_command_count(header); i++, command = perry_macho_next(command)) {
        perry_macho_segment found;
        if (!perry_macho_segment_at(command, &found) || strncmp(found.name, segment, 16) != 0)
            continue;
        for (uint32_t j = 0; j < found.section_count; j++) {
            uint64_t addr, length;
            const uint8_t *entry = perry_macho_section(&found, j, &addr, &length);
            if (strncmp((const char *)entry, section, 16) == 0) {
                *size = (unsigned long)length;
                return (uint8_t *)(uintptr_t)(addr + (uint64_t)image_slide(header));
            }
        }
    }
    return NULL;
}

// The Swift runtime's sections, which dyld finds for it by kind.
struct section_info { const void *buffer; size_t size; };

struct section_info darwin_dyld_lookup_section_info(const void *header, void *location, int kind)
    DARWIN_SYMBOL(_dyld_lookup_section_info);
struct section_info darwin_dyld_lookup_section_info(const void *header, void *location, int kind) {
    (void)location;
    static const char *const names[] = {
        "__swift5_protos", "__swift5_proto", "__swift5_types", "__swift5_replace", "__swift5_replac2",
        "__swift5_acfuncs",
    };
    struct section_info info = { NULL, 0 };
    if (kind >= 0 && (size_t)kind < sizeof(names) / sizeof(names[0])) {
        unsigned long size;
        info.buffer = darwin_getsectiondata(header, "__TEXT", names[kind], &size);
        info.size = size;
    }
    return info;
}

// MARK: - Addresses

// The loaded image whose segments hold `address`, or -1.
static int image_containing(const void *address) {
    uintptr_t target = (uintptr_t)address;
    for (uint32_t i = 0; i < image_count; i++) {
        const void *header = images[i].header;
        const uint8_t *command = perry_macho_commands(header);
        for (uint32_t c = 0; c < perry_macho_command_count(header); c++, command = perry_macho_next(command)) {
            perry_macho_segment segment;
            if (perry_macho_segment_at(command, &segment) && segment.filesize) {
                uintptr_t start = (uintptr_t)(segment.vmaddr + (uint64_t)images[i].slide);
                if (target >= start && target - start < segment.vmsize)
                    return (int)i;
            }
        }
    }
    return -1;
}

const char *darwin_dyld_image_path_containing_address(const void *address) DARWIN_SYMBOL(dyld_image_path_containing_address);
const char *darwin_dyld_image_path_containing_address(const void *address) {
    pthread_mutex_lock(&lock);
    int index = image_containing(address);
    const char *path = index < 0 ? NULL : images[index].path;
    pthread_mutex_unlock(&lock);
    return path;
}

const void *darwin_dyld_image_header_containing_address(const void *address) DARWIN_SYMBOL(dyld_image_header_containing_address);
const void *darwin_dyld_image_header_containing_address(const void *address) {
    pthread_mutex_lock(&lock);
    int index = image_containing(address);
    const void *header = index < 0 ? NULL : images[index].header;
    pthread_mutex_unlock(&lock);
    return header;
}

// Dl_info has the same layout on both. Mach-O images are named by path,
// without their symbols; anything else is glibc's to describe.
int darwin_dladdr(const void *address, Dl_info *info) DARWIN_SYMBOL(dladdr);
int darwin_dladdr(const void *address, Dl_info *info) {
    pthread_mutex_lock(&lock);
    int index = image_containing(address);
    if (index >= 0) {
        info->dli_fname = images[index].path;
        info->dli_fbase = (void *)images[index].header;
        info->dli_sname = NULL;
        info->dli_saddr = NULL;
    }
    pthread_mutex_unlock(&lock);
    return index >= 0 ? 1 : dladdr(address, info);
}

// MARK: - Versions

// The executable's SDK, as dyld_get_program_sdk_version gives it: from
// LC_BUILD_VERSION, or the older LC_VERSION_MIN_IPHONEOS.
static uint32_t program_sdk(void) {
    const uint32_t *mach = darwin_NSGetMachExecuteHeader();
    if (!mach)
        return 0;
    const uint8_t *command = (const uint8_t *)mach + 32;
    for (uint32_t i = 0; i < mach[4]; i++) {
        const uint32_t *words = (const uint32_t *)command;
        if (words[0] == 0x32 /* LC_BUILD_VERSION */)
            return words[4];
        if (words[0] == 0x25 /* LC_VERSION_MIN_IPHONEOS */)
            return words[3];
        command += words[1];
    }
    return 0;
}

/// The system's version, as libSystem gives it to the Swift runtime for
/// availability checks: the SDK the program was built with (as
/// NSProcessInfo's is), or iOS 18 without one.
typedef struct { unsigned major, minor, patch; } darwin_os_system_version;

int darwin_os_system_version_get_current_version(darwin_os_system_version *version)
    DARWIN_SYMBOL(os_system_version_get_current_version);
int darwin_os_system_version_get_current_version(darwin_os_system_version *version) {
    if (!version) return 22;
    uint32_t sdk = program_sdk();
    if (!sdk) sdk = 18u << 16;
    *version = (darwin_os_system_version){ sdk >> 16, (sdk >> 8) & 0xff, sdk & 0xff };
    return 0;
}

// Whether the program was built with an SDK at least `version`: a
// platform's own version, or a yearly set of them (platform 0xffffffff,
// version year << 16 | month << 8 | day), whose iOS version is the year
// less 2006.
typedef struct { uint32_t platform; uint32_t version; } build_version;

// The executable's minimum OS version, from the same load commands.
static uint32_t program_minos(void) {
    const uint32_t *mach = darwin_NSGetMachExecuteHeader();
    if (!mach)
        return 0;
    const uint8_t *command = (const uint8_t *)mach + 32;
    for (uint32_t i = 0; i < mach[4]; i++) {
        const uint32_t *words = (const uint32_t *)command;
        if (words[0] == 0x32 /* LC_BUILD_VERSION */)
            return words[3];
        if (words[0] == 0x25 /* LC_VERSION_MIN_IPHONEOS */)
            return words[2];
        command += words[1];
    }
    return 0;
}

bool darwin_dyld_program_sdk_at_least(build_version version) DARWIN_SYMBOL(dyld_program_sdk_at_least);
bool darwin_dyld_program_sdk_at_least(build_version version) {
    uint32_t wanted = version.version;
    if (version.platform == 0xffffffff)
        wanted = ((version.version >> 16) - 2006) << 16;
    return program_sdk() >= wanted;
}

bool darwin_dyld_program_minos_at_least(build_version version) DARWIN_SYMBOL(dyld_program_minos_at_least);
bool darwin_dyld_program_minos_at_least(build_version version) {
    uint32_t wanted = version.version;
    if (version.platform == 0xffffffff)
        wanted = ((version.version >> 16) - 2006) << 16;
    return program_minos() >= wanted;
}

// The OS is as new as anything a program checks for with @available,
// unless PERRY_OS_VERSION names the iOS version to be ("13.7"): for a
// program whose code for newer systems needs what isn't here, when it
// also runs on older ones.
bool darwin_availability_version_check(uint32_t count, const build_version *versions) DARWIN_SYMBOL(_availability_version_check);
bool darwin_availability_version_check(uint32_t count, const build_version *versions) {
    static uint32_t limit;
    static bool read;
    if (!read) {
        const char *setting = getenv("PERRY_OS_VERSION");
        unsigned major = 0, minor = 0, patch = 0;
        if (setting && sscanf(setting, "%u.%u.%u", &major, &minor, &patch) >= 1)
            limit = major << 16 | (minor & 0xff) << 8 | (patch & 0xff);
        read = true;
    }
    if (!limit)
        return true;
    for (uint32_t i = 0; i < count; i++)
        if (versions[i].version > limit)
            return false;
    return true;
}

// MARK: - Shared cache

// There is no shared cache, and nothing is prebuilt in it: no Objective-C
// or Swift optimizations, no prespecialized Swift metadata.
const void *darwin_dyld_get_shared_cache_range(size_t *length) DARWIN_SYMBOL(_dyld_get_shared_cache_range);
const void *darwin_dyld_get_shared_cache_range(size_t *length) {
    *length = 0;
    return NULL;
}

bool darwin_dyld_shared_cache_some_image_overridden(void) DARWIN_SYMBOL(dyld_shared_cache_some_image_overridden);
bool darwin_dyld_shared_cache_some_image_overridden(void) { return false; }

bool darwin_dyld_is_preoptimized_objc_image_loaded(const void *header) DARWIN_SYMBOL(_dyld_is_preoptimized_objc_image_loaded);
bool darwin_dyld_is_preoptimized_objc_image_loaded(const void *header) {
    (void)header;
    return false;
}

const void *darwin_dyld_get_swift_prespecialized_data(void) DARWIN_SYMBOL(_dyld_get_swift_prespecialized_data);
const void *darwin_dyld_get_swift_prespecialized_data(void) { return NULL; }

const void *darwin_dyld_find_pointer_hash_table_entry(const void *table, const void *key, size_t count, const void **keys)
    DARWIN_SYMBOL(_dyld_find_pointer_hash_table_entry);
const void *darwin_dyld_find_pointer_hash_table_entry(const void *table, const void *key, size_t count, const void **keys) {
    (void)table, (void)key, (void)count, (void)keys;
    return NULL;
}

// A handle's image, for libraries opened as Mach-O: none are, as dlopen
// finds symbols through the loader.
const void *darwin_dyld_get_dlopen_image_header(void *handle) DARWIN_SYMBOL(_dyld_get_dlopen_image_header);
const void *darwin_dyld_get_dlopen_image_header(void *handle) {
    (void)handle;
    return NULL;
}
