// A weak import that no provider defines binds to NULL; calling a missing
// non-weak import reports which symbol was missing.
#include "darwin.h"

extern int perry_fixture_absent(void) __attribute__((weak_import));
extern int perry_fixture_unimplemented(void);

int main(int argc, char **argv) {
    printf("weak import is null: %d\n", perry_fixture_absent == NULL);
    fflush(stdout);
    if (argc > 1 && strcmp(argv[1], "call") == 0)
        return perry_fixture_unimplemented();
    return 0;
}
