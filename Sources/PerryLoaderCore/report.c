// `perry --report`: a line-oriented description of what an app needs, used
// as the API to-do list. Every line starts with a keyword so output can be
// filtered with grep and diffed between Perry versions.

#define _GNU_SOURCE
#include "image.h"
#include "log.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct string_list {
    char **items;
    size_t count, capacity;
} string_list;

static void list_add(string_list *list, const char *fmt, ...) __attribute__((format(printf, 2, 3)));

static void list_add(string_list *list, const char *fmt, ...) {
    if (list->count == list->capacity) {
        list->capacity = list->capacity ? list->capacity * 2 : 64;
        list->items = realloc(list->items, sizeof(char *) * list->capacity);
    }
    va_list args;
    va_start(args, fmt);
    if (vasprintf(&list->items[list->count], fmt, args) >= 0)
        list->count++;
    va_end(args);
}

static int compare_strings(const void *a, const void *b) {
    return strcmp(*(char *const *)a, *(char *const *)b);
}

// Prints sorted, de-duplicated lines and frees the list.
static void list_flush(string_list *list) {
    qsort(list->items, list->count, sizeof(char *), compare_strings);
    for (size_t i = 0; i < list->count; i++) {
        if (i == 0 || strcmp(list->items[i], list->items[i - 1]) != 0)
            puts(list->items[i]);
    }
    for (size_t i = 0; i < list->count; i++)
        free(list->items[i]);
    free(list->items);
    memset(list, 0, sizeof(*list));
}

static void format_version(uint32_t v, char *out, size_t size) {
    if (v & 0xff)
        snprintf(out, size, "%u.%u.%u", v >> 16, (v >> 8) & 0xff, v & 0xff);
    else
        snprintf(out, size, "%u.%u", v >> 16, (v >> 8) & 0xff);
}

static bool in_image(const perry_image *image, const void *p) {
    const uint8_t *start = perry_image_vmaddr(image, image->vm_start);
    return (const uint8_t *)p >= start && (const uint8_t *)p < start + image->vm_size;
}

// MARK: - Objective-C metadata

// Offsets in Apple's 64-bit runtime structures.
enum {
    CLASS_DATA_OFFSET = 32,         // objc_class.bits
    CLASS_RO_NAME_OFFSET = 24,      // class_ro_t.name
    CATEGORY_NAME_OFFSET = 0,       // category_t.name
    CATEGORY_CLASS_OFFSET = 8,      // category_t.cls
};
#define CLASS_DATA_MASK 0x00007ffffffffff8ull

static const char *class_name(const perry_image *image, const uint8_t *cls) {
    if (!cls || !in_image(image, cls))
        return NULL;
    uint64_t bits = *(const uint64_t *)(cls + CLASS_DATA_OFFSET);
    const uint8_t *ro = (const uint8_t *)(uintptr_t)(bits & CLASS_DATA_MASK);
    if (!in_image(image, ro))
        return NULL;
    const char *name = *(const char *const *)(ro + CLASS_RO_NAME_OFFSET);
    return in_image(image, name) ? name : NULL;
}

static const void *const *section_pointers(const perry_image *image, const char *sectname, size_t *count) {
    // Objective-C sections live in __DATA, __DATA_CONST or __DATA_DIRTY.
    const struct section_64 *sect = perry_image_section(image, NULL, sectname);
    if (!sect) {
        *count = 0;
        return NULL;
    }
    *count = sect->size / sizeof(void *);
    return perry_image_vmaddr(image, sect->addr);
}

static const char *strip_prefix(const char *s, const char *prefix) {
    size_t len = strlen(prefix);
    return strncmp(s, prefix, len) == 0 ? s + len : NULL;
}

static void report_objc(const perry_image *image, string_list *out) {
    size_t count;
    const void *const *ptrs;

    ptrs = section_pointers(image, "__objc_classlist", &count);
    for (size_t i = 0; i < count; i++) {
        const char *name = class_name(image, ptrs[i]);
        list_add(out, "objc-class-defined\t%s", name ? name : "?");
    }

    ptrs = section_pointers(image, "__objc_catlist", &count);
    for (size_t i = 0; i < count; i++) {
        const uint8_t *cat = ptrs[i];
        if (!in_image(image, cat))
            continue;
        const char *cat_name = *(const char *const *)(cat + CATEGORY_NAME_OFFSET);
        const void *const *cls_slot = (const void *const *)(cat + CATEGORY_CLASS_OFFSET);
        const char *cls = class_name(image, *cls_slot);
        const char *bound = perry_bind_name_at(cls_slot);
        if (!cls && bound)
            cls = strip_prefix(bound, "_OBJC_CLASS_$_");
        list_add(out, "objc-category\t%s(%s)", cls ? cls : "?", in_image(image, cat_name) ? cat_name : "?");
    }

    ptrs = section_pointers(image, "__objc_selrefs", &count);
    for (size_t i = 0; i < count; i++)
        if (in_image(image, ptrs[i]))
            list_add(out, "objc-selector\t%s", (const char *)ptrs[i]);
}

// MARK: - Report

static const char *status_name(perry_import_status status) {
    switch (status) {
    case PERRY_IMPORT_RESOLVED: return "resolved";
    case PERRY_IMPORT_WEAK_MISSING: return "weak-missing";
    case PERRY_IMPORT_UNRESOLVED: return "unresolved";
    }
    return "?";
}

void perry_print_report(perry_loader *loader) {
    size_t record_count;
    const perry_import_record *records = perry_import_records(&record_count);
    string_list lines = { 0 };

    for (perry_image *image = loader->images; image; image = image->next) {
        char minos[32], sdk[32];
        format_version(image->minos, minos, sizeof(minos));
        format_version(image->sdk, sdk, sizeof(sdk));
        printf("image\t%s\n", image->path);
        printf("platform\t%s\t%s\tsdk %s\n", perry_platform_name(image->platform), minos, sdk);
        printf("encrypted\t%s\n", image->encrypted ? "yes" : "no");
        printf("fixups\t%s\n", image->chained_fixups ? "chained" : image->dyld_info ? "dyld-info" : "none");
        for (uint32_t i = 0; i < image->dep_count; i++) {
            const perry_dependency *dep = &image->deps[i];
            const char *how = dep->provider ? dep->provider->path : dep->image ? dep->image->path
                            : dep->weak ? "missing (weak)" : "missing";
            printf("dependency\t%s\t%s\n", dep->install_name, how);
        }

        size_t resolved = 0, unresolved = 0, weak = 0;
        for (size_t i = 0; i < record_count; i++) {
            const perry_import_record *r = &records[i];
            if (r->image != image)
                continue;
            switch (r->status) {
            case PERRY_IMPORT_RESOLVED: resolved++; break;
            case PERRY_IMPORT_UNRESOLVED: unresolved++; break;
            case PERRY_IMPORT_WEAK_MISSING: weak++; break;
            }
            if (r->status != PERRY_IMPORT_RESOLVED)
                list_add(&lines, "%s\t%s\t%s", status_name(r->status), r->library, r->name);
            const char *cls = strip_prefix(r->name, "_OBJC_CLASS_$_");
            if (cls)
                list_add(&lines, "objc-class-referenced\t%s\t%s", cls, status_name(r->status));
        }
        printf("imports\t%zu resolved\t%zu unresolved\t%zu weak-missing\n", resolved, unresolved, weak);
        list_flush(&lines);
        report_objc(image, &lines);
        list_flush(&lines);
    }
}
