// libGreet.dylib, embedded in Greeter.app/Frameworks.
#include "darwin.h"

int greet_count = 100;

__attribute__((constructor)) static void greet_init(void) {
    greet_count += 1;
    puts("libGreet initializer");
}

const char *greet_message(void) {
    return "hello from libGreet";
}
