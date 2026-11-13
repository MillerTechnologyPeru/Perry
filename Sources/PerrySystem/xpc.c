// XPC's object model: the dictionaries, arrays, strings, numbers and data
// that programs build to describe a request, and read back. Nothing is sent
// anywhere here: Swift Playgrounds' compiler talks to its source-code
// service in the same process, through these objects, and an app extension
// is run in its host's process. Objects are reference counted; a collection
// owns the values it holds.

#define _GNU_SOURCE
#include "PerrySystem.h"

#include <dlfcn.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>

// An XPC object is an Objective-C object, as Darwin's are: Swift retains and
// releases them as it does any other, so each is an instance of a class
// made here, its state in the instance's extra bytes.
enum xpc_kind { Null, Bool, Int64, UInt64, Double, String, Data, Array, Dictionary, Error };

struct xpc_type { const char *name; };

struct xpc_body {
    enum xpc_kind kind;
    union {
        bool boolean;
        int64_t int64;
        uint64_t uint64;
        double real;
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
    int (*add_method)(void *, const char *, void *, const char *);
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

// The two errors programs compare connections' failures with are objects
// that live as long as the process: an isa, then the state.
struct static_object { void *isa; struct xpc_body body; };
struct static_object error_interrupted DARWIN_SYMBOL(_xpc_error_connection_interrupted) = { .body = { .kind = Error } };
struct static_object error_invalid DARWIN_SYMBOL(_xpc_error_connection_invalid) = { .body = { .kind = Error } };

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
        || !objc.create_instance || !objc.indexed_ivars)
        return;
    void *base = objc.get_class("NSObject");
    void *cls = base ? objc.allocate_class_pair(base, "OS_xpc_object", 0) : NULL;
    if (!cls)
        return;
    objc.add_method(cls, "dealloc", (void *)xpc_dealloc, "v16@0:8");
    objc.register_class_pair(cls);
    objc.cls = cls;
    error_interrupted.isa = cls;
    error_invalid.isa = cls;
}

static struct xpc_body *body(xpc_object_t object) {
    if (!object)
        return NULL;
    if (object == &error_interrupted || object == &error_invalid)
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

const char *const darwin_xpc_error_key_description DARWIN_SYMBOL(_xpc_error_key_description) =
    "XPCErrorDescription";

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

static bool immortal(xpc_object_t object) { return object == &error_interrupted || object == &error_invalid; }

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

// When the last reference goes: what the object holds is let go.
static void xpc_dealloc(void *self, void *cmd) {
    struct xpc_body *state = body(self);
    if (state) {
        switch (state->kind) {
        case String: free(state->string.chars); break;
        case Data: free(state->data.bytes); break;
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
    struct { void *receiver; void *super_class; } super = { self, objc.get_class("NSObject") };
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
    }
    return NULL;
}

// MARK: - Scalars

xpc_object_t darwin_xpc_null_create(void) DARWIN_SYMBOL(xpc_null_create);
xpc_object_t darwin_xpc_null_create(void) { return make(Null); }

xpc_object_t darwin_xpc_bool_create(bool value) DARWIN_SYMBOL(xpc_bool_create);
xpc_object_t darwin_xpc_bool_create(bool value) {
    xpc_object_t object = make(Bool);
    if (object)
        body(object)->boolean = value;
    return object;
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
