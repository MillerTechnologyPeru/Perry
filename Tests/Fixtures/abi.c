// Calls whose arguments and results are 64 bits wide, which Darwin's armv7 ABI
// passes differently from Linux's: printf's long long and floating point
// conversions, and the off_t of lseek, pread, pwrite, ftruncate
// and mmap.
#include "darwin.h"

typedef long long off_t;
typedef long ssize_t;

int fclose(FILE *);
int fileno(FILE *);
int fputs(const char *, FILE *);
off_t lseek(int, off_t, int);
ssize_t pread(int, void *, size_t, off_t);
ssize_t pwrite(int, const void *, size_t, off_t);
int ftruncate(int, off_t);
int unlink(const char *);
void *mmap(void *, size_t, int, int, int, off_t);
int munmap(void *, size_t);

int main(void) {
    printf("%d %u %x %c %s|\n", -5, 4000000000u, 255, 'A', "str");
    printf("%lld %llu %lld\n", 1234567890123LL, 18446744073709551615ULL, -9876543210LL);
    printf("%f %.3f %g %e\n", 3.14159, 2.0 / 3, 1e10, 12345.678);
    printf("%5.1f|%-8d|%08.3f|%+d\n", 2.25, 42, 3.14159, 7);
    printf("%d %f %lld %s %f\n", 1, 0.5, 5000000000LL, "mix", 1.5);
    printf("%*d|%.*f|%-*s|\n", 6, 42, 2, 3.14159, 5, "ab");
    printf("%ld %lu %zu %hhd %hd\n", -7L, 7UL, (size_t)9, (signed char)-3, (short)-4);
    printf("%p %%\n", (void *)0x1234);

    char text[64];
    snprintf(text, sizeof(text), "%lld-%.2f-%d", 77LL, 1.5, 9);
    printf("%s\n", text);

    const char *path = "/tmp/perry-abi-fixture";
    FILE *file = fopen(path, "w+");
    fputs("hello, world", file);
    fflush(file);
    int fd = fileno(file);
    printf("end %lld\n", lseek(fd, 0, 2));
    printf("far %lld\n", lseek(fd, 5000000000LL, 0));
    printf("wrote %ld\n", pwrite(fd, "X", 1, 5000000001LL));
    char byte[2] = { 0, 0 };
    printf("read %ld %c\n", pread(fd, byte, 1, 5000000001LL), byte[0]);
    char word[8] = { 0 };
    printf("read %ld %s\n", pread(fd, word, 5, 7), word);
    printf("truncate %d\n", ftruncate(fd, 5));
    printf("end %lld\n", lseek(fd, 0, 2));
    fclose(file);
    unlink(path);

    // MAP_PRIVATE | MAP_ANON, read and write.
    char *page = mmap(0, 4096, 3, 0x1002, -1, 0);
    page[0] = 'k';
    page[4095] = 'z';
    printf("mmap %c %c %d\n", page[0], page[4095], munmap(page, 4096));
    return 0;
}
