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
    perry_system_main_header = info->main_header;
    perry_system_load_library = info->version >= 3 ? info->load_library : NULL;
    perry_system_lookup_after = info->version >= 3 ? info->lookup_symbol_after : NULL;
}

void *(*perry_system_lookup)(const char *install_name, const char *name);
const void *perry_system_main_header;
bool (*perry_system_load_library)(const char *path);
void *(*perry_system_lookup_after)(const void *caller, const char *name);

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

// The unwinder is the host's (libgcc's), which the loader describes Mach-O
// images' frames to: _Unwind_Resume, which cleanups end by calling, and the
// rest of its interface are its own, in thunks.S.

#if defined(__arm__)
// armv7's unwinder is the one below, so _Unwind_Resume, which only code
// built for the other one calls, has nothing to resume.
_Noreturn void darwin_unwind_resume(void *exception) DARWIN_SYMBOL(_Unwind_Resume);
_Noreturn void darwin_unwind_resume(void *exception) {
    fputs("perry: _Unwind_Resume called; armv7 unwinds with setjmp and longjmp\n", stderr);
    abort();
}

// MARK: - setjmp and longjmp unwinding

// Darwin's armv7 code unwinds with setjmp and longjmp: a function with
// cleanups or handlers registers a context when it starts and unregisters it
// when it returns, and stores in it the number of the call it is making.
// Raising an exception walks the registered contexts, most recent first,
// asking each one's personality routine (with its language-specific data) in
// two phases, as libunwind's Unwind-sjlj.c does: the search phase finds the
// context that handles the exception; the cleanup phase runs the cleanups of
// those before it and then that one's handler. Installing a context
// longjmps to its dispatch code with the personality's call site and
// parameters (the exception and the handler's selector) in it.
struct unwind_exception {
    uint64_t exception_class;
    void (*exception_cleanup)(int, struct unwind_exception *);
    uintptr_t private_1;        // a forced unwind's stop function: none here
    uintptr_t private_2;        // the context the search phase found
};

struct sjlj_function_context {
    struct sjlj_function_context *prev;
    uint32_t call_site;
    uintptr_t data[4];
    int (*personality)(int, int, uint64_t, struct unwind_exception *, struct sjlj_function_context *);
    uintptr_t lsda;
    void *jbuf[5];              // r7, the dispatch address, sp
};

enum {
    URC_FOREIGN_EXCEPTION_CAUGHT = 1, URC_FATAL_PHASE2_ERROR = 2, URC_FATAL_PHASE1_ERROR = 3,
    URC_END_OF_STACK = 5, URC_HANDLER_FOUND = 6, URC_INSTALL_CONTEXT = 7, URC_CONTINUE_UNWIND = 8,
};
enum { UA_SEARCH_PHASE = 1, UA_CLEANUP_PHASE = 2, UA_HANDLER_FRAME = 4 };

static __thread struct sjlj_function_context *sjlj_top;

// Restores r7 and sp from the context's buffer and jumps to its dispatch
// code (thunks_arm.S).
_Noreturn void perry_sjlj_longjmp(void **jbuf);

void darwin_sjlj_register(struct sjlj_function_context *context) DARWIN_SYMBOL(_Unwind_SjLj_Register);
void darwin_sjlj_register(struct sjlj_function_context *context) {
    context->prev = sjlj_top;
    sjlj_top = context;
}

void darwin_sjlj_unregister(struct sjlj_function_context *context) DARWIN_SYMBOL(_Unwind_SjLj_Unregister);
void darwin_sjlj_unregister(struct sjlj_function_context *context) {
    sjlj_top = context->prev;
}

static int unwind_phase2(struct unwind_exception *exception) {
    for (struct sjlj_function_context *context = sjlj_top; context; context = context->prev) {
        if (!context->personality)
            continue;
        int handler = context == (struct sjlj_function_context *)exception->private_2;
        int result = context->personality(1, UA_CLEANUP_PHASE | (handler ? UA_HANDLER_FRAME : 0),
                                          exception->exception_class, exception, context);
        if (result == URC_INSTALL_CONTEXT) {
            sjlj_top = context;
            perry_sjlj_longjmp(context->jbuf);
        }
        if (result != URC_CONTINUE_UNWIND || handler)
            return URC_FATAL_PHASE2_ERROR;
    }
    return URC_FATAL_PHASE2_ERROR;
}

// Returns only when no context handles the exception (or a personality
// fails): the thrower then reports it as uncaught.
int darwin_sjlj_raise(struct unwind_exception *exception) DARWIN_SYMBOL(_Unwind_SjLj_RaiseException);
int darwin_sjlj_raise(struct unwind_exception *exception) {
    exception->private_1 = 0;
    exception->private_2 = 0;
    for (struct sjlj_function_context *context = sjlj_top; context; context = context->prev) {
        if (!context->personality)
            continue;
        int result = context->personality(1, UA_SEARCH_PHASE, exception->exception_class, exception, context);
        if (result == URC_HANDLER_FOUND) {
            exception->private_2 = (uintptr_t)context;
            return unwind_phase2(exception);
        }
        if (result != URC_CONTINUE_UNWIND)
            return URC_FATAL_PHASE1_ERROR;
    }
    return URC_END_OF_STACK;
}

// A cleanup's end: the cleanup phase continues past its context.
_Noreturn void darwin_sjlj_resume(struct unwind_exception *exception) DARWIN_SYMBOL(_Unwind_SjLj_Resume);
_Noreturn void darwin_sjlj_resume(struct unwind_exception *exception) {
    unwind_phase2(exception);
    fputs("perry: _Unwind_SjLj_Resume could not continue unwinding\n", stderr);
    abort();
}

int darwin_sjlj_resume_or_rethrow(struct unwind_exception *exception) DARWIN_SYMBOL(_Unwind_SjLj_Resume_or_Rethrow);
int darwin_sjlj_resume_or_rethrow(struct unwind_exception *exception) {
    return darwin_sjlj_raise(exception);
}

void darwin_unwind_delete_exception(struct unwind_exception *exception) DARWIN_SYMBOL(_Unwind_DeleteException);
void darwin_unwind_delete_exception(struct unwind_exception *exception) {
    if (exception->exception_cleanup)
        exception->exception_cleanup(URC_FOREIGN_EXCEPTION_CAUGHT, exception);
}

// What a personality routine reads and sets in a context. Its instruction
// pointer is the call site's number plus one.
uintptr_t darwin_unwind_get_lsda(struct sjlj_function_context *context) DARWIN_SYMBOL(_Unwind_GetLanguageSpecificData);
uintptr_t darwin_unwind_get_lsda(struct sjlj_function_context *context) { return context->lsda; }

uintptr_t darwin_unwind_get_ip(struct sjlj_function_context *context) DARWIN_SYMBOL(_Unwind_GetIP);
uintptr_t darwin_unwind_get_ip(struct sjlj_function_context *context) { return context->call_site + 1; }

uintptr_t darwin_unwind_get_ip_info(struct sjlj_function_context *context, int *before) DARWIN_SYMBOL(_Unwind_GetIPInfo);
uintptr_t darwin_unwind_get_ip_info(struct sjlj_function_context *context, int *before) {
    *before = 0;
    return context->call_site + 1;
}

void darwin_unwind_set_ip(struct sjlj_function_context *context, uintptr_t value) DARWIN_SYMBOL(_Unwind_SetIP);
void darwin_unwind_set_ip(struct sjlj_function_context *context, uintptr_t value) { context->call_site = (uint32_t)(value - 1); }

uintptr_t darwin_unwind_get_gr(struct sjlj_function_context *context, int index) DARWIN_SYMBOL(_Unwind_GetGR);
uintptr_t darwin_unwind_get_gr(struct sjlj_function_context *context, int index) { return context->data[index & 3]; }

void darwin_unwind_set_gr(struct sjlj_function_context *context, int index, uintptr_t value) DARWIN_SYMBOL(_Unwind_SetGR);
void darwin_unwind_set_gr(struct sjlj_function_context *context, int index, uintptr_t value) { context->data[index & 3] = value; }

uintptr_t darwin_unwind_get_region_start(struct sjlj_function_context *context) DARWIN_SYMBOL(_Unwind_GetRegionStart);
uintptr_t darwin_unwind_get_region_start(struct sjlj_function_context *context) { (void)context; return 0; }

uintptr_t darwin_unwind_get_cfa(struct sjlj_function_context *context) DARWIN_SYMBOL(_Unwind_GetCFA);
uintptr_t darwin_unwind_get_cfa(struct sjlj_function_context *context) { return (uintptr_t)context->jbuf[2]; }
#endif
