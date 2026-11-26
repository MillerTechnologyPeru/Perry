// XPC's object model: the dictionaries, arrays, strings, numbers and data
// that programs build to describe a request, and read back. Nothing is sent
// anywhere here: Swift Playgrounds' compiler talks to its source-code
// service in the same process, through these objects, and an app extension
// is run in its host's process. Objects are reference counted; a collection
// owns the values it holds. There are no connections: a message has no peer
// to reply to, and sending one goes nowhere.

#define _GNU_SOURCE
#include "PerrySystem.h"

#include <dlfcn.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <stdio.h>
#include <sys/types.h>
#include <unistd.h>

// An XPC object is an Objective-C object, as Darwin's are: Swift retains and
// releases them as it does any other, so each is an instance of a class
// made here, its state in the instance's extra bytes.
enum xpc_kind { Null, Bool, Int64, UInt64, Double, String, Data, Array, Dictionary, Error, Uuid, Fd, Date };

struct xpc_type { const char *name; };

struct xpc_body {
    enum xpc_kind kind;
    union {
        bool boolean;
        int64_t int64;
        uint64_t uint64;
        double real;
        uint8_t uuid[16];
        int fd;
        struct { char *chars; size_t length; } string;
        struct { uint8_t *bytes; size_t length; } data;
        struct { void **items; size_t count, capacity; } array;
        struct {
            char **keys;
            void **values;
            size_t count, capacity;
        } dictionary;
    };
};
typedef void *xpc_object_t;

static struct {
    void *(*get_class)(const char *);
    void *(*allocate_class_pair)(void *, const char *, size_t);
    void (*register_class_pair)(void *);
    int (*add_method)(void *, void *, void *, const char *);
    void *(*create_instance)(void *, size_t);
    void *(*indexed_ivars)(void *);
    void *(*retain)(void *);
    void (*release)(void *);
    void *(*register_name)(const char *);
    void *msg_send_super;
    void *cls;
    pthread_once_t once;
} objc = { .once = PTHREAD_ONCE_INIT };

static void xpc_dealloc(void *self, void *cmd);
static void *xpc_retain_method(void *self, void *cmd);
static void xpc_release_method(void *self, void *cmd);
static void *xpc_autorelease_method(void *self, void *cmd);
static unsigned long xpc_retain_count_method(void *self, void *cmd);

// The two errors programs compare connections' failures with are objects
// that live as long as the process: an isa, then the state.
struct static_object { void *isa; struct xpc_body body; };
struct static_object error_interrupted DARWIN_SYMBOL(_xpc_error_connection_interrupted) = { .body = { .kind = Error } };
struct static_object error_invalid DARWIN_SYMBOL(_xpc_error_connection_invalid) = { .body = { .kind = Error } };
struct static_object error_termination_imminent DARWIN_SYMBOL(_xpc_error_termination_imminent) = { .body = { .kind = Error } };
struct static_object error_peer_requirement DARWIN_SYMBOL(_xpc_error_peer_code_signing_requirement) = { .body = { .kind = Error } };
// The two booleans, which xpc_bool_create gives as Darwin does.
struct static_object bool_true DARWIN_SYMBOL(_xpc_bool_true) = { .body = { .kind = Bool, .boolean = true } };
struct static_object bool_false DARWIN_SYMBOL(_xpc_bool_false) = { .body = { .kind = Bool, .boolean = false } };

static struct static_object *const static_objects[] = {
    &error_interrupted, &error_invalid, &error_termination_imminent, &error_peer_requirement, &bool_true, &bool_false,
};

static bool is_static(const void *object) {
    for (size_t i = 0; i < sizeof(static_objects) / sizeof(static_objects[0]); i++)
        if (object == static_objects[i])
            return true;
    return false;
}

static void load_runtime(void) {
    void *handle = dlopen("libPerryobjc.so", RTLD_NOW | RTLD_NOLOAD);
    if (!handle)
        return;
    objc.get_class = dlsym(handle, "_objc_getClass");
    objc.allocate_class_pair = dlsym(handle, "_objc_allocateClassPair");
    objc.register_class_pair = dlsym(handle, "_objc_registerClassPair");
    objc.add_method = dlsym(handle, "_class_addMethod");
    objc.create_instance = dlsym(handle, "_class_createInstance");
    objc.indexed_ivars = dlsym(handle, "_object_getIndexedIvars");
    objc.retain = dlsym(handle, "_objc_retain");
    objc.release = dlsym(handle, "_objc_release");
    objc.register_name = dlsym(handle, "_sel_registerName");
    objc.msg_send_super = dlsym(handle, "_objc_msgSendSuper2");
    if (!objc.get_class || !objc.allocate_class_pair || !objc.register_class_pair || !objc.add_method
        || !objc.create_instance || !objc.indexed_ivars || !objc.register_name)
        return;
    void *base = objc.get_class("NSObject");
    void *cls = base ? objc.allocate_class_pair(base, "OS_xpc_object", 0) : NULL;
    if (!cls)
        return;
    // Methods are added by their selectors, which are registered names (a
    // string isn't one).
    objc.add_method(cls, objc.register_name("dealloc"), (void *)xpc_dealloc, "v16@0:8");
    // The objects in data (the booleans, the connection errors) live as long
    // as the process, as Darwin's do: retaining and releasing them does
    // nothing, and the others count as NSObject's do.
    objc.add_method(cls, objc.register_name("retain"), (void *)xpc_retain_method, "@16@0:8");
    objc.add_method(cls, objc.register_name("release"), (void *)xpc_release_method, "Vv16@0:8");
    objc.add_method(cls, objc.register_name("autorelease"), (void *)xpc_autorelease_method, "@16@0:8");
    objc.add_method(cls, objc.register_name("retainCount"), (void *)xpc_retain_count_method, "Q16@0:8");
    objc.register_class_pair(cls);
    objc.cls = cls;
    for (size_t i = 0; i < sizeof(static_objects) / sizeof(static_objects[0]); i++)
        static_objects[i]->isa = cls;
}

static struct xpc_body *body(xpc_object_t object) {
    if (!object)
        return NULL;
    if (is_static(object))
        return &((struct static_object *)object)->body;
    return objc.indexed_ivars ? objc.indexed_ivars(object) : NULL;
}

struct xpc_type darwin_xpc_type_null DARWIN_SYMBOL(_xpc_type_null) = { "null" };
struct xpc_type darwin_xpc_type_bool DARWIN_SYMBOL(_xpc_type_bool) = { "bool" };
struct xpc_type darwin_xpc_type_int64 DARWIN_SYMBOL(_xpc_type_int64) = { "int64" };
struct xpc_type darwin_xpc_type_uint64 DARWIN_SYMBOL(_xpc_type_uint64) = { "uint64" };
struct xpc_type darwin_xpc_type_double DARWIN_SYMBOL(_xpc_type_double) = { "double" };
struct xpc_type darwin_xpc_type_string DARWIN_SYMBOL(_xpc_type_string) = { "string" };
struct xpc_type darwin_xpc_type_data DARWIN_SYMBOL(_xpc_type_data) = { "data" };
struct xpc_type darwin_xpc_type_array DARWIN_SYMBOL(_xpc_type_array) = { "array" };
struct xpc_type darwin_xpc_type_dictionary DARWIN_SYMBOL(_xpc_type_dictionary) = { "dictionary" };
struct xpc_type darwin_xpc_type_error DARWIN_SYMBOL(_xpc_type_error) = { "error" };
struct xpc_type darwin_xpc_type_uuid DARWIN_SYMBOL(_xpc_type_uuid) = { "uuid" };
struct xpc_type darwin_xpc_type_fd DARWIN_SYMBOL(_xpc_type_fd) = { "fd" };
struct xpc_type darwin_xpc_type_date DARWIN_SYMBOL(_xpc_type_date) = { "date" };
// The types of objects made only by what isn't here (connections, services,
// shared memory…): programs compare with them, and no object has them.
struct xpc_type darwin_xpc_type_connection DARWIN_SYMBOL(_xpc_type_connection) = { "connection" };
struct xpc_type darwin_xpc_type_endpoint DARWIN_SYMBOL(_xpc_type_endpoint) = { "endpoint" };
struct xpc_type darwin_xpc_type_shmem DARWIN_SYMBOL(_xpc_type_shmem) = { "shmem" };
struct xpc_type darwin_xpc_type_activity DARWIN_SYMBOL(_xpc_type_activity) = { "activity" };
struct xpc_type darwin_xpc_type_rich_error DARWIN_SYMBOL(_xpc_type_rich_error) = { "rich_error" };
struct xpc_type darwin_xpc_type_bundle DARWIN_SYMBOL(_xpc_type_bundle) = { "bundle" };
struct xpc_type darwin_xpc_type_file_transfer DARWIN_SYMBOL(_xpc_type_file_transfer) = { "file_transfer" };
struct xpc_type darwin_xpc_type_mach_recv DARWIN_SYMBOL(_xpc_type_mach_recv) = { "mach_recv" };
struct xpc_type darwin_xpc_type_mach_send DARWIN_SYMBOL(_xpc_type_mach_send) = { "mach_send" };
struct xpc_type darwin_xpc_type_mach_send_once DARWIN_SYMBOL(_xpc_type_mach_send_once) = { "mach_send_once" };
struct xpc_type darwin_xpc_type_pipe DARWIN_SYMBOL(_xpc_type_pipe) = { "pipe" };
struct xpc_type darwin_xpc_type_pointer DARWIN_SYMBOL(_xpc_type_pointer) = { "pointer" };
struct xpc_type darwin_xpc_type_serializer DARWIN_SYMBOL(_xpc_type_serializer) = { "serializer" };
struct xpc_type darwin_xpc_type_service DARWIN_SYMBOL(_xpc_type_service) = { "service" };
struct xpc_type darwin_xpc_type_service_instance DARWIN_SYMBOL(_xpc_type_service_instance) = { "service_instance" };

const char *const darwin_xpc_error_key_description DARWIN_SYMBOL(_xpc_error_key_description) =
    "XPCErrorDescription";
const char *const darwin_xpc_event_key_name DARWIN_SYMBOL(_xpc_event_key_name) = "XPCEventName";

static xpc_object_t make(enum xpc_kind kind) {
    pthread_once(&objc.once, load_runtime);
    if (!objc.cls)
        return NULL;
    xpc_object_t object = objc.create_instance(objc.cls, sizeof(struct xpc_body));
    struct xpc_body *state = body(object);
    if (state)
        state->kind = kind;
    return object;
}

static bool immortal(xpc_object_t object) { return is_static(object); }

xpc_object_t darwin_xpc_retain(xpc_object_t object) DARWIN_SYMBOL(xpc_retain);
xpc_object_t darwin_xpc_retain(xpc_object_t object) {
    if (object && !immortal(object) && objc.retain)
        objc.retain(object);
    return object;
}

void darwin_xpc_release(xpc_object_t object) DARWIN_SYMBOL(xpc_release);
void darwin_xpc_release(xpc_object_t object) {
    if (object && !immortal(object) && objc.release)
        objc.release(object);
}

/// Sends a method to NSObject's implementation, for the objects that
/// aren't static (objc_msgSendSuper2 takes this class and looks above it).
static void *send_super(void *self, const char *selector) {
    struct { void *receiver; void *current_class; } super = { self, objc.cls };
    return ((void *(*)(void *, void *))objc.msg_send_super)(&super, objc.register_name(selector));
}

static void *xpc_retain_method(void *self, void *cmd) {
    (void)cmd;
    return is_static(self) ? self : send_super(self, "retain");
}

static void xpc_release_method(void *self, void *cmd) {
    (void)cmd;
    if (!is_static(self))
        send_super(self, "release");
}

static void *xpc_autorelease_method(void *self, void *cmd) {
    (void)cmd;
    return is_static(self) ? self : send_super(self, "autorelease");
}

static unsigned long xpc_retain_count_method(void *self, void *cmd) {
    (void)cmd;
    return is_static(self) ? (unsigned long)-1 : (unsigned long)(uintptr_t)send_super(self, "retainCount");
}

// When the last reference goes: what the object holds is let go.
static void xpc_dealloc(void *self, void *cmd) {
    struct xpc_body *state = body(self);
    if (state) {
        switch (state->kind) {
        case String: free(state->string.chars); break;
        case Data: free(state->data.bytes); break;
        case Fd: close(state->fd); break;
        case Array:
            for (size_t i = 0; i < state->array.count; i++)
                darwin_xpc_release(state->array.items[i]);
            free(state->array.items);
            break;
        case Dictionary:
            for (size_t i = 0; i < state->dictionary.count; i++) {
                free(state->dictionary.keys[i]);
                darwin_xpc_release(state->dictionary.values[i]);
            }
            free(state->dictionary.keys);
            free(state->dictionary.values);
            break;
        default: break;
        }
    }
    struct { void *receiver; void *current_class; } super = { self, objc.cls };
    ((void (*)(void *, void *))objc.msg_send_super)(&super, objc.register_name("dealloc"));
}

const struct xpc_type *darwin_xpc_get_type(xpc_object_t object) DARWIN_SYMBOL(xpc_get_type);
const struct xpc_type *darwin_xpc_get_type(xpc_object_t object) {
    struct xpc_body *state = body(object);
    if (!state)
        return NULL;
    switch (state->kind) {
    case Null: return &darwin_xpc_type_null;
    case Bool: return &darwin_xpc_type_bool;
    case Int64: return &darwin_xpc_type_int64;
    case UInt64: return &darwin_xpc_type_uint64;
    case Double: return &darwin_xpc_type_double;
    case String: return &darwin_xpc_type_string;
    case Data: return &darwin_xpc_type_data;
    case Array: return &darwin_xpc_type_array;
    case Dictionary: return &darwin_xpc_type_dictionary;
    case Error: return &darwin_xpc_type_error;
    case Uuid: return &darwin_xpc_type_uuid;
    case Fd: return &darwin_xpc_type_fd;
    case Date: return &darwin_xpc_type_date;
    }
    return NULL;
}

// MARK: - Scalars

xpc_object_t darwin_xpc_null_create(void) DARWIN_SYMBOL(xpc_null_create);
xpc_object_t darwin_xpc_null_create(void) { return make(Null); }

xpc_object_t darwin_xpc_bool_create(bool value) DARWIN_SYMBOL(xpc_bool_create);
xpc_object_t darwin_xpc_bool_create(bool value) {
    pthread_once(&objc.once, load_runtime);
    return value ? (xpc_object_t)&bool_true : (xpc_object_t)&bool_false;
}

bool darwin_xpc_bool_get_value(xpc_object_t object) DARWIN_SYMBOL(xpc_bool_get_value);
bool darwin_xpc_bool_get_value(xpc_object_t object) { return object && body(object)->kind == Bool && body(object)->boolean; }

xpc_object_t darwin_xpc_int64_create(int64_t value) DARWIN_SYMBOL(xpc_int64_create);
xpc_object_t darwin_xpc_int64_create(int64_t value) {
    xpc_object_t object = make(Int64);
    if (object)
        body(object)->int64 = value;
    return object;
}

int64_t darwin_xpc_int64_get_value(xpc_object_t object) DARWIN_SYMBOL(xpc_int64_get_value);
int64_t darwin_xpc_int64_get_value(xpc_object_t object) { return object && body(object)->kind == Int64 ? body(object)->int64 : 0; }

xpc_object_t darwin_xpc_uint64_create(uint64_t value) DARWIN_SYMBOL(xpc_uint64_create);
xpc_object_t darwin_xpc_uint64_create(uint64_t value) {
    xpc_object_t object = make(UInt64);
    if (object)
        body(object)->uint64 = value;
    return object;
}

uint64_t darwin_xpc_uint64_get_value(xpc_object_t object) DARWIN_SYMBOL(xpc_uint64_get_value);
uint64_t darwin_xpc_uint64_get_value(xpc_object_t object) { return object && body(object)->kind == UInt64 ? body(object)->uint64 : 0; }

xpc_object_t darwin_xpc_double_create(double value) DARWIN_SYMBOL(xpc_double_create);
xpc_object_t darwin_xpc_double_create(double value) {
    xpc_object_t object = make(Double);
    if (object)
        body(object)->real = value;
    return object;
}

double darwin_xpc_double_get_value(xpc_object_t object) DARWIN_SYMBOL(xpc_double_get_value);
double darwin_xpc_double_get_value(xpc_object_t object) { return object && body(object)->kind == Double ? body(object)->real : 0; }

// A date is nanoseconds since 1970.
xpc_object_t darwin_xpc_date_create(int64_t interval) DARWIN_SYMBOL(xpc_date_create);
xpc_object_t darwin_xpc_date_create(int64_t interval) {
    xpc_object_t object = make(Date);
    if (object)
        body(object)->int64 = interval;
    return object;
}

xpc_object_t darwin_xpc_date_create_from_current(void) DARWIN_SYMBOL(xpc_date_create_from_current);
xpc_object_t darwin_xpc_date_create_from_current(void) {
    struct timespec now;
    clock_gettime(CLOCK_REALTIME, &now);
    return darwin_xpc_date_create((int64_t)now.tv_sec * 1000000000 + now.tv_nsec);
}

int64_t darwin_xpc_date_get_value(xpc_object_t object) DARWIN_SYMBOL(xpc_date_get_value);
int64_t darwin_xpc_date_get_value(xpc_object_t object) { return object && body(object)->kind == Date ? body(object)->int64 : 0; }

xpc_object_t darwin_xpc_string_create(const char *string) DARWIN_SYMBOL(xpc_string_create);
xpc_object_t darwin_xpc_string_create(const char *string) {
    xpc_object_t object = make(String);
    if (!object)
        return NULL;
    body(object)->string.chars = strdup(string ? string : "");
    body(object)->string.length = body(object)->string.chars ? strlen(body(object)->string.chars) : 0;
    return object;
}

const char *darwin_xpc_string_get_string_ptr(xpc_object_t object) DARWIN_SYMBOL(xpc_string_get_string_ptr);
const char *darwin_xpc_string_get_string_ptr(xpc_object_t object) {
    return object && body(object)->kind == String ? body(object)->string.chars : NULL;
}

size_t darwin_xpc_string_get_length(xpc_object_t object) DARWIN_SYMBOL(xpc_string_get_length);
size_t darwin_xpc_string_get_length(xpc_object_t object) {
    return object && body(object)->kind == String ? body(object)->string.length : 0;
}

xpc_object_t darwin_xpc_data_create(const void *bytes, size_t length) DARWIN_SYMBOL(xpc_data_create);
xpc_object_t darwin_xpc_data_create(const void *bytes, size_t length) {
    xpc_object_t object = make(Data);
    if (!object)
        return NULL;
    body(object)->data.bytes = malloc(length ? length : 1);
    if (body(object)->data.bytes && bytes)
        memcpy(body(object)->data.bytes, bytes, length);
    body(object)->data.length = length;
    return object;
}

const void *darwin_xpc_data_get_bytes_ptr(xpc_object_t object) DARWIN_SYMBOL(xpc_data_get_bytes_ptr);
const void *darwin_xpc_data_get_bytes_ptr(xpc_object_t object) {
    return object && body(object)->kind == Data ? body(object)->data.bytes : NULL;
}

size_t darwin_xpc_data_get_length(xpc_object_t object) DARWIN_SYMBOL(xpc_data_get_length);
size_t darwin_xpc_data_get_length(xpc_object_t object) {
    return object && body(object)->kind == Data ? body(object)->data.length : 0;
}

// MARK: - Arrays

xpc_object_t darwin_xpc_array_create_empty(void) DARWIN_SYMBOL(xpc_array_create_empty);
xpc_object_t darwin_xpc_array_create_empty(void) { return make(Array); }

static void array_insert(xpc_object_t array, size_t index, xpc_object_t value) {
    if (body(array)->array.count == body(array)->array.capacity) {
        size_t capacity = body(array)->array.capacity ? body(array)->array.capacity * 2 : 8;
        xpc_object_t *items = realloc(body(array)->array.items, capacity * sizeof(*items));
        if (!items)
            return;
        body(array)->array.items = items;
        body(array)->array.capacity = capacity;
    }
    if (index > body(array)->array.count)
        index = body(array)->array.count;
    memmove(&body(array)->array.items[index + 1], &body(array)->array.items[index],
            (body(array)->array.count - index) * sizeof(xpc_object_t));
    body(array)->array.items[index] = darwin_xpc_retain(value);
    body(array)->array.count++;
}

xpc_object_t darwin_xpc_array_create(xpc_object_t *objects, size_t count) DARWIN_SYMBOL(xpc_array_create);
xpc_object_t darwin_xpc_array_create(xpc_object_t *objects, size_t count) {
    xpc_object_t array = make(Array);
    for (size_t i = 0; array && objects && i < count; i++)
        array_insert(array, i, objects[i]);
    return array;
}

void darwin_xpc_array_append_value(xpc_object_t array, xpc_object_t value) DARWIN_SYMBOL(xpc_array_append_value);
void darwin_xpc_array_append_value(xpc_object_t array, xpc_object_t value) {
    if (array && body(array)->kind == Array && value)
        array_insert(array, body(array)->array.count, value);
}

size_t darwin_xpc_array_get_count(xpc_object_t array) DARWIN_SYMBOL(xpc_array_get_count);
size_t darwin_xpc_array_get_count(xpc_object_t array) {
    return array && body(array)->kind == Array ? body(array)->array.count : 0;
}

xpc_object_t darwin_xpc_array_get_value(xpc_object_t array, size_t index) DARWIN_SYMBOL(xpc_array_get_value);
xpc_object_t darwin_xpc_array_get_value(xpc_object_t array, size_t index) {
    return array && body(array)->kind == Array && index < body(array)->array.count ? body(array)->array.items[index] : NULL;
}

// XPC_ARRAY_APPEND, SIZE_MAX, as an index appends.
void darwin_xpc_array_set_value(xpc_object_t array, size_t index, xpc_object_t value) DARWIN_SYMBOL(xpc_array_set_value);
void darwin_xpc_array_set_value(xpc_object_t array, size_t index, xpc_object_t value) {
    if (!array || body(array)->kind != Array || !value)
        return;
    if (index >= body(array)->array.count) {
        array_insert(array, body(array)->array.count, value);
        return;
    }
    xpc_object_t old = body(array)->array.items[index];
    body(array)->array.items[index] = darwin_xpc_retain(value);
    darwin_xpc_release(old);
}

#define ARRAY_SETTER(suffix, type, create) \
    void darwin_xpc_array_set_##suffix(xpc_object_t array, size_t index, type value) DARWIN_SYMBOL(xpc_array_set_##suffix); \
    void darwin_xpc_array_set_##suffix(xpc_object_t array, size_t index, type value) { \
        xpc_object_t object = create(value); \
        darwin_xpc_array_set_value(array, index, object); \
        darwin_xpc_release(object); \
    }
ARRAY_SETTER(int64, int64_t, darwin_xpc_int64_create)
ARRAY_SETTER(uint64, uint64_t, darwin_xpc_uint64_create)
ARRAY_SETTER(double, double, darwin_xpc_double_create)
ARRAY_SETTER(string, const char *, darwin_xpc_string_create)

bool darwin_xpc_array_get_bool(xpc_object_t array, size_t index) DARWIN_SYMBOL(xpc_array_get_bool);
bool darwin_xpc_array_get_bool(xpc_object_t array, size_t index) {
    return darwin_xpc_bool_get_value(darwin_xpc_array_get_value(array, index));
}
int64_t darwin_xpc_array_get_int64(xpc_object_t array, size_t index) DARWIN_SYMBOL(xpc_array_get_int64);
int64_t darwin_xpc_array_get_int64(xpc_object_t array, size_t index) {
    return darwin_xpc_int64_get_value(darwin_xpc_array_get_value(array, index));
}
uint64_t darwin_xpc_array_get_uint64(xpc_object_t array, size_t index) DARWIN_SYMBOL(xpc_array_get_uint64);
uint64_t darwin_xpc_array_get_uint64(xpc_object_t array, size_t index) {
    return darwin_xpc_uint64_get_value(darwin_xpc_array_get_value(array, index));
}
double darwin_xpc_array_get_double(xpc_object_t array, size_t index) DARWIN_SYMBOL(xpc_array_get_double);
double darwin_xpc_array_get_double(xpc_object_t array, size_t index) {
    return darwin_xpc_double_get_value(darwin_xpc_array_get_value(array, index));
}
const char *darwin_xpc_array_get_string(xpc_object_t array, size_t index) DARWIN_SYMBOL(xpc_array_get_string);
const char *darwin_xpc_array_get_string(xpc_object_t array, size_t index) {
    return darwin_xpc_string_get_string_ptr(darwin_xpc_array_get_value(array, index));
}

// The block is bool (^)(size_t index, xpc_object_t value); false stops.
bool darwin_xpc_array_apply(xpc_object_t array, void *block) DARWIN_SYMBOL(xpc_array_apply);
bool darwin_xpc_array_apply(xpc_object_t array, void *block) {
    if (!array || body(array)->kind != Array || !block)
        return false;
    typedef bool (*Invoke)(void *, size_t, xpc_object_t);
    Invoke invoke = (Invoke)((void **)block)[2];
    for (size_t i = 0; i < body(array)->array.count; i++)
        if (!invoke(block, i, body(array)->array.items[i]))
            return false;
    return true;
}

// MARK: - Dictionaries

xpc_object_t darwin_xpc_dictionary_create_empty(void) DARWIN_SYMBOL(xpc_dictionary_create_empty);
xpc_object_t darwin_xpc_dictionary_create_empty(void) { return make(Dictionary); }

static ssize_t dictionary_find(xpc_object_t dictionary, const char *key) {
    for (size_t i = 0; i < body(dictionary)->dictionary.count; i++)
        if (strcmp(body(dictionary)->dictionary.keys[i], key) == 0)
            return (ssize_t)i;
    return -1;
}

void darwin_xpc_dictionary_set_value(xpc_object_t dictionary, const char *key, xpc_object_t value)
    DARWIN_SYMBOL(xpc_dictionary_set_value);
void darwin_xpc_dictionary_set_value(xpc_object_t dictionary, const char *key, xpc_object_t value) {
    if (!dictionary || body(dictionary)->kind != Dictionary || !key)
        return;
    ssize_t found = dictionary_find(dictionary, key);
    if (found >= 0) {
        xpc_object_t old = body(dictionary)->dictionary.values[found];
        if (value) {
            body(dictionary)->dictionary.values[found] = darwin_xpc_retain(value);
        } else {
            free(body(dictionary)->dictionary.keys[found]);
            size_t tail = body(dictionary)->dictionary.count - (size_t)found - 1;
            memmove(&body(dictionary)->dictionary.keys[found], &body(dictionary)->dictionary.keys[found + 1], tail * sizeof(char *));
            memmove(&body(dictionary)->dictionary.values[found], &body(dictionary)->dictionary.values[found + 1],
                    tail * sizeof(xpc_object_t));
            body(dictionary)->dictionary.count--;
        }
        darwin_xpc_release(old);
        return;
    }
    if (!value)
        return;
    if (body(dictionary)->dictionary.count == body(dictionary)->dictionary.capacity) {
        size_t capacity = body(dictionary)->dictionary.capacity ? body(dictionary)->dictionary.capacity * 2 : 8;
        char **keys = realloc(body(dictionary)->dictionary.keys, capacity * sizeof(char *));
        if (keys)
            body(dictionary)->dictionary.keys = keys;
        xpc_object_t *values = realloc(body(dictionary)->dictionary.values, capacity * sizeof(xpc_object_t));
        if (values)
            body(dictionary)->dictionary.values = values;
        if (!keys || !values)
            return;
        body(dictionary)->dictionary.capacity = capacity;
    }
    size_t at = body(dictionary)->dictionary.count++;
    body(dictionary)->dictionary.keys[at] = strdup(key);
    body(dictionary)->dictionary.values[at] = darwin_xpc_retain(value);
}

xpc_object_t darwin_xpc_dictionary_create(const char *const *keys, xpc_object_t *values, size_t count)
    DARWIN_SYMBOL(xpc_dictionary_create);
xpc_object_t darwin_xpc_dictionary_create(const char *const *keys, xpc_object_t *values, size_t count) {
    xpc_object_t dictionary = make(Dictionary);
    for (size_t i = 0; dictionary && keys && values && i < count; i++)
        darwin_xpc_dictionary_set_value(dictionary, keys[i], values[i]);
    return dictionary;
}

xpc_object_t darwin_xpc_dictionary_get_value(xpc_object_t dictionary, const char *key)
    DARWIN_SYMBOL(xpc_dictionary_get_value);
xpc_object_t darwin_xpc_dictionary_get_value(xpc_object_t dictionary, const char *key) {
    if (!dictionary || body(dictionary)->kind != Dictionary || !key)
        return NULL;
    ssize_t found = dictionary_find(dictionary, key);
    return found >= 0 ? body(dictionary)->dictionary.values[found] : NULL;
}

#define DICTIONARY_SETTER(suffix, type, create) \
    void darwin_xpc_dictionary_set_##suffix(xpc_object_t dictionary, const char *key, type value) \
        DARWIN_SYMBOL(xpc_dictionary_set_##suffix); \
    void darwin_xpc_dictionary_set_##suffix(xpc_object_t dictionary, const char *key, type value) { \
        xpc_object_t object = create(value); \
        darwin_xpc_dictionary_set_value(dictionary, key, object); \
        darwin_xpc_release(object); \
    }
DICTIONARY_SETTER(bool, bool, darwin_xpc_bool_create)
DICTIONARY_SETTER(int64, int64_t, darwin_xpc_int64_create)
DICTIONARY_SETTER(uint64, uint64_t, darwin_xpc_uint64_create)
DICTIONARY_SETTER(double, double, darwin_xpc_double_create)
DICTIONARY_SETTER(string, const char *, darwin_xpc_string_create)

bool darwin_xpc_dictionary_get_bool(xpc_object_t dictionary, const char *key) DARWIN_SYMBOL(xpc_dictionary_get_bool);
bool darwin_xpc_dictionary_get_bool(xpc_object_t dictionary, const char *key) {
    return darwin_xpc_bool_get_value(darwin_xpc_dictionary_get_value(dictionary, key));
}
int64_t darwin_xpc_dictionary_get_int64(xpc_object_t dictionary, const char *key) DARWIN_SYMBOL(xpc_dictionary_get_int64);
int64_t darwin_xpc_dictionary_get_int64(xpc_object_t dictionary, const char *key) {
    return darwin_xpc_int64_get_value(darwin_xpc_dictionary_get_value(dictionary, key));
}
uint64_t darwin_xpc_dictionary_get_uint64(xpc_object_t dictionary, const char *key) DARWIN_SYMBOL(xpc_dictionary_get_uint64);
uint64_t darwin_xpc_dictionary_get_uint64(xpc_object_t dictionary, const char *key) {
    return darwin_xpc_uint64_get_value(darwin_xpc_dictionary_get_value(dictionary, key));
}
double darwin_xpc_dictionary_get_double(xpc_object_t dictionary, const char *key) DARWIN_SYMBOL(xpc_dictionary_get_double);
double darwin_xpc_dictionary_get_double(xpc_object_t dictionary, const char *key) {
    return darwin_xpc_double_get_value(darwin_xpc_dictionary_get_value(dictionary, key));
}
const char *darwin_xpc_dictionary_get_string(xpc_object_t dictionary, const char *key)
    DARWIN_SYMBOL(xpc_dictionary_get_string);
const char *darwin_xpc_dictionary_get_string(xpc_object_t dictionary, const char *key) {
    return darwin_xpc_string_get_string_ptr(darwin_xpc_dictionary_get_value(dictionary, key));
}

// The block is bool (^)(const char *key, xpc_object_t value); false stops.
bool darwin_xpc_dictionary_apply(xpc_object_t dictionary, void *block) DARWIN_SYMBOL(xpc_dictionary_apply);
bool darwin_xpc_dictionary_apply(xpc_object_t dictionary, void *block) {
    if (!dictionary || body(dictionary)->kind != Dictionary || !block)
        return false;
    typedef bool (*Invoke)(void *, const char *, xpc_object_t);
    Invoke invoke = (Invoke)((void **)block)[2];
    for (size_t i = 0; i < body(dictionary)->dictionary.count; i++)
        if (!invoke(block, body(dictionary)->dictionary.keys[i], body(dictionary)->dictionary.values[i]))
            return false;
    return true;
}

size_t darwin_xpc_dictionary_get_count(xpc_object_t dictionary) DARWIN_SYMBOL(xpc_dictionary_get_count);
size_t darwin_xpc_dictionary_get_count(xpc_object_t dictionary) {
    return dictionary && body(dictionary)->kind == Dictionary ? body(dictionary)->dictionary.count : 0;
}

// A message here never came from a peer: there is nobody to reply to, no
// connection it came on, and no peer's audit token (all zero).
xpc_object_t darwin_xpc_dictionary_create_reply(xpc_object_t original) DARWIN_SYMBOL(xpc_dictionary_create_reply);
xpc_object_t darwin_xpc_dictionary_create_reply(xpc_object_t original) {
    (void)original;
    return NULL;
}

void *darwin_xpc_dictionary_get_remote_connection(xpc_object_t message) DARWIN_SYMBOL(xpc_dictionary_get_remote_connection);
void *darwin_xpc_dictionary_get_remote_connection(xpc_object_t message) {
    (void)message;
    return NULL;
}

void darwin_xpc_dictionary_get_audit_token(xpc_object_t message, void *token) DARWIN_SYMBOL(xpc_dictionary_get_audit_token);
void darwin_xpc_dictionary_get_audit_token(xpc_object_t message, void *token) {
    (void)message;
    if (token)
        memset(token, 0, 32);
}

void darwin_xpc_connection_send_message(void *connection, xpc_object_t message) DARWIN_SYMBOL(xpc_connection_send_message);
void darwin_xpc_connection_send_message(void *connection, xpc_object_t message) {
    (void)connection;
    (void)message;
}

// MARK: - UUIDs and file descriptors

xpc_object_t darwin_xpc_uuid_create(const uint8_t *uuid) DARWIN_SYMBOL(xpc_uuid_create);
xpc_object_t darwin_xpc_uuid_create(const uint8_t *uuid) {
    xpc_object_t object = make(Uuid);
    if (object && uuid)
        memcpy(body(object)->uuid, uuid, 16);
    return object;
}

const uint8_t *darwin_xpc_uuid_get_bytes(xpc_object_t object) DARWIN_SYMBOL(xpc_uuid_get_bytes);
const uint8_t *darwin_xpc_uuid_get_bytes(xpc_object_t object) {
    return object && body(object)->kind == Uuid ? body(object)->uuid : NULL;
}

// The object keeps its own duplicate of the descriptor, closed with it.
xpc_object_t darwin_xpc_fd_create(int fd) DARWIN_SYMBOL(xpc_fd_create);
xpc_object_t darwin_xpc_fd_create(int fd) {
    int copy = dup(fd);
    if (copy < 0)
        return NULL;
    xpc_object_t object = make(Fd);
    if (!object) {
        close(copy);
        return NULL;
    }
    body(object)->fd = copy;
    return object;
}

int darwin_xpc_fd_dup(xpc_object_t object) DARWIN_SYMBOL(xpc_fd_dup);
int darwin_xpc_fd_dup(xpc_object_t object) {
    return object && body(object)->kind == Fd ? dup(body(object)->fd) : -1;
}

// MARK: - Equality, hashing and descriptions

bool darwin_xpc_equal(xpc_object_t a, xpc_object_t b) DARWIN_SYMBOL(xpc_equal);
bool darwin_xpc_equal(xpc_object_t a, xpc_object_t b) {
    if (a == b)
        return true;
    struct xpc_body *x = body(a), *y = body(b);
    if (!x || !y || x->kind != y->kind)
        return false;
    switch (x->kind) {
    case Null: return true;
    case Bool: return x->boolean == y->boolean;
    case Int64: return x->int64 == y->int64;
    case UInt64: return x->uint64 == y->uint64;
    case Double: return x->real == y->real;
    case Date: return x->int64 == y->int64;
    case String: return x->string.length == y->string.length && memcmp(x->string.chars, y->string.chars, x->string.length) == 0;
    case Data: return x->data.length == y->data.length && (x->data.length == 0 || memcmp(x->data.bytes, y->data.bytes, x->data.length) == 0);
    case Uuid: return memcmp(x->uuid, y->uuid, 16) == 0;
    case Array:
        if (x->array.count != y->array.count)
            return false;
        for (size_t i = 0; i < x->array.count; i++)
            if (!darwin_xpc_equal(x->array.items[i], y->array.items[i]))
                return false;
        return true;
    case Dictionary:
        if (x->dictionary.count != y->dictionary.count)
            return false;
        for (size_t i = 0; i < x->dictionary.count; i++)
            if (!darwin_xpc_equal(x->dictionary.values[i], darwin_xpc_dictionary_get_value(b, x->dictionary.keys[i])))
                return false;
        return true;
    case Error: case Fd: return false;
    }
    return false;
}

static size_t hash_bytes(const void *bytes, size_t length, size_t seed) {
    const uint8_t *p = bytes;
    size_t hash = seed ^ 1469598103934665603ull;
    for (size_t i = 0; i < length; i++)
        hash = (hash ^ p[i]) * 1099511628211ull;
    return hash;
}

size_t darwin_xpc_hash(xpc_object_t object) DARWIN_SYMBOL(xpc_hash);
size_t darwin_xpc_hash(xpc_object_t object) {
    struct xpc_body *state = body(object);
    if (!state)
        return 0;
    switch (state->kind) {
    case Null: return 0;
    case Bool: return state->boolean;
    case Int64: return (size_t)state->int64;
    case UInt64: return (size_t)state->uint64;
    case Double: return hash_bytes(&state->real, sizeof(state->real), Double);
    case Date: return (size_t)state->int64;
    case String: return hash_bytes(state->string.chars, state->string.length, String);
    case Data: return hash_bytes(state->data.bytes, state->data.length, Data);
    case Uuid: return hash_bytes(state->uuid, 16, Uuid);
    case Array: return state->array.count * 31 + Array;
    // Equal dictionaries may hold their keys in different orders: only the
    // count goes in.
    case Dictionary: return state->dictionary.count * 31 + Dictionary;
    case Error: case Fd: return (size_t)(uintptr_t)object;
    }
    return 0;
}

// A growing string for descriptions.
struct text { char *chars; size_t length, capacity; };

static void append(struct text *text, const char *format, ...) __attribute__((format(printf, 2, 3)));
static void append(struct text *text, const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    va_list copy;
    va_copy(copy, arguments);
    int needed = vsnprintf(NULL, 0, format, copy);
    va_end(copy);
    if (needed > 0 && text->length + (size_t)needed + 1 > text->capacity) {
        size_t capacity = (text->length + (size_t)needed + 1) * 2;
        char *chars = realloc(text->chars, capacity);
        if (!chars) {
            va_end(arguments);
            return;
        }
        text->chars = chars;
        text->capacity = capacity;
    }
    if (needed > 0) {
        vsnprintf(text->chars + text->length, (size_t)needed + 1, format, arguments);
        text->length += (size_t)needed;
    }
    va_end(arguments);
}

static void describe(struct text *text, xpc_object_t object, int depth) {
    struct xpc_body *state = body(object);
    if (!state) {
        append(text, "<null>");
        return;
    }
    switch (state->kind) {
    case Null: append(text, "<null>"); break;
    case Bool: append(text, "<bool: %s>", state->boolean ? "true" : "false"); break;
    case Int64: append(text, "<int64: %lld>", (long long)state->int64); break;
    case UInt64: append(text, "<uint64: %llu>", (unsigned long long)state->uint64); break;
    case Double: append(text, "<double: %g>", state->real); break;
    case Date: append(text, "<date: %lld>", (long long)state->int64); break;
    case String: append(text, "<string: { length = %zu, contents = \"%s\" }>", state->string.length, state->string.chars ? state->string.chars : ""); break;
    case Data: append(text, "<data: { length = %zu bytes }>", state->data.length); break;
    case Fd: append(text, "<fd: %d>", state->fd); break;
    case Error: append(text, "<error>"); break;
    case Uuid: {
        const uint8_t *u = state->uuid;
        append(text, "<uuid: %02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X>",
               u[0], u[1], u[2], u[3], u[4], u[5], u[6], u[7], u[8], u[9], u[10], u[11], u[12], u[13], u[14], u[15]);
        break;
    }
    case Array:
        append(text, "<array: { count = %zu, contents =\n", state->array.count);
        for (size_t i = 0; i < state->array.count; i++) {
            append(text, "%*s%zu: ", (depth + 1) * 4, "", i);
            describe(text, state->array.items[i], depth + 1);
            append(text, "\n");
        }
        append(text, "%*s}>", depth * 4, "");
        break;
    case Dictionary:
        append(text, "<dictionary: { count = %zu, contents =\n", state->dictionary.count);
        for (size_t i = 0; i < state->dictionary.count; i++) {
            append(text, "%*s\"%s\" => ", (depth + 1) * 4, "", state->dictionary.keys[i]);
            describe(text, state->dictionary.values[i], depth + 1);
            append(text, "\n");
        }
        append(text, "%*s}>", depth * 4, "");
        break;
    }
}

// Freed by the caller, as Darwin's is.
char *darwin_xpc_copy_description(xpc_object_t object) DARWIN_SYMBOL(xpc_copy_description);
char *darwin_xpc_copy_description(xpc_object_t object) {
    struct text text = { 0 };
    describe(&text, object, 0);
    return text.chars ? text.chars : strdup("");
}

// Rich errors come from sessions, which aren't here: one describes itself
// generally and can't be retried.
char *darwin_xpc_rich_error_copy_description(xpc_object_t error) DARWIN_SYMBOL(xpc_rich_error_copy_description);
char *darwin_xpc_rich_error_copy_description(xpc_object_t error) {
    (void)error;
    return strdup("XPC is not available");
}

bool darwin_xpc_rich_error_can_retry(xpc_object_t error) DARWIN_SYMBOL(xpc_rich_error_can_retry);
bool darwin_xpc_rich_error_can_retry(xpc_object_t error) {
    (void)error;
    return false;
}
