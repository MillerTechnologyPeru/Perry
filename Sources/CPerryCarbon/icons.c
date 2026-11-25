// Icon Services: an IconRef is an icon family's bytes, which are an .icns
// file's. A file's icon is its bundle's (CFBundleIconFile in its
// Contents/Info.plist, in Contents/Resources) or a .icns file's own; other
// files have none here, which callers hear as noSuchIconErr. An icon family
// handle (IconRefToIconFamily) is a copy of those bytes, as Growl sends an
// application's icon.

#include "PerryCarbon.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

enum { noSuchIconErr = -2581, invalidIconRefErr = -2580, fnfErr = -43 };

typedef struct carbon_icon {
    uint32_t magic;
    uint8_t *bytes;
    size_t size;
    int32_t count;
} carbon_icon, *IconRef;

#define CARBON_ICON_MAGIC 0x69636e73u   // 'icns'

static IconRef icon_from(void *pointer) {
    IconRef icon = pointer;
    return icon && icon->magic == CARBON_ICON_MAGIC ? icon : NULL;
}

static bool read_whole(const char *path, uint8_t **bytes, size_t *size) {
    FILE *file = fopen(path, "rb");
    if (!file) return false;
    bool done = false;
    if (fseek(file, 0, SEEK_END) == 0) {
        long length = ftell(file);
        if (length > 8 && fseek(file, 0, SEEK_SET) == 0 && (*bytes = malloc((size_t)length))) {
            done = fread(*bytes, 1, (size_t)length, file) == (size_t)length && memcmp(*bytes, "icns", 4) == 0;
            if (done) *size = (size_t)length;
            else free(*bytes);
        }
    }
    fclose(file);
    return done;
}

/// The .icns file a file's icon is in: itself, or its bundle's icon file.
static bool icon_path(const char *path, char *out, size_t size) {
    size_t length = strlen(path);
    if (length > 5 && strcmp(path + length - 5, ".icns") == 0) return snprintf(out, size, "%s", path) < (int)size;
    struct stat info;
    if (stat(path, &info) != 0 || !S_ISDIR(info.st_mode)) return false;
    id url = SEND1(CLASS("NSURL"), "fileURLWithPath:", carbon_string(path));
    id bundle = url ? SEND1(CLASS("NSBundle"), "bundleWithURL:", url) : NULL;
    id name = bundle ? SEND1(bundle, "objectForInfoDictionaryKey:", carbon_string("CFBundleIconFile")) : NULL;
    if (!name) return false;
    const char *file = ((const char *(*)(id, SEL))objc_send)(name, SELECTOR("UTF8String"));
    if (!file || !*file) return false;
    bool has_extension = strlen(file) > 5 && strcmp(file + strlen(file) - 5, ".icns") == 0;
    return snprintf(out, size, "%s/Contents/Resources/%s%s", path, file, has_extension ? "" : ".icns") < (int)size;
}

static IconRef icon_for_path(const char *path) {
    char file[1024];
    uint8_t *bytes = NULL;
    size_t size = 0;
    if (!icon_path(path, file, sizeof file) || !read_whole(file, &bytes, &size)) return NULL;
    IconRef icon = calloc(1, sizeof *icon);
    if (!icon) {
        free(bytes);
        return NULL;
    }
    *icon = (carbon_icon){CARBON_ICON_MAGIC, bytes, size, 1};
    return icon;
}

static bool path_of_ref(const void *ref, char *path, size_t size) {
    int32_t (*make_path)(const void *, char *, uint32_t) = (int32_t (*)(const void *, char *, uint32_t))carbon_function(
        CORESERVICES, "_FSRefMakePath");
    return ref && make_path && make_path(ref, path, (uint32_t)size) == noErr;
}

/// OSErr GetIconRefFromFileInfo(const FSRef *, UniCharCount, const UniChar *, FSCatalogInfoBitmap,
///                              const FSCatalogInfo *, IconServicesUsageFlags, IconRef *, SInt16 *label).
OSErr carbon_GetIconRefFromFileInfo(const void *ref, unsigned long nameLength, const uint16_t *name, uint32_t bitmap,
                                    const void *catalog, uint32_t usage, IconRef *icon, int16_t *label)
    CARBON_SYMBOL(GetIconRefFromFileInfo);
OSErr carbon_GetIconRefFromFileInfo(const void *ref, unsigned long nameLength, const uint16_t *name, uint32_t bitmap,
                                    const void *catalog, uint32_t usage, IconRef *icon, int16_t *label) {
    (void)nameLength; (void)name; (void)bitmap; (void)catalog; (void)usage;
    if (!icon) return paramErr;
    *icon = NULL;
    if (label) *label = 0;
    char path[1024];
    if (!path_of_ref(ref, path, sizeof path)) return fnfErr;
    *icon = icon_for_path(path);
    return *icon ? noErr : noSuchIconErr;
}

/// OSErr GetIconRefFromFile(const FSSpec *, IconRef *, SInt16 *label): the
/// file the FSSpec names, by way of its FSRef.
OSErr carbon_GetIconRefFromFile(const void *spec, IconRef *icon, int16_t *label) CARBON_SYMBOL(GetIconRefFromFile);
OSErr carbon_GetIconRefFromFile(const void *spec, IconRef *icon, int16_t *label) {
    if (!icon) return paramErr;
    *icon = NULL;
    if (label) *label = 0;
    uint8_t ref[80];
    OSErr (*make_ref)(const void *, void *) = (OSErr (*)(const void *, void *))carbon_function(CORESERVICES, "_FSpMakeFSRef");
    if (!spec || !make_ref || make_ref(spec, ref) != noErr) return fnfErr;
    return carbon_GetIconRefFromFileInfo(ref, 0, NULL, 0, NULL, 0, icon, label);
}

/// OSErr IconRefToIconFamily(IconRef, IconSelectorValue, IconFamilyHandle *): a
/// new handle of the icon family's bytes.
OSErr carbon_IconRefToIconFamily(IconRef icon, uint32_t selector, Handle *family) CARBON_SYMBOL(IconRefToIconFamily);
OSErr carbon_IconRefToIconFamily(IconRef icon, uint32_t selector, Handle *family) {
    (void)selector;
    if (!family) return paramErr;
    *family = NULL;
    if (!(icon = icon_from(icon))) return invalidIconRefErr;
    Handle (*new_handle)(long) = (Handle (*)(long))carbon_function(CORESERVICES, "_NewHandle");
    Handle made = new_handle ? new_handle((long)icon->size) : NULL;
    if (!made || !*made) return memFullErr;
    memcpy(*made, icon->bytes, icon->size);
    *family = made;
    return noErr;
}

OSErr carbon_AcquireIconRef(IconRef icon) CARBON_SYMBOL(AcquireIconRef);
OSErr carbon_AcquireIconRef(IconRef icon) {
    if (!(icon = icon_from(icon))) return invalidIconRefErr;
    icon->count++;
    return noErr;
}

OSErr carbon_ReleaseIconRef(IconRef icon) CARBON_SYMBOL(ReleaseIconRef);
OSErr carbon_ReleaseIconRef(IconRef icon) {
    if (!(icon = icon_from(icon))) return invalidIconRefErr;
    if (--icon->count > 0) return noErr;
    icon->magic = 0;
    free(icon->bytes);
    free(icon);
    return noErr;
}
