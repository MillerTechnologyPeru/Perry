// Static initializers, rebased pointer tables and function pointers.
#include "darwin.h"

static const char *names[] = { "alpha", "beta", "gamma" };
static int counter;
static void bump(void) { counter += 10; }
static void (*hooks[])(void) = { bump, bump };
static const char **name_table = names;

__attribute__((constructor)) static void first(void) {
    counter = 1;
    puts("constructor first");
}

__attribute__((constructor)) static void second(void) {
    counter += 1;
    puts("constructor second");
}

int main(void) {
    for (int i = 0; i < 2; i++)
        hooks[i]();
    printf("counter=%d names=%s,%s,%s\n", counter, name_table[0], name_table[1], name_table[2]);
    return 0;
}
