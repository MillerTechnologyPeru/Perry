// libPerryz: the provider for /usr/lib/libz.1.dylib, over Linux's zlib.
//
// The iOS SDK's zlib (1.2.12) and Ubuntu's (1.3) share z_stream and the
// rest of the API, so every import binds to Linux's zlib except gzprintf,
// whose variadic arguments thunks.S converts, and on armv7 the functions
// that set up and end a stream, below.

#include "PerryZ.h"
#include "perry_wrapped.h"

extern const char *zlibVersion(void);

static perry_wrapped_library zlib = PERRY_WRAPPED_LIBRARY(zlibVersion);

__attribute__((visibility("default")))
void *perry_provider_symbol(const char *name) {
    return perry_wrapped_symbol(&zlib, name, NULL);
}

#if defined(__arm__)

// A stream's zalloc and zfree are Darwin functions that Linux's zlib calls.
// Darwin's armv7 code may change r9, which Linux's keeps across calls: zlib
// would lose what it keeps there, as its output pointer, when it allocates
// its window in the middle of inflate. So while a stream is set up, its
// zalloc and zfree are this file's, which keep r9 around the Darwin ones,
// and its opaque is a record of those (zlib passes only the opaque). Ending
// the stream puts them back.

#include <stdlib.h>
#include <zlib.h>

#define DARWIN_SYMBOL(name) __asm__("_" #name) __attribute__((visibility("default"), used))

#define KEEP_R9(call) do { \
        unsigned long kept_r9; \
        __asm__ volatile("mov %0, r9" : "=r"(kept_r9)); \
        call; \
        __asm__ volatile("mov r9, %0" : : "r"(kept_r9) : "memory"); \
    } while (0)

typedef struct {
    alloc_func zalloc;
    free_func zfree;
    voidpf opaque;
} darwin_allocator;

// zlib's own allocation, where the program set only one of the two.
static voidpf keep_alloc(voidpf opaque, uInt items, uInt size) {
    darwin_allocator *allocator = opaque;
    if (!allocator->zalloc)
        return malloc((size_t)items * size);
    voidpf block;
    KEEP_R9(block = allocator->zalloc(allocator->opaque, items, size));
    return block;
}

static void keep_free(voidpf opaque, voidpf address) {
    darwin_allocator *allocator = opaque;
    if (!allocator->zfree) {
        free(address);
        return;
    }
    KEEP_R9(allocator->zfree(allocator->opaque, address));
}

/// Puts the stream's allocator behind this file's functions, unless it uses
/// zlib's or already is. Returns whether it did.
static int wrap(z_streamp stream) {
    if (!stream || stream->zalloc == keep_alloc || (!stream->zalloc && !stream->zfree))
        return 0;
    darwin_allocator *allocator = malloc(sizeof(*allocator));
    if (!allocator)
        return 0;
    *allocator = (darwin_allocator){ stream->zalloc, stream->zfree, stream->opaque };
    stream->zalloc = keep_alloc;
    stream->zfree = keep_free;
    stream->opaque = allocator;
    return 1;
}

/// Puts the program's allocator back.
static void unwrap(z_streamp stream) {
    if (!stream || stream->zalloc != keep_alloc)
        return;
    darwin_allocator *allocator = stream->opaque;
    stream->zalloc = allocator->zalloc;
    stream->zfree = allocator->zfree;
    stream->opaque = allocator->opaque;
    free(allocator);
}

/// After an init: a stream that failed to set up is the program's again.
static int set_up(z_streamp stream, int wrapped, int result) {
    if (wrapped && result != Z_OK)
        unwrap(stream);
    return result;
}

/// After a copy, which shares the source's record: the copy gets its own.
static int copied(z_streamp dest, int result, int (*end)(z_streamp)) {
    if (result != Z_OK || dest->zalloc != keep_alloc)
        return result;
    darwin_allocator *allocator = malloc(sizeof(*allocator));
    if (!allocator) {
        end(dest);
        dest->opaque = NULL;
        dest->zalloc = NULL;
        dest->zfree = NULL;
        return Z_MEM_ERROR;
    }
    *allocator = *(darwin_allocator *)dest->opaque;
    dest->opaque = allocator;
    return result;
}

int darwin_inflateInit_(z_streamp stream, const char *version, int size) DARWIN_SYMBOL(inflateInit_);
int darwin_inflateInit_(z_streamp stream, const char *version, int size) {
    int wrapped = wrap(stream);
    return set_up(stream, wrapped, inflateInit_(stream, version, size));
}

int darwin_inflateInit2_(z_streamp stream, int bits, const char *version, int size) DARWIN_SYMBOL(inflateInit2_);
int darwin_inflateInit2_(z_streamp stream, int bits, const char *version, int size) {
    int wrapped = wrap(stream);
    return set_up(stream, wrapped, inflateInit2_(stream, bits, version, size));
}

int darwin_inflateBackInit_(z_streamp stream, int bits, unsigned char *window, const char *version, int size)
    DARWIN_SYMBOL(inflateBackInit_);
int darwin_inflateBackInit_(z_streamp stream, int bits, unsigned char *window, const char *version, int size) {
    int wrapped = wrap(stream);
    return set_up(stream, wrapped, inflateBackInit_(stream, bits, window, version, size));
}

int darwin_deflateInit_(z_streamp stream, int level, const char *version, int size) DARWIN_SYMBOL(deflateInit_);
int darwin_deflateInit_(z_streamp stream, int level, const char *version, int size) {
    int wrapped = wrap(stream);
    return set_up(stream, wrapped, deflateInit_(stream, level, version, size));
}

int darwin_deflateInit2_(z_streamp stream, int level, int method, int bits, int memory, int strategy,
                         const char *version, int size) DARWIN_SYMBOL(deflateInit2_);
int darwin_deflateInit2_(z_streamp stream, int level, int method, int bits, int memory, int strategy,
                         const char *version, int size) {
    int wrapped = wrap(stream);
    return set_up(stream, wrapped, deflateInit2_(stream, level, method, bits, memory, strategy, version, size));
}

int darwin_inflateEnd(z_streamp stream) DARWIN_SYMBOL(inflateEnd);
int darwin_inflateEnd(z_streamp stream) {
    int result = inflateEnd(stream);
    unwrap(stream);
    return result;
}

int darwin_inflateBackEnd(z_streamp stream) DARWIN_SYMBOL(inflateBackEnd);
int darwin_inflateBackEnd(z_streamp stream) {
    int result = inflateBackEnd(stream);
    unwrap(stream);
    return result;
}

int darwin_deflateEnd(z_streamp stream) DARWIN_SYMBOL(deflateEnd);
int darwin_deflateEnd(z_streamp stream) {
    int result = deflateEnd(stream);
    unwrap(stream);
    return result;
}

int darwin_inflateCopy(z_streamp dest, z_streamp source) DARWIN_SYMBOL(inflateCopy);
int darwin_inflateCopy(z_streamp dest, z_streamp source) {
    return copied(dest, inflateCopy(dest, source), inflateEnd);
}

int darwin_deflateCopy(z_streamp dest, z_streamp source) DARWIN_SYMBOL(deflateCopy);
int darwin_deflateCopy(z_streamp dest, z_streamp source) {
    return copied(dest, deflateCopy(dest, source), deflateEnd);
}

#endif
