// Signals Linux has no number for, and pathconf, as Darwin has them: a
// handler for SIGINFO (which xz sets, to report its progress) is accepted
// and handed back, and pathconf answers with Darwin's limits. It prints the
// same on any Darwin, so a Mac records what it prints.
#include "darwin.h"

struct sigaction_darwin { void (*handler)(int); unsigned int mask; int flags; };
int sigaction(int, const struct sigaction_darwin *, struct sigaction_darwin *);
long pathconf(const char *, int);
long fpathconf(int, int);
int open(const char *, int, ...);

static void progress(int signal) { (void)signal; }

int main(void) {
    struct sigaction_darwin action = { progress, 0, 0 }, previous = { (void (*)(int))1, 0, 0 };
    int query = sigaction(29, 0, &previous);
    printf("siginfo query %d handler %d\n", query, previous.handler == 0);
    int set = sigaction(29, &action, 0);
    int again = sigaction(29, 0, &previous);
    printf("siginfo set %d query %d handler kept %d\n", set, again, previous.handler == progress);
    action.handler = (void (*)(int))1; // SIG_IGN
    sigaction(29, &action, &previous);
    printf("siginfo replaced %d\n", previous.handler == progress);

    errno = 0;
    printf("path max %ld name max %ld\n", pathconf("/", 5), pathconf("/", 4));
    int root = open("/", 0);
    printf("fd path max %ld name max %ld\n", fpathconf(root, 5), fpathconf(root, 4));
    errno = 0;
    long missing = pathconf("/nonexistent/perry/fixture", 4);
    printf("missing path %ld errno %d\n", missing, errno);
    errno = 0;
    long bad = pathconf("/", 9999);
    printf("unknown name %ld errno %d\n", bad, errno);
    errno = 0;
    long vdisable = pathconf("/", 9);
    printf("vdisable of a directory %ld errno %d\n", vdisable, errno);
    return 0;
}
