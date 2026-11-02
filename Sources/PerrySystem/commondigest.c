// CommonCrypto's digests, HMAC, PBKDF2 and random bytes, which libSystem
// exports from libcommonCrypto.
//
// Callers allocate the digest and HMAC contexts at Apple's sizes
// (CC_SHA256_CTX is 104 bytes, CCHmacContext 384), which are smaller than
// other libraries' contexts, so the digests are implemented here to fit
// them. A context's fields are private to the library, as on Darwin.

#include "PerrySystem.h"

#include <errno.h>
#include <stdint.h>
#include <string.h>
#include <sys/random.h>
#include <time.h>

#define CC_EXPORT __attribute__((visibility("default"), used))

// MARK: - Contexts, as they sit in the caller's structs

// 4-byte aligned like Apple's CC_*_CTX, so 64-bit counts are two halves.
typedef struct { uint32_t state[4]; uint32_t count[2]; uint8_t buffer[64]; } md5_context;      // 88 of 92
typedef struct { uint32_t state[5]; uint32_t count[2]; uint8_t buffer[64]; } sha1_context;     // 92 of 96
typedef struct { uint32_t state[8]; uint32_t count[2]; uint8_t buffer[64]; } sha256_context;   // 104 of 104
typedef struct { uint64_t state[8]; uint64_t count[2]; uint8_t buffer[128]; } sha512_context;  // 208 of 208

_Static_assert(sizeof(md5_context) <= 92, "CC_MD5_CTX is 92 bytes");
_Static_assert(sizeof(sha1_context) <= 96, "CC_SHA1_CTX is 96 bytes");
_Static_assert(sizeof(sha256_context) <= 104, "CC_SHA256_CTX is 104 bytes");
_Static_assert(sizeof(sha512_context) <= 208, "CC_SHA512_CTX is 208 bytes");

static uint64_t byte_count(const uint32_t count[2]) { return (uint64_t)count[1] << 32 | count[0]; }

static void add_bytes(uint32_t count[2], size_t n) {
    uint64_t total = byte_count(count) + n;
    count[0] = (uint32_t)total;
    count[1] = (uint32_t)(total >> 32);
}

static uint32_t rotl32(uint32_t x, int n) { return (x << n) | (x >> (32 - n)); }
static uint32_t rotr32(uint32_t x, int n) { return (x >> n) | (x << (32 - n)); }
static uint64_t rotr64(uint64_t x, int n) { return (x >> n) | (x << (64 - n)); }

static uint32_t load_be32(const uint8_t *p) { return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3]; }
static uint32_t load_le32(const uint8_t *p) { return (uint32_t)p[3] << 24 | (uint32_t)p[2] << 16 | (uint32_t)p[1] << 8 | p[0]; }
static uint64_t load_be64(const uint8_t *p) { return (uint64_t)load_be32(p) << 32 | load_be32(p + 4); }
static void store_be32(uint8_t *p, uint32_t v) { p[0] = v >> 24; p[1] = v >> 16; p[2] = v >> 8; p[3] = v; }
static void store_le32(uint8_t *p, uint32_t v) { p[0] = v; p[1] = v >> 8; p[2] = v >> 16; p[3] = v >> 24; }
static void store_be64(uint8_t *p, uint64_t v) { store_be32(p, v >> 32); store_be32(p + 4, (uint32_t)v); }

/// Feeds bytes to a 64-byte-block digest, compressing each full block.
static void absorb64(uint32_t count[2], uint8_t buffer[64], void *state, void (*block)(void *, const uint8_t *),
                     const uint8_t *data, size_t length) {
    size_t used = byte_count(count) % 64;
    add_bytes(count, length);
    if (used) {
        size_t take = 64 - used < length ? 64 - used : length;
        memcpy(buffer + used, data, take);
        data += take;
        length -= take;
        if (used + take < 64)
            return;
        block(state, buffer);
    }
    for (; length >= 64; data += 64, length -= 64)
        block(state, data);
    memcpy(buffer, data, length);
}

/// Pads a 64-byte-block digest: 0x80, zeros, then the bit length.
static void pad64(uint32_t count[2], uint8_t buffer[64], void *state, void (*block)(void *, const uint8_t *),
                  int little_endian) {
    uint64_t bits = byte_count(count) * 8;
    size_t used = byte_count(count) % 64;
    buffer[used++] = 0x80;
    if (used > 56) {
        memset(buffer + used, 0, 64 - used);
        block(state, buffer);
        used = 0;
    }
    memset(buffer + used, 0, 56 - used);
    if (little_endian) {
        store_le32(buffer + 56, (uint32_t)bits);
        store_le32(buffer + 60, (uint32_t)(bits >> 32));
    } else {
        store_be64(buffer + 56, bits);
    }
    block(state, buffer);
}

// MARK: - MD5 (RFC 1321)

static void md5_block(void *context, const uint8_t *p) {
    static const uint32_t k[64] = {
        0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
        0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
        0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
        0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
        0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
        0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
        0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
        0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1, 0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
    };
    static const int r[64] = {
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
        4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
    };
    uint32_t *s = context, m[16];
    for (int i = 0; i < 16; i++)
        m[i] = load_le32(p + 4 * i);
    uint32_t a = s[0], b = s[1], c = s[2], d = s[3];
    for (int i = 0; i < 64; i++) {
        uint32_t f;
        int g;
        if (i < 16) { f = (b & c) | (~b & d); g = i; }
        else if (i < 32) { f = (d & b) | (~d & c); g = (5 * i + 1) % 16; }
        else if (i < 48) { f = b ^ c ^ d; g = (3 * i + 5) % 16; }
        else { f = c ^ (b | ~d); g = (7 * i) % 16; }
        uint32_t t = d;
        d = c;
        c = b;
        b = b + rotl32(a + f + k[i] + m[g], r[i]);
        a = t;
    }
    s[0] += a; s[1] += b; s[2] += c; s[3] += d;
}

static void md5_init(void *c) {
    md5_context *x = c;
    memset(x, 0, sizeof(*x));
    x->state[0] = 0x67452301; x->state[1] = 0xefcdab89; x->state[2] = 0x98badcfe; x->state[3] = 0x10325476;
}
static void md5_update(void *c, const void *d, size_t n) { md5_context *x = c; absorb64(x->count, x->buffer, x->state, md5_block, d, n); }
static void md5_final(uint8_t *md, void *c) {
    md5_context *x = c;
    pad64(x->count, x->buffer, x->state, md5_block, 1);
    for (int i = 0; i < 4; i++)
        store_le32(md + 4 * i, x->state[i]);
}

// MARK: - SHA-1 (FIPS 180-4)

static void sha1_block(void *context, const uint8_t *p) {
    uint32_t *s = context, w[80];
    for (int i = 0; i < 16; i++)
        w[i] = load_be32(p + 4 * i);
    for (int i = 16; i < 80; i++)
        w[i] = rotl32(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    uint32_t a = s[0], b = s[1], c = s[2], d = s[3], e = s[4];
    for (int i = 0; i < 80; i++) {
        uint32_t f, k;
        if (i < 20) { f = (b & c) | (~b & d); k = 0x5a827999; }
        else if (i < 40) { f = b ^ c ^ d; k = 0x6ed9eba1; }
        else if (i < 60) { f = (b & c) | (b & d) | (c & d); k = 0x8f1bbcdc; }
        else { f = b ^ c ^ d; k = 0xca62c1d6; }
        uint32_t t = rotl32(a, 5) + f + e + k + w[i];
        e = d; d = c; c = rotl32(b, 30); b = a; a = t;
    }
    s[0] += a; s[1] += b; s[2] += c; s[3] += d; s[4] += e;
}

static void sha1_init(void *c) {
    sha1_context *x = c;
    memset(x, 0, sizeof(*x));
    x->state[0] = 0x67452301; x->state[1] = 0xefcdab89; x->state[2] = 0x98badcfe;
    x->state[3] = 0x10325476; x->state[4] = 0xc3d2e1f0;
}
static void sha1_update(void *c, const void *d, size_t n) { sha1_context *x = c; absorb64(x->count, x->buffer, x->state, sha1_block, d, n); }
static void sha1_final(uint8_t *md, void *c) {
    sha1_context *x = c;
    pad64(x->count, x->buffer, x->state, sha1_block, 0);
    for (int i = 0; i < 5; i++)
        store_be32(md + 4 * i, x->state[i]);
}

// MARK: - SHA-224 and SHA-256

static void sha256_block(void *context, const uint8_t *p) {
    static const uint32_t k[64] = {
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    };
    uint32_t *s = context, w[64];
    for (int i = 0; i < 16; i++)
        w[i] = load_be32(p + 4 * i);
    for (int i = 16; i < 64; i++) {
        uint32_t s0 = rotr32(w[i - 15], 7) ^ rotr32(w[i - 15], 18) ^ (w[i - 15] >> 3);
        uint32_t s1 = rotr32(w[i - 2], 17) ^ rotr32(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }
    uint32_t a = s[0], b = s[1], c = s[2], d = s[3], e = s[4], f = s[5], g = s[6], h = s[7];
    for (int i = 0; i < 64; i++) {
        uint32_t t1 = h + (rotr32(e, 6) ^ rotr32(e, 11) ^ rotr32(e, 25)) + ((e & f) ^ (~e & g)) + k[i] + w[i];
        uint32_t t2 = (rotr32(a, 2) ^ rotr32(a, 13) ^ rotr32(a, 22)) + ((a & b) ^ (a & c) ^ (b & c));
        h = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
    }
    s[0] += a; s[1] += b; s[2] += c; s[3] += d; s[4] += e; s[5] += f; s[6] += g; s[7] += h;
}

static void sha256_init(void *c) {
    static const uint32_t iv[8] = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 };
    sha256_context *x = c;
    memset(x, 0, sizeof(*x));
    memcpy(x->state, iv, sizeof(iv));
}
static void sha224_init(void *c) {
    static const uint32_t iv[8] = { 0xc1059ed8, 0x367cd507, 0x3070dd17, 0xf70e5939, 0xffc00b31, 0x68581511, 0x64f98fa7, 0xbefa4fa4 };
    sha256_context *x = c;
    memset(x, 0, sizeof(*x));
    memcpy(x->state, iv, sizeof(iv));
}
static void sha256_update(void *c, const void *d, size_t n) { sha256_context *x = c; absorb64(x->count, x->buffer, x->state, sha256_block, d, n); }
static void sha256_finish(uint8_t *md, void *c, int words) {
    sha256_context *x = c;
    pad64(x->count, x->buffer, x->state, sha256_block, 0);
    for (int i = 0; i < words; i++)
        store_be32(md + 4 * i, x->state[i]);
}
static void sha256_final(uint8_t *md, void *c) { sha256_finish(md, c, 8); }
static void sha224_final(uint8_t *md, void *c) { sha256_finish(md, c, 7); }

// MARK: - SHA-384 and SHA-512

static void sha512_block(sha512_context *x, const uint8_t *p) {
    static const uint64_t k[80] = {
        0x428a2f98d728ae22, 0x7137449123ef65cd, 0xb5c0fbcfec4d3b2f, 0xe9b5dba58189dbbc, 0x3956c25bf348b538,
        0x59f111f1b605d019, 0x923f82a4af194f9b, 0xab1c5ed5da6d8118, 0xd807aa98a3030242, 0x12835b0145706fbe,
        0x243185be4ee4b28c, 0x550c7dc3d5ffb4e2, 0x72be5d74f27b896f, 0x80deb1fe3b1696b1, 0x9bdc06a725c71235,
        0xc19bf174cf692694, 0xe49b69c19ef14ad2, 0xefbe4786384f25e3, 0x0fc19dc68b8cd5b5, 0x240ca1cc77ac9c65,
        0x2de92c6f592b0275, 0x4a7484aa6ea6e483, 0x5cb0a9dcbd41fbd4, 0x76f988da831153b5, 0x983e5152ee66dfab,
        0xa831c66d2db43210, 0xb00327c898fb213f, 0xbf597fc7beef0ee4, 0xc6e00bf33da88fc2, 0xd5a79147930aa725,
        0x06ca6351e003826f, 0x142929670a0e6e70, 0x27b70a8546d22ffc, 0x2e1b21385c26c926, 0x4d2c6dfc5ac42aed,
        0x53380d139d95b3df, 0x650a73548baf63de, 0x766a0abb3c77b2a8, 0x81c2c92e47edaee6, 0x92722c851482353b,
        0xa2bfe8a14cf10364, 0xa81a664bbc423001, 0xc24b8b70d0f89791, 0xc76c51a30654be30, 0xd192e819d6ef5218,
        0xd69906245565a910, 0xf40e35855771202a, 0x106aa07032bbd1b8, 0x19a4c116b8d2d0c8, 0x1e376c085141ab53,
        0x2748774cdf8eeb99, 0x34b0bcb5e19b48a8, 0x391c0cb3c5c95a63, 0x4ed8aa4ae3418acb, 0x5b9cca4f7763e373,
        0x682e6ff3d6b2b8a3, 0x748f82ee5defb2fc, 0x78a5636f43172f60, 0x84c87814a1f0ab72, 0x8cc702081a6439ec,
        0x90befffa23631e28, 0xa4506cebde82bde9, 0xbef9a3f7b2c67915, 0xc67178f2e372532b, 0xca273eceea26619c,
        0xd186b8c721c0c207, 0xeada7dd6cde0eb1e, 0xf57d4f7fee6ed178, 0x06f067aa72176fba, 0x0a637dc5a2c898a6,
        0x113f9804bef90dae, 0x1b710b35131c471b, 0x28db77f523047d84, 0x32caab7b40c72493, 0x3c9ebe0a15c9bebc,
        0x431d67c49c100d4c, 0x4cc5d4becb3e42b6, 0x597f299cfc657e2a, 0x5fcb6fab3ad6faec, 0x6c44198c4a475817,
    };
    uint64_t *s = x->state, w[80];
    for (int i = 0; i < 16; i++)
        w[i] = load_be64(p + 8 * i);
    for (int i = 16; i < 80; i++) {
        uint64_t s0 = rotr64(w[i - 15], 1) ^ rotr64(w[i - 15], 8) ^ (w[i - 15] >> 7);
        uint64_t s1 = rotr64(w[i - 2], 19) ^ rotr64(w[i - 2], 61) ^ (w[i - 2] >> 6);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }
    uint64_t a = s[0], b = s[1], c = s[2], d = s[3], e = s[4], f = s[5], g = s[6], h = s[7];
    for (int i = 0; i < 80; i++) {
        uint64_t t1 = h + (rotr64(e, 14) ^ rotr64(e, 18) ^ rotr64(e, 41)) + ((e & f) ^ (~e & g)) + k[i] + w[i];
        uint64_t t2 = (rotr64(a, 28) ^ rotr64(a, 34) ^ rotr64(a, 39)) + ((a & b) ^ (a & c) ^ (b & c));
        h = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
    }
    s[0] += a; s[1] += b; s[2] += c; s[3] += d; s[4] += e; s[5] += f; s[6] += g; s[7] += h;
}

static void sha512_init(void *c) {
    static const uint64_t iv[8] = {
        0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
        0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179,
    };
    sha512_context *x = c;
    memset(x, 0, sizeof(*x));
    memcpy(x->state, iv, sizeof(iv));
}
static void sha384_init(void *c) {
    static const uint64_t iv[8] = {
        0xcbbb9d5dc1059ed8, 0x629a292a367cd507, 0x9159015a3070dd17, 0x152fecd8f70e5939,
        0x67332667ffc00b31, 0x8eb44a8768581511, 0xdb0c2e0d64f98fa7, 0x47b5481dbefa4fa4,
    };
    sha512_context *x = c;
    memset(x, 0, sizeof(*x));
    memcpy(x->state, iv, sizeof(iv));
}
static void sha512_update(void *c, const void *data, size_t length) {
    sha512_context *x = c;
    const uint8_t *p = data;
    size_t used = x->count[0] % 128;
    x->count[0] += length;
    if (x->count[0] < length)
        x->count[1]++;
    if (used) {
        size_t take = 128 - used < length ? 128 - used : length;
        memcpy(x->buffer + used, p, take);
        p += take;
        length -= take;
        if (used + take < 128)
            return;
        sha512_block(x, x->buffer);
    }
    for (; length >= 128; p += 128, length -= 128)
        sha512_block(x, p);
    memcpy(x->buffer, p, length);
}
static void sha512_finish(uint8_t *md, void *c, int words) {
    sha512_context *x = c;
    uint64_t low = x->count[0] << 3, high = (x->count[1] << 3) | (x->count[0] >> 61);
    size_t used = x->count[0] % 128;
    x->buffer[used++] = 0x80;
    if (used > 112) {
        memset(x->buffer + used, 0, 128 - used);
        sha512_block(x, x->buffer);
        used = 0;
    }
    memset(x->buffer + used, 0, 112 - used);
    store_be64(x->buffer + 112, high);
    store_be64(x->buffer + 120, low);
    sha512_block(x, x->buffer);
    for (int i = 0; i < words; i++)
        store_be64(md + 8 * i, x->state[i]);
}
static void sha512_final(uint8_t *md, void *c) { sha512_finish(md, c, 8); }
static void sha384_final(uint8_t *md, void *c) { sha512_finish(md, c, 6); }

// MARK: - The exported digest functions

typedef struct digest {
    size_t context_size, block_size, output_size;
    void (*init)(void *);
    void (*update)(void *, const void *, size_t);
    void (*final)(uint8_t *, void *);
} digest;

static const digest md5 = { sizeof(md5_context), 64, 16, md5_init, md5_update, md5_final };
static const digest sha1 = { sizeof(sha1_context), 64, 20, sha1_init, sha1_update, sha1_final };
static const digest sha224 = { sizeof(sha256_context), 64, 28, sha224_init, sha256_update, sha224_final };
static const digest sha256 = { sizeof(sha256_context), 64, 32, sha256_init, sha256_update, sha256_final };
static const digest sha384 = { sizeof(sha512_context), 128, 48, sha384_init, sha512_update, sha384_final };
static const digest sha512 = { sizeof(sha512_context), 128, 64, sha512_init, sha512_update, sha512_final };

/// The context, copied to aligned memory while it is used: callers'
/// structs are only 4-byte aligned.
typedef union { md5_context m; sha1_context s1; sha256_context s256; sha512_context s512; uint8_t bytes[1]; } any_context;

static void one_shot(const digest *d, const void *data, size_t length, uint8_t *md) {
    any_context c;
    d->init(&c);
    d->update(&c, data, length);
    d->final(md, &c);
}

#define DIGEST(NAME, CTX, D)                                                                         \
    CC_EXPORT int darwin_CC_##NAME##_Init(void *c) __asm__("_CC_" #NAME "_Init");                     \
    CC_EXPORT int darwin_CC_##NAME##_Init(void *c) {                                                  \
        any_context x;                                                                                \
        (D).init(&x);                                                                                 \
        memcpy(c, &x, (D).context_size);                                                              \
        return 1;                                                                                     \
    }                                                                                                 \
    CC_EXPORT int darwin_CC_##NAME##_Update(void *c, const void *data, uint32_t length)               \
        __asm__("_CC_" #NAME "_Update");                                                              \
    CC_EXPORT int darwin_CC_##NAME##_Update(void *c, const void *data, uint32_t length) {             \
        any_context x;                                                                                \
        memcpy(&x, c, (D).context_size);                                                              \
        (D).update(&x, data, length);                                                                 \
        memcpy(c, &x, (D).context_size);                                                              \
        return 1;                                                                                     \
    }                                                                                                 \
    CC_EXPORT int darwin_CC_##NAME##_Final(unsigned char *md, void *c) __asm__("_CC_" #NAME "_Final"); \
    CC_EXPORT int darwin_CC_##NAME##_Final(unsigned char *md, void *c) {                              \
        any_context x;                                                                                \
        memcpy(&x, c, (D).context_size);                                                              \
        (D).final(md, &x);                                                                            \
        memset(c, 0, (D).context_size);                                                               \
        return 1;                                                                                     \
    }                                                                                                 \
    CC_EXPORT unsigned char *darwin_CC_##NAME(const void *data, uint32_t length, unsigned char *md)   \
        __asm__("_CC_" #NAME);                                                                        \
    CC_EXPORT unsigned char *darwin_CC_##NAME(const void *data, uint32_t length, unsigned char *md) { \
        one_shot(&(D), data, length, md);                                                             \
        return md;                                                                                    \
    }

DIGEST(MD5, md5_context, md5)
DIGEST(SHA1, sha1_context, sha1)
DIGEST(SHA224, sha256_context, sha224)
DIGEST(SHA256, sha256_context, sha256)
DIGEST(SHA384, sha512_context, sha384)
DIGEST(SHA512, sha512_context, sha512)

// MARK: - HMAC (RFC 2104)

enum { kCCHmacAlgSHA1, kCCHmacAlgMD5, kCCHmacAlgSHA256, kCCHmacAlgSHA384, kCCHmacAlgSHA512, kCCHmacAlgSHA224 };

static const digest *hmac_digest(uint32_t algorithm) {
    switch (algorithm) {
    case kCCHmacAlgSHA1: return &sha1;
    case kCCHmacAlgMD5: return &md5;
    case kCCHmacAlgSHA256: return &sha256;
    case kCCHmacAlgSHA384: return &sha384;
    case kCCHmacAlgSHA512: return &sha512;
    case kCCHmacAlgSHA224: return &sha224;
    }
    return NULL;
}

/// What a CCHmacContext (384 bytes) holds: the algorithm, the inner digest
/// and the outer key block.
typedef struct {
    uint32_t algorithm;
    uint32_t reserved;
    uint8_t inner[sizeof(sha512_context)];
    uint8_t outer_key[128];
} hmac_context;

_Static_assert(sizeof(hmac_context) <= 384, "CCHmacContext is 384 bytes");

static void hmac_init(hmac_context *h, uint32_t algorithm, const void *key, size_t key_length) {
    const digest *d = hmac_digest(algorithm);
    memset(h, 0, sizeof(*h));
    h->algorithm = algorithm;
    if (!d)
        return;
    uint8_t block[128] = {0};
    if (key_length > d->block_size)
        one_shot(d, key, key_length, block);
    else if (key_length)
        memcpy(block, key, key_length);
    uint8_t inner_key[128];
    for (size_t i = 0; i < d->block_size; i++) {
        inner_key[i] = block[i] ^ 0x36;
        h->outer_key[i] = block[i] ^ 0x5c;
    }
    any_context c;
    d->init(&c);
    d->update(&c, inner_key, d->block_size);
    memcpy(h->inner, &c, d->context_size);
}

static void hmac_update(hmac_context *h, const void *data, size_t length) {
    const digest *d = hmac_digest(h->algorithm);
    if (!d)
        return;
    any_context c;
    memcpy(&c, h->inner, d->context_size);
    d->update(&c, data, length);
    memcpy(h->inner, &c, d->context_size);
}

static void hmac_final(hmac_context *h, uint8_t *mac) {
    const digest *d = hmac_digest(h->algorithm);
    if (!d)
        return;
    uint8_t inner_hash[64];
    any_context c;
    memcpy(&c, h->inner, d->context_size);
    d->final(inner_hash, &c);
    d->init(&c);
    d->update(&c, h->outer_key, d->block_size);
    d->update(&c, inner_hash, d->output_size);
    d->final(mac, &c);
}

CC_EXPORT void darwin_CCHmacInit(void *context, uint32_t algorithm, const void *key, size_t key_length) __asm__("_CCHmacInit");
CC_EXPORT void darwin_CCHmacInit(void *context, uint32_t algorithm, const void *key, size_t key_length) {
    hmac_context h;
    hmac_init(&h, algorithm, key, key_length);
    memcpy(context, &h, sizeof(h));
}

CC_EXPORT void darwin_CCHmacUpdate(void *context, const void *data, size_t length) __asm__("_CCHmacUpdate");
CC_EXPORT void darwin_CCHmacUpdate(void *context, const void *data, size_t length) {
    hmac_context h;
    memcpy(&h, context, sizeof(h));
    hmac_update(&h, data, length);
    memcpy(context, &h, sizeof(h));
}

CC_EXPORT void darwin_CCHmacFinal(void *context, void *mac) __asm__("_CCHmacFinal");
CC_EXPORT void darwin_CCHmacFinal(void *context, void *mac) {
    hmac_context h;
    memcpy(&h, context, sizeof(h));
    hmac_final(&h, mac);
    memset(context, 0, sizeof(h));
}

CC_EXPORT void darwin_CCHmac(uint32_t algorithm, const void *key, size_t key_length, const void *data, size_t length,
                             void *mac) __asm__("_CCHmac");
CC_EXPORT void darwin_CCHmac(uint32_t algorithm, const void *key, size_t key_length, const void *data, size_t length,
                             void *mac) {
    hmac_context h;
    hmac_init(&h, algorithm, key, key_length);
    hmac_update(&h, data, length);
    hmac_final(&h, mac);
}

// MARK: - PBKDF2 (RFC 8018)

enum { kCCPBKDF2 = 2 };
enum { kCCPRFHmacAlgSHA1 = 1, kCCPRFHmacAlgSHA224, kCCPRFHmacAlgSHA256, kCCPRFHmacAlgSHA384, kCCPRFHmacAlgSHA512 };
enum { kCCSuccess = 0, kCCParamError = -4300 };

static int prf_hmac(uint32_t prf) {
    switch (prf) {
    case kCCPRFHmacAlgSHA1: return kCCHmacAlgSHA1;
    case kCCPRFHmacAlgSHA224: return kCCHmacAlgSHA224;
    case kCCPRFHmacAlgSHA256: return kCCHmacAlgSHA256;
    case kCCPRFHmacAlgSHA384: return kCCHmacAlgSHA384;
    case kCCPRFHmacAlgSHA512: return kCCHmacAlgSHA512;
    }
    return -1;
}

static void pbkdf2(int algorithm, const void *password, size_t password_length, const uint8_t *salt, size_t salt_length,
                   unsigned rounds, uint8_t *out, size_t out_length) {
    const digest *d = hmac_digest((uint32_t)algorithm);
    hmac_context base, h;
    hmac_init(&base, (uint32_t)algorithm, password, password_length);
    uint8_t u[64], t[64];
    for (uint32_t index = 1; out_length; index++) {
        uint8_t counter[4];
        store_be32(counter, index);
        h = base;
        hmac_update(&h, salt, salt_length);
        hmac_update(&h, counter, 4);
        hmac_final(&h, u);
        memcpy(t, u, d->output_size);
        for (unsigned r = 1; r < rounds; r++) {
            h = base;
            hmac_update(&h, u, d->output_size);
            hmac_final(&h, u);
            for (size_t i = 0; i < d->output_size; i++)
                t[i] ^= u[i];
        }
        size_t take = out_length < d->output_size ? out_length : d->output_size;
        memcpy(out, t, take);
        out += take;
        out_length -= take;
    }
}

CC_EXPORT int darwin_CCKeyDerivationPBKDF(uint32_t algorithm, const char *password, size_t password_length,
                                          const uint8_t *salt, size_t salt_length, uint32_t prf, unsigned rounds,
                                          uint8_t *derived, size_t derived_length) __asm__("_CCKeyDerivationPBKDF");
CC_EXPORT int darwin_CCKeyDerivationPBKDF(uint32_t algorithm, const char *password, size_t password_length,
                                          const uint8_t *salt, size_t salt_length, uint32_t prf, unsigned rounds,
                                          uint8_t *derived, size_t derived_length) {
    int hmac = prf_hmac(prf);
    if (algorithm != kCCPBKDF2 || hmac < 0 || rounds == 0 || !derived || derived_length == 0 ||
        (!password && password_length) || (!salt && salt_length))
        return kCCParamError;
    pbkdf2(hmac, password, password_length, salt, salt_length, rounds, derived, derived_length);
    return kCCSuccess;
}

/// Rounds that take about `milliseconds`, measured here.
CC_EXPORT unsigned darwin_CCCalibratePBKDF(uint32_t algorithm, size_t password_length, size_t salt_length, uint32_t prf,
                                           size_t derived_length, uint32_t milliseconds) __asm__("_CCCalibratePBKDF");
CC_EXPORT unsigned darwin_CCCalibratePBKDF(uint32_t algorithm, size_t password_length, size_t salt_length, uint32_t prf,
                                           size_t derived_length, uint32_t milliseconds) {
    int hmac = prf_hmac(prf);
    if (algorithm != kCCPBKDF2 || hmac < 0 || derived_length == 0)
        return (unsigned)-1;
    enum { SAMPLE = 10000 };
    uint8_t password[64] = {0}, salt[64] = {0}, out[64];
    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);
    pbkdf2(hmac, password, password_length < 64 ? password_length : 64, salt, salt_length < 64 ? salt_length : 64,
           SAMPLE, out, derived_length < 64 ? derived_length : 64);
    clock_gettime(CLOCK_MONOTONIC, &end);
    double elapsed = (end.tv_sec - start.tv_sec) * 1e3 + (end.tv_nsec - start.tv_nsec) / 1e6;
    double rounds = elapsed > 0 ? SAMPLE * milliseconds / elapsed : SAMPLE;
    return rounds < 1 ? 1 : rounds > 4e9 ? 4000000000u : (unsigned)rounds;
}

// MARK: - Random bytes

enum { kCCRNGFailure = -4307 };

CC_EXPORT int darwin_CCRandomGenerateBytes(void *bytes, size_t count) __asm__("_CCRandomGenerateBytes");
CC_EXPORT int darwin_CCRandomGenerateBytes(void *bytes, size_t count) {
    uint8_t *p = bytes;
    while (count) {
        ssize_t got = getrandom(p, count, 0);
        if (got < 0) {
            if (errno == EINTR)
                continue;
            return kCCRNGFailure;
        }
        p += got;
        count -= (size_t)got;
    }
    return kCCSuccess;
}
