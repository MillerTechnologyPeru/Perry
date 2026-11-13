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
    bool started;               // its startup function has been called
} perry_provider;

typedef struct perry_dependency {
    const char *install_name;   // points into the image's load commands
    bool weak;
    bool reexport;
    struct perry_image *image;  // set when the dependency is a Mach-O image
    perry_provider *provider;   // set when a Linux provider stands in for it
    struct perry_image *swift_overlay; // a framework's Swift code, for a Swift image
    struct perry_image *swift_additions; // Swift API of the framework's that Perry adds, after the overlay's
} perry_dependency;

typedef struct perry_segment {
    char name[17];
    uint64_t vmaddr;            // unslid
    uint64_t vmsize;
    uint64_t fileoff;
    uint64_t filesize;
    int initprot;
    uint32_t flags;
    const section_t *sections;
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
    const mach_header_t *header;

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
    bool unixthread;            // started by LC_UNIXTHREAD rather than LC_MAIN
    const struct symtab_command *symtab;
    const struct dysymtab_command *dysymtab;
    void *legacy_main;          // _main, for LC_UNIXTHREAD executables, which have no LC_MAIN
    uint32_t thread_pc;         // LC_UNIXTHREAD's unslid pc: crt1's `start`

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
// Starts providers loaded after the program started (by a symbol lookup
// that needed a new one), as those at startup were; none before startup.
void perry_start_late_providers(perry_loader *loader);
// With PERRY_CRASH_REPORT set, prints registers and frames on a fatal signal.
void perry_install_crash_reporter(perry_loader *loader);
// With PERRY_PROFILE set to a path, samples the main thread's stacks there.
void perry_install_profiler(perry_loader *loader);
_Noreturn void perry_run_main(perry_loader *loader, perry_image *image, int argc, char **argv, char **envp, char **apple);

// The architectures a Mach-O file holds, as PERRY_ARCH_* bits: a thin file's
// one, or each slice of a universal file. Zero when the file is not Mach-O.
#define PERRY_ARCH_ARM64    1u
#define PERRY_ARCH_ARMV7    2u
#define PERRY_ARCH_X86_64   4u
#define PERRY_ARCH_I386     8u
unsigned perry_macho_architectures(const char *path);

// Address helpers
void *perry_image_vmaddr(const perry_image *image, uint64_t unslid);

// Points the image's thread-local variable descriptors at Perry's tlv_get_addr.
void perry_setup_thread_locals(perry_image *image);
void *perry_image_fileoff(const perry_image *image, uint64_t fileoff);
const section_t *perry_image_section(const perry_image *image, const char *segname, const char *sectname);
const char *perry_platform_name(uint32_t platform);

// Fixups (fixups.c)
void perry_apply_fixups(perry_loader *loader, perry_image *image);

// Describes the image's frames to the host's unwinder, from its
// __unwind_info, so that exceptions pass through its code and are caught
// in it. After its fixups, which bind its personality routines.
void perry_register_unwind_info(perry_image *image);

// Symbol resolution (symbols.c)
typedef struct perry_symbol {
    void *address;
    bool found;
    bool weak_def;
} perry_symbol;

perry_symbol perry_resolve(perry_loader *loader, perry_image *image, int ordinal, const char *name, bool weak_import);
/// Fills in the witness tables made for apps from libraries' resilient
/// conformances, once every image is bound.
void perry_make_witness_tables(perry_loader *loader);
bool perry_exports_lookup(perry_loader *loader, perry_image *image, const char *name, perry_symbol *out, int depth);
#if defined(__arm__)
/// The entry an armv7 image calls an imported function through, which aligns
/// the stack; `function` itself for the few that must be called directly.
void *perry_aligned_entry(void *function, const char *name);
#endif
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
