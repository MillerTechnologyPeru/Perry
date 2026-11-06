// Objective-C exceptions on armv7, where Darwin's code unwinds with setjmp
// and longjmp through contexts it registers with libSystem (runtime.c):
// objc_exception_throw and rethrow, the catch bookkeeping, and the
// personality routine that reads a function's exception table to find its
// handler for the exception's class. Exception tables are LLVM's SjLj form:
// each call site's dispatch index and actions, the actions' catch types, and
// those types' objc_typeinfo records (OBJC_EHTYPE_$_Class).

#if defined(__arm__) && defined(__ELF__)

#include "CPerryObjC.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define DARWIN_SYMBOL(name) __asm__(name) __attribute__((visibility("default"), used))

// The runtime's own functions, by their Darwin names.
void *perry_object_getClass(void *object) __asm__("_object_getClass");
void *perry_class_getSuperclass(void *cls) __asm__("_class_getSuperclass");
const char *perry_class_getName(void *cls) __asm__("_class_getName");
void *perry_objc_retain(void *object) __asm__("_objc_retain");
void *perry_objc_autorelease(void *object) __asm__("_objc_autorelease");

struct unwind_exception {
    uint64_t exception_class;
    void (*exception_cleanup)(int, struct unwind_exception *);
    uintptr_t private_1, private_2;
};

struct sjlj_function_context {
    struct sjlj_function_context *prev;
    uint32_t call_site;
    uintptr_t data[4];
    void *personality;
    const uint8_t *lsda;
};

enum {
    URC_FATAL_PHASE1_ERROR = 3, URC_HANDLER_FOUND = 6, URC_INSTALL_CONTEXT = 7, URC_CONTINUE_UNWIND = 8,
};
enum { UA_SEARCH_PHASE = 1, UA_CLEANUP_PHASE = 2, UA_HANDLER_FRAME = 4 };

// "NXTSOBJC", as Apple's runtime names its exceptions.
static const uint64_t objc_exception_class = 0x4e5854534f424a43ull;

struct objc_exception {
    struct unwind_exception header;
    void *object;
    // The handler the search phase found: its selector and dispatch index.
    uintptr_t selector;
    uint32_t dispatch;
    int rethrown;
    struct objc_exception *next_caught;
};

// What a catch clause names: objc_typeinfo, whose vtable is
// objc_ehtype_vtable's third word, as Darwin's compilers emit it.
struct objc_typeinfo {
    const void *vtable;
    const char *name;
    void *cls;
};

const void *objc_ehtype_vtable[4] DARWIN_SYMBOL("_objc_ehtype_vtable");
const struct objc_typeinfo objc_ehtype_id DARWIN_SYMBOL("_OBJC_EHTYPE_id") = { &objc_ehtype_vtable[2], "id", NULL };

static perry_objc_raise_function raise_exception;
static __thread struct objc_exception *caught;

void perry_objc_set_unwinder(perry_objc_raise_function raise) { raise_exception = raise; }

// MARK: - Throwing and catching

static void destroy(int reason, struct unwind_exception *header) {
    (void)reason;
    struct objc_exception *exception = (struct objc_exception *)header;
    // Kept alive while unwinding, since cleanups pop autorelease pools.
    perry_objc_autorelease(exception->object);
    free(exception);
}

_Noreturn void objc_exception_throw(void *object) DARWIN_SYMBOL("_objc_exception_throw");
_Noreturn void objc_exception_throw(void *object) {
    struct objc_exception *exception = calloc(1, sizeof(*exception));
    exception->header.exception_class = objc_exception_class;
    exception->header.exception_cleanup = destroy;
    exception->object = perry_objc_retain(object);
    if (raise_exception)
        raise_exception(&exception->header);
    perry_objc_uncaught_exception(object);
}

// Called inside a @catch block, with the exception it is handling.
_Noreturn void objc_exception_rethrow(void) DARWIN_SYMBOL("_objc_exception_rethrow");
_Noreturn void objc_exception_rethrow(void) {
    struct objc_exception *exception = caught;
    if (!exception)
        perry_objc_uncaught_exception(NULL);
    exception->rethrown = 1;
    if (raise_exception)
        raise_exception(&exception->header);
    perry_objc_uncaught_exception(exception->object);
}

void *objc_begin_catch(void *header) DARWIN_SYMBOL("_objc_begin_catch");
void *objc_begin_catch(void *header) {
    struct objc_exception *exception = header;
    if (exception->header.exception_class != objc_exception_class)
        return header;
    exception->rethrown = 0;
    exception->next_caught = caught;
    caught = exception;
    return exception->object;
}

void objc_end_catch(void) DARWIN_SYMBOL("_objc_end_catch");
void objc_end_catch(void) {
    struct objc_exception *exception = caught;
    if (!exception)
        return;
    caught = exception->next_caught;
    // A rethrown exception goes on to the next handler.
    if (!exception->rethrown)
        destroy(0, &exception->header);
}

// MARK: - The personality routine

static uintptr_t read_uleb(const uint8_t **p) {
    uintptr_t value = 0;
    unsigned shift = 0;
    uint8_t byte;
    do {
        byte = *(*p)++;
        value |= (uintptr_t)(byte & 0x7f) << shift;
        shift += 7;
    } while (byte & 0x80);
    return value;
}

static intptr_t read_sleb(const uint8_t **p) {
    intptr_t value = 0;
    unsigned shift = 0;
    uint8_t byte;
    do {
        byte = *(*p)++;
        value |= (intptr_t)(byte & 0x7f) << shift;
        shift += 7;
    } while (byte & 0x80);
    if ((byte & 0x40) && shift < sizeof(value) * 8)
        value |= -((intptr_t)1 << shift);
    return value;
}

// A DWARF-encoded pointer: absolute or pc-relative, 4-byte or LEB128, and
// possibly indirect.
static uintptr_t read_encoded(const uint8_t **p, uint8_t encoding) {
    const uint8_t *start = *p;
    uintptr_t value;
    switch (encoding & 0x0f) {
    case 0x01: value = read_uleb(p); break;
    case 0x09: value = (uintptr_t)read_sleb(p); break;
    default: memcpy(&value, *p, 4); *p += 4; break;     // absptr, udata4, sdata4
    }
    if (value && (encoding & 0x70) == 0x10)             // pcrel
        value += (uintptr_t)start;
    if (value && (encoding & 0x80))                     // indirect
        value = *(const uintptr_t *)value;
    return value;
}

static int type_size(uint8_t encoding) {
    switch (encoding & 0x0f) {
    case 0x02: case 0x0a: return 2;
    case 0x04: case 0x0c: return 8;
    default: return 4;
    }
}

// Whether a catch clause's type takes the object: catch-all (no type), id,
// or the object's class or one of its superclasses, by pointer or, for a
// record with no class (Foundation's NSException's), by name.
static int catches(const struct objc_typeinfo *type, void *object) {
    if (!type)
        return 1;
    if (type == &objc_ehtype_id || (!type->cls && type->name && strcmp(type->name, "id") == 0))
        return 1;
    if (!object)
        return 0;
    for (void *cls = perry_object_getClass(object); cls; cls = perry_class_getSuperclass(cls)) {
        if (type->cls ? cls == type->cls : (type->name && strcmp(perry_class_getName(cls), type->name) == 0))
            return 1;
    }
    return 0;
}

static int install(struct sjlj_function_context *context, struct unwind_exception *header, uintptr_t selector,
                   uint32_t dispatch) {
    context->data[0] = (uintptr_t)header;
    context->data[1] = selector;
    context->call_site = dispatch;
    return URC_INSTALL_CONTEXT;
}

int objc_personality(int version, int actions, uint64_t exception_class, struct unwind_exception *header,
                     struct sjlj_function_context *context) DARWIN_SYMBOL("___objc_personality_v0");
int objc_personality(int version, int actions, uint64_t exception_class, struct unwind_exception *header,
                     struct sjlj_function_context *context) {
    if (version != 1 || !header || !context)
        return URC_FATAL_PHASE1_ERROR;
    int native = exception_class == objc_exception_class;
    struct objc_exception *exception = native ? (struct objc_exception *)header : NULL;
    if ((actions & UA_HANDLER_FRAME) && exception)
        return install(context, header, exception->selector, exception->dispatch);

    const uint8_t *p = context->lsda;
    // The call site being made, numbered from 1; -1 for none that unwinds.
    uint32_t site = context->call_site;
    if (!p || site == (uint32_t)-1)
        return URC_CONTINUE_UNWIND;
    if (site == 0)
        abort();                // a call that must not throw threw

    uint8_t start_encoding = *p++;
    if (start_encoding != 0xff)
        read_encoded(&p, start_encoding);
    uint8_t type_encoding = *p++;
    const uint8_t *types = NULL;
    if (type_encoding != 0xff) {
        uintptr_t offset = read_uleb(&p);
        types = p + offset;
    }
    p++;                        // the call site encoding: LEB128 in SjLj tables
    uintptr_t table_length = read_uleb(&p);
    const uint8_t *actions_table = p + table_length;
    uintptr_t dispatch = 0, action = 0;
    int found = 0;
    while (p < actions_table) {
        dispatch = read_uleb(&p);
        action = read_uleb(&p);
        if (--site == 0) {
            found = 1;
            break;
        }
    }
    if (!found)
        abort();

    if (action == 0)            // cleanup only
        return actions & UA_SEARCH_PHASE ? URC_CONTINUE_UNWIND : install(context, header, 0, (uint32_t)dispatch);

    int cleanup = 0;
    const uint8_t *record = actions_table + action - 1;
    for (;;) {
        intptr_t filter = read_sleb(&record);
        const uint8_t *next_at = record;
        intptr_t next = read_sleb(&record);
        if (filter > 0 && types) {
            const uint8_t *entry = types - (uintptr_t)filter * type_size(type_encoding);
            const struct objc_typeinfo *type = (const struct objc_typeinfo *)read_encoded(&entry, type_encoding);
            // Foreign exceptions only reach catch-all clauses. The handler's
            // frame finds its clause again for them, which nothing cached.
            int looking = (actions & UA_SEARCH_PHASE) || (actions & UA_HANDLER_FRAME);
            if (looking && (type ? exception && catches(type, exception->object) : 1)) {
                if (!(actions & UA_SEARCH_PHASE))
                    return install(context, header, (uintptr_t)filter, (uint32_t)dispatch);
                if (exception) {
                    exception->selector = (uintptr_t)filter;
                    exception->dispatch = (uint32_t)dispatch;
                }
                return URC_HANDLER_FOUND;
            }
        } else if (filter == 0) {
            cleanup = 1;
        }
        if (next == 0)
            break;
        record = next_at + next;
    }
    if ((actions & UA_CLEANUP_PHASE) && cleanup)
        return install(context, header, 0, (uint32_t)dispatch);
    return URC_CONTINUE_UNWIND;
}

#endif
