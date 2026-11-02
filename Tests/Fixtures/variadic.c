// Darwin passes variadic arguments on the stack; glibc expects registers.
#include "darwin.h"

static int format(char *buf, size_t size, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(buf, size, fmt, ap);
    va_end(ap);
    return n;
}

int main(void) {
    printf("ints %d %d %d %d %d %d %d %d %d %d\n", 1, 2, 3, 4, 5, 6, 7, 8, 9, 10);
    printf("mixed %s %.2f %ld %c %.1f %u\n", "str", 3.14159, 1234567890123L, 'x', -2.5, 42u);
    char buf[64];
    int n = snprintf(buf, sizeof(buf), "%s-%d-%.3f", "snprintf", 99, 0.125);
    printf("%s (%d)\n", buf, n);
    format(buf, sizeof(buf), "%s|%d|%g", "vsnprintf", -7, 1e10);
    puts(buf);
    fprintf(stderr, "to stderr %d\n", 5);
    return 0;
}
