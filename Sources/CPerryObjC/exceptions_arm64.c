// Objective-C exceptions on arm64, where they are C++ exceptions as on
// Darwin: objc_exception_throw throws the object with a type_info of the
// runtime's own (objc_typeinfo, which a @catch clause names through
// OBJC_EHTYPE_$_Class), and the C++ runtime's personality routine asks that
// type_info whether a clause catches it. The frames of Mach-O code are
// described to the unwinder by the loader (unwind.c), so an exception gets
// to a @catch in a program's code as a C++ one gets to a catch.
//
// The C++ runtime is the one programs' C++ uses, libperry-c++abi, opened
// when the first exception is thrown or caught. Without it an exception
// ends the process, as every one did before.

#if defined(__aarch64__) && defined(__ELF__)

#define _GNU_SOURCE
#include "CPerryObjC.h"

#include <dlfcn.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define DARWIN_SYMBOL(name) __asm__(name) __attribute__((visibility("default"), used))

// The runtime's own functions, by their Darwin names.
void *perry_object_getClass(void *object) __asm__("_object_getClass");
void *perry_class_getSuperclass(void *cls) __asm__("_class_getSuperclass");
const char *perry_class_getName(void *cls) __asm__("_class_getName");
void *perry_objc_lookUpClass(const char *name) __asm__("_objc_lookUpClass");
void *perry_objc_retain(void *object) __asm__("_objc_retain");
void *perry_objc_autorelease(void *object) __asm__("_objc_autorelease");

// What a catch clause names, and what an exception is thrown as. The first
// two words are a C++ type_info's.
struct objc_typeinfo {
    const void **vtable;
    const char *name;
    void *cls;
};

// What is thrown: the object, and the type_info made for its class.
struct objc_exception {
    void *object;
    struct objc_typeinfo type;
};

const void *objc_ehtype_vtable[11] DARWIN_SYMBOL("_objc_ehtype_vtable");
const struct objc_typeinfo objc_ehtype_id DARWIN_SYMBOL("_OBJC_EHTYPE_id") = { &objc_ehtype_vtable[2], "id", NULL };

static void nothing(void) {}
static bool never(void) { return false; }

// type_info's can_catch, for a clause's type: whether it catches what was
// thrown, and if so, the object in place of the pointer to what was thrown,
// for objc_begin_catch to return.
static bool catches(const struct objc_typeinfo *clause, const struct objc_typeinfo *thrown, void **adjusted) {
    if (!thrown || thrown->vtable != &objc_ehtype_vtable[2])
        return false;   // a C++ exception
    void *object = ((struct objc_exception *)*adjusted)->object;
    if (clause != &objc_ehtype_id && strcmp(clause->name, "id") != 0) {
        void *wanted = clause->cls ? clause->cls : perry_objc_lookUpClass(clause->name);
        void *cls = object ? perry_object_getClass(object) : NULL;
        while (cls && cls != wanted)
            cls = perry_class_getSuperclass(cls);
        if (!cls || !wanted)
            return false;
    }
    *adjusted = object;
    return true;
}

// type_info's virtual functions, from the third word: two destructors, two
// that do nothing, can_catch, and the searches casting uses.
const void *objc_ehtype_vtable[11] = {
    NULL, &objc_ehtype_id, nothing, nothing, never, never, catches, never, never, never, never,
};

// MARK: - The C++ runtime

static struct {
    void *(*allocate)(size_t);
    void (*throw)(void *, void *, void (*)(void *));
    void (*rethrow)(void);
    void *(*begin_catch)(void *);
    void (*end_catch)(void);
    int (*personality)(int, int, uint64_t, void *, void *);
    const struct objc_typeinfo *(*current_type)(void);
    void *(*current_exception)(void);
    void (*(*set_terminate)(void (*)(void)))(void);
} cxx;

static void (*previous_terminate)(void);

// Where an exception nothing catches ends: an Objective-C one goes to the
// uncaught exception handler, which reports it.
static void terminate(void) {
    const struct objc_typeinfo *type = cxx.current_type ? cxx.current_type() : NULL;
    if (type && type->vtable == &objc_ehtype_vtable[2] && cxx.current_exception) {
        struct objc_exception *exception = cxx.current_exception();
        perry_objc_uncaught_exception(exception ? exception->object : NULL);
    }
    if (previous_terminate)
        previous_terminate();
    abort();
}

static bool load(void) {
    static int state;   // 0: not tried, 1: there, 2: missing
    int now = __atomic_load_n(&state, __ATOMIC_ACQUIRE);
    if (now)
        return now == 1;
    void *library = dlopen("libperry-c++abi.so.1", RTLD_NOW | RTLD_LOCAL);
    if (library) {
        cxx.allocate = dlsym(library, "__cxa_allocate_exception");
        cxx.throw = dlsym(library, "__cxa_throw");
        cxx.rethrow = dlsym(library, "__cxa_rethrow");
        cxx.begin_catch = dlsym(library, "__cxa_begin_catch");
        cxx.end_catch = dlsym(library, "__cxa_end_catch");
        cxx.personality = dlsym(library, "__gxx_personality_v0");
        cxx.current_type = dlsym(library, "__cxa_current_exception_type");
        cxx.current_exception = dlsym(library, "__cxa_current_primary_exception");
        cxx.set_terminate = dlsym(library, "_ZSt13set_terminatePFvvE");
    }
    bool found = cxx.allocate && cxx.throw && cxx.rethrow && cxx.begin_catch && cxx.end_catch && cxx.personality;
    int expected = 0;
    if (__atomic_compare_exchange_n(&state, &expected, found ? 1 : 2, false, __ATOMIC_RELEASE, __ATOMIC_ACQUIRE) &&
        found && cxx.set_terminate)
        previous_terminate = cxx.set_terminate(terminate);
    return found;
}

// MARK: - Throwing and catching

static void destroy(void *thrown) {
    // Kept alive while unwinding, since cleanups pop autorelease pools.
    perry_objc_autorelease(((struct objc_exception *)thrown)->object);
}

_Noreturn void objc_exception_throw(void *object) DARWIN_SYMBOL("_objc_exception_throw");
_Noreturn void objc_exception_throw(void *object) {
    if (!load())
        perry_objc_uncaught_exception(object);
    struct objc_exception *exception = cxx.allocate(sizeof(*exception));
    void *cls = object ? perry_object_getClass(object) : NULL;
    exception->object = perry_objc_retain(object);
    exception->type.vtable = &objc_ehtype_vtable[2];
    exception->type.name = cls ? perry_class_getName(cls) : "id";
    exception->type.cls = cls;
    cxx.throw(exception, &exception->type, destroy);
    abort();
}

// Called inside a @catch block, with the exception it is handling.
_Noreturn void objc_exception_rethrow(void) DARWIN_SYMBOL("_objc_exception_rethrow");
_Noreturn void objc_exception_rethrow(void) {
    if (!load())
        perry_objc_uncaught_exception(NULL);
    cxx.rethrow();
    abort();
}

void *objc_begin_catch(void *exception) DARWIN_SYMBOL("_objc_begin_catch");
void *objc_begin_catch(void *exception) {
    return load() ? cxx.begin_catch(exception) : NULL;
}

void objc_end_catch(void) DARWIN_SYMBOL("_objc_end_catch");
void objc_end_catch(void) {
    if (load())
        cxx.end_catch();
}

// The personality routine Objective-C code's unwind tables name: the C++
// one, which reads the same tables.
int objc_personality_v0(int version, int actions, uint64_t exception_class, void *exception, void *context)
    DARWIN_SYMBOL("___objc_personality_v0");
int objc_personality_v0(int version, int actions, uint64_t exception_class, void *exception, void *context) {
    if (!load())
        perry_objc_uncaught_exception(NULL);
    return cxx.personality(version, actions, exception_class, exception, context);
}

#endif
