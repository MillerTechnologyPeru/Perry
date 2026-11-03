#ifndef PERRY_IMAGE_H
#define PERRY_IMAGE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "macho.h"

struct perry_image;

// A Linux ELF library standing in for a Darwin library, e.g.
// libPerrySystem.so for /usr/lib/libSystem.B.dylib. Its exported symbol
// names are the Mach-O names (with the leading underscore).
typedef struct perry_provider {
    char *install_name;
    char *path;
    void *handle;
    void *base;     // load address, used to reject symbols found in the provider's own dependencies
    void *(*symbol)(const char *name);  // perry_provider_symbol, if the provider has one
    const char *reexports[2];   // install names of libraries whose symbols it re-exports, as libSystem does libdispatch's
} perry_provider;

typedef struct perry_dependency {
    const char *install_name;   // points into the image's load commands
    bool weak;
    bool reexport;
    struct perry_image *image;  // set when the dependency is a Mach-O image
    perry_provider *provider;   // set when a Linux provider stands in for it
} perry_dependency;

typedef struct perry_segment {
    char name[17];
    uint64_t vmaddr;            // unslid
    uint64_t vmsize;
    uint64_t fileoff;
    uint64_t filesize;
    int initprot;
    uint32_t flags;
    const struct section_64 *sections;
    uint32_t nsects;
    bool mapped;                // false for __PAGEZERO and empty segments
} perry_segment;

typedef struct perry_image {
    char *path;
    struct perry_image *next;   // global load-order list

    // Mapped image. `base` is the address of the mach header in memory.
    uint8_t *base;
    intptr_t slide;             // added to unslid vmaddrs
    uint64_t vm_start;          // lowest unslid vmaddr (ignoring __PAGEZERO)
    size_t vm_size;
    const struct mach_header_64 *header;

    perry_segment *segments;
    uint32_t segment_count;

    perry_dependency *deps;
    uint32_t dep_count;

    const char **rpaths;
    uint32_t rpath_count;

    const char *install_name;   // LC_ID_DYLIB, NULL for executables

    // Platform information.
    uint32_t platform;          // PLATFORM_*; 0 when unknown
    uint32_t minos;
    uint32_t sdk;
    bool encrypted;
    uint32_t cryptid;

    // Entry point (LC_MAIN), as an offset from the mach header.
    bool has_entry;
    uint64_t entryoff;

    // Linkedit data. Pointers are into the mapped __LINKEDIT segment.
    const struct linkedit_data_command *chained_fixups;
    const struct dyld_info_command *dyld_info;
    const uint8_t *exports_trie;
    uint32_t exports_trie_size;

    bool fixed_up;
    bool initialized;
    bool initializing;
} perry_image;

typedef struct perry_loader {
    perry_image *main_image;
    perry_image *images;        // load order
    perry_image **images_tail;

    perry_provider **providers;  // includes negative entries (handle == NULL)
    uint32_t provider_count;

    uint64_t next_image_address; // where the next slid image is placed

    char **library_dirs;        // where provider .so files are searched
    uint32_t library_dir_count;

    const char *bundle_path;    // .app bundle, when launched from one

    char *swift_runtime_dir;    // Darwin's Swift runtime libraries (/usr/lib/swift), from PERRY_SWIFT_RUNTIME

    bool report;                // collect unresolved symbols instead of failing
    bool strict;                // fail on unresolved non-weak imports
} perry_loader;

// Loading
void perry_loader_init(perry_loader *loader);
perry_image *perry_load_executable(perry_loader *loader, const char *path);
void perry_run_initializers(perry_loader *loader, perry_image *image, int argc, char **argv, char **envp, char **apple);
_Noreturn void perry_run_main(perry_loader *loader, perry_image *image, int argc, char **argv, char **envp, char **apple);

// Address helpers
void *perry_image_vmaddr(const perry_image *image, uint64_t unslid);
void *perry_image_fileoff(const perry_image *image, uint64_t fileoff);
const struct section_64 *perry_image_section(const perry_image *image, const char *segname, const char *sectname);
const char *perry_platform_name(uint32_t platform);

// Fixups (fixups.c)
void perry_apply_fixups(perry_loader *loader, perry_image *image);

// Symbol resolution (symbols.c)
typedef struct perry_symbol {
    void *address;
    bool found;
    bool weak_def;
} perry_symbol;

perry_symbol perry_resolve(perry_loader *loader, perry_image *image, int ordinal, const char *name, bool weak_import);
bool perry_exports_lookup(perry_loader *loader, perry_image *image, const char *name, perry_symbol *out, int depth);
perry_provider *perry_find_provider(perry_loader *loader, const char *install_name);
void *perry_provider_symbol(perry_loader *loader, const char *install_name, const char *name);
void *perry_unresolved_stub(const char *library, const char *name);

// Import records, for reports and diagnostics.
typedef enum {
    PERRY_IMPORT_RESOLVED,
    PERRY_IMPORT_WEAK_MISSING,
    PERRY_IMPORT_UNRESOLVED,
} perry_import_status;

typedef struct perry_import_record {
    const perry_image *image;
    const char *library;        // install name, or "<flat>" / "<main>" / "<weak>"
    const char *name;
    perry_import_status status;
} perry_import_record;

void perry_record_import(const perry_image *image, const char *library, const char *name, perry_import_status status);
void perry_record_bind_location(void *location, const char *name);
const char *perry_bind_name_at(const void *location);
const perry_import_record *perry_import_records(size_t *count);

// Report (report.c)
void perry_print_report(perry_loader *loader);

#endif
