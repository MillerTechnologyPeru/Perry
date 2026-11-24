// Foundation's exported constants and C functions: a selection of the
// string constants of each group, NSDecimal arithmetic and its errors,
// NSDecimalString, NSDecimalNumber and its behaviors and exceptions, memory
// pages, extra reference counts and directories. Prints to stdout so the
// test can compare exact text.
#import <Foundation/Foundation.h>

// Under ARC these are unavailable by name; they are called by their symbols.
extern void GlossaryIncrementExtraRefCount(void *object) __asm__("_NSIncrementExtraRefCount");
extern BOOL GlossaryDecrementExtraRefCountWasZero(void *object) __asm__("_NSDecrementExtraRefCountWasZero");
extern NSUInteger GlossaryExtraRefCount(void *object) __asm__("_NSExtraRefCount");
extern BOOL GlossaryShouldRetainWithZone(void *object, void *zone) __asm__("_NSShouldRetainWithZone");
// The NeXT-era user defaults keys, which the iOS headers leave out.
extern NSString *const GlossaryAMPMDesignation __asm__("_NSAMPMDesignation");
extern NSString *const GlossaryMonthNameArray __asm__("_NSMonthNameArray");
extern NSString *const GlossaryDecimalSeparator __asm__("_NSDecimalSeparator");
extern NSString *const GlossaryYearMonthWeekDesignations __asm__("_NSYearMonthWeekDesignations");
// Newer than iOS 15, or not declared for macOS: by their symbols too.
extern NSString *const GlossaryCalendarBangla __asm__("_NSCalendarIdentifierBangla");
extern NSString *const GlossaryCalendarVikram __asm__("_NSCalendarIdentifierVikram");
extern NSString *const GlossaryCalendarDangi __asm__("_NSCalendarIdentifierDangi");
extern NSString *const GlossaryCookieSetByJavaScript __asm__("_NSHTTPCookieSetByJavaScript");
extern NSString *const GlossarySizeLimitExceeded __asm__("_NSUserDefaultsSizeLimitExceededNotification");

static void print(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static NSDecimal parsed(NSString *text) {
    return [[NSDecimalNumber decimalNumberWithString:text] decimalValue];
}

static NSString *string(NSDecimal value) {
    return NSDecimalString(&value, nil);
}

static NSString *fields(NSDecimal value) {
    return [NSString stringWithFormat:@"exp=%d len=%u neg=%u compact=%u m0=%u", value._exponent, value._length,
            value._isNegative, value._isCompact, value._mantissa[0]];
}

static const char *modeName(NSRoundingMode mode) {
    switch (mode) {
    case NSRoundPlain: return "plain";
    case NSRoundDown: return "down";
    case NSRoundUp: return "up";
    case NSRoundBankers: return "bankers";
    }
    return "?";
}

/// A behavior that reports each error and answers 42 for division by zero.
@interface GlossaryBehavior : NSObject <NSDecimalNumberBehaviors>
@end

@implementation GlossaryBehavior
- (NSRoundingMode)roundingMode { return NSRoundUp; }
- (short)scale { return 1; }
- (NSDecimalNumber *)exceptionDuringOperation:(SEL)operation error:(NSCalculationError)error
                                  leftOperand:(NSDecimalNumber *)left rightOperand:(NSDecimalNumber *)right {
    print([NSString stringWithFormat:@"behavior %@ error=%lu left=%@ right=%@", NSStringFromSelector(operation),
           (unsigned long)error, left, right]);
    return error == NSCalculationDivideByZero ? [NSDecimalNumber decimalNumberWithString:@"42"] : nil;
}
@end

/// A behavior like the default handler's, plain with no scale, that reports
/// each error and raises none: what each operation would raise for.
@interface GlossaryWatcher : NSObject <NSDecimalNumberBehaviors>
@end

@implementation GlossaryWatcher
- (NSRoundingMode)roundingMode { return NSRoundPlain; }
- (short)scale { return NSDecimalNoScale; }
- (NSDecimalNumber *)exceptionDuringOperation:(SEL)operation error:(NSCalculationError)error
                                  leftOperand:(NSDecimalNumber *)left rightOperand:(NSDecimalNumber *)right {
    print([NSString stringWithFormat:@"watcher %@ error=%lu", NSStringFromSelector(operation), (unsigned long)error]);
    return nil;
}
@end

static void constants(void) {
    print([NSString stringWithFormat:@"defaults %@ %@ %@ %@", GlossaryAMPMDesignation, GlossaryMonthNameArray,
           GlossaryDecimalSeparator, GlossaryYearMonthWeekDesignations]);
    print([NSString stringWithFormat:@"calendars %@ %@ %@", GlossaryCalendarBangla, GlossaryCalendarVikram,
           GlossaryCalendarDangi]);
    print([NSString stringWithFormat:@"exceptions %@ %@ %@ %@", NSInconsistentArchiveException,
           NSInvalidUnarchiveOperationException, NSInvocationOperationVoidResultException, NSOldStyleException]);
    print([NSString stringWithFormat:@"notifications %@ %@ %@ %@", NSThreadWillExitNotification,
           NSSystemClockDidChangeNotification, GlossarySizeLimitExceeded,
           NSWillBecomeMultiThreadedNotification]);
    print([NSString stringWithFormat:@"tags %@ %@ %@ %@ %@", NSLinguisticTagSchemeLexicalClass, NSLinguisticTagNoun,
           NSLinguisticTagOtherWhitespace, NSLinguisticTagPlaceName, NSLinguisticTagSchemeNameTypeOrLexicalClass]);
    print([NSString stringWithFormat:@"metadata %@ %@ %@ %@", NSMetadataItemFSNameKey, NSMetadataQueryUbiquitousDocumentsScope,
           NSMetadataUbiquitousItemDownloadingStatusCurrent, NSMetadataQueryUpdateAddedItemsKey]);
    print([NSString stringWithFormat:@"names %@ %@ %@", NSPersonNameComponentGivenName, NSPersonNameComponentPrefix,
           NSPersonNameComponentKey]);
    print([NSString stringWithFormat:@"progress %@ %@ %@ %@", NSProgressKindFile, NSProgressFileOperationKindDownloading,
           NSProgressEstimatedTimeRemainingKey, NSProgressFileURLKey]);
    print([NSString stringWithFormat:@"streams %@ %@ %@ %@ %@", NSStreamSOCKSProxyHostKey, NSStreamSocketSecurityLevelTLSv1,
           NSStreamFileCurrentOffsetKey, NSStreamSOCKSErrorDomain, NSStreamNetworkServiceTypeCallSignaling]);
    print([NSString stringWithFormat:@"detection %@ %@", NSStringEncodingDetectionAllowLossyKey,
           NSStringEncodingDetectionSuggestedEncodingsKey]);
    print([NSString stringWithFormat:@"transforms %d %d %d", [NSStringTransformToLatin isEqualToString:(__bridge NSString *)kCFStringTransformToLatin],
           [NSStringTransformStripDiacritics isEqualToString:(__bridge NSString *)kCFStringTransformStripDiacritics],
           [NSStringTransformToXMLHex isEqualToString:(__bridge NSString *)kCFStringTransformToXMLHex]]);
    print([NSString stringWithFormat:@"checking %@ %@ %@ %@", NSTextCheckingCityKey, NSTextCheckingZIPKey,
           NSTextCheckingAirlineKey, NSTextCheckingJobTitleKey]);
    print([NSString stringWithFormat:@"urls %@ %@ %@ %@ %@", NSURLFileScheme, NSURLIsSparseKey, NSURLFileResourceTypeRegular,
           NSURLUbiquitousItemDownloadingStatusCurrent, NSURLFileProtectionComplete]);
    print([NSString stringWithFormat:@"extensions %@ %@ %@", NSExtensionItemAttachmentsKey,
           NSExtensionJavaScriptPreprocessingResultsKey, NSExtensionItemsAndErrorsKey]);
    print([NSString stringWithFormat:@"keys %@ %@ %@ %@ %@ %@", GlossaryCookieSetByJavaScript, NSLocalizedFailureErrorKey,
           NSStringEncodingErrorKey, NSItemProviderErrorDomain, NSAssertionHandlerKey, NSMultipleUnderlyingErrorsKey]);
    print([NSString stringWithFormat:@"decimal exceptions %@ %@ %@ %@", NSDecimalNumberExactnessException,
           NSDecimalNumberOverflowException, NSDecimalNumberUnderflowException, NSDecimalNumberDivideByZeroException]);
}

static void arithmetic(void) {
    NSDecimal a = parsed(@"1234.5678"), b = parsed(@"-0.0078"), result;
    NSCalculationError error = NSDecimalAdd(&result, &a, &b, NSRoundPlain);
    print([NSString stringWithFormat:@"add %@ err=%lu", string(result), (unsigned long)error]);
    error = NSDecimalSubtract(&result, &a, &b, NSRoundPlain);
    print([NSString stringWithFormat:@"subtract %@ err=%lu", string(result), (unsigned long)error]);
    error = NSDecimalMultiply(&result, &a, &b, NSRoundPlain);
    print([NSString stringWithFormat:@"multiply %@ err=%lu", string(result), (unsigned long)error]);
    error = NSDecimalDivide(&result, &a, &b, NSRoundPlain);
    print([NSString stringWithFormat:@"divide %@ err=%lu", string(result), (unsigned long)error]);
    NSDecimal one = parsed(@"1"), three = parsed(@"3");
    error = NSDecimalDivide(&result, &one, &three, NSRoundPlain);
    print([NSString stringWithFormat:@"third %@ err=%lu %@", string(result), (unsigned long)error, fields(result)]);
    NSDecimal two = parsed(@"2");
    error = NSDecimalPower(&result, &two, 100, NSRoundPlain);
    print([NSString stringWithFormat:@"power %@ err=%lu", string(result), (unsigned long)error]);
    error = NSDecimalMultiplyByPowerOf10(&result, &a, -6, NSRoundPlain);
    print([NSString stringWithFormat:@"power10 %@ err=%lu", string(result), (unsigned long)error]);

    // Errors.
    NSDecimal maximum = [[NSDecimalNumber maximumDecimalNumber] decimalValue], ten = parsed(@"10");
    error = NSDecimalMultiply(&result, &maximum, &ten, NSRoundPlain);
    print([NSString stringWithFormat:@"overflow err=%lu nan=%d", (unsigned long)error, NSDecimalIsNotANumber(&result)]);
    error = NSDecimalMultiplyByPowerOf10(&result, &maximum, 1, NSRoundPlain);
    print([NSString stringWithFormat:@"overflow10 err=%lu", (unsigned long)error]);
    NSDecimal tiny = parsed(@"1e-100"), huge = parsed(@"1e100");
    error = NSDecimalDivide(&result, &tiny, &huge, NSRoundPlain);
    print([NSString stringWithFormat:@"underflow err=%lu nan=%d", (unsigned long)error, NSDecimalIsNotANumber(&result)]);
    NSDecimal zero = parsed(@"0");
    error = NSDecimalDivide(&result, &one, &zero, NSRoundPlain);
    print([NSString stringWithFormat:@"divide by zero err=%lu %@", (unsigned long)error, string(result)]);
    NSDecimal nan = [[NSDecimalNumber notANumber] decimalValue];
    error = NSDecimalAdd(&result, &nan, &one, NSRoundPlain);
    print([NSString stringWithFormat:@"nan err=%lu %@", (unsigned long)error, string(result)]);
    NSDecimal wide = parsed(@"12345678901234567890123456789012345678"), fraction = parsed(@"0.001");
    error = NSDecimalAdd(&result, &wide, &fraction, NSRoundPlain);
    print([NSString stringWithFormat:@"precision err=%lu %@", (unsigned long)error, string(result)]);

    // Rounding in each mode.
    NSArray *values = @[@"2.5", @"-2.5", @"3.5", @"1.25", @"-1.35", @"0.04999"];
    for (NSRoundingMode mode = NSRoundPlain; mode <= NSRoundBankers; mode++) {
        NSMutableArray *rounded = [NSMutableArray array];
        for (NSString *text in values) {
            NSDecimal value = parsed(text);
            NSDecimalRound(&result, &value, 0, mode);
            NSString *whole = string(result);
            NSDecimalRound(&result, &value, 1, mode);
            [rounded addObject:[NSString stringWithFormat:@"%@>%@/%@", text, whole, string(result)]];
        }
        print([NSString stringWithFormat:@"round %s %@", modeName(mode), [rounded componentsJoinedByString:@" "]]);
    }
    NSDecimal sum = parsed(@"1.5"), cents = parsed(@"0.333");
    NSDecimalAdd(&result, &sum, &cents, NSRoundBankers);
    NSDecimalRound(&result, &result, 2, NSRoundBankers);
    print([NSString stringWithFormat:@"in place %@", string(result)]);

    // Comparing, normalizing, compacting, copying.
    NSDecimal small = parsed(@"0.5"), large = parsed(@"12");
    print([NSString stringWithFormat:@"compare %ld %ld %ld %ld", (long)NSDecimalCompare(&small, &large),
           (long)NSDecimalCompare(&large, &small), (long)NSDecimalCompare(&small, &small), (long)NSDecimalCompare(&nan, &small)]);
    NSDecimal first = parsed(@"1.5"), second = parsed(@"250");
    error = NSDecimalNormalize(&first, &second, NSRoundPlain);
    print([NSString stringWithFormat:@"normalize err=%lu %@ | %@", (unsigned long)error, fields(first), fields(second)]);
    NSDecimal raw = {0};
    raw._exponent = -3;
    raw._length = 1;
    raw._mantissa[0] = 12000;
    print([NSString stringWithFormat:@"raw %@ %@", string(raw), fields(raw)]);
    NSDecimalCompact(&raw);
    print([NSString stringWithFormat:@"compacted %@ %@", string(raw), fields(raw)]);
    NSDecimal copy;
    NSDecimalCopy(&copy, &raw);
    print([NSString stringWithFormat:@"copy %@ same=%ld", string(copy), (long)NSDecimalCompare(&copy, &raw)]);
    NSDecimal negative = parsed(@"-1234.5");
    print([NSString stringWithFormat:@"strings %@ %@ %@ %@", NSDecimalString(&negative, nil),
           NSDecimalString(&negative, @{NSLocaleDecimalSeparator: @","}),
           NSDecimalString(&negative, [NSLocale localeWithLocaleIdentifier:@"de_DE"]),
           NSDecimalString(&negative, [NSLocale localeWithLocaleIdentifier:@"en_US"])]);
    NSDecimal scaled = parsed(@"5e10"), point = parsed(@"0.000123");
    print([NSString stringWithFormat:@"exponents %@ %@ %@ %@", string(scaled), fields(scaled), string(point), fields(point)]);
}

static void numbers(void) {
    NSDecimalNumber *price = [NSDecimalNumber decimalNumberWithString:@"19.99"];
    NSDecimalNumber *quantity = [NSDecimalNumber decimalNumberWithString:@"3"];
    NSDecimalNumber *total = [price decimalNumberByMultiplyingBy:quantity];
    print([NSString stringWithFormat:@"total %@ %s double=%.2f int=%d", total, total.objCType, total.doubleValue, total.intValue]);
    print([NSString stringWithFormat:@"sum %@ difference %@ quotient %@", [price decimalNumberByAdding:quantity],
           [price decimalNumberBySubtracting:quantity], [price decimalNumberByDividingBy:quantity]]);
    print([NSString stringWithFormat:@"power %@ %@ shifted %@ %@", [quantity decimalNumberByRaisingToPower:4],
           [[NSDecimalNumber zero] decimalNumberByRaisingToPower:0], [price decimalNumberByMultiplyingByPowerOf10:3],
           [price decimalNumberByMultiplyingByPowerOf10:-4]]);

    NSDecimalNumberHandler *cents = [NSDecimalNumberHandler decimalNumberHandlerWithRoundingMode:NSRoundBankers scale:2
        raiseOnExactness:NO raiseOnOverflow:NO raiseOnUnderflow:NO raiseOnDivideByZero:NO];
    print([NSString stringWithFormat:@"handler mode=%lu scale=%d", (unsigned long)cents.roundingMode, cents.scale]);
    print([NSString stringWithFormat:@"cents %@ %@ %@", [price decimalNumberByDividingBy:quantity withBehavior:cents],
           [[NSDecimalNumber decimalNumberWithString:@"2.345"] decimalNumberByRoundingAccordingToBehavior:cents],
           [[NSDecimalNumber decimalNumberWithString:@"2.355"] decimalNumberByRoundingAccordingToBehavior:cents]]);
    print([NSString stringWithFormat:@"quiet %@ %@", [[NSDecimalNumber one] decimalNumberByDividingBy:[NSDecimalNumber zero] withBehavior:cents],
           [[NSDecimalNumber maximumDecimalNumber] decimalNumberByAdding:[NSDecimalNumber maximumDecimalNumber] withBehavior:cents]]);

    GlossaryBehavior *behavior = [GlossaryBehavior new];
    print([NSString stringWithFormat:@"custom %@", [[NSDecimalNumber one] decimalNumberByDividingBy:[NSDecimalNumber zero] withBehavior:behavior]]);
    print([NSString stringWithFormat:@"custom %@", [[NSDecimalNumber one] decimalNumberByDividingBy:quantity withBehavior:behavior]]);
    print([NSString stringWithFormat:@"custom %@", [[NSDecimalNumber decimalNumberWithString:@"2.25"]
                                                    decimalNumberByMultiplyingByPowerOf10:200 withBehavior:behavior]]);
    print([NSString stringWithFormat:@"custom %@", [[NSDecimalNumber decimalNumberWithString:@"2.25"]
                                                    decimalNumberByRaisingToPower:3 withBehavior:behavior]]);

    // The errors the default behavior raises for, reported by a watcher set
    // as the thread's default behavior instead (Perry cannot deliver an
    // exception to @catch yet).
    [NSDecimalNumber setDefaultBehavior:[GlossaryWatcher new]];
    print([NSString stringWithFormat:@"divide gave %@", [[NSDecimalNumber one] decimalNumberByDividingBy:[NSDecimalNumber zero]]]);
    print([NSString stringWithFormat:@"overflow gave %@", [[NSDecimalNumber maximumDecimalNumber]
                                                           decimalNumberByMultiplyingBy:[NSDecimalNumber decimalNumberWithString:@"10"]]]);
    print([NSString stringWithFormat:@"underflow gave %@", [[NSDecimalNumber decimalNumberWithString:@"1e-100"]
                                                            decimalNumberByDividingBy:[NSDecimalNumber decimalNumberWithString:@"1e100"]]]);
    print([NSString stringWithFormat:@"nan gave %@", [[NSDecimalNumber notANumber] decimalNumberByAdding:[NSDecimalNumber one]]]);
    print([NSString stringWithFormat:@"power10 gave %@", [[NSDecimalNumber maximumDecimalNumber] decimalNumberByMultiplyingByPowerOf10:1]]);
    print([NSString stringWithFormat:@"subtract gave %@", [[NSDecimalNumber decimalNumberWithString:@"12345678901234567890123456789012345678"]
                                                           decimalNumberBySubtracting:[NSDecimalNumber decimalNumberWithString:@"0.001"]]]);
    print([NSString stringWithFormat:@"add gave %@", [[NSDecimalNumber decimalNumberWithString:@"12345678901234567890123456789012345678"]
                                                      decimalNumberByAdding:[NSDecimalNumber decimalNumberWithString:@"0.001"]]]);
    [[NSThread currentThread].threadDictionary removeObjectForKey:@"NSDecimalNumberBehaviors"];
    NSDecimalNumberHandler *strict = [[NSDecimalNumberHandler alloc] initWithRoundingMode:NSRoundDown scale:3
        raiseOnExactness:YES raiseOnOverflow:YES raiseOnUnderflow:YES raiseOnDivideByZero:YES];
    print([NSString stringWithFormat:@"strict mode=%lu scale=%d rounded=%@", (unsigned long)strict.roundingMode, strict.scale,
           [[NSDecimalNumber decimalNumberWithString:@"-2.71828"] decimalNumberByRoundingAccordingToBehavior:strict]]);
    print([NSString stringWithFormat:@"quiet handler %@", [cents exceptionDuringOperation:@selector(decimalNumberByAdding:)
        error:NSCalculationOverflow leftOperand:[NSDecimalNumber one] rightOperand:[NSDecimalNumber one]]]);

    // The default behavior, per thread.
    NSDecimalNumberHandler *shared = [NSDecimalNumberHandler defaultDecimalNumberHandler];
    print([NSString stringWithFormat:@"default shared=%d current=%d mode=%lu scale=%d", shared == [NSDecimalNumberHandler defaultDecimalNumberHandler],
           (id)[NSDecimalNumber defaultBehavior] == (id)shared, (unsigned long)shared.roundingMode, shared.scale]);
    [NSDecimalNumber setDefaultBehavior:cents];
    print([NSString stringWithFormat:@"set current=%d dictionary=%d quotient=%@", (id)[NSDecimalNumber defaultBehavior] == (id)cents,
           [NSThread currentThread].threadDictionary[@"NSDecimalNumberBehaviors"] == cents, [price decimalNumberByDividingBy:quantity]]);
    __block BOOL otherThread = YES;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [NSThread detachNewThreadWithBlock:^{
        otherThread = (id)[NSDecimalNumber defaultBehavior] == (id)cents;
        dispatch_semaphore_signal(done);
    }];
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    print([NSString stringWithFormat:@"other thread uses it=%d", otherThread]);
    [[NSThread currentThread].threadDictionary removeObjectForKey:@"NSDecimalNumberBehaviors"];
    print([NSString stringWithFormat:@"reset current=%d", (id)[NSDecimalNumber defaultBehavior] == (id)shared]);

    // Values and conversions.
    NSDecimalNumber *mixed = [NSDecimalNumber decimalNumberWithString:@"-1.9"];
    print([NSString stringWithFormat:@"-1.9 int=%d long=%lld unsigned=%u bool=%d double=%.1f", mixed.intValue, mixed.longLongValue,
           mixed.unsignedIntValue, mixed.boolValue, mixed.doubleValue]);
    NSDecimalNumber *big = [NSDecimalNumber decimalNumberWithString:@"1e30"];
    print([NSString stringWithFormat:@"1e30 long=%lld int=%d %@", big.longLongValue, big.intValue, big]);
    NSDecimalNumber *wide = [NSDecimalNumber decimalNumberWithString:@"123456789012345678.9"];
    print([NSString stringWithFormat:@"wide long=%lld int=%d short=%hd %@", wide.longLongValue, wide.intValue, wide.shortValue, wide.stringValue]);
    NSDecimal value = [[NSDecimalNumber decimalNumberWithString:@"-12.340"] decimalValue];
    print([NSString stringWithFormat:@"decimalValue %@ %@ %@", fields(value), [[NSDecimalNumber alloc] initWithDecimal:value],
           [NSDecimalNumber decimalNumberWithDecimal:value]]);
    print([NSString stringWithFormat:@"mantissa %@ %@ %@", [NSDecimalNumber decimalNumberWithMantissa:12345 exponent:-3 isNegative:YES],
           [NSDecimalNumber decimalNumberWithMantissa:0 exponent:5 isNegative:YES],
           [[NSDecimalNumber alloc] initWithMantissa:7 exponent:2 isNegative:NO]]);
    print([NSString stringWithFormat:@"numbers %@ %@ %@ %s", [NSDecimalNumber numberWithInt:-7], [NSDecimalNumber numberWithDouble:0.1],
           [[NSDecimalNumber alloc] initWithDouble:2.5], [NSDecimalNumber numberWithInt:-7].objCType]);
    print([NSString stringWithFormat:@"parse %@ %@ %@ %@ %@", [NSDecimalNumber decimalNumberWithString:@"12.5abc"],
           [NSDecimalNumber decimalNumberWithString:@"abc"], [NSDecimalNumber decimalNumberWithString:@"  -0.050e2"],
           [NSDecimalNumber decimalNumberWithString:@"1,5" locale:[NSLocale localeWithLocaleIdentifier:@"de_DE"]],
           [NSDecimalNumber decimalNumberWithString:@"1,5" locale:@{NSLocaleDecimalSeparator: @","}]]);
    print([NSString stringWithFormat:@"locale %@ %@", [[NSDecimalNumber decimalNumberWithString:@"-1234.5"] descriptionWithLocale:@{NSLocaleDecimalSeparator: @","}],
           [[NSDecimalNumber decimalNumberWithString:@"0.25"] descriptionWithLocale:[NSLocale localeWithLocaleIdentifier:@"de_DE"]]]);
    print([NSString stringWithFormat:@"limits %@ %@ %@ %@", [NSDecimalNumber maximumDecimalNumber], [NSDecimalNumber minimumDecimalNumber],
           [NSDecimalNumber notANumber], [NSDecimalNumber zero]]);
    print([NSString stringWithFormat:@"compare %ld %ld %ld equal=%d %d %d nan=%d", (long)[price compare:quantity], (long)[quantity compare:@3],
           (long)[[NSDecimalNumber notANumber] compare:[NSDecimalNumber one]], [quantity isEqual:@3], [quantity isEqualToNumber:@3.0],
           [[NSDecimalNumber decimalNumberWithString:@"0.1"] isEqual:@0.1], [[NSDecimalNumber notANumber] isEqual:[NSDecimalNumber notANumber]]]);
    print([NSString stringWithFormat:@"mixed %@ %@", [[NSDecimalNumber one] decimalNumberByAdding:(NSDecimalNumber *)@2.5],
           [[NSDecimalNumber one] decimalNumberByAdding:(NSDecimalNumber *)@0.1]]);
}

static void functions(void) {
    NSUInteger size = 3 * NSPageSize();
    unsigned char *pages = NSAllocateMemoryPages(size);
    BOOL zeroed = YES;
    for (NSUInteger index = 0; index < size; index++) {
        if (pages[index] != 0) zeroed = NO;
    }
    memcpy(pages, "glossary", 9);
    NSCopyMemoryPages(pages, pages + 3, 9);
    print([NSString stringWithFormat:@"pages zeroed=%d aligned=%d copied=%s", zeroed, ((uintptr_t)pages % NSPageSize()) == 0,
           (const char *)pages]);
    NSDeallocateMemoryPages(pages, size);

    NSObject *object = [NSObject new];
    void *raw = (__bridge void *)object;
    NSUInteger before = GlossaryExtraRefCount(raw);
    GlossaryIncrementExtraRefCount(raw);
    NSUInteger raised = GlossaryExtraRefCount(raw);
    BOOL firstZero = GlossaryDecrementExtraRefCountWasZero(raw);
    NSUInteger after = GlossaryExtraRefCount(raw);
    BOOL secondZero = GlossaryDecrementExtraRefCountWasZero(raw);
    print([NSString stringWithFormat:@"refcounts %lu %lu %d %lu %d retain=%d", (unsigned long)before, (unsigned long)raised, firstZero,
           (unsigned long)after, secondZero, GlossaryShouldRetainWithZone(raw, NULL)]);

    NSString *home = NSHomeDirectoryForUser(@"root");
    print([NSString stringWithFormat:@"home root=%d absolute=%d missing=%@ mine=%d root dir=%@", home != nil, [home hasPrefix:@"/"],
           NSHomeDirectoryForUser(@"glossary-no-such-user"), [NSHomeDirectoryForUser(nil) isEqualToString:NSHomeDirectory()],
           NSOpenStepRootDirectory()]);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        constants();
        arithmetic();
        numbers();
        functions();
    }
    return 0;
}
