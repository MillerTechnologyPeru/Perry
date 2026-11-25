// The Resource Manager: resource files read whole, their maps parsed, and
// resources given out as the Memory Manager's handles (CoreServices'). A
// file's resources are its resource fork's, which Linux keeps as an
// AppleDouble file beside it ("._name") when they were copied with the file;
// FSOpenResourceFile reads them from the data fork, as .rsrc files keep
// them. Files are searched from the current one back to the first opened,
// as the Resource Manager's chain goes.

#include "PerryCarbon.h"

#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

enum { resFNotFound = -193, mapReadErr = -199, eofErr = -39, fnfErr = -43 };

typedef struct { uint8_t hidden[80]; } FSRef;

typedef struct resource_file {
    int16_t reference;
    uint8_t *data;
    size_t size;
    uint32_t dataOffset, mapOffset;
    struct resource_file *next;   // the one opened before
} resource_file;

static resource_file *chain;     // the last opened first
static int16_t current, next_reference = 2;
static OSErr last_error;

// The Memory Manager's handles, CoreServices'.
static Handle new_handle(size_t size) {
    static Handle (*function)(long);
    if (!function) function = (Handle (*)(long))carbon_function(CORESERVICES, "_NewHandle");
    return function ? function((long)size) : NULL;
}

static uint32_t big32(const uint8_t *bytes) {
    return (uint32_t)bytes[0] << 24 | (uint32_t)bytes[1] << 16 | (uint32_t)bytes[2] << 8 | bytes[3];
}

static uint16_t big16(const uint8_t *bytes) { return (uint16_t)(bytes[0] << 8 | bytes[1]); }

static bool read_file(const char *path, uint8_t **data, size_t *size) {
    int descriptor = open(path, O_RDONLY);
    if (descriptor < 0) return false;
    struct stat info;
    if (fstat(descriptor, &info) != 0 || info.st_size <= 0) {
        close(descriptor);
        return false;
    }
    *size = (size_t)info.st_size;
    *data = malloc(*size);
    bool done = *data && read(descriptor, *data, *size) == (ssize_t)*size;
    close(descriptor);
    if (!done) free(*data);
    return done;
}

/// A resource fork's bytes, from an AppleDouble file: its resource fork
/// entry (ID 2).
static bool apple_double(const uint8_t *data, size_t size, size_t *offset, size_t *length) {
    if (size < 26 || big32(data) != 0x00051607) return false;
    uint16_t entries = big16(data + 24);
    for (uint16_t index = 0; index < entries && 26 + (size_t)(index + 1) * 12 <= size; index++) {
        const uint8_t *entry = data + 26 + index * 12;
        if (big32(entry) != 2) continue;
        *offset = big32(entry + 4);
        *length = big32(entry + 8);
        return *offset + *length <= size;
    }
    return false;
}

static int16_t open_bytes(uint8_t *data, size_t size) {
    if (size < 16) {
        free(data);
        last_error = eofErr;
        return -1;
    }
    resource_file *file = calloc(1, sizeof *file);
    if (!file) {
        free(data);
        last_error = memFullErr;
        return -1;
    }
    file->data = data;
    file->size = size;
    file->dataOffset = big32(data);
    file->mapOffset = big32(data + 4);
    if ((size_t)file->mapOffset + 30 > size || file->dataOffset > size) {
        free(data);
        free(file);
        last_error = mapReadErr;
        return -1;
    }
    file->reference = next_reference++;
    file->next = chain;
    chain = file;
    current = file->reference;
    last_error = noErr;
    return file->reference;
}

/// A file's resources: its resource fork's (AppleDouble), else its data
/// fork's when `data_fork`.
static int16_t open_path(const char *path, bool data_fork) {
    uint8_t *data = NULL;
    size_t size = 0;
    if (data_fork) {
        if (!read_file(path, &data, &size)) {
            last_error = access(path, F_OK) == 0 ? eofErr : fnfErr;
            return -1;
        }
        return open_bytes(data, size);
    }
    char double_path[PATH_MAX];
    const char *slash = strrchr(path, '/');
    snprintf(double_path, sizeof double_path, "%.*s._%s", slash ? (int)(slash - path + 1) : 0, path, slash ? slash + 1 : path);
    size_t offset = 0, length = 0;
    if (read_file(double_path, &data, &size) && apple_double(data, size, &offset, &length)) {
        memmove(data, data + offset, length);
        return open_bytes(data, length);
    }
    free(data);
    // No resource fork: the file opens with none, as an empty fork is.
    last_error = access(path, F_OK) == 0 ? eofErr : fnfErr;
    return -1;
}

static bool path_of(const FSRef *ref, char *path, size_t size) {
    int32_t (*function)(const FSRef *, char *, uint32_t) = (int32_t (*)(const FSRef *, char *, uint32_t))carbon_function(
        CORESERVICES, "_FSRefMakePath");
    return function && function(ref, path, (uint32_t)size) == noErr;
}

int16_t carbon_FSOpenResFile(const FSRef *ref, int8_t permission) CARBON_SYMBOL(FSOpenResFile);
int16_t carbon_FSOpenResFile(const FSRef *ref, int8_t permission) {
    (void)permission;
    char path[PATH_MAX];
    if (!path_of(ref, path, sizeof path)) {
        last_error = paramErr;
        return -1;
    }
    return open_path(path, false);
}

OSErr carbon_FSOpenResourceFile(const FSRef *ref, size_t forkLength, const uint16_t *fork, int8_t permission, int16_t *reference)
    CARBON_SYMBOL(FSOpenResourceFile);
OSErr carbon_FSOpenResourceFile(const FSRef *ref, size_t forkLength, const uint16_t *fork, int8_t permission, int16_t *reference) {
    (void)fork; (void)permission;
    char path[PATH_MAX];
    if (!reference || !path_of(ref, path, sizeof path)) return paramErr;
    *reference = open_path(path, forkLength == 0);
    return *reference < 0 ? last_error : noErr;
}

int16_t carbon_FSpOpenResFile(const void *spec, int8_t permission) CARBON_SYMBOL(FSpOpenResFile);
int16_t carbon_FSpOpenResFile(const void *spec, int8_t permission) {
    FSRef ref;
    OSErr (*make)(const void *, FSRef *) = (OSErr (*)(const void *, FSRef *))carbon_function(
        "/System/Library/Frameworks/Carbon.framework/Versions/A/Carbon", "_FSpMakeFSRef");
    if (!make || make(spec, &ref) != noErr) {
        last_error = fnfErr;
        return -1;
    }
    return carbon_FSOpenResFile(&ref, permission);
}

static resource_file *file_for(int16_t reference) {
    for (resource_file *file = chain; file; file = file->next)
        if (file->reference == reference) return file;
    return NULL;
}

void carbon_CloseResFile(int16_t reference) CARBON_SYMBOL(CloseResFile);
void carbon_CloseResFile(int16_t reference) {
    for (resource_file **link = &chain; *link; link = &(*link)->next)
        if ((*link)->reference == reference) {
            resource_file *file = *link;
            *link = file->next;
            free(file->data);
            free(file);
            if (current == reference) current = chain ? chain->reference : 0;
            last_error = noErr;
            return;
        }
    last_error = -51;   // rfNumErr
}

int16_t carbon_CurResFile(void) CARBON_SYMBOL(CurResFile);
int16_t carbon_CurResFile(void) { return current; }

void carbon_UseResFile(int16_t reference) CARBON_SYMBOL(UseResFile);
void carbon_UseResFile(int16_t reference) {
    if (reference == 0 || file_for(reference)) {
        current = reference;
        last_error = noErr;
    } else {
        last_error = -51;
    }
}

OSErr carbon_ResError(void) CARBON_SYMBOL(ResError);
OSErr carbon_ResError(void) { return last_error; }

// MARK: - Resources

// What a handle the Resource Manager gave out is: its type, ID and file.
typedef struct handle_record {
    Handle handle;
    OSType type;
    int16_t identifier;
    int16_t file;
    struct handle_record *next;
} handle_record;

static handle_record *given;

/// The resource's bytes in a file, if the file has it.
static bool find_in(resource_file *file, OSType type, int16_t identifier, const unsigned char *name, const uint8_t **bytes,
                    uint32_t *length, int16_t *found) {
    const uint8_t *map = file->data + file->mapOffset;
    uint16_t typeList = big16(map + 24), nameList = big16(map + 26);
    if ((size_t)file->mapOffset + typeList + 2 > file->size) return false;
    const uint8_t *types = map + typeList;
    int typeCount = big16(types) + 1;
    for (int index = 0; index < typeCount; index++) {
        const uint8_t *entry = types + 2 + index * 8;
        if ((size_t)(entry + 8 - file->data) > file->size) return false;
        if (big32(entry) != type) continue;
        int count = big16(entry + 4) + 1;
        const uint8_t *references = types + big16(entry + 6);
        for (int at = 0; at < count; at++) {
            const uint8_t *reference = references + at * 12;
            if ((size_t)(reference + 12 - file->data) > file->size) return false;
            int16_t id = (int16_t)big16(reference);
            if (name) {
                uint16_t nameOffset = big16(reference + 2);
                if (nameOffset == 0xffff) continue;
                const uint8_t *resourceName = map + nameList + nameOffset;
                if ((size_t)(resourceName - file->data) + resourceName[0] + 1 > file->size) continue;
                if (resourceName[0] != name[0] || memcmp(resourceName + 1, name + 1, name[0]) != 0) continue;
            } else if (id != identifier) {
                continue;
            }
            uint32_t offset = big32(reference + 4) & 0xffffff;
            const uint8_t *data = file->data + file->dataOffset + offset;
            if ((size_t)(data - file->data) + 4 > file->size) return false;
            *length = big32(data);
            if ((size_t)(data - file->data) + 4 + *length > file->size) return false;
            *bytes = data + 4;
            *found = id;
            return true;
        }
    }
    return false;
}

static Handle get(OSType type, int16_t identifier, const unsigned char *name, bool oneFile) {
    resource_file *file = file_for(current);
    for (; file; file = oneFile ? NULL : file->next) {
        // An existing handle for the resource is given again.
        const uint8_t *bytes;
        uint32_t length;
        int16_t id;
        if (!find_in(file, type, identifier, name, &bytes, &length, &id)) continue;
        for (handle_record *record = given; record; record = record->next)
            if (record->type == type && record->identifier == id && record->file == file->reference) {
                last_error = noErr;
                return record->handle;
            }
        Handle handle = new_handle(length);
        if (!handle) {
            last_error = memFullErr;
            return NULL;
        }
        memcpy(*handle, bytes, length);
        handle_record *record = calloc(1, sizeof *record);
        if (record) {
            *record = (handle_record){handle, type, id, file->reference, given};
            given = record;
        }
        last_error = noErr;
        return handle;
    }
    last_error = resNotFound;
    CARBON_TRACE("resource %c%c%c%c %d isn't there", (char)(type >> 24), (char)(type >> 16), (char)(type >> 8), (char)type, identifier);
    return NULL;
}

Handle carbon_GetResource(OSType type, int16_t identifier) CARBON_SYMBOL(GetResource);
Handle carbon_GetResource(OSType type, int16_t identifier) { return get(type, identifier, NULL, false); }

Handle carbon_Get1Resource(OSType type, int16_t identifier) CARBON_SYMBOL(Get1Resource);
Handle carbon_Get1Resource(OSType type, int16_t identifier) { return get(type, identifier, NULL, true); }

Handle carbon_GetNamedResource(OSType type, const unsigned char *name) CARBON_SYMBOL(GetNamedResource);
Handle carbon_GetNamedResource(OSType type, const unsigned char *name) { return name ? get(type, 0, name, false) : NULL; }

Handle carbon_Get1NamedResource(OSType type, const unsigned char *name) CARBON_SYMBOL(Get1NamedResource);
Handle carbon_Get1NamedResource(OSType type, const unsigned char *name) { return name ? get(type, 0, name, true) : NULL; }

/// Resources are read when they're got: loading them again changes nothing.
void carbon_LoadResource(Handle handle) CARBON_SYMBOL(LoadResource);
void carbon_LoadResource(Handle handle) { last_error = handle ? noErr : nilHandleErr; }

void carbon_ReleaseResource(Handle handle) CARBON_SYMBOL(ReleaseResource);
void carbon_ReleaseResource(Handle handle) {
    void (*dispose)(Handle) = (void (*)(Handle))carbon_function(CORESERVICES, "_DisposeHandle");
    for (handle_record **link = &given; *link; link = &(*link)->next)
        if ((*link)->handle == handle) {
            handle_record *record = *link;
            *link = record->next;
            free(record);
            if (dispose) dispose(handle);
            last_error = noErr;
            return;
        }
    last_error = -192;   // resNotFound: not a resource's handle
}

void carbon_DetachResource(Handle handle) CARBON_SYMBOL(DetachResource);
void carbon_DetachResource(Handle handle) {
    for (handle_record **link = &given; *link; link = &(*link)->next)
        if ((*link)->handle == handle) {
            handle_record *record = *link;
            *link = record->next;
            free(record);
            return;
        }
}

int16_t carbon_HomeResFile(Handle handle) CARBON_SYMBOL(HomeResFile);
int16_t carbon_HomeResFile(Handle handle) {
    for (handle_record *record = given; record; record = record->next)
        if (record->handle == handle) return record->file;
    last_error = -192;
    return -1;
}

void carbon_GetResInfo(Handle handle, int16_t *identifier, OSType *type, unsigned char *name) CARBON_SYMBOL(GetResInfo);
void carbon_GetResInfo(Handle handle, int16_t *identifier, OSType *type, unsigned char *name) {
    for (handle_record *record = given; record; record = record->next)
        if (record->handle == handle) {
            if (identifier) *identifier = record->identifier;
            if (type) *type = record->type;
            if (name) name[0] = 0;
            return;
        }
    last_error = -192;
}

int16_t carbon_Count1Resources(OSType type) CARBON_SYMBOL(Count1Resources);
int16_t carbon_Count1Resources(OSType type) {
    resource_file *file = file_for(current);
    if (!file) return 0;
    const uint8_t *map = file->data + file->mapOffset;
    const uint8_t *types = map + big16(map + 24);
    int typeCount = big16(types) + 1;
    for (int index = 0; index < typeCount; index++) {
        const uint8_t *entry = types + 2 + index * 8;
        if ((size_t)(entry + 8 - file->data) > file->size) break;
        if (big32(entry) == type) return (int16_t)(big16(entry + 4) + 1);
    }
    return 0;
}

int16_t carbon_CountResources(OSType type) CARBON_SYMBOL(CountResources);
int16_t carbon_CountResources(OSType type) {
    int16_t saved = current, total = 0;
    for (resource_file *file = file_for(current); file; file = file->next) {
        current = file->reference;
        total += carbon_Count1Resources(type);
    }
    current = saved;
    return total;
}

/// The international resources ('itl0' to 'itl4') aren't the system's
/// here: programs use their own defaults when there are none.
Handle carbon_GetIntlResource(int16_t identifier) CARBON_SYMBOL(GetIntlResource);
Handle carbon_GetIntlResource(int16_t identifier) {
    (void)identifier;
    last_error = resNotFound;
    return NULL;
}

void carbon_SetResLoad(Boolean load) CARBON_SYMBOL(SetResLoad);
void carbon_SetResLoad(Boolean load) { (void)load; }
