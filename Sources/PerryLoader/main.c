// perry: runs arm64 iOS and macOS Mach-O binaries on arm64 Linux, and, built
// as a 32-bit program (perry32), armv7 iOS binaries on a kernel that runs
// 32-bit ARM programs.

#define _GNU_SOURCE
#include "bundle.h"
#include "image.h"
#include "log.h"

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/personality.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <unistd.h>

extern char **environ;

// Makes a directory and its parents, as mkdir -p does.
static void make_directories(const char *path) {
    char partial[PATH_MAX];
    snprintf(partial, sizeof(partial), "%s", path);
    for (char *slash = partial + 1; *slash; slash++) {
        if (*slash != '/')
            continue;
        *slash = 0;
        mkdir(partial, 0755);
        *slash = '/';
    }
    if (mkdir(partial, 0755) != 0 && errno != EEXIST)
        perry_fatal("cannot make %s", path);
}

// A directory of the container kept elsewhere, as a port keeps its saves
// beside it: `name` in the container links to `variable`'s directory, made
// if missing. An empty directory already there is replaced; one with files
// in it is left, and the setting ignored, so nothing is lost.
static void redirect(const char *container, const char *name, const char *variable) {
    const char *target = getenv(variable);
    if (!target || !*target)
        return;
    make_directories(target);
    char link[PATH_MAX];
    snprintf(link, sizeof(link), "%s/%s", container, name);
    char parent[PATH_MAX];
    snprintf(parent, sizeof(parent), "%s", link);
    char *slash = strrchr(parent, '/');
    if (slash) {
        *slash = 0;
        make_directories(parent);
    }
    struct stat status;
    if (lstat(link, &status) == 0) {
        if (S_ISLNK(status.st_mode)) {
            unlink(link);
        } else if (!S_ISDIR(status.st_mode) || rmdir(link) != 0) {
            fprintf(stderr, "perry: %s has files in it, so %s is not used\n", link, variable);
            return;
        }
    }
    if (symlink(target, link) != 0)
        fprintf(stderr, "perry: cannot link %s to %s: %s\n", link, target, strerror(errno));
}

// An app's container, as iOS gives each app: its home directory, with
// Documents, Library (Caches, Preferences) and tmp, which HOME and TMPDIR
// name while it runs. PERRY_DOCUMENTS, PERRY_LIBRARY, PERRY_CACHES,
// PERRY_PREFERENCES and PERRY_TMP put those directories elsewhere.
static void enter_container(const perry_bundle *bundle) {
    const char *container = getenv("PERRY_CONTAINER");
    char path[PATH_MAX];
    if (!container) {
        const char *home = getenv("HOME");
        snprintf(path, sizeof(path), "%s/.perry/Containers/%s", home ? home : "/tmp", bundle->identifier);
        container = path;
    }
    make_directories(container);
    redirect(container, "Documents", "PERRY_DOCUMENTS");
    redirect(container, "Library", "PERRY_LIBRARY");
    redirect(container, "Library/Caches", "PERRY_CACHES");
    redirect(container, "Library/Preferences", "PERRY_PREFERENCES");
    redirect(container, "tmp", "PERRY_TMP");
    const char *directories[] = { "Documents", "Library/Caches", "Library/Preferences", "tmp" };
    for (size_t index = 0; index < sizeof(directories) / sizeof(directories[0]); index++) {
        char directory[PATH_MAX];
        snprintf(directory, sizeof(directory), "%s/%s", container, directories[index]);
        make_directories(directory);
    }
    char tmp[PATH_MAX];
    snprintf(tmp, sizeof(tmp), "%s/tmp/", container);
    setenv("HOME", container, 1);
    setenv("TMPDIR", tmp, 1);
}

static void usage(FILE *out) {
    fputs("usage: perry [options] <executable | App.app> [arguments...]\n"
          "\n"
          "options:\n"
          "  --report    load and bind without running; print imports, missing\n"
          "              symbols and Objective-C references\n"
          "  --strict    fail when a non-weak import cannot be resolved\n"
          "  -h, --help  show this help\n"
          "\n"
          "environment:\n"
          "  PERRY_TRACE         comma-separated: load, bind, init, all\n"
          "  PERRY_LIBRARY_PATH  colon-separated directories with provider libraries\n"
          "  PERRY_CONTAINER     an app's home directory; ~/.perry/Containers/<bundle id>\n"
          "                      unless set\n"
          "  PERRY_DOCUMENTS, PERRY_LIBRARY, PERRY_CACHES, PERRY_PREFERENCES, PERRY_TMP\n"
          "                      directories to keep the container's Documents,\n"
          "                      Library, Library/Caches, Library/Preferences and tmp\n"
          "                      in instead, as a port keeps saves beside it\n",
          out);
}

#if defined(__LP64__)
// Darwin's runtimes keep pointers in 47 bits: libobjc's class_rw/ro data
// pointers, which Swift's runtime masks with 0x7ffffffffff8, for one. Its
// heap is there, but arm64 Linux maps memory from the top of its 48-bit
// address space down, and puts the brk heap above 2^47 too. The legacy
// layout maps from a quarter of the address space (2^46) up instead: the
// kernel takes it with ADDR_COMPAT_LAYOUT, which container seccomp profiles
// often refuse, or an unlimited stack, and both only for a new program, so
// perry runs itself again. The brk heap then gets a page placed above it,
// so that glibc's malloc grows its main arena by mapping memory instead.
static bool maps_low(void) {
    void *probe = mmap(NULL, 4096, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (probe == MAP_FAILED)
        return false;
    munmap(probe, 4096);
    return (uintptr_t)probe < (1ull << 47);
}

static void use_low_addresses(char **argv) {
    const uint64_t limit = 1ull << 47;
    bool low = maps_low();
    if (!low && !getenv("PERRY_REEXECUTED")) {
        int persona = personality(0xffffffff);
        bool changed = persona != -1 && personality((unsigned long)persona | ADDR_COMPAT_LAYOUT) != -1;
        struct rlimit stack;
        if (!changed && getrlimit(RLIMIT_STACK, &stack) == 0 && stack.rlim_max == RLIM_INFINITY) {
            stack.rlim_cur = RLIM_INFINITY;
            changed = setrlimit(RLIMIT_STACK, &stack) == 0;
        }
        if (changed) {
            // By its own path, so that it keeps its name.
            char self[PATH_MAX];
            ssize_t length = readlink("/proc/self/exe", self, sizeof(self) - 1);
            if (length > 0) {
                self[length] = 0;
                setenv("PERRY_REEXECUTED", "1", 1);
                execv(self, argv);
            }
        }
    }
    unsetenv("PERRY_REEXECUTED");
    if (!low && !maps_low())
        perry_warn("memory is mapped above 2^47, where Darwin's runtimes cannot use it");

    uintptr_t page = (uintptr_t)sysconf(_SC_PAGESIZE);
    uintptr_t top = ((uintptr_t)sbrk(0) + page - 1) & ~(page - 1);
    if (top >= limit)
        mmap((void *)top, page, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE, -1, 0);
}

#else
// A 32-bit process has no address space above 4 GB to avoid.
static void use_low_addresses(char **argv) { (void)argv; }
#endif

#if defined(__LP64__)
// A program with no arm64 code but armv7 code is run by perry32, the same
// loader built as a 32-bit program, which maps armv7 Mach-O beside 32-bit
// providers: one process cannot hold both. It is found beside this program,
// or at PERRY32.
static void run_in_32_bit_loader(const char *executable, char **argv) {
    unsigned archs = perry_macho_architectures(executable);
    if (!(archs & PERRY_ARCH_ARMV7) || (archs & PERRY_ARCH_ARM64))
        return;
    const char *named = getenv("PERRY32");
    char self[PATH_MAX], sibling[PATH_MAX + 16];
    const char *path = named;
    if (!path) {
        ssize_t length = readlink("/proc/self/exe", self, sizeof(self) - 1);
        if (length > 0) {
            self[length] = 0;
            char *slash = strrchr(self, '/');
            if (slash)
                *slash = 0;
            snprintf(sibling, sizeof(sibling), "%s/perry32", self);
            path = sibling;
        }
    }
    if (!path || access(path, X_OK) != 0)
        perry_fatal("%s is an armv7 program, which perry32 runs, and it was not found%s", executable,
                    path ? "" : " (set PERRY32)");
    execv(path, argv);
    perry_fatal("cannot run %s: %s", path, strerror(errno));
}
#endif

int main(int argc, char **argv) {
    use_low_addresses(argv);
    perry_log_init();

    bool report = false, strict = false;
    int i = 1;
    for (; i < argc && argv[i][0] == '-'; i++) {
        if (strcmp(argv[i], "--report") == 0)
            report = true;
        else if (strcmp(argv[i], "--strict") == 0)
            strict = true;
        else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            usage(stdout);
            return 0;
        } else if (strcmp(argv[i], "--") == 0) {
            i++;
            break;
        } else {
            fprintf(stderr, "perry: unknown option %s\n", argv[i]);
            usage(stderr);
            return 2;
        }
    }
    if (i >= argc) {
        usage(stderr);
        return 2;
    }

    const char *target = argv[i];
    perry_bundle bundle;
    bool has_bundle = perry_bundle_open(target, &bundle);
    char resolved[PATH_MAX];
    const char *executable = has_bundle ? bundle.executable_path
                           : (realpath(target, resolved) ? resolved : target);

#if defined(__LP64__)
    run_in_32_bit_loader(executable, argv);
#endif

    perry_loader loader;
    perry_loader_init(&loader);
    loader.report = report;
    loader.strict = strict;
    loader.bundle_path = has_bundle ? bundle.path : NULL;

    perry_image *image = perry_load_executable(&loader, executable);

    if (report) {
        if (has_bundle)
            printf("bundle\t%s\t%s\n", bundle.path, bundle.identifier ? bundle.identifier : "-");
        perry_print_report(&loader);
        return 0;
    }

    if (has_bundle && bundle.identifier)
        enter_container(&bundle);

    // The program sees its own path as argv[0], as it would under dyld.
    int app_argc = argc - i;
    char **app_argv = calloc((size_t)app_argc + 1, sizeof(char *));
    app_argv[0] = (char *)executable;
    for (int k = 1; k < app_argc; k++)
        app_argv[k] = argv[i + k];

    char *apple_exe = NULL;
    if (asprintf(&apple_exe, "executable_path=%s", executable) < 0)
        perry_fatal("out of memory");
    char *apple[] = { apple_exe, NULL };

    perry_run_initializers(&loader, image, app_argc, app_argv, environ, apple);
    perry_run_main(&loader, image, app_argc, app_argv, environ, apple);
}
