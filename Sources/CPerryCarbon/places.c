// Where a program and its files are: its main bundle and executable, the
// home's file system its startup volume's space is counted on, and the
// discs mounted after it. The File Manager's C and Swift both ask these.

#include "PerryCarbon.h"

#include <dlfcn.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

static const char *bundle_string(const char *selector) {
    id path = ((id (*)(id, SEL))objc_send)(SEND(CLASS("NSBundle"), "mainBundle"), objc_selector(selector));
    return path ? ((const char *(*)(id, SEL))objc_send)(path, SELECTOR("UTF8String")) : NULL;
}

const char *carbon_bundle_path(void) {
    static char path[PATH_MAX];
    if (!path[0]) {
        const char *bundle = bundle_string("bundlePath");
        if (!bundle || snprintf(path, sizeof path, "%s", bundle) >= (int)sizeof path) return NULL;
    }
    return path;
}

const char *carbon_executable_path(void) {
    static char path[PATH_MAX];
    if (!path[0]) {
        const char *executable = bundle_string("executablePath");
        if (!executable || snprintf(path, sizeof path, "%s", executable) >= (int)sizeof path) return NULL;
    }
    return path;
}

// The discs mounted are volumes after the first, numbered -101 and down, as
// CoreServices' FSGetVolumeInfo numbers them: libPerrySystem finds them, for
// getmntinfo, and its perry_disc_volume is found in that library as it is
// loaded here (by its path, from this process's mappings).
int carbon_disc_volume(int index, char *name, size_t name_size, char *mount, size_t mount_size) {
    static int (*volume)(int, char *, size_t, char *, size_t);
    static bool looked, looked_in_maps;
    if (!looked) {
        looked = true;
        // Through the loader, which has the library open; opening it again
        // by its path finds nothing under box86, and a program saw no disc.
        volume = (int (*)(int, char *, size_t, char *, size_t))carbon_function("/usr/lib/libSystem.B.dylib", "perry_disc_volume");
    }
    if (!looked_in_maps && !volume) {
        looked_in_maps = true;
        FILE *maps = fopen("/proc/self/maps", "r");
        char line[4096];
        while (maps && fgets(line, sizeof line, maps)) {
            char *path = strchr(line, '/');
            size_t length = path ? strcspn(path, "\n") : 0;
            static const char library[] = "/libPerrySystem.so";
            if (length < sizeof library - 1 || strncmp(path + length - (sizeof library - 1), library, sizeof library - 1) != 0)
                continue;
            path[length] = '\0';
            void *handle = dlopen(path, RTLD_NOW | RTLD_NOLOAD);
            if (handle) volume = (int (*)(int, char *, size_t, char *, size_t))dlsym(handle, "perry_disc_volume");
            break;
        }
        if (maps) fclose(maps);
    }
    return volume ? volume(index, name, name_size, mount, mount_size) : 0;
}

/// The file system the program's home folder is on, which is where it
/// writes. The root may be another, with no room at all (a read-only system
/// image, as ROCKNIX's is), and a program that checks for room before it
/// starts would stop.
const char *carbon_startup_volume_path(void) {
    static char home[PATH_MAX];
    if (!home[0]) {
        id (*home_directory)(void) = (id (*)(void))carbon_function(
            "/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation", "_NSHomeDirectory");
        id folder = home_directory ? home_directory() : NULL;
        const char *path = folder ? ((const char *(*)(id, SEL))objc_send)(folder, SELECTOR("UTF8String")) : NULL;
        struct stat info;
        snprintf(home, sizeof home, "%s", path && stat(path, &info) == 0 ? path : "/");
    }
    return home;
}
