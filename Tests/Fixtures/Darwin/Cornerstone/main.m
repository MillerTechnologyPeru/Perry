// CoreFoundation in C: arrays, dictionaries and sets with CF's and custom
// callbacks, strings, numbers, data, dates, URLs, UUIDs, the main bundle,
// preferences, errors, character sets, and toll-free bridging both ways.

#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#include <stdio.h>

static void say(const char *format, ...) __attribute__((format(printf, 1, 2)));
static void say(const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    vprintf(format, arguments);
    va_end(arguments);
    printf("\n");
    fflush(stdout);
}

/// A CF string as UTF-8, for printing.
static const char *utf8(CFStringRef string) {
    static char buffers[16][1024];
    static int next = 0;
    char *buffer = buffers[next++ % 16];
    if (!string) return "(null)";
    if (!CFStringGetCString(string, buffer, sizeof(buffers[0]), kCFStringEncodingUTF8)) return "(too long)";
    return buffer;
}

/// A property list value, without addresses.
static const char *describe(CFTypeRef value) {
    static char buffers[8][128];
    static int next = 0;
    char *buffer = buffers[next++ % 8];
    if (!value) return "nil";
    if (CFGetTypeID(value) == CFStringGetTypeID()) return utf8(value);
    if (CFGetTypeID(value) == CFBooleanGetTypeID()) return CFBooleanGetValue(value) ? "true" : "false";
    if (CFGetTypeID(value) == CFNumberGetTypeID()) {
        long long number = 0;
        CFNumberGetValue(value, kCFNumberLongLongType, &number);
        snprintf(buffer, 128, "#%lld", number);
        return buffer;
    }
    return "?";
}

static int retains, releases;
static const void *countingRetain(CFAllocatorRef allocator, const void *value) {
    retains++;
    return value;
}
static void countingRelease(CFAllocatorRef allocator, const void *value) {
    releases++;
}
static Boolean integersEqual(const void *a, const void *b) {
    return (intptr_t)a == (intptr_t)b;
}
static CFHashCode integerHash(const void *value) {
    return (CFHashCode)(intptr_t)value;
}

static void sum(const void *value, void *context) {
    *(intptr_t *)context += (intptr_t)value;
}

static CFComparisonResult compareIntegers(const void *a, const void *b, void *context) {
    intptr_t x = (intptr_t)a, y = (intptr_t)b;
    return x < y ? kCFCompareLessThan : x > y ? kCFCompareGreaterThan : kCFCompareEqualTo;
}

static void printEntry(const void *key, const void *value, void *context) {
    char *out = context;
    char line[128];
    snprintf(line, sizeof(line), "%s%s=%s", out[0] ? "," : "", utf8(key), describe(value));
    strcat(out, line);
}

static void arrays(void) {
    CFStringRef values[] = {CFSTR("b"), CFSTR("a"), CFSTR("c")};
    CFArrayRef array = CFArrayCreate(NULL, (const void **)values, 3, &kCFTypeArrayCallBacks);
    say("array: count %ld, [1] %s, contains a %d z %d, index of c %ld, type %d, NSArray %d",
        (long)CFArrayGetCount(array), utf8(CFArrayGetValueAtIndex(array, 1)),
        CFArrayContainsValue(array, CFRangeMake(0, 3), CFSTR("a")), CFArrayContainsValue(array, CFRangeMake(0, 3), CFSTR("z")),
        (long)CFArrayGetFirstIndexOfValue(array, CFRangeMake(0, 3), CFSTR("c")), CFGetTypeID(array) == CFArrayGetTypeID(),
        [(__bridge id)array isKindOfClass:NSArray.class]);

    CFMutableArrayRef mutable = CFArrayCreateMutableCopy(NULL, 0, array);
    CFArrayAppendValue(mutable, CFSTR("d"));
    CFArrayInsertValueAtIndex(mutable, 0, CFSTR("start"));
    CFArrayRemoveValueAtIndex(mutable, 2);
    CFArraySetValueAtIndex(mutable, 1, CFSTR("B"));
    CFArrayExchangeValuesAtIndices(mutable, 0, 1);
    CFArraySortValues(mutable, CFRangeMake(0, CFArrayGetCount(mutable)), (CFComparatorFunction)CFStringCompare, NULL);
    CFArrayAppendArray(mutable, array, CFRangeMake(0, 2));
    say("mutable: %s", utf8(CFStringCreateByCombiningStrings(NULL, mutable, CFSTR(" "))));
    const void *fetched[2];
    CFArrayGetValues(mutable, CFRangeMake(1, 2), fetched);
    say("values: %s %s, last %ld", utf8(fetched[0]), utf8(fetched[1]),
        (long)CFArrayGetLastIndexOfValue(mutable, CFRangeMake(0, CFArrayGetCount(mutable)), CFSTR("b")));
    CFArrayRemoveAllValues(mutable);
    say("emptied: %ld", (long)CFArrayGetCount(mutable));

    // Integers, not objects, with callbacks of the program's own.
    CFArrayCallBacks callbacks = {0, countingRetain, countingRelease, NULL, integersEqual};
    CFMutableArrayRef numbers = CFArrayCreateMutable(NULL, 0, &callbacks);
    for (intptr_t i = 5; i >= 1; i--) CFArrayAppendValue(numbers, (const void *)i);
    CFArraySortValues(numbers, CFRangeMake(0, 5), compareIntegers, NULL);
    intptr_t total = 0;
    CFArrayApplyFunction(numbers, CFRangeMake(0, 5), sum, &total);
    say("integers: first %ld last %ld, sum %ld, index of 3 = %ld, retains %d", (long)(intptr_t)CFArrayGetValueAtIndex(numbers, 0),
        (long)(intptr_t)CFArrayGetValueAtIndex(numbers, 4), (long)total,
        (long)CFArrayGetFirstIndexOfValue(numbers, CFRangeMake(0, 5), (const void *)3), retains);
    CFArrayRemoveValueAtIndex(numbers, 0);
    CFRelease(numbers);
    say("released: %d", releases);
    CFArrayRef plain = CFArrayCreate(NULL, (const void *[]){(void *)7, (void *)8}, 2, NULL);
    say("no callbacks: %ld %ld", (long)(intptr_t)CFArrayGetValueAtIndex(plain, 0), (long)(intptr_t)CFArrayGetValueAtIndex(plain, 1));
    CFRelease(plain);
    CFRelease(mutable);
    CFRelease(array);
}

static void dictionaries(void) {
    CFStringRef keys[] = {CFSTR("one"), CFSTR("two")};
    int two = 2;
    CFNumberRef values[] = {CFNumberCreate(NULL, kCFNumberIntType, &(int){1}), CFNumberCreate(NULL, kCFNumberIntType, &two)};
    CFDictionaryRef dictionary = CFDictionaryCreate(NULL, (const void **)keys, (const void **)values, 2,
                                                    &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    const void *found = NULL;
    Boolean present = CFDictionaryGetValueIfPresent(dictionary, CFSTR("two"), &found);
    say("dictionary: count %ld, one %s, two present %d %s, three %p, contains key %d value %d, NSDictionary %d",
        (long)CFDictionaryGetCount(dictionary), describe(CFDictionaryGetValue(dictionary, CFSTR("one"))), present,
        describe(found), CFDictionaryGetValue(dictionary, CFSTR("three")),
        CFDictionaryContainsKey(dictionary, CFSTR("one")), CFDictionaryContainsValue(dictionary, values[1]),
        [(__bridge id)dictionary isKindOfClass:NSDictionary.class]);

    CFMutableDictionaryRef mutable = CFDictionaryCreateMutableCopy(NULL, 0, dictionary);
    CFDictionaryAddValue(mutable, CFSTR("one"), CFSTR("ignored"));
    CFDictionarySetValue(mutable, CFSTR("three"), CFSTR("3"));
    CFDictionaryReplaceValue(mutable, CFSTR("two"), CFSTR("II"));
    CFDictionaryReplaceValue(mutable, CFSTR("four"), CFSTR("ignored"));
    CFDictionaryRemoveValue(mutable, CFSTR("one"));
    CFDictionarySetValue(mutable, CFSTR("zero"), kCFBooleanFalse);
    char out[512] = "";
    NSArray *sortedKeys = [[(__bridge NSDictionary *)mutable allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *key in sortedKeys) printEntry((__bridge CFStringRef)key, CFDictionaryGetValue(mutable, (__bridge CFStringRef)key), out);
    say("mutable: %s, count of II %ld", out, (long)CFDictionaryGetCountOfValue(mutable, CFSTR("II")));
    CFIndex count = CFDictionaryGetCount(mutable);
    const void *allKeys[8], *allValues[8];
    CFDictionaryGetKeysAndValues(mutable, allKeys, allValues);
    int matched = 0;
    for (CFIndex i = 0; i < count; i++) matched += CFEqual(CFDictionaryGetValue(mutable, allKeys[i]), allValues[i]);
    say("keys and values: %d of %ld match", matched, (long)count);

    // Integer keys with no callbacks.
    CFMutableDictionaryRef raw = CFDictionaryCreateMutable(NULL, 0, NULL, NULL);
    CFDictionarySetValue(raw, (const void *)1, (const void *)100);
    CFDictionarySetValue(raw, (const void *)2, (const void *)200);
    CFDictionarySetValue(raw, (const void *)1, (const void *)111);
    say("raw: count %ld, 1 -> %ld, 2 -> %ld, 3 present %d", (long)CFDictionaryGetCount(raw),
        (long)(intptr_t)CFDictionaryGetValue(raw, (const void *)1), (long)(intptr_t)CFDictionaryGetValue(raw, (const void *)2),
        CFDictionaryContainsKey(raw, (const void *)3));
    CFRelease(raw);

    CFSetCallBacks setCallbacks = {0, NULL, NULL, NULL, integersEqual, integerHash};
    CFMutableSetRef set = CFSetCreateMutable(NULL, 0, &setCallbacks);
    CFSetAddValue(set, (const void *)4);
    CFSetAddValue(set, (const void *)4);
    CFSetAddValue(set, (const void *)9);
    say("set: count %ld, has 9 %d, has 5 %d", (long)CFSetGetCount(set), CFSetContainsValue(set, (const void *)9),
        CFSetContainsValue(set, (const void *)5));
    CFSetRemoveValue(set, (const void *)9);
    say("set removed: %ld", (long)CFSetGetCount(set));
    CFRelease(set);
    CFSetRef strings = CFSetCreate(NULL, (const void **)keys, 2, &kCFTypeSetCallBacks);
    say("string set: %ld, has two %d, NSSet %d", (long)CFSetGetCount(strings), CFSetContainsValue(strings, CFSTR("two")),
        [(__bridge id)strings isKindOfClass:NSSet.class]);
    CFRelease(strings);
    CFRelease(mutable);
    CFRelease(dictionary);
}

static void strings(void) {
    CFStringRef string = CFStringCreateWithCString(NULL, "Hello, World", kCFStringEncodingUTF8);
    CFStringRef formatted = CFStringCreateWithFormat(NULL, NULL, CFSTR("%@ #%d %.2f %s"), string, 7, 3.14159, "c");
    say("format: %s", utf8(formatted));
    say("compare: %ld %ld %ld, insensitive %ld", (long)CFStringCompare(CFSTR("a"), CFSTR("b"), 0),
        (long)CFStringCompare(CFSTR("b"), CFSTR("a"), 0), (long)CFStringCompare(CFSTR("a"), CFSTR("a"), 0),
        (long)CFStringCompare(CFSTR("ABC"), CFSTR("abc"), kCFCompareCaseInsensitive));
    CFRange found = CFStringFind(string, CFSTR("World"), 0);
    CFRange missing = CFStringFind(string, CFSTR("xyz"), 0);
    say("find: %ld %ld, missing %ld %ld, prefix %d suffix %d", (long)found.location, (long)found.length,
        (long)missing.location, (long)missing.length, CFStringHasPrefix(string, CFSTR("Hello")), CFStringHasSuffix(string, CFSTR("x")));
    CFStringRef part = CFStringCreateWithSubstring(NULL, string, CFRangeMake(7, 5));
    say("substring: %s, char %c, length %ld", utf8(part), (char)CFStringGetCharacterAtIndex(string, 4), (long)CFStringGetLength(string));
    CFMutableStringRef mutable = CFStringCreateMutableCopy(NULL, 0, string);
    CFStringAppend(mutable, CFSTR("!"));
    CFStringAppendCString(mutable, " ok", kCFStringEncodingUTF8);
    CFStringInsert(mutable, 0, CFSTR(">> "));
    CFStringUppercase(mutable, NULL);
    CFStringReplaceAll(mutable, CFStringCreateWithFormat(NULL, NULL, CFSTR("%@ [%ld]"), CFStringCreateCopy(NULL, mutable), (long)CFStringGetLength(mutable)));
    say("mutable: %s", utf8(mutable));
    CFStringLowercase(mutable, NULL);
    CFStringFindAndReplace(mutable, CFSTR("o"), CFSTR("0"), CFRangeMake(0, CFStringGetLength(mutable)), 0);
    CFStringDelete(mutable, CFRangeMake(0, 3));
    say("lower: %s", utf8(mutable));
    CFArrayRef pieces = CFStringCreateArrayBySeparatingStrings(NULL, CFSTR("a,b,,c"), CFSTR(","));
    say("separated: %ld, joined %s", (long)CFArrayGetCount(pieces), utf8(CFStringCreateByCombiningStrings(NULL, pieces, CFSTR("|"))));
    say("numbers: %d %.3f", (int)CFStringGetIntValue(CFSTR("  42abc")), CFStringGetDoubleValue(CFSTR("2.5e2")));
    UInt8 bytes[] = {0x63, 0x61, 0x66, 0xc3, 0xa9};
    CFStringRef cafe = CFStringCreateWithBytes(NULL, bytes, 5, kCFStringEncodingUTF8, false);
    UniChar characters[8];
    CFStringGetCharacters(cafe, CFRangeMake(0, 4), characters);
    UInt8 latin[8];
    CFIndex used = 0;
    CFIndex converted = CFStringGetBytes(cafe, CFRangeMake(0, 4), kCFStringEncodingISOLatin1, '?', false, latin, sizeof(latin), &used);
    say("bytes: %s length %ld, last char %04x, latin1 %ld chars %ld bytes last %02x, max %ld", utf8(cafe), (long)CFStringGetLength(cafe),
        characters[3], (long)converted, (long)used, latin[3],
        (long)CFStringGetMaximumSizeForEncoding(4, kCFStringEncodingUTF8));
    CFDataRef data = CFStringCreateExternalRepresentation(NULL, cafe, kCFStringEncodingUTF8, 0);
    CFStringRef back = CFStringCreateFromExternalRepresentation(NULL, data, kCFStringEncodingUTF8);
    say("external: %ld bytes, equal %d, NSString %d, bridged length %lu", (long)CFDataGetLength(data), CFEqual(back, cafe),
        [(__bridge id)cafe isKindOfClass:NSString.class], (unsigned long)[(__bridge NSString *)cafe length]);
    CFStringRef escaped = CFURLCreateStringByAddingPercentEscapes(NULL, CFSTR("a b&c=d/é"), NULL, CFSTR("&="), kCFStringEncodingUTF8);
    CFStringRef unescaped = CFURLCreateStringByReplacingPercentEscapesUsingEncoding(NULL, escaped, CFSTR(""), kCFStringEncodingUTF8);
    say("escapes: %s -> %s", utf8(escaped), utf8(unescaped));
    say("type: %d, encoding name %s, system UTF-8 %d", CFGetTypeID(string) == CFStringGetTypeID(),
        utf8(CFStringGetNameOfEncoding(kCFStringEncodingUTF8)), CFStringGetSystemEncoding() == kCFStringEncodingMacRoman);
}

static void values(void) {
    double pi = 3.25;
    long long big = 1LL << 40;
    CFNumberRef real = CFNumberCreate(NULL, kCFNumberDoubleType, &pi);
    CFNumberRef integer = CFNumberCreate(NULL, kCFNumberLongLongType, &big);
    int asInt = 0;
    double asDouble = 0;
    Boolean exact = CFNumberGetValue(real, kCFNumberIntType, &asInt);
    CFNumberGetValue(integer, kCFNumberDoubleType, &asDouble);
    say("numbers: int %d exact %d, double %.0f, float %d %d, compare %ld, type %d, bool %d %d, NSNumber %d",
        asInt, exact, asDouble, CFNumberIsFloatType(real), CFNumberIsFloatType(integer), (long)CFNumberCompare(real, integer, NULL),
        CFGetTypeID(real) == CFNumberGetTypeID(), CFBooleanGetValue(kCFBooleanTrue), CFGetTypeID(kCFBooleanTrue) == CFBooleanGetTypeID(),
        [(__bridge id)real isKindOfClass:NSNumber.class]);
    say("number types: %ld %ld", (long)CFNumberGetType(real), (long)CFNumberGetByteSize(integer));

    UInt8 raw[] = {1, 2, 3};
    CFDataRef data = CFDataCreate(NULL, raw, 3);
    CFMutableDataRef mutable = CFDataCreateMutableCopy(NULL, 0, data);
    CFDataAppendBytes(mutable, (UInt8[]){4, 5}, 2);
    CFDataReplaceBytes(mutable, CFRangeMake(0, 1), (UInt8[]){9, 9}, 2);
    CFDataDeleteBytes(mutable, CFRangeMake(4, 1));
    UInt8 copied[8] = {0};
    CFDataGetBytes(mutable, CFRangeMake(0, CFDataGetLength(mutable)), copied);
    CFDataSetLength(mutable, 7);
    say("data: %ld, first %d, mutable %d %d %d %d %d, now %ld, NSData %d", (long)CFDataGetLength(data), CFDataGetBytePtr(data)[0],
        copied[0], copied[1], copied[2], copied[3], copied[4], (long)CFDataGetLength(mutable), [(__bridge id)data isKindOfClass:NSData.class]);

    CFDateRef date = CFDateCreate(NULL, 700000000);
    CFDateRef later = CFDateCreate(NULL, 700000060);
    say("dates: %.0f, compare %ld, interval %.0f, NSDate %d, epoch %.0f", CFDateGetAbsoluteTime(date), (long)CFDateCompare(date, later, NULL),
        CFDateGetTimeIntervalSinceDate(later, date), [(__bridge id)date isKindOfClass:NSDate.class], kCFAbsoluteTimeIntervalSince1970);

    say("null: %d", CFGetTypeID(kCFNull) == CFNullGetTypeID());

    CFURLRef url = CFURLCreateWithString(NULL, CFSTR("https://user@example.com:8443/a/b/file.tar.gz?q=1#frag"), NULL);
    say("url: %s host %s port %ld path %s last %s ext %s query %s fragment %s scheme %s user %s",
        utf8(CFURLGetString(url)), utf8(CFURLCopyHostName(url)), (long)CFURLGetPortNumber(url), utf8(CFURLCopyPath(url)),
        utf8(CFURLCopyLastPathComponent(url)), utf8(CFURLCopyPathExtension(url)), utf8(CFURLCopyQueryString(url, NULL)),
        utf8(CFURLCopyFragment(url, NULL)), utf8(CFURLCopyScheme(url)), utf8(CFURLCopyUserName(url)));
    CFURLRef file = CFURLCreateWithFileSystemPath(NULL, CFSTR("/tmp/some dir/x.txt"), kCFURLPOSIXPathStyle, false);
    char path[256];
    CFURLGetFileSystemRepresentation(file, true, (UInt8 *)path, sizeof(path));
    CFURLRef parent = CFURLCreateCopyDeletingLastPathComponent(NULL, file);
    CFURLRef child = CFURLCreateCopyAppendingPathComponent(NULL, parent, CFSTR("y.md"), false);
    CFURLRef relative = CFURLCreateWithString(NULL, CFSTR("../c"), url);
    say("file: %s, path %s, fs %s, parent %s, child %s, relative %s, absolute %s, NSURL %d", utf8(CFURLGetString(file)),
        utf8(CFURLCopyFileSystemPath(file, kCFURLPOSIXPathStyle)), path, utf8(CFURLGetString(parent)), utf8(CFURLGetString(child)),
        utf8(CFURLGetString(relative)), utf8(CFURLGetString(CFURLCopyAbsoluteURL(relative))), [(__bridge id)url isKindOfClass:NSURL.class]);

    CFUUIDRef uuid = CFUUIDCreateFromString(NULL, CFSTR("E621E1F8-C36C-495A-93FC-0C247A3E6E5F"));
    CFUUIDBytes uuidBytes = CFUUIDGetUUIDBytes(uuid);
    CFUUIDRef same = CFUUIDCreateFromUUIDBytes(NULL, uuidBytes);
    CFUUIDRef fresh = CFUUIDCreate(NULL);
    say("uuid: %s, bytes %02x %02x, equal %d, fresh length %ld, differs %d, type %d", utf8(CFUUIDCreateString(NULL, uuid)),
        uuidBytes.byte0, uuidBytes.byte15, CFEqual(uuid, same), (long)CFStringGetLength(CFUUIDCreateString(NULL, fresh)),
        !CFEqual(uuid, fresh), CFGetTypeID(uuid) == CFUUIDGetTypeID());
}

static void environment(void) {
    CFBundleRef bundle = CFBundleGetMainBundle();
    CFURLRef resource = CFBundleCopyResourceURL(bundle, CFSTR("note"), CFSTR("txt"), NULL);
    CFStringRef name = CFURLCopyLastPathComponent(resource);
    CFDictionaryRef info = CFBundleGetInfoDictionary(bundle);
    say("bundle: %s, greeting %s, executable %s, resource %s, missing %p, info has version %d, same %d",
        utf8(CFBundleGetIdentifier(bundle)), utf8(CFBundleGetValueForInfoDictionaryKey(bundle, CFSTR("PerryGreeting"))),
        utf8(CFBundleGetValueForInfoDictionaryKey(bundle, kCFBundleExecutableKey)), utf8(name),
        CFBundleCopyResourceURL(bundle, CFSTR("absent"), CFSTR("txt"), NULL), CFDictionaryContainsKey(info, kCFBundleVersionKey),
        CFBundleGetBundleWithIdentifier(CFSTR("org.perry.fixture.cornerstone")) == bundle);

    CFStringRef key = CFSTR("CornerstoneCount");
    CFPreferencesSetAppValue(key, (__bridge CFNumberRef)@41, kCFPreferencesCurrentApplication);
    Boolean valid = false;
    CFIndex value = CFPreferencesGetAppIntegerValue(key, kCFPreferencesCurrentApplication, &valid);
    CFPreferencesSetAppValue(CFSTR("CornerstoneFlag"), kCFBooleanTrue, kCFPreferencesCurrentApplication);
    Boolean flag = CFPreferencesGetAppBooleanValue(CFSTR("CornerstoneFlag"), kCFPreferencesCurrentApplication, NULL);
    CFPropertyListRef copied = CFPreferencesCopyAppValue(key, kCFPreferencesCurrentApplication);
    say("preferences: %ld valid %d, flag %d, copied %s, defaults %ld, synchronized %d", (long)value, valid, flag,
        describe(copied), (long)[NSUserDefaults.standardUserDefaults integerForKey:@"CornerstoneCount"],
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication));
    CFPreferencesSetAppValue(key, NULL, kCFPreferencesCurrentApplication);
    CFPreferencesSetAppValue(CFSTR("CornerstoneFlag"), NULL, kCFPreferencesCurrentApplication);
    say("removed: %p", CFPreferencesCopyAppValue(key, kCFPreferencesCurrentApplication));

    CFErrorRef error = CFErrorCreate(NULL, kCFErrorDomainPOSIX, 2, NULL);
    say("error: %s %ld, NSError %d, %s", utf8(CFErrorGetDomain(error)), (long)CFErrorGetCode(error),
        [(__bridge id)error isKindOfClass:NSError.class], utf8(CFErrorCopyDescription(error)));

    CFCharacterSetRef digits = CFCharacterSetGetPredefined(kCFCharacterSetDecimalDigit);
    CFCharacterSetRef vowels = CFCharacterSetCreateWithCharactersInString(NULL, CFSTR("aeiou"));
    say("character sets: %d %d, %d %d", CFCharacterSetIsCharacterMember(digits, '7'), CFCharacterSetIsCharacterMember(digits, 'x'),
        CFCharacterSetIsCharacterMember(vowels, 'e'), CFCharacterSetIsCharacterMember(vowels, 'z'));

    CFTimeZoneRef zone = CFTimeZoneCreateWithName(NULL, CFSTR("America/New_York"), true);
    CFLocaleRef locale = CFLocaleCreate(NULL, CFSTR("fr_FR"));
    say("zone: %s offset %.0f, locale %s, currency %s", utf8(CFTimeZoneGetName(zone)), CFTimeZoneGetSecondsFromGMT(zone, 700000000),
        utf8(CFLocaleGetIdentifier(locale)), utf8(CFLocaleGetValue(locale, kCFLocaleCurrencyCode)));

    // Bridging transfers.
    NSString *made = @"bridge";
    CFStringRef retained = (__bridge_retained CFStringRef)[made mutableCopy];
    NSString *back = CFBridgingRelease(retained);
    CFTypeRef autoreleased = CFAutorelease(CFStringCreateCopy(NULL, CFSTR("auto")));
    say("bridging: %s, %s, retain count positive %d", back.UTF8String, utf8(autoreleased), CFGetRetainCount(autoreleased) > 0);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        arrays();
        dictionaries();
        strings();
        values();
        environment();
    }
    return 0;
}
