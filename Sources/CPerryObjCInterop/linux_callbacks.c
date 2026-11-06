#include "CPerryObjCInterop.h"

#if defined(__arm__)
// r9 is saved with the return address, which keeps the stack 8-byte aligned.
__attribute__((naked)) void perry_keep_r9(void (*function)(void *), void *context) {
    __asm__ volatile(
        "push {r9, lr}\n"
        "mov r12, r0\n"
        "mov r0, r1\n"
        "blx r12\n"
        "pop {r9, pc}\n");
}
#else
void perry_keep_r9(void (*function)(void *), void *context) { function(context); }
#endif
