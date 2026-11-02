// Mach-O image mapping, dependency loading, initializers and entry.

#define _GNU_SOURCE
#include "image.h"
#include "log.h"
#include "perry_interface.h"

#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <link.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#ifndef MAP_FIXED_NOREPLACE
#define MAP_FIXED_NOREPLACE 0x100000
#endif

static size_t host_page_size;

// MARK: - Loader setup

static void add_library_dir(perry_loader *loader, const char *dir) {
    loader->library_dirs = realloc(loader->library_dirs, sizeof(char *) * (loader->library_dir_count + 1));
    loader->library_dirs[loader->library_dir_count++] = strdup(dir);
}

void perry_loader_init(perry_loader *loader) {
    memset(loader, 0, sizeof(*loader));
    loader->images_tail = &loader->images;
    host_page_size = (size_t)sysconf(_SC_PAGESIZE);
    if (host_page_size > 0x4000)
        perry_fatal("host page size %zu is larger than the 16 KB Mach-O segment alignment", host_page_size);

    const char *env = getenv("PERRY_LIBRARY_PATH");
    if (env) {
        char *copy = strdup(env);
        for (char *save = NULL, *dir = strtok_r(copy, ":", &save); dir; dir = strtok_r(NULL, ":", &save))
            add_library_dir(loader, dir);
        free(copy);
    }

    char exe[PATH_MAX];
    ssize_t len = readlink("/proc/self/exe", exe, sizeof(exe) - 1);
    if (len > 0) {
        exe[len] = 0;
        char *slash = strrchr(exe, '/');
        if (slash) {
            *slash = 0;
            char dir[PATH_MAX + 32];
            add_library_dir(loader, exe);
            snprintf(dir, sizeof(dir), "%s/../lib/perry", exe);
            add_library_dir(loader, dir);
        }
    }
}

// MARK: - Address helpers

void *perry_image_vmaddr(const perry_image *image, uint64_t unslid) {
    return (void *)(uintptr_t)(unslid + (uint64_t)image->slide);
}

void *perry_image_fileoff(const perry_image *image, uint64_t fileoff) {
    for (uint32_t i = 0; i < image->segment_count; i++) {
        const perry_segment *seg = &image->segments[i];
        if (seg->mapped && seg->filesize && fileoff >= seg->fileoff && fileoff < seg->fileoff + seg->filesize)
            return perry_image_vmaddr(image, seg->vmaddr + (fileoff - seg->fileoff));
    }
    return NULL;
}

const struct section_64 *perry_image_section(const perry_image *image, const char *segname, const char *sectname) {
    for (uint32_t i = 0; i < image->segment_count; i++) {
        const perry_segment *seg = &image->segments[i];
        if (segname && strncmp(seg->name, segname, 16) != 0)
            continue;
        for (uint32_t j = 0; j < seg->nsects; j++)
            if (strncmp(seg->sections[j].sectname, sectname, 16) == 0)
                return &seg->sections[j];
    }
    return NULL;
}

const char *perry_platform_name(uint32_t platform) {
    switch (platform) {
    case PLATFORM_MACOS: return "macOS";
    case PLATFORM_IOS: return "iOS";
    case PLATFORM_TVOS: return "tvOS";
    case PLATFORM_WATCHOS: return "watchOS";
    case PLATFORM_MACCATALYST: return "Mac Catalyst";
    case PLATFORM_IOSSIMULATOR: return "iOS Simulator";
    case 0: return "unknown";
    default: return "other";
    }
}

static char *dirname_of(const char *path) {
    const char *slash = strrchr(path, '/');
    if (!slash)
        return strdup(".");
    return strndup(path, (size_t)(slash - path));
}

static bool file_exists(const char *path) {
    struct stat st;
    return stat(path, &st) == 0 && S_ISREG(st.st_mode);
}

// MARK: - File access

typedef struct macho_file {
    uint8_t *map;
    size_t map_size;
    const uint8_t *data;   // start of the arm64 slice
    size_t size;
} macho_file;

static uint32_t be32(uint32_t v) { return __builtin_bswap32(v); }
static uint64_t be64(uint64_t v) { return __builtin_bswap64(v); }

static void check_cpu(const char *path, int32_t cputype, int32_t cpusubtype) {
    if (cputype != CPU_TYPE_ARM64)
        perry_fatal("%s: not an arm64 binary (cputype 0x%x)", path, cputype);
    if (((uint32_t)cpusubtype & ~CPU_SUBTYPE_MASK) == CPU_SUBTYPE_ARM64E)
        perry_fatal("%s: arm64e binaries are not supported (pointer authentication)", path);
}

static bool open_macho(const char *path, macho_file *out) {
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return false;
    struct stat st;
    if (fstat(fd, &st) != 0 || st.st_size < (off_t)sizeof(struct mach_header_64)) {
        close(fd);
        perry_fatal("%s: file too small to be a Mach-O binary", path);
    }
    void *map = mmap(NULL, (size_t)st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);
    if (map == MAP_FAILED)
        perry_fatal("%s: mmap failed: %s", path, strerror(errno));

    out->map = map;
    out->map_size = (size_t)st.st_size;
    out->data = map;
    out->size = (size_t)st.st_size;

    uint32_t magic = *(const uint32_t *)map;
    if (magic == be32(FAT_MAGIC) || magic == be32(FAT_MAGIC_64)) {
        const struct fat_header *fat = map;
        bool is64 = magic == be32(FAT_MAGIC_64);
        uint32_t count = be32(fat->nfat_arch);
        const uint8_t *arches = (const uint8_t *)(fat + 1);
        bool found = false;
        for (uint32_t i = 0; i < count && !found; i++) {
            int32_t cputype, cpusubtype;
            uint64_t offset, size;
            if (is64) {
                const struct fat_arch_64 *arch = (const struct fat_arch_64 *)arches + i;
                cputype = (int32_t)be32((uint32_t)arch->cputype);
                cpusubtype = (int32_t)be32((uint32_t)arch->cpusubtype);
                offset = be64(arch->offset);
                size = be64(arch->size);
            } else {
                const struct fat_arch *arch = (const struct fat_arch *)arches + i;
                cputype = (int32_t)be32((uint32_t)arch->cputype);
                cpusubtype = (int32_t)be32((uint32_t)arch->cpusubtype);
                offset = be32(arch->offset);
                size = be32(arch->size);
            }
            uint32_t sub = (uint32_t)cpusubtype & ~CPU_SUBTYPE_MASK;
            if (cputype == CPU_TYPE_ARM64 && sub != CPU_SUBTYPE_ARM64E) {
                if (offset + size > out->map_size)
                    perry_fatal("%s: truncated fat slice", path);
                out->data = (const uint8_t *)map + offset;
                out->size = size;
                found = true;
            }
        }
        if (!found)
            perry_fatal("%s: universal binary has no arm64 slice", path);
    }

    const struct mach_header_64 *mh = (const struct mach_header_64 *)out->data;
    if (mh->magic != MH_MAGIC_64)
        perry_fatal("%s: not a 64-bit Mach-O binary (magic 0x%08x)", path, mh->magic);
    check_cpu(path, mh->cputype, mh->cpusubtype);
    if (sizeof(*mh) + mh->sizeofcmds > out->size)
        perry_fatal("%s: load commands exceed file size", path);
    return true;
}

// MARK: - Load command parsing

#define FOR_EACH_LOAD_COMMAND(mh, lc) \
    for (const struct load_command *lc = (const struct load_command *)((const struct mach_header_64 *)(mh) + 1), \
         *lc##_end = (const struct load_command *)((const uint8_t *)(lc) + (mh)->sizeofcmds); \
         lc < lc##_end && lc->cmdsize >= sizeof(struct load_command); \
         lc = (const struct load_command *)((const uint8_t *)lc + lc->cmdsize))

// Parses load commands from the mapped header so that every pointer kept in
// the image stays valid after the file mapping is released.
static void parse_load_commands(perry_image *image) {
    const struct mach_header_64 *mh = image->header;
    uint32_t dep_cap = 0, rpath_cap = 0;

    FOR_EACH_LOAD_COMMAND(mh, lc) {
        switch (lc->cmd) {
        case LC_LOAD_DYLIB:
        case LC_LOAD_WEAK_DYLIB:
        case LC_REEXPORT_DYLIB:
        case LC_LOAD_UPWARD_DYLIB:
        case LC_LAZY_LOAD_DYLIB: {
            const struct dylib_command *dc = (const void *)lc;
            if (image->dep_count == dep_cap) {
                dep_cap = dep_cap ? dep_cap * 2 : 8;
                image->deps = realloc(image->deps, sizeof(perry_dependency) * dep_cap);
            }
            perry_dependency *dep = &image->deps[image->dep_count++];
            memset(dep, 0, sizeof(*dep));
            dep->install_name = (const char *)dc + dc->name_offset;
            dep->weak = lc->cmd == LC_LOAD_WEAK_DYLIB;
            dep->reexport = lc->cmd == LC_REEXPORT_DYLIB;
            break;
        }
        case LC_ID_DYLIB: {
            const struct dylib_command *dc = (const void *)lc;
            image->install_name = (const char *)dc + dc->name_offset;
            break;
        }
        case LC_RPATH: {
            const struct rpath_command *rc = (const void *)lc;
            if (image->rpath_count == rpath_cap) {
                rpath_cap = rpath_cap ? rpath_cap * 2 : 4;
                image->rpaths = realloc(image->rpaths, sizeof(char *) * rpath_cap);
            }
            image->rpaths[image->rpath_count++] = (const char *)rc + rc->path_offset;
            break;
        }
        case LC_MAIN: {
            const struct entry_point_command *ep = (const void *)lc;
            image->has_entry = true;
            image->entryoff = ep->entryoff;
            break;
        }
        case LC_UNIXTHREAD:
            if (mh->filetype == MH_EXECUTE)
                perry_fatal("%s: LC_UNIXTHREAD executables are not supported", image->path);
            break;
        case LC_ENCRYPTION_INFO_64: {
            const struct encryption_info_command_64 *ec = (const void *)lc;
            image->cryptid = ec->cryptid;
            image->encrypted = ec->cryptid != 0;
            break;
        }
        case LC_BUILD_VERSION: {
            const struct build_version_command *bv = (const void *)lc;
            image->platform = bv->platform;
            image->minos = bv->minos;
            image->sdk = bv->sdk;
            break;
        }
        case LC_VERSION_MIN_IPHONEOS:
        case LC_VERSION_MIN_MACOSX: {
            const struct version_min_command *vm = (const void *)lc;
            if (!image->platform) {
                image->platform = lc->cmd == LC_VERSION_MIN_IPHONEOS ? PLATFORM_IOS : PLATFORM_MACOS;
                image->minos = vm->version;
                image->sdk = vm->sdk;
            }
            break;
        }
        case LC_DYLD_CHAINED_FIXUPS:
            image->chained_fixups = (const void *)lc;
            break;
        case LC_DYLD_INFO:
        case LC_DYLD_INFO_ONLY: {
            const struct dyld_info_command *di = (const void *)lc;
            image->dyld_info = di;
            if (di->export_size && !image->exports_trie) {
                image->exports_trie = perry_image_fileoff(image, di->export_off);
                image->exports_trie_size = di->export_size;
            }
            break;
        }
        case LC_DYLD_EXPORTS_TRIE: {
            const struct linkedit_data_command *ld = (const void *)lc;
            image->exports_trie = perry_image_fileoff(image, ld->dataoff);
            image->exports_trie_size = ld->datasize;
            break;
        }
        default:
            break;
        }
    }
}

// MARK: - Mapping

static uint64_t round_up(uint64_t value, uint64_t align) {
    return (value + align - 1) & ~(align - 1);
}

// Darwin code assumes user addresses are small: the Objective-C runtime masks
// class data pointers to 47 bits, and iOS processes normally live below
// 64 GB. Linux hands out mmap addresses just under 2^48, so images are placed
// upward from 4 GB, where dyld puts them, instead.
#define PERRY_IMAGE_REGION_START  0x100000000ull
#define PERRY_IMAGE_REGION_END    0x1000000000ull     // 64 GB
#define PERRY_IMAGE_ALIGN         0x4000ull           // Mach-O segment alignment

static void *reserve_low(perry_loader *loader, size_t span) {
    if (!loader->next_image_address)
        loader->next_image_address = PERRY_IMAGE_REGION_START;
    for (uint64_t addr = loader->next_image_address; addr + span <= PERRY_IMAGE_REGION_END;) {
        void *p = mmap((void *)(uintptr_t)addr, span, PROT_NONE,
                       MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE, -1, 0);
        if (p == (void *)(uintptr_t)addr) {
            loader->next_image_address = round_up(addr + span, PERRY_IMAGE_ALIGN);
            return p;
        }
        if (p != MAP_FAILED)
            munmap(p, span);    // kernels without MAP_FIXED_NOREPLACE treat it as a hint
        else if (errno != EEXIST)
            break;
        addr += 0x1000000;      // skip past whatever occupies this range
    }
    perry_warn("no free address range below 64 GB; mapping image high");
    return mmap(NULL, span, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
}

static perry_image *map_image(perry_loader *loader, const char *path, const macho_file *file) {
    const struct mach_header_64 *fmh = (const struct mach_header_64 *)file->data;
    if (fmh->filetype != MH_EXECUTE && fmh->filetype != MH_DYLIB && fmh->filetype != MH_BUNDLE)
        perry_fatal("%s: unsupported Mach-O file type %u", path, fmh->filetype);

    perry_image *image = calloc(1, sizeof(*image));
    image->path = strdup(path);

    // Collect segments from the file copy of the load commands.
    uint32_t seg_cap = 0;
    uint64_t vm_start = UINT64_MAX, vm_end = 0, header_vmaddr = UINT64_MAX;
    FOR_EACH_LOAD_COMMAND(fmh, lc) {
        if (lc->cmd != LC_SEGMENT_64)
            continue;
        const struct segment_command_64 *sc = (const void *)lc;
        bool pagezero = sc->vmaddr == 0 && sc->filesize == 0 && sc->initprot == 0;
        if (sc->fileoff + sc->filesize > file->size)
            perry_fatal("%s: segment %.16s extends past end of file", path, sc->segname);
        if (image->segment_count == seg_cap) {
            seg_cap = seg_cap ? seg_cap * 2 : 8;
            image->segments = realloc(image->segments, sizeof(perry_segment) * seg_cap);
        }
        perry_segment *seg = &image->segments[image->segment_count++];
        memset(seg, 0, sizeof(*seg));
        memcpy(seg->name, sc->segname, 16);
        seg->vmaddr = sc->vmaddr;
        seg->vmsize = sc->vmsize;
        seg->fileoff = sc->fileoff;
        seg->filesize = sc->filesize;
        seg->initprot = sc->initprot;
        seg->flags = sc->flags;
        seg->nsects = sc->nsects;
        seg->mapped = !pagezero && sc->vmsize != 0;
        // Section headers follow the segment command; rebased to the mapped copy below.
        seg->sections = (const struct section_64 *)((const uint8_t *)sc - file->data + sizeof(*sc));
        if (!seg->mapped)
            continue;
        if (sc->vmaddr < vm_start)
            vm_start = sc->vmaddr;
        if (sc->vmaddr + sc->vmsize > vm_end)
            vm_end = sc->vmaddr + sc->vmsize;
        if (sc->fileoff == 0 && sc->filesize)
            header_vmaddr = sc->vmaddr;
    }
    if (vm_end == 0 || header_vmaddr == UINT64_MAX)
        perry_fatal("%s: no segment maps the Mach-O header", path);

    // Reserve the whole range, then map each segment into it.
    size_t span = round_up(vm_end - vm_start, host_page_size);
    bool pie = fmh->filetype != MH_EXECUTE || (fmh->flags & MH_PIE);
    void *reserve = MAP_FAILED;
    if (!pie)
        reserve = mmap((void *)(uintptr_t)vm_start, span, PROT_NONE,
                       MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE, -1, 0);
    if (reserve == MAP_FAILED && !pie)
        perry_fatal("%s: cannot map non-PIE executable at 0x%llx", path, (unsigned long long)vm_start);
    if (reserve == MAP_FAILED)
        reserve = reserve_low(loader, span);
    if (reserve == MAP_FAILED)
        perry_fatal("%s: cannot reserve %zu bytes: %s", path, span, strerror(errno));
    image->vm_start = vm_start;
    image->vm_size = span;
    image->slide = (intptr_t)((uintptr_t)reserve - vm_start);

    for (uint32_t i = 0; i < image->segment_count; i++) {
        perry_segment *seg = &image->segments[i];
        if (!seg->mapped)
            continue;
        uint8_t *addr = perry_image_vmaddr(image, seg->vmaddr);
        if ((uintptr_t)addr % host_page_size)
            perry_fatal("%s: segment %s is not page aligned on this host", path, seg->name);
        size_t size = round_up(seg->vmsize, host_page_size);
        if (mmap(addr, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0) == MAP_FAILED)
            perry_fatal("%s: cannot map segment %s: %s", path, seg->name, strerror(errno));
        memcpy(addr, file->data + seg->fileoff, seg->filesize);
        perry_trace(PERRY_TRACE_LOAD, "  %-16s %p-%p prot %c%c%c", seg->name, (void *)addr,
                    (void *)(addr + seg->vmsize), seg->initprot & 1 ? 'r' : '-',
                    seg->initprot & 2 ? 'w' : '-', seg->initprot & 4 ? 'x' : '-');
    }

    image->base = perry_image_vmaddr(image, header_vmaddr);
    image->header = (const struct mach_header_64 *)image->base;
    for (uint32_t i = 0; i < image->segment_count; i++)
        image->segments[i].sections = (const struct section_64 *)(image->base + (uintptr_t)image->segments[i].sections);

    parse_load_commands(image);

    *loader->images_tail = image;
    loader->images_tail = &image->next;
    return image;
}

// Applies each segment's final protection once fixups are done.
static void protect_image(perry_image *image) {
    for (uint32_t i = 0; i < image->segment_count; i++) {
        perry_segment *seg = &image->segments[i];
        if (!seg->mapped)
            continue;
        uint8_t *addr = perry_image_vmaddr(image, seg->vmaddr);
        size_t size = round_up(seg->vmsize, host_page_size);
        int prot = seg->initprot & (PROT_READ | PROT_WRITE | PROT_EXEC);
        if (seg->flags & SG_READ_ONLY)
            prot &= ~PROT_WRITE;
        if (prot & PROT_EXEC)
            __builtin___clear_cache((char *)addr, (char *)addr + seg->vmsize);
        if (mprotect(addr, size, prot) != 0)
            perry_fatal("%s: mprotect of %s failed: %s", image->path, seg->name, strerror(errno));
    }
}

// MARK: - Dependencies

static perry_image *load_image(perry_loader *loader, const char *path);

// Expands @executable_path, @loader_path and @rpath. Returns a malloc'd path
// to an existing file, or NULL.
static char *expand_install_name(perry_loader *loader, perry_image *image, const char *name) {
    char buf[PATH_MAX];
    if (strncmp(name, "@executable_path/", 17) == 0) {
        char *dir = dirname_of(loader->main_image ? loader->main_image->path : image->path);
        snprintf(buf, sizeof(buf), "%s/%s", dir, name + 17);
        free(dir);
        return file_exists(buf) ? strdup(buf) : NULL;
    }
    if (strncmp(name, "@loader_path/", 13) == 0) {
        char *dir = dirname_of(image->path);
        snprintf(buf, sizeof(buf), "%s/%s", dir, name + 13);
        free(dir);
        return file_exists(buf) ? strdup(buf) : NULL;
    }
    if (strncmp(name, "@rpath/", 7) == 0) {
        // Search the loading image's rpaths, then the main executable's.
        const perry_image *sources[2] = { image, loader->main_image };
        for (int s = 0; s < 2; s++) {
            const perry_image *src = sources[s];
            if (!src || (s == 1 && src == image))
                continue;
            for (uint32_t i = 0; i < src->rpath_count; i++) {
                char base[PATH_MAX];
                const char *rpath = src->rpaths[i];
                if (strncmp(rpath, "@executable_path", 16) == 0) {
                    char *dir = dirname_of(loader->main_image ? loader->main_image->path : image->path);
                    snprintf(base, sizeof(base), "%s%s", dir, rpath + 16);
                    free(dir);
                } else if (strncmp(rpath, "@loader_path", 12) == 0) {
                    char *dir = dirname_of(src->path);
                    snprintf(base, sizeof(base), "%s%s", dir, rpath + 12);
                    free(dir);
                } else {
                    snprintf(base, sizeof(base), "%s", rpath);
                }
                snprintf(buf, sizeof(buf), "%s/%s", base, name + 7);
                if (file_exists(buf))
                    return strdup(buf);
            }
        }
        return NULL;
    }
    return NULL;
}

static perry_image *find_loaded(perry_loader *loader, const char *path) {
    char real[PATH_MAX];
    if (!realpath(path, real))
        return NULL;
    for (perry_image *img = loader->images; img; img = img->next) {
        char other[PATH_MAX];
        if (realpath(img->path, other) && strcmp(real, other) == 0)
            return img;
    }
    return NULL;
}

static void load_dependencies(perry_loader *loader, perry_image *image) {
    for (uint32_t i = 0; i < image->dep_count; i++) {
        perry_dependency *dep = &image->deps[i];
        const char *name = dep->install_name;

        // Linux providers stand in for system libraries.
        if (name[0] == '/')
            dep->provider = perry_find_provider(loader, name);
        if (dep->provider) {
            perry_trace(PERRY_TRACE_LOAD, "%s -> provider %s", name, dep->provider->path);
            continue;
        }

        // Libraries shipped inside the app are loaded as Mach-O.
        char *path = name[0] == '@' ? expand_install_name(loader, image, name)
                                    : (file_exists(name) ? strdup(name) : NULL);
        if (path) {
            dep->image = find_loaded(loader, path);
            if (!dep->image)
                dep->image = load_image(loader, path);
            free(path);
            continue;
        }

        if (dep->weak)
            perry_trace(PERRY_TRACE_LOAD, "weak dependency %s not found", name);
        else if (!loader->report)
            perry_warn("%s: library not available: %s", image->path, name);
    }
}

static perry_image *load_image(perry_loader *loader, const char *path) {
    macho_file file;
    if (!open_macho(path, &file))
        perry_fatal("cannot open %s: %s", path, strerror(errno));
    perry_trace(PERRY_TRACE_LOAD, "loading %s", path);
    perry_image *image = map_image(loader, path, &file);
    munmap(file.map, file.map_size);

    if (image->encrypted && !loader->report)
        perry_fatal("%s: binary is encrypted (cryptid %u); only decrypted binaries can be loaded",
                    path, image->cryptid);
    if (image->platform == PLATFORM_TVOS || image->platform == PLATFORM_WATCHOS)
        perry_warn("%s: built for %s; only iOS and macOS binaries are supported",
                   path, perry_platform_name(image->platform));

    load_dependencies(loader, image);
    return image;
}

perry_image *perry_load_executable(perry_loader *loader, const char *path) {
    macho_file file;
    if (!open_macho(path, &file))
        perry_fatal("cannot open %s: %s", path, strerror(errno));
    const struct mach_header_64 *mh = (const struct mach_header_64 *)file.data;
    if (mh->filetype != MH_EXECUTE)
        perry_fatal("%s: not an executable (file type %u)", path, mh->filetype);
    munmap(file.map, file.map_size);

    // The main image must be known before its dependencies expand @executable_path.
    perry_image *image = calloc(1, sizeof(*image));
    image->path = strdup(path);
    loader->main_image = image;
    perry_image *loaded = load_image(loader, path);
    free(image->path);
    free(image);
    loader->main_image = loaded;

    // Bind every image after all of them are mapped, so symbols resolve across images.
    for (perry_image *img = loader->images; img; img = img->next) {
        perry_apply_fixups(loader, img);
        protect_image(img);
    }
    return loaded;
}

// MARK: - Initializers and entry

// Matches the ProgramVars structure dyld passes to initializers.
struct program_vars {
    const void *mh;
    int *NXArgcPtr;
    char ***NXArgvPtr;
    char ***environPtr;
    const char **__prognamePtr;
};

static int program_argc;
static char **program_argv;
static char **program_envp;
static const char *program_name;

typedef void (*initializer_fn)(int, char **, char **, char **, const struct program_vars *);

// Providers' image hooks (perry_provider_image_init), found at startup.
static perry_provider_image_fn *image_hooks;
static uint32_t image_hook_count;

static void notify_image_init(perry_image *image) {
    perry_image_info info = { image->header, image->slide, image->path };
    for (uint32_t i = 0; i < image_hook_count; i++)
        image_hooks[i](&info);
}

static void run_image_initializers(perry_loader *loader, perry_image *image, int argc, char **argv,
                                   char **envp, char **apple) {
    if (image->initialized || image->initializing)
        return;
    image->initializing = true;
    for (uint32_t i = 0; i < image->dep_count; i++)
        if (image->deps[i].image)
            run_image_initializers(loader, image->deps[i].image, argc, argv, envp, apple);

    notify_image_init(image);

    struct program_vars vars = {
        image->header, &program_argc, &program_argv, &program_envp, &program_name,
    };
    for (uint32_t s = 0; s < image->segment_count; s++) {
        const perry_segment *seg = &image->segments[s];
        for (uint32_t j = 0; j < seg->nsects; j++) {
            const struct section_64 *sect = &seg->sections[j];
            uint32_t type = sect->flags & SECTION_TYPE;
            if (type == S_MOD_INIT_FUNC_POINTERS) {
                initializer_fn *fns = perry_image_vmaddr(image, sect->addr);
                for (uint64_t k = 0; k < sect->size / sizeof(void *); k++) {
                    perry_trace(PERRY_TRACE_INIT, "initializer %p in %s", (void *)fns[k], image->path);
                    fns[k](argc, argv, envp, apple, &vars);
                }
            } else if (type == S_INIT_FUNC_OFFSETS) {
                const uint32_t *offsets = perry_image_vmaddr(image, sect->addr);
                for (uint64_t k = 0; k < sect->size / sizeof(uint32_t); k++) {
                    initializer_fn fn = (initializer_fn)(void *)(image->base + offsets[k]);
                    perry_trace(PERRY_TRACE_INIT, "initializer %p in %s", (void *)fn, image->path);
                    fn(argc, argv, envp, apple, &vars);
                }
            }
        }
    }
    image->initializing = false;
    image->initialized = true;
}

static perry_loader *startup_loader;

static void *lookup_symbol(const char *install_name, const char *name) {
    return perry_provider_symbol(startup_loader, install_name, name);
}

// Passes the program's arguments and bundle to providers, e.g. for
// _NSGetArgv in libSystem and the main bundle in Foundation.
static void start_providers(perry_loader *loader, perry_image *image) {
    startup_loader = loader;
    perry_startup_info info = {
        .version = PERRY_STARTUP_INFO_VERSION,
        .argc = program_argc,
        .argv = program_argv,
        .envp = program_envp,
        .progname = program_name,
        .executable_path = image->path,
        .bundle_path = loader->bundle_path,
        .main_header = image->header,
        .lookup_symbol = lookup_symbol,
    };
    // Several install names may share one provider; start each library once.
    for (uint32_t i = 0; i < loader->provider_count; i++) {
        void *handle = loader->providers[i]->handle;
        bool seen = !handle;
        for (uint32_t j = 0; j < i && !seen; j++)
            seen = loader->providers[j]->handle == handle;
        if (seen)
            continue;
        perry_provider_startup_fn fn = (perry_provider_startup_fn)dlsym(handle, PERRY_PROVIDER_STARTUP_SYMBOL);
        if (fn)
            fn(&info);
        perry_provider_image_fn hook = (perry_provider_image_fn)dlsym(handle, PERRY_PROVIDER_IMAGE_INIT_SYMBOL);
        if (hook) {
            image_hooks = realloc(image_hooks, sizeof(*image_hooks) * (image_hook_count + 1));
            image_hooks[image_hook_count++] = hook;
        }
    }
}

void perry_run_initializers(perry_loader *loader, perry_image *image, int argc, char **argv, char **envp,
                            char **apple) {
    program_argc = argc;
    program_argv = argv;
    program_envp = envp;
    const char *slash = strrchr(argv[0], '/');
    program_name = slash ? slash + 1 : argv[0];
    start_providers(loader, image);
    // Dependencies first, in load order, then the main executable last.
    for (perry_image *img = loader->images; img; img = img->next)
        if (img != image)
            run_image_initializers(loader, img, argc, argv, envp, apple);
    run_image_initializers(loader, image, argc, argv, envp, apple);
}

void perry_run_main(perry_loader *loader, perry_image *image, int argc, char **argv, char **envp, char **apple) {
    (void)loader;
    if (!image->has_entry)
        perry_fatal("%s: no LC_MAIN entry point", image->path);
    typedef int (*main_fn)(int, char **, char **, char **);
    main_fn entry = (main_fn)(void *)(image->base + image->entryoff);
    perry_trace(PERRY_TRACE_INIT, "calling main at %p", (void *)entry);
    exit(entry(argc, argv, envp, apple));
}
