#ifndef CPERRY_OBJC_H
#define CPERRY_OBJC_H

// The parts of libPerryobjc that must be C or assembly: Apple's arm64
// Objective-C metadata layouts, the exported class storage and data symbols,
// and objc_msgSend. Layouts follow what clang and ld64 emit into Mach-O
// images; they are written here from the format, not from Apple's headers.

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// MARK: - Metadata emitted by the compiler

// objc_class. `cache` belongs to the runtime: Mach-O images point it at
// _objc_empty_cache, and realization replaces it with a perry_class_header.
typedef struct perry_objc_class {
    struct perry_objc_class *isa;
    struct perry_objc_class *superclass;
    void *cache;
    void *vtable;
    uintptr_t bits;                 // perry_class_ro * plus Swift flag bits
} perry_objc_class;

// `bits` holds the class_ro_t pointer, with Swift flags in the low bits.
// Apple masks it to 47 bits; the runtime clears only the low three, since
// classes it builds have their class_ro_t on the Linux heap above 2^47.

enum {
    PERRY_RO_META = 1 << 0,
    PERRY_RO_ROOT = 1 << 1,
    PERRY_RO_HAS_CXX_STRUCTORS = 1 << 2,
};

// class_ro_t
typedef struct perry_class_ro {
    uint32_t flags;
    uint32_t instance_start;
    uint32_t instance_size;
    uint32_t reserved;
    const uint8_t *ivar_layout;
    const char *name;
    const void *base_methods;       // method list
    const void *base_protocols;     // protocol list
    const void *ivars;              // ivar list
    const uint8_t *weak_ivar_layout;
    const void *base_properties;
} perry_class_ro;

// Method lists: a header, then entries of `entsize` bytes.
typedef struct perry_list_header {
    uint32_t entsize_and_flags;
    uint32_t count;
} perry_list_header;

enum {
    PERRY_METHOD_LIST_RELATIVE = (int32_t)0x80000000,    // small entries of 32-bit offsets
    PERRY_METHOD_LIST_DIRECT_SELECTORS = 0x40000000,     // small names point at strings
    PERRY_LIST_ENTSIZE_MASK = 0x0000fffc,
};

// A full method entry. Also the runtime's Method.
typedef struct perry_method {
    const char *name;               // SEL
    const char *types;
    void *imp;
} perry_method;

// A small method entry: each field is an offset from itself. `name`
// points at a selector reference unless the list has direct selectors.
typedef struct perry_small_method {
    int32_t name;
    int32_t types;
    int32_t imp;
} perry_small_method;

// category_t
typedef struct perry_category {
    const char *name;
    perry_objc_class *cls;
    const void *instance_methods;
    const void *class_methods;
    const void *protocols;
    const void *instance_properties;
} perry_category;

// protocol_t
typedef struct perry_protocol {
    void *isa;
    const char *name;
    const void *protocols;          // protocol list: uint64_t count, then pointers
    const void *instance_methods;
    const void *class_methods;
    const void *optional_instance_methods;
    const void *optional_class_methods;
    const void *instance_properties;
    uint32_t size;
    uint32_t flags;
} perry_protocol;

// ivar_t. arm64 ivar offset variables are 32 bits.
typedef struct perry_ivar {
    int32_t *offset;
    const char *name;
    const char *type;
    uint32_t alignment_raw;
    uint32_t size;
} perry_ivar;

// objc_method_description and objc_property_attribute_t, returned and
// filled in by value.
typedef struct perry_method_description {
    const char *name;
    const char *types;
} perry_method_description;

typedef struct perry_property_attribute {
    const char *name;
    const char *value;
} perry_property_attribute;

// MARK: - Runtime state read by objc_msgSend

// What a realized class's `cache` points to. objc_msgSend loads `cache`
// and probes it: `mask`, then `mask + 1` buckets of {sel, imp}. A bucket
// with a selector but no IMP yet is a miss.
typedef struct perry_class_header {
    void *cache;
    void *info;                     // the Swift ClassInfo, unretained
} perry_class_header;

typedef struct perry_cache_bucket {
    const void *sel;
    void *imp;
} perry_cache_bucket;

// The cache every unrealized class starts with: one empty bucket.
void *perry_objc_empty_cache_table(void);

// The address of _objc_empty_cache, which Mach-O classes reference.
void *perry_objc_empty_cache(void);

static inline void perry_store_release(void **slot, void *value) {
    __atomic_store_n(slot, value, __ATOMIC_RELEASE);
}

static inline void *perry_load_acquire(void *const *slot) {
    return __atomic_load_n(slot, __ATOMIC_ACQUIRE);
}

static inline void perry_release_fence(void) {
    __atomic_thread_fence(__ATOMIC_RELEASE);
}

// MARK: - Exported class storage

perry_objc_class *perry_objc_nsobject_class(void);
perry_objc_class *perry_objc_nsobject_metaclass(void);
perry_objc_class *perry_objc_protocol_class(void);
perry_objc_class *perry_objc_protocol_metaclass(void);

// MARK: - Messaging (msgsend.S)

// Addresses of the assembly entry points, to call through a typed pointer.
const void *perry_objc_msgSend_address(void);
const void *perry_objc_msgSendSuper2_address(void);
const void *perry_objc_msgForward_address(void);

// objc_msgSend's slow path, implemented in Swift: the IMP for `sel` sent to
// `receiver`, whose class (or, for super sends, the starting class) is `cls`.
void *perry_objc_lookup_slow(void *receiver, const void *sel, perry_objc_class *cls);

// _objc_msgForward's decision, implemented in Swift: send to `target`
// instead, or jump to `handler` with the original arguments.
typedef struct perry_forward_result {
    void *target;
    void *handler;
} perry_forward_result;

perry_forward_result perry_objc_forward(void *receiver, const void *sel);

// MARK: - Blocks runtime

// What _Block_use_RR2 takes: how blocks retain the objects they capture.
typedef struct perry_block_callbacks {
    size_t size;
    void (*retain)(const void *object);
    void (*release)(const void *object);
    void (*destruct_instance)(const void *object);
} perry_block_callbacks;

#endif
