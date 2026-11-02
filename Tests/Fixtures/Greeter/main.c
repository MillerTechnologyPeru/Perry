#include "darwin.h"

extern int greet_count;
const char *greet_message(void);

__attribute__((constructor)) static void main_init(void) {
    printf("app initializer sees greet_count=%d\n", greet_count);
}

int main(int argc, char **argv) {
    printf("%s, count=%d\n", greet_message(), greet_count);
    printf("argv0 ends with Greeter.app/Greeter: %d\n",
           strlen(argv[0]) >= 19 && strcmp(argv[0] + strlen(argv[0]) - 19, "Greeter.app/Greeter") == 0);
    return 0;
}
