// Process startup state, stack protector and dyld entry points.

#define _GNU_SOURCE
#include "PerrySystem.h"
#include "perry_interface.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/random.h>

// MARK: - Program variables

static int program_argc;
static char **program_argv;
static const char *program_executable_path;

char **darwin_environ DARWIN_SYMBOL(environ);
const char *darwin_progname DARWIN_SYMBOL(__progname);

__attribute__((visibility("default")))
void perry_provider_startup(const perry_startup_info *info) {
    if (info->version < PERRY_STARTUP_INFO_VERSION)
        return;
    program_argc = info->argc;
    program_argv = info->argv;
    program_executable_path = info->executable_path;
    darwin_environ = info->envp;
    darwin_progname = info->progname;
}

int *darwin_NSGetArgc(void) DARWIN_SYMBOL(_NSGetArgc);
int *darwin_NSGetArgc(void) { return &program_argc; }

char ***darwin_NSGetArgv(void) DARWIN_SYMBOL(_NSGetArgv);
char ***darwin_NSGetArgv(void) { return &program_argv; }

char ***darwin_NSGetEnviron(void) DARWIN_SYMBOL(_NSGetEnviron);
char ***darwin_NSGetEnviron(void) { return &darwin_environ; }

const char **darwin_NSGetProgname(void) DARWIN_SYMBOL(_NSGetProgname);
const char **darwin_NSGetProgname(void) { return &darwin_progname; }

int darwin_NSGetExecutablePath(char *buf, uint32_t *size) DARWIN_SYMBOL(_NSGetExecutablePath);
int darwin_NSGetExecutablePath(char *buf, uint32_t *size) {
    const char *path = program_executable_path ? program_executable_path : "";
    uint32_t needed = (uint32_t)strlen(path) + 1;
    if (*size < needed) {
        *size = needed;
        return -1;
    }
    memcpy(buf, path, needed);
    return 0;
}

// MARK: - Stack protector

uintptr_t darwin_stack_chk_guard DARWIN_SYMBOL(__stack_chk_guard);

__attribute__((constructor)) static void init_stack_guard(void) {
    uintptr_t value = 0;
    if (getrandom(&value, sizeof(value), 0) != sizeof(value))
        value = (uintptr_t)&value ^ 0x5a17c0de5a17c0deull;
    value &= ~(uintptr_t)0xff; // a zero byte stops string overflows from copying the canary
    darwin_stack_chk_guard = value;
}

_Noreturn void darwin_stack_chk_fail(void) DARWIN_SYMBOL(__stack_chk_fail);
_Noreturn void darwin_stack_chk_fail(void) {
    fputs("perry: stack buffer overflow detected\n", stderr);
    abort();
}

// MARK: - dyld

// Perry binds lazy pointers when the image loads, so the lazy binding
// helper should never run.
_Noreturn void darwin_dyld_stub_binder(void) __asm__("dyld_stub_binder") __attribute__((visibility("default"), used));
_Noreturn void darwin_dyld_stub_binder(void) {
    fputs("perry: dyld_stub_binder called; lazy binding is not supported\n", stderr);
    abort();
}

// MARK: - Unwinding

// Cleanups in unwind tables end by resuming the exception. Perry cannot
// unwind Mach-O frames, so an exception never gets here, but the symbol
// must resolve.
_Noreturn void darwin_unwind_resume(void *exception) DARWIN_SYMBOL(_Unwind_Resume);
_Noreturn void darwin_unwind_resume(void *exception) {
    fputs("perry: _Unwind_Resume called; unwinding Mach-O frames is not supported\n", stderr);
    abort();
}
