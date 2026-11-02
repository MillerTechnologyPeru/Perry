// kSecRandomDefault: a constant SecRandomRef, NULL, under its Darwin name.

#include "CPerrySecurity.h"

const void *const perry_random_default __asm__("_kSecRandomDefault")
    __attribute__((visibility("default"), used)) = 0;
