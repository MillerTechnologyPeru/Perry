// Files with Darwin's ABI over glibc's: open's flags, fcntl's commands and
// file locks, the *at functions' AT_FDCWD and flags, struct stat and
// struct dirent, which are laid out differently. open, openat and fcntl
// are variadic on Darwin; thunks.S hands them their arguments as a
// va_list.

#define _GNU_SOURCE
#include "PerrySystem.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/statfs.h>
#include <sys/statvfs.h>
#include <sys/sysmacros.h>
#include <sys/time.h>
#include <unistd.h>

// MARK: - Flags

enum {
    DARWIN_O_NONBLOCK = 0x4,
    DARWIN_O_APPEND = 0x8,
    DARWIN_O_SHLOCK = 0x10,
    DARWIN_O_EXLOCK = 0x20,
    DARWIN_O_ASYNC = 0x40,
    DARWIN_O_SYNC = 0x80,
    DARWIN_O_NOFOLLOW = 0x100,
    DARWIN_O_CREAT = 0x200,
    DARWIN_O_TRUNC = 0x400,
    DARWIN_O_EXCL = 0x800,
    DARWIN_O_NOCTTY = 0x20000,
    DARWIN_O_DIRECTORY = 0x100000,
    DARWIN_O_DSYNC = 0x400000,
    DARWIN_O_CLOEXEC = 0x1000000,

    DARWIN_AT_FDCWD = -2,
    DARWIN_AT_EACCESS = 0x10,
    DARWIN_AT_SYMLINK_NOFOLLOW = 0x20,
    DARWIN_AT_SYMLINK_FOLLOW = 0x40,
    DARWIN_AT_REMOVEDIR = 0x80,

    DARWIN_F_GETLK = 7,
    DARWIN_F_SETLK = 8,
    DARWIN_F_SETLKW = 9,
    DARWIN_F_PREALLOCATE = 42,
    DARWIN_F_RDAHEAD = 45,
    DARWIN_F_NOCACHE = 48,
    DARWIN_F_GETPATH = 50,
    DARWIN_F_FULLFSYNC = 51,
    DARWIN_F_DUPFD_CLOEXEC = 67,
    DARWIN_F_SETNOSIGPIPE = 73,
    DARWIN_F_GETNOSIGPIPE = 74,
    DARWIN_F_BARRIERFSYNC = 85,

    DARWIN_F_RDLCK = 1,
    DARWIN_F_UNLCK = 2,
    DARWIN_F_WRLCK = 3,
};

static const struct { int darwin, linux_value; } open_flags[] = {
    { DARWIN_O_NONBLOCK, O_NONBLOCK }, { DARWIN_O_APPEND, O_APPEND }, { DARWIN_O_ASYNC, O_ASYNC },
    { DARWIN_O_SYNC, O_SYNC }, { DARWIN_O_NOFOLLOW, O_NOFOLLOW }, { DARWIN_O_CREAT, O_CREAT },
    { DARWIN_O_TRUNC, O_TRUNC }, { DARWIN_O_EXCL, O_EXCL }, { DARWIN_O_NOCTTY, O_NOCTTY },
    { DARWIN_O_DIRECTORY, O_DIRECTORY }, { DARWIN_O_DSYNC, O_DSYNC }, { DARWIN_O_CLOEXEC, O_CLOEXEC },
};

#define COUNT(array) (sizeof(array) / sizeof((array)[0]))

static int open_flags_to_linux(int flags) {
    int out = flags & O_ACCMODE;
    for (size_t i = 0; i < COUNT(open_flags); i++)
        if (flags & open_flags[i].darwin)
            out |= open_flags[i].linux_value;
    return out;
}

static int open_flags_to_darwin(int flags) {
    int out = flags & O_ACCMODE;
    for (size_t i = 0; i < COUNT(open_flags); i++)
        // O_SYNC includes O_DSYNC on Linux; report it only when all of it is set.
        if ((flags & open_flags[i].linux_value) == open_flags[i].linux_value)
            out |= open_flags[i].darwin;
    if ((out & DARWIN_O_SYNC) && (out & DARWIN_O_DSYNC))
        out &= ~DARWIN_O_DSYNC;
    return out;
}

static int directory_to_linux(int fd) {
    return fd == DARWIN_AT_FDCWD ? AT_FDCWD : fd;
}

static int at_flags_to_linux(int flags) {
    int out = 0;
    if (flags & DARWIN_AT_EACCESS) out |= AT_EACCESS;
    if (flags & DARWIN_AT_SYMLINK_NOFOLLOW) out |= AT_SYMLINK_NOFOLLOW;
    if (flags & DARWIN_AT_SYMLINK_FOLLOW) out |= AT_SYMLINK_FOLLOW;
    if (flags & DARWIN_AT_REMOVEDIR) out |= AT_REMOVEDIR;
    return out;
}

// O_EXLOCK and O_SHLOCK take a flock() lock as the file opens.
static int lock_on_open(int fd, int flags) {
    if (fd < 0 || !(flags & (DARWIN_O_EXLOCK | DARWIN_O_SHLOCK)))
        return fd;
    int operation = (flags & DARWIN_O_EXLOCK) ? LOCK_EX : LOCK_SH;
    if (flags & DARWIN_O_NONBLOCK)
        operation |= LOCK_NB;
    if (flock(fd, operation) != 0) {
        int saved = errno;
        close(fd);
        errno = saved;
        return -1;
    }
    return fd;
}

// MARK: - open

int perry_vopen(const char *path, int flags, va_list arguments) {
    mode_t mode = (flags & DARWIN_O_CREAT) ? (mode_t)va_arg(arguments, int) : 0;
    return lock_on_open(open(path, open_flags_to_linux(flags), mode), flags);
}

int perry_vopenat(int directory, const char *path, int flags, va_list arguments) {
    mode_t mode = (flags & DARWIN_O_CREAT) ? (mode_t)va_arg(arguments, int) : 0;
    return lock_on_open(openat(directory_to_linux(directory), path, open_flags_to_linux(flags), mode), flags);
}

// open with a data protection class, which Linux files do not have.
int perry_vopen_dprotected(const char *path, int flags, int protection_class, int dpflags, va_list arguments) {
    (void)protection_class;
    (void)dpflags;
    return perry_vopen(path, flags, arguments);
}

int darwin_creat(const char *path, mode_t mode) DARWIN_SYMBOL(creat);
int darwin_creat(const char *path, mode_t mode) {
    return creat(path, mode);
}

// MARK: - fcntl

struct darwin_flock {
    off_t l_start;
    off_t l_len;
    pid_t l_pid;
    short l_type;
    short l_whence;
};

static short lock_type_to_linux(short type) {
    switch (type) {
    case DARWIN_F_RDLCK: return F_RDLCK;
    case DARWIN_F_WRLCK: return F_WRLCK;
    default: return F_UNLCK;
    }
}

static short lock_type_to_darwin(short type) {
    switch (type) {
    case F_RDLCK: return DARWIN_F_RDLCK;
    case F_WRLCK: return DARWIN_F_WRLCK;
    default: return DARWIN_F_UNLCK;
    }
}

static int lock_command(int fd, int command, struct darwin_flock *darwin) {
    if (!darwin) {
        errno = EFAULT;
        return -1;
    }
    struct flock lock = {
        .l_type = lock_type_to_linux(darwin->l_type), .l_whence = darwin->l_whence,
        .l_start = darwin->l_start, .l_len = darwin->l_len, .l_pid = darwin->l_pid,
    };
    int result = fcntl(fd, command, &lock);
    if (result == 0 && command == F_GETLK) {
        darwin->l_type = lock_type_to_darwin(lock.l_type);
        darwin->l_whence = lock.l_whence;
        darwin->l_start = lock.l_start;
        darwin->l_len = lock.l_len;
        darwin->l_pid = lock.l_pid;
    }
    return result;
}

int perry_vfcntl(int fd, int command, va_list arguments) {
    long argument = va_arg(arguments, long);
    switch (command) {
    case F_DUPFD:
    case F_GETFD:
    case F_SETFD:
        return fcntl(fd, command, (int)argument);
    case F_GETFL: {
        int flags = fcntl(fd, F_GETFL);
        return flags < 0 ? flags : open_flags_to_darwin(flags);
    }
    case F_SETFL:
        return fcntl(fd, F_SETFL, open_flags_to_linux((int)argument));
    case DARWIN_F_GETLK:
        return lock_command(fd, F_GETLK, (struct darwin_flock *)argument);
    case DARWIN_F_SETLK:
        return lock_command(fd, F_SETLK, (struct darwin_flock *)argument);
    case DARWIN_F_SETLKW:
        return lock_command(fd, F_SETLKW, (struct darwin_flock *)argument);
    case DARWIN_F_DUPFD_CLOEXEC:
        return fcntl(fd, F_DUPFD_CLOEXEC, (int)argument);
    case DARWIN_F_GETPATH: {
        // The path into a MAXPATHLEN (1024) buffer.
        char link[64], target[PATH_MAX];
        snprintf(link, sizeof(link), "/proc/self/fd/%d", fd);
        ssize_t length = readlink(link, target, sizeof(target) - 1);
        if (length < 0)
            return -1;
        if (length >= 1024) {
            errno = ENAMETOOLONG;
            return -1;
        }
        target[length] = 0;
        memcpy((char *)argument, target, (size_t)length + 1);
        return 0;
    }
    case DARWIN_F_FULLFSYNC:
    case DARWIN_F_BARRIERFSYNC:
        return fsync(fd);
    case DARWIN_F_NOCACHE:
    case DARWIN_F_RDAHEAD:
    case DARWIN_F_SETNOSIGPIPE:
    case DARWIN_F_PREALLOCATE:
        // Hints with nothing to do here; sockets never raise SIGPIPE.
        return fcntl(fd, F_GETFD) < 0 ? -1 : 0;
    case DARWIN_F_GETNOSIGPIPE:
        return fcntl(fd, F_GETFD) < 0 ? -1 : 1;
    default:
        errno = EINVAL;
        return -1;
    }
}

// MARK: - stat

// Darwin's armv7 aligns 64-bit members to 4 bytes, so st_size is at offset 60
// and the structure is 108 bytes; arm64's is 144.
#if defined(__arm__)
#pragma pack(push, 4)
#endif
struct darwin_stat {
    int32_t st_dev;
    uint16_t st_mode;
    uint16_t st_nlink;
    uint64_t st_ino;
    uint32_t st_uid;
    uint32_t st_gid;
    int32_t st_rdev;
    struct timespec st_atimespec;
    struct timespec st_mtimespec;
    struct timespec st_ctimespec;
    struct timespec st_birthtimespec;
    int64_t st_size;
    int64_t st_blocks;
    int32_t st_blksize;
    uint32_t st_flags;
    uint32_t st_gen;
    int32_t st_lspare;
    int64_t st_qspare[2];
};
#if defined(__arm__)
#pragma pack(pop)
_Static_assert(sizeof(struct darwin_stat) == 108, "struct stat is 108 bytes on Darwin armv7");
_Static_assert(offsetof(struct darwin_stat, st_size) == 60, "st_size is at 60 on Darwin armv7");
#else
_Static_assert(sizeof(struct darwin_stat) == 144, "struct stat is 144 bytes on Darwin");
#endif

// Darwin's dev_t packs the major number into the top 8 bits.
static int32_t device_to_darwin(uint32_t major_number, uint32_t minor_number) {
    return (int32_t)((major_number << 24) | (minor_number & 0xffffff));
}

static struct timespec timestamp(struct statx_timestamp time) {
    return (struct timespec){ .tv_sec = time.tv_sec, .tv_nsec = time.tv_nsec };
}

// statx, for the birth time struct stat lacks; birth is the change time
// where the file system does not record it.
static int stat_at(int directory, const char *path, int flags, struct darwin_stat *out) {
    struct statx info;
    if (statx(directory, path, flags, STATX_BASIC_STATS | STATX_BTIME, &info) != 0)
        return -1;
    memset(out, 0, sizeof(*out));
    out->st_dev = device_to_darwin(info.stx_dev_major, info.stx_dev_minor);
    out->st_mode = (uint16_t)info.stx_mode;
    out->st_nlink = info.stx_nlink > UINT16_MAX ? UINT16_MAX : (uint16_t)info.stx_nlink;
    out->st_ino = info.stx_ino;
    out->st_uid = info.stx_uid;
    out->st_gid = info.stx_gid;
    out->st_rdev = device_to_darwin(info.stx_rdev_major, info.stx_rdev_minor);
    out->st_atimespec = timestamp(info.stx_atime);
    out->st_mtimespec = timestamp(info.stx_mtime);
    out->st_ctimespec = timestamp(info.stx_ctime);
    out->st_birthtimespec = timestamp((info.stx_mask & STATX_BTIME) ? info.stx_btime : info.stx_ctime);
    out->st_size = (int64_t)info.stx_size;
    out->st_blocks = (int64_t)info.stx_blocks;
    out->st_blksize = (int32_t)info.stx_blksize;
    return 0;
}

int darwin_stat(const char *path, struct darwin_stat *out) DARWIN_SYMBOL(stat);
int darwin_stat(const char *path, struct darwin_stat *out) {
    return stat_at(AT_FDCWD, path, 0, out);
}

int darwin_lstat(const char *path, struct darwin_stat *out) DARWIN_SYMBOL(lstat);
int darwin_lstat(const char *path, struct darwin_stat *out) {
    return stat_at(AT_FDCWD, path, AT_SYMLINK_NOFOLLOW, out);
}

int darwin_fstat(int fd, struct darwin_stat *out) DARWIN_SYMBOL(fstat);
int darwin_fstat(int fd, struct darwin_stat *out) {
    return stat_at(fd, "", AT_EMPTY_PATH, out);
}

int darwin_fstatat(int directory, const char *path, struct darwin_stat *out, int flags) DARWIN_SYMBOL(fstatat);
int darwin_fstatat(int directory, const char *path, struct darwin_stat *out, int flags) {
    return stat_at(directory_to_linux(directory), path, at_flags_to_linux(flags), out);
}

// MARK: - File systems

// struct statfs with 64-bit inodes, as on arm64.
struct darwin_statfs {
    uint32_t f_bsize;
    int32_t f_iosize;
    uint64_t f_blocks;
    uint64_t f_bfree;
    uint64_t f_bavail;
    uint64_t f_files;
    uint64_t f_ffree;
    int32_t f_fsid[2];
    uint32_t f_owner;
    uint32_t f_type;
    uint32_t f_flags;
    uint32_t f_fssubtype;
    char f_fstypename[16];
    char f_mntonname[1024];
    char f_mntfromname[1024];
    uint32_t f_flags_ext;
    uint32_t f_reserved[7];
};

_Static_assert(sizeof(struct darwin_statfs) == 2168, "struct statfs is 2168 bytes on Darwin");

enum { DARWIN_MNT_RDONLY = 0x1, DARWIN_MNT_NOSUID = 0x8, DARWIN_MNT_LOCAL = 0x1000 };

// Every file system is a local APFS volume mounted at /, as an app's
// container is on iOS: the sizes are the real ones.
static void statfs_to_darwin(const struct statfs *info, struct darwin_statfs *out) {
    memset(out, 0, sizeof *out);
    out->f_bsize = (uint32_t)info->f_bsize;
    out->f_iosize = (int32_t)info->f_bsize;
    out->f_blocks = info->f_blocks;
    out->f_bfree = info->f_bfree;
    out->f_bavail = info->f_bavail;
    out->f_files = info->f_files;
    out->f_ffree = info->f_ffree;
    memcpy(out->f_fsid, &info->f_fsid, sizeof out->f_fsid);
    out->f_owner = 0;
    out->f_type = 0x1a;
    out->f_flags = DARWIN_MNT_LOCAL | (info->f_flags & ST_RDONLY ? DARWIN_MNT_RDONLY : 0) |
                   (info->f_flags & ST_NOSUID ? DARWIN_MNT_NOSUID : 0);
    strcpy(out->f_fstypename, "apfs");
    strcpy(out->f_mntonname, "/");
    strcpy(out->f_mntfromname, "/dev/disk1s1");
}

#if defined(__arm__)
// struct statvfs on 32-bit Darwin: eleven 32-bit words, where glibc's
// has 64-bit counts.
struct darwin_statvfs {
    uint32_t f_bsize, f_frsize, f_blocks, f_bfree, f_bavail, f_files, f_ffree, f_favail, f_fsid, f_flag, f_namemax;
};

// A count too large for 32 bits is the largest there is.
static uint32_t count32(uint64_t count) { return count > UINT32_MAX ? UINT32_MAX : (uint32_t)count; }

static void statvfs_to_darwin(const struct statvfs64 *info, struct darwin_statvfs *out) {
    out->f_bsize = (uint32_t)info->f_bsize;
    out->f_frsize = (uint32_t)info->f_frsize;
    out->f_blocks = count32(info->f_blocks);
    out->f_bfree = count32(info->f_bfree);
    out->f_bavail = count32(info->f_bavail);
    out->f_files = count32(info->f_files);
    out->f_ffree = count32(info->f_ffree);
    out->f_favail = count32(info->f_favail);
    out->f_fsid = (uint32_t)info->f_fsid;
    // ST_RDONLY and ST_NOSUID are bits 0 and 1 on both.
    out->f_flag = (uint32_t)info->f_flag & 3;
    out->f_namemax = (uint32_t)info->f_namemax;
}

int darwin_statvfs(const char *path, struct darwin_statvfs *out) DARWIN_SYMBOL(statvfs);
int darwin_statvfs(const char *path, struct darwin_statvfs *out) {
    struct statvfs64 info;
    if (statvfs64(path, &info) != 0) return -1;
    statvfs_to_darwin(&info, out);
    return 0;
}

int darwin_fstatvfs(int fd, struct darwin_statvfs *out) DARWIN_SYMBOL(fstatvfs);
int darwin_fstatvfs(int fd, struct darwin_statvfs *out) {
    struct statvfs64 info;
    if (fstatvfs64(fd, &info) != 0) return -1;
    statvfs_to_darwin(&info, out);
    return 0;
}
#endif

int darwin_statfs_path(const char *path, struct darwin_statfs *out) DARWIN_SYMBOL(statfs);
int darwin_statfs_path(const char *path, struct darwin_statfs *out) {
    struct statfs info;
    if (statfs(path, &info) != 0) return -1;
    statfs_to_darwin(&info, out);
    return 0;
}

int darwin_fstatfs(int fd, struct darwin_statfs *out) DARWIN_SYMBOL(fstatfs);
int darwin_fstatfs(int fd, struct darwin_statfs *out) {
    struct statfs info;
    if (fstatfs(fd, &info) != 0) return -1;
    statfs_to_darwin(&info, out);
    return 0;
}

// MARK: - Times and file system control

// Darwin's struct timeval: a 32-bit tv_usec, then padding.
struct darwin_file_timeval {
    int64_t tv_sec;
    int32_t tv_usec;
};

int darwin_futimes(int fd, const struct darwin_file_timeval times[2]) DARWIN_SYMBOL(futimes);
int darwin_futimes(int fd, const struct darwin_file_timeval times[2]) {
    if (!times) return futimes(fd, NULL);
    struct timeval converted[2] = {
        { .tv_sec = times[0].tv_sec, .tv_usec = times[0].tv_usec },
        { .tv_sec = times[1].tv_sec, .tv_usec = times[1].tv_usec },
    };
    return futimes(fd, converted);
}

// File system controls are HFS's and APFS's, which no Linux file system has.
int darwin_fsctl(const char *path, unsigned long request, void *data, unsigned options) DARWIN_SYMBOL(fsctl);
int darwin_fsctl(const char *path, unsigned long request, void *data, unsigned options) {
    (void)path; (void)request; (void)data; (void)options;
    errno = ENOTSUP;
    return -1;
}

// MARK: - The other *at functions

int darwin_unlinkat(int directory, const char *path, int flags) DARWIN_SYMBOL(unlinkat);
int darwin_unlinkat(int directory, const char *path, int flags) {
    return unlinkat(directory_to_linux(directory), path, at_flags_to_linux(flags));
}

int darwin_mkdirat(int directory, const char *path, mode_t mode) DARWIN_SYMBOL(mkdirat);
int darwin_mkdirat(int directory, const char *path, mode_t mode) {
    return mkdirat(directory_to_linux(directory), path, mode);
}

int darwin_renameat(int from_directory, const char *from, int to_directory, const char *to) DARWIN_SYMBOL(renameat);
int darwin_renameat(int from_directory, const char *from, int to_directory, const char *to) {
    return renameat(directory_to_linux(from_directory), from, directory_to_linux(to_directory), to);
}

int darwin_faccessat(int directory, const char *path, int mode, int flags) DARWIN_SYMBOL(faccessat);
int darwin_faccessat(int directory, const char *path, int mode, int flags) {
    return faccessat(directory_to_linux(directory), path, mode, at_flags_to_linux(flags));
}

ssize_t darwin_readlinkat(int directory, const char *path, char *buffer, size_t size) DARWIN_SYMBOL(readlinkat);
ssize_t darwin_readlinkat(int directory, const char *path, char *buffer, size_t size) {
    return readlinkat(directory_to_linux(directory), path, buffer, size);
}

int darwin_symlinkat(const char *target, int directory, const char *path) DARWIN_SYMBOL(symlinkat);
int darwin_symlinkat(const char *target, int directory, const char *path) {
    return symlinkat(target, directory_to_linux(directory), path);
}

int darwin_fchmodat(int directory, const char *path, mode_t mode, int flags) DARWIN_SYMBOL(fchmodat);
int darwin_fchmodat(int directory, const char *path, mode_t mode, int flags) {
    return fchmodat(directory_to_linux(directory), path, mode, at_flags_to_linux(flags));
}

int darwin_linkat(int from_directory, const char *from, int to_directory, const char *to, int flags) DARWIN_SYMBOL(linkat);
int darwin_linkat(int from_directory, const char *from, int to_directory, const char *to, int flags) {
    return linkat(directory_to_linux(from_directory), from, directory_to_linux(to_directory), to, at_flags_to_linux(flags));
}

// realpath under its Darwin name for programs built for 10.5 and later.
char *darwin_realpath(const char *path, char *resolved) __asm__("_realpath$DARWIN_EXTSN")
    __attribute__((visibility("default"), used));
char *darwin_realpath(const char *path, char *resolved) {
    return realpath(path, resolved);
}

char *darwin_realpath_plain(const char *path, char *resolved) DARWIN_SYMBOL(realpath);
char *darwin_realpath_plain(const char *path, char *resolved) {
    return realpath(path, resolved);
}

// MARK: - Directories

struct darwin_dirent {
    uint64_t d_ino;
    uint64_t d_seekoff;
    uint16_t d_reclen;
    uint16_t d_namlen;
    uint8_t d_type;
    char d_name[1024];
};

_Static_assert(offsetof(struct darwin_dirent, d_name) == 21, "d_name is at 21 on Darwin");

// A Darwin DIR: glibc's stream and the entry readdir returns.
typedef struct darwin_dir {
    DIR *dir;
    struct darwin_dirent entry;
} darwin_dir;

static darwin_dir *wrap_dir(DIR *dir) {
    if (!dir)
        return NULL;
    darwin_dir *wrapped = calloc(1, sizeof(*wrapped));
    if (!wrapped) {
        closedir(dir);
        errno = ENOMEM;
        return NULL;
    }
    wrapped->dir = dir;
    return wrapped;
}

static void entry_to_darwin(const struct dirent *entry, struct darwin_dirent *out) {
    size_t length = strnlen(entry->d_name, sizeof(out->d_name) - 1);
    out->d_ino = entry->d_ino;
    out->d_seekoff = (uint64_t)entry->d_off;
    out->d_namlen = (uint16_t)length;
    out->d_type = entry->d_type;    // DT_* values agree
    memcpy(out->d_name, entry->d_name, length);
    out->d_name[length] = 0;
    // The record length Darwin's getdirentries reports: rounded to 4.
    out->d_reclen = (uint16_t)((offsetof(struct darwin_dirent, d_name) + length + 1 + 3) & ~3u);
}

darwin_dir *darwin_opendir(const char *path) DARWIN_SYMBOL(opendir);
darwin_dir *darwin_opendir(const char *path) {
    return wrap_dir(opendir(path));
}

darwin_dir *darwin_fdopendir(int fd) DARWIN_SYMBOL(fdopendir);
darwin_dir *darwin_fdopendir(int fd) {
    return wrap_dir(fdopendir(fd));
}

struct darwin_dirent *darwin_readdir(darwin_dir *dir) DARWIN_SYMBOL(readdir);
struct darwin_dirent *darwin_readdir(darwin_dir *dir) {
    struct dirent *entry = readdir(dir->dir);
    if (!entry)
        return NULL;
    entry_to_darwin(entry, &dir->entry);
    return &dir->entry;
}

int darwin_readdir_r(darwin_dir *dir, struct darwin_dirent *entry, struct darwin_dirent **result) DARWIN_SYMBOL(readdir_r);
int darwin_readdir_r(darwin_dir *dir, struct darwin_dirent *entry, struct darwin_dirent **result) {
    int saved = errno;
    errno = 0;
    struct dirent *found = readdir(dir->dir);
    int error = errno;
    errno = saved;
    if (!found) {
        *result = NULL;
        return perry_darwin_errno_from_linux(error);
    }
    entry_to_darwin(found, entry);
    *result = entry;
    return 0;
}

int darwin_closedir(darwin_dir *dir) DARWIN_SYMBOL(closedir);
int darwin_closedir(darwin_dir *dir) {
    int result = closedir(dir->dir);
    free(dir);
    return result;
}

void darwin_rewinddir(darwin_dir *dir) DARWIN_SYMBOL(rewinddir);
void darwin_rewinddir(darwin_dir *dir) {
    rewinddir(dir->dir);
}

long darwin_telldir(darwin_dir *dir) DARWIN_SYMBOL(telldir);
long darwin_telldir(darwin_dir *dir) {
    return telldir(dir->dir);
}

void darwin_seekdir(darwin_dir *dir, long position) DARWIN_SYMBOL(seekdir);
void darwin_seekdir(darwin_dir *dir, long position) {
    seekdir(dir->dir, position);
}

int darwin_dirfd(darwin_dir *dir) DARWIN_SYMBOL(dirfd);
int darwin_dirfd(darwin_dir *dir) {
    return dirfd(dir->dir);
}
