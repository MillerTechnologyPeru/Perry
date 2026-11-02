// Time zones, locales, calendars and date components, and the date,
// ISO 8601 and number formatters, with explicit locales and time zones.
// The reference date is 2024-03-10 06:30:15 UTC, half an hour before
// daylight saving time began in New York.

#import <Foundation/Foundation.h>
#include <stdio.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static NSDate *reference(void) {
    return [NSDate dateWithTimeIntervalSince1970:1710052215];
}

static void timeZones(void) {
    NSTimeZone *york = [NSTimeZone timeZoneWithName:@"America/New_York"];
    NSDate *date = reference();
    NSDate *summer = [date dateByAddingTimeInterval:120 * 86400];
    say([NSString stringWithFormat:@"zone: %@ %@/%@, offsets %ld/%ld, DST %d/%d, saving %.0f", york.name,
         [york abbreviationForDate:date], [york abbreviationForDate:summer],
         (long)[york secondsFromGMTForDate:date], (long)[york secondsFromGMTForDate:summer],
         [york isDaylightSavingTimeForDate:date], [york isDaylightSavingTimeForDate:summer],
         [york daylightSavingTimeOffsetForDate:summer]]);
    NSDate *transition = [york nextDaylightSavingTimeTransitionAfterDate:date];
    say([NSString stringWithFormat:@"transition: %.0f", transition.timeIntervalSince1970]);
    NSLocale *english = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    say([NSString stringWithFormat:@"names: %@; %@; %@", [york localizedName:NSTimeZoneNameStyleStandard locale:english],
         [york localizedName:NSTimeZoneNameStyleDaylightSaving locale:english],
         [york localizedName:NSTimeZoneNameStyleShortStandard locale:english]]);
    NSTimeZone *india = [NSTimeZone timeZoneForSecondsFromGMT:19800];
    NSTimeZone *pacific = [NSTimeZone timeZoneWithAbbreviation:@"PST"];
    say([NSString stringWithFormat:@"fixed: %@ %ld %@; PST is %@; UTC %@; GMT %@; bogus %@", india.name,
         (long)india.secondsFromGMT, india.abbreviation, pacific.name, [NSTimeZone timeZoneWithName:@"UTC"].name,
         [NSTimeZone timeZoneForSecondsFromGMT:0].name, [NSTimeZone timeZoneWithName:@"Mars/Olympus"]]);
    say([NSString stringWithFormat:@"known: %d %d", [NSTimeZone.knownTimeZoneNames containsObject:@"Asia/Tokyo"],
         [NSTimeZone.knownTimeZoneNames containsObject:@"Europe/Paris"]]);
    say([NSString stringWithFormat:@"equal: %d %d", [york isEqualToTimeZone:[NSTimeZone timeZoneWithName:@"America/New_York"]],
         [york isEqual:india]]);
}

static void locales(void) {
    NSLocale *french = [NSLocale localeWithLocaleIdentifier:@"fr_FR"];
    NSLocale *english = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    say([NSString stringWithFormat:@"fr_FR: %@ %@ %@, decimal '%@', grouping '%@', %@ %@, metric %d", french.localeIdentifier,
         french.languageCode, french.countryCode, french.decimalSeparator, french.groupingSeparator,
         french.currencyCode, french.currencySymbol, french.usesMetricSystem]);
    say([NSString stringWithFormat:@"en_US: decimal '%@', grouping '%@', %@ %@, metric %d, calendar %@", english.decimalSeparator,
         english.groupingSeparator, english.currencyCode, english.currencySymbol, english.usesMetricSystem,
         english.calendarIdentifier]);
    say([NSString stringWithFormat:@"display: %@; %@; %@; %@",
         [english displayNameForKey:NSLocaleIdentifier value:@"de_DE"],
         [french localizedStringForCountryCode:@"JP"], [french localizedStringForLanguageCode:@"en"],
         [english localizedStringForCurrencyCode:@"JPY"]]);
    say([NSString stringWithFormat:@"keys: %@ %@ %@", [french objectForKey:NSLocaleLanguageCode],
         [french objectForKey:NSLocaleCountryCode], [french objectForKey:NSLocaleDecimalSeparator]]);
    say([NSString stringWithFormat:@"components: %@; from %@",
         [NSLocale componentsFromLocaleIdentifier:@"zh_Hant_TW"],
         [NSLocale localeIdentifierFromComponents:@{NSLocaleLanguageCode: @"pt", NSLocaleCountryCode: @"BR"}]]);
}

static void calendars(void) {
    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = [NSTimeZone timeZoneWithName:@"America/New_York"];
    NSDate *date = reference();
    NSDateComponents *parts = [calendar components:NSCalendarUnitEra | NSCalendarUnitYear | NSCalendarUnitMonth |
                               NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond |
                               NSCalendarUnitWeekday | NSCalendarUnitWeekOfYear | NSCalendarUnitQuarter fromDate:date];
    say([NSString stringWithFormat:@"components: era %ld %ld-%ld-%ld %ld:%ld:%ld weekday %ld week %ld, unset %ld",
         (long)parts.era, (long)parts.year, (long)parts.month, (long)parts.day, (long)parts.hour, (long)parts.minute,
         (long)parts.second, (long)parts.weekday, (long)parts.weekOfYear, (long)(parts.nanosecond == NSDateComponentUndefined)]);

    NSDateComponents *january = [NSDateComponents new];
    january.year = 2024;
    january.month = 1;
    january.day = 31;
    january.hour = 12;
    NSDate *end = [calendar dateFromComponents:january];
    NSDateComponents *month = [NSDateComponents new];
    month.month = 1;
    NSDate *february = [calendar dateByAddingComponents:month toDate:end options:0];
    NSDate *tomorrow = [calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:date options:0];
    say([NSString stringWithFormat:@"arithmetic: %.0f, +1 month day %ld, +1 day %.0f hours later",
         end.timeIntervalSince1970, (long)[calendar component:NSCalendarUnitDay fromDate:february],
         [tomorrow timeIntervalSinceDate:date] / 3600]);

    NSDateComponents *between = [calendar components:NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour
                                            fromDate:end toDate:date options:0];
    NSRange days = [calendar rangeOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitMonth forDate:february];
    NSUInteger ordinal = [calendar ordinalityOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitYear forDate:date];
    say([NSString stringWithFormat:@"between: %ld months %ld days %ld hours; February has %lu days from %lu; day %lu of the year",
         (long)between.month, (long)between.day, (long)between.hour, (unsigned long)days.length,
         (unsigned long)days.location, (unsigned long)ordinal]);

    NSDate *start = [calendar startOfDayForDate:date];
    NSDate *noon = [calendar dateBySettingHour:12 minute:0 second:0 ofDate:date options:0];
    say([NSString stringWithFormat:@"day: starts %.0f, noon %.0f, same day %d %d", start.timeIntervalSince1970,
         noon.timeIntervalSince1970, [calendar isDate:start inSameDayAsDate:noon],
         [calendar isDate:start inSameDayAsDate:tomorrow]]);

    NSCalendar *british = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    british.locale = [NSLocale localeWithLocaleIdentifier:@"en_GB"];
    calendar.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    say([NSString stringWithFormat:@"weeks: first weekday US %lu GB %lu, minimum days %lu/%lu", (unsigned long)calendar.firstWeekday,
         (unsigned long)british.firstWeekday, (unsigned long)calendar.minimumDaysInFirstWeek,
         (unsigned long)british.minimumDaysInFirstWeek]);
    say([NSString stringWithFormat:@"symbols: %@; %@; %@ %@", [calendar.shortWeekdaySymbols componentsJoinedByString:@" "],
         [calendar.monthSymbols componentsJoinedByString:@" "], calendar.AMSymbol, calendar.PMSymbol]);

    for (NSCalendarIdentifier identifier in @[NSCalendarIdentifierHebrew, NSCalendarIdentifierIslamicUmmAlQura,
                                              NSCalendarIdentifierJapanese, NSCalendarIdentifierBuddhist,
                                              NSCalendarIdentifierISO8601]) {
        NSCalendar *other = [NSCalendar calendarWithIdentifier:identifier];
        other.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
        NSDateComponents *c = [other components:NSCalendarUnitEra | NSCalendarUnitYear | NSCalendarUnitMonth |
                               NSCalendarUnitDay | NSCalendarUnitWeekOfYear fromDate:date];
        say([NSString stringWithFormat:@"%@: era %ld year %ld month %ld day %ld week %ld", other.calendarIdentifier,
             (long)c.era, (long)c.year, (long)c.month, (long)c.day, (long)c.weekOfYear]);
    }

    NSDateComponents *invalid = [NSDateComponents new];
    invalid.calendar = calendar;
    invalid.year = 2023;
    invalid.month = 2;
    invalid.day = 29;
    NSDateComponents *valid = [invalid copy];
    valid.day = 28;
    [valid setValue:2025 forComponent:NSCalendarUnitYear];
    say([NSString stringWithFormat:@"valid: %d %d, year %ld, date %.0f", invalid.isValidDate, valid.isValidDate,
         (long)[valid valueForComponent:NSCalendarUnitYear], valid.date.timeIntervalSince1970]);
}

static void dateFormatters(void) {
    NSDate *date = reference();
    NSDateFormatter *posix = [NSDateFormatter new];
    posix.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    posix.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
    posix.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ";
    NSString *text = [posix stringFromDate:date];
    NSDate *parsed = [posix dateFromString:@"2024-07-04T12:00:00.250-04:00"];
    say([NSString stringWithFormat:@"pattern: %@, parsed %.2f, bad %@", text, parsed.timeIntervalSince1970,
         [posix dateFromString:@"July 4th"]]);

    posix.timeZone = [NSTimeZone timeZoneWithName:@"America/New_York"];
    posix.dateFormat = @"EEEE, MMMM d, y 'at' h:mm a zzz (Q, w, D)";
    say([NSString stringWithFormat:@"named: %@", [posix stringFromDate:date]]);

    for (NSString *identifier in @[@"en_US", @"fr_FR", @"de_DE", @"ja_JP"]) {
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:identifier];
        formatter.timeZone = [NSTimeZone timeZoneWithName:@"America/New_York"];
        NSMutableArray *styles = [NSMutableArray array];
        for (NSNumber *style in @[@(NSDateFormatterShortStyle), @(NSDateFormatterMediumStyle),
                                  @(NSDateFormatterLongStyle), @(NSDateFormatterFullStyle)]) {
            formatter.dateStyle = style.unsignedIntegerValue;
            formatter.timeStyle = style.unsignedIntegerValue == NSDateFormatterFullStyle ? NSDateFormatterNoStyle
                                                                                       : style.unsignedIntegerValue;
            [styles addObject:[formatter stringFromDate:date]];
        }
        formatter.dateStyle = NSDateFormatterNoStyle;
        formatter.timeStyle = NSDateFormatterShortStyle;
        [styles addObject:[formatter stringFromDate:date]];
        say([NSString stringWithFormat:@"%@: %@", identifier, [styles componentsJoinedByString:@" | "]]);
    }

    NSLocale *german = [NSLocale localeWithLocaleIdentifier:@"de_DE"];
    NSDateFormatter *templated = [NSDateFormatter new];
    templated.locale = german;
    templated.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
    [templated setLocalizedDateFormatFromTemplate:@"MMMMdjmm"];
    say([NSString stringWithFormat:@"template: %@, %@ -> %@; '%@'",
         [NSDateFormatter dateFormatFromTemplate:@"yMMMd" options:0 locale:[NSLocale localeWithLocaleIdentifier:@"en_US"]],
         [NSDateFormatter dateFormatFromTemplate:@"yMMMd" options:0 locale:german], templated.dateFormat,
         [templated stringFromDate:date]]);

    NSDateFormatter *styled = [NSDateFormatter new];
    styled.locale = german;
    styled.dateStyle = NSDateFormatterMediumStyle;
    styled.timeStyle = NSDateFormatterShortStyle;
    say([NSString stringWithFormat:@"style pattern: %@; symbols %@ %@ %@", styled.dateFormat,
         styled.shortMonthSymbols[2], styled.weekdaySymbols[0], styled.AMSymbol]);

    NSISO8601DateFormatter *iso = [NSISO8601DateFormatter new];
    NSString *isoText = [iso stringFromDate:date];
    iso.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    NSDate *isoParsed = [iso dateFromString:@"2024-03-10T06:30:15.125Z"];
    iso.formatOptions = NSISO8601DateFormatWithFullDate;
    say([NSString stringWithFormat:@"iso: %@, parsed %.3f, date only %@, bad %@", isoText, isoParsed.timeIntervalSince1970,
         [iso stringFromDate:date], [iso dateFromString:@"yesterday"]]);
}

static void numberFormatters(void) {
    NSNumber *number = @1234567.891;
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *identifier in @[@"en_US", @"de_DE", @"fr_FR", @"ja_JP", @"en_IN"]) {
        NSNumberFormatter *formatter = [NSNumberFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:identifier];
        NSMutableArray *forms = [NSMutableArray array];
        for (NSNumber *style in @[@(NSNumberFormatterDecimalStyle), @(NSNumberFormatterCurrencyStyle),
                                  @(NSNumberFormatterPercentStyle), @(NSNumberFormatterScientificStyle)]) {
            formatter.numberStyle = style.unsignedIntegerValue;
            [forms addObject:[formatter stringFromNumber:style.integerValue == NSNumberFormatterPercentStyle ? @0.256 : number]];
        }
        [lines addObject:[NSString stringWithFormat:@"%@: %@", identifier, [forms componentsJoinedByString:@" | "]]];
    }
    for (NSString *line in lines) say(line);

    NSNumberFormatter *formatter = [NSNumberFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    say([NSString stringWithFormat:@"plain: %@ %@ %@", [formatter stringFromNumber:@1234.5678],
         [formatter stringFromNumber:@-42], [formatter stringFromNumber:@0.5]]);
    formatter.numberStyle = NSNumberFormatterSpellOutStyle;
    NSString *spelled = [formatter stringFromNumber:@1234];
    formatter.numberStyle = NSNumberFormatterOrdinalStyle;
    NSString *ordinals = [NSString stringWithFormat:@"%@ %@ %@ %@", [formatter stringFromNumber:@1], [formatter stringFromNumber:@2],
                          [formatter stringFromNumber:@3], [formatter stringFromNumber:@11]];
    formatter.numberStyle = NSNumberFormatterCurrencyISOCodeStyle;
    formatter.currencyCode = @"EUR";
    NSString *iso = [formatter stringFromNumber:@9.99];
    formatter.numberStyle = NSNumberFormatterCurrencyAccountingStyle;
    formatter.currencyCode = @"USD";
    say([NSString stringWithFormat:@"spelled: %@; ordinal %@; %@; accounting %@", spelled, ordinals, iso,
         [formatter stringFromNumber:@-5.5]]);

    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.minimumFractionDigits = 2;
    formatter.maximumFractionDigits = 2;
    NSString *fixed = [formatter stringFromNumber:@3.14159];
    formatter.maximumFractionDigits = 0;
    formatter.minimumFractionDigits = 0;
    formatter.roundingMode = NSNumberFormatterRoundHalfEven;
    NSString *even = [NSString stringWithFormat:@"%@ %@", [formatter stringFromNumber:@2.5], [formatter stringFromNumber:@3.5]];
    formatter.roundingMode = NSNumberFormatterRoundUp;
    NSString *up = [formatter stringFromNumber:@2.1];
    formatter.usesGroupingSeparator = NO;
    formatter.minimumIntegerDigits = 6;
    NSString *padded = [formatter stringFromNumber:@1234];
    say([NSString stringWithFormat:@"digits: %@, half even %@, up %@, padded %@", fixed, even, up, padded]);

    NSNumberFormatter *parser = [NSNumberFormatter new];
    parser.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    parser.numberStyle = NSNumberFormatterDecimalStyle;
    NSNumber *parsed = [parser numberFromString:@"1,234.5"];
    NSNumberFormatter *germanParser = [NSNumberFormatter new];
    germanParser.locale = [NSLocale localeWithLocaleIdentifier:@"de_DE"];
    germanParser.numberStyle = NSNumberFormatterDecimalStyle;
    say([NSString stringWithFormat:@"parse: %@ %@ %@, separators '%@' '%@', style pattern %@", parsed,
         [germanParser numberFromString:@"1.234,5"], [parser numberFromString:@"abc"], germanParser.decimalSeparator,
         germanParser.groupingSeparator, parser.positiveFormat]);
    say([NSString stringWithFormat:@"class: %@", [NSNumberFormatter localizedStringFromNumber:@0.75
                                                  numberStyle:NSNumberFormatterNoStyle]]);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        timeZones();
        locales();
        calendars();
        dateFormatters();
        numberFormatters();
    }
    return 0;
}
