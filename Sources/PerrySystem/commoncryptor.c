// CommonCrypto's symmetric ciphers and key wrapping, which libSystem
// exports from libcommonCrypto, over OpenSSL's EVP interface.
//
// A CCCryptorRef is the library's own allocation, so it can hold an
// OpenSSL cipher context. Decrypting with PKCS#7 padding removes it as
// CommonCrypto does, without OpenSSL's checks: a last byte from 1 to the
// block size removes that many bytes, whatever the others hold, and any
// other last byte removes nothing, which is not an error. libcrypto is loaded on first use, so processes
// that never encrypt never load it; OpenSSL's legacy provider supplies
// DES, RC4, RC2, CAST and Blowfish where it is installed.

#define _GNU_SOURCE
#include "PerrySystem.h"

#include <dlfcn.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CC_EXPORT __attribute__((visibility("default"), used))

enum {
    kCCSuccess = 0,
    kCCParamError = -4300,
    kCCBufferTooSmall = -4301,
    kCCMemoryFailure = -4302,
    kCCAlignmentError = -4303,
    kCCDecodeError = -4304,
    kCCUnimplemented = -4305,
    kCCKeySizeError = -4310,
};
enum { kCCEncrypt = 0, kCCDecrypt = 1 };
enum { kCCAlgorithmAES = 0, kCCAlgorithmDES, kCCAlgorithm3DES, kCCAlgorithmCAST, kCCAlgorithmRC4, kCCAlgorithmRC2, kCCAlgorithmBlowfish };
enum { kCCOptionPKCS7Padding = 1, kCCOptionECBMode = 2 };
enum { kCCModeECB = 1, kCCModeCBC = 2, kCCModeCFB = 3, kCCModeCTR = 4, kCCModeOFB = 7, kCCModeRC4 = 9, kCCModeCFB8 = 10 };
enum { ccNoPadding = 0, ccPKCS7Padding = 1 };

// MARK: - OpenSSL, loaded on first use

static struct {
    void *(*ctx_new)(void);
    void (*ctx_free)(void *);
    int (*init)(void *, const void *, void *, const unsigned char *, const unsigned char *, int);
    int (*update)(void *, unsigned char *, int *, const unsigned char *, int);
    int (*final)(void *, unsigned char *, int *);
    int (*set_padding)(void *, int);
    int (*set_key_length)(void *, int);
    const void *(*cipher_by_name)(const char *);
    void *(*provider_load)(void *, const char *);
    int loaded;
} evp;

static void load_evp(void) {
    void *crypto = dlopen("libcrypto.so.3", RTLD_NOW | RTLD_LOCAL);
    if (!crypto)
        return;
    evp.ctx_new = dlsym(crypto, "EVP_CIPHER_CTX_new");
    evp.ctx_free = dlsym(crypto, "EVP_CIPHER_CTX_free");
    evp.init = dlsym(crypto, "EVP_CipherInit_ex");
    evp.update = dlsym(crypto, "EVP_CipherUpdate");
    evp.final = dlsym(crypto, "EVP_CipherFinal_ex");
    evp.set_padding = dlsym(crypto, "EVP_CIPHER_CTX_set_padding");
    evp.set_key_length = dlsym(crypto, "EVP_CIPHER_CTX_set_key_length");
    evp.cipher_by_name = dlsym(crypto, "EVP_get_cipherbyname");
    evp.provider_load = dlsym(crypto, "OSSL_PROVIDER_load");
    // Loading the legacy provider stops the default one loading implicitly,
    // so load both.
    if (evp.provider_load) {
        evp.provider_load(NULL, "default");
        evp.provider_load(NULL, "legacy");
    }
    evp.loaded = evp.ctx_new && evp.ctx_free && evp.init && evp.update && evp.final && evp.set_padding &&
                 evp.set_key_length && evp.cipher_by_name;
}

static int have_evp(void) {
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    pthread_once(&once, load_evp);
    return evp.loaded;
}

// MARK: - Cryptors

typedef struct cryptor {
    void *context;
    const void *cipher;
    int encrypt;
    int padding;
    size_t block_size;          // 1 for stream ciphers and stream modes
    size_t buffered;            // input not yet output: a partial block, and a held-back block
    int unpads;                 // decrypting with padding: this file removes it
    size_t partial;             // the partial block OpenSSL holds, when it does not pad
    unsigned char held[16];     // the last whole block, which may be the padding
    size_t held_length;
    unsigned char key[64];
    size_t key_length;
    int variable_key;
} cryptor;

/// OpenSSL's name for an algorithm, mode and key size, the block size and
/// whether the key length varies; kCCSuccess or the error to report.
static int cipher_name(uint32_t algorithm, uint32_t mode, size_t key_length, char *name, size_t size,
                       size_t *block, int *variable) {
    const char *base;
    const char *modes[11] = {0};
    *variable = 0;
    switch (algorithm) {
    case kCCAlgorithmAES: {
        if (key_length != 16 && key_length != 24 && key_length != 32)
            return kCCKeySizeError;
        const char *suffix = mode == kCCModeECB ? "ecb" : mode == kCCModeCBC ? "cbc" : mode == kCCModeCFB ? "cfb"
                           : mode == kCCModeCTR ? "ctr" : mode == kCCModeOFB ? "ofb" : mode == kCCModeCFB8 ? "cfb8" : NULL;
        if (!suffix)
            return kCCUnimplemented;
        snprintf(name, size, "aes-%zu-%s", key_length * 8, suffix);
        *block = mode == kCCModeECB || mode == kCCModeCBC ? 16 : 1;
        return kCCSuccess;
    }
    case kCCAlgorithmDES:
        if (key_length != 8)
            return kCCKeySizeError;
        base = "des";
        break;
    case kCCAlgorithm3DES:
        if (key_length != 24)
            return kCCKeySizeError;
        base = "des-ede3";
        break;
    case kCCAlgorithmCAST:
        if (key_length < 5 || key_length > 16)
            return kCCKeySizeError;
        base = "cast5";
        *variable = 1;
        break;
    case kCCAlgorithmRC2:
        if (key_length < 1 || key_length > 128)
            return kCCKeySizeError;
        base = "rc2";
        *variable = 1;
        break;
    case kCCAlgorithmBlowfish:
        if (key_length < 8 || key_length > 56)
            return kCCKeySizeError;
        base = "bf";
        *variable = 1;
        break;
    case kCCAlgorithmRC4:
        if (key_length < 1 || key_length > 512)
            return kCCKeySizeError;
        snprintf(name, size, "rc4");
        *block = 1;
        *variable = 1;
        return kCCSuccess;
    default:
        return kCCParamError;
    }
    modes[kCCModeECB] = algorithm == kCCAlgorithm3DES ? "" : "-ecb";
    modes[kCCModeCBC] = "-cbc";
    modes[kCCModeCFB] = "-cfb";
    modes[kCCModeOFB] = "-ofb";
    modes[kCCModeCFB8] = algorithm == kCCAlgorithmDES || algorithm == kCCAlgorithm3DES ? "-cfb8" : NULL;
    if (mode >= 11 || !modes[mode])
        return kCCUnimplemented;
    snprintf(name, size, "%s%s", base, modes[mode]);
    *block = mode == kCCModeECB || mode == kCCModeCBC ? 8 : 1;
    return kCCSuccess;
}

static int start(cryptor *c, const void *iv) {
    unsigned char zeros[16] = {0};
    if (!evp.init(c->context, c->cipher, NULL, NULL, NULL, c->encrypt))
        return kCCParamError;
    if (c->variable_key && !evp.set_key_length(c->context, (int)c->key_length))
        return kCCKeySizeError;
    if (!evp.init(c->context, NULL, NULL, c->key, iv ? iv : zeros, c->encrypt))
        return kCCParamError;
    c->unpads = !c->encrypt && c->padding && c->block_size > 1;
    evp.set_padding(c->context, c->padding && c->block_size > 1 && !c->unpads);
    c->buffered = 0;
    c->partial = 0;
    c->held_length = 0;
    return kCCSuccess;
}

static int create(uint32_t operation, uint32_t mode, uint32_t algorithm, int padding, const void *iv,
                  const void *key, size_t key_length, cryptor **out) {
    if (!out || !key || (operation != kCCEncrypt && operation != kCCDecrypt))
        return kCCParamError;
    char name[32];
    size_t block = 0;
    int variable = 0;
    if (algorithm == kCCAlgorithmRC4)
        mode = kCCModeRC4;
    int status = cipher_name(algorithm, mode, key_length, name, sizeof(name), &block, &variable);
    if (status != kCCSuccess)
        return status;
    if (!have_evp())
        return kCCUnimplemented;
    const void *cipher = evp.cipher_by_name(name);
    if (!cipher || key_length > sizeof(((cryptor *)0)->key))
        return kCCUnimplemented;
    cryptor *c = calloc(1, sizeof(*c));
    if (!c)
        return kCCMemoryFailure;
    c->context = evp.ctx_new();
    c->cipher = cipher;
    c->encrypt = operation == kCCEncrypt;
    c->padding = padding;
    c->block_size = block;
    c->variable_key = variable;
    memcpy(c->key, key, key_length);
    c->key_length = key_length;
    status = c->context ? start(c, iv) : kCCMemoryFailure;
    if (status != kCCSuccess) {
        if (c->context)
            evp.ctx_free(c->context);
        free(c);
        return status;
    }
    *out = c;
    return kCCSuccess;
}

/// The most output an update or final with `length` more bytes produces.
static size_t output_length(const cryptor *c, size_t length, int final) {
    size_t total = c->buffered + length;
    if (c->block_size <= 1)
        return length;
    if (!final) {
        // Decrypting with padding holds back the last whole block, which
        // may be the padding, until the final call.
        if (!c->encrypt && c->padding && total && total % c->block_size == 0)
            return total - c->block_size;
        return total - total % c->block_size;
    }
    if (c->encrypt && c->padding)
        return (total / c->block_size + 1) * c->block_size;
    return total;
}

/// Twelve arguments, so four are on the stack, where Darwin packs the two
/// 32-bit ones (numRounds and options) into one 8-byte slot; Linux would
/// give each its own. They are read as that one slot, so cryptorRef comes
/// from the slot after it.
CC_EXPORT int darwin_CCCryptorCreateWithMode(uint32_t operation, uint32_t mode, uint32_t algorithm, uint32_t padding,
                                             const void *iv, const void *key, size_t key_length, const void *tweak,
                                             size_t tweak_length, uint64_t rounds_and_options, cryptor **out)
    __asm__("_CCCryptorCreateWithMode");
CC_EXPORT int darwin_CCCryptorCreateWithMode(uint32_t operation, uint32_t mode, uint32_t algorithm, uint32_t padding,
                                             const void *iv, const void *key, size_t key_length, const void *tweak,
                                             size_t tweak_length, uint64_t rounds_and_options, cryptor **out) {
    (void)tweak; (void)tweak_length; (void)rounds_and_options;
    return create(operation, mode, algorithm, padding == ccPKCS7Padding, iv, key, key_length, out);
}

CC_EXPORT int darwin_CCCryptorCreate(uint32_t operation, uint32_t algorithm, uint32_t options, const void *key,
                                     size_t key_length, const void *iv, cryptor **out) __asm__("_CCCryptorCreate");
CC_EXPORT int darwin_CCCryptorCreate(uint32_t operation, uint32_t algorithm, uint32_t options, const void *key,
                                     size_t key_length, const void *iv, cryptor **out) {
    uint32_t mode = options & kCCOptionECBMode ? kCCModeECB : kCCModeCBC;
    return create(operation, mode, algorithm, (options & kCCOptionPKCS7Padding) != 0, iv, key, key_length, out);
}

CC_EXPORT int darwin_CCCryptorRelease(cryptor *c) __asm__("_CCCryptorRelease");
CC_EXPORT int darwin_CCCryptorRelease(cryptor *c) {
    if (!c)
        return kCCParamError;
    evp.ctx_free(c->context);
    memset(c, 0, sizeof(*c));
    free(c);
    return kCCSuccess;
}

CC_EXPORT size_t darwin_CCCryptorGetOutputLength(cryptor *c, size_t length, int final) __asm__("_CCCryptorGetOutputLength");
CC_EXPORT size_t darwin_CCCryptorGetOutputLength(cryptor *c, size_t length, int final) {
    return c ? output_length(c, length, final) : 0;
}

/// An update when this file removes the padding: OpenSSL decrypts without
/// it, and the last whole block is held back while the input so far is
/// whole blocks, as OpenSSL would hold it to remove the padding.
static int unpadded_update(cryptor *c, const void *in, size_t in_length, void *out, size_t *moved) {
    size_t block = c->block_size;
    unsigned char *decrypted = malloc(in_length + block + c->held_length);
    if (!decrypted)
        return kCCMemoryFailure;
    memcpy(decrypted, c->held, c->held_length);
    int written = 0;
    if (in_length && !evp.update(c->context, decrypted + c->held_length, &written, in, (int)in_length)) {
        free(decrypted);
        return kCCParamError;
    }
    size_t available = c->held_length + (size_t)written;
    c->partial = (c->partial + in_length) % block;
    c->held_length = 0;
    if (c->partial == 0 && available >= block) {
        available -= block;
        memcpy(c->held, decrypted + available, block);
        c->held_length = block;
    }
    memcpy(out, decrypted, available);
    free(decrypted);
    c->buffered = c->partial + c->held_length;
    if (moved)
        *moved = available;
    return kCCSuccess;
}

CC_EXPORT int darwin_CCCryptorUpdate(cryptor *c, const void *in, size_t in_length, void *out, size_t out_available,
                                     size_t *moved) __asm__("_CCCryptorUpdate");
CC_EXPORT int darwin_CCCryptorUpdate(cryptor *c, const void *in, size_t in_length, void *out, size_t out_available,
                                     size_t *moved) {
    if (!c || (!in && in_length))
        return kCCParamError;
    size_t needed = output_length(c, in_length, 0);
    if (out_available < needed) {
        if (moved)
            *moved = needed;
        return kCCBufferTooSmall;
    }
    if (c->unpads)
        return unpadded_update(c, in, in_length, out, moved);
    int written = 0;
    if (in_length && !evp.update(c->context, out, &written, in, (int)in_length))
        return kCCParamError;
    // OpenSSL holds back what it cannot output yet: a partial block.
    c->buffered = c->buffered + in_length - (size_t)written;
    if (moved)
        *moved = (size_t)written;
    return kCCSuccess;
}

CC_EXPORT int darwin_CCCryptorFinal(cryptor *c, void *out, size_t out_available, size_t *moved) __asm__("_CCCryptorFinal");
CC_EXPORT int darwin_CCCryptorFinal(cryptor *c, void *out, size_t out_available, size_t *moved) {
    if (!c)
        return kCCParamError;
    size_t needed = output_length(c, 0, 1);
    if (out_available < needed) {
        if (moved)
            *moved = needed;
        return kCCBufferTooSmall;
    }
    if (c->block_size > 1 && (!c->padding || c->unpads) && (c->unpads ? c->partial : c->buffered)) {
        if (moved)
            *moved = 0;
        return kCCAlignmentError;
    }
    if (c->unpads) {
        // CommonCrypto's PKCS#7 removal: the last byte's count, unchecked.
        size_t length = c->held_length;
        if (length) {
            unsigned pad = c->held[length - 1];
            if (pad >= 1 && pad <= length)
                length -= pad;
            memcpy(out, c->held, length);
        }
        c->held_length = 0;
        c->buffered = 0;
        if (moved)
            *moved = length;
        return kCCSuccess;
    }
    unsigned char scratch[32];
    int written = 0;
    int ok = evp.final(c->context, out ? out : scratch, &written);
    if (moved)
        *moved = ok ? (size_t)written : 0;
    c->buffered = 0;
    if (!ok)
        return c->encrypt ? kCCAlignmentError : kCCDecodeError;
    return kCCSuccess;
}

CC_EXPORT int darwin_CCCryptorReset(cryptor *c, const void *iv) __asm__("_CCCryptorReset");
CC_EXPORT int darwin_CCCryptorReset(cryptor *c, const void *iv) {
    return c ? start(c, iv) : kCCParamError;
}

CC_EXPORT int darwin_CCCrypt(uint32_t operation, uint32_t algorithm, uint32_t options, const void *key, size_t key_length,
                             const void *iv, const void *in, size_t in_length, void *out, size_t out_available,
                             size_t *moved) __asm__("_CCCrypt");
CC_EXPORT int darwin_CCCrypt(uint32_t operation, uint32_t algorithm, uint32_t options, const void *key, size_t key_length,
                             const void *iv, const void *in, size_t in_length, void *out, size_t out_available,
                             size_t *moved) {
    cryptor *c = NULL;
    int status = darwin_CCCryptorCreate(operation, algorithm, options, key, key_length, iv, &c);
    if (status != kCCSuccess)
        return status;
    size_t needed = output_length(c, in_length, 1);
    if (out_available < needed) {
        darwin_CCCryptorRelease(c);
        if (moved)
            *moved = needed;
        return kCCBufferTooSmall;
    }
    size_t first = 0, second = 0;
    status = darwin_CCCryptorUpdate(c, in, in_length, out, out_available, &first);
    if (status == kCCSuccess)
        status = darwin_CCCryptorFinal(c, (uint8_t *)out + first, out_available - first, &second);
    darwin_CCCryptorRelease(c);
    if (moved)
        *moved = status == kCCSuccess ? first + second : 0;
    return status;
}

// MARK: - AES key wrap (RFC 3394)

static const uint8_t rfc3394_iv[8] = { 0xA6, 0xA6, 0xA6, 0xA6, 0xA6, 0xA6, 0xA6, 0xA6 };
CC_EXPORT const uint8_t *const darwin_CCrfc3394_iv __asm__("_CCrfc3394_iv") = rfc3394_iv;
CC_EXPORT const size_t darwin_CCrfc3394_ivLen __asm__("_CCrfc3394_ivLen") = sizeof(rfc3394_iv);

enum { kCCWRAPAES = 1 };

/// One AES block with the key encryption key.
static int aes_block(const uint8_t *kek, size_t kek_length, int encrypt, const uint8_t in[16], uint8_t out[16]) {
    cryptor *c = NULL;
    if (create(encrypt ? kCCEncrypt : kCCDecrypt, kCCModeECB, kCCAlgorithmAES, 0, NULL, kek, kek_length, &c) != kCCSuccess)
        return 0;
    int written = 0;
    int ok = evp.update(c->context, out, &written, in, 16) && written == 16;
    darwin_CCCryptorRelease(c);
    return ok;
}

CC_EXPORT size_t darwin_CCSymmetricWrappedSize(uint32_t algorithm, size_t raw_length) __asm__("_CCSymmetricWrappedSize");
CC_EXPORT size_t darwin_CCSymmetricWrappedSize(uint32_t algorithm, size_t raw_length) {
    (void)algorithm;
    return raw_length + 8;
}

CC_EXPORT size_t darwin_CCSymmetricUnwrappedSize(uint32_t algorithm, size_t wrapped_length) __asm__("_CCSymmetricUnwrappedSize");
CC_EXPORT size_t darwin_CCSymmetricUnwrappedSize(uint32_t algorithm, size_t wrapped_length) {
    (void)algorithm;
    return wrapped_length >= 8 ? wrapped_length - 8 : 0;
}

CC_EXPORT int darwin_CCSymmetricKeyWrap(uint32_t algorithm, const uint8_t *iv, size_t iv_length, const uint8_t *kek,
                                        size_t kek_length, const uint8_t *raw, size_t raw_length, uint8_t *wrapped,
                                        size_t *wrapped_length) __asm__("_CCSymmetricKeyWrap");
CC_EXPORT int darwin_CCSymmetricKeyWrap(uint32_t algorithm, const uint8_t *iv, size_t iv_length, const uint8_t *kek,
                                        size_t kek_length, const uint8_t *raw, size_t raw_length, uint8_t *wrapped,
                                        size_t *wrapped_length) {
    if (algorithm != kCCWRAPAES || !iv || iv_length != 8 || !raw || raw_length < 16 || raw_length % 8 || !wrapped ||
        !wrapped_length || *wrapped_length < raw_length + 8)
        return kCCParamError;
    size_t n = raw_length / 8;
    uint8_t a[8], block[16];
    memcpy(a, iv, 8);
    memmove(wrapped + 8, raw, raw_length);
    for (int j = 0; j < 6; j++) {
        for (size_t i = 1; i <= n; i++) {
            memcpy(block, a, 8);
            memcpy(block + 8, wrapped + 8 * i, 8);
            if (!aes_block(kek, kek_length, 1, block, block))
                return kCCParamError;
            uint64_t t = (uint64_t)n * j + i;
            for (int b = 0; b < 8; b++)
                a[b] = block[b] ^ (uint8_t)(t >> (8 * (7 - b)));
            memcpy(wrapped + 8 * i, block + 8, 8);
        }
    }
    memcpy(wrapped, a, 8);
    *wrapped_length = raw_length + 8;
    return kCCSuccess;
}

CC_EXPORT int darwin_CCSymmetricKeyUnwrap(uint32_t algorithm, const uint8_t *iv, size_t iv_length, const uint8_t *kek,
                                          size_t kek_length, const uint8_t *wrapped, size_t wrapped_length, uint8_t *raw,
                                          size_t *raw_length) __asm__("_CCSymmetricKeyUnwrap");
CC_EXPORT int darwin_CCSymmetricKeyUnwrap(uint32_t algorithm, const uint8_t *iv, size_t iv_length, const uint8_t *kek,
                                          size_t kek_length, const uint8_t *wrapped, size_t wrapped_length, uint8_t *raw,
                                          size_t *raw_length) {
    if (algorithm != kCCWRAPAES || !iv || iv_length != 8 || !wrapped || wrapped_length < 24 || wrapped_length % 8 ||
        !raw || !raw_length || *raw_length < wrapped_length - 8)
        return kCCParamError;
    size_t n = wrapped_length / 8 - 1;
    uint8_t a[8], block[16];
    memcpy(a, wrapped, 8);
    memmove(raw, wrapped + 8, wrapped_length - 8);
    for (int j = 5; j >= 0; j--) {
        for (size_t i = n; i >= 1; i--) {
            uint64_t t = (uint64_t)n * j + i;
            for (int b = 0; b < 8; b++)
                block[b] = a[b] ^ (uint8_t)(t >> (8 * (7 - b)));
            memcpy(block + 8, raw + 8 * (i - 1), 8);
            if (!aes_block(kek, kek_length, 0, block, block))
                return kCCParamError;
            memcpy(a, block, 8);
            memcpy(raw + 8 * (i - 1), block + 8, 8);
        }
    }
    if (memcmp(a, iv, 8) != 0)
        return kCCDecodeError;
    *raw_length = wrapped_length - 8;
    return kCCSuccess;
}
