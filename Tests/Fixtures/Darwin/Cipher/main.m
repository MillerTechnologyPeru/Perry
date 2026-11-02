// CommonCrypto: digests (one-shot, incremental, copied contexts), HMAC,
// symmetric ciphers in each algorithm and mode, CommonCrypto's errors,
// PBKDF2, AES key wrapping and random bytes.

#import <CommonCrypto/CommonCrypto.h>
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <string.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static NSString *hex(const void *bytes, size_t length) {
    NSMutableString *text = [NSMutableString string];
    for (size_t i = 0; i < length; i++) {
        [text appendFormat:@"%02x", ((const uint8_t *)bytes)[i]];
    }
    return text;
}

static const char *fox = "The quick brown fox jumps over the lazy dog";

static void digests(void) {
    uint8_t md[CC_SHA512_DIGEST_LENGTH];
    const char *inputs[] = {"", "abc", fox};
    for (int i = 0; i < 3; i++) {
        CC_LONG n = (CC_LONG)strlen(inputs[i]);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        CC_MD5(inputs[i], n, md);
#pragma clang diagnostic pop
        say([NSString stringWithFormat:@"md5('%s') %@", inputs[i], hex(md, CC_MD5_DIGEST_LENGTH)]);
        CC_SHA1(inputs[i], n, md);
        say([NSString stringWithFormat:@"sha1 %@", hex(md, CC_SHA1_DIGEST_LENGTH)]);
        CC_SHA224(inputs[i], n, md);
        say([NSString stringWithFormat:@"sha224 %@", hex(md, CC_SHA224_DIGEST_LENGTH)]);
        CC_SHA256(inputs[i], n, md);
        say([NSString stringWithFormat:@"sha256 %@", hex(md, CC_SHA256_DIGEST_LENGTH)]);
        CC_SHA384(inputs[i], n, md);
        say([NSString stringWithFormat:@"sha384 %@", hex(md, CC_SHA384_DIGEST_LENGTH)]);
        CC_SHA512(inputs[i], n, md);
        say([NSString stringWithFormat:@"sha512 %@", hex(md, CC_SHA512_DIGEST_LENGTH)]);
    }

    // A million 'a's, fed in uneven pieces, and a context copied midway.
    NSMutableData *million = [NSMutableData dataWithLength:1000000];
    memset(million.mutableBytes, 'a', million.length);
    CC_SHA256_CTX sha256;
    CC_SHA512_CTX sha512;
    CC_SHA1_CTX sha1;
    CC_SHA256_Init(&sha256);
    CC_SHA512_Init(&sha512);
    CC_SHA1_Init(&sha1);
    size_t offset = 0, piece = 1;
    CC_SHA256_CTX fork;
    BOOL forked = NO;
    while (offset < million.length) {
        size_t take = MIN(piece, million.length - offset);
        CC_SHA256_Update(&sha256, (const uint8_t *)million.bytes + offset, (CC_LONG)take);
        CC_SHA512_Update(&sha512, (const uint8_t *)million.bytes + offset, (CC_LONG)take);
        CC_SHA1_Update(&sha1, (const uint8_t *)million.bytes + offset, (CC_LONG)take);
        offset += take;
        if (offset >= 500000 && !forked) {
            fork = sha256;
            forked = YES;
        }
        piece = piece * 3 + 7;
    }
    CC_SHA256_Final(md, &sha256);
    say([NSString stringWithFormat:@"sha256(million a) %@", hex(md, 32)]);
    CC_SHA512_Final(md, &sha512);
    say([NSString stringWithFormat:@"sha512(million a) %@", hex(md, 64)]);
    CC_SHA1_Final(md, &sha1);
    say([NSString stringWithFormat:@"sha1(million a) %@", hex(md, 20)]);
    CC_SHA256_Update(&fork, "tail", 4);
    CC_SHA256_Final(md, &fork);
    say([NSString stringWithFormat:@"copied context %@", hex(md, 32)]);
}

static void hmacs(void) {
    struct { CCHmacAlgorithm algorithm; const char *name; size_t length; } kinds[] = {
        {kCCHmacAlgMD5, "md5", 16}, {kCCHmacAlgSHA1, "sha1", 20}, {kCCHmacAlgSHA224, "sha224", 28},
        {kCCHmacAlgSHA256, "sha256", 32}, {kCCHmacAlgSHA384, "sha384", 48}, {kCCHmacAlgSHA512, "sha512", 64},
    };
    uint8_t mac[64];
    char longKey[200];
    memset(longKey, 'k', sizeof longKey);
    for (int i = 0; i < 6; i++) {
        CCHmac(kinds[i].algorithm, "key", 3, fox, strlen(fox), mac);
        NSString *oneShot = hex(mac, kinds[i].length);
        CCHmacContext context;
        CCHmacInit(&context, kinds[i].algorithm, longKey, sizeof longKey);
        CCHmacUpdate(&context, fox, 10);
        CCHmacUpdate(&context, fox + 10, strlen(fox) - 10);
        CCHmacFinal(&context, mac);
        say([NSString stringWithFormat:@"hmac %s %@ long key %@", kinds[i].name, oneShot, hex(mac, kinds[i].length)]);
    }
}

static void cryptOnce(NSString *label, CCOperation operation, CCAlgorithm algorithm, CCOptions options, const void *key,
                  size_t keyLength, const void *iv, const void *input, size_t length) {
    uint8_t output[256];
    size_t moved = 0;
    CCCryptorStatus status = CCCrypt(operation, algorithm, options, key, keyLength, iv, input, length, output,
                                     sizeof output, &moved);
    say([NSString stringWithFormat:@"%@: status %d, %zu bytes %@", label, status, moved,
         status == kCCSuccess ? hex(output, moved) : @""]);
}

static void ciphers(void) {
    const uint8_t key[32] = "0123456789abcdef0123456789ABCDEF";
    const uint8_t iv[16] = "fedcba9876543210";
    const char *message = "Attack at dawn, then retreat at dusk.";
    size_t length = strlen(message);

    cryptOnce(@"aes128 cbc pkcs7", kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, key, 16, iv, message, length);
    cryptOnce(@"aes192 cbc pkcs7", kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, key, 24, iv, message, length);
    cryptOnce(@"aes256 ecb pkcs7", kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding | kCCOptionECBMode, key, 32, NULL,
          message, length);
    cryptOnce(@"aes128 cbc 32 bytes no padding", kCCEncrypt, kCCAlgorithmAES, 0, key, 16, NULL, message, 32);
    cryptOnce(@"des cbc", kCCEncrypt, kCCAlgorithmDES, kCCOptionPKCS7Padding, key, 8, iv, message, length);
    cryptOnce(@"3des cbc", kCCEncrypt, kCCAlgorithm3DES, kCCOptionPKCS7Padding, key, 24, iv, message, length);
    cryptOnce(@"cast cbc", kCCEncrypt, kCCAlgorithmCAST, kCCOptionPKCS7Padding, key, 16, iv, message, length);
    cryptOnce(@"rc4", kCCEncrypt, kCCAlgorithmRC4, 0, key, 16, NULL, message, length);
    cryptOnce(@"rc2 cbc", kCCEncrypt, kCCAlgorithmRC2, kCCOptionPKCS7Padding, key, 16, iv, message, length);
    cryptOnce(@"blowfish cbc", kCCEncrypt, kCCAlgorithmBlowfish, kCCOptionPKCS7Padding, key, 16, iv, message, length);

    // Round trip, and the errors.
    uint8_t encrypted[64], decrypted[64];
    size_t moved = 0, back = 0;
    CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, key, 16, iv, message, length, encrypted, sizeof encrypted, &moved);
    CCCryptorStatus status = CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, key, 16, iv, encrypted, moved,
                                     decrypted, sizeof decrypted, &back);
    say([NSString stringWithFormat:@"round trip: status %d, %zu bytes, '%.*s'", status, back, (int)back, decrypted]);
    status = CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, key + 1, 16, iv, encrypted, moved, decrypted,
                     sizeof decrypted, &back);
    say([NSString stringWithFormat:@"wrong key: status %d", status]);
    status = CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, key, 15, iv, message, length, encrypted,
                     sizeof encrypted, &moved);
    say([NSString stringWithFormat:@"15-byte key: status %d", status]);
    moved = 0;
    status = CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, key, 16, iv, message, length, encrypted, 16, &moved);
    say([NSString stringWithFormat:@"small buffer: status %d, needs %zu", status, moved]);
    status = CCCrypt(kCCEncrypt, kCCAlgorithmAES, 0, key, 16, iv, message, 20, encrypted, sizeof encrypted, &moved);
    say([NSString stringWithFormat:@"unaligned without padding: status %d", status]);

    // A cryptor fed in pieces.
    CCCryptorRef cryptor;
    CCCryptorCreate(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, key, 16, iv, &cryptor);
    NSMutableArray *sizes = [NSMutableArray array];
    size_t total = 0;
    for (size_t at = 0; at < 48; at += 10) {
        size_t take = MIN((size_t)10, 48 - at);
        size_t needed = CCCryptorGetOutputLength(cryptor, take, false);
        CCCryptorUpdate(cryptor, encrypted + at, take, decrypted + total, sizeof decrypted - total, &moved);
        [sizes addObject:[NSString stringWithFormat:@"%zu/%zu", moved, needed]];
        total += moved;
    }
    size_t finalNeeded = CCCryptorGetOutputLength(cryptor, 0, true);
    status = CCCryptorFinal(cryptor, decrypted + total, sizeof decrypted - total, &moved);
    total += moved;
    CCCryptorRelease(cryptor);
    say([NSString stringWithFormat:@"pieces: %@, final %d %zu/%zu, '%.*s'", [sizes componentsJoinedByString:@" "],
         status, moved, finalNeeded, (int)total, decrypted]);

    // Stream modes.
    CCMode modes[] = {kCCModeCTR, kCCModeCFB, kCCModeOFB, kCCModeCFB8};
    const char *names[] = {"ctr", "cfb", "ofb", "cfb8"};
    for (int i = 0; i < 4; i++) {
        CCCryptorCreateWithMode(kCCEncrypt, modes[i], kCCAlgorithmAES, ccNoPadding, iv, key, 16, NULL, 0, 0,
                                modes[i] == kCCModeCTR ? kCCModeOptionCTR_BE : 0, &cryptor);
        CCCryptorUpdate(cryptor, message, length, encrypted, sizeof encrypted, &moved);
        size_t tail = 0;
        CCCryptorFinal(cryptor, encrypted + moved, sizeof encrypted - moved, &tail);
        CCCryptorRelease(cryptor);
        say([NSString stringWithFormat:@"aes128 %s: %zu+%zu %@", names[i], moved, tail, hex(encrypted, moved + tail)]);
    }
}

static void derivation(void) {
    uint8_t derived[64];
    int status = CCKeyDerivationPBKDF(kCCPBKDF2, "password", 8, (const uint8_t *)"salt", 4, kCCPRFHmacAlgSHA1, 2,
                                      derived, 20);
    say([NSString stringWithFormat:@"pbkdf2 sha1 x2: %d %@", status, hex(derived, 20)]);
    status = CCKeyDerivationPBKDF(kCCPBKDF2, "passwordPASSWORDpassword", 24,
                                  (const uint8_t *)"saltSALTsaltSALTsaltSALTsaltSALTsalt", 36, kCCPRFHmacAlgSHA256, 4096,
                                  derived, 40);
    say([NSString stringWithFormat:@"pbkdf2 sha256 x4096: %d %@", status, hex(derived, 40)]);
    status = CCKeyDerivationPBKDF(kCCPBKDF2, "pw", 2, (const uint8_t *)"s", 1, 99, 1, derived, 16);
    say([NSString stringWithFormat:@"pbkdf2 bad prf: %d", status]);
    unsigned rounds = CCCalibratePBKDF(kCCPBKDF2, 8, 8, kCCPRFHmacAlgSHA256, 32, 10);
    say([NSString stringWithFormat:@"calibrated rounds positive %d", rounds > 0 && rounds != UINT_MAX]);

    const uint8_t kek[16] = {0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f};
    const uint8_t raw[16] = {0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff};
    uint8_t wrapped[24], unwrapped[16];
    size_t wrappedLength = sizeof wrapped, unwrappedLength = sizeof unwrapped;
    status = CCSymmetricKeyWrap(kCCWRAPAES, CCrfc3394_iv, CCrfc3394_ivLen, kek, 16, raw, 16, wrapped, &wrappedLength);
    say([NSString stringWithFormat:@"wrap: %d, %zu bytes %@, sizes %zu %zu", status, wrappedLength, hex(wrapped, wrappedLength),
         CCSymmetricWrappedSize(kCCWRAPAES, 16), CCSymmetricUnwrappedSize(kCCWRAPAES, 24)]);
    status = CCSymmetricKeyUnwrap(kCCWRAPAES, CCrfc3394_iv, CCrfc3394_ivLen, kek, 16, wrapped, 24, unwrapped, &unwrappedLength);
    say([NSString stringWithFormat:@"unwrap: %d %@", status, hex(unwrapped, unwrappedLength)]);
    wrapped[3] ^= 1;
    unwrappedLength = sizeof unwrapped;
    status = CCSymmetricKeyUnwrap(kCCWRAPAES, CCrfc3394_iv, CCrfc3394_ivLen, kek, 16, wrapped, 24, unwrapped, &unwrappedLength);
    say([NSString stringWithFormat:@"tampered unwrap: %d", status]);

    uint8_t random[32] = {0};
    status = CCRandomGenerateBytes(random, sizeof random);
    uint8_t zeros[32] = {0};
    say([NSString stringWithFormat:@"random: %d, filled %d", status, memcmp(random, zeros, 32) != 0]);
}

int main(void) {
    @autoreleasepool {
        digests();
        hmacs();
        ciphers();
        derivation();
    }
    return 0;
}
