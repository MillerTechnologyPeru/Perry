#ifndef PERRY_MACHO_H
#define PERRY_MACHO_H

// Walking a mapped Mach-O image's load commands, for 64-bit images
// (mach_header_64, LC_SEGMENT_64, section_64) and 32-bit ones (mach_header,
// LC_SEGMENT, section).

#include <stdint.h>
#include <string.h>

static inline int perry_macho_is64(const void *header) {
    return *(const uint32_t *)header == 0xfeedfacf;
}

static inline const uint8_t *perry_macho_commands(const void *header) {
    return (const uint8_t *)header + (perry_macho_is64(header) ? 32 : 28);
}

static inline uint32_t perry_macho_command_count(const void *header) {
    return ((const uint32_t *)header)[4];
}

static inline const uint8_t *perry_macho_next(const uint8_t *command) {
    return command + ((const uint32_t *)command)[1];
}

// A segment command's fields, of either size.
typedef struct {
    const char *name;
    uint64_t vmaddr, vmsize, filesize;
    uint32_t section_count;
    const uint8_t *sections;
    int is64;
} perry_macho_segment;

// False for a command that is not a segment.
static inline int perry_macho_segment_at(const uint8_t *command, perry_macho_segment *out) {
    uint32_t kind = ((const uint32_t *)command)[0];
    if (kind == 0x19) {         // LC_SEGMENT_64
        out->name = (const char *)command + 8;
        memcpy(&out->vmaddr, command + 24, 8);
        memcpy(&out->vmsize, command + 32, 8);
        memcpy(&out->filesize, command + 48, 8);
        memcpy(&out->section_count, command + 64, 4);
        out->sections = command + 72;
        out->is64 = 1;
        return 1;
    }
    if (kind == 0x1) {          // LC_SEGMENT
        const uint32_t *fields = (const uint32_t *)command;
        out->name = (const char *)command + 8;
        out->vmaddr = fields[6];
        out->vmsize = fields[7];
        out->filesize = fields[9];
        out->section_count = fields[12];
        out->sections = command + 56;
        out->is64 = 0;
        return 1;
    }
    return 0;
}

// A section's header within a segment: section_64 (80 bytes) or section
// (68 bytes), with its address and size.
static inline const uint8_t *perry_macho_section(const perry_macho_segment *segment, uint32_t index,
                                                 uint64_t *addr, uint64_t *size) {
    const uint8_t *entry = segment->sections + index * (segment->is64 ? 80 : 68);
    if (segment->is64) {
        memcpy(addr, entry + 32, 8);
        memcpy(size, entry + 40, 8);
    } else {
        *addr = ((const uint32_t *)entry)[8];
        *size = ((const uint32_t *)entry)[9];
    }
    return entry;
}

#endif
