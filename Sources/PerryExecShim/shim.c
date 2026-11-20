// libPerryExecShim: Linux programs a Mac program starts (Xcode runs its
// compiler through /bin/sh -c) are given this library with LD_PRELOAD, and
// PERRY_LOADER naming perry. When such a program execs or spawns a Mach-O
// file, which Linux can't run, it runs perry with the file and its
// arguments instead: perry <path> <arguments>. Anything else runs as asked.
// The variables stay in the environment, so the programs those start do
// the same.

#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern char **environ;

// Whether `path` is a Mach-O file or a universal one.
static int is_macho(const char *path) {
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return 0;
    uint32_t magic = 0;
    ssize_t count = read(fd, &magic, sizeof magic);
    close(fd);
    if (count != sizeof magic) return 0;
    return magic == 0xfeedface || magic == 0xfeedfacf || magic == 0xcefaedfe || magic == 0xcffaedfe
        || magic == 0xcafebabe || magic == 0xbebafeca;
}

// `name`'s path, searching PATH when it has no slash and `search` is set:
// into `out`, or NULL if none is found.
static const char *resolve(const char *name, int search, char *out, size_t size) {
    if (!search || strchr(name, '/')) return name;
    const char *path = getenv("PATH");
    if (!path) path = "/usr/bin:/bin";
    while (*path) {
        const char *end = strchr(path, ':');
        size_t length = end ? (size_t)(end - path) : strlen(path);
        if (length + strlen(name) + 2 <= size) {
            memcpy(out, path, length);
            out[length] = '/';
            strcpy(out + length + 1, name);
            if (access(out, X_OK) == 0) return out;
        }
        if (!end) break;
        path = end + 1;
    }
    return NULL;
}

// perry's arguments to run `path` with `argv`'s arguments after the first,
// or NULL when `path` isn't a Mach-O file or perry isn't known.
static char **loader_arguments(const char *path, char *const argv[]) {
    const char *loader = getenv("PERRY_LOADER");
    if (!loader || !*loader || !path || !is_macho(path)) return NULL;
    size_t count = 0;
    while (argv && argv[count]) count++;
    char **arguments = calloc(count + 3, sizeof *arguments);
    if (!arguments) return NULL;
    arguments[0] = (char *)loader;
    arguments[1] = (char *)path;
    for (size_t index = 1; index < count; index++) arguments[index + 1] = argv[index];
    return arguments;
}

typedef int (*execve_function)(const char *, char *const[], char *const[]);
typedef int (*spawn_function)(pid_t *, const char *, const posix_spawn_file_actions_t *, const posix_spawnattr_t *,
                              char *const[], char *const[]);

static int real_execve(const char *path, char *const argv[], char *const envp[]) {
    static execve_function real;
    if (!real) real = (execve_function)dlsym(RTLD_NEXT, "execve");
    return real(path, argv, envp);
}

static int run(const char *name, char *const argv[], char *const envp[], int search) {
    char found[4096];
    const char *path = resolve(name, search, found, sizeof found);
    if (!path) {
        errno = ENOENT;
        return -1;
    }
    char **arguments = loader_arguments(path, argv);
    if (arguments) {
        real_execve(arguments[0], arguments, envp);
        int error = errno;
        free(arguments);
        errno = error;
        return -1;
    }
    return real_execve(path, argv, envp);
}

int execve(const char *path, char *const argv[], char *const envp[]) { return run(path, argv, envp, 0); }
int execv(const char *path, char *const argv[]) { return run(path, argv, environ, 0); }
int execvp(const char *file, char *const argv[]) { return run(file, argv, environ, 1); }
int execvpe(const char *file, char *const argv[], char *const envp[]) { return run(file, argv, envp, 1); }

static int spawn(const char *symbol, pid_t *pid, const char *name, const posix_spawn_file_actions_t *actions,
                 const posix_spawnattr_t *attributes, char *const argv[], char *const envp[], int search) {
    spawn_function real = (spawn_function)dlsym(RTLD_NEXT, symbol);
    char found[4096];
    const char *path = resolve(name, search, found, sizeof found);
    char **arguments = path ? loader_arguments(path, argv) : NULL;
    if (!arguments) return real(pid, name, actions, attributes, argv, envp);
    spawn_function spawn = (spawn_function)dlsym(RTLD_NEXT, "posix_spawn");
    int status = spawn(pid, arguments[0], actions, attributes, arguments, envp);
    free(arguments);
    return status;
}

int posix_spawn(pid_t *pid, const char *path, const posix_spawn_file_actions_t *actions, const posix_spawnattr_t *attributes,
                char *const argv[], char *const envp[]) {
    return spawn("posix_spawn", pid, path, actions, attributes, argv, envp, 0);
}

int posix_spawnp(pid_t *pid, const char *file, const posix_spawn_file_actions_t *actions, const posix_spawnattr_t *attributes,
                 char *const argv[], char *const envp[]) {
    return spawn("posix_spawnp", pid, file, actions, attributes, argv, envp, 1);
}
