// libPerrycompression: the provider for /usr/lib/libcompression.dylib.
//
// libcompression is an Apple API, so this implements it over the open
// libraries for each format: ZLIB is raw DEFLATE (RFC 1951) from zlib,
// LZMA an XZ stream from liblzma, LZ4_RAW a raw LZ4 block, LZ4 raw blocks
// in Apple's container ("bv41" blocks ending with "bv4$"), BROTLI a Brotli
// stream, and LZFSE Apple's open-source LZFSE. LZBITMAP and the newer
// buffer-only formats are not documented and are reported as failures.
//
// Encoders produce valid streams in each format that Darwin decodes, not
// necessarily Darwin's bytes; decoders read what Darwin produces.

#define _GNU_SOURCE
#include "PerryCompression.h"

#include <brotli/decode.h>
#include <brotli/encode.h>
#include <lz4.h>
#include <lzfse.h>
#include <lzma.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

#define DARWIN_SYMBOL(name) __asm__("_" #name) __attribute__((visibility("default"), used))

typedef enum {
    COMPRESSION_LZ4 = 0x100,
    COMPRESSION_ZLIB = 0x205,
    COMPRESSION_LZMA = 0x306,
    COMPRESSION_LZ4_RAW = 0x101,
    COMPRESSION_BROTLI = 0xB02,
    COMPRESSION_LZFSE = 0x801,
} compression_algorithm;

typedef struct {
    uint8_t *dst_ptr;
    size_t dst_size;
    const uint8_t *src_ptr;
    size_t src_size;
    void *state;
} compression_stream;

enum { COMPRESSION_STREAM_ENCODE = 0, COMPRESSION_STREAM_DECODE = 1 };
enum { COMPRESSION_STREAM_FINALIZE = 1 };
enum { COMPRESSION_STATUS_OK = 0, COMPRESSION_STATUS_ERROR = -1, COMPRESSION_STATUS_END = 1 };

// Levels as Apple documents them: zlib level 5, LZMA preset 6.
enum { ZLIB_LEVEL = 5, LZMA_PRESET = 6, BROTLI_QUALITY = 5 };

// MARK: - Apple's LZ4 container

enum { LZ4_BLOCK_SIZE = 64 * 1024 };

static const uint8_t lz4_compressed_magic[4] = { 'b', 'v', '4', '1' };
static const uint8_t lz4_raw_magic[4] = { 'b', 'v', '4', '-' };
static const uint8_t lz4_end_magic[4] = { 'b', 'v', '4', '$' };

static uint32_t load32(const uint8_t *p) { return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24; }
static void store32(uint8_t *p, uint32_t v) { p[0] = v; p[1] = v >> 8; p[2] = v >> 16; p[3] = v >> 24; }

/// Encodes into dst; the size written, or 0 if it does not fit.
static size_t lz4_frame_encode(uint8_t *dst, size_t dst_size, const uint8_t *src, size_t src_size) {
    size_t written = 0;
    for (size_t offset = 0; offset < src_size; offset += LZ4_BLOCK_SIZE) {
        int length = (int)(src_size - offset < LZ4_BLOCK_SIZE ? src_size - offset : LZ4_BLOCK_SIZE);
        if (written + 12 > dst_size)
            return 0;
        int encoded = LZ4_compress_default((const char *)src + offset, (char *)dst + written + 12, length,
                                           (int)(dst_size - written - 12 > INT32_MAX ? INT32_MAX : dst_size - written - 12));
        if (encoded <= 0)
            return 0;
        memcpy(dst + written, lz4_compressed_magic, 4);
        store32(dst + written + 4, (uint32_t)length);
        store32(dst + written + 8, (uint32_t)encoded);
        written += 12 + (size_t)encoded;
    }
    if (written + 4 > dst_size)
        return 0;
    memcpy(dst + written, lz4_end_magic, 4);
    return written + 4;
}

/// The decoded size of a complete container, or -1 if it is incomplete or
/// malformed; `end` gets the container's length.
static long long lz4_frame_size(const uint8_t *src, size_t src_size, size_t *end) {
    size_t offset = 0;
    unsigned long long total = 0;
    while (offset + 4 <= src_size) {
        const uint8_t *block = src + offset;
        if (memcmp(block, lz4_end_magic, 4) == 0) {
            if (end)
                *end = offset + 4;
            return (long long)total;
        }
        if (memcmp(block, lz4_compressed_magic, 4) == 0) {
            if (offset + 12 > src_size)
                return -1;
            total += load32(block + 4);
            offset += 12 + load32(block + 8);
        } else if (memcmp(block, lz4_raw_magic, 4) == 0) {
            if (offset + 8 > src_size)
                return -1;
            total += load32(block + 4);
            offset += 8 + load32(block + 4);
        } else {
            return -1;
        }
    }
    return -1;
}

/// Decodes a complete container into dst, which must hold all of it.
static int lz4_frame_decode(uint8_t *dst, const uint8_t *src, size_t src_size) {
    size_t offset = 0, written = 0;
    while (offset + 4 <= src_size) {
        const uint8_t *block = src + offset;
        if (memcmp(block, lz4_end_magic, 4) == 0)
            return 1;
        uint32_t length = load32(block + 4);
        if (memcmp(block, lz4_compressed_magic, 4) == 0) {
            uint32_t encoded = load32(block + 8);
            if (offset + 12 + encoded > src_size)
                return 0;
            // A block may refer back into earlier output.
            int decoded = LZ4_decompress_safe_usingDict((const char *)block + 12, (char *)dst + written, (int)encoded,
                                                        (int)length, (const char *)dst, (int)written);
            if (decoded != (int)length)
                return 0;
            offset += 12 + encoded;
        } else {
            if (offset + 8 + length > src_size)
                return 0;
            memcpy(dst + written, block + 8, length);
            offset += 8 + length;
        }
        written += length;
    }
    return 0;
}

// MARK: - Whole-buffer coding

/// Encodes `src`; the size written to dst, or 0 if it does not fit.
static size_t encode(uint8_t *dst, size_t dst_size, const uint8_t *src, size_t src_size, void *scratch,
                     compression_algorithm algorithm) {
    switch (algorithm) {
    case COMPRESSION_ZLIB: {
        z_stream z = {0};
        if (deflateInit2(&z, ZLIB_LEVEL, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY) != Z_OK)
            return 0;
        z.next_in = (Bytef *)src;
        z.avail_in = (uInt)src_size;
        z.next_out = dst;
        z.avail_out = (uInt)dst_size;
        int status = deflate(&z, Z_FINISH);
        size_t written = z.total_out;
        deflateEnd(&z);
        return status == Z_STREAM_END ? written : 0;
    }
    case COMPRESSION_LZMA: {
        size_t written = 0;
        return lzma_easy_buffer_encode(LZMA_PRESET, LZMA_CHECK_CRC64, NULL, src, src_size, dst, &written, dst_size)
                   == LZMA_OK ? written : 0;
    }
    case COMPRESSION_LZ4_RAW:
        return (size_t)(LZ4_compress_default((const char *)src, (char *)dst, (int)src_size,
                                             (int)(dst_size > INT32_MAX ? INT32_MAX : dst_size)));
    case COMPRESSION_LZ4:
        return lz4_frame_encode(dst, dst_size, src, src_size);
    case COMPRESSION_LZFSE:
        return lzfse_encode_buffer(dst, dst_size, src, src_size, scratch);
    case COMPRESSION_BROTLI: {
        size_t written = dst_size;
        return BrotliEncoderCompress(BROTLI_QUALITY, BROTLI_DEFAULT_WINDOW, BROTLI_MODE_GENERIC, src_size, src,
                                     &written, dst) ? written : 0;
    }
    }
    return 0;
}

/// Decodes `src` into dst: the size written, or 0 on error. When dst is too
/// small, ZLIB, LZ4 and LZFSE return dst_size, the data truncated to fit;
/// LZMA and BROTLI return 0 after writing what fits, as Darwin's do.
static size_t decode(uint8_t *dst, size_t dst_size, const uint8_t *src, size_t src_size, void *scratch,
                     compression_algorithm algorithm) {
    switch (algorithm) {
    case COMPRESSION_ZLIB: {
        z_stream z = {0};
        if (inflateInit2(&z, -15) != Z_OK)
            return 0;
        z.next_in = (Bytef *)src;
        z.avail_in = (uInt)src_size;
        z.next_out = dst;
        z.avail_out = (uInt)dst_size;
        int status = inflate(&z, Z_FINISH);
        size_t written = z.total_out;
        inflateEnd(&z);
        if (status == Z_STREAM_END || (z.avail_out == 0 && (status == Z_OK || status == Z_BUF_ERROR)))
            return written;
        return 0;
    }
    case COMPRESSION_LZMA: {
        lzma_stream s = LZMA_STREAM_INIT;
        if (lzma_stream_decoder(&s, UINT64_MAX, 0) != LZMA_OK)
            return 0;
        s.next_in = src;
        s.avail_in = src_size;
        s.next_out = dst;
        s.avail_out = dst_size;
        lzma_ret status = lzma_code(&s, LZMA_FINISH);
        size_t written = s.total_out;
        lzma_end(&s);
        return status == LZMA_STREAM_END ? written : 0;
    }
    case COMPRESSION_LZ4_RAW: {
        int written = LZ4_decompress_safe_partial((const char *)src, (char *)dst, (int)src_size,
                                                  (int)(dst_size > INT32_MAX ? INT32_MAX : dst_size),
                                                  (int)(dst_size > INT32_MAX ? INT32_MAX : dst_size));
        return written < 0 ? 0 : (size_t)written;
    }
    case COMPRESSION_LZ4: {
        long long total = lz4_frame_size(src, src_size, NULL);
        if (total < 0)
            return 0;
        uint8_t *all = malloc(total ? (size_t)total : 1);
        if (!all || !lz4_frame_decode(all, src, src_size)) {
            free(all);
            return 0;
        }
        size_t written = (size_t)total < dst_size ? (size_t)total : dst_size;
        memcpy(dst, all, written);
        free(all);
        return written;
    }
    case COMPRESSION_LZFSE:
        return lzfse_decode_buffer(dst, dst_size, src, src_size, scratch);
    case COMPRESSION_BROTLI: {
        BrotliDecoderState *state = BrotliDecoderCreateInstance(NULL, NULL, NULL);
        if (!state)
            return 0;
        size_t in_left = src_size, out_left = dst_size, written = 0;
        const uint8_t *in = src;
        uint8_t *out = dst;
        BrotliDecoderResult result = BrotliDecoderDecompressStream(state, &in_left, &in, &out_left, &out, &written);
        BrotliDecoderDestroyInstance(state);
        return result == BROTLI_DECODER_RESULT_SUCCESS ? written : 0;
    }
    }
    return 0;
}

size_t darwin_compression_encode_scratch_buffer_size(compression_algorithm algorithm)
    DARWIN_SYMBOL(compression_encode_scratch_buffer_size);
size_t darwin_compression_decode_scratch_buffer_size(compression_algorithm algorithm)
    DARWIN_SYMBOL(compression_decode_scratch_buffer_size);
size_t darwin_compression_encode_buffer(uint8_t *dst, size_t dst_size, const uint8_t *src, size_t src_size,
                                        void *scratch, compression_algorithm algorithm)
    DARWIN_SYMBOL(compression_encode_buffer);
size_t darwin_compression_decode_buffer(uint8_t *dst, size_t dst_size, const uint8_t *src, size_t src_size,
                                        void *scratch, compression_algorithm algorithm)
    DARWIN_SYMBOL(compression_decode_buffer);

/// Only LZFSE uses a caller's scratch buffer; the others need none.
size_t darwin_compression_encode_scratch_buffer_size(compression_algorithm algorithm) {
    return algorithm == COMPRESSION_LZFSE ? lzfse_encode_scratch_size() : 0;
}

size_t darwin_compression_decode_scratch_buffer_size(compression_algorithm algorithm) {
    return algorithm == COMPRESSION_LZFSE ? lzfse_decode_scratch_size() : 0;
}

size_t darwin_compression_encode_buffer(uint8_t *dst, size_t dst_size, const uint8_t *src, size_t src_size,
                                        void *scratch, compression_algorithm algorithm) {
    if (!dst || (!src && src_size))
        return 0;
    return encode(dst, dst_size, src, src_size, scratch, algorithm);
}

size_t darwin_compression_decode_buffer(uint8_t *dst, size_t dst_size, const uint8_t *src, size_t src_size,
                                        void *scratch, compression_algorithm algorithm) {
    if (!dst || (!src && src_size))
        return 0;
    return decode(dst, dst_size, src, src_size, scratch, algorithm);
}

// MARK: - Streams

/// A stream's state. ZLIB, LZMA and BROTLI stream through their libraries;
/// LZ4 and LZFSE collect the input and code it whole, then hand the result
/// out across calls.
typedef struct stream_state {
    compression_algorithm algorithm;
    int operation;
    z_stream zlib;
    lzma_stream lzma;
    BrotliEncoderState *brotli_encoder;
    BrotliDecoderState *brotli_decoder;
    uint8_t *input;
    size_t input_size, input_capacity;
    uint8_t *output;
    size_t output_size, output_offset;
    int coded;
} stream_state;

static int append(stream_state *state, const uint8_t *bytes, size_t count) {
    if (state->input_size + count > state->input_capacity) {
        size_t capacity = state->input_capacity ? state->input_capacity : 4096;
        while (capacity < state->input_size + count)
            capacity *= 2;
        uint8_t *grown = realloc(state->input, capacity);
        if (!grown)
            return 0;
        state->input = grown;
        state->input_capacity = capacity;
    }
    memcpy(state->input + state->input_size, bytes, count);
    state->input_size += count;
    return 1;
}

/// Codes the collected input: 1 when done, 0 if the input is not complete
/// yet (decoding), -1 on error.
static int code_collected(stream_state *state, int final) {
    const uint8_t *in = state->input;
    size_t n = state->input_size;
    if (state->operation == COMPRESSION_STREAM_ENCODE) {
        if (!final)
            return 0;
        size_t capacity = n + n / 2 + 1024;
        for (;;) {
            uint8_t *out = malloc(capacity);
            if (!out)
                return -1;
            size_t written = encode(out, capacity, in, n, NULL, state->algorithm);
            if (written) {
                state->output = out;
                state->output_size = written;
                return 1;
            }
            free(out);
            if (capacity > (n + 1024) * 8)
                return -1;
            capacity *= 2;
        }
    }
    if (state->algorithm == COMPRESSION_LZ4) {
        long long total = lz4_frame_size(in, n, NULL);
        if (total < 0)
            return final ? -1 : 0;
        uint8_t *out = malloc(total ? (size_t)total : 1);
        if (!out || !lz4_frame_decode(out, in, n)) {
            free(out);
            return -1;
        }
        state->output = out;
        state->output_size = (size_t)total;
        return 1;
    }
    // LZFSE: complete once it ends with the end-of-stream block.
    if (n < 4 || memcmp(in + n - 4, "bvx$", 4) != 0)
        return final ? -1 : 0;
    if (n == 4) {
        state->output = malloc(1);
        state->output_size = 0;
        return 1;
    }
    for (size_t capacity = n * 4 + 1024; capacity < ((size_t)1 << 34); capacity *= 2) {
        uint8_t *out = malloc(capacity);
        if (!out)
            return -1;
        size_t written = lzfse_decode_buffer(out, capacity, in, n, NULL);
        if (written > 0 && written < capacity) {
            state->output = out;
            state->output_size = written;
            return 1;
        }
        free(out);
        if (written == 0)
            return final ? -1 : 0;
    }
    return -1;
}

int darwin_compression_stream_init(compression_stream *stream, int operation, compression_algorithm algorithm)
    DARWIN_SYMBOL(compression_stream_init);
int darwin_compression_stream_process(compression_stream *stream, int flags) DARWIN_SYMBOL(compression_stream_process);
int darwin_compression_stream_destroy(compression_stream *stream) DARWIN_SYMBOL(compression_stream_destroy);

int darwin_compression_stream_init(compression_stream *stream, int operation, compression_algorithm algorithm) {
    if (!stream || (operation != COMPRESSION_STREAM_ENCODE && operation != COMPRESSION_STREAM_DECODE))
        return COMPRESSION_STATUS_ERROR;
    stream->dst_ptr = NULL;
    stream->dst_size = 0;
    stream->src_ptr = NULL;
    stream->src_size = 0;
    stream->state = NULL;
    stream_state *state = calloc(1, sizeof(*state));
    if (!state)
        return COMPRESSION_STATUS_ERROR;
    state->algorithm = algorithm;
    state->operation = operation;
    int encoding = operation == COMPRESSION_STREAM_ENCODE;
    int ok;
    switch (algorithm) {
    case COMPRESSION_ZLIB:
        ok = (encoding ? deflateInit2(&state->zlib, ZLIB_LEVEL, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY)
                       : inflateInit2(&state->zlib, -15)) == Z_OK;
        break;
    case COMPRESSION_LZMA:
        state->lzma = (lzma_stream)LZMA_STREAM_INIT;
        ok = (encoding ? lzma_easy_encoder(&state->lzma, LZMA_PRESET, LZMA_CHECK_CRC64)
                       : lzma_stream_decoder(&state->lzma, UINT64_MAX, 0)) == LZMA_OK;
        break;
    case COMPRESSION_BROTLI:
        if (encoding) {
            state->brotli_encoder = BrotliEncoderCreateInstance(NULL, NULL, NULL);
            ok = state->brotli_encoder && BrotliEncoderSetParameter(state->brotli_encoder, BROTLI_PARAM_QUALITY, BROTLI_QUALITY);
        } else {
            state->brotli_decoder = BrotliDecoderCreateInstance(NULL, NULL, NULL);
            ok = state->brotli_decoder != NULL;
        }
        break;
    case COMPRESSION_LZ4:
    case COMPRESSION_LZFSE:
        ok = 1;
        break;
    default:
        ok = 0;     // LZ4_RAW and the buffer-only formats have no stream form.
    }
    if (!ok) {
        free(state);
        return COMPRESSION_STATUS_ERROR;
    }
    stream->state = state;
    return COMPRESSION_STATUS_OK;
}

int darwin_compression_stream_process(compression_stream *stream, int flags) {
    if (!stream || !stream->state)
        return COMPRESSION_STATUS_ERROR;
    stream_state *state = stream->state;
    int final = (flags & COMPRESSION_STREAM_FINALIZE) != 0;
    int encoding = state->operation == COMPRESSION_STREAM_ENCODE;

    switch (state->algorithm) {
    case COMPRESSION_ZLIB: {
        z_stream *z = &state->zlib;
        z->next_in = (Bytef *)stream->src_ptr;
        z->avail_in = (uInt)stream->src_size;
        z->next_out = stream->dst_ptr;
        z->avail_out = (uInt)stream->dst_size;
        int status = encoding ? deflate(z, final ? Z_FINISH : Z_NO_FLUSH) : inflate(z, Z_NO_FLUSH);
        size_t consumed = stream->src_size - z->avail_in, produced = stream->dst_size - z->avail_out;
        stream->src_ptr += consumed;
        stream->src_size -= consumed;
        stream->dst_ptr += produced;
        stream->dst_size -= produced;
        if (status == Z_STREAM_END)
            return COMPRESSION_STATUS_END;
        return status == Z_OK || status == Z_BUF_ERROR ? COMPRESSION_STATUS_OK : COMPRESSION_STATUS_ERROR;
    }
    case COMPRESSION_LZMA: {
        lzma_stream *s = &state->lzma;
        s->next_in = stream->src_ptr;
        s->avail_in = stream->src_size;
        s->next_out = stream->dst_ptr;
        s->avail_out = stream->dst_size;
        lzma_ret status = lzma_code(s, final ? LZMA_FINISH : LZMA_RUN);
        size_t consumed = stream->src_size - s->avail_in, produced = stream->dst_size - s->avail_out;
        stream->src_ptr += consumed;
        stream->src_size -= consumed;
        stream->dst_ptr += produced;
        stream->dst_size -= produced;
        if (status == LZMA_STREAM_END)
            return COMPRESSION_STATUS_END;
        return status == LZMA_OK || status == LZMA_BUF_ERROR ? COMPRESSION_STATUS_OK : COMPRESSION_STATUS_ERROR;
    }
    case COMPRESSION_BROTLI: {
        size_t in_left = stream->src_size, out_left = stream->dst_size;
        const uint8_t *in = stream->src_ptr;
        uint8_t *out = stream->dst_ptr;
        int status;
        if (encoding) {
            BROTLI_BOOL ok = BrotliEncoderCompressStream(state->brotli_encoder,
                                                         final ? BROTLI_OPERATION_FINISH : BROTLI_OPERATION_PROCESS,
                                                         &in_left, &in, &out_left, &out, NULL);
            status = !ok ? COMPRESSION_STATUS_ERROR
                   : BrotliEncoderIsFinished(state->brotli_encoder) ? COMPRESSION_STATUS_END : COMPRESSION_STATUS_OK;
        } else {
            BrotliDecoderResult result = BrotliDecoderDecompressStream(state->brotli_decoder, &in_left, &in,
                                                                       &out_left, &out, NULL);
            status = result == BROTLI_DECODER_RESULT_ERROR ? COMPRESSION_STATUS_ERROR
                   : result == BROTLI_DECODER_RESULT_SUCCESS ? COMPRESSION_STATUS_END : COMPRESSION_STATUS_OK;
        }
        stream->src_ptr = in;
        stream->src_size = in_left;
        stream->dst_ptr = out;
        stream->dst_size = out_left;
        return status;
    }
    default: {
        if (!state->coded) {
            if (stream->src_size && !append(state, stream->src_ptr, stream->src_size))
                return COMPRESSION_STATUS_ERROR;
            stream->src_ptr += stream->src_size;
            stream->src_size = 0;
            int coded = code_collected(state, final);
            if (coded < 0)
                return COMPRESSION_STATUS_ERROR;
            if (coded == 0)
                return COMPRESSION_STATUS_OK;
            state->coded = 1;
        }
        size_t left = state->output_size - state->output_offset;
        size_t count = left < stream->dst_size ? left : stream->dst_size;
        memcpy(stream->dst_ptr, state->output + state->output_offset, count);
        state->output_offset += count;
        stream->dst_ptr += count;
        stream->dst_size -= count;
        return state->output_offset == state->output_size ? COMPRESSION_STATUS_END : COMPRESSION_STATUS_OK;
    }
    }
}

int darwin_compression_stream_destroy(compression_stream *stream) {
    if (!stream || !stream->state)
        return COMPRESSION_STATUS_ERROR;
    stream_state *state = stream->state;
    int encoding = state->operation == COMPRESSION_STREAM_ENCODE;
    switch (state->algorithm) {
    case COMPRESSION_ZLIB:
        encoding ? deflateEnd(&state->zlib) : inflateEnd(&state->zlib);
        break;
    case COMPRESSION_LZMA:
        lzma_end(&state->lzma);
        break;
    case COMPRESSION_BROTLI:
        if (state->brotli_encoder)
            BrotliEncoderDestroyInstance(state->brotli_encoder);
        if (state->brotli_decoder)
            BrotliDecoderDestroyInstance(state->brotli_decoder);
        break;
    default:
        break;
    }
    free(state->input);
    free(state->output);
    free(state);
    stream->state = NULL;
    return COMPRESSION_STATUS_OK;
}
