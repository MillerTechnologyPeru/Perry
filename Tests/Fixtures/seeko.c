// fseeko and ftello, whose off_t is 64 bits wide on Darwin always.
#include "darwin.h"

typedef long long off_t;

int fclose(FILE *);
int fputs(const char *, FILE *);
int fseeko(FILE *, off_t, int);
off_t ftello(FILE *);
int unlink(const char *);

int main(void) {
    const char *path = "/tmp/perry-seeko-fixture";
    FILE *file = fopen(path, "w+");
    fputs("hello, world", file);
    printf("seek %d %lld\n", fseeko(file, 2, 0), ftello(file));
    printf("seek %d %lld\n", fseeko(file, -1, 2), ftello(file));
    printf("seek %d %lld\n", fseeko(file, 3, 1), ftello(file));
    fclose(file);
    unlink(path);
    return 0;
}
