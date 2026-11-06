#define _GNU_SOURCE
#include "bundle.h"
#include "log.h"

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

static bool is_directory(const char *path) {
    struct stat st;
    return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

static bool is_file(const char *path) {
    struct stat st;
    return stat(path, &st) == 0 && S_ISREG(st.st_mode);
}

bool perry_bundle_open(const char *path, perry_bundle *bundle) {
    memset(bundle, 0, sizeof(*bundle));
    if (!is_directory(path))
        return false;

    char root[PATH_MAX];
    if (!realpath(path, root))
        perry_fatal("%s: cannot resolve bundle path", path);

    // iOS bundles keep Info.plist and the executable at the top level;
    // macOS bundles keep them under Contents/. perry32 runs only iOS apps.
    char plist_path[PATH_MAX + 32], exe_dir[PATH_MAX + 32];
    snprintf(plist_path, sizeof(plist_path), "%s/Info.plist", root);
    snprintf(exe_dir, sizeof(exe_dir), "%s", root);
    if (!is_file(plist_path)) {
#if defined(__arm__)
        perry_fatal("%s: directory is not an iOS bundle (no Info.plist)", path);
#else
        snprintf(plist_path, sizeof(plist_path), "%s/Contents/Info.plist", root);
        snprintf(exe_dir, sizeof(exe_dir), "%s/Contents/MacOS", root);
        if (!is_file(plist_path))
            perry_fatal("%s: directory is not a bundle (no Info.plist)", path);
#endif
    }

    const char *error = NULL;
    perry_plist *info = perry_plist_load(plist_path, &error);
    if (!info || info->type != PERRY_PLIST_DICT)
        perry_fatal("%s: cannot read Info.plist: %s", path, error ? error : "root is not a dictionary");

    const char *exe = perry_plist_get_string(info, "CFBundleExecutable");
    char fallback[PATH_MAX];
    if (!exe) {
        // Fall back to the bundle name without its extension.
        const char *base = strrchr(root, '/');
        snprintf(fallback, sizeof(fallback), "%s", base ? base + 1 : root);
        char *dot = strrchr(fallback, '.');
        if (dot)
            *dot = 0;
        exe = fallback;
        perry_warn("%s: Info.plist has no CFBundleExecutable, trying %s", path, exe);
    }
    if (strchr(exe, '/'))
        perry_fatal("%s: invalid CFBundleExecutable \"%s\"", path, exe);

    char exe_path[PATH_MAX * 2];
    snprintf(exe_path, sizeof(exe_path), "%s/%s", exe_dir, exe);
    if (!is_file(exe_path))
        perry_fatal("%s: bundle executable %s not found", path, exe_path);

    bundle->path = strdup(root);
    bundle->executable_path = strdup(exe_path);
    const char *identifier = perry_plist_get_string(info, "CFBundleIdentifier");
    bundle->identifier = identifier ? strdup(identifier) : NULL;
    bundle->info = info;
    return true;
}

void perry_bundle_close(perry_bundle *bundle) {
    free(bundle->path);
    free(bundle->executable_path);
    free(bundle->identifier);
    perry_plist_free(bundle->info);
    memset(bundle, 0, sizeof(*bundle));
}
