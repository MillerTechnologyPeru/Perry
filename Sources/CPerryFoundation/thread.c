// The point +[NSThread exit] returns to. NSThread's threads run their main
// through perry_foundation_thread_run, and exiting jumps back there,
// abandoning the frames above as Darwin's pthread_exit does, without
// unwinding: Mach-O code has only compact unwind information, which
// glibc's forced unwind cannot read.

#include "CPerryFoundation.h"

#include <setjmp.h>
#include <stddef.h>

static __thread jmp_buf *exit_point;

void perry_foundation_thread_run(void (*body)(void *), void *context) {
    jmp_buf point;
    jmp_buf *outer = exit_point;
    if (setjmp(point) == 0) {
        exit_point = &point;
        body(context);
    }
    exit_point = outer;
}

bool perry_foundation_thread_exit(void) {
    if (!exit_point)
        return false;
    longjmp(*exit_point, 1);
}
