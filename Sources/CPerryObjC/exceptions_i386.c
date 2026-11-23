// Objective-C exceptions on i386 and ppc, whose old ABI has no unwind tables:
// each @try sets a jmp_buf with Darwin's setjmp, registers it with
// objc_exception_try_enter, and a throw longjmps to the innermost one.

#if (defined(__i386__) || (defined(__powerpc__) && !defined(__powerpc64__))) && defined(__ELF__)

#include "CPerryObjC.h"

#define DARWIN_SYMBOL(name) __asm__(name) __attribute__((visibility("default"), used))

// What the compiler reserves in a function with @try: a jmp_buf (Darwin's
// _JBLEN words), then words for the runtime. The exception is in
// pointers[0], the next outer handler in pointers[1].
#if defined(__i386__)
#define JMP_BUF_WORDS 18
_Noreturn void perry_objc_i386_longjmp(int *buffer);
#define exception_longjmp perry_objc_i386_longjmp
#else
#define JMP_BUF_WORDS 192
_Noreturn void perry_objc_ppc_longjmp(int *buffer);
#define exception_longjmp perry_objc_ppc_longjmp
#endif

struct exception_data {
    int buffer[JMP_BUF_WORDS];
    void *pointers[4];
};

static __thread struct exception_data *innermost;

void objc_exception_try_enter(void *data) DARWIN_SYMBOL("_objc_exception_try_enter");
void objc_exception_try_enter(void *data) {
    struct exception_data *handler = data;
    handler->pointers[0] = NULL;
    handler->pointers[1] = innermost;
    innermost = handler;
}

void objc_exception_try_exit(void *data) DARWIN_SYMBOL("_objc_exception_try_exit");
void objc_exception_try_exit(void *data) {
    innermost = ((struct exception_data *)data)->pointers[1];
}

void *objc_exception_extract(void *data) DARWIN_SYMBOL("_objc_exception_extract");
void *objc_exception_extract(void *data) {
    return ((struct exception_data *)data)->pointers[0];
}

_Noreturn void objc_exception_throw(void *object) DARWIN_SYMBOL("_objc_exception_throw");
_Noreturn void objc_exception_throw(void *object) {
    object = perry_objc_preprocess_exception(object);
    struct exception_data *handler = innermost;
    if (!handler)
        perry_objc_uncaught_exception(object);
    innermost = handler->pointers[1];
    handler->pointers[0] = object;
    exception_longjmp(handler->buffer);
}

_Noreturn void objc_exception_rethrow(void) DARWIN_SYMBOL("_objc_exception_rethrow");
_Noreturn void objc_exception_rethrow(void) {
    perry_objc_uncaught_exception(NULL);
}

// Whether `exception` is an instance of `cls` or of one of its subclasses.
int objc_exception_match(perry_objc_class *cls, void *exception) DARWIN_SYMBOL("_objc_exception_match");
int objc_exception_match(perry_objc_class *cls, void *exception) {
    if (!exception)
        return 0;
    for (perry_objc_class *current = *(perry_objc_class **)exception; current; current = current->superclass)
        if (current == cls)
            return 1;
    return 0;
}

#endif
