// Rebasing and binding: chained fixups (LC_DYLD_CHAINED_FIXUPS), the older
// dyld info opcode streams (LC_DYLD_INFO_ONLY), and before those (iOS 2 and
// 3.0) the symbol table's indirect symbols and relocations.

#include "image.h"
#include "leb128.h"
#include "log.h"

#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>

#ifndef MAP_FIXED_NOREPLACE
#define MAP_FIXED_NOREPLACE 0x100000
#endif

// MARK: - Binding

static uint64_t bind_target(perry_loader *loader, perry_image *image, int ordinal, const char *name,
                            bool weak_import) {
    // An app extension, loaded into its host's process, ends its work with
    // exit, which must not end the host's.
    if (image->header->filetype == MH_EXECUTE && image != loader->main_image && strcmp(name, "_exit") == 0)
        return (uint64_t)(uintptr_t)perry_extension_exit;
    perry_symbol sym = perry_resolve(loader, image, ordinal, name, weak_import);
#if defined(__powerpc__)
    // Darwin code reaches a Linux function through a stub that sets r2.
    return (uint64_t)(uintptr_t)perry_ppc_linux_entry(sym.address);
#else
    return (uint64_t)(uintptr_t)sym.address;
#endif
}

// A pointer-sized slot in the image, which Darwin's ARM ABIs size as the
// loader's own pointers: 8 bytes for arm64, 4 for armv7.
typedef uintptr_t slot_t;

static void write_bind(perry_loader *loader, slot_t *loc, uint64_t value, const char *name) {
    *loc = (slot_t)value;
    if (loader->report)
        perry_record_bind_location(loc, name);
    perry_trace(PERRY_TRACE_BIND, "bind %p = 0x%llx %s", (void *)loc, (unsigned long long)value, name);
}

// What a lazy pointer, which only calls go through, is bound to: on armv7
// the function's aligned entry.
static uint64_t called_function(uint64_t function, const char *name) {
#if defined(__arm__)
    return (uint64_t)(uintptr_t)perry_aligned_entry((void *)(uintptr_t)function, name);
#else
    (void)name;
    return function;
#endif
}

// MARK: - Chained fixups

// Chained fixups are 64-bit: DYLD_CHAINED_PTR_64 and its offset form. Images
// for iOS 2 through 10 carry dyld info opcodes instead, which every pointer
// width uses.
#if defined(__LP64__)
typedef struct chained_import {
    uint64_t target;    // resolved address including the import's addend
    const char *name;
} chained_import;

static void walk_chain(perry_loader *loader, perry_image *image, uint16_t format, uint8_t *loc,
                       const chained_import *imports, uint32_t import_count) {
    for (;;) {
        uint64_t raw = *(uint64_t *)loc;
        uint64_t next = CHAINED_PTR64_NEXT(raw);
        if (CHAINED_PTR64_BIND(raw)) {
            uint32_t ordinal = (uint32_t)CHAINED_PTR64_ORDINAL(raw);
            if (ordinal >= import_count)
                perry_fatal("%s: chained bind ordinal %u out of range", image->path, ordinal);
            write_bind(loader, (slot_t *)loc, imports[ordinal].target + CHAINED_PTR64_ADDEND(raw),
                       imports[ordinal].name);
        } else {
            uint64_t target = CHAINED_PTR64_TARGET(raw);
            uint64_t value = format == DYLD_CHAINED_PTR_64_OFFSET
                ? (uint64_t)(uintptr_t)image->base + target
                : target + (uint64_t)image->slide;
            *(uint64_t *)loc = value | (CHAINED_PTR64_HIGH8(raw) << 56);
        }
        if (next == 0)
            break;
        loc += next * 4;
    }
}

static int import_ordinal(uint32_t raw, unsigned bits) {
    // Special ordinals are encoded as small negative numbers in the field width.
    uint32_t max = (1u << bits) - 1;
    if (raw > max - 0x10)
        return (int)raw - (int)max - 1;
    return (int)raw;
}

static void apply_chained_fixups(perry_loader *loader, perry_image *image) {
    const uint8_t *data = perry_image_fileoff(image, image->chained_fixups->dataoff);
    if (!data)
        perry_fatal("%s: chained fixups outside __LINKEDIT", image->path);
    const struct dyld_chained_fixups_header *header = (const void *)data;
    if (header->fixups_version != 0)
        perry_fatal("%s: unsupported chained fixups version %u", image->path, header->fixups_version);
    if (header->symbols_format != 0)
        perry_fatal("%s: compressed chained fixup symbols are not supported", image->path);

    // Resolve every import once.
    const char *symbols = (const char *)data + header->symbols_offset;
    const uint8_t *import_data = data + header->imports_offset;
    chained_import *imports = calloc(header->imports_count ? header->imports_count : 1, sizeof(*imports));
    for (uint32_t i = 0; i < header->imports_count; i++) {
        int ordinal;
        bool weak;
        uint32_t name_offset;
        int64_t addend = 0;
        switch (header->imports_format) {
        case DYLD_CHAINED_IMPORT: {
            uint32_t v = ((const uint32_t *)import_data)[i];
            ordinal = import_ordinal(v & 0xff, 8);
            weak = (v >> 8) & 1;
            name_offset = v >> 9;
            break;
        }
        case DYLD_CHAINED_IMPORT_ADDEND: {
            const uint32_t *v = (const uint32_t *)import_data + i * 2;
            ordinal = import_ordinal(v[0] & 0xff, 8);
            weak = (v[0] >> 8) & 1;
            name_offset = v[0] >> 9;
            addend = (int32_t)v[1];
            break;
        }
        case DYLD_CHAINED_IMPORT_ADDEND64: {
            const uint64_t *v = (const uint64_t *)import_data + i * 2;
            ordinal = import_ordinal(v[0] & 0xffff, 16);
            weak = (v[0] >> 16) & 1;
            name_offset = (uint32_t)(v[0] >> 32);
            addend = (int64_t)v[1];
            break;
        }
        default:
            perry_fatal("%s: unknown chained import format %u", image->path, header->imports_format);
        }
        imports[i].name = symbols + name_offset;
        imports[i].target = bind_target(loader, image, ordinal, imports[i].name, weak) + (uint64_t)addend;
    }

    // Walk the chains of every page of every segment.
    const uint8_t *starts_base = data + header->starts_offset;
    const struct dyld_chained_starts_in_image *starts = (const void *)starts_base;
    for (uint32_t s = 0; s < starts->seg_count; s++) {
        if (starts->seg_info_offset[s] == 0)
            continue;
        const struct dyld_chained_starts_in_segment *seg = (const void *)(starts_base + starts->seg_info_offset[s]);
        uint16_t format = seg->pointer_format;
        if (format != DYLD_CHAINED_PTR_64 && format != DYLD_CHAINED_PTR_64_OFFSET)
            perry_fatal("%s: unsupported chained pointer format %u (arm64e?)", image->path, format);
        uint8_t *seg_base = image->base + seg->segment_offset;
        for (uint16_t page = 0; page < seg->page_count; page++) {
            uint16_t start = seg->page_start[page];
            if (start == DYLD_CHAINED_PTR_START_NONE)
                continue;
            uint8_t *page_base = seg_base + (uint64_t)page * seg->page_size;
            if (start & DYLD_CHAINED_PTR_START_MULTI) {
                // Index into an overflow list of chain starts for this page.
                for (uint32_t idx = start & ~DYLD_CHAINED_PTR_START_MULTI;; idx++) {
                    uint16_t s2 = seg->page_start[idx];
                    walk_chain(loader, image, format, page_base + (s2 & ~DYLD_CHAINED_PTR_START_LAST),
                               imports, header->imports_count);
                    if (s2 & DYLD_CHAINED_PTR_START_LAST)
                        break;
                }
            } else {
                walk_chain(loader, image, format, page_base + start, imports, header->imports_count);
            }
        }
    }
    free(imports);
}
#else
static void apply_chained_fixups(perry_loader *loader, perry_image *image) {
    (void)loader;
    perry_fatal("%s: chained fixups are not supported in a 32-bit image", image->path);
}
#endif

// MARK: - Dyld info opcodes

static uint8_t *segment_address(perry_image *image, unsigned index, uint64_t offset) {
    if (index >= image->segment_count || !image->segments[index].mapped)
        perry_fatal("%s: fixup references bad segment %u", image->path, index);
    const perry_segment *seg = &image->segments[index];
    if (offset >= seg->vmsize)
        perry_fatal("%s: fixup offset 0x%llx past end of %s", image->path, (unsigned long long)offset, seg->name);
    return perry_image_vmaddr(image, seg->vmaddr + offset);
}

// Text relocations, which i386 code can have, are patched like pointers; a
// relative one moves the other way, its target staying put as the image slides.
static void rebase_at(perry_image *image, unsigned seg, uint64_t offset, uint8_t type) {
    slot_t *slot = (slot_t *)segment_address(image, seg, offset);
    if (type == REBASE_TYPE_TEXT_PCREL32)
        *slot -= (slot_t)image->slide;
    else
        *slot += (slot_t)image->slide;
}

static void run_rebase_opcodes(perry_image *image, const uint8_t *p, const uint8_t *end) {
    unsigned seg = 0;
    uint64_t offset = 0;
    uint8_t type = REBASE_TYPE_POINTER;
    while (p < end) {
        uint8_t byte = *p++;
        uint8_t imm = byte & REBASE_IMMEDIATE_MASK;
        switch (byte & REBASE_OPCODE_MASK) {
        case REBASE_OPCODE_DONE:
            return;
        case REBASE_OPCODE_SET_TYPE_IMM:
            if (imm != REBASE_TYPE_POINTER && (sizeof(slot_t) != 4 || imm > REBASE_TYPE_TEXT_PCREL32))
                perry_fatal("%s: unsupported rebase type %u", image->path, imm);
            type = imm;
            break;
        case REBASE_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB:
            seg = imm;
            offset = perry_read_uleb(&p, end);
            break;
        case REBASE_OPCODE_ADD_ADDR_ULEB:
            offset += perry_read_uleb(&p, end);
            break;
        case REBASE_OPCODE_ADD_ADDR_IMM_SCALED:
            offset += (uint64_t)imm * sizeof(slot_t);
            break;
        case REBASE_OPCODE_DO_REBASE_IMM_TIMES:
            for (unsigned i = 0; i < imm; i++, offset += sizeof(slot_t))
                rebase_at(image, seg, offset, type);
            break;
        case REBASE_OPCODE_DO_REBASE_ULEB_TIMES: {
            uint64_t count = perry_read_uleb(&p, end);
            for (uint64_t i = 0; i < count; i++, offset += sizeof(slot_t))
                rebase_at(image, seg, offset, type);
            break;
        }
        case REBASE_OPCODE_DO_REBASE_ADD_ADDR_ULEB:
            rebase_at(image, seg, offset, type);
            offset += sizeof(slot_t) + perry_read_uleb(&p, end);
            break;
        case REBASE_OPCODE_DO_REBASE_ULEB_TIMES_SKIPPING_ULEB: {
            uint64_t count = perry_read_uleb(&p, end);
            uint64_t skip = perry_read_uleb(&p, end);
            for (uint64_t i = 0; i < count; i++, offset += sizeof(slot_t) + skip)
                rebase_at(image, seg, offset, type);
            break;
        }
        default:
            perry_fatal("%s: bad rebase opcode 0x%02x", image->path, byte);
        }
    }
}

typedef enum { BIND_REGULAR, BIND_LAZY, BIND_WEAK } bind_kind;

static void run_bind_opcodes(perry_loader *loader, perry_image *image, const uint8_t *p, const uint8_t *end,
                             bind_kind kind) {
    unsigned seg = 0;
    uint64_t offset = 0;
    int ordinal = kind == BIND_WEAK ? BIND_SPECIAL_DYLIB_WEAK_LOOKUP : 0;
    const char *name = NULL;
    bool weak_import = false;
    int64_t addend = 0;
    uint64_t cached = 0;
    bool cache_valid = false;

#define DO_BIND() do { \
        if (!cache_valid) { \
            /* Weak coalescing only rebinds when another definition exists. */ \
            cached = bind_target(loader, image, ordinal, name, weak_import || kind == BIND_WEAK); \
            cache_valid = true; \
        } \
        if (kind != BIND_WEAK || cached) \
            write_bind(loader, (slot_t *)segment_address(image, seg, offset), \
                       (kind == BIND_LAZY ? called_function(cached, name) : cached) + (uint64_t)addend, name); \
    } while (0)

    while (p < end) {
        uint8_t byte = *p++;
        uint8_t imm = byte & BIND_IMMEDIATE_MASK;
        switch (byte & BIND_OPCODE_MASK) {
        case BIND_OPCODE_DONE:
            // Lazy binding info is a sequence of entries, each ending in DONE.
            if (kind != BIND_LAZY)
                return;
            break;
        case BIND_OPCODE_SET_DYLIB_ORDINAL_IMM:
            ordinal = imm;
            cache_valid = false;
            break;
        case BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB:
            ordinal = (int)perry_read_uleb(&p, end);
            cache_valid = false;
            break;
        case BIND_OPCODE_SET_DYLIB_SPECIAL_IMM:
            ordinal = imm ? (int)(int8_t)(BIND_OPCODE_MASK | imm) : 0;
            cache_valid = false;
            break;
        case BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM:
            name = (const char *)p;
            p += strnlen(name, (size_t)(end - p)) + 1;
            weak_import = imm & BIND_SYMBOL_FLAGS_WEAK_IMPORT;
            cache_valid = false;
            break;
        case BIND_OPCODE_SET_TYPE_IMM:
            if (imm != BIND_TYPE_POINTER)
                perry_fatal("%s: unsupported bind type %u", image->path, imm);
            break;
        case BIND_OPCODE_SET_ADDEND_SLEB:
            addend = perry_read_sleb(&p, end);
            break;
        case BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB:
            seg = imm;
            offset = perry_read_uleb(&p, end);
            break;
        case BIND_OPCODE_ADD_ADDR_ULEB:
            offset += perry_read_uleb(&p, end);
            break;
        case BIND_OPCODE_DO_BIND:
            DO_BIND();
            offset += sizeof(slot_t);
            break;
        case BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB:
            DO_BIND();
            offset += sizeof(slot_t) + perry_read_uleb(&p, end);
            break;
        case BIND_OPCODE_DO_BIND_ADD_ADDR_IMM_SCALED:
            DO_BIND();
            offset += sizeof(slot_t) + (uint64_t)imm * sizeof(slot_t);
            break;
        case BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB: {
            uint64_t count = perry_read_uleb(&p, end);
            uint64_t skip = perry_read_uleb(&p, end);
            for (uint64_t i = 0; i < count; i++) {
                DO_BIND();
                offset += sizeof(slot_t) + skip;
            }
            break;
        }
        case BIND_OPCODE_THREADED:
            perry_fatal("%s: threaded binds (arm64e) are not supported", image->path);
        default:
            perry_fatal("%s: bad bind opcode 0x%02x", image->path, byte);
        }
    }
#undef DO_BIND
}

static void apply_dyld_info(perry_loader *loader, perry_image *image) {
    const struct dyld_info_command *di = image->dyld_info;
#define STREAM(off, size) (const uint8_t *)perry_image_fileoff(image, off), \
                          (const uint8_t *)perry_image_fileoff(image, off) + (size)
    if (di->rebase_size)
        run_rebase_opcodes(image, STREAM(di->rebase_off, di->rebase_size));
    if (di->bind_size)
        run_bind_opcodes(loader, image, STREAM(di->bind_off, di->bind_size), BIND_REGULAR);
    // Lazy pointers are bound eagerly; dyld_stub_binder is never called.
    if (di->lazy_bind_size)
        run_bind_opcodes(loader, image, STREAM(di->lazy_bind_off, di->lazy_bind_size), BIND_LAZY);
    if (di->weak_bind_size)
        run_bind_opcodes(loader, image, STREAM(di->weak_bind_off, di->weak_bind_size), BIND_WEAK);
#undef STREAM
}

// MARK: - Symbol table binding

// Images linked before LC_DYLD_INFO: the 32-bit ones, and x86_64's built for
// Mac OS X 10.5. Symbol pointer sections (the non-lazy pointers and the
// stubs' lazy ones, bound now) have an entry each in the indirect symbol
// table, from the section's reserved1; other pointers to imports have
// external relocations, whose addend is in place. Local relocations only
// move an image that is slid.
#if !defined(__LP64__) || defined(__x86_64__)
typedef struct classic_symbols {
    const nlist_t *symbols;
    uint32_t count;
    const char *strings;
    uint32_t strings_size;
} classic_symbols;

#if defined(__i386__) || defined(__powerpc__)
// What `__dyld_func_lookup` gives crt1 of programs from before Mac OS X 10.5:
// libSystem's function of that name where it has one (crt1 of Tiger's
// GCC walks the images with _dyld_image_count and _dyld_get_image_name,
// looking for libobjc's __objcInit), whose Darwin name is its name there;
// and for the startup functions it calls with no arguments, which have
// nothing left to do, one that returns 0.
static void *dyld_nothing(void) { return NULL; }

static perry_loader *dyld_loader;

static int dyld_func_lookup(const char *name, void **address) {
    void *function = name && dyld_loader ? perry_provider_symbol(dyld_loader, "/usr/lib/libSystem.B.dylib", name) : NULL;
    if (!function)
        function = (void *)dyld_nothing;
#if defined(__powerpc__)
    *address = perry_ppc_thread_stub(function);
#else
    *address = function;
#endif
    return 1;
}

// __DATA,__dyld holds what crt1 calls dyld through, which dyld fills in: the
// lazy binder, unused since imports are bound at load, and the function
// lookup.
static void fill_dyld_section(perry_loader *loader, perry_image *image) {
    dyld_loader = loader;
    for (uint32_t s = 0; s < image->segment_count; s++) {
        const perry_segment *segment = &image->segments[s];
        for (uint32_t i = 0; segment->mapped && i < segment->nsects; i++) {
            const section_t *section = &segment->sections[i];
            if (strncmp(section->sectname, "__dyld", 16) != 0 || section->size < 2 * sizeof(slot_t))
                continue;
            slot_t *slots = perry_image_vmaddr(image, section->addr);
#if defined(__powerpc__)
            slots[0] = (slot_t)(uintptr_t)perry_ppc_thread_stub((void *)dyld_nothing);
            slots[1] = (slot_t)(uintptr_t)perry_ppc_thread_stub((void *)dyld_func_lookup);
#else
            slots[0] = (slot_t)(uintptr_t)dyld_nothing;
            slots[1] = (slot_t)(uintptr_t)dyld_func_lookup;
#endif
        }
    }
}
#endif

static uintptr_t classic_symbol_value(perry_loader *loader, perry_image *image, const classic_symbols *table,
                                      uint32_t index, const char **name_out) {
    if (index >= table->count)
        perry_fatal("%s: symbol index %u out of range", image->path, index);
    const nlist_t *symbol = &table->symbols[index];
    const char *name = symbol->n_strx < table->strings_size ? table->strings + symbol->n_strx : "";
    *name_out = name;
    if ((symbol->n_type & N_TYPE) == N_UNDF) {
        int ordinal = GET_LIBRARY_ORDINAL((uint16_t)symbol->n_desc);
        // 0xfe and 0xff are the dynamic lookup and the executable.
        if (ordinal >= 0xfe)
            ordinal = (int)(int8_t)ordinal;
        // An image with a flat namespace, as before Mac OS X 10.1, names no
        // library for its symbols.
        if (!(image->header->flags & MH_TWOLEVEL))
            ordinal = -2;
        return (uintptr_t)bind_target(loader, image, ordinal, name, (symbol->n_desc & N_WEAK_REF) != 0);
    }
#if defined(__arm__)
    uint32_t address = (uint32_t)(uintptr_t)perry_image_vmaddr(image, symbol->n_value & ~1u);
    return address | ((symbol->n_desc & N_ARM_THUMB_DEF) || (symbol->n_value & 1) ? 1 : 0);
#else
    return (uintptr_t)perry_image_vmaddr(image, symbol->n_value);
#endif
}

// A whole pointer's relocation: its r_length is the pointer size's log2.
#if defined(__LP64__)
enum { POINTER_LENGTH = 3, POINTER_RELOCATION = X86_64_RELOC_UNSIGNED };
#else
enum { POINTER_LENGTH = 2, POINTER_RELOCATION = GENERIC_RELOC_VANILLA };
#endif

static void apply_symbol_table(perry_loader *loader, perry_image *image) {
    const struct symtab_command *st = image->symtab;
    const struct dysymtab_command *dst = image->dysymtab;
    classic_symbols table = {
        perry_image_fileoff(image, st->symoff), st->nsyms, perry_image_fileoff(image, st->stroff), st->strsize,
    };
    if (!table.symbols || !table.strings)
        perry_fatal("%s: the symbol table is not in a mapped segment", image->path);

    // r_address is from the first segment, __PAGEZERO in an executable; on
    // x86_64 from the first segment that can be written.
    uint64_t first = image->segment_count ? image->segments[0].vmaddr : 0;
#if defined(__x86_64__)
    for (uint32_t s = 0; s < image->segment_count; s++)
        if (image->segments[s].initprot & PROT_WRITE) {
            first = image->segments[s].vmaddr;
            break;
        }
#endif
    uint8_t *relocation_base = perry_image_vmaddr(image, first);

    // Local relocations first: the lazy pointers have them too, for the
    // stub helpers they start out pointing at.
    const struct relocation_info *local = dst->nlocrel && image->slide ? perry_image_fileoff(image, dst->locreloff) : NULL;
    for (uint32_t i = 0; local && i < dst->nlocrel; i++) {
        const struct relocation_info *relocation = &local[i];
#if defined(__i386__) || defined(__powerpc__)
        // On i386 and ppc scattered entries are also pointers to a local
        // symbol with an offset: r_address is their low 24 bits, then r_type
        // and r_length. ppc's others are parts of instructions' immediates,
        // which code built to be slid (PIC) has none of.
        if ((uint32_t)relocation->r_address & R_SCATTERED) {
            uint32_t bits = (uint32_t)relocation->r_address;
            if (((bits >> 24) & 0xf) == GENERIC_RELOC_VANILLA && ((bits >> 28) & 3) == 2 && !((bits >> 30) & 1))
                *(slot_t *)(relocation_base + (bits & 0xffffff)) += (slot_t)image->slide;
            continue;
        }
#else
        // Scattered entries are parts of instructions' immediates, which are
        // not slid; the rest are pointers.
        if ((uint32_t)relocation->r_address & R_SCATTERED)
            continue;
#endif
        if (relocation->r_length != POINTER_LENGTH || relocation->r_type != POINTER_RELOCATION)
            perry_fatal("%s: unsupported local relocation %u", image->path, i);
        *(slot_t *)(relocation_base + relocation->r_address) += (slot_t)image->slide;
    }

    const uint32_t *indirect = dst->nindirectsyms ? perry_image_fileoff(image, dst->indirectsymoff) : NULL;
    for (uint32_t s = 0; s < image->segment_count; s++) {
        const perry_segment *segment = &image->segments[s];
        for (uint32_t i = 0; segment->mapped && i < segment->nsects; i++) {
            const section_t *section = &segment->sections[i];
            uint32_t type = section->flags & SECTION_TYPE;
#if defined(__i386__)
            // __IMPORT,__jump_table, of images linked before Mac OS X 10.6:
            // stubs of five bytes (reserved2), each a jump dyld writes.
            if (type == S_SYMBOL_STUBS && (section->flags & S_ATTR_SELF_MODIFYING_CODE) && section->reserved2 == 5) {
                uint8_t *stubs = perry_image_vmaddr(image, section->addr);
                uint32_t stub_count = (uint32_t)(section->size / 5);
                if (!indirect || section->reserved1 + stub_count > dst->nindirectsyms)
                    perry_fatal("%s: %.16s has no indirect symbols", image->path, section->sectname);
                for (uint32_t n = 0; n < stub_count; n++) {
                    uint32_t index = indirect[section->reserved1 + n];
                    if (index & (INDIRECT_SYMBOL_ABS | INDIRECT_SYMBOL_LOCAL))
                        continue;
                    const char *name;
                    uint32_t value = classic_symbol_value(loader, image, &table, index, &name);
                    uint8_t *stub = stubs + n * 5;
                    stub[0] = 0xe9;     // jmp rel32
                    uint32_t displacement = value - (uint32_t)(uintptr_t)(stub + 5);
                    memcpy(stub + 1, &displacement, 4);
                    perry_trace(PERRY_TRACE_BIND, "jump %p = 0x%x %s", (void *)stub, value, name);
                }
                continue;
            }
#endif
            if (type != S_NON_LAZY_SYMBOL_POINTERS && type != S_LAZY_SYMBOL_POINTERS)
                continue;
            slot_t *slots = perry_image_vmaddr(image, section->addr);
            uint32_t count = (uint32_t)(section->size / sizeof(slot_t));
            if (!indirect || section->reserved1 + count > dst->nindirectsyms)
                perry_fatal("%s: %.16s has no indirect symbols", image->path, section->sectname);
            for (uint32_t n = 0; n < count; n++) {
                uint32_t index = indirect[section->reserved1 + n];
                if (index & INDIRECT_SYMBOL_ABS)
                    continue;
                if (index & INDIRECT_SYMBOL_LOCAL) {
                    // A pointer to the image's own symbol, there already.
                    if (type == S_NON_LAZY_SYMBOL_POINTERS)
                        slots[n] += (slot_t)image->slide;
                    continue;
                }
                const char *name;
                uintptr_t value = classic_symbol_value(loader, image, &table, index, &name);
                if (type == S_LAZY_SYMBOL_POINTERS)
                    value = (uintptr_t)called_function(value, name);
                write_bind(loader, &slots[n], value, name);
            }
        }
    }

    const struct relocation_info *external = dst->nextrel ? perry_image_fileoff(image, dst->extreloff) : NULL;
    for (uint32_t i = 0; external && i < dst->nextrel; i++) {
        const struct relocation_info *relocation = &external[i];
        if (((uint32_t)relocation->r_address & R_SCATTERED) || !relocation->r_extern || relocation->r_pcrel
            || relocation->r_length != POINTER_LENGTH || relocation->r_type != POINTER_RELOCATION)
            perry_fatal("%s: unsupported external relocation %u", image->path, i);
        slot_t *slot = (slot_t *)(relocation_base + relocation->r_address);
        const char *name;
        uintptr_t value = classic_symbol_value(loader, image, &table, relocation->r_symbolnum, &name);
        // A missing weak import stays NULL, whatever the addend.
        write_bind(loader, slot, value ? value + *slot : 0, name);
    }
}
#endif

#if defined(__powerpc__)
// MARK: - The commpage

// Apple's GCC sends Objective-C messages on ppc (Mac OS X 10.4 and later) with
// an absolute branch to the commpage's copy of objc_msgSend, `bla 0xfffeff00`,
// or `ba` for a tail call. On 32-bit Linux that address is the kernel's. So
// each such branch becomes a relative one to an island near the image, which
// jumps to libobjc's objc_msgSend. Branches reach 32 MB either way.
enum { COMMPAGE_MSGSEND = 0xfffeff00u, BRANCH_REACH = 32u << 20 };

static uint32_t *commpage_island(perry_loader *loader, perry_image *image) {
    perry_symbol send = perry_resolve(loader, image, BIND_SPECIAL_DYLIB_FLAT_LOOKUP, "_objc_msgSend", false);
    if (!send.address)
        perry_fatal("%s: sends messages through the commpage, and no library has objc_msgSend", image->path);
    uint32_t target = (uint32_t)(uintptr_t)perry_ppc_linux_entry(send.address);
    // Right after the image, or failing that anywhere in reach of it.
    uintptr_t end = (uintptr_t)perry_image_vmaddr(image, image->vm_start) + image->vm_size;
    uint32_t *island = MAP_FAILED;
    for (uintptr_t hint = end; island == MAP_FAILED && hint < end + BRANCH_REACH / 2; hint += 0x10000)
        island = mmap((void *)hint, 0x1000, PROT_READ | PROT_WRITE | PROT_EXEC,
                      MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE, -1, 0);
    if (island == MAP_FAILED)
        perry_fatal("%s: no room near the image for the commpage's objc_msgSend", image->path);
    island[0] = 0x3d800000u | (target >> 16);       // lis r12, objc_msgSend@h
    island[1] = 0x618c0000u | (target & 0xffff);    // ori r12, r12, objc_msgSend@l
    island[2] = 0x7d8903a6u;                        // mtctr r12
    island[3] = 0x4e800420u;                        // bctr
    __builtin___clear_cache((char *)island, (char *)(island + 4));
    mprotect(island, 0x1000, PROT_READ | PROT_EXEC);
    return island;
}

static void patch_commpage_branches(perry_loader *loader, perry_image *image) {
    const uint32_t absolute = 0x48000000u | (COMMPAGE_MSGSEND & 0x03fffffcu) | 2;    // ba
    uint32_t *island = NULL;
    unsigned patched = 0;
    for (uint32_t s = 0; s < image->segment_count; s++) {
        const perry_segment *segment = &image->segments[s];
        for (uint32_t i = 0; segment->mapped && i < segment->nsects; i++) {
            const section_t *section = &segment->sections[i];
            // S_ATTR_PURE_INSTRUCTIONS or S_ATTR_SOME_INSTRUCTIONS.
            if (!(section->flags & 0x80000400u))
                continue;
            uint32_t *words = perry_image_vmaddr(image, section->addr);
            for (uint32_t k = 0; k < section->size / 4; k++) {
                if ((words[k] & ~1u) != absolute)
                    continue;
                if (!island)
                    island = commpage_island(loader, image);
                intptr_t offset = (intptr_t)island - (intptr_t)&words[k];
                if (offset < -(intptr_t)BRANCH_REACH || offset >= (intptr_t)BRANCH_REACH)
                    perry_fatal("%s: the commpage's objc_msgSend is out of a branch's reach", image->path);
                words[k] = 0x48000000u | ((uint32_t)offset & 0x03fffffcu) | (words[k] & 1);   // b or bl
                patched++;
            }
        }
    }
    if (patched)
        perry_trace(PERRY_TRACE_BIND, "%s: %u commpage objc_msgSend branches to %p", image->path, patched, (void *)island);
}
#endif

void perry_apply_fixups(perry_loader *loader, perry_image *image) {
    if (image->fixed_up)
        return;
    image->fixed_up = true;
    if (image->chained_fixups)
        apply_chained_fixups(loader, image);
    else if (image->dyld_info)
        apply_dyld_info(loader, image);
#if !defined(__LP64__) || defined(__x86_64__)
    else if (image->symtab && image->dysymtab)
        apply_symbol_table(loader, image);
#endif
    else if (image->slide != 0 && image->header->filetype != MH_EXECUTE)
        perry_warn("%s: no fixup information; image may not work when slid", image->path);
#if defined(__i386__) || defined(__powerpc__)
    fill_dyld_section(loader, image);
#endif
#if defined(__powerpc__)
    patch_commpage_branches(loader, image);
#endif
}
