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

// glibc defines _environ and __progname too, and this library's own uses
// of a default-visibility name bind to the first definition loaded:
// glibc's. These aliases are this library's variables.
extern char **local_environ __attribute__((alias("_environ"), visibility("hidden")));
extern const char *local_progname __attribute__((alias("___progname"), visibility("hidden")));

__attribute__((visibility("default")))
void perry_provider_startup(const perry_startup_info *info) {
    if (info->version < PERRY_STARTUP_INFO_VERSION)
        return;
    program_argc = info->argc;
    program_argv = info->argv;
    program_executable_path = info->executable_path;
    local_environ = info->envp;
    local_progname = info->progname;
    perry_system_lookup = info->lookup_symbol;
}

void *(*perry_system_lookup)(const char *install_name, const char *name);

int *darwin_NSGetArgc(void) DARWIN_SYMBOL(_NSGetArgc);
int *darwin_NSGetArgc(void) { return &program_argc; }

char ***darwin_NSGetArgv(void) DARWIN_SYMBOL(_NSGetArgv);
char ***darwin_NSGetArgv(void) { return &program_argv; }

char ***darwin_NSGetEnviron(void) DARWIN_SYMBOL(_NSGetEnviron);
char ***darwin_NSGetEnviron(void) { return &local_environ; }

const char **darwin_NSGetProgname(void) DARWIN_SYMBOL(_NSGetProgname);
const char **darwin_NSGetProgname(void) { return &local_progname; }

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

#if defined(__arm__)
// MARK: - setjmp and longjmp unwinding

// Darwin's armv7 code unwinds with setjmp and longjmp: a function with cleanups
// registers a context when it starts and unregisters it when it ends, and
// exceptions longjmp to the registered contexts' landing pads. The contexts
// chain through their first member, most recent first.
struct sjlj_function_context {
    struct sjlj_function_context *prev;
};

static __thread struct sjlj_function_context *sjlj_top;

void darwin_sjlj_register(struct sjlj_function_context *context) DARWIN_SYMBOL(_Unwind_SjLj_Register);
void darwin_sjlj_register(struct sjlj_function_context *context) {
    context->prev = sjlj_top;
    sjlj_top = context;
}

void darwin_sjlj_unregister(struct sjlj_function_context *context) DARWIN_SYMBOL(_Unwind_SjLj_Unregister);
void darwin_sjlj_unregister(struct sjlj_function_context *context) {
    sjlj_top = context->prev;
}

// Raising an exception through registered frames is not implemented, so
// neither is resuming one.
_Noreturn void darwin_sjlj_resume(void *exception) DARWIN_SYMBOL(_Unwind_SjLj_Resume);
_Noreturn void darwin_sjlj_resume(void *exception) {
    fputs("perry: _Unwind_SjLj_Resume called; exceptions are not supported\n", stderr);
    abort();
}

int darwin_sjlj_raise(void *exception) DARWIN_SYMBOL(_Unwind_SjLj_RaiseException);
int darwin_sjlj_raise(void *exception) {
    fputs("perry: _Unwind_SjLj_RaiseException called; exceptions are not supported\n", stderr);
    abort();
}
#endif
