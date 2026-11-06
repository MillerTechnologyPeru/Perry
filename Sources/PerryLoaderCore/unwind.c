// Exceptions through Mach-O code.
//
// A C++ exception thrown in a program's code is unwound by the host's
// unwinder (libgcc's, which libc++abi and libstdc++ raise exceptions with),
// which finds each frame's description, a DWARF FDE, in an ELF object's
// .eh_frame or among those registered with __register_frame. A Mach-O
// image describes its frames in __TEXT,__unwind_info instead: a compact
// encoding per function, which says how the frame is laid out, or that the
// function's FDE in __TEXT,__eh_frame does.
//
// So for each image an .eh_frame is written here and registered: an FDE
// for every function, made from its compact encoding, or carrying over the
// instructions of its own FDE, with the personality routine and LSDA the
// unwind info names. Pointers are written absolute, as the image is where
// it will stay.

#define _GNU_SOURCE
#include "image.h"
#include "log.h"

// armv7's code has no unwind tables: it unwinds with setjmp and longjmp,
// through contexts it registers with libSystem as it runs.
#if !defined(__LP64__)
void perry_register_unwind_info(perry_image *image) { (void)image; }
#else

#include <dlfcn.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// MARK: - Writing

typedef struct {
    uint8_t *bytes;
    size_t size, capacity;
} buffer;

static void put(buffer *b, const void *data, size_t count) {
    if (b->size + count > b->capacity) {
        b->capacity = (b->size + count) * 2 + 4096;
        b->bytes = realloc(b->bytes, b->capacity);
        if (!b->bytes)
            perry_fatal("out of memory for unwind information");
    }
    memcpy(b->bytes + b->size, data, count);
    b->size += count;
}

static void put8(buffer *b, uint8_t value) { put(b, &value, 1); }
static void put32(buffer *b, uint32_t value) { put(b, &value, 4); }
static void put64(buffer *b, uint64_t value) { put(b, &value, 8); }

static void put_uleb(buffer *b, uint64_t value) {
    do {
        uint8_t byte = value & 0x7f;
        value >>= 7;
        put8(b, value ? byte | 0x80 : byte);
    } while (value);
}

static void put_sleb(buffer *b, int64_t value) {
    for (;;) {
        uint8_t byte = value & 0x7f;
        value >>= 7;
        bool done = (value == 0 && !(byte & 0x40)) || (value == -1 && (byte & 0x40));
        put8(b, done ? byte : byte | 0x80);
        if (done)
            return;
    }
}

/// Ends the entry begun at `start`: padded with DW_CFA_nop to 8 bytes, its
/// length filled in.
static void finish(buffer *b, size_t start) {
    while ((b->size - start) % 8)
        put8(b, 0);
    uint32_t length = (uint32_t)(b->size - start - 4);
    memcpy(b->bytes + start, &length, 4);
}

/// A CIE whose FDEs' pointers are absolute; with a personality routine,
/// each FDE carries an LSDA pointer. Its offset in the buffer.
static size_t write_cie(buffer *b, uint64_t code_align, int64_t data_align, uint8_t return_register, uintptr_t personality,
                        const uint8_t *initial, size_t initial_size) {
    size_t start = b->size;
    put32(b, 0);                // the length, filled in by finish
    put32(b, 0);                // a CIE
    put8(b, 1);                 // version
    if (personality)
        put(b, "zPLR", 5);
    else
        put(b, "zR", 3);
    put_uleb(b, code_align);
    put_sleb(b, data_align);
    put8(b, return_register);
    if (personality) {
        put_uleb(b, 11);
        put8(b, 0x00);          // P: DW_EH_PE_absptr
        put64(b, personality);
        put8(b, 0x00);          // L: DW_EH_PE_absptr
        put8(b, 0x00);          // R: DW_EH_PE_absptr
    } else {
        put_uleb(b, 1);
        put8(b, 0x00);          // R
    }
    put(b, initial, initial_size);
    finish(b, start);
    return start;
}

static void write_fde(buffer *b, size_t cie, bool has_personality, uintptr_t start_address, uintptr_t size, uintptr_t lsda,
                      const uint8_t *instructions, size_t instructions_size) {
    size_t start = b->size;
    put32(b, 0);
    put32(b, (uint32_t)(b->size - cie));    // back from this field to the CIE
    put64(b, start_address);
    put64(b, size);
    if (has_personality) {
        put_uleb(b, 8);
        put64(b, lsda);
    } else {
        put_uleb(b, 0);
    }
    put(b, instructions, instructions_size);
    finish(b, start);
}

// MARK: - Compact encodings (arm64)

enum {
    UNWIND_HAS_LSDA = 0x40000000,
    UNWIND_PERSONALITY_SHIFT = 28,
    UNWIND_ARM64_MODE_MASK = 0x0f000000,
    UNWIND_ARM64_MODE_FRAMELESS = 0x02000000,
    UNWIND_ARM64_MODE_DWARF = 0x03000000,
    UNWIND_ARM64_MODE_FRAME = 0x04000000,
};

/// A frame with x29 and x30 pushed and x29 pointing at them: the CFA is
/// x29 + 16, and the pairs of callee-saved registers the encoding lists
/// are below x29, in its order.
static size_t frame_instructions(uint32_t encoding, uint8_t *out) {
    static const struct { uint32_t bit; uint8_t first; } pairs[] = {
        { 0x001, 19 }, { 0x002, 21 }, { 0x004, 23 }, { 0x008, 25 }, { 0x010, 27 },     // x19 to x28
        { 0x100, 72 }, { 0x200, 74 }, { 0x400, 76 }, { 0x800, 78 },                     // d8 to d15 (v8 is 72)
    };
    size_t n = 0;
    out[n++] = 0x0c; out[n++] = 29; out[n++] = 16;      // DW_CFA_def_cfa x29, 16
    out[n++] = 0x80 | 29; out[n++] = 2;                  // DW_CFA_offset x29, cfa - 16
    out[n++] = 0x80 | 30; out[n++] = 1;                  // DW_CFA_offset x30, cfa - 8
    uint8_t slot = 3;
    for (size_t i = 0; i < sizeof(pairs) / sizeof(pairs[0]); i++) {
        if (!(encoding & pairs[i].bit))
            continue;
        for (uint8_t reg = pairs[i].first; reg < pairs[i].first + 2; reg++) {
            if (reg < 64) {
                out[n++] = 0x80 | reg;                   // DW_CFA_offset
            } else {
                out[n++] = 0x05;                         // DW_CFA_offset_extended
                out[n++] = reg;
            }
            out[n++] = slot++;
        }
    }
    return n;
}

// MARK: - DWARF entries

static uint64_t read_uleb(const uint8_t **p, const uint8_t *end) {
    uint64_t value = 0;
    for (unsigned shift = 0; *p < end; shift += 7) {
        uint8_t byte = *(*p)++;
        if (shift < 64)
            value |= (uint64_t)(byte & 0x7f) << shift;
        if (!(byte & 0x80))
            break;
    }
    return value;
}

static int64_t read_sleb(const uint8_t **p, const uint8_t *end) {
    int64_t value = 0;
    unsigned shift = 0;
    uint8_t byte = 0;
    while (*p < end) {
        byte = *(*p)++;
        if (shift < 64)
            value |= (int64_t)(byte & 0x7f) << shift;
        shift += 7;
        if (!(byte & 0x80))
            break;
    }
    if (shift < 64 && (byte & 0x40))
        value |= -((int64_t)1 << shift);
    return value;
}

/// The bytes a pointer of that encoding takes; 0 for one of no fixed size.
static size_t encoded_size(uint8_t encoding) {
    switch (encoding & 0x0f) {
    case 0x00: case 0x04: case 0x0c: return 8;
    case 0x03: case 0x0b: return 4;
    case 0x02: case 0x0a: return 2;
    default: return 0;
    }
}

typedef struct {
    const uint8_t *at;
    uint64_t code_align;
    int64_t data_align;
    uint8_t return_register, pointer_encoding;
    bool augmented;
    const uint8_t *initial;
    size_t initial_size;
} source_cie;

static bool parse_cie(const uint8_t *cie, const uint8_t *limit, source_cie *out) {
    if (cie + 12 > limit)
        return false;
    uint32_t length, id;
    memcpy(&length, cie, 4);
    memcpy(&id, cie + 4, 4);
    const uint8_t *p = cie + 8, *end = cie + 4 + length;
    if (!length || length == 0xffffffff || id != 0 || end > limit)
        return false;
    uint8_t version = *p++;
    const char *augmentation = (const char *)p;
    size_t name = strnlen(augmentation, (size_t)(end - p));
    if (p + name >= end)
        return false;
    p += name + 1;
    out->at = cie;
    out->code_align = read_uleb(&p, end);
    out->data_align = read_sleb(&p, end);
    out->return_register = version == 1 ? *p++ : (uint8_t)read_uleb(&p, end);
    out->pointer_encoding = 0x00;
    out->augmented = augmentation[0] == 'z';
    if (out->augmented) {
        uint64_t data = read_uleb(&p, end);
        const uint8_t *data_end = p + data;
        if (data_end > end)
            return false;
        for (const char *c = augmentation + 1; *c; c++) {
            switch (*c) {
            case 'P': {
                size_t size = encoded_size(*p);
                if (!size)
                    return false;
                p += 1 + size;
                break;
            }
            case 'L': p++; break;
            case 'R': out->pointer_encoding = *p++; break;
            case 'S': case 'B': case 'G': break;
            default: return false;
            }
        }
        p = data_end;
    } else if (augmentation[0]) {
        return false;
    }
    out->initial = p;
    out->initial_size = (size_t)(end - p);
    return true;
}

/// The call frame instructions of the FDE at `fde`, and its CIE.
static bool parse_fde(const uint8_t *fde, const uint8_t *section, const uint8_t *limit, source_cie *cie,
                      const uint8_t **instructions, size_t *instructions_size) {
    if (fde + 12 > limit)
        return false;
    uint32_t length, back;
    memcpy(&length, fde, 4);
    memcpy(&back, fde + 4, 4);
    const uint8_t *p = fde + 8, *end = fde + 4 + length;
    if (!length || length == 0xffffffff || !back || end > limit || fde + 4 - back < section)
        return false;
    if (!parse_cie(fde + 4 - back, limit, cie))
        return false;
    size_t pointer = encoded_size(cie->pointer_encoding);
    if (!pointer || p + 2 * pointer > end)
        return false;
    p += 2 * pointer;           // where the function starts, and its length
    if (cie->augmented) {
        uint64_t data = read_uleb(&p, end);
        if (p + data > end)
            return false;
        p += data;
    }
    *instructions = p;
    *instructions_size = (size_t)(end - p);
    return true;
}

// MARK: - An image's unwind info

typedef struct { uint32_t offset, encoding; } function_entry;

static uint32_t word(const uint8_t *base, size_t offset) {
    uint32_t value;
    memcpy(&value, base + offset, 4);
    return value;
}

static uint16_t half(const uint8_t *base, size_t offset) {
    uint16_t value;
    memcpy(&value, base + offset, 2);
    return value;
}

void perry_register_unwind_info(perry_image *image) {
    static void (*register_frame)(void *);
    static bool looked;
    if (!looked) {
        // The unwinder's library, which the loader doesn't link itself: the
        // one the process's C++ libraries raise exceptions with.
        void *unwinder = dlopen("libgcc_s.so.1", RTLD_NOW | RTLD_GLOBAL);
        if (unwinder)
            register_frame = (void (*)(void *))dlsym(unwinder, "__register_frame");
        looked = true;
    }
    const struct section_64 *section = perry_image_section(image, "__TEXT", "__unwind_info");
    if (!register_frame || !section || section->size < 28)
        return;
    const uint8_t *info = perry_image_vmaddr(image, section->addr);
    size_t info_size = section->size;
    if (word(info, 0) != 1)
        return;
    uint32_t common_offset = word(info, 4), common_count = word(info, 8);
    uint32_t personality_offset = word(info, 12), personality_count = word(info, 16);
    uint32_t index_offset = word(info, 20), index_count = word(info, 24);
    if (index_count < 2 || (uint64_t)index_offset + 12ull * index_count > info_size ||
        (uint64_t)common_offset + 4ull * common_count > info_size ||
        (uint64_t)personality_offset + 4ull * personality_count > info_size)
        return;

    // Every function's offset from the image's header and its encoding,
    // in order, from the pages the first-level index lists.
    function_entry *functions = NULL;
    size_t count = 0, capacity = 0;
    for (uint32_t i = 0; i + 1 < index_count; i++) {
        uint32_t first = word(info, index_offset + 12 * i), page = word(info, index_offset + 12 * i + 4);
        if (!page || (uint64_t)page + 12 > info_size)
            continue;
        uint32_t kind = word(info, page);
        uint32_t entries_at = page + half(info, page + 4), entries = half(info, page + 6);
        if (count + entries > capacity) {
            capacity = (count + entries) * 2;
            functions = realloc(functions, capacity * sizeof(*functions));
            if (!functions)
                perry_fatal("out of memory for unwind information");
        }
        if (kind == 2 && (uint64_t)entries_at + 8ull * entries <= info_size) {
            for (uint32_t k = 0; k < entries; k++)
                functions[count++] = (function_entry){ word(info, entries_at + 8 * k), word(info, entries_at + 8 * k + 4) };
        } else if (kind == 3 && (uint64_t)entries_at + 4ull * entries <= info_size) {
            uint32_t local_at = page + half(info, page + 8), local_count = half(info, page + 10);
            for (uint32_t k = 0; k < entries; k++) {
                uint32_t entry = word(info, entries_at + 4 * k), which = entry >> 24, encoding = 0;
                if (which < common_count)
                    encoding = word(info, common_offset + 4 * which);
                else if (which - common_count < local_count && (uint64_t)local_at + 4ull * (which - common_count) + 4 <= info_size)
                    encoding = word(info, local_at + 4 * (which - common_count));
                functions[count++] = (function_entry){ first + (entry & 0xffffff), encoding };
            }
        }
    }
    if (!count) {
        free(functions);
        return;
    }
    uint32_t end_offset = word(info, index_offset + 12 * (index_count - 1));

    // The LSDAs, one array for the image, in the functions' order.
    uint32_t lsda_at = word(info, index_offset + 8), lsda_end = word(info, index_offset + 12 * (index_count - 1) + 8);
    if (lsda_end > info_size || lsda_at > lsda_end)
        lsda_at = lsda_end = 0;

    const struct section_64 *frames_section = perry_image_section(image, "__TEXT", "__eh_frame");
    const uint8_t *frames = frames_section ? perry_image_vmaddr(image, frames_section->addr) : NULL;
    const uint8_t *frames_limit = frames ? frames + frames_section->size : NULL;

    // The personality routines: each named by where its pointer is, bound
    // by now. One that isn't here leaves its functions without handlers.
    uintptr_t personalities[4] = { 0 };
    for (uint32_t i = 0; i < personality_count && i < 3; i++) {
        uint32_t at = word(info, personality_offset + 4 * i);
        if ((uint64_t)at + 8 <= image->vm_size)
            memcpy(&personalities[i + 1], image->base + at, sizeof(uintptr_t));
    }

    buffer out = { 0 };
    // CIEs for the frames made from compact encodings, one per personality:
    // the CFA starts as sp, the return address is x30's.
    static const uint8_t compact_initial[] = { 0x0c, 31, 0 };
    size_t compact_cies[4];
    bool compact_made[4] = { false };
    // CIEs for FDEs carried over, by the CIE they had and their personality.
    struct { const uint8_t *source; uint32_t personality; size_t offset; } carried[64];
    size_t carried_count = 0, carried_next = 0;
    uint32_t compact = 0, dwarf = 0, without = 0;

    for (size_t i = 0; i < count; i++) {
        uint32_t offset = functions[i].offset, encoding = functions[i].encoding;
        uint32_t next = i + 1 < count ? functions[i + 1].offset : end_offset;
        if (next <= offset || next > image->vm_size)
            continue;
        uint32_t which = (encoding >> UNWIND_PERSONALITY_SHIFT) & 3;
        uintptr_t personality = personalities[which];
        uintptr_t lsda = 0;
        if (encoding & UNWIND_HAS_LSDA) {
            while (lsda_at + 8 <= lsda_end && word(info, lsda_at) < offset)
                lsda_at += 8;
            if (lsda_at + 8 <= lsda_end && word(info, lsda_at) == offset)
                lsda = (uintptr_t)image->base + word(info, lsda_at + 4);
        }
        uintptr_t start = (uintptr_t)image->base + offset;
        uint8_t made[64];
        size_t made_size = 0;
        switch (encoding & UNWIND_ARM64_MODE_MASK) {
        case UNWIND_ARM64_MODE_FRAME:
            made_size = frame_instructions(encoding, made);
            break;
        case UNWIND_ARM64_MODE_FRAMELESS: {
            // Only sp was moved; the return address is still in x30.
            uint32_t stack = ((encoding >> 12) & 0xfff) * 16;
            if (stack) {
                made[made_size++] = 0x0e;       // DW_CFA_def_cfa_offset
                for (uint32_t rest = stack;;) {
                    uint8_t byte = rest & 0x7f;
                    rest >>= 7;
                    made[made_size++] = rest ? byte | 0x80 : byte;
                    if (!rest)
                        break;
                }
            }
            break;
        }
        case UNWIND_ARM64_MODE_DWARF: {
            source_cie cie;
            const uint8_t *instructions;
            size_t instructions_size;
            if (!frames || !parse_fde(frames + (encoding & 0xffffff), frames, frames_limit, &cie, &instructions, &instructions_size)) {
                without++;
                continue;
            }
            size_t found = carried_count;
            for (size_t k = 0; k < carried_count; k++)
                if (carried[k].source == cie.at && carried[k].personality == which)
                    found = k;
            if (found == carried_count) {
                // Remembered while there is room, then in place of the
                // oldest: an image has a CIE for each file it was made of,
                // and functions that share one are together.
                found = carried_next++ % (sizeof(carried) / sizeof(carried[0]));
                if (carried_count < sizeof(carried) / sizeof(carried[0]))
                    carried_count++;
                carried[found].source = cie.at;
                carried[found].personality = which;
                carried[found].offset = write_cie(&out, cie.code_align, cie.data_align, cie.return_register, personality,
                                                  cie.initial, cie.initial_size);
            }
            write_fde(&out, carried[found].offset, personality != 0, start, next - offset, lsda, instructions, instructions_size);
            dwarf++;
            continue;
        }
        default:
            // No unwind information: nothing unwinds through it.
            without++;
            continue;
        }
        if (!compact_made[which]) {
            compact_cies[which] = write_cie(&out, 1, -8, 30, personality, compact_initial, sizeof(compact_initial));
            compact_made[which] = true;
        }
        write_fde(&out, compact_cies[which], personality != 0, start, next - offset, lsda, made, made_size);
        compact++;
    }
    free(functions);
    if (!compact && !dwarf) {
        free(out.bytes);
        return;
    }
    put32(&out, 0);             // the end of the list
    // Kept for as long as the image is, which is the life of the process.
    register_frame(out.bytes);
    perry_trace(PERRY_TRACE_LOAD, "%s: unwind information for %u functions (%u with their own DWARF), %u without",
                image->path, compact + dwarf, dwarf, without);
}
#endif
