// libPerryBom: the provider for /System/Library/PrivateFrameworks/Bom.framework.
//
// Bom's copier copies files, directory trees and archives, and tells a
// program what it is doing through handlers. Swift Playgrounds uses it to
// unpack a project template, a zip, into a new project. What the copier
// copies, here, is a zip, which is unpacked, a directory, which is copied
// with what is in it, or a file. The handlers are kept and not called.

#define _GNU_SOURCE
#include "PerryBom.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <zlib.h>

#define BOM_SYMBOL(name) __asm__("_" #name) __attribute__((visibility("default"), used))

__attribute__((visibility("default")))
void *perry_provider_symbol(const char *name) {
    (void)name;
    return NULL;
}

// MARK: - Copier

struct copier {
    void *user_data;
    void *handlers[8];
};

void *bom_copier_new(void) BOM_SYMBOL(BOMCopierNew);
void *bom_copier_new(void) { return calloc(1, sizeof(struct copier)); }

void bom_copier_free(void *copier) BOM_SYMBOL(BOMCopierFree);
void bom_copier_free(void *copier) { free(copier); }

void bom_copier_set_user_data(void *copier, void *data) BOM_SYMBOL(BOMCopierSetUserData);
void bom_copier_set_user_data(void *copier, void *data) {
    if (copier)
        ((struct copier *)copier)->user_data = data;
}

void *bom_copier_user_data(void *copier) BOM_SYMBOL(BOMCopierUserData);
void *bom_copier_user_data(void *copier) { return copier ? ((struct copier *)copier)->user_data : NULL; }

#define HANDLER_SETTER(symbol, slot) \
    void bom_copier_set_##slot(void *copier, void *handler) BOM_SYMBOL(symbol); \
    void bom_copier_set_##slot(void *copier, void *handler) { \
        if (copier) \
            ((struct copier *)copier)->handlers[slot_index_##slot] = handler; \
    }
enum {
    slot_index_started, slot_index_finished, slot_index_update, slot_index_fatal, slot_index_fatal_file,
    slot_index_conflict, slot_index_file_error,
};
HANDLER_SETTER(BOMCopierSetCopyFileStartedHandler, started)
HANDLER_SETTER(BOMCopierSetCopyFileFinishedHandler, finished)
HANDLER_SETTER(BOMCopierSetCopyFileUpdateHandler, update)
HANDLER_SETTER(BOMCopierSetFatalErrorHandler, fatal)
HANDLER_SETTER(BOMCopierSetFatalFileErrorHandler, fatal_file)
HANDLER_SETTER(BOMCopierSetFileConflictErrorHandler, conflict)
HANDLER_SETTER(BOMCopierSetFileErrorHandler, file_error)

// MARK: - Zip archives

static uint16_t u16(const uint8_t *p) { return (uint16_t)(p[0] | p[1] << 8); }
static uint32_t u32(const uint8_t *p) { return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24; }

// A name that stays inside the folder it is unpacked into.
static bool safe_name(const char *name) {
    if (!*name || name[0] == '/')
        return false;
    for (const char *p = name; *p; p++)
        if ((p == name || p[-1] == '/') && p[0] == '.' && p[1] == '.' && (p[2] == '/' || p[2] == 0))
            return false;
    return true;
}

static void make_parents(char *path) {
    for (char *slash = strchr(path + 1, '/'); slash; slash = strchr(slash + 1, '/')) {
        *slash = 0;
        mkdir(path, 0777);
        *slash = '/';
    }
}

static bool read_file(const char *path, uint8_t **data, size_t *size) {
    int fd = open(path, O_RDONLY);
    struct stat info;
    if (fd < 0 || fstat(fd, &info) != 0) {
        if (fd >= 0) close(fd);
        return false;
    }
    *size = (size_t)info.st_size;
    *data = malloc(*size ? *size : 1);
    size_t done = 0;
    while (*data && done < *size) {
        ssize_t n = read(fd, *data + done, *size - done);
        if (n <= 0) break;
        done += (size_t)n;
    }
    close(fd);
    if (done != *size) {
        free(*data);
        return false;
    }
    return true;
}

static bool is_zip(const uint8_t *data, size_t size) { return size >= 4 && u32(data) == 0x04034b50u; }

// The central directory: where it starts and how many entries it has.
static bool find_directory(const uint8_t *data, size_t size, size_t *start, size_t *count) {
    if (size < 22)
        return false;
    for (size_t at = size - 22;; at--) {
        if (u32(data + at) == 0x06054b50u) {
            *count = u16(data + at + 10);
            *start = u32(data + at + 16);
            return *start <= size;
        }
        if (at == 0 || size - at > 22 + 65535)
            return false;
    }
}

static bool inflate_entry(const uint8_t *in, size_t in_size, uint8_t *out, size_t out_size) {
    z_stream stream = { 0 };
    if (inflateInit2(&stream, -15) != Z_OK)
        return false;
    stream.next_in = (Bytef *)in;
    stream.avail_in = (uInt)in_size;
    stream.next_out = out;
    stream.avail_out = (uInt)out_size;
    int result = inflate(&stream, Z_FINISH);
    inflateEnd(&stream);
    return result == Z_STREAM_END || (result == Z_OK && stream.total_out == out_size);
}

// Unpacks the archive into `destination`, or just counts its entries.
static int unpack(struct copier *copier, const uint8_t *data, size_t size, const char *destination, long *entries) {
    size_t at, count;
    if (!find_directory(data, size, &at, &count))
        return EINVAL;
    for (size_t i = 0; i < count; i++) {
        if (at + 46 > size || u32(data + at) != 0x02014b50u)
            return EINVAL;
        uint16_t made_by = u16(data + at + 4), method = u16(data + at + 10);
        uint32_t compressed = u32(data + at + 20), uncompressed = u32(data + at + 24);
        uint16_t name_length = u16(data + at + 28), extra_length = u16(data + at + 30), comment_length = u16(data + at + 32);
        uint32_t attributes = u32(data + at + 38), local = u32(data + at + 42);
        if (at + 46 + name_length > size)
            return EINVAL;
        char *name = strndup((const char *)data + at + 46, name_length);
        at += 46u + name_length + extra_length + comment_length;
        if (entries)
            (*entries)++;
        if (entries) {
            free(name);
            continue;
        }
        if (!name || !safe_name(name)) {
            free(name);
            continue;
        }
        char *path = NULL;
        if (asprintf(&path, "%s/%s", destination, name) < 0) {
            free(name);
            return ENOMEM;
        }
        bool directory = name_length > 0 && name[name_length - 1] == '/';
        // The program hears of each item as it is begun, by its path in the
        // archive, without a directory's trailing slash.
        typedef int (*Started)(void *, const char *, long, void *);
        if (copier && copier->handlers[slot_index_started]) {
            if (directory)
                name[name_length - 1] = 0;
            ((Started)copier->handlers[slot_index_started])(copier, name, 0, NULL);
            if (directory)
                name[name_length - 1] = '/';
        }
        mode_t mode = (made_by >> 8) == 3 ? (mode_t)(attributes >> 16) : 0;
        int status = 0;
        if (directory) {
            make_parents(path);
            if (mkdir(path, 0777) != 0 && errno != EEXIST)
                status = errno;
        } else {
            if ((size_t)local + 30 > size || u32(data + local) != 0x04034b50u) {
                status = EINVAL;
            } else {
                size_t body = (size_t)local + 30 + u16(data + local + 26) + u16(data + local + 28);
                uint8_t *contents = malloc(uncompressed ? uncompressed : 1);
                if (body + compressed > size || !contents) {
                    status = EINVAL;
                } else if (method == 0 && compressed == uncompressed) {
                    memcpy(contents, data + body, uncompressed);
                } else if (method != 8 || !inflate_entry(data + body, compressed, contents, uncompressed)) {
                    status = EINVAL;
                }
                if (!status) {
                    make_parents(path);
                    if ((mode & S_IFMT) == S_IFLNK) {
                        char *target = strndup((const char *)contents, uncompressed);
                        unlink(path);
                        if (!target || symlink(target, path) != 0)
                            status = errno;
                        free(target);
                    } else {
                        int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, mode & 0777 ? mode & 0777 : 0644);
                        if (fd < 0 || write(fd, contents, uncompressed) != (ssize_t)uncompressed)
                            status = errno ? errno : EIO;
                        if (fd >= 0)
                            close(fd);
                    }
                }
                free(contents);
            }
        }
        free(path);
        free(name);
        if (status)
            return status;
    }
    return 0;
}

// MARK: - Copies of files

static int copy_item(const char *from, const char *to);

static int copy_file(const char *from, const char *to, mode_t mode) {
    uint8_t *data;
    size_t size;
    if (!read_file(from, &data, &size))
        return errno ? errno : EIO;
    int fd = open(to, O_WRONLY | O_CREAT | O_TRUNC, mode & 0777);
    int status = 0;
    if (fd < 0 || write(fd, data, size) != (ssize_t)size)
        status = errno ? errno : EIO;
    if (fd >= 0)
        close(fd);
    free(data);
    return status;
}

static int copy_directory(const char *from, const char *to, mode_t mode) {
    if (mkdir(to, mode & 0777) != 0 && errno != EEXIST)
        return errno;
    DIR *directory = opendir(from);
    if (!directory)
        return errno;
    int status = 0;
    for (struct dirent *entry; !status && (entry = readdir(directory));) {
        if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, ".."))
            continue;
        char *source = NULL, *target = NULL;
        if (asprintf(&source, "%s/%s", from, entry->d_name) < 0 || asprintf(&target, "%s/%s", to, entry->d_name) < 0)
            status = ENOMEM;
        else
            status = copy_item(source, target);
        free(source);
        free(target);
    }
    closedir(directory);
    return status;
}

static int copy_item(const char *from, const char *to) {
    struct stat info;
    if (lstat(from, &info) != 0)
        return errno;
    if (S_ISLNK(info.st_mode)) {
        char target[4096];
        ssize_t length = readlink(from, target, sizeof(target) - 1);
        if (length < 0)
            return errno;
        target[length] = 0;
        unlink(to);
        return symlink(target, to) == 0 ? 0 : errno;
    }
    return S_ISDIR(info.st_mode) ? copy_directory(from, to, info.st_mode) : copy_file(from, to, info.st_mode);
}

// Copies, or unpacks, `from` into `to`: a zip unpacks into the directory `to`,
// which is made. Returns 0, or an errno.
int bom_copier_copy(void *copier, const char *from, const char *to, void *options) BOM_SYMBOL(BOMCopierCopyWithOptions);
static int copy_with_options(void *copier, const char *from, const char *to, void *options);
int bom_copier_copy(void *copier, const char *from, const char *to, void *options) {
    int status = copy_with_options(copier, from, to, options);
    if (getenv("PERRY_BOM_TRACE"))
        fprintf(stderr, "perry: BOMCopierCopyWithOptions(%s, %s) = %d\n", from ? from : "(null)", to ? to : "(null)", status);
    return status;
}

static int copy_with_options(void *copier, const char *from, const char *to, void *options) {
    (void)options;
    if (!from || !to)
        return EINVAL;
    uint8_t *data;
    size_t size;
    struct stat info;
    if (stat(from, &info) == 0 && !S_ISDIR(info.st_mode) && read_file(from, &data, &size)) {
        int status;
        if (is_zip(data, size)) {
            char *destination = strdup(to);
            if (destination) {
                make_parents(destination);
                if (mkdir(destination, 0777) != 0 && errno != EEXIST)
                    status = errno;
                else
                    status = unpack(copier, data, size, destination, NULL);
            } else {
                status = ENOMEM;
            }
            free(destination);
        } else {
            status = copy_file(from, to, info.st_mode);
        }
        free(data);
        return status;
    }
    return copy_item(from, to);
}

// How many entries an archive holds, for progress: 0, or an error, and the
// count in the third argument.
int bom_copier_count_files(void *copier, const char *archive, uint64_t *count, void *options)
    BOM_SYMBOL(BOMCopierCountFilesInArchive);
int bom_copier_count_files(void *copier, const char *archive, uint64_t *count, void *options) {
    (void)copier; (void)options;
    uint8_t *data;
    size_t size;
    if (!archive || !read_file(archive, &data, &size))
        return errno ? errno : ENOENT;
    long entries = 0;
    if (is_zip(data, size))
        unpack(NULL, data, size, NULL, &entries);
    free(data);
    if (count)
        *count = (uint64_t)entries;
    return 0;
}
