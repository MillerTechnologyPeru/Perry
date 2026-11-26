// errno uses Darwin numbering through __error().
#include "darwin.h"

int main(void) {
    errno = 0;
    long v = strtol("99999999999999999999999", NULL, 10);
    printf("strtol overflow errno=%d (ERANGE=%d) value-positive=%d\n", errno, ERANGE, v > 0);

    errno = 0;
    strtol("12", NULL, 10);
    printf("after success errno=%d\n", errno);

    FILE *f = fopen("/nonexistent/perry/fixture", "r");
    printf("fopen null=%d errno=%d (ENOENT=%d) message=%s\n", f == NULL, errno, ENOENT, strerror(errno));

    // The same failure again, after the program cleared errno.
    errno = 0;
    fopen("/nonexistent/perry/fixture", "r");
    printf("repeated failure errno=%d\n", errno);

    errno = 35; // Darwin EAGAIN
    printf("darwin EAGAIN message=%s\n", strerror(errno));
    return 0;
}
