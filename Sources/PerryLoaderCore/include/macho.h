// Mach-O file format definitions used by the Perry loader.
//
// Written from Apple's published format documentation (mach-o/loader.h,
// mach-o/fixup-chains.h, mach-o/fat.h). Only what Perry needs is defined.

#ifndef PERRY_MACHO_H
#define PERRY_MACHO_H

#include <stdint.h>

// MARK: - Headers

#define MH_MAGIC                0xfeedfaceu
#define MH_MAGIC_64             0xfeedfacfu
#define FAT_MAGIC               0xcafebabeu
#define FAT_MAGIC_64            0xcafebabfu

#define CPU_ARCH_ABI64          0x01000000
#define CPU_TYPE_ARM            12
#define CPU_TYPE_ARM64          (CPU_TYPE_ARM | CPU_ARCH_ABI64)
#define CPU_TYPE_X86_64         (7 | CPU_ARCH_ABI64)
#define CPU_SUBTYPE_MASK        0xff000000u
#define CPU_SUBTYPE_ARM64_ALL   0
#define CPU_SUBTYPE_ARM64_V8    1
#define CPU_SUBTYPE_ARM64E      2
#define CPU_SUBTYPE_ARM_ALL     0
#define CPU_SUBTYPE_ARM_V6      6
#define CPU_SUBTYPE_ARM_V7      9
#define CPU_SUBTYPE_ARM_V7F     10
#define CPU_SUBTYPE_ARM_V7S     11
#define CPU_SUBTYPE_ARM_V7K     12

#define MH_EXECUTE              0x2
#define MH_DYLIB                0x6
#define MH_BUNDLE               0x8

#define MH_TWOLEVEL             0x80
#define MH_PIE                  0x200000

struct mach_header_64 {
    uint32_t magic;
    int32_t cputype;
    int32_t cpusubtype;
    uint32_t filetype;
    uint32_t ncmds;
    uint32_t sizeofcmds;
    uint32_t flags;
    uint32_t reserved;
};

struct mach_header {
    uint32_t magic;
    int32_t cputype;
    int32_t cpusubtype;
    uint32_t filetype;
    uint32_t ncmds;
    uint32_t sizeofcmds;
    uint32_t flags;
};

// Fat headers are always big-endian.
struct fat_header {
    uint32_t magic;
    uint32_t nfat_arch;
};

struct fat_arch {
    int32_t cputype;
    int32_t cpusubtype;
    uint32_t offset;
    uint32_t size;
    uint32_t align;
};

struct fat_arch_64 {
    int32_t cputype;
    int32_t cpusubtype;
    uint64_t offset;
    uint64_t size;
    uint32_t align;
    uint32_t reserved;
};

// MARK: - Load commands

#define LC_REQ_DYLD                 0x80000000u
#define LC_SYMTAB                   0x2
#define LC_SEGMENT                  0x1
#define LC_UNIXTHREAD               0x5
#define LC_DYSYMTAB                 0xb
#define LC_LOAD_DYLIB               0xc
#define LC_ID_DYLIB                 0xd
#define LC_LOAD_DYLINKER            0xe
#define LC_LOAD_WEAK_DYLIB          (0x18 | LC_REQ_DYLD)
#define LC_SEGMENT_64               0x19
#define LC_UUID                     0x1b
#define LC_RPATH                    (0x1c | LC_REQ_DYLD)
#define LC_REEXPORT_DYLIB           (0x1f | LC_REQ_DYLD)
#define LC_LAZY_LOAD_DYLIB          0x20
#define LC_ENCRYPTION_INFO          0x21
#define LC_DYLD_INFO                0x22
#define LC_DYLD_INFO_ONLY           (0x22 | LC_REQ_DYLD)
#define LC_LOAD_UPWARD_DYLIB        (0x23 | LC_REQ_DYLD)
#define LC_VERSION_MIN_MACOSX       0x24
#define LC_VERSION_MIN_IPHONEOS     0x25
#define LC_MAIN                     (0x28 | LC_REQ_DYLD)
#define LC_ENCRYPTION_INFO_64       0x2c
#define LC_BUILD_VERSION            0x32
#define LC_DYLD_EXPORTS_TRIE        (0x33 | LC_REQ_DYLD)
#define LC_DYLD_CHAINED_FIXUPS      (0x34 | LC_REQ_DYLD)

struct load_command {
    uint32_t cmd;
    uint32_t cmdsize;
};

// LC_UNIXTHREAD: the initial register state, laid out by flavor.
struct thread_command {
    uint32_t cmd;
    uint32_t cmdsize;
    uint32_t flavor;
    uint32_t count;     // in 32-bit words
    uint32_t state[];
};

#define ARM_THREAD_STATE        1
#define ARM_THREAD_STATE_PC     15      // r15, in the 17 words of r0-r12, sp, lr, pc, cpsr

#define SG_READ_ONLY 0x10

struct segment_command {
    uint32_t cmd;
    uint32_t cmdsize;
    char segname[16];
    uint32_t vmaddr;
    uint32_t vmsize;
    uint32_t fileoff;
    uint32_t filesize;
    int32_t maxprot;
    int32_t initprot;
    uint32_t nsects;
    uint32_t flags;
};

struct segment_command_64 {
    uint32_t cmd;
    uint32_t cmdsize;
    char segname[16];
    uint64_t vmaddr;
    uint64_t vmsize;
    uint64_t fileoff;
    uint64_t filesize;
    int32_t maxprot;
    int32_t initprot;
    uint32_t nsects;
    uint32_t flags;
};

#define SECTION_TYPE                0x000000ffu
#define S_ZEROFILL                  0x1
#define S_NON_LAZY_SYMBOL_POINTERS  0x6
#define S_LAZY_SYMBOL_POINTERS      0x7
#define S_MOD_INIT_FUNC_POINTERS    0x9
#define S_THREAD_LOCAL_REGULAR      0x11
#define S_THREAD_LOCAL_ZEROFILL     0x12
#define S_THREAD_LOCAL_VARIABLES    0x13
#define S_THREAD_LOCAL_INIT_FUNCTION_POINTERS 0x15
#define S_INIT_FUNC_OFFSETS         0x16

struct section_64 {
    char sectname[16];
    char segname[16];
    uint64_t addr;
    uint64_t size;
    uint32_t offset;
    uint32_t align;
    uint32_t reloff;
    uint32_t nreloc;
    uint32_t flags;
    uint32_t reserved1;
    uint32_t reserved2;
    uint32_t reserved3;
};

struct section {
    char sectname[16];
    char segname[16];
    uint32_t addr;
    uint32_t size;
    uint32_t offset;
    uint32_t align;
    uint32_t reloff;
    uint32_t nreloc;
    uint32_t flags;
    uint32_t reserved1;
    uint32_t reserved2;
};

struct dylib_command {
    uint32_t cmd;
    uint32_t cmdsize;
    uint32_t name_offset;
    uint32_t timestamp;
    uint32_t current_version;
    uint32_t compatibility_version;
};

struct rpath_command {
    uint32_t cmd;
    uint32_t cmdsize;
    uint32_t path_offset;
};

struct entry_point_command {
    uint32_t cmd;
    uint32_t cmdsize;
    uint64_t entryoff;
    uint64_t stacksize;
};

struct encryption_info_command {
    uint32_t cmd;
    uint32_t cmdsize;
    uint32_t cryptoff;
    uint32_t cryptsize;
    uint32_t cryptid;
};

struct encryption_info_command_64 {
    uint32_t cmd;
    uint32_t cmdsize;
    uint32_t cryptoff;
    uint32_t cryptsize;
    uint32_t cryptid;
    uint32_t pad;
};

#define PLATFORM_MACOS              1
#define PLATFORM_IOS                2
#define PLATFORM_TVOS               3
#define PLATFORM_WATCHOS            4
#define PLATFORM_MACCATALYST        6
#define PLATFORM_IOSSIMULATOR       7

struct build_version_command {
    uint32_t cmd;
    uint32_t cmdsize;
    uint32_t platform;
    uint32_t minos;
    uint32_t sdk;
    uint32_t ntools;
};

struct version_min_command {
    uint32_t cmd;
    uint32_t cmdsize;
    uint32_t version;
    uint32_t sdk;
};

struct linkedit_data_command {
    uint32_t cmd;
    uint32_t cmdsize;
    uint32_t dataoff;
    uint32_t datasize;
};

struct dyld_info_command {
    uint32_t cmd;
    uint32_t cmdsize;
    uint32_t rebase_off;
    uint32_t rebase_size;
    uint32_t bind_off;
    uint32_t bind_size;
    uint32_t weak_bind_off;
    uint32_t weak_bind_size;
    uint32_t lazy_bind_off;
    uint32_t lazy_bind_size;
    uint32_t export_off;
    uint32_t export_size;
};

struct nlist {
    uint32_t n_strx;
    uint8_t n_type;
    uint8_t n_sect;
    int16_t n_desc;
    uint32_t n_value;
};

#define N_STAB                  0xe0
#define N_TYPE                  0x0e
#define N_EXT                   0x01
#define N_SECT                  0xe
#define N_ARM_THUMB_DEF         0x0008  // n_desc: the symbol is Thumb code

#define N_UNDF                  0x0
#define N_WEAK_REF              0x0040  // n_desc: the import may be missing
// n_desc's high byte of an undefined symbol: its library's ordinal.
#define GET_LIBRARY_ORDINAL(n_desc) (((n_desc) >> 8) & 0xff)

// The dynamic symbol table (LC_DYSYMTAB), which images linked before
// LC_DYLD_INFO (iOS 3.1) are bound from: the indirect symbol table names the
// symbol of each symbol pointer and stub, and the external relocations the
// symbols other pointers refer to.
struct dysymtab_command {
    uint32_t cmd;
    uint32_t cmdsize;
    uint32_t ilocalsym, nlocalsym;
    uint32_t iextdefsym, nextdefsym;
    uint32_t iundefsym, nundefsym;
    uint32_t tocoff, ntoc;
    uint32_t modtaboff, nmodtab;
    uint32_t extrefsymoff, nextrefsyms;
    uint32_t indirectsymoff, nindirectsyms;
    uint32_t extreloff, nextrel;
    uint32_t locreloff, nlocrel;
};

#define INDIRECT_SYMBOL_LOCAL   0x80000000u
#define INDIRECT_SYMBOL_ABS     0x40000000u

// r_address is from the image's first segment; a scattered entry has its
// high bit set.
struct relocation_info {
    int32_t r_address;
    uint32_t r_symbolnum : 24, r_pcrel : 1, r_length : 2, r_extern : 1, r_type : 4;
};
#define R_SCATTERED             0x80000000u
#define GENERIC_RELOC_VANILLA   0

struct symtab_command {
    uint32_t cmd;
    uint32_t cmdsize;
    uint32_t symoff;
    uint32_t nsyms;
    uint32_t stroff;
    uint32_t strsize;
};

// MARK: - The image's own pointer width

// The loader maps images of its own pointer width: a 64-bit loader loads
// arm64 Mach-O, a 32-bit one loads armv7 Mach-O. These name the structures
// of whichever it is, so the code that walks them is written once.

#if defined(__LP64__)
#define MH_MAGIC_NATIVE         MH_MAGIC_64
#define LC_SEGMENT_NATIVE       LC_SEGMENT_64
#define LC_ENCRYPTION_INFO_NATIVE LC_ENCRYPTION_INFO_64
typedef struct mach_header_64 mach_header_t;
typedef struct segment_command_64 segment_command_t;
typedef struct section_64 section_t;
typedef struct encryption_info_command_64 encryption_info_command_t;
#else
#define MH_MAGIC_NATIVE         MH_MAGIC
#define LC_SEGMENT_NATIVE       LC_SEGMENT
#define LC_ENCRYPTION_INFO_NATIVE LC_ENCRYPTION_INFO
typedef struct mach_header mach_header_t;
typedef struct segment_command segment_command_t;
typedef struct section section_t;
typedef struct encryption_info_command encryption_info_command_t;
#endif

// MARK: - Library ordinals

#define BIND_SPECIAL_DYLIB_SELF             0
#define BIND_SPECIAL_DYLIB_MAIN_EXECUTABLE  (-1)
#define BIND_SPECIAL_DYLIB_FLAT_LOOKUP      (-2)
#define BIND_SPECIAL_DYLIB_WEAK_LOOKUP      (-3)

// MARK: - Legacy dyld info opcodes

#define REBASE_TYPE_POINTER                         1
#define REBASE_OPCODE_MASK                          0xf0
#define REBASE_IMMEDIATE_MASK                       0x0f
#define REBASE_OPCODE_DONE                          0x00
#define REBASE_OPCODE_SET_TYPE_IMM                  0x10
#define REBASE_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB   0x20
#define REBASE_OPCODE_ADD_ADDR_ULEB                 0x30
#define REBASE_OPCODE_ADD_ADDR_IMM_SCALED           0x40
#define REBASE_OPCODE_DO_REBASE_IMM_TIMES           0x50
#define REBASE_OPCODE_DO_REBASE_ULEB_TIMES          0x60
#define REBASE_OPCODE_DO_REBASE_ADD_ADDR_ULEB       0x70
#define REBASE_OPCODE_DO_REBASE_ULEB_TIMES_SKIPPING_ULEB 0x80

#define BIND_TYPE_POINTER                           1
#define BIND_SYMBOL_FLAGS_WEAK_IMPORT               0x1
#define BIND_SYMBOL_FLAGS_NON_WEAK_DEFINITION       0x8
#define BIND_OPCODE_MASK                            0xf0
#define BIND_IMMEDIATE_MASK                         0x0f
#define BIND_OPCODE_DONE                            0x00
#define BIND_OPCODE_SET_DYLIB_ORDINAL_IMM           0x10
#define BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB          0x20
#define BIND_OPCODE_SET_DYLIB_SPECIAL_IMM           0x30
#define BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM   0x40
#define BIND_OPCODE_SET_TYPE_IMM                    0x50
#define BIND_OPCODE_SET_ADDEND_SLEB                 0x60
#define BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB     0x70
#define BIND_OPCODE_ADD_ADDR_ULEB                   0x80
#define BIND_OPCODE_DO_BIND                         0x90
#define BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB           0xa0
#define BIND_OPCODE_DO_BIND_ADD_ADDR_IMM_SCALED     0xb0
#define BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB 0xc0
#define BIND_OPCODE_THREADED                        0xd0

// MARK: - Export trie

#define EXPORT_SYMBOL_FLAGS_KIND_MASK           0x03
#define EXPORT_SYMBOL_FLAGS_KIND_REGULAR        0x00
#define EXPORT_SYMBOL_FLAGS_KIND_THREAD_LOCAL   0x01
#define EXPORT_SYMBOL_FLAGS_KIND_ABSOLUTE       0x02
#define EXPORT_SYMBOL_FLAGS_WEAK_DEFINITION     0x04
#define EXPORT_SYMBOL_FLAGS_REEXPORT            0x08
#define EXPORT_SYMBOL_FLAGS_STUB_AND_RESOLVER   0x10

// MARK: - Chained fixups

struct dyld_chained_fixups_header {
    uint32_t fixups_version;
    uint32_t starts_offset;
    uint32_t imports_offset;
    uint32_t symbols_offset;
    uint32_t imports_count;
    uint32_t imports_format;
    uint32_t symbols_format;
};

struct dyld_chained_starts_in_image {
    uint32_t seg_count;
    uint32_t seg_info_offset[];
};

struct dyld_chained_starts_in_segment {
    uint32_t size;
    uint16_t page_size;
    uint16_t pointer_format;
    uint64_t segment_offset;
    uint32_t max_valid_pointer;
    uint16_t page_count;
    uint16_t page_start[];
};

#define DYLD_CHAINED_PTR_START_NONE     0xffff
#define DYLD_CHAINED_PTR_START_MULTI    0x8000
#define DYLD_CHAINED_PTR_START_LAST     0x8000

#define DYLD_CHAINED_PTR_ARM64E         1
#define DYLD_CHAINED_PTR_64             2
#define DYLD_CHAINED_PTR_64_OFFSET      6
#define DYLD_CHAINED_PTR_ARM64E_USERLAND 9
#define DYLD_CHAINED_PTR_ARM64E_USERLAND24 12

#define DYLD_CHAINED_IMPORT             1
#define DYLD_CHAINED_IMPORT_ADDEND      2
#define DYLD_CHAINED_IMPORT_ADDEND64    3

// Bitfield layouts for DYLD_CHAINED_PTR_64 and DYLD_CHAINED_PTR_64_OFFSET.
// rebase: target:36 high8:8 reserved:7 next:12 bind:1
// bind:   ordinal:24 addend:8 reserved:19 next:12 bind:1
#define CHAINED_PTR64_BIND(v)           (((v) >> 63) & 1)
#define CHAINED_PTR64_NEXT(v)           (((v) >> 51) & 0xfff)
#define CHAINED_PTR64_TARGET(v)         ((v) & 0xfffffffffull)
#define CHAINED_PTR64_HIGH8(v)          (((v) >> 36) & 0xff)
#define CHAINED_PTR64_ORDINAL(v)        ((v) & 0xffffff)
#define CHAINED_PTR64_ADDEND(v)         (((v) >> 24) & 0xff)

#endif
