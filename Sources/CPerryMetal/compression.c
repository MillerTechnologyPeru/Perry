#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Metal's IO compression contexts (MTLIOCompressor.h), which asset tools
// write pack files with for MTLIOCommandQueue to read. The data is cut into
// chunks of the context's size and each chunk is compressed on its own, so
// a reader can decompress any one of them. Zlib chunks are real zlib
// streams, made with the system's libz, opened when a context first needs
// it; the other methods (LZFSE, LZ4, LZMA, LZBitmap), which Linux has no
// standard library for, and zlib without libz, keep their chunks stored as
// they are, which the chunk table records. The file is Perry's own layout,
// not Apple's pack format:
//
//   "PMIOPACK" | u32 version (1) | u32 method | u64 chunk size | u64 total size
//   | u64 chunk count | chunks: (u64 size, u64 stored size, u32 how stored
//   (0 stored, 1 zlib), u32 0, bytes)...
//
// all little-endian, the header rewritten with the counts when the context
// is flushed.

#define DARWIN_SYMBOL(name) __asm__(name) __attribute__((visibility("default"), used))

enum { METHOD_ZLIB = 0, METHOD_LZBITMAP = 4 };
enum { STATUS_COMPLETE = 0, STATUS_ERROR = 1 };
static const size_t default_chunk_size = 64 * 1024;

typedef struct {
    FILE *file;
    long method;
    size_t chunk_size;
    unsigned char *pending;
    size_t pending_length;
    uint64_t total;
    uint64_t chunks;
    int failed;
} perry_io_compression;

// zlib's compress2 and compressBound.
typedef int (*compress2_function)(unsigned char *, unsigned long *, const unsigned char *, unsigned long, int);
typedef unsigned long (*bound_function)(unsigned long);
static compress2_function zlib_compress2;
static bound_function zlib_bound;

static void open_zlib(void) {
    static int tried;
    if (tried)
        return;
    tried = 1;
    void *library = dlopen("libz.so.1", RTLD_NOW | RTLD_LOCAL);
    if (!library)
        library = dlopen("libz.so", RTLD_NOW | RTLD_LOCAL);
    if (!library)
        return;
    zlib_compress2 = (compress2_function)dlsym(library, "compress2");
    zlib_bound = (bound_function)dlsym(library, "compressBound");
    if (!zlib_compress2 || !zlib_bound)
        zlib_compress2 = NULL;
}

static int write_u64(FILE *file, uint64_t value) {
    unsigned char bytes[8];
    for (int i = 0; i < 8; i++)
        bytes[i] = (unsigned char)(value >> (8 * i));
    return fwrite(bytes, 1, 8, file) == 8;
}

static int write_u32(FILE *file, uint32_t value) {
    unsigned char bytes[4];
    for (int i = 0; i < 4; i++)
        bytes[i] = (unsigned char)(value >> (8 * i));
    return fwrite(bytes, 1, 4, file) == 4;
}

static int write_header(perry_io_compression *context) {
    return fseek(context->file, 0, SEEK_SET) == 0 && fwrite("PMIOPACK", 1, 8, context->file) == 8 &&
           write_u32(context->file, 1) && write_u32(context->file, (uint32_t)context->method) &&
           write_u64(context->file, context->chunk_size) && write_u64(context->file, context->total) &&
           write_u64(context->file, context->chunks);
}

/// Writes the pending bytes as one chunk.
static void write_chunk(perry_io_compression *context) {
    if (context->pending_length == 0 || context->failed)
        return;
    const unsigned char *bytes = context->pending;
    uint64_t stored = context->pending_length;
    uint32_t how = 0;
    unsigned char *compressed = NULL;
    if (context->method == METHOD_ZLIB && zlib_compress2) {
        unsigned long capacity = zlib_bound(context->pending_length);
        compressed = malloc(capacity);
        // Kept compressed only when that is smaller.
        if (compressed && zlib_compress2(compressed, &capacity, context->pending, context->pending_length, 6) == 0 &&
            capacity < context->pending_length) {
            bytes = compressed;
            stored = capacity;
            how = 1;
        }
    }
    if (!write_u64(context->file, context->pending_length) || !write_u64(context->file, stored) ||
        !write_u32(context->file, how) || !write_u32(context->file, 0) ||
        fwrite(bytes, 1, stored, context->file) != stored)
        context->failed = 1;
    free(compressed);
    context->chunks++;
    context->pending_length = 0;
}

size_t perry_MTLIOCompressionContextDefaultChunkSize(void) DARWIN_SYMBOL("_MTLIOCompressionContextDefaultChunkSize");
size_t perry_MTLIOCompressionContextDefaultChunkSize(void) { return default_chunk_size; }

void *perry_MTLIOCreateCompressionContext(const char *path, long type, size_t chunk_size)
    DARWIN_SYMBOL("_MTLIOCreateCompressionContext");
void *perry_MTLIOCreateCompressionContext(const char *path, long type, size_t chunk_size) {
    if (type < METHOD_ZLIB || type > METHOD_LZBITMAP)
        return NULL;
    if (!path) {
        errno = EINVAL;
        return NULL;
    }
    perry_io_compression *context = calloc(1, sizeof(*context));
    if (!context)
        return NULL;
    context->method = type;
    context->chunk_size = chunk_size ? chunk_size : default_chunk_size;
    context->pending = malloc(context->chunk_size);
    context->file = context->pending ? fopen(path, "wb") : NULL;
    if (!context->file || !write_header(context)) {
        int saved = errno;
        if (context->file)
            fclose(context->file);
        free(context->pending);
        free(context);
        errno = saved;
        return NULL;
    }
    if (type == METHOD_ZLIB)
        open_zlib();
    return context;
}

void perry_MTLIOCompressionContextAppendData(void *opaque, const void *data, size_t size)
    DARWIN_SYMBOL("_MTLIOCompressionContextAppendData");
void perry_MTLIOCompressionContextAppendData(void *opaque, const void *data, size_t size) {
    perry_io_compression *context = opaque;
    if (!context || (!data && size))
        return;
    const unsigned char *bytes = data;
    context->total += size;
    while (size > 0) {
        size_t room = context->chunk_size - context->pending_length;
        size_t count = size < room ? size : room;
        memcpy(context->pending + context->pending_length, bytes, count);
        context->pending_length += count;
        bytes += count;
        size -= count;
        if (context->pending_length == context->chunk_size)
            write_chunk(context);
    }
}

long perry_MTLIOFlushAndDestroyCompressionContext(void *opaque) DARWIN_SYMBOL("_MTLIOFlushAndDestroyCompressionContext");
long perry_MTLIOFlushAndDestroyCompressionContext(void *opaque) {
    perry_io_compression *context = opaque;
    if (!context)
        return STATUS_ERROR;
    write_chunk(context);
    int ok = !context->failed && write_header(context);
    ok = fclose(context->file) == 0 && ok;
    free(context->pending);
    free(context);
    return ok ? STATUS_COMPLETE : STATUS_ERROR;
}
