// Compression: zlib (buffers, streams with gzip headers, gz files written
// with gzprintf), bzip2, and libcompression's buffer and stream APIs for
// each algorithm, decoding samples Apple's encoders made (the bundle's
// sample.* files) and round-tripping its own output.

#import <Foundation/Foundation.h>
#import <compression.h>
#include <bzlib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

/// The text every sample encodes.
static NSData *sampleText(void) {
    NSMutableData *data = [NSMutableData data];
    char line[128];
    for (int i = 0; i < 1200; i++) {
        int n = snprintf(line, sizeof line, "Line %04d: the quick brown fox jumps over the lazy dog, %d bottles\n",
                         i, (i * 37) % 101);
        [data appendBytes:line length:(NSUInteger)n];
    }
    return data;
}

static uLong crcOf(const void *bytes, size_t length) {
    return crc32(0, bytes, (uInt)length);
}

// MARK: - zlib

static void zlibChecks(NSData *text) {
    say([NSString stringWithFormat:@"zlib: input %lu, crc32 %08lx, adler32 %08lx, bound %lu", (unsigned long)text.length,
         crcOf(text.bytes, text.length), adler32(1, text.bytes, (uInt)text.length), compressBound(text.length)]);

    uLongf packedLength = compressBound(text.length);
    Bytef *packed = malloc(packedLength);
    int status = compress2(packed, &packedLength, text.bytes, text.length, 9);
    uLongf unpackedLength = text.length;
    Bytef *unpacked = malloc(unpackedLength);
    int back = uncompress(unpacked, &unpackedLength, packed, packedLength);
    say([NSString stringWithFormat:@"compress2: status %d, round trip %d, %d", status, back,
         unpackedLength == text.length && memcmp(unpacked, text.bytes, text.length) == 0]);

    // A gzip stream through deflate and inflate, in small pieces.
    z_stream deflater = {0};
    deflateInit2(&deflater, 6, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY);
    NSMutableData *gzip = [NSMutableData data];
    uint8_t chunk[1000];
    deflater.next_in = (Bytef *)text.bytes;
    deflater.avail_in = (uInt)text.length;
    do {
        deflater.next_out = chunk;
        deflater.avail_out = sizeof chunk;
        status = deflate(&deflater, Z_FINISH);
        [gzip appendBytes:chunk length:sizeof chunk - deflater.avail_out];
    } while (status == Z_OK);
    deflateEnd(&deflater);
    const uint8_t *header = gzip.bytes;
    z_stream inflater = {0};
    inflateInit2(&inflater, 15 + 32);
    NSMutableData *inflated = [NSMutableData data];
    inflater.next_in = (Bytef *)gzip.bytes;
    inflater.avail_in = (uInt)gzip.length;
    int pieces = 0;
    do {
        inflater.next_out = chunk;
        inflater.avail_out = sizeof chunk;
        status = inflate(&inflater, Z_NO_FLUSH);
        [inflated appendBytes:chunk length:sizeof chunk - inflater.avail_out];
        pieces++;
    } while (status == Z_OK);
    inflateEnd(&inflater);
    say([NSString stringWithFormat:@"gzip stream: magic %02x%02x, end %d, %d pieces, equal %d", header[0], header[1],
         status == Z_STREAM_END, pieces, [inflated isEqualToData:text]]);

    // A gzip file, written with gzprintf.
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"vault.txt.gz"];
    gzFile file = gzopen(path.fileSystemRepresentation, "wb9");
    int printed = gzprintf(file, "%s has %d items at %.2f%% and %c%c\n", "vault", 42, 99.5, 'o', 'k');
    gzprintf(file, "%-8s|%5d|%x\n", "left", 7, 0xbeef);
    gzputs(file, "plain line\n");
    gzclose(file);
    file = gzopen(path.fileSystemRepresentation, "rb");
    char line[200];
    NSMutableArray *lines = [NSMutableArray array];
    while (gzgets(file, line, sizeof line)) {
        [lines addObject:[[NSString stringWithUTF8String:line] stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet]];
    }
    gzclose(file);
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    say([NSString stringWithFormat:@"gzprintf wrote %d; read back: %@", printed, [lines componentsJoinedByString:@" / "]]);
    free(packed);
    free(unpacked);
}

// MARK: - bzip2

static void bzip2Checks(NSData *text) {
    unsigned int packedLength = (unsigned int)text.length + 1000;
    char *packed = malloc(packedLength);
    int status = BZ2_bzBuffToBuffCompress(packed, &packedLength, (char *)text.bytes, (unsigned int)text.length, 9, 0, 0);
    unsigned int unpackedLength = (unsigned int)text.length;
    char *unpacked = malloc(unpackedLength);
    int back = BZ2_bzBuffToBuffDecompress(unpacked, &unpackedLength, packed, packedLength, 0, 0);
    say([NSString stringWithFormat:@"bzip2: status %d, %u bytes, starts %.3s, round trip %d %d", status, packedLength,
         packed, back, unpackedLength == text.length && memcmp(unpacked, text.bytes, text.length) == 0]);
    unsigned int tooSmall = 10;
    say([NSString stringWithFormat:@"bzip2 small output: %d", BZ2_bzBuffToBuffDecompress(unpacked, &tooSmall, packed, packedLength, 0, 0)]);
    free(packed);
    free(unpacked);
}

// MARK: - libcompression

typedef struct { const char *name; compression_algorithm algorithm; BOOL streams; } Algorithm;

static const Algorithm algorithms[] = {
    {"lz4", COMPRESSION_LZ4, YES}, {"zlib", COMPRESSION_ZLIB, YES}, {"lzma", COMPRESSION_LZMA, YES},
    {"lz4raw", COMPRESSION_LZ4_RAW, NO}, {"lzfse", COMPRESSION_LZFSE, YES}, {"brotli", COMPRESSION_BROTLI, YES},
};

/// Codes `input` through a stream, `piece` bytes in and out at a time.
static NSData *streamed(compression_stream_operation operation, compression_algorithm algorithm, NSData *input,
                        size_t piece, compression_status *last) {
    compression_stream stream;
    if (compression_stream_init(&stream, operation, algorithm) != COMPRESSION_STATUS_OK) {
        *last = COMPRESSION_STATUS_ERROR;
        return nil;
    }
    NSMutableData *output = [NSMutableData data];
    uint8_t *buffer = malloc(piece);
    size_t offset = 0;
    compression_status status = COMPRESSION_STATUS_OK;
    stream.src_ptr = input.bytes;
    stream.src_size = 0;
    while (status == COMPRESSION_STATUS_OK) {
        if (stream.src_size == 0 && offset < input.length) {
            stream.src_ptr = (const uint8_t *)input.bytes + offset;
            stream.src_size = MIN(piece, input.length - offset);
            offset += stream.src_size;
        }
        stream.dst_ptr = buffer;
        stream.dst_size = piece;
        int flags = offset == input.length ? COMPRESSION_STREAM_FINALIZE : 0;
        status = compression_stream_process(&stream, flags);
        [output appendBytes:buffer length:piece - stream.dst_size];
    }
    compression_stream_destroy(&stream);
    free(buffer);
    *last = status;
    return output;
}

static void compressionChecks(NSData *text) {
    uint8_t *decoded = malloc(text.length + 100);
    uint8_t *encoded = malloc(text.length * 2);
    for (size_t i = 0; i < sizeof algorithms / sizeof *algorithms; i++) {
        Algorithm a = algorithms[i];
        NSString *resource = [NSString stringWithFormat:@"sample.%s", a.name];
        NSData *apple = [NSData dataWithContentsOfFile:[NSBundle.mainBundle pathForResource:resource ofType:nil]];

        // Apple's encoding, decoded whole and truncated.
        size_t size = compression_decode_buffer(decoded, text.length + 100, apple.bytes, apple.length, NULL, a.algorithm);
        BOOL same = size == text.length && memcmp(decoded, text.bytes, size) == 0;
        size_t truncated = compression_decode_buffer(decoded, 1000, apple.bytes, apple.length, NULL, a.algorithm);
        BOOL prefix = memcmp(decoded, text.bytes, 1000) == 0;

        // This side's encoding, round-tripped.
        size_t packed = compression_encode_buffer(encoded, text.length * 2, text.bytes, text.length, NULL, a.algorithm);
        size_t back = compression_decode_buffer(decoded, text.length + 100, encoded, packed, NULL, a.algorithm);
        BOOL roundTrip = packed > 0 && back == text.length && memcmp(decoded, text.bytes, back) == 0;
        size_t cramped = compression_encode_buffer(encoded, 16, text.bytes, text.length, NULL, a.algorithm);

        NSString *line = [NSString stringWithFormat:@"%s: Apple's %lu bytes decode %d, truncated %zu %d, round trip %d, cramped %zu",
                          a.name, (unsigned long)apple.length, same, truncated, prefix, roundTrip, cramped];
        if (a.streams) {
            compression_status encodeStatus, decodeStatus, appleStatus;
            NSData *packedStream = streamed(COMPRESSION_STREAM_ENCODE, a.algorithm, text, 4096, &encodeStatus);
            NSData *unpacked = streamed(COMPRESSION_STREAM_DECODE, a.algorithm, packedStream, 777, &decodeStatus);
            NSData *appleUnpacked = streamed(COMPRESSION_STREAM_DECODE, a.algorithm, apple, 500, &appleStatus);
            line = [line stringByAppendingFormat:@"; streams end %d %d, equal %d, Apple's streamed %d",
                    encodeStatus == COMPRESSION_STATUS_END, decodeStatus == COMPRESSION_STATUS_END,
                    [unpacked isEqualToData:text], appleStatus == COMPRESSION_STATUS_END && [appleUnpacked isEqualToData:text]];
        }
        say(line);
    }
    compression_stream stream;
    say([NSString stringWithFormat:@"stream LZ4_RAW init %d", compression_stream_init(&stream, COMPRESSION_STREAM_ENCODE,
                                                                                         COMPRESSION_LZ4_RAW)]);
    uint8_t garbage[64];
    memset(garbage, 0x5a, sizeof garbage);
    say([NSString stringWithFormat:@"garbage zlib decode %zu", compression_decode_buffer(decoded, 100, garbage, sizeof garbage,
                                                                                          NULL, COMPRESSION_ZLIB)]);
    free(decoded);
    free(encoded);
}

int main(void) {
    @autoreleasepool {
        NSData *text = sampleText();
        zlibChecks(text);
        bzip2Checks(text);
        compressionChecks(text);
    }
    return 0;
}
