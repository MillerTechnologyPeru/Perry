// CoreFoundation's number and date formatters, through their C API, built
// on a Mac with Xcode. Locales and time zones are given, so the output is
// the same anywhere.
#import <Foundation/Foundation.h>

static void print(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static NSString *text(CFStringRef string) {
    return string ? [NSString stringWithFormat:@"[%@]", (__bridge NSString *)string] : @"(null)";
}

/// A formatted number, released.
static NSString *formatted(CFNumberFormatterRef formatter, double value) {
    CFNumberRef number = CFNumberCreate(NULL, kCFNumberDoubleType, &value);
    CFStringRef string = CFNumberFormatterCreateStringWithNumber(NULL, formatter, number);
    NSString *result = text(string);
    if (string) CFRelease(string);
    CFRelease(number);
    return result;
}

/// The number parsed from `string` in `range`, and the range parsed.
static NSString *parsed(CFNumberFormatterRef formatter, NSString *string, CFRange range, CFOptionFlags options) {
    CFNumberRef number = CFNumberFormatterCreateNumberFromString(NULL, formatter, (__bridge CFStringRef)string, &range, options);
    if (!number) return @"none";
    double value = 0;
    CFNumberGetValue(number, kCFNumberDoubleType, &value);
    NSString *result = [NSString stringWithFormat:@"%g %s {%ld, %ld}", value,
                        CFNumberIsFloatType(number) ? "float" : "integer", (long)range.location, (long)range.length];
    CFRelease(number);
    return result;
}

static void numbers(void) {
    CFLocaleRef us = CFLocaleCreate(NULL, CFSTR("en_US"));
    CFLocaleRef de = CFLocaleCreate(NULL, CFSTR("de_DE"));
    print([NSString stringWithFormat:@"number type %d", CFGetTypeID(CFNumberFormatterCreate(NULL, us, 0)) == CFNumberFormatterGetTypeID()]);

    CFNumberFormatterRef decimal = CFNumberFormatterCreate(NULL, us, kCFNumberFormatterDecimalStyle);
    print([NSString stringWithFormat:@"decimal %@ style %ld format %@", formatted(decimal, 1234567.891),
           (long)CFNumberFormatterGetStyle(decimal), text(CFNumberFormatterGetFormat(decimal))]);
    print([NSString stringWithFormat:@"locale %@", text(CFLocaleGetIdentifier(CFNumberFormatterGetLocale(decimal)))]);

    CFNumberFormatterRef none = CFNumberFormatterCreate(NULL, us, kCFNumberFormatterNoStyle);
    print([NSString stringWithFormat:@"none %@ %@", formatted(none, 2.5), formatted(none, 12345)]);
    print([NSString stringWithFormat:@"currency %@ %@",
           formatted(CFNumberFormatterCreate(NULL, us, kCFNumberFormatterCurrencyStyle), 1234.5),
           formatted(CFNumberFormatterCreate(NULL, de, kCFNumberFormatterCurrencyStyle), 1234.5)]);
    print([NSString stringWithFormat:@"percent %@ spell %@ ordinal %@",
           formatted(CFNumberFormatterCreate(NULL, us, kCFNumberFormatterPercentStyle), 0.256),
           formatted(CFNumberFormatterCreate(NULL, us, kCFNumberFormatterSpellOutStyle), 42),
           formatted(CFNumberFormatterCreate(NULL, us, kCFNumberFormatterOrdinalStyle), 3)]);

    int seven = 7;
    CFStringRef value = CFNumberFormatterCreateStringWithValue(NULL, decimal, kCFNumberIntType, &seven);
    print([NSString stringWithFormat:@"value %@", text(value)]);

    CFNumberFormatterRef custom = CFNumberFormatterCreate(NULL, us, kCFNumberFormatterDecimalStyle);
    CFNumberFormatterSetFormat(custom, CFSTR("0.00"));
    print([NSString stringWithFormat:@"custom %@ format %@", formatted(custom, 3.14159), text(CFNumberFormatterGetFormat(custom))]);

    print([NSString stringWithFormat:@"parse %@ | %@ | %@ | %@ | %@",
           parsed(decimal, @"1,234.5", CFRangeMake(0, 7), 0), parsed(decimal, @"42", CFRangeMake(0, 2), 0),
           parsed(decimal, @"12abc", CFRangeMake(0, 5), 0), parsed(decimal, @"x12", CFRangeMake(1, 2), 0),
           parsed(decimal, @"3.7", CFRangeMake(0, 3), kCFNumberFormatterParseIntegersOnly)]);
    print([NSString stringWithFormat:@"parse none %@", parsed(decimal, @"abc", CFRangeMake(0, 3), 0)]);

    SInt32 integer = 0;
    Boolean got = CFNumberFormatterGetValueFromString(decimal, CFSTR("-42"), NULL, kCFNumberSInt32Type, &integer);
    double real = 0;
    Boolean gotReal = CFNumberFormatterGetValueFromString(decimal, CFSTR("2.25"), NULL, kCFNumberDoubleType, &real);
    Boolean bad = CFNumberFormatterGetValueFromString(decimal, CFSTR("x"), NULL, kCFNumberSInt32Type, &integer);
    print([NSString stringWithFormat:@"value from string %d %d | %d %g | %d", got, (int)integer, gotReal, real, bad]);

    CFNumberFormatterRef properties = CFNumberFormatterCreate(NULL, us, kCFNumberFormatterDecimalStyle);
    int two = 2;
    CFNumberRef twoNumber = CFNumberCreate(NULL, kCFNumberIntType, &two);
    CFNumberFormatterSetProperty(properties, kCFNumberFormatterMaxFractionDigits, twoNumber);
    CFNumberFormatterSetProperty(properties, kCFNumberFormatterMinFractionDigits, twoNumber);
    CFNumberFormatterSetProperty(properties, kCFNumberFormatterUseGroupingSeparator, kCFBooleanFalse);
    print([NSString stringWithFormat:@"properties %@ %@", formatted(properties, 1234.5678), formatted(properties, 1)]);
    CFNumberRef maxFraction = CFNumberFormatterCopyProperty(properties, kCFNumberFormatterMaxFractionDigits);
    int maxValue = 0;
    CFNumberGetValue(maxFraction, kCFNumberIntType, &maxValue);
    CFBooleanRef grouping = CFNumberFormatterCopyProperty(properties, kCFNumberFormatterUseGroupingSeparator);
    print([NSString stringWithFormat:@"copied max %d grouping %d", maxValue, CFBooleanGetValue(grouping)]);

    CFNumberFormatterSetProperty(properties, kCFNumberFormatterZeroSymbol, CFSTR("nil"));
    CFNumberFormatterSetProperty(properties, kCFNumberFormatterPositivePrefix, CFSTR("+"));
    print([NSString stringWithFormat:@"zero %@ prefix %@ zero symbol %@", formatted(properties, 0), formatted(properties, 5),
           text(CFNumberFormatterCopyProperty(properties, kCFNumberFormatterZeroSymbol))]);

    CFNumberFormatterRef german = CFNumberFormatterCreate(NULL, de, kCFNumberFormatterDecimalStyle);
    print([NSString stringWithFormat:@"german %@ separator %@ grouping %@", formatted(german, 1234.5),
           text(CFNumberFormatterCopyProperty(german, kCFNumberFormatterDecimalSeparator)),
           text(CFNumberFormatterCopyProperty(german, kCFNumberFormatterGroupingSeparator))]);

    CFNumberFormatterRef euros = CFNumberFormatterCreate(NULL, us, kCFNumberFormatterCurrencyStyle);
    CFNumberFormatterSetProperty(euros, kCFNumberFormatterCurrencyCode, CFSTR("EUR"));
    print([NSString stringWithFormat:@"euros %@ code %@ default %@", formatted(euros, 9.5),
           text(CFNumberFormatterCopyProperty(euros, kCFNumberFormatterCurrencyCode)),
           text(CFNumberFormatterCopyProperty(custom, kCFNumberFormatterDefaultFormat))]);

    int32_t digits = -1;
    double rounding = -1;
    Boolean yen = CFNumberFormatterGetDecimalInfoForCurrencyCode(CFSTR("JPY"), &digits, &rounding);
    print([NSString stringWithFormat:@"JPY %d %d %g", yen, digits, rounding]);
    yen = CFNumberFormatterGetDecimalInfoForCurrencyCode(CFSTR("USD"), &digits, &rounding);
    print([NSString stringWithFormat:@"USD %d %d %g", yen, digits, rounding]);
    print([NSString stringWithFormat:@"keys %@ %@", text(kCFNumberFormatterCurrencyCode), text(kCFNumberFormatterIsLenient)]);
}

static void dates(void) {
    CFLocaleRef us = CFLocaleCreate(NULL, CFSTR("en_US"));
    CFLocaleRef de = CFLocaleCreate(NULL, CFSTR("de_DE"));
    CFTimeZoneRef utc = CFTimeZoneCreateWithName(NULL, CFSTR("UTC"), true);
    CFTimeZoneRef tokyo = CFTimeZoneCreateWithName(NULL, CFSTR("Asia/Tokyo"), true);
    // 2025-11-23 10:30:45 UTC.
    CFAbsoluteTime when = 785586645;

    CFDateFormatterRef styled = CFDateFormatterCreate(NULL, us, kCFDateFormatterLongStyle, kCFDateFormatterNoStyle);
    print([NSString stringWithFormat:@"date type %d", CFGetTypeID(styled) == CFDateFormatterGetTypeID()]);
    CFDateFormatterSetProperty(styled, kCFDateFormatterTimeZone, utc);
    CFStringRef long_ = CFDateFormatterCreateStringWithAbsoluteTime(NULL, styled, when);
    print([NSString stringWithFormat:@"long %@ styles %ld %ld format %@", text(long_), (long)CFDateFormatterGetDateStyle(styled),
           (long)CFDateFormatterGetTimeStyle(styled), text(CFDateFormatterGetFormat(styled))]);

    CFDateFormatterRef german = CFDateFormatterCreate(NULL, de, kCFDateFormatterFullStyle, kCFDateFormatterNoStyle);
    CFDateFormatterSetProperty(german, kCFDateFormatterTimeZone, tokyo);
    print([NSString stringWithFormat:@"german %@", text(CFDateFormatterCreateStringWithAbsoluteTime(NULL, german, when))]);

    CFDateFormatterRef fixed = CFDateFormatterCreate(NULL, us, kCFDateFormatterNoStyle, kCFDateFormatterNoStyle);
    CFDateFormatterSetProperty(fixed, kCFDateFormatterTimeZone, utc);
    CFDateFormatterSetFormat(fixed, CFSTR("yyyy-MM-dd HH:mm:ss"));
    CFDateRef date = CFDateCreate(NULL, when);
    print([NSString stringWithFormat:@"fixed %@ format %@ default %@", text(CFDateFormatterCreateStringWithDate(NULL, fixed, date)),
           text(CFDateFormatterGetFormat(fixed)), text(CFDateFormatterCopyProperty(styled, kCFDateFormatterDefaultFormat))]);

    CFRange range = CFRangeMake(0, 23);
    CFDateRef parsed = CFDateFormatterCreateDateFromString(NULL, fixed, CFSTR("2001-01-02 03:04:05 tail"), &range);
    print([NSString stringWithFormat:@"parsed %.0f {%ld, %ld}", parsed ? CFDateGetAbsoluteTime(parsed) : -1.0,
           (long)range.location, (long)range.length]);
    CFAbsoluteTime absolute = 0;
    Boolean got = CFDateFormatterGetAbsoluteTimeFromString(fixed, CFSTR("2026-11-23 10:30:45"), NULL, &absolute);
    Boolean bad = CFDateFormatterGetAbsoluteTimeFromString(fixed, CFSTR("tomorrow"), NULL, &absolute);
    print([NSString stringWithFormat:@"absolute %d %.0f | %d", got, absolute, bad]);

    print([NSString stringWithFormat:@"templates %@ %@",
           text(CFDateFormatterCreateDateFormatFromTemplate(NULL, CFSTR("yMMMd"), 0, us)),
           text(CFDateFormatterCreateDateFormatFromTemplate(NULL, CFSTR("yMMMd"), 0, de))]);

    CFArrayRef months = CFDateFormatterCopyProperty(styled, kCFDateFormatterMonthSymbols);
    CFArrayRef weekdays = CFDateFormatterCopyProperty(german, kCFDateFormatterShortWeekdaySymbols);
    print([NSString stringWithFormat:@"months %ld %@ %@ weekdays %ld %@", (long)CFArrayGetCount(months),
           text(CFArrayGetValueAtIndex(months, 0)), text(CFArrayGetValueAtIndex(months, 11)),
           (long)CFArrayGetCount(weekdays), text(CFArrayGetValueAtIndex(weekdays, 0))]);
    print([NSString stringWithFormat:@"am %@ pm %@ calendar %@", text(CFDateFormatterCopyProperty(styled, kCFDateFormatterAMSymbol)),
           text(CFDateFormatterCopyProperty(styled, kCFDateFormatterPMSymbol)),
           text(CFDateFormatterCopyProperty(styled, kCFDateFormatterCalendarName))]);

    CFTimeZoneRef zone = CFDateFormatterCopyProperty(german, kCFDateFormatterTimeZone);
    CFBooleanRef lenient = CFDateFormatterCopyProperty(fixed, kCFDateFormatterIsLenient);
    print([NSString stringWithFormat:@"zone %@ lenient %d locale %@", text(CFTimeZoneGetName(zone)), CFBooleanGetValue(lenient),
           text(CFLocaleGetIdentifier(CFDateFormatterGetLocale(german)))]);

    CFDateFormatterRef iso = CFDateFormatterCreateISO8601Formatter(NULL, kCFISO8601DateFormatWithInternetDateTime);
    CFDateFormatterSetProperty(iso, kCFDateFormatterTimeZone, utc);
    print([NSString stringWithFormat:@"iso %@", text(CFDateFormatterCreateStringWithAbsoluteTime(NULL, iso, when))]);
    print([NSString stringWithFormat:@"keys %@ %@", text(kCFDateFormatterTimeZone), text(kCFDateFormatterDoesRelativeDateFormattingKey)]);
}

int main(void) {
    @autoreleasepool {
        numbers();
        dates();
    }
    return 0;
}
