// Rebasing and binding: chained fixups (LC_DYLD_CHAINED_FIXUPS), the older
// dyld info opcode streams (LC_DYLD_INFO_ONLY), and before those (iOS 2 and
// 3.0) the symbol table's indirect symbols and relocations.

#include "image.h"
#include "leb128.h"
#include "log.h"

#include <stdlib.h>
#include <string.h>

// MARK: - Binding

static uint64_t bind_target(perry_loader *loader, perry_image *image, int ordinal, const char *name,
                            bool weak_import) {
    perry_symbol sym = perry_resolve(loader, image, ordinal, name, weak_import);
    return (uint64_t)(uintptr_t)sym.address;
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

static void run_rebase_opcodes(perry_image *image, const uint8_t *p, const uint8_t *end) {
    unsigned seg = 0;
    uint64_t offset = 0;
    while (p < end) {
        uint8_t byte = *p++;
        uint8_t imm = byte & REBASE_IMMEDIATE_MASK;
        switch (byte & REBASE_OPCODE_MASK) {
        case REBASE_OPCODE_DONE:
            return;
        case REBASE_OPCODE_SET_TYPE_IMM:
            if (imm != REBASE_TYPE_POINTER)
                perry_fatal("%s: unsupported rebase type %u", image->path, imm);
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
                *(slot_t *)segment_address(image, seg, offset) += (slot_t)image->slide;
            break;
        case REBASE_OPCODE_DO_REBASE_ULEB_TIMES: {
            uint64_t count = perry_read_uleb(&p, end);
            for (uint64_t i = 0; i < count; i++, offset += sizeof(slot_t))
                *(slot_t *)segment_address(image, seg, offset) += (slot_t)image->slide;
            break;
        }
        case REBASE_OPCODE_DO_REBASE_ADD_ADDR_ULEB:
            *(slot_t *)segment_address(image, seg, offset) += (slot_t)image->slide;
            offset += sizeof(slot_t) + perry_read_uleb(&p, end);
            break;
        case REBASE_OPCODE_DO_REBASE_ULEB_TIMES_SKIPPING_ULEB: {
            uint64_t count = perry_read_uleb(&p, end);
            uint64_t skip = perry_read_uleb(&p, end);
            for (uint64_t i = 0; i < count; i++, offset += sizeof(slot_t) + skip)
                *(slot_t *)segment_address(image, seg, offset) += (slot_t)image->slide;
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
            write_bind(loader, (slot_t *)segment_address(image, seg, offset), cached + (uint64_t)addend, name); \
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

// Images linked before LC_DYLD_INFO, which are 32-bit. Symbol pointer
// sections (the non-lazy pointers and the stubs' lazy ones, bound now) have
// an entry each in the indirect symbol table, from the section's reserved1;
// other pointers to imports have external relocations, whose addend is in
// place. Local relocations only move an image that is slid.
#if !defined(__LP64__)
typedef struct classic_symbols {
    const struct nlist *symbols;
    uint32_t count;
    const char *strings;
    uint32_t strings_size;
} classic_symbols;

static uint32_t classic_symbol_value(perry_loader *loader, perry_image *image, const classic_symbols *table,
                                     uint32_t index, const char **name_out) {
    if (index >= table->count)
        perry_fatal("%s: symbol index %u out of range", image->path, index);
    const struct nlist *symbol = &table->symbols[index];
    const char *name = symbol->n_strx < table->strings_size ? table->strings + symbol->n_strx : "";
    *name_out = name;
    if ((symbol->n_type & N_TYPE) == N_UNDF) {
        int ordinal = GET_LIBRARY_ORDINAL((uint16_t)symbol->n_desc);
        // 0xfe and 0xff are the dynamic lookup and the executable.
        if (ordinal >= 0xfe)
            ordinal = (int)(int8_t)ordinal;
        return (uint32_t)bind_target(loader, image, ordinal, name, (symbol->n_desc & N_WEAK_REF) != 0);
    }
    uint32_t address = (uint32_t)(uintptr_t)perry_image_vmaddr(image, symbol->n_value & ~1u);
    return address | ((symbol->n_desc & N_ARM_THUMB_DEF) || (symbol->n_value & 1) ? 1 : 0);
}

static void apply_symbol_table(perry_loader *loader, perry_image *image) {
    const struct symtab_command *st = image->symtab;
    const struct dysymtab_command *dst = image->dysymtab;
    classic_symbols table = {
        perry_image_fileoff(image, st->symoff), st->nsyms, perry_image_fileoff(image, st->stroff), st->strsize,
    };
    if (!table.symbols || !table.strings)
        perry_fatal("%s: the symbol table is not in a mapped segment", image->path);

    const uint32_t *indirect = dst->nindirectsyms ? perry_image_fileoff(image, dst->indirectsymoff) : NULL;
    for (uint32_t s = 0; s < image->segment_count; s++) {
        const perry_segment *segment = &image->segments[s];
        for (uint32_t i = 0; segment->mapped && i < segment->nsects; i++) {
            const section_t *section = &segment->sections[i];
            uint32_t type = section->flags & SECTION_TYPE;
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
                uint32_t value = classic_symbol_value(loader, image, &table, index, &name);
                write_bind(loader, &slots[n], value, name);
            }
        }
    }

    // r_address is from the first segment, __PAGEZERO in an executable.
    uint8_t *relocation_base = perry_image_vmaddr(image, image->segment_count ? image->segments[0].vmaddr : 0);
    const struct relocation_info *external = dst->nextrel ? perry_image_fileoff(image, dst->extreloff) : NULL;
    for (uint32_t i = 0; external && i < dst->nextrel; i++) {
        const struct relocation_info *relocation = &external[i];
        if (((uint32_t)relocation->r_address & R_SCATTERED) || !relocation->r_extern || relocation->r_pcrel
            || relocation->r_length != 2 || relocation->r_type != GENERIC_RELOC_VANILLA)
            perry_fatal("%s: unsupported external relocation %u", image->path, i);
        slot_t *slot = (slot_t *)(relocation_base + relocation->r_address);
        const char *name;
        uint32_t value = classic_symbol_value(loader, image, &table, relocation->r_symbolnum, &name);
        // A missing weak import stays NULL, whatever the addend.
        write_bind(loader, slot, value ? value + *slot : 0, name);
    }

    const struct relocation_info *local = dst->nlocrel && image->slide ? perry_image_fileoff(image, dst->locreloff) : NULL;
    for (uint32_t i = 0; local && i < dst->nlocrel; i++) {
        const struct relocation_info *relocation = &local[i];
        // Scattered entries are parts of instructions' immediates, which are
        // not slid; the rest are pointers.
        if ((uint32_t)relocation->r_address & R_SCATTERED)
            continue;
        if (relocation->r_length != 2 || relocation->r_type != GENERIC_RELOC_VANILLA)
            perry_fatal("%s: unsupported local relocation %u", image->path, i);
        *(slot_t *)(relocation_base + relocation->r_address) += (slot_t)image->slide;
    }
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
#if !defined(__LP64__)
    else if (image->symtab && image->dysymtab)
        apply_symbol_table(loader, image);
#endif
    else if (image->slide != 0 && image->header->filetype != MH_EXECUTE)
        perry_warn("%s: no fixup information; image may not work when slid", image->path);
}
