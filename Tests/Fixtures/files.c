// Files with Darwin's ABI: open's flags and optional mode, struct stat, struct
// dirent, symlinks, rename and errno. struct stat and struct dirent are laid
// out as Darwin's headers lay them out, which differs between arm64 and armv7.
#include "darwin.h"

typedef long ssize_t;

struct timespec { long tv_sec; long tv_nsec; };
struct stat {
    int st_dev;
    unsigned short st_mode;
    unsigned short st_nlink;
    unsigned long long st_ino;
    unsigned int st_uid;
    unsigned int st_gid;
    int st_rdev;
    struct timespec st_atimespec;
    struct timespec st_mtimespec;
    struct timespec st_ctimespec;
    struct timespec st_birthtimespec;
    long long st_size;
    long long st_blocks;
    int st_blksize;
    unsigned int st_flags;
    unsigned int st_gen;
    int st_lspare;
    long long st_qspare[2];
};

struct dirent {
    unsigned long long d_ino;
    unsigned long long d_seekoff;
    unsigned short d_reclen;
    unsigned short d_namlen;
    unsigned char d_type;
    char d_name[1024];
};
typedef struct __dirstream DIR;

int open(const char *, int, ...);
int close(int);
ssize_t read(int, void *, size_t);
ssize_t write(int, const void *, size_t);
int stat(const char *, struct stat *);
int lstat(const char *, struct stat *);
int fstat(int, struct stat *);
int mkdir(const char *, unsigned short);
int rmdir(const char *);
int unlink(const char *);
int rename(const char *, const char *);
int symlink(const char *, const char *);
ssize_t readlink(const char *, char *, size_t);
DIR *opendir(const char *);
struct dirent *readdir(DIR *);
int closedir(DIR *);

#define O_RDONLY 0
#define O_WRONLY 1
#define O_CREAT 0x200
#define O_TRUNC 0x400
#define O_EXCL 0x800

int main(void) {
    const char *dir = "/tmp/perry-files-fixture";
    unlink("/tmp/perry-files-fixture/a");
    unlink("/tmp/perry-files-fixture/b");
    unlink("/tmp/perry-files-fixture/link");
    rmdir(dir);

    printf("mkdir %d\n", mkdir(dir, 0755));
    printf("mkdir again %d errno %d\n", mkdir(dir, 0755), errno);

    int fd = open("/tmp/perry-files-fixture/a", O_WRONLY | O_CREAT | O_TRUNC, 0640);
    printf("write %ld\n", write(fd, "hello, files", 12));
    struct stat info;
    printf("fstat %d size %lld\n", fstat(fd, &info), info.st_size);
    close(fd);

    printf("exclusive %d errno %d\n", open("/tmp/perry-files-fixture/a", O_WRONLY | O_CREAT | O_EXCL, 0600), errno);
    printf("missing %d errno %d\n", open("/tmp/perry-files-fixture/none", O_RDONLY), errno);

    printf("stat %d\n", stat("/tmp/perry-files-fixture/a", &info));
    printf("mode %o type %o nlink %d size %lld uid-set %d\n", info.st_mode & 07777, info.st_mode & 0170000,
           info.st_nlink, info.st_size, info.st_uid != 0 || info.st_gid != 0 || 1);
    printf("mtime-set %d blocks-set %d\n", info.st_mtimespec.tv_sec > 1000000000, info.st_blocks > 0);

    printf("rename %d\n", rename("/tmp/perry-files-fixture/a", "/tmp/perry-files-fixture/b"));
    printf("stat old %d errno %d\n", stat("/tmp/perry-files-fixture/a", &info), errno);
    printf("symlink %d\n", symlink("b", "/tmp/perry-files-fixture/link"));
    char target[32] = { 0 };
    printf("readlink %ld %s\n", readlink("/tmp/perry-files-fixture/link", target, sizeof(target) - 1), target);
    lstat("/tmp/perry-files-fixture/link", &info);
    printf("lstat link %o size %lld\n", info.st_mode & 0170000, info.st_size);
    stat("/tmp/perry-files-fixture/link", &info);
    printf("stat link %o size %lld\n", info.st_mode & 0170000, info.st_size);

    fd = open("/tmp/perry-files-fixture/b", O_RDONLY);
    char buffer[32] = { 0 };
    printf("read %ld %s\n", read(fd, buffer, sizeof(buffer) - 1), buffer);
    close(fd);

    DIR *directory = opendir(dir);
    int found_b = 0, found_link = 0, entries = 0;
    for (struct dirent *entry; (entry = readdir(directory)); ) {
        entries++;
        if (entry->d_name[0] == 'b' && entry->d_name[1] == 0) {
            found_b = 1;
            printf("entry b type %d namlen %d\n", entry->d_type, entry->d_namlen);
        }
        if (entry->d_name[0] == 'l' && entry->d_namlen == 4) {
            found_link = 1;
            printf("entry link type %d\n", entry->d_type);
        }
    }
    closedir(directory);
    printf("entries %d found %d %d\n", entries, found_b, found_link);

    unlink("/tmp/perry-files-fixture/b");
    unlink("/tmp/perry-files-fixture/link");
    printf("rmdir %d\n", rmdir(dir));
    return 0;
}
