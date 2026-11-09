// File metadata with both of i386 Darwin's layouts: the plain names programs
// for systems before 10.6 use, and the $INODE64 names of later ones. A guard
// after each buffer catches a function writing a larger layout than asked for.
#include "darwin.h"

struct timespec { long tv_sec; long tv_nsec; };

struct stat32 {
    int st_dev; unsigned st_ino; unsigned short st_mode, st_nlink; unsigned st_uid, st_gid; int st_rdev;
    struct timespec st_atimespec, st_mtimespec, st_ctimespec;
    long long st_size, st_blocks; int st_blksize; unsigned st_flags, st_gen; int st_lspare; long long st_qspare[2];
};

struct stat64 {
    int st_dev; unsigned short st_mode, st_nlink; unsigned long long st_ino; unsigned st_uid, st_gid; int st_rdev;
    struct timespec st_atimespec, st_mtimespec, st_ctimespec, st_birthtimespec;
    long long st_size, st_blocks; int st_blksize; unsigned st_flags, st_gen; int st_lspare; long long st_qspare[2];
};

struct dirent32 { unsigned d_ino; unsigned short d_reclen; unsigned char d_type, d_namlen; char d_name[256]; };
struct dirent64 { unsigned long long d_ino, d_seekoff; unsigned short d_reclen, d_namlen; unsigned char d_type; char d_name[1024]; };

struct statfs32 {
    short f_otype, f_oflags; long f_bsize, f_iosize, f_blocks, f_bfree, f_bavail, f_files, f_ffree; int f_fsid[2];
    unsigned f_owner; short f_reserved1, f_type; long f_flags; long f_reserved2[2];
    char f_fstypename[15], f_mntonname[90], f_mntfromname[90], f_reserved3; long f_reserved4[4];
};

typedef struct __dirstream DIR;
int stat(const char *, struct stat32 *);
int lstat(const char *, struct stat32 *);
int stat_new(const char *, struct stat64 *) __asm__("_stat$INODE64");
int statfs(const char *, struct statfs32 *);
int mkdir(const char *, unsigned short);
int rmdir(const char *);
int unlink(const char *);
int open(const char *, int, ...);
int close(int);
long write(int, const void *, unsigned long);
DIR *opendir(const char *);
struct dirent32 *readdir(DIR *);
struct dirent64 *readdir_new(DIR *) __asm__("_readdir$INODE64");
int closedir(DIR *);

int main(void) {
    const char *dir = "/tmp/perry-legacy-files", *file = "/tmp/perry-legacy-files/entry";
    unlink(file); rmdir(dir);
    mkdir(dir, 0755);
    int fd = open(file, 0x601, 0640);
    write(fd, "twelve bytes", 12);
    close(fd);

    struct { struct stat32 info; unsigned guard; } old = { .guard = 0xfeedface };
    printf("old %d size %lld mode %o nlink %d guard %x\n", stat(file, &old.info), old.info.st_size,
           old.info.st_mode, old.info.st_nlink, old.guard);
    struct { struct stat64 info; unsigned guard; } new = { .guard = 0xfeedface };
    printf("new %d size %lld mode %o nlink %d guard %x\n", stat_new(file, &new.info), new.info.st_size,
           new.info.st_mode, new.info.st_nlink, new.guard);
    printf("same inode %d mtime %d\n", new.info.st_ino == old.info.st_ino,
           new.info.st_mtimespec.tv_sec == old.info.st_mtimespec.tv_sec);

    DIR *d = opendir(dir);
    struct dirent32 *e;
    while ((e = readdir(d)))
        if (e->d_name[0] != '.')
            printf("old entry %s type %d namlen %d\n", e->d_name, e->d_type, e->d_namlen);
    closedir(d);
    d = opendir(dir);
    struct dirent64 *f;
    while ((f = readdir_new(d)))
        if (f->d_name[0] != '.')
            printf("new entry %s type %d namlen %d\n", f->d_name, f->d_type, f->d_namlen);
    closedir(d);

    struct { struct statfs32 info; unsigned guard; } fs = { .guard = 0xfeedface };
    int result = statfs("/tmp", &fs.info);
    printf("statfs %d %s positive %d guard %x\n", result, fs.info.f_fstypename,
           fs.info.f_bsize > 0 && fs.info.f_blocks > 0 && fs.info.f_bavail >= 0, fs.guard);

    unlink(file); rmdir(dir);
    return 0;
}
