// Security: random bytes; the keychain's generic and internet passwords
// (add, copy, update, delete, attributes, persistent references, match
// limits, errors); RSA and elliptic-curve keys (import, export, signing,
// verification, encryption, key exchange, ECIES, generation, keys stored
// in the keychain); certificates; and trust evaluation with policies,
// anchors and dates. Keys and certificates are fixed so output is
// reproducible. Darwin's output comes from the iOS Simulator, whose
// keychain the entitlements open.

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include <stdio.h>
#include <stdlib.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static NSString *const RSA_HEX =
    @"308204a30201000282010100c17c398e81cbfffa1e7698991cc464a4d17e73725785f644600294a4638440d477dce05e"
    @"287251d34bc90f0c0daa7b26a4f76bfe765b1775f32707f25267c25b1c328787ca226007396ea1ec0f8b11ca95616e47"
    @"18ca73d3826421dcea634c748aae9ac249a20e4eca04de01dae4ba9429b438a5bd5f894c88a8b748f1979c771bd02a1a"
    @"6609e9a4ab4c47021b1b7d2831fb3972318afdc7a97c0df15f6507dcacee519ec65ca0648e5021aabb3a1e70028437c4"
    @"7120231fee1350036e8611820f90e347a1d7654de4337406c5aa2d9754b0f1c5c2db7e8dd36f3d6207a603e9656c7f00"
    @"1714e2d65c6c0dea1381e2d657b2939fc366e083f512998403b116d302030100010282010039b4ad0ddd945421ead800"
    @"271a3750b4ff6e314c56e23352ad37d7d137850838d60ee033f4e833934b3509f1d45996252e6a44a13df76905daa137"
    @"73843441f91e6dcb922a2d1a6acd2c3bcac5cffa5c6b3505c8da91f6fd8c14052d78126989109b86b88f716fc6fbe57b"
    @"b91de9bde3d6945398cae42574d80549b4cda92416b438508b02434095571d5efbab3c7d914968212f1b8dd880623af2"
    @"2a0209973a981d2f3541a75e43da26dfb9e5f0dccefec8fc9ce0c700d00376ac5cec1671cc8ca324d5c171410971537c"
    @"b7c19dc7a9533cbef75ed13585b4a1de5d71cd9c6cd7973fb827d7e6c2b0238b43bcb11de9d56a5b1522592e6a15574b"
    @"feb4da8db102818100fc9fb92afb0f854b7acfab9331afe5a374d6783c44bfe3b054e8e541e7a081978237b838a4f31f"
    @"d71fdeb8bb167529bcc4efc0237c3c63fa048da11afd2d523a9f3602f628e050651248f2e2a789ccd257ab29304f9fd6"
    @"025320ab358a662ca7f10eb0be6830270f39834de2b587141e97c920f8524cc34d05a73aa77d4fc67502818100c4122d"
    @"2704bcb14ce877eac35c4161be6ecd98f5a23b22b4c6d17f384e4e8db50012435806ca4ad667773a09a20fb49a920ecd"
    @"d64548502ca3fe20dc201968fb20d5075621abe597c4e297d5e56bd3f57d3122097156e5762d3fd6286693c3f1be7efa"
    @"23ee8bb0a9e4323bdc32ee474e2afe36b38664e3c78860be862d250f27028180599a19664a483602109c4a01da54c641"
    @"94b6614d17216c93e579f99ec7962180e899f4c87a9115510b27c723ec923fec8979740fe207d57a1f5550b82ee67d4c"
    @"f79d83ad65d03213b74992849be1ff78f7c968c18eec654ecbc74192aaf5148fb8ab7a3afedf5d6b43fdf3891ed3bb6a"
    @"22721f3494944f8d291d286bb1c1b2e502818100b200325faeec43262811ddde77dd9f880bfdb8f49ed082e48d6ed9c9"
    @"5b45f35e33ef609604ac181ee79594e9f3e7c035678deb0eb09d42b414397cc97a96b6f8edc8983d789a1ef896b483d5"
    @"9acf368132a3ad5bd73a655cd11d9825db6220cc51fde2c746242941433adb9f3fd99480818582519f1beeb251bc4a9b"
    @"7356a6970281800f2a7b1ddbc10a38332798a82cffa0eb7d5435ab48ba0741875621086332d77f9d84b58864ccad7aef"
    @"19e3e230c82f59bc3a8f940f48a9f9047766d82eafc56dca3c451112a68706a63324fe1e8edb348d12ea21f47491c53c"
    @"7eb2bf65a290640b2412b8b555c8686a37ab174b7029162feca7742e7ea1d2ffaf1d18e9385646";
static NSString *const EC1_HEX =
    @"04e7f3114ce59bd871154628a3f71bd8a77dfe74c051c0e4e3a38db42dd43546d767dc36139713e7ffbc8756ae727bb5"
    @"af1a73beeba3cc3d93ca72d3e2423d6778ff1efab9a5ae9c5a4c0689c12c3c72d0ae67ac3ac5d4f779cdb49590e2273b"
    @"8c";
static NSString *const EC2_HEX =
    @"043d3b608f671a4d7003e15029be8518a8016c2bcd5f302a98c8dddf1835d2964367aef8a2a94f0d653f91ef192161fc"
    @"b75e58072f76feaed5dcacf68119302bd38ab091a0eb65d74526a43fa3df1f146071f7eb3de3471cc2c752c3e54f1a00"
    @"3f";
static NSString *const CA_HEX =
    @"3082018330820128a00302010202021001300a06082a8648ce3d04030230283116301406035504030c0d506572727920"
    @"54657374204341310e300c060355040a0c055065727279301e170d3236313130323137303334395a170d333631303330"
    @"3137303334395a30283116301406035504030c0d50657272792054657374204341310e300c060355040a0c0550657272"
    @"793059301306072a8648ce3d020106082a8648ce3d030107034200047abe7dc48472e048c8dc5a4b1f47409368bc4efa"
    @"6d24788fe90c272af97410691864cd578e834f7ea2fefe48e9633d7cd1588e4f3150936e38952f8c162a6e50a3423040"
    @"300f0603551d130101ff040530030101ff300e0603551d0f0101ff040403020106301d0603551d0e0416041435315131"
    @"8e675044e52d6b4185190b451a2d13dc300a06082a8648ce3d0403020349003046022100889457988b4b3942d5dba0cc"
    @"0b614a611686c90854c1c035064f4ead7c2dc86f022100a302f3232e597720d512456f45c93f43d8b2463324085acd59"
    @"97a7a977f0932c";
static NSString *const LEAF_HEX =
    @"308201ec30820192a00302010202022002300a06082a8648ce3d04030230283116301406035504030c0d506572727920"
    @"54657374204341310e300c060355040a0c055065727279301e170d3236313130323137303334395a170d323930313130"
    @"3137303334395a30473112301006035504030c096c6f63616c686f7374310e300c060355040a0c055065727279312130"
    @"1f06092a864886f70d0109011612746573744070657272792e696e76616c69643059301306072a8648ce3d020106082a"
    @"8648ce3d030107034200040069052d6c4bfa6f85520358a091ee9562f45d58c649ac0e127d85d6108b53f3e39d2aa89d"
    @"ed7ad5365c6569539b1e0f93c8e956b364e12449cfa3ca841686fba3818c308189300c0603551d130101ff0402300030"
    @"0e0603551d0f0101ff04040302078030130603551d25040c300a06082b0601050507030130140603551d11040d300b82"
    @"096c6f63616c686f7374301d0603551d0e041604145ab420c68ee06676f29220d8d62c8ad8d38fd67e301f0603551d23"
    @"041830168014353151318e675044e52d6b4185190b451a2d13dc300a06082a8648ce3d040302034800304502201121c2"
    @"9e53c4066ee03612c2e07f3fda4f7d90aaa7ee5f4c17b7e00a0ec1c13e022100e666aaf16d61c91968e826b7a963efde"
    @"b37f5ef2fd6867ea1b1791292d991b17";

static NSData *hexData(NSString *hex) {
    NSMutableData *data = [NSMutableData dataWithCapacity:hex.length / 2];
    for (NSUInteger i = 0; i + 1 < hex.length; i += 2) {
        char pair[3] = {(char)[hex characterAtIndex:i], (char)[hex characterAtIndex:i + 1], 0};
        uint8_t byte = (uint8_t)strtoul(pair, NULL, 16);
        [data appendBytes:&byte length:1];
    }
    return data;
}

static NSString *hex(NSData *data, NSUInteger limit) {
    NSMutableString *text = [NSMutableString string];
    const uint8_t *bytes = data.bytes;
    for (NSUInteger i = 0; i < MIN(limit, data.length); i++) [text appendFormat:@"%02x", bytes[i]];
    return text;
}

static NSString *status(OSStatus status) {
    return [NSString stringWithFormat:@"%d", (int)status];
}

static NSString *errorText(CFErrorRef error) {
    if (!error) return @"nil";
    NSError *object = (__bridge NSError *)error;
    return [NSString stringWithFormat:@"%@ %ld", object.domain, (long)object.code];
}

#define B(x) ((__bridge id)(x))

// MARK: - Keychain

static NSString *const Service = @"org.perry.keyring";

static NSDictionary *password(NSString *account) {
    return @{B(kSecClass): B(kSecClassGenericPassword), B(kSecAttrService): Service, B(kSecAttrAccount): account};
}

static NSDictionary *with(NSDictionary *base, NSDictionary *more) {
    NSMutableDictionary *merged = [base mutableCopy];
    [merged addEntriesFromDictionary:more];
    return merged;
}

static void keychain(void) {
    uint8_t random[32] = {0};
    int filled = SecRandomCopyBytes(kSecRandomDefault, sizeof(random), random);
    int nonzero = 0;
    for (int i = 0; i < 32; i++) nonzero += random[i] != 0;
    say([NSString stringWithFormat:@"random: %d, filled %d", filled, nonzero > 20]);

    // Leftovers from an interrupted run.
    SecItemDelete((__bridge CFDictionaryRef)@{B(kSecClass): B(kSecClassGenericPassword), B(kSecAttrService): Service});
    SecItemDelete((__bridge CFDictionaryRef)@{B(kSecClass): B(kSecClassInternetPassword), B(kSecAttrServer): @"keyring.perry.invalid"});

    NSData *secret = [@"s3cret" dataUsingEncoding:NSUTF8StringEncoding];
    OSStatus added = SecItemAdd((__bridge CFDictionaryRef)with(password(@"alice"),
        @{B(kSecValueData): secret, B(kSecAttrLabel): @"Alice", B(kSecAttrComment): @"first"}), NULL);
    OSStatus duplicate = SecItemAdd((__bridge CFDictionaryRef)with(password(@"alice"), @{B(kSecValueData): secret}), NULL);
    say([NSString stringWithFormat:@"add: %@, duplicate %@", status(added), status(duplicate)]);

    CFTypeRef result = NULL;
    OSStatus copied = SecItemCopyMatching((__bridge CFDictionaryRef)with(password(@"alice"),
        @{B(kSecReturnData): @YES, B(kSecMatchLimit): B(kSecMatchLimitOne)}), &result);
    NSData *data = CFBridgingRelease(result);
    say([NSString stringWithFormat:@"copy data: %@ '%@' %d", status(copied),
         [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], [data isKindOfClass:NSData.class]]);

    result = NULL;
    copied = SecItemCopyMatching((__bridge CFDictionaryRef)with(password(@"alice"), @{B(kSecReturnAttributes): @YES}), &result);
    NSDictionary *attributes = CFBridgingRelease(result);
    say([NSString stringWithFormat:@"attributes: %@ acct %@ svce %@ labl %@ icmt %@ pdmn %@ sync %@, dates %d %d, data %d",
         status(copied), attributes[B(kSecAttrAccount)], attributes[B(kSecAttrService)], attributes[B(kSecAttrLabel)],
         attributes[B(kSecAttrComment)], attributes[B(kSecAttrAccessible)], attributes[B(kSecAttrSynchronizable)],
         [attributes[B(kSecAttrCreationDate)] isKindOfClass:NSDate.class],
         [attributes[B(kSecAttrModificationDate)] isKindOfClass:NSDate.class], attributes[B(kSecValueData)] != nil]);

    result = NULL;
    copied = SecItemCopyMatching((__bridge CFDictionaryRef)with(password(@"alice"),
        @{B(kSecReturnAttributes): @YES, B(kSecReturnData): @YES}), &result);
    NSDictionary *both = CFBridgingRelease(result);
    say([NSString stringWithFormat:@"data and attributes: %@ '%@' %@", status(copied),
         [[NSString alloc] initWithData:both[B(kSecValueData)] encoding:NSUTF8StringEncoding], both[B(kSecAttrAccount)]]);

    SecItemAdd((__bridge CFDictionaryRef)with(password(@"bob"), @{B(kSecValueData): [@"hunter2" dataUsingEncoding:NSUTF8StringEncoding],
        B(kSecAttrAccessible): B(kSecAttrAccessibleAfterFirstUnlock)}), NULL);
    result = NULL;
    copied = SecItemCopyMatching((__bridge CFDictionaryRef)@{B(kSecClass): B(kSecClassGenericPassword), B(kSecAttrService): Service,
        B(kSecReturnAttributes): @YES, B(kSecMatchLimit): B(kSecMatchLimitAll)}, &result);
    NSArray *all = CFBridgingRelease(result);
    NSArray *accounts = [[all valueForKey:B(kSecAttrAccount)] sortedArrayUsingSelector:@selector(compare:)];
    NSDictionary *bob = [all filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"acct == 'bob'"]].firstObject;
    say([NSString stringWithFormat:@"all: %@ %lu %@, bob's pdmn %@", status(copied), (unsigned long)all.count,
         [accounts componentsJoinedByString:@","], bob[B(kSecAttrAccessible)]]);

    OSStatus updated = SecItemUpdate((__bridge CFDictionaryRef)password(@"alice"),
        (__bridge CFDictionaryRef)@{B(kSecValueData): [@"n3w" dataUsingEncoding:NSUTF8StringEncoding], B(kSecAttrLabel): @"Alice 2"});
    OSStatus missingUpdate = SecItemUpdate((__bridge CFDictionaryRef)password(@"nobody"),
        (__bridge CFDictionaryRef)@{B(kSecAttrLabel): @"x"});
    result = NULL;
    SecItemCopyMatching((__bridge CFDictionaryRef)with(password(@"alice"), @{B(kSecReturnAttributes): @YES, B(kSecReturnData): @YES}), &result);
    NSDictionary *after = CFBridgingRelease(result);
    say([NSString stringWithFormat:@"update: %@, missing %@, now '%@' %@, modified later %d", status(updated), status(missingUpdate),
         [[NSString alloc] initWithData:after[B(kSecValueData)] encoding:NSUTF8StringEncoding], after[B(kSecAttrLabel)],
         [after[B(kSecAttrModificationDate)] compare:after[B(kSecAttrCreationDate)]] != NSOrderedAscending]);

    result = NULL;
    SecItemCopyMatching((__bridge CFDictionaryRef)with(password(@"bob"), @{B(kSecReturnPersistentRef): @YES}), &result);
    NSData *reference = CFBridgingRelease(result);
    result = NULL;
    copied = SecItemCopyMatching((__bridge CFDictionaryRef)@{B(kSecValuePersistentRef): reference, B(kSecReturnData): @YES}, &result);
    NSData *byReference = CFBridgingRelease(result);
    say([NSString stringWithFormat:@"persistent reference: %d, %@ '%@'", [reference isKindOfClass:NSData.class], status(copied),
         [[NSString alloc] initWithData:byReference encoding:NSUTF8StringEncoding]]);

    NSDictionary *internet = @{B(kSecClass): B(kSecClassInternetPassword), B(kSecAttrServer): @"keyring.perry.invalid",
                               B(kSecAttrProtocol): B(kSecAttrProtocolHTTPS), B(kSecAttrPort): @443, B(kSecAttrAccount): @"carol"};
    added = SecItemAdd((__bridge CFDictionaryRef)with(internet, @{B(kSecValueData): [@"pa55" dataUsingEncoding:NSUTF8StringEncoding]}), NULL);
    result = NULL;
    copied = SecItemCopyMatching((__bridge CFDictionaryRef)@{B(kSecClass): B(kSecClassInternetPassword),
        B(kSecAttrServer): @"keyring.perry.invalid", B(kSecReturnAttributes): @YES, B(kSecReturnData): @YES}, &result);
    NSDictionary *found = CFBridgingRelease(result);
    say([NSString stringWithFormat:@"internet: add %@, copy %@ '%@' %@ %@ %@ %@", status(added), status(copied),
         [[NSString alloc] initWithData:found[B(kSecValueData)] encoding:NSUTF8StringEncoding], found[B(kSecAttrAccount)],
         found[B(kSecAttrProtocol)], found[B(kSecAttrPort)], found[B(kSecAttrServer)]]);

    OSStatus deleted = SecItemDelete((__bridge CFDictionaryRef)password(@"alice"));
    copied = SecItemCopyMatching((__bridge CFDictionaryRef)password(@"alice"), NULL);
    OSStatus again = SecItemDelete((__bridge CFDictionaryRef)password(@"alice"));
    OSStatus rest = SecItemDelete((__bridge CFDictionaryRef)@{B(kSecClass): B(kSecClassGenericPassword), B(kSecAttrService): Service});
    OSStatus internetDeleted = SecItemDelete((__bridge CFDictionaryRef)internet);
    say([NSString stringWithFormat:@"delete: %@, then copy %@, again %@, rest %@, internet %@", status(deleted), status(copied),
         status(again), status(rest), status(internetDeleted)]);

    OSStatus noClass = SecItemAdd((__bridge CFDictionaryRef)@{B(kSecAttrAccount): @"x", B(kSecValueData): secret}, NULL);
    OSStatus noClassQuery = SecItemCopyMatching((__bridge CFDictionaryRef)@{B(kSecAttrAccount): @"x"}, NULL);
    NSString *message = CFBridgingRelease(SecCopyErrorMessageString(errSecItemNotFound, NULL));
    say([NSString stringWithFormat:@"errors: %@ %@; '%@'", status(noClass), status(noClassQuery), message]);
}

// MARK: - Keys

static SecKeyRef importKey(NSString *hexText, id type, id keyClass, int bits) {
    CFErrorRef error = NULL;
    SecKeyRef key = SecKeyCreateWithData((__bridge CFDataRef)hexData(hexText), (__bridge CFDictionaryRef)@{
        B(kSecAttrKeyType): type, B(kSecAttrKeyClass): keyClass, B(kSecAttrKeySizeInBits): @(bits)}, &error);
    if (!key) say([NSString stringWithFormat:@"import failed: %@", errorText(error)]);
    return key;
}

static void rsa(void) {
    SecKeyRef private = importKey(RSA_HEX, B(kSecAttrKeyTypeRSA), B(kSecAttrKeyClassPrivate), 2048);
    SecKeyRef public = SecKeyCopyPublicKey(private);
    NSDictionary *attributes = CFBridgingRelease(SecKeyCopyAttributes(private));
    say([NSString stringWithFormat:@"rsa: block %zu, type %@ class %@ bits %@, sign %@ decrypt %@, public class %@",
         SecKeyGetBlockSize(private), attributes[B(kSecAttrKeyType)], attributes[B(kSecAttrKeyClass)],
         attributes[B(kSecAttrKeySizeInBits)], attributes[B(kSecAttrCanSign)], attributes[B(kSecAttrCanDecrypt)],
         ((NSDictionary *)CFBridgingRelease(SecKeyCopyAttributes(public)))[B(kSecAttrKeyClass)]]);

    NSData *exported = CFBridgingRelease(SecKeyCopyExternalRepresentation(private, NULL));
    NSData *publicData = CFBridgingRelease(SecKeyCopyExternalRepresentation(public, NULL));
    say([NSString stringWithFormat:@"rsa export: private matches %d, public %lu bytes %@...", [exported isEqual:hexData(RSA_HEX)],
         (unsigned long)publicData.length, hex(publicData, 12)]);

    NSData *message = [@"hello, keyring" dataUsingEncoding:NSUTF8StringEncoding];
    CFErrorRef error = NULL;
    NSData *signature = CFBridgingRelease(SecKeyCreateSignature(private, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256,
                                                                (__bridge CFDataRef)message, &error));
    BOOL verified = SecKeyVerifySignature(public, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256, (__bridge CFDataRef)message,
                                          (__bridge CFDataRef)signature, NULL);
    NSData *tampered = [@"hello, keyrinG" dataUsingEncoding:NSUTF8StringEncoding];
    CFErrorRef verifyError = NULL;
    BOOL wrong = SecKeyVerifySignature(public, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256, (__bridge CFDataRef)tampered,
                                       (__bridge CFDataRef)signature, &verifyError);
    say([NSString stringWithFormat:@"rsa pkcs1 signature: %lu bytes %@..%@, verified %d, tampered %d %@",
         (unsigned long)signature.length, hex(signature, 8), hex([signature subdataWithRange:NSMakeRange(signature.length - 4, 4)], 4),
         verified, wrong, errorText(verifyError)]);

    NSData *pss = CFBridgingRelease(SecKeyCreateSignature(private, kSecKeyAlgorithmRSASignatureMessagePSSSHA256,
                                                          (__bridge CFDataRef)message, NULL));
    BOOL pssVerified = SecKeyVerifySignature(public, kSecKeyAlgorithmRSASignatureMessagePSSSHA256, (__bridge CFDataRef)message,
                                             (__bridge CFDataRef)pss, NULL);
    say([NSString stringWithFormat:@"rsa pss: %lu bytes, verified %d", (unsigned long)pss.length, pssVerified]);

    for (id algorithm in @[B(kSecKeyAlgorithmRSAEncryptionOAEPSHA256), B(kSecKeyAlgorithmRSAEncryptionOAEPSHA1),
                           B(kSecKeyAlgorithmRSAEncryptionPKCS1)]) {
        NSData *cipher = CFBridgingRelease(SecKeyCreateEncryptedData(public, (__bridge SecKeyAlgorithm)algorithm,
                                                                     (__bridge CFDataRef)message, NULL));
        NSData *plain = CFBridgingRelease(SecKeyCreateDecryptedData(private, (__bridge SecKeyAlgorithm)algorithm,
                                                                    (__bridge CFDataRef)cipher, NULL));
        say([NSString stringWithFormat:@"rsa %@: %lu bytes, round trip %d, supported %d %d", [algorithm componentsSeparatedByString:@":"].lastObject,
             (unsigned long)cipher.length, [plain isEqual:message],
             SecKeyIsAlgorithmSupported(public, kSecKeyOperationTypeEncrypt, (__bridge SecKeyAlgorithm)algorithm),
             SecKeyIsAlgorithmSupported(private, kSecKeyOperationTypeEncrypt, (__bridge SecKeyAlgorithm)algorithm)]);
    }
    CFRelease(public);
    CFRelease(private);
}

static void ec(void) {
    SecKeyRef first = importKey(EC1_HEX, B(kSecAttrKeyTypeECSECPrimeRandom), B(kSecAttrKeyClassPrivate), 256);
    SecKeyRef second = importKey(EC2_HEX, B(kSecAttrKeyTypeECSECPrimeRandom), B(kSecAttrKeyClassPrivate), 256);
    SecKeyRef firstPublic = SecKeyCopyPublicKey(first);
    SecKeyRef secondPublic = SecKeyCopyPublicKey(second);
    NSData *publicData = CFBridgingRelease(SecKeyCopyExternalRepresentation(firstPublic, NULL));
    NSData *privateData = CFBridgingRelease(SecKeyCopyExternalRepresentation(first, NULL));
    NSDictionary *attributes = CFBridgingRelease(SecKeyCopyAttributes(first));
    say([NSString stringWithFormat:@"ec: block %zu, public %lu bytes matches %d, private matches %d, type %@ bits %@",
         SecKeyGetBlockSize(first), (unsigned long)publicData.length,
         [publicData isEqual:[hexData(EC1_HEX) subdataWithRange:NSMakeRange(0, 65)]], [privateData isEqual:hexData(EC1_HEX)],
         attributes[B(kSecAttrKeyType)], attributes[B(kSecAttrKeySizeInBits)]]);

    NSData *message = [@"elliptic" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *signature = CFBridgingRelease(SecKeyCreateSignature(first, kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                                                                (__bridge CFDataRef)message, NULL));
    BOOL verified = SecKeyVerifySignature(firstPublic, kSecKeyAlgorithmECDSASignatureMessageX962SHA256, (__bridge CFDataRef)message,
                                          (__bridge CFDataRef)signature, NULL);
    BOOL other = SecKeyVerifySignature(secondPublic, kSecKeyAlgorithmECDSASignatureMessageX962SHA256, (__bridge CFDataRef)message,
                                       (__bridge CFDataRef)signature, NULL);
    NSData *raw = CFBridgingRelease(SecKeyCreateSignature(first, kSecKeyAlgorithmECDSASignatureRFC4754, (__bridge CFDataRef)message, NULL));
    say([NSString stringWithFormat:@"ecdsa: der %d, verified %d, other key %d, rfc4754 %lu bytes verified %d",
         ((const uint8_t *)signature.bytes)[0] == 0x30, verified, other, (unsigned long)raw.length,
         SecKeyVerifySignature(firstPublic, kSecKeyAlgorithmECDSASignatureRFC4754, (__bridge CFDataRef)message, (__bridge CFDataRef)raw, NULL)]);

    NSData *shared = CFBridgingRelease(SecKeyCopyKeyExchangeResult(first, kSecKeyAlgorithmECDHKeyExchangeStandard, secondPublic,
                                                                  (__bridge CFDictionaryRef)@{}, NULL));
    NSData *mirrored = CFBridgingRelease(SecKeyCopyKeyExchangeResult(second, kSecKeyAlgorithmECDHKeyExchangeStandard, firstPublic,
                                                                    (__bridge CFDictionaryRef)@{}, NULL));
    NSData *derived = CFBridgingRelease(SecKeyCopyKeyExchangeResult(first, kSecKeyAlgorithmECDHKeyExchangeStandardX963SHA256, secondPublic,
        (__bridge CFDictionaryRef)@{B(kSecKeyKeyExchangeParameterRequestedSize): @32,
                                    B(kSecKeyKeyExchangeParameterSharedInfo): [@"info" dataUsingEncoding:NSUTF8StringEncoding]}, NULL));
    say([NSString stringWithFormat:@"ecdh: %@, symmetric %d, x963 %@", hex(shared, 32), [shared isEqual:mirrored], hex(derived, 32)]);

    for (id algorithm in @[B(kSecKeyAlgorithmECIESEncryptionStandardX963SHA256AESGCM),
                           B(kSecKeyAlgorithmECIESEncryptionStandardVariableIVX963SHA256AESGCM)]) {
        NSData *cipher = CFBridgingRelease(SecKeyCreateEncryptedData(firstPublic, (__bridge SecKeyAlgorithm)algorithm,
                                                                     (__bridge CFDataRef)message, NULL));
        NSData *plain = CFBridgingRelease(SecKeyCreateDecryptedData(first, (__bridge SecKeyAlgorithm)algorithm,
                                                                    (__bridge CFDataRef)cipher, NULL));
        say([NSString stringWithFormat:@"ecies %@: %lu bytes, round trip %d", [algorithm componentsSeparatedByString:@":"].lastObject,
             (unsigned long)cipher.length, [plain isEqual:message]]);
    }

    CFErrorRef error = NULL;
    SecKeyRef generated = SecKeyCreateRandomKey((__bridge CFDictionaryRef)@{B(kSecAttrKeyType): B(kSecAttrKeyTypeECSECPrimeRandom),
                                                                           B(kSecAttrKeySizeInBits): @256}, &error);
    SecKeyRef generatedPublic = SecKeyCopyPublicKey(generated);
    NSData *generatedSignature = CFBridgingRelease(SecKeyCreateSignature(generated, kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                                                                         (__bridge CFDataRef)message, NULL));
    SecKeyRef rsaGenerated = SecKeyCreateRandomKey((__bridge CFDictionaryRef)@{B(kSecAttrKeyType): B(kSecAttrKeyTypeRSA),
                                                                              B(kSecAttrKeySizeInBits): @2048}, NULL);
    say([NSString stringWithFormat:@"generated: ec %d verified %d, rsa block %zu, bad size %@",
         generated != NULL, SecKeyVerifySignature(generatedPublic, kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                                                  (__bridge CFDataRef)message, (__bridge CFDataRef)generatedSignature, NULL),
         SecKeyGetBlockSize(rsaGenerated),
         SecKeyCreateRandomKey((__bridge CFDictionaryRef)@{B(kSecAttrKeyType): B(kSecAttrKeyTypeECSECPrimeRandom),
                                                           B(kSecAttrKeySizeInBits): @123}, NULL) ? @"made" : @"refused"]);

    NSData *tag = [@"org.perry.keyring.key" dataUsingEncoding:NSUTF8StringEncoding];
    SecItemDelete((__bridge CFDictionaryRef)@{B(kSecClass): B(kSecClassKey), B(kSecAttrApplicationTag): tag});
    SecKeyRef stored = SecKeyCreateRandomKey((__bridge CFDictionaryRef)@{B(kSecAttrKeyType): B(kSecAttrKeyTypeECSECPrimeRandom),
        B(kSecAttrKeySizeInBits): @256, B(kSecPrivateKeyAttrs): @{B(kSecAttrIsPermanent): @YES, B(kSecAttrApplicationTag): tag}}, NULL);
    CFTypeRef result = NULL;
    OSStatus copied = SecItemCopyMatching((__bridge CFDictionaryRef)@{B(kSecClass): B(kSecClassKey), B(kSecAttrApplicationTag): tag,
        B(kSecAttrKeyType): B(kSecAttrKeyTypeECSECPrimeRandom), B(kSecReturnRef): @YES}, &result);
    SecKeyRef fetched = (SecKeyRef)result;
    NSData *fetchedSignature = CFBridgingRelease(SecKeyCreateSignature(fetched, kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                                                                       (__bridge CFDataRef)message, NULL));
    SecKeyRef storedPublic = SecKeyCopyPublicKey(stored);
    OSStatus keyDeleted = SecItemDelete((__bridge CFDictionaryRef)@{B(kSecClass): B(kSecClassKey), B(kSecAttrApplicationTag): tag});
    say([NSString stringWithFormat:@"stored key: %@, same key %d, deleted %@", status(copied),
         SecKeyVerifySignature(storedPublic, kSecKeyAlgorithmECDSASignatureMessageX962SHA256, (__bridge CFDataRef)message,
                               (__bridge CFDataRef)fetchedSignature, NULL), status(keyDeleted)]);
}

// MARK: - Certificates and trust

static void trust(void) {
    SecCertificateRef ca = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)hexData(CA_HEX));
    SecCertificateRef leaf = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)hexData(LEAF_HEX));
    SecCertificateRef garbage = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)[@"not a certificate" dataUsingEncoding:NSUTF8StringEncoding]);
    CFStringRef commonName = NULL;
    SecCertificateCopyCommonName(leaf, &commonName);
    CFArrayRef emails = NULL;
    SecCertificateCopyEmailAddresses(leaf, &emails);
    NSData *serial = CFBridgingRelease(SecCertificateCopySerialNumberData(leaf, NULL));
    NSData *der = CFBridgingRelease(SecCertificateCopyData(leaf));
    SecKeyRef leafKey = SecCertificateCopyKey(leaf);
    NSData *leafKeyData = CFBridgingRelease(SecKeyCopyExternalRepresentation(leafKey, NULL));
    say([NSString stringWithFormat:@"certificate: '%@' '%@' ca '%@', emails %@, serial %@, der matches %d, key %lu bytes, garbage %d",
         CFBridgingRelease(SecCertificateCopySubjectSummary(leaf)), CFBridgingRelease(commonName),
         CFBridgingRelease(SecCertificateCopySubjectSummary(ca)), [CFBridgingRelease(emails) componentsJoinedByString:@","],
         hex(serial, 8), [der isEqual:hexData(LEAF_HEX)], (unsigned long)leafKeyData.length, garbage != NULL]);

    NSArray *chain = @[(__bridge id)leaf, (__bridge id)ca];
    NSDate *now = [NSDate dateWithTimeIntervalSince1970:1800000000];   // 2027-01-15
    NSArray *cases = @[
        @[@"localhost", @YES, now, @"trusted"],
        @[@"example.com", @YES, now, @"wrong host"],
        @[@"localhost", @NO, now, @"no anchor"],
        @[@"localhost", @YES, [NSDate dateWithTimeIntervalSince1970:2000000000], @"expired"],
    ];
    for (NSArray *test in cases) {
        SecPolicyRef policy = SecPolicyCreateSSL(true, (__bridge CFStringRef)test[0]);
        SecTrustRef evaluation = NULL;
        OSStatus created = SecTrustCreateWithCertificates((__bridge CFArrayRef)chain, policy, &evaluation);
        if ([test[1] boolValue]) SecTrustSetAnchorCertificates(evaluation, (__bridge CFArrayRef)@[(__bridge id)ca]);
        else SecTrustSetAnchorCertificatesOnly(evaluation, true);
        SecTrustSetVerifyDate(evaluation, (__bridge CFDateRef)test[2]);
        CFErrorRef error = NULL;
        bool trusted = SecTrustEvaluateWithError(evaluation, &error);
        SecTrustResultType resultType = 0;
        SecTrustGetTrustResult(evaluation, &resultType);
        say([NSString stringWithFormat:@"trust %@: created %@, trusted %d, result %u, error %@, chain %ld", test[3], status(created),
             trusted, resultType, errorText(error), (long)SecTrustGetCertificateCount(evaluation)]);
        if (error) CFRelease(error);
        CFRelease(evaluation);
        CFRelease(policy);
    }

    SecPolicyRef basic = SecPolicyCreateBasicX509();
    SecTrustRef evaluation = NULL;
    SecTrustCreateWithCertificates((__bridge CFArrayRef)chain, basic, &evaluation);
    SecTrustSetAnchorCertificates(evaluation, (__bridge CFArrayRef)@[(__bridge id)ca]);
    SecTrustSetVerifyDate(evaluation, (__bridge CFDateRef)now);
    bool trusted = SecTrustEvaluateWithError(evaluation, NULL);
    SecKeyRef trustKey = SecTrustCopyKey(evaluation);
    NSArray *built = CFBridgingRelease(SecTrustCopyCertificateChain(evaluation));
    NSDictionary *policyProperties = CFBridgingRelease(SecPolicyCopyProperties(basic));
    say([NSString stringWithFormat:@"basic: trusted %d, key %d, chain %lu, leaf first %d, policy %@",
         trusted, trustKey != NULL, (unsigned long)built.count, CFEqual((__bridge CFTypeRef)built.firstObject, leaf),
         policyProperties[B(kSecPolicyOid)]]);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        keychain();
        rsa();
        ec();
        trust();
    }
    return 0;
}
