// Formatters, units and measurements, built on a Mac with Xcode: number
// formatter edge cases (nil, NaN and infinity symbols, bounds, rounding
// behavior, the legacy format, attributed strings), relative dates, byte
// counts, the newer unit classes and their conversions, and measurement
// formatting in en_US. Prints to stdout so the test can compare exact text.
#import <Foundation/Foundation.h>
#import <objc/message.h>

static void print(NSString *line) {
    printf("%s\n", line.UTF8String);
}

static NSString *text(id object) {
    if (object == nil) return @"(nil)";
    if ([object isKindOfClass:[NSAttributedString class]]) return [NSString stringWithFormat:@"«%@»", [object string]];
    return [object description];
}

static id get(id object, NSString *name) {
    return ((id (*)(id, SEL))objc_msgSend)(object, NSSelectorFromString(name));
}

static BOOL getBool(id object, NSString *name) {
    return ((BOOL (*)(id, SEL))objc_msgSend)(object, NSSelectorFromString(name));
}

// The 10.0-era number formatter properties aren't in iOS's headers, but
// NSNumberFormatter answers them there too.
static void set(id object, NSString *name, id value) {
    ((void (*)(id, SEL, id))objc_msgSend)(object, NSSelectorFromString(name), value);
}

static void setBool(id object, NSString *name, BOOL value) {
    ((void (*)(id, SEL, BOOL))objc_msgSend)(object, NSSelectorFromString(name), value);
}

static NSLocale *us(void) { return [NSLocale localeWithLocaleIdentifier:@"en_US"]; }

static NSNumberFormatter *numbers(NSNumberFormatterStyle style) {
    NSNumberFormatter *formatter = [NSNumberFormatter new];
    formatter.locale = us();
    formatter.numberStyle = style;
    return formatter;
}

static NSDateFormatter *dates(void) {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = us();
    formatter.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
    return formatter;
}

static NSString *seconds(NSDate *date) {
    return date ? [NSString stringWithFormat:@"%.0f", date.timeIntervalSince1970] : @"(nil)";
}

// A formatter that turns partial strings into upper case: the default
// -isPartialStringValid:proposedSelectedRange:... asks it.
@interface GaugeUpperFormatter : NSFormatter
@end

@implementation GaugeUpperFormatter
- (NSString *)stringForObjectValue:(id)value { return [value description]; }
- (BOOL)getObjectValue:(id *)value forString:(NSString *)string errorDescription:(NSString **)error {
    *value = string;
    return YES;
}
- (BOOL)isPartialStringValid:(NSString *)partial newEditingString:(NSString **)replacement errorDescription:(NSString **)error {
    if ([partial isEqualToString:partial.uppercaseString]) return YES;
    *replacement = partial.uppercaseString;
    return NO;
}
@end

static void numberFormatters(void) {
    NSNumber *noNumber = nil;
    NSString *noString = nil;
    NSNumberFormatter *f = numbers(NSNumberFormatterDecimalStyle);
    print([NSString stringWithFormat:@"symbols nil=[%@] nan=[%@] +inf=[%@] -inf=[%@] permill=[%@] exp=[%@] intl=[%@] cds=[%@] cgs=[%@]",
           f.nilSymbol, f.notANumberSymbol, f.positiveInfinitySymbol, f.negativeInfinitySymbol, f.perMillSymbol,
           f.exponentSymbol, f.internationalCurrencySymbol, f.currencyDecimalSeparator, f.currencyGroupingSeparator]);
    print([NSString stringWithFormat:@"legacy thousand=[%@] has=%d localizes=%d format=[%@]",
           get(f, @"thousandSeparator"), getBool(f, @"hasThousandSeparators"), getBool(f, @"localizesFormat"), get(f, @"format")]);
    print([NSString stringWithFormat:@"defaults min=%@ max=%@ context=%ld partial=%d",
           text(f.minimum), text(f.maximum), (long)f.formattingContext, f.isPartialStringValidationEnabled]);
    print([NSString stringWithFormat:@"attributed nil=%@ nan=%@ zero=%@", text(get(f, @"attributedStringForNil")),
           text(get(f, @"attributedStringForNotANumber")), text(get(f, @"attributedStringForZero"))]);
    print([NSString stringWithFormat:@"text attributes %@ %@ %@", text(f.textAttributesForPositiveValues),
           text(f.textAttributesForNil), text(f.textAttributesForNegativeInfinity)]);
    print([NSString stringWithFormat:@"format nan=[%@] inf=[%@] -inf=[%@] nil=%@ object nil=[%@] string=%@",
           [f stringFromNumber:@(NAN)], [f stringFromNumber:@(INFINITY)], [f stringFromNumber:@(-INFINITY)],
           text([f stringFromNumber:noNumber]), [f stringForObjectValue:nil], text([f stringForObjectValue:@"x"])]);

    f.nilSymbol = @"<nil>";
    f.notANumberSymbol = @"NotNum";
    f.positiveInfinitySymbol = @"PosInf";
    f.negativeInfinitySymbol = @"NegInf";
    print([NSString stringWithFormat:@"custom nan=[%@] inf=[%@] -inf=[%@] nil=[%@] attributed nil=%@ nan=%@",
           [f stringFromNumber:@(NAN)], [f stringFromNumber:@(INFINITY)], [f stringFromNumber:@(-INFINITY)],
           [f stringForObjectValue:nil], text(get(f, @"attributedStringForNil")), text(get(f, @"attributedStringForNotANumber"))]);
    print([NSString stringWithFormat:@"parse NotNum=%@ PosInf=%@ NegInf=%@ 1,234.5=%@", text([f numberFromString:@"NotNum"]),
           text([f numberFromString:@"PosInf"]), text([f numberFromString:@"NegInf"]), text([f numberFromString:@"1,234.5"])]);
    set(f, @"setAttributedStringForZero:", [[NSAttributedString alloc] initWithString:@"zip"]);
    set(f, @"setAttributedStringForNil:", [[NSAttributedString alloc] initWithString:@"NIL!"]);
    set(f, @"setAttributedStringForNotANumber:", [[NSAttributedString alloc] initWithString:@"NAN!"]);
    print([NSString stringWithFormat:@"attributed set zero=[%@] zeroSymbol=%@ nil=[%@] nilSymbol=%@ nan=[%@] nanSymbol=%@",
           [f stringFromNumber:@0], f.zeroSymbol, [f stringForObjectValue:nil], f.nilSymbol, [f stringFromNumber:@(NAN)],
           f.notANumberSymbol]);
    f.zeroSymbol = @"none";
    print([NSString stringWithFormat:@"zero symbol attributed=%@", text(get(f, @"attributedStringForZero"))]);
    f.notANumberSymbol = noString;
    f.positiveInfinitySymbol = noString;
    print([NSString stringWithFormat:@"reset nan=%@ [%@] inf=%@ [%@]", f.notANumberSymbol, [f stringFromNumber:@(NAN)],
           text(f.positiveInfinitySymbol), [f stringFromNumber:@(INFINITY)]]);

    NSNumberFormatter *bounded = numbers(NSNumberFormatterDecimalStyle);
    bounded.minimum = @0;
    bounded.maximum = @1000;
    print([NSString stringWithFormat:@"bounds 50=%@ 1500=%@ -1=%@ format 1500=[%@] min=%@ max=%@",
           text([bounded numberFromString:@"50"]), text([bounded numberFromString:@"1500"]),
           text([bounded numberFromString:@"-1"]), [bounded stringFromNumber:@1500], bounded.minimum, bounded.maximum]);
    for (NSString *string in @[@"1500.5", @"-1,234", @"abc", @"999"]) {
        id value = nil;
        NSString *error = nil;
        BOOL ok = [bounded getObjectValue:&value forString:string errorDescription:&error];
        print([NSString stringWithFormat:@"get %@ ok=%d value=%@ error=%@", string, ok, text(value), text(error)]);
    }
    NSArray *ranged = @[@[@"42 apples", @0, @6], @[@"x  12.5y", @3, @6], @[@"abc", @0, @3], @[@"5000", @0, @4]];
    for (NSArray *entry in ranged) {
        NSRange range = NSMakeRange([entry[1] unsignedIntegerValue], [entry[2] unsignedIntegerValue]);
        id value = nil;
        NSError *error = nil;
        BOOL ok = [bounded getObjectValue:&value forString:entry[0] range:&range error:&error];
        print([NSString stringWithFormat:@"range [%@] ok=%d value=%@ range=%lu,%lu error=%@ %ld %@", entry[0], ok, text(value),
               (unsigned long)range.location, (unsigned long)range.length, text(error.localizedDescription), (long)error.code,
               text(error.domain)]);
    }

    for (NSNumberFormatterStyle style = NSNumberFormatterDecimalStyle; style <= NSNumberFormatterPercentStyle; style++) {
        NSNumberFormatter *styled = numbers(style);
        print([NSString stringWithFormat:@"style %lu format=[%@] positive=[%@] negative=[%@]", (unsigned long)style,
               get(styled, @"format"), styled.positiveFormat, styled.negativeFormat]);
    }
    for (NSString *format in @[@"0.0", @"0.0;-0.00", @"#,##0.00;zero;(#,##0.00)", @"0;;-0", @"0.00;0", @"0%;nil;-0%", @"$#,##0.00"]) {
        NSNumberFormatter *legacy = numbers(NSNumberFormatterDecimalStyle);
        set(legacy, @"setFormat:", format);
        print([NSString stringWithFormat:@"set [%@] format=[%@] positive=[%@] negative=[%@] zero=[%@] | %@ %@ %@", format,
               get(legacy, @"format"), legacy.positiveFormat, legacy.negativeFormat, legacy.zeroSymbol, [legacy stringFromNumber:@1234.5],
               [legacy stringFromNumber:@0], [legacy stringFromNumber:@-7]]);
    }
    NSNumberFormatter *zeroed = numbers(NSNumberFormatterDecimalStyle);
    zeroed.zeroSymbol = @"Z";
    zeroed.positiveFormat = @"0.0";
    print([NSString stringWithFormat:@"zero symbol format=[%@]", get(zeroed, @"format")]);

    NSNumberFormatter *grouped = numbers(NSNumberFormatterDecimalStyle);
    set(grouped, @"setThousandSeparator:", @"'");
    print([NSString stringWithFormat:@"thousand [%@] grouping=[%@] has=%d uses=%d %@", get(grouped, @"thousandSeparator"),
           grouped.groupingSeparator, getBool(grouped, @"hasThousandSeparators"), grouped.usesGroupingSeparator,
           [grouped stringFromNumber:@1234567]]);
    setBool(grouped, @"setHasThousandSeparators:", NO);
    print([NSString stringWithFormat:@"no thousands has=%d uses=%d %@", getBool(grouped, @"hasThousandSeparators"),
           grouped.usesGroupingSeparator, [grouped stringFromNumber:@1234567]]);
    setBool(grouped, @"setLocalizesFormat:", NO);
    print([NSString stringWithFormat:@"localizes=%d", getBool(grouped, @"localizesFormat")]);
    SEL minimumGrouping = NSSelectorFromString(@"setMinimumGroupingDigits:");
    ((void (*)(id, SEL, NSInteger))objc_msgSend)(grouped, minimumGrouping, 2);
    setBool(grouped, @"setHasThousandSeparators:", YES);
    print([NSString stringWithFormat:@"grouping digits %ld %@ %@",
           (long)((NSInteger (*)(id, SEL))objc_msgSend)(grouped, NSSelectorFromString(@"minimumGroupingDigits")),
           [grouped stringFromNumber:@1234], [grouped stringFromNumber:@12345]]);

    NSNumberFormatter *scientific = numbers(NSNumberFormatterScientificStyle);
    scientific.exponentSymbol = @"x10^";
    NSNumberFormatter *mill = numbers(NSNumberFormatterPercentStyle);
    mill.positiveFormat = @"#0‰";
    mill.perMillSymbol = @"pm";
    NSNumberFormatter *iso = numbers(NSNumberFormatterCurrencyISOCodeStyle);
    iso.internationalCurrencySymbol = @"XYZ";
    NSNumberFormatter *currency = numbers(NSNumberFormatterCurrencyStyle);
    currency.currencyDecimalSeparator = @"_";
    currency.currencyGroupingSeparator = @"~";
    print([NSString stringWithFormat:@"symbols set %@ %@ %@ %@ %@ %@ decimal=%@", [scientific stringFromNumber:@12345],
           [mill stringFromNumber:@0.5], [iso stringFromNumber:@1234.5], [currency stringFromNumber:@1234567.5],
           currency.currencyDecimalSeparator, currency.currencyGroupingSeparator, currency.decimalSeparator]);

    for (NSUInteger mode = NSRoundPlain; mode <= NSRoundBankers; mode++) {
        NSNumberFormatter *rounding = numbers(NSNumberFormatterDecimalStyle);
        rounding.maximumFractionDigits = 1;
        set(rounding, @"setRoundingBehavior:", [NSDecimalNumberHandler decimalNumberHandlerWithRoundingMode:mode scale:1 raiseOnExactness:NO
                                                                                 raiseOnOverflow:NO raiseOnUnderflow:NO
                                                                              raiseOnDivideByZero:NO]);
        NSDecimalNumberHandler *handler = (NSDecimalNumberHandler *)get(rounding, @"roundingBehavior");
        print([NSString stringWithFormat:@"rounding behavior %lu mode=%lu handler=%lu scale=%d 2.25=%@ 2.35=%@ -2.25=%@",
               (unsigned long)mode, (unsigned long)rounding.roundingMode, (unsigned long)handler.roundingMode,
               handler.scale, [rounding stringFromNumber:@2.25], [rounding stringFromNumber:@2.35],
               [rounding stringFromNumber:@-2.25]]);
    }
    for (NSNumberFormatterRoundingMode mode = NSNumberFormatterRoundCeiling; mode <= NSNumberFormatterRoundHalfUp; mode++) {
        NSNumberFormatter *rounding = numbers(NSNumberFormatterDecimalStyle);
        rounding.roundingMode = mode;
        print([NSString stringWithFormat:@"rounding mode %lu handler=%lu", (unsigned long)mode,
               (unsigned long)((NSDecimalNumberHandler *)get(rounding, @"roundingBehavior")).roundingMode]);
    }
    NSNumberFormatter *context = numbers(NSNumberFormatterDecimalStyle);
    context.formattingContext = NSFormattingContextBeginningOfSentence;
    context.partialStringValidationEnabled = YES;
    print([NSString stringWithFormat:@"context=%ld partial=%d", (long)context.formattingContext,
           context.isPartialStringValidationEnabled]);

    NSNumberFormatter *styledText = numbers(NSNumberFormatterDecimalStyle);
    styledText.textAttributesForNegativeValues = @{@"color": @"red"};
    styledText.textAttributesForZero = @{@"color": @"gray"};
    for (NSNumber *number in @[@5, @0, @-5]) {
        NSAttributedString *styledString = [styledText attributedStringForObjectValue:number withDefaultAttributes:@{@"font": @"body"}];
        NSDictionary *attributes = [styledString attributesAtIndex:0 effectiveRange:NULL];
        print([NSString stringWithFormat:@"attributed %@ = [%@] color=%@ font=%@ count=%lu", number, styledString.string,
               text(attributes[@"color"]), text(attributes[@"font"]), (unsigned long)attributes.count]);
    }
    print([NSString stringWithFormat:@"text attributes negative color=%@", styledText.textAttributesForNegativeValues[@"color"]]);
}

static void dateFormatters(void) {
    NSDateFormatter *f = dates();
    print([NSString stringWithFormat:@"date defaults relative=%d default=%@ twoDigit=%@ gregorian=%@ calendarDates=%d context=%ld",
           f.doesRelativeDateFormatting, seconds(f.defaultDate), seconds(f.twoDigitStartDate), seconds(f.gregorianStartDate),
           f.generatesCalendarDates, (long)f.formattingContext]);
    NSDate *now = [NSDate date];
    NSDate *yesterday = [now dateByAddingTimeInterval:-86400];
    NSDate *tomorrow = [now dateByAddingTimeInterval:86400];
    NSDate *later = [now dateByAddingTimeInterval:3 * 86400];
    f.doesRelativeDateFormatting = YES;
    for (NSDateFormatterStyle style = NSDateFormatterShortStyle; style <= NSDateFormatterFullStyle; style++) {
        f.dateStyle = style;
        print([NSString stringWithFormat:@"relative %lu: %@ %@ %@ later relative=%d format=%@", (unsigned long)style,
               [f stringFromDate:now], [f stringFromDate:yesterday], [f stringFromDate:tomorrow],
               [@[@"Today", @"Yesterday", @"Tomorrow"] containsObject:[f stringFromDate:later]], f.dateFormat]);
    }
    f.dateStyle = NSDateFormatterMediumStyle;
    f.timeStyle = NSDateFormatterShortStyle;
    print([NSString stringWithFormat:@"relative with time: %d", [[f stringFromDate:now] hasPrefix:@"Today at "]]);
    f.timeStyle = NSDateFormatterNoStyle;
    for (NSInteger context = 0; context <= 5; context++) {
        f.formattingContext = context;
        print([NSString stringWithFormat:@"relative context %ld: %@ %@", (long)context, [f stringFromDate:yesterday],
               [f stringFromDate:now]]);
    }
    NSDateFormatter *french = dates();
    french.locale = [NSLocale localeWithLocaleIdentifier:@"fr_FR"];
    french.dateStyle = NSDateFormatterLongStyle;
    french.doesRelativeDateFormatting = YES;
    print([NSString stringWithFormat:@"french %@ %@ %@", [french stringFromDate:now], [french stringFromDate:yesterday],
           [french stringFromDate:tomorrow]]);
    french.formattingContext = NSFormattingContextBeginningOfSentence;
    print([NSString stringWithFormat:@"french beginning %@", [french stringFromDate:now]]);

    NSDate *fixed = [NSDate dateWithTimeIntervalSince1970:1000000000];
    NSDateFormatter *formatted = dates();
    formatted.dateStyle = NSDateFormatterMediumStyle;
    formatted.doesRelativeDateFormatting = YES;
    formatted.dateFormat = @"yyyy";
    print([NSString stringWithFormat:@"relative with format: %@ format=%@ relative=%d", [formatted stringFromDate:fixed],
           formatted.dateFormat, formatted.doesRelativeDateFormatting]);

    NSDateFormatter *years = dates();
    years.dateFormat = @"yy-MM-dd";
    print([NSString stringWithFormat:@"two digit 49=%@ 51=%@", seconds([years dateFromString:@"49-01-01"]),
           seconds([years dateFromString:@"51-01-01"])]);
    years.twoDigitStartDate = [NSDate dateWithTimeIntervalSince1970:0];
    print([NSString stringWithFormat:@"two digit from 1970: start=%@ 49=%@ 69=%@ 71=%@", seconds(years.twoDigitStartDate),
           seconds([years dateFromString:@"49-01-01"]), seconds([years dateFromString:@"69-01-01"]),
           seconds([years dateFromString:@"71-01-01"])]);
    NSDateFormatter *partial = dates();
    partial.dateFormat = @"HH:mm";
    print([NSString stringWithFormat:@"no default date %@", seconds([partial dateFromString:@"10:30"])]);
    partial.defaultDate = fixed;
    print([NSString stringWithFormat:@"default date %@ %@", seconds(partial.defaultDate), seconds([partial dateFromString:@"10:30"])]);
    partial.dateFormat = @"MM-dd";
    print([NSString stringWithFormat:@"default date month %@", seconds([partial dateFromString:@"03-04"])]);
    partial.gregorianStartDate = [NSDate dateWithTimeIntervalSince1970:0];
    partial.generatesCalendarDates = YES;
    print([NSString stringWithFormat:@"gregorian=%@ calendarDates=%d", seconds(partial.gregorianStartDate),
           partial.generatesCalendarDates]);

    NSDateFormatter *symbols = dates();
    print([NSString stringWithFormat:@"symbols %@ | %@ | %@ | %@ | %@",
           [symbols.shortStandaloneQuarterSymbols componentsJoinedByString:@","],
           [symbols.shortStandaloneWeekdaySymbols componentsJoinedByString:@","],
           [symbols.standaloneQuarterSymbols componentsJoinedByString:@","],
           [symbols.veryShortStandaloneMonthSymbols componentsJoinedByString:@","],
           [symbols.veryShortStandaloneWeekdaySymbols componentsJoinedByString:@","]]);
    symbols.monthSymbols = @[@"Jan1", @"Feb2", @"Mar3", @"Apr4", @"May5", @"Jun6", @"Jul7", @"Aug8", @"Sep9", @"Oct10",
                             @"Nov11", @"Dec12"];
    symbols.shortWeekdaySymbols = @[@"Su", @"Mo", @"Tu", @"We", @"Th", @"Fr", @"Sa"];
    symbols.eraSymbols = @[@"bce", @"ce"];
    symbols.dateFormat = @"EEE, d MMMM y G";
    print([NSString stringWithFormat:@"custom symbols %@ first=%@ parsed=%@", [symbols stringFromDate:fixed],
           symbols.monthSymbols.firstObject, seconds([symbols dateFromString:@"Su, 9 Sep9 2001 ce"])]);
    symbols.quarterSymbols = @[@"Q-one", @"Q-two", @"Q-three", @"Q-four"];
    symbols.dateFormat = @"QQQQ";
    print([NSString stringWithFormat:@"custom quarter %@", [symbols stringFromDate:fixed]]);
    symbols.monthSymbols = nil;
    print([NSString stringWithFormat:@"reset month %@", symbols.monthSymbols.firstObject]);

    NSDateFormatter *parser = dates();
    parser.dateFormat = @"yyyy-MM-dd";
    NSRange range = NSMakeRange(2, 12);
    id value = nil;
    NSError *error = nil;
    BOOL ok = [parser getObjectValue:&value forString:@"x 2001-09-09 tail" range:&range error:&error];
    print([NSString stringWithFormat:@"date range ok=%d value=%@ range=%lu,%lu", ok, seconds(value), (unsigned long)range.location,
           (unsigned long)range.length]);
    range = NSMakeRange(0, 5);
    ok = [parser getObjectValue:&value forString:@"hello" range:&range error:&error];
    print([NSString stringWithFormat:@"date range bad ok=%d range=%lu,%lu error=%@ %ld", ok, (unsigned long)range.location,
           (unsigned long)range.length, error.localizedDescription, (long)error.code]);
    NSString *description = nil;
    ok = [parser getObjectValue:&value forString:@"bogus" errorDescription:&description];
    print([NSString stringWithFormat:@"date error description ok=%d %@", ok, description]);

    NSISO8601DateFormatter *iso = [NSISO8601DateFormatter new];
    value = nil;
    ok = [iso getObjectValue:&value forString:@"2001-09-09T01:46:40Z" errorDescription:NULL];
    print([NSString stringWithFormat:@"iso get ok=%d %@", ok, seconds(value)]);
}

static void byteCounts(void) {
    static long long counts[] = {0, 1, 999, 1000, 1023, 1024, 1500, 2500, 99999, 999499, 999500, 999999, 1048575, 1234567,
                                 1250000, 1135000000, 999999999999LL, 1234567890123LL, 1234567890123456789LL, -1, -1234567};
    for (NSByteCountFormatterCountStyle style = NSByteCountFormatterCountStyleFile; style <= NSByteCountFormatterCountStyleBinary; style++) {
        NSMutableString *line = [NSMutableString stringWithFormat:@"bytes style %ld:", (long)style];
        for (size_t i = 0; i < sizeof counts / sizeof *counts; i++) {
            [line appendFormat:@" [%@]", [NSByteCountFormatter stringFromByteCount:counts[i] countStyle:style]];
        }
        print(line);
    }
    NSByteCountFormatter *f = [NSByteCountFormatter new];
    print([NSString stringWithFormat:@"bytes defaults units=%lu style=%ld nonnumeric=%d unit=%d count=%d actual=%d adaptive=%d zeropad=%d context=%ld",
           (unsigned long)f.allowedUnits, (long)f.countStyle, f.allowsNonnumericFormatting, f.includesUnit, f.includesCount,
           f.includesActualByteCount, f.isAdaptive, f.zeroPadsFractionDigits, (long)f.formattingContext]);
    void (^row)(NSString *) = ^(NSString *label) {
        NSMutableString *line = [NSMutableString stringWithString:label];
        for (size_t i = 0; i < sizeof counts / sizeof *counts; i++) [line appendFormat:@" [%@]", [f stringFromByteCount:counts[i]]];
        print(line);
    };
    f.includesActualByteCount = YES; row(@"actual:");
    f.includesActualByteCount = NO; f.zeroPadsFractionDigits = YES; row(@"zero pads:");
    f.zeroPadsFractionDigits = NO; f.adaptive = NO; row(@"not adaptive:");
    f.adaptive = YES; f.allowedUnits = NSByteCountFormatterUseMB; row(@"MB:");
    f.allowedUnits = NSByteCountFormatterUseKB | NSByteCountFormatterUseGB; row(@"KB GB:");
    f.allowedUnits = NSByteCountFormatterUseBytes; row(@"bytes only:");
    f.allowedUnits = NSByteCountFormatterUseBytes | NSByteCountFormatterUseMB; row(@"bytes MB:");
    f.allowedUnits = NSByteCountFormatterUseDefault; f.allowsNonnumericFormatting = NO; row(@"numeric:");
    f.allowsNonnumericFormatting = YES; f.includesUnit = NO; row(@"no unit:");
    f.includesUnit = YES; f.includesCount = NO; row(@"no count:");
    f.includesCount = YES; f.countStyle = NSByteCountFormatterCountStyleMemory; f.includesActualByteCount = YES; row(@"memory actual:");
    f.includesActualByteCount = NO; f.countStyle = NSByteCountFormatterCountStyleFile;
    f.formattingContext = NSFormattingContextBeginningOfSentence;
    print([NSString stringWithFormat:@"bytes context=%ld %@", (long)f.formattingContext, [f stringFromByteCount:1234567]]);
    f.formattingContext = NSFormattingContextUnknown;
    NSMeasurement *megabytes = [[NSMeasurement alloc] initWithDoubleValue:1.5 unit:NSUnitInformationStorage.megabytes];
    NSMeasurement *gibibits = [[NSMeasurement alloc] initWithDoubleValue:3 unit:NSUnitInformationStorage.gibibits];
    NSMeasurement *bits = [[NSMeasurement alloc] initWithDoubleValue:12 unit:NSUnitInformationStorage.bits];
    print([NSString stringWithFormat:@"bytes measurements %@ %@ %@ %@ %@", [f stringFromMeasurement:megabytes],
           [f stringFromMeasurement:gibibits], [NSByteCountFormatter stringFromMeasurement:megabytes countStyle:NSByteCountFormatterCountStyleBinary],
           [NSByteCountFormatter stringFromMeasurement:bits countStyle:NSByteCountFormatterCountStyleFile], [f stringForObjectValue:megabytes]]);
    id value = nil;
    print([NSString stringWithFormat:@"bytes object %@ %@ get=%d", [f stringForObjectValue:@1234567], text([f stringForObjectValue:@"x"]),
           [f getObjectValue:&value forString:@"1 KB" errorDescription:NULL]]);
}

static NSString *unitLine(Class cls, NSString *selector) {
    NSUnit *unit = ((id (*)(id, SEL))objc_msgSend)(cls, NSSelectorFromString(selector));
    NSDimension *base = [(id)cls baseUnit];
    NSMeasurement *one = [[NSMeasurement alloc] initWithDoubleValue:1 unit:unit];
    NSMeasurement *inBase = [one measurementByConvertingToUnit:base];
    NSMeasurement *back = [[[NSMeasurement alloc] initWithDoubleValue:2 unit:base] measurementByConvertingToUnit:(NSDimension *)unit];
    return [NSString stringWithFormat:@"%@ %@ = %.10g %@, 2 %@ = %.10g", selector, unit.symbol, inBase.doubleValue, base.symbol,
            base.symbol, back.doubleValue];
}

static void units(void) {
    NSDictionary<NSString *, NSArray<NSString *> *> *classes = @{
        @"NSUnitDispersion": @[@"partsPerMillion"],
        @"NSUnitElectricCharge": @[@"coulombs", @"megaampereHours", @"kiloampereHours", @"ampereHours", @"milliampereHours",
                                   @"microampereHours"],
        @"NSUnitElectricCurrent": @[@"megaamperes", @"kiloamperes", @"amperes", @"milliamperes", @"microamperes"],
        @"NSUnitElectricResistance": @[@"megaohms", @"kiloohms", @"ohms", @"milliohms", @"microohms"],
        @"NSUnitFuelEfficiency": @[@"litersPer100Kilometers", @"milesPerGallon", @"milesPerImperialGallon"],
        @"NSUnitIlluminance": @[@"lux"],
        @"NSUnitInformationStorage": @[@"bytes", @"bits", @"nibbles", @"yottabytes", @"zettabytes", @"exabytes", @"petabytes",
                                       @"terabytes", @"gigabytes", @"megabytes", @"kilobytes", @"yottabits", @"zettabits",
                                       @"exabits", @"petabits", @"terabits", @"gigabits", @"megabits", @"kilobits", @"yobibytes",
                                       @"zebibytes", @"exbibytes", @"pebibytes", @"tebibytes", @"gibibytes", @"mebibytes",
                                       @"kibibytes", @"yobibits", @"zebibits", @"exbibits", @"pebibits", @"tebibits", @"gibibits",
                                       @"mebibits", @"kibibits"],
        @"NSUnitVolume": @[@"acreFeet", @"bushels", @"cubicDecimeters", @"cubicKilometers", @"cubicMiles", @"cubicMillimeters",
                           @"cubicYards", @"imperialFluidOunces", @"imperialGallons", @"imperialPints", @"imperialQuarts",
                           @"imperialTablespoons", @"imperialTeaspoons", @"metricCups"],
        @"NSUnitArea": @[@"squareMicrometers", @"squareNanometers", @"acres", @"squareFeet", @"squareMiles"],
        @"NSUnitAngle": @[@"arcMinutes", @"arcSeconds", @"radians"],
        @"NSUnitLength": @[@"fathoms", @"furlongs", @"astronomicalUnits"],
        @"NSUnitTemperature": @[@"celsius", @"fahrenheit"],
        @"NSUnitSpeed": @[@"kilometersPerHour", @"knots"],
    };
    for (NSString *name in [classes.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        Class cls = NSClassFromString(name);
        print([NSString stringWithFormat:@"%@ base %@ dimension=%d", name, ((NSDimension *)[(id)cls baseUnit]).symbol,
               [cls isSubclassOfClass:[NSDimension class]]]);
        for (NSString *selector in classes[name]) print(unitLine(cls, selector));
    }
    NSUnitFuelEfficiency *mpg = NSUnitFuelEfficiency.milesPerGallon;
    NSMeasurement *thirty = [[NSMeasurement alloc] initWithDoubleValue:30 unit:mpg];
    print([NSString stringWithFormat:@"fuel 30 mpg = %.6f L/100km = %.6f UK mpg converter=%@ reciprocal=%.3f linear=%d",
           [thirty measurementByConvertingToUnit:NSUnitFuelEfficiency.litersPer100Kilometers].doubleValue,
           [thirty measurementByConvertingToUnit:NSUnitFuelEfficiency.milesPerImperialGallon].doubleValue,
           NSStringFromClass([mpg.converter class]), ((double (*)(id, SEL))objc_msgSend)(mpg.converter, NSSelectorFromString(@"reciprocalValue")),
           [NSUnitFuelEfficiency.litersPer100Kilometers.converter isKindOfClass:[NSUnitConverterLinear class]]]);
    id reciprocal = ((id (*)(id, SEL, double))objc_msgSend)([NSClassFromString(@"NSUnitConverterReciprocal") alloc],
                                                           NSSelectorFromString(@"initWithReciprocalValue:"), 100);
    id same = ((id (*)(id, SEL, double))objc_msgSend)([NSClassFromString(@"NSUnitConverterReciprocal") alloc],
                                                     NSSelectorFromString(@"initWithReciprocalValue:"), 100);
    print([NSString stringWithFormat:@"reciprocal 4 -> %g, 5 <- %g equal=%d", [reciprocal baseUnitValueFromValue:4],
           [reciprocal valueFromBaseUnitValue:5], [reciprocal isEqual:same]]);
    NSUnitConcentrationMass *glucose = [NSUnitConcentrationMass millimolesPerLiterWithGramsPerMole:180];
    print([NSString stringWithFormat:@"millimoles %@ coefficient=%g new=%d", glucose.symbol,
           ((NSUnitConverterLinear *)glucose.converter).coefficient,
           glucose != [NSUnitConcentrationMass millimolesPerLiterWithGramsPerMole:180]]);
    print([NSString stringWithFormat:@"shared %d equal %d", NSUnitElectricCurrent.amperes == [NSUnitElectricCurrent baseUnit],
           [NSUnitElectricCurrent.amperes isEqual:[[NSUnitElectricCurrent alloc] initWithSymbol:@"A"
                                                                                       converter:[[NSUnitConverterLinear alloc] initWithCoefficient:1]]]]);
}

static void measurementFormatters(void) {
    NSMeasurementFormatter *f = [NSMeasurementFormatter new];
    f.locale = us();
    f.unitOptions = NSMeasurementFormatterUnitOptionsProvidedUnit;
    NSArray<NSUnit *> *units = @[
        NSUnitDispersion.partsPerMillion, NSUnitElectricCharge.coulombs, NSUnitElectricCharge.milliampereHours,
        NSUnitElectricCurrent.amperes, NSUnitElectricCurrent.milliamperes, NSUnitElectricCurrent.kiloamperes,
        NSUnitElectricResistance.ohms, NSUnitElectricResistance.kiloohms, NSUnitFuelEfficiency.litersPer100Kilometers,
        NSUnitFuelEfficiency.milesPerGallon, NSUnitFuelEfficiency.milesPerImperialGallon, NSUnitIlluminance.lux,
        NSUnitInformationStorage.bytes, NSUnitInformationStorage.bits, NSUnitInformationStorage.kilobytes,
        NSUnitInformationStorage.gigabits, NSUnitInformationStorage.mebibytes, NSUnitVolume.imperialGallons,
        NSUnitVolume.imperialPints, NSUnitVolume.imperialFluidOunces, NSUnitVolume.metricCups, NSUnitVolume.acreFeet,
        NSUnitVolume.cubicDecimeters, NSUnitConcentrationMass.milligramsPerDeciliter, NSUnitLength.meters, NSUnitLength.feet,
        NSUnitLength.micrometers, NSUnitMass.poundsMass, NSUnitTemperature.celsius, NSUnitTemperature.fahrenheit,
        NSUnitAngle.degrees, NSUnitAcceleration.gravity, NSUnitArea.squareMicrometers, NSUnitDuration.minutes,
    ];
    for (NSUnit *unit in units) {
        NSMutableString *line = [NSMutableString stringWithString:unit.symbol];
        for (NSFormattingUnitStyle style = NSFormattingUnitStyleShort; style <= NSFormattingUnitStyleLong; style++) {
            f.unitStyle = style;
            [line appendFormat:@" | %@ / %@ / %@ / %@", [f stringFromUnit:unit],
             [f stringFromMeasurement:[[NSMeasurement alloc] initWithDoubleValue:1 unit:unit]],
             [f stringFromMeasurement:[[NSMeasurement alloc] initWithDoubleValue:2.5 unit:unit]],
             [f stringFromMeasurement:[[NSMeasurement alloc] initWithDoubleValue:-1234.5678 unit:unit]]];
        }
        print(line);
    }
    f.unitStyle = NSFormattingUnitStyleLong;
    NSUnit *widgets = [[NSUnit alloc] initWithSymbol:@"widgets"];
    NSUnitLength *meters = [[NSUnitLength alloc] initWithSymbol:@"m" converter:[[NSUnitConverterLinear alloc] initWithCoefficient:1]];
    print([NSString stringWithFormat:@"custom %@ %@ %@", [f stringFromMeasurement:[[NSMeasurement alloc] initWithDoubleValue:3 unit:widgets]],
           [f stringFromUnit:widgets], [f stringFromMeasurement:[[NSMeasurement alloc] initWithDoubleValue:3 unit:meters]]]);
    f.unitStyle = NSFormattingUnitStyleMedium;
    f.unitOptions = NSMeasurementFormatterUnitOptionsTemperatureWithoutUnit | NSMeasurementFormatterUnitOptionsProvidedUnit;
    print([NSString stringWithFormat:@"temperature without unit %@ %@",
           [f stringFromMeasurement:[[NSMeasurement alloc] initWithDoubleValue:20 unit:NSUnitTemperature.celsius]],
           [f stringFromMeasurement:[[NSMeasurement alloc] initWithDoubleValue:68 unit:NSUnitTemperature.fahrenheit]]]);
    f.unitOptions = 0;
    print([NSString stringWithFormat:@"default options %@ %@ %@",
           [f stringFromMeasurement:[[NSMeasurement alloc] initWithDoubleValue:3 unit:NSUnitElectricCurrent.amperes]],
           [f stringFromMeasurement:[[NSMeasurement alloc] initWithDoubleValue:1500 unit:NSUnitElectricResistance.ohms]],
           [f stringFromMeasurement:[[NSMeasurement alloc] initWithDoubleValue:2048 unit:NSUnitInformationStorage.bytes]]]);
}

static void otherFormatters(void) {
    NSDateComponents *components = [NSDateComponents new];
    components.hour = 1;
    components.minute = 2;
    components.second = 3;
    NSMutableString *line = [NSMutableString stringWithString:@"components"];
    for (NSDateComponentsFormatterUnitsStyle style = NSDateComponentsFormatterUnitsStylePositional;
         style <= NSDateComponentsFormatterUnitsStyleBrief; style++) {
        [line appendFormat:@" [%@]", [NSDateComponentsFormatter localizedStringFromDateComponents:components unitsStyle:style]];
    }
    print(line);
    NSLengthFormatter *length = [NSLengthFormatter new];
    id value = @"untouched";
    BOOL ok = [length getObjectValue:&value forString:@"5 m" errorDescription:NULL];
    print([NSString stringWithFormat:@"length get ok=%d value=%@", ok, text(value)]);

    GaugeUpperFormatter *upper = [GaugeUpperFormatter new];
    NSString *partial = @"abc";
    NSRange selection = NSMakeRange(1, 0);
    ok = [upper isPartialStringValid:&partial proposedSelectedRange:&selection originalString:@"ab"
               originalSelectedRange:NSMakeRange(2, 0) errorDescription:NULL];
    print([NSString stringWithFormat:@"partial ok=%d %@ selection=%lu,%lu attributed=%@", ok, partial,
           (unsigned long)selection.location, (unsigned long)selection.length,
           text([upper attributedStringForObjectValue:@1 withDefaultAttributes:nil])]);
    partial = @"ABC";
    ok = [upper isPartialStringValid:&partial proposedSelectedRange:&selection originalString:@"AB"
               originalSelectedRange:NSMakeRange(2, 0) errorDescription:NULL];
    print([NSString stringWithFormat:@"partial upper ok=%d %@", ok, partial]);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        numberFormatters();
        dateFormatters();
        byteCounts();
        units();
        measurementFormatters();
        otherFormatters();
    }
    return 0;
}
