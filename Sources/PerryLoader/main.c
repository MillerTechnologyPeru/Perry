// perry: runs arm64 iOS and macOS Mach-O binaries on arm64 Linux.

#define _GNU_SOURCE
#include "bundle.h"
#include "image.h"
#include "log.h"

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

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

// An app's container, as iOS gives each app: its home directory, with
// Documents, Library (Caches, Preferences) and tmp, which HOME and TMPDIR
// name while it runs.
static void enter_container(const perry_bundle *bundle) {
    const char *container = getenv("PERRY_CONTAINER");
    char path[PATH_MAX];
    if (!container) {
        const char *home = getenv("HOME");
        snprintf(path, sizeof(path), "%s/.perry/Containers/%s", home ? home : "/tmp", bundle->identifier);
        container = path;
    }
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
          "                      unless set\n",
          out);
}

int main(int argc, char **argv) {
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
