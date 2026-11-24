// CoreFoundation's functions and constants that Perry was missing, a few
// of each family, built on a Mac with Xcode. Only what is the same on any
// machine is printed: no paths, names or times of this one.
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <unistd.h>

// Private on Darwin, as Swift's open-source CoreFoundation declares them.
extern CFStringRef CFCopyUserName(void);
extern CFStringRef CFCopySystemVersionString(void);
extern CFTimeInterval CFGetSystemUptime(void);
extern void CFQSortArray(void *list, CFIndex count, CFIndex elementSize, CFComparatorFunction comparator, void *context);
extern void CFMergeSortArray(void *list, CFIndex count, CFIndex elementSize, CFComparatorFunction comparator, void *context);
extern void CFSortIndexes(CFIndex *indexBuffer, CFIndex count, CFOptionFlags opts, CFComparisonResult (^cmp)(CFIndex, CFIndex));
extern Boolean CFCharacterSetIsSurrogatePairMember(CFCharacterSetRef theSet, UniChar surrogateHigh, UniChar surrogateLow);
extern CFTypeID CFTypeGetTypeID(void);
extern CFReadStreamRef CFReadStreamCreateWithData(CFAllocatorRef alloc, CFDataRef data);
extern const CFStringRef kCFLocaleCurrencyCodeKey, kCFCalendarIdentifierHebrew, kCFNumberFormatterCurrencyCodeKey;

static void print(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static NSString *range(CFRange range) { return [NSString stringWithFormat:@"{%ld, %ld}", (long)range.location, (long)range.length]; }

static CFComparisonResult compareInts(const void *a, const void *b, void *context) {
    int x = *(const int *)a, y = *(const int *)b;
    return x < y ? kCFCompareLessThan : x > y ? kCFCompareGreaterThan : kCFCompareEqualTo;
}

static void miscellaneous(void) {
    // iOS's, and macOS's under another declaration.
    CFURLRef (*copyHome)(void) = dlsym(RTLD_DEFAULT, "CFCopyHomeDirectoryURL");
    CFURLRef home = copyHome ? copyHome() : NULL;
    CFStringRef user = CFCopyUserName();
    CFStringRef version = CFCopySystemVersionString();
    print([NSString stringWithFormat:@"home %d user %d version %d uptime %d", home != NULL, user && CFStringGetLength(user) > 0,
           version != NULL, CFGetSystemUptime() > 0]);
    int numbers[] = {5, 3, 9, 1, 7};
    CFQSortArray(numbers, 5, sizeof(int), compareInts, NULL);
    int merged[] = {4, 4, 2, 8, 6};
    CFMergeSortArray(merged, 5, sizeof(int), compareInts, NULL);
    print([NSString stringWithFormat:@"sorted %d %d %d %d %d merged %d %d %d %d %d", numbers[0], numbers[1], numbers[2], numbers[3],
           numbers[4], merged[0], merged[1], merged[2], merged[3], merged[4]]);
    CFIndex indexes[] = {0, 1, 2, 3};
    const char *letters = "dbca";
    CFSortIndexes(indexes, 4, 0, ^CFComparisonResult(CFIndex a, CFIndex b) {
        return letters[a] < letters[b] ? kCFCompareLessThan : letters[a] > letters[b] ? kCFCompareGreaterThan : kCFCompareEqualTo;
    });
    print([NSString stringWithFormat:@"indexes %ld %ld %ld %ld", (long)indexes[0], (long)indexes[1], (long)indexes[2], (long)indexes[3]]);

    CFSetRef set = CFSetCreate(NULL, (const void *[]){CFSTR("a"), CFSTR("b")}, 2, &kCFTypeSetCallBacks);
    const void *found = NULL;
    Boolean present = CFSetGetValueIfPresent(set, CFSTR("b"), &found);
    print([NSString stringWithFormat:@"set %d %@ missing %d", present, (__bridge NSString *)found, CFSetGetValueIfPresent(set, CFSTR("z"), &found)]);

    CFUUIDRef uuid = CFUUIDCreateWithBytes(NULL, 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0, 0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF);
    print([NSString stringWithFormat:@"uuid %@", CFBridgingRelease(CFUUIDCreateString(NULL, uuid))]);
    CFDataRef haystack = CFDataCreate(NULL, (const UInt8 *)"abcabcabc", 9);
    CFDataRef needle = CFDataCreate(NULL, (const UInt8 *)"cab", 3);
    print([NSString stringWithFormat:@"find %@ backwards %@ anchored %@", range(CFDataFind(haystack, needle, CFRangeMake(0, 9), 0)),
           range(CFDataFind(haystack, needle, CFRangeMake(0, 9), kCFDataSearchBackwards)),
           range(CFDataFind(haystack, needle, CFRangeMake(0, 9), kCFDataSearchAnchored))]);
    CFCharacterSetRef letters2 = CFCharacterSetGetPredefined(kCFCharacterSetLetter);
    CFCharacterSetRef copy = CFCharacterSetCreateCopy(NULL, letters2);
    print([NSString stringWithFormat:@"set copy %d %d surrogate %d", CFCharacterSetIsCharacterMember(copy, 'q'),
           CFCharacterSetIsCharacterMember(copy, '1'), CFCharacterSetIsSurrogatePairMember(letters2, 0xD835, 0xDC00)]);
    print([NSString stringWithFormat:@"type ids %lu %lu %lu", (unsigned long)CFTypeGetTypeID(), (unsigned long)CFAllocatorGetTypeID(),
           (unsigned long)CFNotificationCenterGetTypeID()]);
    CFErrorRef error = CFErrorCreateWithUserInfoKeysAndValues(NULL, kCFErrorDomainPOSIX, 2, (const void *[]){kCFErrorLocalizedRecoverySuggestionKey},
                                                              (const void *[]){CFSTR("Try again")}, 1);
    print([NSString stringWithFormat:@"error %ld %@", (long)CFErrorGetCode(error), CFBridgingRelease(CFErrorCopyRecoverySuggestion(error))]);
    CFPropertyListRef plist = (__bridge CFPropertyListRef)@{@"name": @"Perry", @"list": @[@1, @2]};
    print([NSString stringWithFormat:@"plist valid %d %d", CFPropertyListIsValid(plist, kCFPropertyListXMLFormat_v1_0),
           CFPropertyListIsValid((__bridge CFPropertyListRef)@{@1: @2}, kCFPropertyListXMLFormat_v1_0)]);
    void *bytes = CFAllocatorAllocate(NULL, 16, 0);
    print([NSString stringWithFormat:@"allocated %d", bytes != NULL]);
    CFAllocatorDeallocate(NULL, bytes);
}

static void strings(void) {
    unsigned char name[] = {5, 'P', 'e', 'r', 'r', 'y'};
    CFStringRef fromPascal = CFStringCreateWithPascalString(NULL, name, kCFStringEncodingMacRoman);
    CFMutableStringRef mutable = CFStringCreateMutableCopy(NULL, 0, fromPascal);
    unsigned char suffix[] = {3, ' ', 'O', 'S'};
    CFStringAppendPascalString(mutable, suffix, kCFStringEncodingMacRoman);
    print([NSString stringWithFormat:@"pascal [%@] [%@]", fromPascal, mutable]);
    CFStringRef text = CFSTR("one, two, one, three");
    CFArrayRef finds = CFStringCreateArrayWithFindResults(NULL, text, CFSTR("one"), CFRangeMake(0, CFStringGetLength(text)), 0);
    NSMutableArray *ranges = [NSMutableArray array];
    for (CFIndex i = 0; i < CFArrayGetCount(finds); i++) {
        [ranges addObject:range(*(const CFRange *)CFArrayGetValueAtIndex(finds, i))];
    }
    CFRange at;
    Boolean digit = CFStringFindCharacterFromSet(CFSTR("abc123"), CFCharacterSetGetPredefined(kCFCharacterSetDecimalDigit), CFRangeMake(0, 6), 0, &at);
    print([NSString stringWithFormat:@"finds %@ digit %d %@", [ranges componentsJoinedByString:@" "], digit, range(at)]);
    CFMutableStringRef folded = CFStringCreateMutableCopy(NULL, 0, CFSTR("Ünïcödé"));
    CFStringFold(folded, kCFCompareCaseInsensitive | kCFCompareDiacriticInsensitive, NULL);
    CFMutableStringRef normalized = CFStringCreateMutableCopy(NULL, 0, CFSTR("é"));
    CFStringNormalize(normalized, kCFStringNormalizationFormC);
    print([NSString stringWithFormat:@"folded [%@] normalized %ld", folded, (long)CFStringGetLength(normalized)]);
    CFIndex start, end, contents;
    CFStringGetLineBounds(CFSTR("ab\ncd\nef"), CFRangeMake(4, 0), &start, &end, &contents);
    print([NSString stringWithFormat:@"line %ld %ld %ld composed %@", (long)start, (long)end, (long)contents,
           range(CFStringGetRangeOfComposedCharactersAtIndex(CFSTR("aéz"), 1))]);
    print([NSString stringWithFormat:@"mac encoding %u", (unsigned)CFStringGetMostCompatibleMacStringEncoding(kCFStringEncodingISOLatin1)]);
}

static void locales(void) {
    CFArrayRef countries = CFLocaleCopyISOCountryCodes();
    CFArrayRef languages = CFLocaleCopyISOLanguageCodes();
    print([NSString stringWithFormat:@"countries has US %d languages has fr %d", CFArrayContainsValue(countries, CFRangeMake(0, CFArrayGetCount(countries)), CFSTR("US")),
           CFArrayContainsValue(languages, CFRangeMake(0, CFArrayGetCount(languages)), CFSTR("fr"))]);
    CFLocaleRef english = CFLocaleCreate(NULL, CFSTR("en_US"));
    print([NSString stringWithFormat:@"display %@ %@ canonical %@ direction %ld %ld", CFBridgingRelease(CFLocaleCopyDisplayNameForPropertyValue(english, kCFLocaleLanguageCode, CFSTR("fr"))),
           CFBridgingRelease(CFLocaleCopyDisplayNameForPropertyValue(english, kCFLocaleCountryCode, CFSTR("JP"))),
           CFBridgingRelease(CFLocaleCreateCanonicalLocaleIdentifierFromString(NULL, CFSTR("en-us"))),
           (long)CFLocaleGetLanguageCharacterDirection(CFSTR("ar")), (long)CFLocaleGetLanguageCharacterDirection(CFSTR("en"))]);
    CFTimeZoneRef tokyo = CFTimeZoneCreateWithName(NULL, CFSTR("Asia/Tokyo"), true);
    CFArrayRef names = CFTimeZoneCopyKnownNames();
    print([NSString stringWithFormat:@"zone abbreviation %@ known has Tokyo %d", CFBridgingRelease(CFTimeZoneCopyAbbreviation(tokyo, 0)),
           CFArrayContainsValue(names, CFRangeMake(0, CFArrayGetCount(names)), CFSTR("Asia/Tokyo"))]);
    CFMutableAttributedStringRef attributed = CFAttributedStringCreateMutable(NULL, 0);
    CFAttributedStringReplaceString(attributed, CFRangeMake(0, 0), CFSTR("Hello world"));
    CFAttributedStringSetAttribute(attributed, CFRangeMake(0, 5), CFSTR("bold"), kCFBooleanTrue);
    CFRange effective;
    CFTypeRef bold = CFAttributedStringGetAttribute(attributed, 2, CFSTR("bold"), &effective);
    CFAttributedStringRef sub = CFAttributedStringCreateWithSubstring(NULL, attributed, CFRangeMake(3, 5));
    print([NSString stringWithFormat:@"attributed %d %@ sub [%@] %ld type %d", bold == kCFBooleanTrue, range(effective), CFAttributedStringGetString(sub),
           (long)CFAttributedStringGetLength(sub), CFGetTypeID(attributed) == CFAttributedStringGetTypeID()]);
}

static void dates(void) {
    CFCalendarRef calendar = CFCalendarCreateWithIdentifier(NULL, kCFGregorianCalendar);
    CFTimeZoneRef utc = CFTimeZoneCreateWithName(NULL, CFSTR("UTC"), true);
    CFCalendarSetTimeZone(calendar, utc);
    CFAbsoluteTime at = 0;
    CFCalendarComposeAbsoluteTime(calendar, &at, "yMdHms", 2024, 2, 28, 12, 0, 0);
    CFAbsoluteTime later = at;
    CFCalendarAddComponents(calendar, &later, 0, "dH", 2, 3);
    int year, month, day, hour;
    CFCalendarDecomposeAbsoluteTime(calendar, later, "yMdH", &year, &month, &day, &hour);
    int days = 0;
    CFCalendarGetComponentDifference(calendar, at, later, 0, "d", &days);
    print([NSString stringWithFormat:@"added %d-%02d-%02d %02d difference %d days", year, month, day, hour, days]);
    CFRange dayRange = CFCalendarGetRangeOfUnit(calendar, kCFCalendarUnitDay, kCFCalendarUnitMonth, at);
    CFRange maximum = CFCalendarGetMaximumRangeOfUnit(calendar, kCFCalendarUnitDay);
    print([NSString stringWithFormat:@"days in February %@ maximum %@ ordinality %ld first week %ld", range(dayRange), range(maximum),
           (long)CFCalendarGetOrdinalityOfUnit(calendar, kCFCalendarUnitDay, kCFCalendarUnitYear, at), (long)CFCalendarGetMinimumDaysInFirstWeek(calendar)]);
    CFAbsoluteTime startOfMonth;
    CFTimeInterval length;
    Boolean ok = CFCalendarGetTimeRangeOfUnit(calendar, kCFCalendarUnitMonth, at, &startOfMonth, &length);
    print([NSString stringWithFormat:@"month %d starts %.0f lasts %.0f", ok, startOfMonth, length]);
    CFGregorianDate gregorian = {2024, 2, 30, 0, 0, 0};
    print([NSString stringWithFormat:@"gregorian valid %d %d", CFGregorianDateIsValid(gregorian, kCFGregorianAllUnits),
           CFGregorianDateIsValid((CFGregorianDate){2024, 2, 29, 0, 0, 0}, kCFGregorianAllUnits)]);
    print([NSString stringWithFormat:@"day of year %d week %d", (int)CFAbsoluteTimeGetDayOfYear(at, utc), (int)CFAbsoluteTimeGetWeekOfYear(at, utc)]);
}

static void urls(void) {
    CFURLRef url = CFURLCreateWithString(NULL, CFSTR("https://user:pw@example.com:8080/a/b;p=1?q=2#f"), NULL);
    print([NSString stringWithFormat:@"net %@ parameter %@ specifier %@ decomposable %d", CFBridgingRelease(CFURLCopyNetLocation(url)),
           CFBridgingRelease(CFURLCopyParameterString(url, NULL)), CFBridgingRelease(CFURLCopyResourceSpecifier(url)), CFURLCanBeDecomposed(url)]);
    CFRange separators;
    CFRange host = CFURLGetByteRangeForComponent(url, kCFURLComponentHost, &separators);
    UInt8 buffer[128];
    CFIndex length = CFURLGetBytes(url, buffer, sizeof buffer);
    print([NSString stringWithFormat:@"host %@ separators %@ bytes %ld", range(host), range(separators), (long)length]);
    char directory[] = "/tmp/perry-inventory-XXXXXX";
    mkdtemp(directory);
    NSString *file = [NSString stringWithFormat:@"%s/file.txt", directory];
    [@"twelve bytes" writeToFile:file atomically:NO encoding:NSUTF8StringEncoding error:nil];
    CFURLRef fileURL = CFURLCreateWithFileSystemPath(NULL, (__bridge CFStringRef)file, kCFURLPOSIXPathStyle, false);
    CFTypeRef size = NULL;
    Boolean got = CFURLCopyResourcePropertyForKey(fileURL, kCFURLFileSizeKey, &size, NULL);
    CFTypeRef isDirectory = NULL;
    CFURLCopyResourcePropertyForKey(fileURL, kCFURLIsDirectoryKey, &isDirectory, NULL);
    CFTypeRef name = NULL;
    CFURLCopyResourcePropertyForKey(fileURL, kCFURLNameKey, &name, NULL);
    print([NSString stringWithFormat:@"file %d size %@ directory %@ name %@ reachable %d", got, size, isDirectory, name, CFURLResourceIsReachable(fileURL, NULL)]);
    CFURLRef directoryURL = CFURLCreateWithFileSystemPath(NULL, (__bridge CFStringRef)@(directory), kCFURLPOSIXPathStyle, true);
    CFURLEnumeratorRef enumerator = CFURLEnumeratorCreateForDirectoryURL(NULL, directoryURL, kCFURLEnumeratorDefaultBehavior, NULL);
    CFURLRef next = NULL;
    NSMutableArray *found = [NSMutableArray array];
    while (CFURLEnumeratorGetNextURL(enumerator, &next, NULL) == kCFURLEnumeratorSuccess) {
        [found addObject:CFBridgingRelease(CFURLCopyLastPathComponent(next))];
    }
    print([NSString stringWithFormat:@"enumerated %@ type %d", [found componentsJoinedByString:@","], CFGetTypeID(enumerator) == CFURLEnumeratorGetTypeID()]);
    unlink(file.UTF8String);
    rmdir(directory);
    CFBundleRef main = CFBundleGetMainBundle();
    print([NSString stringWithFormat:@"bundle region %@ executable loaded %d", CFBundleGetDevelopmentRegion(main), CFBundleIsExecutableLoaded(main)]);
}

static void streams(void) {
    CFDataRef data = CFDataCreate(NULL, (const UInt8 *)"stream data", 11);
    CFReadStreamRef reader = CFReadStreamCreateWithData(NULL, data);
    CFReadStreamOpen(reader);
    UInt8 bytes[32] = {0};
    CFIndex read = CFReadStreamRead(reader, bytes, sizeof bytes);
    print([NSString stringWithFormat:@"read %ld [%s] type %d", (long)read, bytes, CFGetTypeID(reader) == CFReadStreamGetTypeID()]);
    CFReadStreamClose(reader);
    UInt8 buffer[16] = {0};
    CFWriteStreamRef writer = CFWriteStreamCreateWithBuffer(NULL, buffer, sizeof buffer);
    CFWriteStreamOpen(writer);
    CFIndex written = CFWriteStreamWrite(writer, (const UInt8 *)"0123456789ABCDEFGH", 18);
    print([NSString stringWithFormat:@"written %ld [%.16s] type %d", (long)written, buffer, CFGetTypeID(writer) == CFWriteStreamGetTypeID()]);
    CFWriteStreamClose(writer);
    CFWriteStreamRef memory = CFWriteStreamCreateWithAllocatedBuffers(NULL, NULL);
    CFWriteStreamOpen(memory);
    CFErrorRef error = NULL;
    CFIndex plistBytes = CFPropertyListWrite((__bridge CFPropertyListRef)@{@"k": @"v"}, memory, kCFPropertyListXMLFormat_v1_0, 0, &error);
    CFDataRef contents = CFWriteStreamCopyProperty(memory, kCFStreamPropertyDataWritten);
    CFWriteStreamClose(memory);
    CFReadStreamRef back = CFReadStreamCreateWithData(NULL, contents);
    CFReadStreamOpen(back);
    CFPropertyListRef plist = CFPropertyListCreateWithStream(NULL, back, 0, 0, NULL, NULL);
    print([NSString stringWithFormat:@"plist %d bytes %d back %@", plistBytes > 0, CFDataGetLength(contents) == plistBytes,
           [(__bridge NSDictionary *)plist objectForKey:@"k"]]);
}

static CFDataRef replyTo(CFMessagePortRef port, SInt32 msgid, CFDataRef data, void *info) {
    NSString *text = [[NSString alloc] initWithData:(__bridge NSData *)data encoding:NSUTF8StringEncoding];
    return CFBridgingRetain([[NSString stringWithFormat:@"%d:%@!", (int)msgid, text] dataUsingEncoding:NSUTF8StringEncoding]);
}

static void messagePorts(void) {
    CFMessagePortContext context = {0, NULL, NULL, NULL, NULL};
    Boolean shouldFree = false;
    CFStringRef name = CFSTR("org.perry.fixture.inventory.port");
    CFMessagePortRef local = CFMessagePortCreateLocal(NULL, name, replyTo, &context, &shouldFree);
    CFRunLoopSourceRef source = CFMessagePortCreateRunLoopSource(NULL, local, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
    CFMessagePortRef remote = CFMessagePortCreateRemote(NULL, name);
    print([NSString stringWithFormat:@"ports %d %d remote %d %d name %@ type %d", local != NULL, remote != NULL, CFMessagePortIsRemote(local),
           CFMessagePortIsRemote(remote), CFMessagePortGetName(local), CFGetTypeID(local) == CFMessagePortGetTypeID()]);
    // A request to a port of the same process is answered when its run loop
    // runs: here, on this thread, while the request waits.
    CFDataRef reply = NULL;
    SInt32 status = CFMessagePortSendRequest(remote, 7, (__bridge CFDataRef)[@"hi" dataUsingEncoding:NSUTF8StringEncoding], 1, 1, kCFRunLoopDefaultMode, &reply);
    print([NSString stringWithFormat:@"request %d reply %@", (int)status, reply ? [[NSString alloc] initWithData:(__bridge NSData *)reply encoding:NSUTF8StringEncoding] : @"-"]);
    CFMessagePortInvalidate(remote);
    CFMessagePortInvalidate(local);
    print([NSString stringWithFormat:@"invalidated %d %d", CFMessagePortIsValid(local), CFMessagePortIsValid(remote)]);
}

static void runLoops(void) {
    CFRunLoopRef loop = CFRunLoopGetCurrent();
    CFRunLoopSourceContext context = {0};
    CFRunLoopSourceRef source = CFRunLoopSourceCreate(NULL, 3, &context);
    CFRunLoopAddSource(loop, source, kCFRunLoopDefaultMode);
    CFRunLoopObserverRef observer = CFRunLoopObserverCreate(NULL, kCFRunLoopAllActivities, true, 5, NULL, NULL);
    CFRunLoopTimerRef timer = CFRunLoopTimerCreate(NULL, CFAbsoluteTimeGetCurrent() + 100, 0, 0, 9, NULL, NULL);
    CFRunLoopTimerSetTolerance(timer, 0.5);
    print([NSString stringWithFormat:@"run loop type %d contains %d source order %ld observer order %ld repeats %d timer order %ld tolerance %.1f",
           CFGetTypeID(loop) == CFRunLoopGetTypeID(), CFRunLoopContainsSource(loop, source, kCFRunLoopDefaultMode), (long)CFRunLoopSourceGetOrder(source),
           (long)CFRunLoopObserverGetOrder(observer), CFRunLoopObserverDoesRepeat(observer), (long)CFRunLoopTimerGetOrder(timer), CFRunLoopTimerGetTolerance(timer)]);
    print([NSString stringWithFormat:@"type ids %d %d %d waiting %d", CFGetTypeID(source) == CFRunLoopSourceGetTypeID(),
           CFGetTypeID(observer) == CFRunLoopObserverGetTypeID(), CFGetTypeID(timer) == CFRunLoopTimerGetTypeID(), CFRunLoopIsWaiting(loop)]);
    CFRunLoopRemoveSource(loop, source, kCFRunLoopDefaultMode);
}

static void security(void) {
    CFFileSecurityRef security = CFFileSecurityCreate(NULL);
    CFFileSecuritySetMode(security, 0644);
    CFFileSecuritySetOwner(security, 501);
    mode_t mode = 0;
    uid_t owner = 0;
    print([NSString stringWithFormat:@"security mode %d %o owner %d %d type %d", CFFileSecurityGetMode(security, &mode), mode,
           CFFileSecurityGetOwner(security, &owner), owner, CFGetTypeID(security) == CFFileSecurityGetTypeID()]);
}

static void constants(void) {
    print([NSString stringWithFormat:@"keys %@ %@ %@ %@ %@", kCFURLFileSizeKey, kCFLocaleCurrencyCodeKey, kCFCalendarIdentifierHebrew,
           kCFStreamPropertyDataWritten, kCFNumberFormatterCurrencyCodeKey]);
}

int main(void) {
    @autoreleasepool {
        miscellaneous();
        strings();
        locales();
        dates();
        urls();
        streams();
        messagePorts();
        runLoops();
        security();
        constants();
    }
    return 0;
}
