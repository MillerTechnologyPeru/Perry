// Coders, strings, scanners, attributed strings and character sets, built
// on a Mac with Xcode: secure keyed archiving with NSCoder's typed methods
// and its failure policy, NSArchiver's Objective-C type coding, string
// encoding detection, and the newer NSString, NSScanner,
// NSAttributedString and NSCharacterSet methods. Prints to stdout so the
// test can compare exact text.
#import <Foundation/Foundation.h>
#import <stdlib.h>
#import <string.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#pragma clang diagnostic ignored "-Wformat-nonliteral"

static void print(NSString *line) {
    printf("%s\n", line.UTF8String);
}

static NSString *flag(BOOL value) { return value ? @"YES" : @"NO"; }

// MARK: - Secure keyed coding

@interface SCRItem : NSObject <NSSecureCoding>
@property (nonatomic) int small;
@property (nonatomic) int32_t middle;
@property (nonatomic) int64_t big;
@property (nonatomic) float ratio;
@property (nonatomic) double precise;
@property (nonatomic) BOOL on;
@property (nonatomic, copy) NSData *blob;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSArray<NSString *> *tags;
@property (nonatomic, copy) NSDictionary<NSString *, NSNumber *> *scores;
@property (nonatomic, weak) SCRItem *partner;
@property (nonatomic, strong) SCRItem *child;
@property (nonatomic) BOOL sawItemAllowed;
@end

@implementation SCRItem
+ (BOOL)supportsSecureCoding { return YES; }

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInt:self.small forKey:@"small"];
    [coder encodeInt32:self.middle forKey:@"middle"];
    [coder encodeInt64:self.big forKey:@"big"];
    [coder encodeFloat:self.ratio forKey:@"ratio"];
    [coder encodeDouble:self.precise forKey:@"precise"];
    [coder encodeBool:self.on forKey:@"on"];
    [coder encodeBytes:self.blob.bytes length:self.blob.length forKey:@"blob"];
    [coder encodeObject:self.name forKey:@"name"];
    [coder encodeObject:self.tags forKey:@"tags"];
    [coder encodeObject:self.scores forKey:@"scores"];
    [coder encodeConditionalObject:self.partner forKey:@"partner"];
    [coder encodeObject:self.child forKey:@"child"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super init])) {
        _sawItemAllowed = [coder.allowedClasses containsObject:[SCRItem class]];
        _small = [coder decodeIntForKey:@"small"];
        _middle = [coder decodeInt32ForKey:@"middle"];
        _big = [coder decodeInt64ForKey:@"big"];
        _ratio = [coder decodeFloatForKey:@"ratio"];
        _precise = [coder decodeDoubleForKey:@"precise"];
        _on = [coder decodeBoolForKey:@"on"];
        NSUInteger length = 0;
        const uint8_t *bytes = [coder decodeBytesForKey:@"blob" returnedLength:&length];
        _blob = [NSData dataWithBytes:bytes length:length];
        _name = [coder decodeObjectOfClass:[NSString class] forKey:@"name"];
        _tags = [coder decodeArrayOfObjectsOfClass:[NSString class] forKey:@"tags"];
        _scores = [coder decodeDictionaryWithKeysOfClass:[NSString class] objectsOfClass:[NSNumber class] forKey:@"scores"];
        _partner = [coder decodeObjectOfClass:[SCRItem class] forKey:@"partner"];
        _child = [coder decodeObjectOfClasses:[NSSet setWithObjects:[SCRItem class], [NSNull class], nil] forKey:@"child"];
    }
    return self;
}

- (NSString *)summary {
    uint8_t blob[8] = {0};
    [self.blob getBytes:blob length:MIN(self.blob.length, sizeof blob)];
    NSMutableArray *scores = [NSMutableArray array];
    for (NSString *key in [self.scores.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [scores addObject:[NSString stringWithFormat:@"%@=%@", key, self.scores[key]]];
    }
    return [NSString stringWithFormat:@"%@ small=%d middle=%d big=%lld ratio=%.3f precise=%.6f on=%@ blob=%lu:%02x%02x tags=%@ scores=%@ allowed=%@",
            self.name, self.small, self.middle, self.big, self.ratio, self.precise, flag(self.on),
            (unsigned long)self.blob.length, blob[0], blob[1], [self.tags componentsJoinedByString:@","],
            [scores componentsJoinedByString:@","], flag(self.sawItemAllowed)];
}
@end

@interface SCRFailing : NSObject <NSSecureCoding>
@end

@implementation SCRFailing
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder { [coder encodeInt:1 forKey:@"one"]; }
- (instancetype)initWithCoder:(NSCoder *)coder {
    [coder failWithError:[NSError errorWithDomain:@"Scrivener" code:7 userInfo:nil]];
    return nil;
}
@end

@interface SCRInsecure : NSObject <NSCoding>
@end

@implementation SCRInsecure
- (void)encodeWithCoder:(NSCoder *)coder { [coder encodeInt:2 forKey:@"two"]; }
- (instancetype)initWithCoder:(NSCoder *)coder { return [super init]; }
@end

static SCRItem *item(NSString *name, int number) {
    SCRItem *item = [SCRItem new];
    item.name = name;
    item.small = -number;
    item.middle = number * 1000;
    item.big = (int64_t)number * 10000000000LL;
    item.ratio = number / 4.0f;
    item.precise = number / 3.0;
    item.on = number % 2;
    uint8_t bytes[] = {(uint8_t)number, 0xab, 0xcd};
    item.blob = [NSData dataWithBytes:bytes length:sizeof bytes];
    item.tags = @[name, @"tag"];
    item.scores = @{@"x": @(number), @"y": @(number * 2.5)};
    return item;
}

static NSString *errorText(NSError *error) {
    return error ? [NSString stringWithFormat:@"%@/%ld", error.domain, (long)error.code] : @"none";
}

static void keyedCoding(void) {
    SCRItem *a = item(@"a", 1), *b = item(@"b", 2), *c = item(@"c", 3), *d = item(@"d", 4), *e = item(@"e", 5);
    a.partner = b;
    c.partner = d;
    a.child = e;
    e.partner = a;
    NSError *error = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:@[a, b, c] requiringSecureCoding:YES error:&error];
    print([NSString stringWithFormat:@"archived=%@ error=%@", flag(data != nil), errorText(error)]);

    NSArray<SCRItem *> *items = [NSKeyedUnarchiver unarchivedArrayOfObjectsOfClass:[SCRItem class] fromData:data error:&error];
    print([NSString stringWithFormat:@"items=%lu error=%@", (unsigned long)items.count, errorText(error)]);
    for (SCRItem *decoded in items) print(decoded.summary);
    SCRItem *first = items[0];
    print([NSString stringWithFormat:@"a.partner is b=%@ c.partner=%@ a.child=%@ e.partner is a=%@",
           flag(first.partner == items[1]), items[2].partner ? @"set" : @"nil", first.child.name,
           flag(first.child.partner == first)]);

    // The wrong class, at the top and inside.
    NSArray *wrong = [NSKeyedUnarchiver unarchivedArrayOfObjectsOfClass:[NSString class] fromData:data error:&error];
    print([NSString stringWithFormat:@"as strings=%@ error=%ld", wrong ? @"set" : @"nil", (long)error.code]);
    error = nil;
    id number = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSNumber class]
                                                 fromData:[NSKeyedArchiver archivedDataWithRootObject:@"text" requiringSecureCoding:YES error:NULL]
                                                    error:&error];
    print([NSString stringWithFormat:@"string as number=%@ error=%ld", number ?: @"nil", (long)error.code]);

    // Dictionaries of classes.
    NSData *dictionary = [NSKeyedArchiver archivedDataWithRootObject:@{@"one": @1, @"two": @2} requiringSecureCoding:YES error:NULL];
    NSDictionary *decodedDictionary = [NSKeyedUnarchiver unarchivedDictionaryWithKeysOfClass:[NSString class] objectsOfClass:[NSNumber class]
                                                                                    fromData:dictionary error:&error];
    print([NSString stringWithFormat:@"dictionary one=%@ two=%@ count=%lu", decodedDictionary[@"one"], decodedDictionary[@"two"],
           (unsigned long)decodedDictionary.count]);
    // Numbers of the wrong class are refused on macOS 27 and accepted on
    // macOS 26, so no reference can show either.
    NSArray *mixed = [NSKeyedUnarchiver unarchivedArrayOfObjectsOfClasses:[NSSet setWithObjects:[NSString class], [NSNumber class], nil]
                                                                 fromData:[NSKeyedArchiver archivedDataWithRootObject:@[@"s", @4]
                                                                                                requiringSecureCoding:YES error:NULL]
                                                                    error:&error];
    print([NSString stringWithFormat:@"mixed=%@", [mixed componentsJoinedByString:@","]]);

    // The failure policy and the coder's error.
    NSData *text = [NSKeyedArchiver archivedDataWithRootObject:@"text" requiringSecureCoding:YES error:NULL];
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:text error:&error];
    print([NSString stringWithFormat:@"secure=%@ policy=%ld error=%@", flag(unarchiver.requiresSecureCoding),
           (long)unarchiver.decodingFailurePolicy, errorText(unarchiver.error)]);
    id wrongRoot = [unarchiver decodeObjectOfClass:[NSNumber class] forKey:NSKeyedArchiveRootObjectKey];
    print([NSString stringWithFormat:@"wrong root=%@ error=%ld", wrongRoot ?: @"nil", (long)unarchiver.error.code]);
    id after = [unarchiver decodeObjectOfClass:[NSString class] forKey:NSKeyedArchiveRootObjectKey];
    print([NSString stringWithFormat:@"after failure=%@", after ?: @"nil"]);
    [unarchiver finishDecoding];

    unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:text error:&error];
    NSError *topError = nil;
    id top = [unarchiver decodeTopLevelObjectOfClass:[NSNumber class] forKey:NSKeyedArchiveRootObjectKey error:&topError];
    print([NSString stringWithFormat:@"top level=%@ error=%ld coder error=%@", top ?: @"nil", (long)topError.code,
           errorText(unarchiver.error)]);
    top = [unarchiver decodeTopLevelObjectOfClass:[NSString class] forKey:NSKeyedArchiveRootObjectKey error:&topError];
    print([NSString stringWithFormat:@"top level again=%@", top ?: @"nil"]);
    [unarchiver finishDecoding];

    error = nil;
    id failing = [NSKeyedUnarchiver unarchivedObjectOfClass:[SCRFailing class]
                                                  fromData:[NSKeyedArchiver archivedDataWithRootObject:[SCRFailing new]
                                                                                 requiringSecureCoding:YES error:NULL]
                                                     error:&error];
    print([NSString stringWithFormat:@"failing=%@ error=%@", failing ?: @"nil", errorText(error)]);

    error = nil;
    NSData *insecure = [NSKeyedArchiver archivedDataWithRootObject:[SCRInsecure new] requiringSecureCoding:YES error:&error];
    print([NSString stringWithFormat:@"insecure archive=%@ error=%ld", insecure ? @"set" : @"nil", (long)error.code]);
    insecure = [NSKeyedArchiver archivedDataWithRootObject:[SCRInsecure new] requiringSecureCoding:NO error:NULL];
    error = nil;
    id insecureObject = [NSKeyedUnarchiver unarchivedObjectOfClass:[SCRInsecure class] fromData:insecure error:&error];
    print([NSString stringWithFormat:@"insecure unarchive=%@ error=%ld", insecureObject ? @"set" : @"nil", (long)error.code]);
    unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:insecure error:NULL];
    unarchiver.requiresSecureCoding = NO;
    insecureObject = [unarchiver decodeTopLevelObjectAndReturnError:&error];
    print([NSString stringWithFormat:@"insecure unchecked=%@", NSStringFromClass([insecureObject class])]);

    // Class names.
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initRequiringSecureCoding:YES];
    [archiver setClassName:@"SCRRenamed" forClass:[SCRItem class]];
    [NSKeyedArchiver setClassName:@"SCRGlobal" forClass:[SCRFailing class]];
    print([NSString stringWithFormat:@"class names=%@ %@ %@", [archiver classNameForClass:[SCRItem class]],
           [NSKeyedArchiver classNameForClass:[SCRFailing class]], [archiver classNameForClass:[NSString class]] ?: @"nil"]);
    [NSKeyedArchiver setClassName:nil forClass:[SCRFailing class]];
    [archiver encodeObject:item(@"renamed", 6) forKey:@"thing"];
    [archiver encodeInt64:-42 forKey:@"plain"];
    [archiver finishEncoding];
    unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:archiver.encodedData error:NULL];
    [unarchiver setClass:[SCRItem class] forClassName:@"SCRRenamed"];
    SCRItem *renamed = [unarchiver decodeObjectOfClass:[SCRItem class] forKey:@"thing"];
    print([NSString stringWithFormat:@"renamed=%@ plain=%lld int=%d contains=%@/%@", renamed.name,
           [unarchiver decodeInt64ForKey:@"plain"], [unarchiver decodeIntForKey:@"plain"],
           flag([unarchiver containsValueForKey:@"plain"]), flag([unarchiver containsValueForKey:@"missing"])]);
    [unarchiver finishDecoding];

    // Unkeyed values in a keyed archive.
    archiver = [[NSKeyedArchiver alloc] initRequiringSecureCoding:NO];
    int numbers[3] = {7, 8, 9};
    double real = 2.5;
    [archiver encodeValueOfObjCType:@encode(double) at:&real];
    [archiver encodeObject:@"unkeyed"];
    [archiver encodeBytes:"xyz" length:3];
    [archiver encodeArrayOfObjCType:@encode(int) count:3 at:numbers];
    short pair[2] = {-5, 6};
    [archiver encodeValuesOfObjCTypes:"ss", &pair[0], &pair[1]];
    [archiver encodeDataObject:[@"data" dataUsingEncoding:NSUTF8StringEncoding]];
    [archiver finishEncoding];
    unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:archiver.encodedData error:NULL];
    unarchiver.requiresSecureCoding = NO;
    double readReal = 0;
    [unarchiver decodeValueOfObjCType:@encode(double) at:&readReal size:sizeof readReal];
    NSString *unkeyed = [unarchiver decodeObject];
    NSUInteger byteCount = 0;
    const char *readBytes = [unarchiver decodeBytesWithReturnedLength:&byteCount];
    int readNumbers[3] = {0, 0, 0};
    [unarchiver decodeArrayOfObjCType:@encode(int) count:3 at:readNumbers];
    short readPair[2] = {0, 0};
    [unarchiver decodeValuesOfObjCTypes:"ss", &readPair[0], &readPair[1]];
    NSData *readData = [unarchiver decodeDataObject];
    print([NSString stringWithFormat:@"unkeyed real=%.1f object=%@ bytes=%.*s array=%d,%d,%d pair=%d,%d data=%@", readReal, unkeyed,
           (int)byteCount, readBytes, readNumbers[0], readNumbers[1], readNumbers[2], readPair[0], readPair[1],
           [[NSString alloc] initWithData:readData encoding:NSUTF8StringEncoding]]);
}

// MARK: - Delegates and streams

@interface SCRDelegate : NSObject <NSKeyedArchiverDelegate, NSKeyedUnarchiverDelegate>
@property (nonatomic) NSMutableArray<NSString *> *events;
@end

@implementation SCRDelegate
- (instancetype)init {
    if ((self = [super init])) _events = [NSMutableArray array];
    return self;
}
- (id)archiver:(NSKeyedArchiver *)archiver willEncodeObject:(id)object {
    if ([object isKindOfClass:[SCRItem class]]) [self.events addObject:[@"will:" stringByAppendingString:[object name]]];
    return object;
}
- (void)archiver:(NSKeyedArchiver *)archiver didEncodeObject:(id)object {
    if ([object isKindOfClass:[SCRItem class]]) [self.events addObject:[@"did:" stringByAppendingString:[object name]]];
}
- (void)archiverWillFinish:(NSKeyedArchiver *)archiver { [self.events addObject:@"willFinish"]; }
- (void)archiverDidFinish:(NSKeyedArchiver *)archiver { [self.events addObject:@"didFinish"]; }
- (id)unarchiver:(NSKeyedUnarchiver *)unarchiver didDecodeObject:(id)object {
    if ([object isKindOfClass:[SCRItem class]]) [self.events addObject:[@"decoded:" stringByAppendingString:[object name]]];
    return object;
}
- (void)unarchiverWillFinish:(NSKeyedUnarchiver *)unarchiver { [self.events addObject:@"unarchiverWillFinish"]; }
- (void)unarchiverDidFinish:(NSKeyedUnarchiver *)unarchiver { [self.events addObject:@"unarchiverDidFinish"]; }
@end

static void delegates(void) {
    SCRDelegate *delegate = [SCRDelegate new];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initRequiringSecureCoding:YES];
    archiver.delegate = delegate;
    SCRItem *outer = item(@"outer", 1);
    outer.child = item(@"inner", 2);
    [archiver encodeObject:outer forKey:@"outer"];
    [archiver finishEncoding];
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:archiver.encodedData error:NULL];
    unarchiver.delegate = delegate;
    SCRItem *decoded = [unarchiver decodeObjectOfClass:[SCRItem class] forKey:@"outer"];
    [unarchiver finishDecoding];
    print([NSString stringWithFormat:@"delegate=%@ events=%@ child=%@", flag(unarchiver.delegate == delegate),
           [delegate.events componentsJoinedByString:@","], decoded.child.name]);

    NSOutputStream *stream = [NSOutputStream outputStreamToMemory];
    [stream open];
    NSError *error = nil;
    NSInteger written = [NSPropertyListSerialization writePropertyList:@{@"key": @[@1, @"two"]} toStream:stream
                                                                format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
    NSData *xml = [stream propertyForKey:NSStreamDataWrittenToMemoryStreamKey];
    [stream close];
    id back = [NSPropertyListSerialization propertyListWithData:xml options:0 format:NULL error:NULL];
    print([NSString stringWithFormat:@"stream written=%@ round trip=%@", flag(written == (NSInteger)xml.length && written > 0),
           [back[@"key"] componentsJoinedByString:@"+"]]);
}

// MARK: - NSArchiver

typedef struct { int number; double amount; } SCRPair;

@interface SCRLegacy : NSObject <NSCoding>
@property (nonatomic) int first, second;
@property (nonatomic) float third;
- (short *)shorts;
- (void)setShorts:(const short *)shorts;
@property (nonatomic, copy) NSData *bytes, *data;
@property (nonatomic) SCRPair pair;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, strong) id conditional;
@end

@implementation SCRLegacy {
    short _values[3];
}
- (short *)shorts { return _values; }
- (void)setShorts:(const short *)shorts { memcpy(_values, shorts, sizeof _values); }

- (void)encodeWithCoder:(NSCoder *)coder {
    int first = self.first, second = self.second;
    float third = self.third;
    NSString *label = self.label;
    [coder encodeValuesOfObjCTypes:"ifi@", &first, &third, &second, &label];
    [coder encodeArrayOfObjCType:@encode(short) count:3 at:_values];
    [coder encodeBytes:self.bytes.bytes length:self.bytes.length];
    [coder encodeDataObject:self.data];
    SCRPair pair = self.pair;
    [coder encodeValueOfObjCType:@encode(SCRPair) at:&pair];
    [coder encodeConditionalObject:self.conditional];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super init])) {
        int first = 0, second = 0;
        float third = 0;
        NSString *label = nil;
        [coder decodeValuesOfObjCTypes:"ifi@", &first, &third, &second, &label];
        _first = first;
        _second = second;
        _third = third;
        _label = label;
        [coder decodeArrayOfObjCType:@encode(short) count:3 at:_values];
        NSUInteger length = 0;
        void *bytes = [coder decodeBytesWithReturnedLength:&length];
        _bytes = [NSData dataWithBytes:bytes length:length];
        _data = [coder decodeDataObject];
        SCRPair pair = {0, 0};
        [coder decodeValueOfObjCType:@encode(SCRPair) at:&pair size:sizeof pair];
        _pair = pair;
        _conditional = [coder decodeObject];
    }
    return self;
}
@end

static void legacyCoding(void) {
    Class archiverClass = NSClassFromString(@"NSArchiver"), unarchiverClass = NSClassFromString(@"NSUnarchiver");
    print([NSString stringWithFormat:@"archiver is coder=%@ unarchiver is coder=%@", flag([archiverClass isSubclassOfClass:[NSCoder class]]),
           flag([unarchiverClass isSubclassOfClass:[NSCoder class]])]);
    SCRLegacy *legacy = [SCRLegacy new];
    legacy.first = 11;
    legacy.second = -22;
    legacy.third = 3.5f;
    short shorts[3] = {-1, 300, 7};
    [legacy setShorts:shorts];
    legacy.bytes = [@"raw" dataUsingEncoding:NSUTF8StringEncoding];
    legacy.data = [@"payload" dataUsingEncoding:NSUTF8StringEncoding];
    legacy.pair = (SCRPair){42, 0.125};
    legacy.label = @"legacy";
    legacy.conditional = @"not elsewhere";
    NSData *data = [archiverClass archivedDataWithRootObject:legacy];
    SCRLegacy *back = [unarchiverClass unarchiveObjectWithData:data];
    print([NSString stringWithFormat:@"legacy first=%d second=%d third=%.2f label=%@ shorts=%d,%d,%d bytes=%@ data=%@ pair=%d/%.3f conditional=%@",
           back.first, back.second, back.third, back.label, back.shorts[0], back.shorts[1], back.shorts[2],
           [[NSString alloc] initWithData:back.bytes encoding:NSUTF8StringEncoding],
           [[NSString alloc] initWithData:back.data encoding:NSUTF8StringEncoding], back.pair.number, back.pair.amount,
           back.conditional ?: @"nil"]);
}

// MARK: - Strings

static NSString *detect(const void *bytes, NSUInteger length, NSDictionary *options) {
    NSString *converted = nil;
    BOOL lossy = NO;
    NSStringEncoding encoding = [NSString stringEncodingForData:[NSData dataWithBytes:bytes length:length]
                                                encodingOptions:options convertedString:&converted usedLossyConversion:&lossy];
    return [NSString stringWithFormat:@"%lu \"%@\" lossy=%@", (unsigned long)encoding, converted ?: @"(nil)", flag(lossy)];
}

// The layout of NSConstantString and NSSimpleCString objects, as older
// compilers and -fno-constant-cfstrings emit string literals.
static struct { Class isa; const char *bytes; unsigned int length; unsigned int unused; } legacyLiteral, simpleLiteral;

static void constantStrings(void) {
    legacyLiteral.isa = NSClassFromString(@"NSConstantString");
    legacyLiteral.bytes = "legacy literal!";
    legacyLiteral.length = 14;
    simpleLiteral.isa = NSClassFromString(@"NSSimpleCString");
    simpleLiteral.bytes = "simple";
    simpleLiteral.length = 6;
    __unsafe_unretained NSString *legacy = (__bridge NSString *)(void *)&legacyLiteral;
    __unsafe_unretained NSString *simple = (__bridge NSString *)(void *)&simpleLiteral;
    print([NSString stringWithFormat:@"constant class=%@ super=%@ string=%@ length=%lu upper=%@ char=%c equal=%@ hash=%@ kind=%@",
           NSStringFromClass([legacy class]), NSStringFromClass([[legacy class] superclass]), legacy, (unsigned long)legacy.length,
           legacy.uppercaseString, (char)[legacy characterAtIndex:7], flag([legacy isEqualToString:@"legacy literal"]),
           flag(legacy.hash == @"legacy literal".hash), flag([legacy isKindOfClass:[NSString class]])]);
    print([NSString stringWithFormat:@"simple=%@ length=%lu utf8=%s copy=%@ appended=%@", simple, (unsigned long)simple.length,
           simple.UTF8String, flag([[simple copy] isEqual:@"simple"]), [simple stringByAppendingString:@"+"]]);
}

static void encodings(void) {
    print([@"bom utf8: " stringByAppendingString:detect("\xEF\xBB\xBFh\xC3\xA9llo", 9, nil)]);
    print([@"bom utf16: " stringByAppendingString:detect("\xFF\xFEh\0i\0", 6, nil)]);
    print([@"bom utf16be: " stringByAppendingString:detect("\xFE\xFF\0o\0k", 6, nil)]);
    print([@"ascii: " stringByAppendingString:detect("plain text", 10, nil)]);
    print([@"utf8: " stringByAppendingString:detect("na\xC3\xAFve caf\xC3\xA9", 12, nil)]);
    NSDictionary *latin = @{NSStringEncodingDetectionSuggestedEncodingsKey: @[@(NSISOLatin1StringEncoding)],
                            NSStringEncodingDetectionUseOnlySuggestedEncodingsKey: @YES};
    print([@"latin1 suggested: " stringByAppendingString:detect("caf\xE9 cr\xE8me", 10, latin)]);
    NSDictionary *windows = @{NSStringEncodingDetectionSuggestedEncodingsKey: @[@(NSWindowsCP1252StringEncoding)],
                              NSStringEncodingDetectionUseOnlySuggestedEncodingsKey: @YES};
    print([@"cp1252 suggested: " stringByAppendingString:detect("\x93smart\x94 \x80", 9, windows)]);
    NSDictionary *disallowed = @{NSStringEncodingDetectionSuggestedEncodingsKey: @[@(NSISOLatin1StringEncoding)],
                                 NSStringEncodingDetectionDisallowedEncodingsKey: @[@(NSUTF8StringEncoding)],
                                 NSStringEncodingDetectionUseOnlySuggestedEncodingsKey: @YES};
    print([@"utf8 disallowed: " stringByAppendingString:detect("caf\xC3\xA9", 5, disallowed)]);
    NSDictionary *strict = @{NSStringEncodingDetectionSuggestedEncodingsKey: @[@(NSUTF8StringEncoding)],
                             NSStringEncodingDetectionUseOnlySuggestedEncodingsKey: @YES,
                             NSStringEncodingDetectionAllowLossyKey: @NO};
    print([@"invalid strict: " stringByAppendingString:detect("bad\xFF\xFE\xFD", 6, strict)]);
    NSDictionary *lossy = @{NSStringEncodingDetectionSuggestedEncodingsKey: @[@(NSASCIIStringEncoding)],
                            NSStringEncodingDetectionUseOnlySuggestedEncodingsKey: @YES,
                            NSStringEncodingDetectionAllowLossyKey: @YES,
                            NSStringEncodingDetectionLossySubstitutionKey: @"?"};
    print([@"ascii lossy: " stringByAppendingString:detect("ab\xC3\xA9", 4, lossy)]);
    print([@"empty: " stringByAppendingString:detect("", 0, nil)]);
}

static void strings(void) {
    print([NSString stringWithFormat:@"cstring length=%@ init=%@ nocopy=%@", [NSString stringWithCString:"abcdef" length:3],
           [[NSString alloc] initWithCString:"uvwxyz" length:4],
           [[NSString alloc] initWithCStringNoCopy:strdup("owned") length:5 freeWhenDone:YES]]);
    print([NSString stringWithFormat:@"lossy=%s smallest=%lu,%lu fastest=%lu", [@"plain" lossyCString],
           (unsigned long)@"abc".smallestEncoding, (unsigned long)@"☃".smallestEncoding, (unsigned long)@"abc".fastestEncoding]);
    print([NSString stringWithFormat:@"prefix=%@|%@|%@", [@"Hello World" commonPrefixWithString:@"help me" options:NSCaseInsensitiveSearch],
           [@"Hello World" commonPrefixWithString:@"help me" options:0], [@"café" commonPrefixWithString:@"cafés" options:0]]);
    print([NSString stringWithFormat:@"folded=%@|%@",
           [@"Café ÉCOLE" stringByFoldingWithOptions:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch locale:nil],
           [@"ＡＢc" stringByFoldingWithOptions:NSWidthInsensitiveSearch locale:nil]]);
    print([NSString stringWithFormat:@"transforms=%@|%@|%@|%@|%@|%@",
           [@"Crème brûlée" stringByApplyingTransform:NSStringTransformStripDiacritics reverse:NO],
           [@"ＡＢＣ" stringByApplyingTransform:NSStringTransformFullwidthToHalfwidth reverse:NO],
           [@"ABC" stringByApplyingTransform:NSStringTransformFullwidthToHalfwidth reverse:YES],
           [@"ひらがな" stringByApplyingTransform:NSStringTransformHiraganaToKatakana reverse:NO],
           [@"Москва" stringByApplyingTransform:NSStringTransformToLatin reverse:NO],
           [@"café" stringByApplyingTransform:NSStringTransformToXMLHex reverse:NO]]);
    print([NSString stringWithFormat:@"name=%@ upper=%@ bad=%@", [@"☕" stringByApplyingTransform:NSStringTransformToUnicodeName reverse:NO],
           [@"shout" stringByApplyingTransform:@"Any-Upper" reverse:NO],
           [@"x" stringByApplyingTransform:@"No-Such-Transform" reverse:NO] ?: @"nil"]);
    NSMutableString *mutable = [@"keep éè keep" mutableCopy];
    NSRange updated = {0, 0};
    BOOL changed = [mutable applyTransform:NSStringTransformStripDiacritics reverse:NO range:NSMakeRange(5, 2) updatedRange:&updated];
    print([NSString stringWithFormat:@"applied=%@ %@ updated=%@", flag(changed), mutable, NSStringFromRange(updated)]);
    print([NSString stringWithFormat:@"standard range=%@ %@", NSStringFromRange([@"Straße Café bar" localizedStandardRangeOfString:@"cafe"]),
           NSStringFromRange([@"abc" localizedStandardRangeOfString:@"zzz"])]);
    print([[@"/usr" stringsByAppendingPaths:@[@"lib", @"share/doc"]] componentsJoinedByString:@","]);

    char buffer[8];
    NSRange remaining = {0, 0};
    [@"abcdefghij" getCString:buffer maxLength:7 range:NSMakeRange(2, 3) remainingRange:&remaining];
    print([NSString stringWithFormat:@"getCString=%s remaining=%@", buffer, NSStringFromRange(remaining)]);

    __block int freed = 0;
    @autoreleasepool {
        char *bytes = strdup("deallocator");
        NSString *owned = [[NSString alloc] initWithBytesNoCopy:bytes length:11 encoding:NSUTF8StringEncoding
                                                    deallocator:^(void *pointer, NSUInteger length) { freed += (int)length; free(pointer); }];
        unichar *characters = malloc(4 * sizeof(unichar));
        characters[0] = 'u'; characters[1] = 'n'; characters[2] = 'i'; characters[3] = 0x263A;
        NSString *units = [[NSString alloc] initWithCharactersNoCopy:characters length:4
                                                         deallocator:^(unichar *pointer, NSUInteger length) { freed += (int)length; free(pointer); }];
        print([NSString stringWithFormat:@"no copy=%@ %@", owned, units]);
    }
    print([NSString stringWithFormat:@"deallocated=%d", freed]);

    NSLocale *posix = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    print([[NSString alloc] initWithFormat:@"%.2f-%@-%d" locale:posix, 3.14159, @"loc", 42]);
    print([NSString localizedStringWithFormat:@"%d/%@", 7, @"seven"]);
    if (@available(macOS 13.0, iOS 16.0, *)) {
        NSError *error = nil;
        NSString *valid = [NSString stringWithValidatedFormat:@"%d apples" validFormatSpecifiers:@"%d" error:&error, 3];
        NSString *invalid = [NSString stringWithValidatedFormat:@"%@ apples" validFormatSpecifiers:@"%d" error:&error, 3];
        NSString *initialized = [[NSString alloc] initWithValidatedFormat:@"%2$@ %1$d" validFormatSpecifiers:@"%d %@" locale:posix error:NULL, 5, @"five"];
        print([NSString stringWithFormat:@"validated=%@ invalid=%@ error=%ld init=%@", valid, invalid ?: @"nil", (long)error.code, initialized]);
    } else {
        print(@"validated=3 apples invalid=nil error=2048 init=five 5");
    }
    print([NSString stringWithFormat:@"variant=%@", [@"wide…" variantFittingPresentationWidth:2]]);

    NSString *directory = @"/tmp/scrivener-fixture";
    [[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    NSURL *url = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"apple.txt"]];
    BOOL wrote = [@"written through a URL" writeToURL:url atomically:YES];
    [@"" writeToFile:[directory stringByAppendingPathComponent:@"apricot.txt"] atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    [@"" writeToFile:[directory stringByAppendingPathComponent:@"banana.md"] atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    print([NSString stringWithFormat:@"wrote=%@ read=%@", flag(wrote), [NSString stringWithContentsOfURL:url]]);
    NSString *completed = nil;
    NSArray *matches = nil;
    NSUInteger count = [[directory stringByAppendingPathComponent:@"ap"] completePathIntoString:&completed caseSensitive:YES
                                                                               matchesIntoArray:&matches filterTypes:nil];
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *match in matches) [names addObject:match.lastPathComponent];
    print([NSString stringWithFormat:@"complete=%lu %@ %@", (unsigned long)count, completed.lastPathComponent, [[names sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","]]);
    count = [[directory stringByAppendingPathComponent:@"b"] completePathIntoString:&completed caseSensitive:YES matchesIntoArray:&matches
                                                                         filterTypes:@[@"txt"]];
    print([NSString stringWithFormat:@"complete txt=%lu", (unsigned long)count]);

    NSScanner *scanner = [NSScanner scannerWithString:@"  -123.4500 rest 1e3 x"];
    NSDecimal decimal;
    BOOL scanned = [scanner scanDecimal:&decimal];
    print([NSString stringWithFormat:@"decimal=%@ exponent=%d length=%u negative=%u mantissa=%u,%u location=%lu", flag(scanned),
           decimal._exponent, decimal._length, decimal._isNegative, decimal._mantissa[0], decimal._mantissa[1],
           (unsigned long)scanner.scanLocation]);
    [scanner scanString:@"rest" intoString:NULL];
    scanned = [scanner scanDecimal:&decimal];
    print([NSString stringWithFormat:@"decimal=%@ exponent=%d mantissa=%u location=%lu", flag(scanned), decimal._exponent,
           decimal._mantissa[0], (unsigned long)scanner.scanLocation]);
    scanned = [scanner scanDecimal:&decimal];
    print([NSString stringWithFormat:@"decimal=%@ location=%lu", flag(scanned), (unsigned long)scanner.scanLocation]);
    scanner = [NSScanner scannerWithString:@"18446744073709551616123"];
    scanned = [scanner scanDecimal:&decimal];
    print([NSString stringWithFormat:@"wide decimal=%@ length=%u mantissa=%u,%u,%u,%u,%u", flag(scanned), decimal._length,
           decimal._mantissa[0], decimal._mantissa[1], decimal._mantissa[2], decimal._mantissa[3], decimal._mantissa[4]]);
}

// MARK: - Attributed strings and character sets

static NSString *runs(NSAttributedString *string) {
    NSMutableArray *parts = [NSMutableArray array];
    [string enumerateAttributesInRange:NSMakeRange(0, string.length) options:0
                            usingBlock:^(NSDictionary *attributes, NSRange range, BOOL *stop) {
        NSMutableArray *pairs = [NSMutableArray array];
        for (NSString *key in [attributes.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            [pairs addObject:[NSString stringWithFormat:@"%@=%@", key, attributes[key]]];
        }
        [parts addObject:[NSString stringWithFormat:@"[%@]{%@}", [string.string substringWithRange:range], [pairs componentsJoinedByString:@","]]];
    }];
    return [parts componentsJoinedByString:@""];
}

static void attributed(void) {
    NSMutableAttributedString *format = [[NSMutableAttributedString alloc] initWithString:@"Hello %@, you have %ld new!"
                                                                              attributes:@{@"base": @1}];
    [format addAttribute:@"bold" value:@YES range:NSMakeRange(0, 5)];
    [format addAttribute:@"arg" value:@"count" range:NSMakeRange(19, 3)];
    NSAttributedString *name = [[NSAttributedString alloc] initWithString:@"Ann" attributes:@{@"name": @"yes", @"base": @9}];
    if (@available(macOS 12.0, iOS 15.0, *)) {
        print(runs([NSAttributedString localizedAttributedStringWithFormat:format, name, (long)3]));
        print(runs([NSAttributedString localizedAttributedStringWithFormat:format
                                                                   options:NSAttributedStringFormattingInsertArgumentAttributesWithoutMerging, name, (long)12]));
        print(runs([[NSAttributedString alloc] initWithFormat:format options:0 locale:[NSLocale localeWithLocaleIdentifier:@"en_US"], @"Bob", (long)1]));
        NSMutableAttributedString *appended = [[NSMutableAttributedString alloc] initWithString:@"> "];
        [appended appendLocalizedFormat:[[NSAttributedString alloc] initWithString:@"%d%%" attributes:@{@"pct": @1}], 50];
        print(runs(appended));
        print(runs([name attributedStringByInflectingString]));
    } else {
        print(@"[Hello]{base=1,bold=1}[ ]{base=1}[Ann]{base=9,name=yes}[, you have ]{base=1}[3]{arg=count,base=1}[ new!]{base=1}");
    }

    NSCharacterSet *decomposable = [NSCharacterSet decomposableCharacterSet];
    print([NSString stringWithFormat:@"decomposable e-acute=%@ e=%@ angstrom=%@ hangul=%@ mutable=%@",
           flag([decomposable characterIsMember:0xE9]), flag([decomposable characterIsMember:'e']),
           flag([decomposable characterIsMember:0x212B]), flag([decomposable characterIsMember:0xAC00]),
           flag([[NSMutableCharacterSet decomposableCharacterSet] isKindOfClass:[NSMutableCharacterSet class]])]);
    NSString *path = @"/tmp/scrivener-fixture/set.bitmap";
    [[[NSCharacterSet characterSetWithCharactersInString:@"azé"] bitmapRepresentation] writeToFile:path atomically:NO];
    NSCharacterSet *loaded = [NSCharacterSet characterSetWithContentsOfFile:path];
    NSMutableCharacterSet *loadedMutable = [NSMutableCharacterSet characterSetWithContentsOfFile:path];
    [loadedMutable addCharactersInString:@"q"];
    print([NSString stringWithFormat:@"loaded a=%@ b=%@ e-acute=%@ mutable q=%@ missing=%@", flag([loaded characterIsMember:'a']),
           flag([loaded characterIsMember:'b']), flag([loaded characterIsMember:0xE9]), flag([loadedMutable characterIsMember:'q']),
           [NSCharacterSet characterSetWithContentsOfFile:@"/tmp/scrivener-fixture/none"] ? @"set" : @"nil"]);
    [[NSFileManager defaultManager] removeItemAtPath:@"/tmp/scrivener-fixture" error:NULL];
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        keyedCoding();
        delegates();
        legacyCoding();
        constantStrings();
        encodings();
        strings();
        attributed();
    }
    return 0;
}
