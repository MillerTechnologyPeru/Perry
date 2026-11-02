// Blocks runtime: Darwin's _Block_copy family, written from clang's
// published Block ABI specification (clang/docs/Block-ABI-Apple.rst).
//
// The _NSConcrete*Block symbols are class storage: the Objective-C runtime
// (libPerryobjc) builds the block classes inside them at startup so blocks
// can be messaged, and installs retain/release for captured objects through
// _Block_use_RR2.

#include "PerrySystem.h"

#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// MARK: - Layouts

enum {
    BLOCK_DEALLOCATING = 0x0001,
    BLOCK_REFCOUNT_MASK = 0xfffe,       // reference count in steps of 2
    BLOCK_NEEDS_FREE = 1 << 24,         // heap block
    BLOCK_HAS_COPY_DISPOSE = 1 << 25,
    BLOCK_IS_GLOBAL = 1 << 28,
    BLOCK_HAS_SIGNATURE = 1 << 30,
};

// Flags passed to _Block_object_assign and _Block_object_dispose.
enum {
    FIELD_IS_OBJECT = 3,
    FIELD_IS_BLOCK = 7,
    FIELD_IS_BYREF = 8,
    FIELD_IS_WEAK = 16,
    BYREF_CALLER = 128,
    FIELD_KIND_MASK = FIELD_IS_OBJECT | FIELD_IS_BLOCK | FIELD_IS_BYREF | FIELD_IS_WEAK | BYREF_CALLER,
};

// Flags of a __block variable.
enum {
    BYREF_NEEDS_FREE = 1 << 24,
    BYREF_HAS_COPY_DISPOSE = 1 << 25,
    BYREF_LAYOUT_EXTENDED = 1 << 28,
};

struct block_descriptor {
    uintptr_t reserved;
    uintptr_t size;
    // Then block_helpers if BLOCK_HAS_COPY_DISPOSE, then block_signature
    // if BLOCK_HAS_SIGNATURE.
};

struct block_helpers {
    void (*copy)(void *dst, const void *src);
    void (*dispose)(const void *block);
};

struct block_signature {
    const char *signature;
    const char *layout;
};

struct block_layout {
    void *isa;
    _Atomic int32_t flags;
    int32_t reserved;
    void (*invoke)(void);
    struct block_descriptor *descriptor;
    // Captured variables follow.
};

struct block_byref {
    void *isa;
    struct block_byref *forwarding;
    _Atomic int32_t flags;
    uint32_t size;
    // Then byref_helpers if BYREF_HAS_COPY_DISPOSE, then the layout string
    // if BYREF_LAYOUT_EXTENDED, then the variable.
};

struct byref_helpers {
    void (*keep)(struct block_byref *dst, struct block_byref *src);
    void (*destroy)(struct block_byref *byref);
};

// MARK: - Class storage

// Each holds a class in words 0-15 and its metaclass in words 16-31.
void *darwin_NSConcreteStackBlock[32] DARWIN_SYMBOL(_NSConcreteStackBlock);
void *darwin_NSConcreteMallocBlock[32] DARWIN_SYMBOL(_NSConcreteMallocBlock);
void *darwin_NSConcreteGlobalBlock[32] DARWIN_SYMBOL(_NSConcreteGlobalBlock);
void *darwin_NSConcreteAutoBlock[32] DARWIN_SYMBOL(_NSConcreteAutoBlock);
void *darwin_NSConcreteFinalizingBlock[32] DARWIN_SYMBOL(_NSConcreteFinalizingBlock);
void *darwin_NSConcreteWeakBlockVariable[32] DARWIN_SYMBOL(_NSConcreteWeakBlockVariable);

// MARK: - Object callbacks

struct block_callbacks_rr {
    size_t size;
    void (*retain)(const void *object);
    void (*release)(const void *object);
    void (*destruct_instance)(const void *object);
};

static void ignore_object(const void *object) { (void)object; }

static void (*retain_object)(const void *) = ignore_object;
static void (*release_object)(const void *) = ignore_object;

void darwin_Block_use_RR2(const struct block_callbacks_rr *callbacks) DARWIN_SYMBOL(_Block_use_RR2);
void darwin_Block_use_RR2(const struct block_callbacks_rr *callbacks) {
    retain_object = callbacks->retain;
    release_object = callbacks->release;
}

// MARK: - Reference counts

// Counts saturate: a count at the maximum stays there and is never freed.
static void count_increment(_Atomic int32_t *flags) {
    int32_t old = atomic_load_explicit(flags, memory_order_relaxed);
    do {
        if ((old & BLOCK_REFCOUNT_MASK) == BLOCK_REFCOUNT_MASK)
            return;
    } while (!atomic_compare_exchange_weak(flags, &old, old + 2));
}

// Returns true when the count drops to zero; the caller then frees.
static bool count_decrement(_Atomic int32_t *flags) {
    int32_t old = atomic_load_explicit(flags, memory_order_relaxed);
    int32_t new;
    do {
        int32_t count = old & BLOCK_REFCOUNT_MASK;
        if (count == BLOCK_REFCOUNT_MASK || count == 0)
            return false;
        new = old - 2;
        if (count == 2)
            new |= BLOCK_DEALLOCATING;
    } while (!atomic_compare_exchange_weak(flags, &old, new));
    return (new & BLOCK_REFCOUNT_MASK) == 0;
}

static const struct block_helpers *block_helpers(const struct block_layout *block) {
    return (const struct block_helpers *)(block->descriptor + 1);
}

// MARK: - Blocks

void *darwin_Block_copy(const void *arg) DARWIN_SYMBOL(_Block_copy);
void *darwin_Block_copy(const void *arg) {
    struct block_layout *block = (struct block_layout *)arg;
    if (!block)
        return NULL;
    int32_t flags = atomic_load_explicit(&block->flags, memory_order_relaxed);
    if (flags & BLOCK_NEEDS_FREE) {
        count_increment(&block->flags);
        return block;
    }
    if (flags & BLOCK_IS_GLOBAL)
        return block;

    // A stack block: move it to the heap with a count of one.
    size_t size = block->descriptor->size;
    struct block_layout *copy = malloc(size);
    if (!copy)
        return NULL;
    memcpy(copy, block, size);
    flags &= ~(BLOCK_REFCOUNT_MASK | BLOCK_DEALLOCATING);
    atomic_store_explicit(&copy->flags, flags | BLOCK_NEEDS_FREE | 2, memory_order_relaxed);
    copy->isa = darwin_NSConcreteMallocBlock;
    if (flags & BLOCK_HAS_COPY_DISPOSE)
        block_helpers(block)->copy(copy, block);
    return copy;
}

void darwin_Block_release(const void *arg) DARWIN_SYMBOL(_Block_release);
void darwin_Block_release(const void *arg) {
    struct block_layout *block = (struct block_layout *)arg;
    if (!block)
        return;
    int32_t flags = atomic_load_explicit(&block->flags, memory_order_relaxed);
    if ((flags & BLOCK_IS_GLOBAL) || !(flags & BLOCK_NEEDS_FREE))
        return;
    if (count_decrement(&block->flags)) {
        if (flags & BLOCK_HAS_COPY_DISPOSE)
            block_helpers(block)->dispose(block);
        free(block);
    }
}

// MARK: - __block variables

static struct block_byref *byref_copy(struct block_byref *src) {
    struct block_byref *current = src->forwarding;
    int32_t flags = atomic_load_explicit(&current->flags, memory_order_relaxed);
    if ((flags & BLOCK_REFCOUNT_MASK) != 0) {
        // Already on the heap: one more reference.
        if (flags & BYREF_NEEDS_FREE)
            count_increment(&current->flags);
        return current;
    }

    // First copy: move the variable to the heap. The count of two covers
    // the heap copy and the stack frame that still forwards to it.
    struct block_byref *copy = malloc(src->size);
    copy->isa = NULL;
    atomic_store_explicit(&copy->flags, flags | BYREF_NEEDS_FREE | 4, memory_order_relaxed);
    copy->forwarding = copy;
    copy->size = src->size;
    src->forwarding = copy;
    if (flags & BYREF_HAS_COPY_DISPOSE) {
        const struct byref_helpers *src_helpers = (const struct byref_helpers *)(src + 1);
        struct byref_helpers *copy_helpers = (struct byref_helpers *)(copy + 1);
        *copy_helpers = *src_helpers;
        if (flags & BYREF_LAYOUT_EXTENDED)
            *(const char **)(copy_helpers + 1) = *(const char *const *)(src_helpers + 1);
        // The variable's own helper copies (and retains) its value.
        src_helpers->keep(copy, src);
    } else {
        memcpy(copy + 1, src + 1, src->size - sizeof(*src));
    }
    return copy;
}

static void byref_release(struct block_byref *byref) {
    byref = byref->forwarding;
    int32_t flags = atomic_load_explicit(&byref->flags, memory_order_relaxed);
    if (!(flags & BYREF_NEEDS_FREE))
        return;
    if (count_decrement(&byref->flags)) {
        if (flags & BYREF_HAS_COPY_DISPOSE)
            ((const struct byref_helpers *)(byref + 1))->destroy(byref);
        free(byref);
    }
}

// MARK: - Copy and dispose helpers

void darwin_Block_object_assign(void *dest, const void *object, int flags) DARWIN_SYMBOL(_Block_object_assign);
void darwin_Block_object_assign(void *dest, const void *object, int flags) {
    const void **slot = dest;
    switch (flags & FIELD_KIND_MASK) {
    case FIELD_IS_OBJECT:
        retain_object(object);
        *slot = object;
        break;
    case FIELD_IS_BLOCK:
        *slot = darwin_Block_copy(object);
        break;
    case FIELD_IS_BYREF:
    case FIELD_IS_BYREF | FIELD_IS_WEAK:
        *slot = byref_copy((struct block_byref *)object);
        break;
    default:
        // BYREF_CALLER: the __block variable's own helpers copy the value
        // without taking a reference.
        *slot = object;
        break;
    }
}

void darwin_Block_object_dispose(const void *object, int flags) DARWIN_SYMBOL(_Block_object_dispose);
void darwin_Block_object_dispose(const void *object, int flags) {
    switch (flags & FIELD_KIND_MASK) {
    case FIELD_IS_OBJECT:
        release_object(object);
        break;
    case FIELD_IS_BLOCK:
        darwin_Block_release(object);
        break;
    case FIELD_IS_BYREF:
    case FIELD_IS_BYREF | FIELD_IS_WEAK:
        byref_release((struct block_byref *)object);
        break;
    default:
        break;
    }
}

// MARK: - Introspection

static const struct block_signature *block_signature(const struct block_layout *block) {
    int32_t flags = atomic_load_explicit(&((struct block_layout *)block)->flags, memory_order_relaxed);
    if (!(flags & BLOCK_HAS_SIGNATURE))
        return NULL;
    const uint8_t *p = (const uint8_t *)(block->descriptor + 1);
    if (flags & BLOCK_HAS_COPY_DISPOSE)
        p += sizeof(struct block_helpers);
    return (const struct block_signature *)p;
}

bool darwin_Block_has_signature(const void *block) DARWIN_SYMBOL(_Block_has_signature);
bool darwin_Block_has_signature(const void *block) {
    return block_signature(block) != NULL;
}

const char *darwin_Block_signature(const void *block) DARWIN_SYMBOL(_Block_signature);
const char *darwin_Block_signature(const void *block) {
    const struct block_signature *sig = block_signature(block);
    return sig ? sig->signature : NULL;
}

size_t darwin_Block_size(const void *block) DARWIN_SYMBOL(Block_size);
size_t darwin_Block_size(const void *block) {
    return ((const struct block_layout *)block)->descriptor->size;
}

bool darwin_Block_isDeallocating(const void *block) DARWIN_SYMBOL(_Block_isDeallocating);
bool darwin_Block_isDeallocating(const void *block) {
    struct block_layout *b = (struct block_layout *)block;
    return atomic_load_explicit(&b->flags, memory_order_relaxed) & BLOCK_DEALLOCATING;
}

bool darwin_Block_tryRetain(const void *block) DARWIN_SYMBOL(_Block_tryRetain);
bool darwin_Block_tryRetain(const void *block) {
    struct block_layout *b = (struct block_layout *)block;
    int32_t old = atomic_load_explicit(&b->flags, memory_order_relaxed);
    do {
        if (old & BLOCK_DEALLOCATING)
            return false;
        if ((old & BLOCK_REFCOUNT_MASK) == BLOCK_REFCOUNT_MASK)
            return true;
    } while (!atomic_compare_exchange_weak(&b->flags, &old, old + 2));
    return true;
}
