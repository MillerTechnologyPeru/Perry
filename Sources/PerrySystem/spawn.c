// posix_spawn and its file actions and attributes. Darwin's
// posix_spawn_file_actions_t and posix_spawnattr_t are a pointer each, to
// an object the init functions make; here that object is glibc's. The
// flags both systems have (reset IDs, set the process group, set signals'
// defaults, set the signal mask) are kept, Darwin's own (set exec, start
// suspended, close on exec by default) are not, and signal sets are
// renumbered. A Mac program to spawn, or to exec, runs under Perry, as
// this one does.

#define _GNU_SOURCE
#include "PerrySystem.h"

#include <errno.h>
#include <signal.h>
#include <spawn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>

int perry_signal_to_linux(int signal);
int perry_open_flags_to_linux(int flags);

static void sigset_from_darwin(sigset_t *set, const uint32_t *darwin) {
    sigemptyset(set);
    if (!darwin) return;
    for (int signal = 1; signal <= 31; signal++)
        if (*darwin & (1u << (signal - 1)) && perry_signal_to_linux(signal) > 0)
            sigaddset(set, perry_signal_to_linux(signal));
}

// MARK: - File actions

int darwin_posix_spawn_file_actions_init(void **actions) DARWIN_SYMBOL(posix_spawn_file_actions_init);
int darwin_posix_spawn_file_actions_init(void **actions) {
    posix_spawn_file_actions_t *made = malloc(sizeof *made);
    if (!made) return ENOMEM;
    int status = posix_spawn_file_actions_init(made);
    if (status) {
        free(made);
        return status;
    }
    *actions = made;
    return 0;
}

int darwin_posix_spawn_file_actions_destroy(void **actions) DARWIN_SYMBOL(posix_spawn_file_actions_destroy);
int darwin_posix_spawn_file_actions_destroy(void **actions) {
    if (!actions || !*actions) return EINVAL;
    posix_spawn_file_actions_destroy(*actions);
    free(*actions);
    *actions = NULL;
    return 0;
}

int darwin_posix_spawn_file_actions_adddup2(void **actions, int fd, int target) DARWIN_SYMBOL(posix_spawn_file_actions_adddup2);
int darwin_posix_spawn_file_actions_adddup2(void **actions, int fd, int target) {
    return actions && *actions ? posix_spawn_file_actions_adddup2(*actions, fd, target) : EINVAL;
}

int darwin_posix_spawn_file_actions_addclose(void **actions, int fd) DARWIN_SYMBOL(posix_spawn_file_actions_addclose);
int darwin_posix_spawn_file_actions_addclose(void **actions, int fd) {
    return actions && *actions ? posix_spawn_file_actions_addclose(*actions, fd) : EINVAL;
}

int darwin_posix_spawn_file_actions_addopen(void **actions, int fd, const char *path, int flags, mode_t mode)
    DARWIN_SYMBOL(posix_spawn_file_actions_addopen);
int darwin_posix_spawn_file_actions_addopen(void **actions, int fd, const char *path, int flags, mode_t mode) {
    return actions && *actions ? posix_spawn_file_actions_addopen(*actions, fd, path, perry_open_flags_to_linux(flags), mode) : EINVAL;
}

int darwin_posix_spawn_file_actions_addinherit_np(void **actions, int fd) DARWIN_SYMBOL(posix_spawn_file_actions_addinherit_np);
int darwin_posix_spawn_file_actions_addinherit_np(void **actions, int fd) {
    (void)actions; (void)fd;
    return 0;   // descriptors are inherited unless closed on exec
}

// MARK: - Attributes

int darwin_posix_spawnattr_init(void **attributes) DARWIN_SYMBOL(posix_spawnattr_init);
int darwin_posix_spawnattr_init(void **attributes) {
    posix_spawnattr_t *made = malloc(sizeof *made);
    if (!made) return ENOMEM;
    int status = posix_spawnattr_init(made);
    if (status) {
        free(made);
        return status;
    }
    *attributes = made;
    return 0;
}

int darwin_posix_spawnattr_destroy(void **attributes) DARWIN_SYMBOL(posix_spawnattr_destroy);
int darwin_posix_spawnattr_destroy(void **attributes) {
    if (!attributes || !*attributes) return EINVAL;
    posix_spawnattr_destroy(*attributes);
    free(*attributes);
    *attributes = NULL;
    return 0;
}

// POSIX_SPAWN_RESETIDS 1, SETPGROUP 2, SETSIGDEF 4, SETSIGMASK 8 are both
// systems'; Darwin's higher bits (SETEXEC, START_SUSPENDED, CLOEXEC_DEFAULT)
// are its own.
int darwin_posix_spawnattr_setflags(void **attributes, short flags) DARWIN_SYMBOL(posix_spawnattr_setflags);
int darwin_posix_spawnattr_setflags(void **attributes, short flags) {
    return attributes && *attributes ? posix_spawnattr_setflags(*attributes, (short)(flags & 0x0f)) : EINVAL;
}

int darwin_posix_spawnattr_getflags(void **attributes, short *flags) DARWIN_SYMBOL(posix_spawnattr_getflags);
int darwin_posix_spawnattr_getflags(void **attributes, short *flags) {
    return attributes && *attributes ? posix_spawnattr_getflags(*attributes, flags) : EINVAL;
}

int darwin_posix_spawnattr_setpgroup(void **attributes, pid_t group) DARWIN_SYMBOL(posix_spawnattr_setpgroup);
int darwin_posix_spawnattr_setpgroup(void **attributes, pid_t group) {
    return attributes && *attributes ? posix_spawnattr_setpgroup(*attributes, group) : EINVAL;
}

int darwin_posix_spawnattr_setsigmask(void **attributes, const uint32_t *mask) DARWIN_SYMBOL(posix_spawnattr_setsigmask);
int darwin_posix_spawnattr_setsigmask(void **attributes, const uint32_t *mask) {
    if (!attributes || !*attributes) return EINVAL;
    sigset_t set;
    sigset_from_darwin(&set, mask);
    return posix_spawnattr_setsigmask(*attributes, &set);
}

int darwin_posix_spawnattr_setsigdefault(void **attributes, const uint32_t *signals) DARWIN_SYMBOL(posix_spawnattr_setsigdefault);
int darwin_posix_spawnattr_setsigdefault(void **attributes, const uint32_t *signals) {
    if (!attributes || !*attributes) return EINVAL;
    sigset_t set;
    sigset_from_darwin(&set, signals);
    return posix_spawnattr_setsigdefault(*attributes, &set);
}

// Which processor types a child may run: one, here.
int darwin_posix_spawnattr_setbinpref_np(void **attributes, size_t count, const int *types, size_t *copied)
    DARWIN_SYMBOL(posix_spawnattr_setbinpref_np);
int darwin_posix_spawnattr_setbinpref_np(void **attributes, size_t count, const int *types, size_t *copied) {
    (void)attributes; (void)types;
    if (copied) *copied = count;
    return 0;
}

// MARK: - Spawning

// Whether the file at `path` is a Mach-O executable (thin or universal).
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

// The program's path for `name`, searching PATH when it has no slash.
static char *resolve(const char *name, int search) {
    if (!search || strchr(name, '/')) return strdup(name);
    const char *path = getenv("PATH");
    if (!path) path = "/usr/bin:/bin";
    char *copy = strdup(path), *saved = NULL;
    for (char *dir = strtok_r(copy, ":", &saved); dir; dir = strtok_r(NULL, ":", &saved)) {
        size_t length = strlen(dir) + strlen(name) + 2;
        char *candidate = malloc(length);
        snprintf(candidate, length, "%s/%s", dir, name);
        if (access(candidate, X_OK) == 0) {
            free(copy);
            return candidate;
        }
        free(candidate);
    }
    free(copy);
    return strdup(name);
}

// Perry's own path, and an argument list that has it run `path` with
// `argv`'s arguments after the first: perry <path> <arguments>.
static char **loader_arguments(const char *path, char *const argv[], char *loader, size_t size) {
    ssize_t length = readlink("/proc/self/exe", loader, size - 1);
    if (length <= 0) return NULL;
    loader[length] = 0;
    size_t count = 0;
    while (argv && argv[count]) count++;
    char **arguments = calloc(count + 3, sizeof *arguments);
    if (!arguments) return NULL;
    arguments[0] = loader;
    arguments[1] = (char *)path;
    for (size_t index = 1; index < count; index++) arguments[index + 1] = argv[index];
    return arguments;
}

static int spawn(pid_t *pid, const char *name, void **actions, void **attributes, char *const argv[], char *const envp[], int search) {
    char *path = resolve(name, search);
    int status;
    if (is_macho(path)) {
        // Perry itself runs it: perry <path> <its arguments>.
        char loader[4096];
        char **arguments = loader_arguments(path, argv, loader, sizeof loader);
        if (!arguments) {
            free(path);
            return ENOEXEC;
        }
        status = posix_spawn(pid, loader, actions ? *actions : NULL, attributes ? *attributes : NULL, arguments, envp);
        free(arguments);
    } else {
        status = posix_spawn(pid, path, actions ? *actions : NULL, attributes ? *attributes : NULL, argv, envp);
    }
    free(path);
    return status;
}

int darwin_posix_spawn(pid_t *pid, const char *path, void **actions, void **attributes, char *const argv[], char *const envp[])
    DARWIN_SYMBOL(posix_spawn);
int darwin_posix_spawn(pid_t *pid, const char *path, void **actions, void **attributes, char *const argv[], char *const envp[]) {
    return spawn(pid, path, actions, attributes, argv, envp, 0);
}

int darwin_posix_spawnp(pid_t *pid, const char *file, void **actions, void **attributes, char *const argv[], char *const envp[])
    DARWIN_SYMBOL(posix_spawnp);
int darwin_posix_spawnp(pid_t *pid, const char *file, void **actions, void **attributes, char *const argv[], char *const envp[]) {
    return spawn(pid, file, actions, attributes, argv, envp, 1);
}

// MARK: - Exec

extern char **environ;

// The exec family: a Mac program replaces this one with Perry running it
// (Xcode's gcc driver runs the compiler for the architecture this way);
// anything else, as the system execs it.
static int exec(const char *name, char *const argv[], char *const envp[], int search) {
    char *path = resolve(name, search);
    if (is_macho(path)) {
        char loader[4096];
        char **arguments = loader_arguments(path, argv, loader, sizeof loader);
        if (!arguments) {
            free(path);
            errno = ENOEXEC;
            return -1;
        }
        execve(loader, arguments, envp);
        int error = errno;
        free(arguments);
        free(path);
        errno = error;
        return -1;
    }
    execve(path, argv, envp);
    int error = errno;
    // A file found on PATH that isn't a program at all is run by the shell,
    // as execvp does.
    if (search && error == ENOEXEC) execvp(name, argv);
    free(path);
    errno = error;
    return -1;
}

int darwin_execv(const char *path, char *const argv[]) DARWIN_SYMBOL(execv);
int darwin_execv(const char *path, char *const argv[]) { return exec(path, argv, environ, 0); }

int darwin_execve(const char *path, char *const argv[], char *const envp[]) DARWIN_SYMBOL(execve);
int darwin_execve(const char *path, char *const argv[], char *const envp[]) { return exec(path, argv, envp, 0); }

int darwin_execvp(const char *file, char *const argv[]) DARWIN_SYMBOL(execvp);
int darwin_execvp(const char *file, char *const argv[]) { return exec(file, argv, environ, 1); }
