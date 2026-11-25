// removefile(3): removing a file, or a directory and all it holds, with the
// callbacks a state object carries, and the overwriting passes Darwin can
// make over a file's contents before it goes. Over openat, fstatat and
// unlinkat: a directory is walked depth first through descriptors, so a
// path's length doesn't matter (REMOVEFILE_ALLOW_LONG_PATHS asks for
// nothing more) and the working directory is never changed. Links are
// removed, never followed. The *64 forms of the calls are used, so that on
// 32-bit systems a large file or a 64-bit inode number is no EOVERFLOW.

#define _GNU_SOURCE
#include "PerrySystem.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

enum {
    REMOVEFILE_RECURSIVE = 1 << 0,
    REMOVEFILE_KEEP_PARENT = 1 << 1,
    REMOVEFILE_SECURE_7_PASS = 1 << 2,
    REMOVEFILE_SECURE_35_PASS = 1 << 3,
    REMOVEFILE_SECURE_1_PASS = 1 << 4,
    REMOVEFILE_SECURE_3_PASS = 1 << 5,
    REMOVEFILE_SECURE_1_PASS_ZERO = 1 << 6,
    REMOVEFILE_CROSS_MOUNT = 1 << 7,
    REMOVEFILE_ALLOW_LONG_PATHS = 1 << 8,
    REMOVEFILE_CLEAR_PURGEABLE = 1 << 9,
    REMOVEFILE_SYSTEM_DISCARDED = 1 << 10,
    REMOVEFILE_RECURSIVE_SLIM = 1 << 11,
    REMOVEFILE_SECURE = REMOVEFILE_SECURE_7_PASS | REMOVEFILE_SECURE_35_PASS | REMOVEFILE_SECURE_1_PASS |
                        REMOVEFILE_SECURE_3_PASS | REMOVEFILE_SECURE_1_PASS_ZERO,

    REMOVEFILE_STATE_CONFIRM_CALLBACK = 1,
    REMOVEFILE_STATE_CONFIRM_CONTEXT = 2,
    REMOVEFILE_STATE_ERROR_CALLBACK = 3,
    REMOVEFILE_STATE_ERROR_CONTEXT = 4,
    REMOVEFILE_STATE_ERRNO = 5,
    REMOVEFILE_STATE_STATUS_CALLBACK = 6,
    REMOVEFILE_STATE_STATUS_CONTEXT = 7,
    REMOVEFILE_STATE_FTSENT = 8,

    REMOVEFILE_PROCEED = 0,
    REMOVEFILE_SKIP = 1,
    REMOVEFILE_STOP = 2,

    DARWIN_AT_FDCWD = -2,
};

struct darwin_removefile_state;
typedef int (*removefile_callback)(struct darwin_removefile_state *state, const char *path, void *context);

// The state is Perry's own; Darwin's is opaque too. `error` is in Darwin's
// numbering, as a callback reads it.
struct darwin_removefile_state {
    removefile_callback confirm, error_callback, status;
    void *confirm_context, *error_context, *status_context;
    int error;
    _Atomic bool cancelled;
};

struct darwin_removefile_state *darwin_removefile_state_alloc(void) DARWIN_SYMBOL(removefile_state_alloc);
struct darwin_removefile_state *darwin_removefile_state_alloc(void) {
    struct darwin_removefile_state *state = calloc(1, sizeof(*state));
    if (!state)
        errno = ENOMEM;
    return state;
}

int darwin_removefile_state_free(struct darwin_removefile_state *state) DARWIN_SYMBOL(removefile_state_free);
int darwin_removefile_state_free(struct darwin_removefile_state *state) {
    free(state);
    return 0;
}

// A callback is a function pointer, a context a pointer, the error an int.
// There is no FTSENT to give (the walk isn't fts's): it reads as NULL, and
// can't be set.
int darwin_removefile_state_get(struct darwin_removefile_state *state, uint32_t key, void *out) DARWIN_SYMBOL(removefile_state_get);
int darwin_removefile_state_get(struct darwin_removefile_state *state, uint32_t key, void *out) {
    if (!state || !out) {
        errno = EINVAL;
        return -1;
    }
    switch (key) {
    case REMOVEFILE_STATE_CONFIRM_CALLBACK: *(removefile_callback *)out = state->confirm; break;
    case REMOVEFILE_STATE_CONFIRM_CONTEXT: *(void **)out = state->confirm_context; break;
    case REMOVEFILE_STATE_ERROR_CALLBACK: *(removefile_callback *)out = state->error_callback; break;
    case REMOVEFILE_STATE_ERROR_CONTEXT: *(void **)out = state->error_context; break;
    case REMOVEFILE_STATE_ERRNO: *(int *)out = state->error; break;
    case REMOVEFILE_STATE_STATUS_CALLBACK: *(removefile_callback *)out = state->status; break;
    case REMOVEFILE_STATE_STATUS_CONTEXT: *(void **)out = state->status_context; break;
    case REMOVEFILE_STATE_FTSENT: *(void **)out = NULL; break;
    default:
        errno = EINVAL;
        return -1;
    }
    return 0;
}

// The value is the callback or context itself (removefile_state_set(s,
// REMOVEFILE_STATE_CONFIRM_CALLBACK, function)), and for the error a pointer
// to it.
int darwin_removefile_state_set(struct darwin_removefile_state *state, uint32_t key, const void *value)
    DARWIN_SYMBOL(removefile_state_set);
int darwin_removefile_state_set(struct darwin_removefile_state *state, uint32_t key, const void *value) {
    if (!state) {
        errno = EINVAL;
        return -1;
    }
    switch (key) {
    case REMOVEFILE_STATE_CONFIRM_CALLBACK: state->confirm = (removefile_callback)value; break;
    case REMOVEFILE_STATE_CONFIRM_CONTEXT: state->confirm_context = (void *)value; break;
    case REMOVEFILE_STATE_ERROR_CALLBACK: state->error_callback = (removefile_callback)value; break;
    case REMOVEFILE_STATE_ERROR_CONTEXT: state->error_context = (void *)value; break;
    case REMOVEFILE_STATE_ERRNO:
        if (!value) {
            errno = EINVAL;
            return -1;
        }
        state->error = *(const int *)value;
        break;
    case REMOVEFILE_STATE_STATUS_CALLBACK: state->status = (removefile_callback)value; break;
    case REMOVEFILE_STATE_STATUS_CONTEXT: state->status_context = (void *)value; break;
    default:
        errno = EINVAL;
        return -1;
    }
    return 0;
}

// Stops a removefile running with this state, from another thread or a
// callback: it fails with ECANCELED before its next file.
int darwin_removefile_cancel(struct darwin_removefile_state *state) DARWIN_SYMBOL(removefile_cancel);
int darwin_removefile_cancel(struct darwin_removefile_state *state) {
    if (!state) {
        errno = EINVAL;
        return -1;
    }
    state->cancelled = true;
    return 0;
}

// MARK: - Overwriting

// A pass writes one pattern over the whole file: a byte, three repeating
// bytes, or random bytes (length 0).
struct pass {
    uint8_t length;
    uint8_t bytes[3];
};

#define RANDOM_PASS { 0, { 0 } }
#define BYTE_PASS(b) { 1, { b } }
#define TRIPLE_PASS(a, b, c) { 3, { a, b, c } }

static const struct pass one_pass[] = { RANDOM_PASS };
static const struct pass one_zero_pass[] = { BYTE_PASS(0x00) };
static const struct pass three_passes[] = { RANDOM_PASS, RANDOM_PASS, BYTE_PASS(0xAA) };
// The US DoD's, as removefile(3) lists them.
static const struct pass seven_passes[] = {
    BYTE_PASS(0xF6), BYTE_PASS(0x00), BYTE_PASS(0xFF), RANDOM_PASS, BYTE_PASS(0x00), BYTE_PASS(0xFF), RANDOM_PASS,
};
// Peter Gutmann's 35: four random passes, his 27 patterns, four random.
static const struct pass gutmann_passes[] = {
    RANDOM_PASS, RANDOM_PASS, RANDOM_PASS, RANDOM_PASS,
    BYTE_PASS(0x55), BYTE_PASS(0xAA), TRIPLE_PASS(0x92, 0x49, 0x24), TRIPLE_PASS(0x49, 0x24, 0x92),
    TRIPLE_PASS(0x24, 0x92, 0x49), BYTE_PASS(0x00), BYTE_PASS(0x11), BYTE_PASS(0x22), BYTE_PASS(0x33),
    BYTE_PASS(0x44), BYTE_PASS(0x55), BYTE_PASS(0x66), BYTE_PASS(0x77), BYTE_PASS(0x88), BYTE_PASS(0x99),
    BYTE_PASS(0xAA), BYTE_PASS(0xBB), BYTE_PASS(0xCC), BYTE_PASS(0xDD), BYTE_PASS(0xEE), BYTE_PASS(0xFF),
    TRIPLE_PASS(0x92, 0x49, 0x24), TRIPLE_PASS(0x49, 0x24, 0x92), TRIPLE_PASS(0x24, 0x92, 0x49),
    TRIPLE_PASS(0x6D, 0xB6, 0xDB), TRIPLE_PASS(0xB6, 0xDB, 0x6D), TRIPLE_PASS(0xDB, 0x6D, 0xB6),
    RANDOM_PASS, RANDOM_PASS, RANDOM_PASS, RANDOM_PASS,
};

// The passes the flags ask for: the most passes of those given.
static const struct pass *passes_for(uint32_t flags, size_t *count) {
#define PASSES(list) (*count = sizeof(list) / sizeof(list[0]), list)
    if (flags & REMOVEFILE_SECURE_35_PASS) return PASSES(gutmann_passes);
    if (flags & REMOVEFILE_SECURE_7_PASS) return PASSES(seven_passes);
    if (flags & REMOVEFILE_SECURE_3_PASS) return PASSES(three_passes);
    if (flags & REMOVEFILE_SECURE_1_PASS) return PASSES(one_pass);
    if (flags & REMOVEFILE_SECURE_1_PASS_ZERO) return PASSES(one_zero_pass);
#undef PASSES
    *count = 0;
    return NULL;
}

// Writes each pass over the file's length and makes it reach the disc. A
// file with other names keeps its contents for them: only this name goes.
static int overwrite(int directory, const char *name, uint32_t flags) {
    size_t count;
    const struct pass *passes = passes_for(flags, &count);
    if (!passes)
        return 0;
    int fd = openat64(directory, name, O_WRONLY | O_NOFOLLOW | O_NOCTTY | O_CLOEXEC);
    if (fd < 0)
        return -1;
    struct stat64 info;
    if (fstat64(fd, &info) != 0) {
        int error = errno;
        close(fd);
        errno = error;
        return -1;
    }
    if (!S_ISREG(info.st_mode) || info.st_nlink > 1) {
        close(fd);
        return 0;
    }
    // Two bytes over, so a chunk of a three-byte pattern can start at any of its bytes.
    enum { CHUNK = 65536 };
    uint8_t *buffer = malloc(CHUNK + 2);
    if (!buffer) {
        close(fd);
        errno = ENOMEM;
        return -1;
    }
    int result = 0;
    for (size_t p = 0; p < count && result == 0; p++) {
        for (size_t i = 0; passes[p].length && i < CHUNK + 2; i++)
            buffer[i] = passes[p].bytes[i % passes[p].length];
        off64_t at = 0;
        while (at < info.st_size && result == 0) {
            size_t length = info.st_size - at < CHUNK ? (size_t)(info.st_size - at) : CHUNK;
            if (!passes[p].length)
                arc4random_buf(buffer, length);
            // The pattern runs on across chunks: start it where the offset left it.
            const uint8_t *from = passes[p].length == 3 ? buffer + at % 3 : buffer;
            ssize_t written = pwrite64(fd, from, length, at);
            if (written < 0) {
                if (errno != EINTR)
                    result = -1;
                continue;
            }
            if (written == 0) {
                errno = EIO;
                result = -1;
                continue;
            }
            at += written;
        }
        if (result == 0 && fsync(fd) != 0 && errno != EINVAL)
            result = -1;
    }
    free(buffer);
    int error = errno;
    close(fd);
    errno = error;
    return result;
}

// MARK: - The walk

struct walk {
    struct darwin_removefile_state *state;
    uint32_t flags;
    dev_t device;
    int error;      // Linux's errno for the first failure kept; 0 for none
    bool stopped;
};

// A callback's answer, or -1 for one that isn't an answer.
static int ask(struct walk *walk, removefile_callback callback, void *context, const char *path) {
    int answer = PERRY_DARWIN_FUNCTION(callback)(walk->state, path, context);
    return answer == REMOVEFILE_PROCEED || answer == REMOVEFILE_SKIP || answer == REMOVEFILE_STOP ? answer : -1;
}

static void stop(struct walk *walk, int error) {
    if (!walk->error)
        walk->error = error;
    walk->stopped = true;
}

// A failure at `path`: the error callback decides, given the error in the
// state, whether the walk goes on (and the failure is forgotten) or stops.
// Without one, the walk goes on and the first failure is what removefile
// reports at the end.
static void failed(struct walk *walk, const char *path, int error) {
    if (walk->state)
        walk->state->error = perry_darwin_errno_from_linux(error);
    if (walk->state && walk->state->error_callback) {
        int answer = ask(walk, walk->state->error_callback, walk->state->error_context, path);
        if (answer == REMOVEFILE_STOP)
            stop(walk, error);
        else if (answer < 0)
            stop(walk, EINVAL);
        return;
    }
    if (!walk->error)
        walk->error = error;
}

// `path` joined with `name`, to free.
static char *child_path(const char *path, const char *name) {
    size_t length = strlen(path);
    bool slash = length > 0 && path[length - 1] == '/';
    char *joined = malloc(length + strlen(name) + 2);
    if (joined)
        strcpy(stpcpy(stpcpy(joined, path), slash ? "" : "/"), name);
    return joined;
}

// The names in a directory, but . and .., read whole before any is removed;
// `count` of them in an array to free with each name. NULL with errno for a
// failure.
static char **directory_names(int fd, size_t *count) {
    *count = 0;
    int copy = dup(fd);
    DIR *directory = copy >= 0 ? fdopendir(copy) : NULL;
    if (!directory) {
        int error = errno;
        if (copy >= 0)
            close(copy);
        errno = error;
        return NULL;
    }
    size_t capacity = 16;
    char **names = malloc(capacity * sizeof(*names));
    struct dirent64 *entry;
    errno = 0;
    while (names && (entry = readdir64(directory))) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
            continue;
        if (*count == capacity) {
            char **grown = realloc(names, (capacity *= 2) * sizeof(*names));
            if (!grown)
                break;
            names = grown;
        }
        if (!(names[*count] = strdup(entry->d_name)))
            break;
        (*count)++;
        errno = 0;
    }
    int error = names && errno == 0 ? 0 : (errno ? errno : ENOMEM);
    closedir(directory);
    if (error) {
        for (size_t i = 0; names && i < *count; i++)
            free(names[i]);
        free(names);
        *count = 0;
        errno = error;
        return NULL;
    }
    return names;
}

// Removes `name` in `directory`, which is `path` to the callbacks, and for
// a directory when recursive what it holds first. The top item is kept
// with REMOVEFILE_KEEP_PARENT.
static void remove_item(struct walk *walk, int directory, const char *name, const char *path, bool top) {
    if (walk->state && walk->state->cancelled) {
        stop(walk, ECANCELED);
        return;
    }
    struct stat64 info;
    if (fstatat64(directory, name, &info, AT_SYMLINK_NOFOLLOW) != 0) {
        failed(walk, path, errno);
        return;
    }
    if (top)
        walk->device = info.st_dev;
    bool is_directory = S_ISDIR(info.st_mode);
    // Another file system's directory is left as it is without
    // REMOVEFILE_CROSS_MOUNT, and removing it fails (EBUSY) as it should.
    if (is_directory && (walk->flags & (REMOVEFILE_RECURSIVE | REMOVEFILE_RECURSIVE_SLIM)) &&
        (top || info.st_dev == walk->device || (walk->flags & REMOVEFILE_CROSS_MOUNT))) {
        int fd = openat(directory, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        size_t count = 0;
        char **names = fd >= 0 ? directory_names(fd, &count) : NULL;
        if (!names) {
            failed(walk, path, errno);
        } else {
            for (size_t i = 0; i < count; i++) {
                if (!walk->stopped) {
                    char *inner = child_path(path, names[i]);
                    if (inner)
                        remove_item(walk, fd, names[i], inner, false);
                    else
                        failed(walk, path, ENOMEM);
                    free(inner);
                }
                free(names[i]);
            }
            free(names);
        }
        if (fd >= 0)
            close(fd);
        if (walk->stopped)
            return;
    }
    if (top && (walk->flags & REMOVEFILE_KEEP_PARENT))
        return;
    if (walk->state && walk->state->confirm) {
        int answer = ask(walk, walk->state->confirm, walk->state->confirm_context, path);
        if (answer == REMOVEFILE_SKIP)
            return;
        if (answer != REMOVEFILE_PROCEED) {
            stop(walk, answer == REMOVEFILE_STOP ? ECANCELED : EINVAL);
            return;
        }
    }
    if (S_ISREG(info.st_mode) && (walk->flags & REMOVEFILE_SECURE) && overwrite(directory, name, walk->flags) != 0) {
        failed(walk, path, errno);
        return;
    }
    if (unlinkat(directory, name, is_directory ? AT_REMOVEDIR : 0) != 0) {
        failed(walk, path, errno);
        return;
    }
    if (walk->state && walk->state->status) {
        int answer = ask(walk, walk->state->status, walk->state->status_context, path);
        if (answer == REMOVEFILE_STOP)
            stop(walk, ECANCELED);
        else if (answer < 0)
            stop(walk, EINVAL);
    }
}

// MARK: - removefile

// 0, or -1 with errno for the first failure the walk kept. Darwin's flags
// for APFS (REMOVEFILE_CLEAR_PURGEABLE, REMOVEFILE_SYSTEM_DISCARDED) have
// nothing to do on Linux's file systems. REMOVEFILE_RECURSIVE_SLIM is the
// same walk, and takes no overwriting, long paths, or confirm or status
// callbacks (EINVAL), as on Darwin.
static int remove_at(int directory, const char *path, struct darwin_removefile_state *state, uint32_t flags) {
    if (!path) {
        errno = EINVAL;
        return -1;
    }
    if ((flags & REMOVEFILE_RECURSIVE_SLIM) &&
        ((flags & (REMOVEFILE_SECURE | REMOVEFILE_ALLOW_LONG_PATHS)) || (state && (state->confirm || state->status)))) {
        errno = EINVAL;
        return -1;
    }
    if (state)
        state->cancelled = false;
    struct walk walk = { .state = state, .flags = flags };
    remove_item(&walk, directory == DARWIN_AT_FDCWD ? AT_FDCWD : directory, path, path, true);
    if (walk.error) {
        errno = walk.error;
        return -1;
    }
    return 0;
}

int darwin_removefile(const char *path, struct darwin_removefile_state *state, uint32_t flags) DARWIN_SYMBOL(removefile);
int darwin_removefile(const char *path, struct darwin_removefile_state *state, uint32_t flags) {
    return remove_at(AT_FDCWD, path, state, flags);
}

int darwin_removefileat(int fd, const char *path, struct darwin_removefile_state *state, uint32_t flags)
    DARWIN_SYMBOL(removefileat);
int darwin_removefileat(int fd, const char *path, struct darwin_removefile_state *state, uint32_t flags) {
    return remove_at(fd, path, state, flags);
}
