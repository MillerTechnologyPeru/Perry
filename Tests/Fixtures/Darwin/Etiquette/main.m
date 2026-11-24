// Formatters for people and phrases, built on a Mac with Xcode: person
// names and their formatter, date intervals, relative dates, lists, masses
// and energies, in en_US and GMT at fixed dates. Spaces other than ASCII's
// print as <U+XXXX> so the expected output shows them. Prints to stdout so
// the test can compare exact text.
#import <Foundation/Foundation.h>

static void print(NSString *line) {
    NSMutableString *shown = [NSMutableString string];
    for (NSUInteger i = 0; i < line.length; i++) {
        unichar c = [line characterAtIndex:i];
        if (c == 0x00A0 || c == 0x202F || c == 0x2009 || c == 0x2007 || c == 0x200B || c == 0x200E || c == 0x200F) {
            [shown appendFormat:@"<U+%04X>", c];
        } else {
            [shown appendFormat:@"%C", c];
        }
    }
    printf("%s\n", shown.UTF8String);
}

static NSString *show(id object) { return object ? [object description] : @"(nil)"; }

static NSString *describeName(NSPersonNameComponents *name) {
    if (!name) return @"(nil)";
    return [NSString stringWithFormat:@"prefix=%@ given=%@ middle=%@ family=%@ suffix=%@ nickname=%@",
            show(name.namePrefix), show(name.givenName), show(name.middleName), show(name.familyName),
            show(name.nameSuffix), show(name.nickname)];
}

static NSPersonNameComponents *fullName(void) {
    NSPersonNameComponents *name = [[NSPersonNameComponents alloc] init];
    name.namePrefix = @"Dr.";
    name.givenName = @"Johnathan";
    name.middleName = @"Maple";
    name.familyName = @"Appleseed";
    name.nameSuffix = @"Jr.";
    name.nickname = @"Johnny";
    return name;
}

static void personNames(void) {
    NSPersonNameComponents *name = fullName();
    print([@"name: " stringByAppendingString:describeName(name)]);
    NSPersonNameComponents *copy = [name copy];
    print([NSString stringWithFormat:@"copy equal=%d", [copy isEqual:name]]);
    copy.nickname = @"Jack";
    print([NSString stringWithFormat:@"changed equal=%d original=%@", [copy isEqual:name], name.nickname]);
    NSPersonNameComponents *empty = [[NSPersonNameComponents alloc] init];
    print([NSString stringWithFormat:@"empty equal=%d hash-equal=%d", [empty isEqual:[[NSPersonNameComponents alloc] init]],
           empty.hash == [[NSPersonNameComponents alloc] init].hash]);

    NSPersonNameComponents *phonetic = [[NSPersonNameComponents alloc] init];
    phonetic.givenName = @"JON-uh-thun";
    phonetic.familyName = @"AP-ul-seed";
    name.phoneticRepresentation = phonetic;
    print([@"phonetic: " stringByAppendingString:describeName(name.phoneticRepresentation)]);

    NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:name requiringSecureCoding:YES error:nil];
    NSPersonNameComponents *unarchived = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSPersonNameComponents class]
                                                                           fromData:archive error:nil];
    print([NSString stringWithFormat:@"archived equal=%d phonetic=%@", [unarchived isEqual:name],
           unarchived.phoneticRepresentation.familyName]);

    NSPersonNameComponentsFormatter *formatter = [[NSPersonNameComponentsFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    print([NSString stringWithFormat:@"defaults style=%ld phonetic=%d", (long)formatter.style, formatter.isPhonetic]);
    NSPersonNameComponents *plain = [[NSPersonNameComponents alloc] init];
    plain.givenName = @"Kate";
    plain.familyName = @"Bell";
    NSPersonNameComponents *givenOnly = [[NSPersonNameComponents alloc] init];
    givenOnly.givenName = @"Cher";
    NSPersonNameComponents *nicknamed = [[NSPersonNameComponents alloc] init];
    nicknamed.givenName = @"Robert";
    nicknamed.familyName = @"Smith";
    nicknamed.nickname = @"Bob";
    NSPersonNameComponents *japanese = [[NSPersonNameComponents alloc] init];
    japanese.givenName = @"太郎";
    japanese.familyName = @"山田";
    NSPersonNameComponents *korean = [[NSPersonNameComponents alloc] init];
    korean.givenName = @"민준";
    korean.familyName = @"김";
    NSArray *names = @[name, plain, givenOnly, nicknamed, empty, japanese, korean];
    NSArray *styleNames = @[@"default", @"short", @"medium", @"long", @"abbreviated"];
    for (NSInteger style = 0; style <= 4; style++) {
        formatter.style = style;
        NSMutableArray *parts = [NSMutableArray array];
        for (NSPersonNameComponents *each in names) {
            [parts addObject:[NSString stringWithFormat:@"[%@]", [formatter stringFromPersonNameComponents:each]]];
        }
        print([NSString stringWithFormat:@"%@: %@", styleNames[style], [parts componentsJoinedByString:@" "]]);
    }
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"ja_JP"];
    for (NSInteger style = 0; style <= 4; style++) {
        formatter.style = style;
        print([NSString stringWithFormat:@"ja_JP %@: [%@] [%@]", styleNames[style], [formatter stringFromPersonNameComponents:name],
               [formatter stringFromPersonNameComponents:japanese]]);
    }
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    formatter.style = NSPersonNameComponentsFormatterStyleDefault;
    formatter.phonetic = YES;
    print([NSString stringWithFormat:@"phonetic default: [%@]", [formatter stringFromPersonNameComponents:name]]);
    formatter.phonetic = NO;
    print([NSString stringWithFormat:@"class medium: [%@]",
           [NSPersonNameComponentsFormatter localizedStringFromPersonNameComponents:plain
                                                                              style:NSPersonNameComponentsFormatterStyleMedium
                                                                            options:0]]);
    print([NSString stringWithFormat:@"class long phonetic: [%@]",
           [NSPersonNameComponentsFormatter localizedStringFromPersonNameComponents:name
                                                                              style:NSPersonNameComponentsFormatterStyleLong
                                                                            options:NSPersonNameComponentsFormatterPhonetic]]);

    formatter.style = NSPersonNameComponentsFormatterStyleLong;
    NSAttributedString *annotated = [formatter annotatedStringFromPersonNameComponents:name];
    NSMutableArray *runs = [NSMutableArray array];
    [annotated enumerateAttributesInRange:NSMakeRange(0, annotated.length) options:0
                               usingBlock:^(NSDictionary *attributes, NSRange range, BOOL *stop) {
        [runs addObject:[NSString stringWithFormat:@"%@=%@", [annotated.string substringWithRange:range],
                         show(attributes[NSPersonNameComponentKey])]];
    }];
    print([NSString stringWithFormat:@"annotated: %@", [runs componentsJoinedByString:@" | "]]);
    print([NSString stringWithFormat:@"key: %@ %@ %@ %@ %@ %@ %@ %@", NSPersonNameComponentKey, NSPersonNameComponentGivenName,
           NSPersonNameComponentFamilyName, NSPersonNameComponentMiddleName, NSPersonNameComponentPrefix,
           NSPersonNameComponentSuffix, NSPersonNameComponentNickname, NSPersonNameComponentDelimiter]);

    for (NSString *text in @[@"Kate Bell", @"Johnathan Maple Appleseed", @"Dr. Kate Bell", @"Kate Bell Jr.", @"Cher", @""]) {
        print([NSString stringWithFormat:@"parse [%@]: %@", text, describeName([formatter personNameComponentsFromString:text])]);
    }
    id value = nil;
    NSString *error = nil;
    BOOL parsed = [formatter getObjectValue:&value forString:@"Kate Bell" errorDescription:&error];
    print([NSString stringWithFormat:@"getObjectValue: %d %@", parsed,
           [value isKindOfClass:[NSPersonNameComponents class]] ? describeName(value) : show(value)]);
    print([NSString stringWithFormat:@"stringForObjectValue: [%@] [%@]", [formatter stringForObjectValue:plain],
           show([formatter stringForObjectValue:@"text"])]);
}

static void dateIntervals(NSLocale *locale, NSTimeZone *gmt) {
    NSDateIntervalFormatter *formatter = [[NSDateIntervalFormatter alloc] init];
    formatter.locale = locale;
    formatter.timeZone = gmt;
    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = gmt;
    formatter.calendar = calendar;
    print([NSString stringWithFormat:@"interval defaults date=%lu time=%lu template=[%@] zone=%@ locale=%@",
           (unsigned long)formatter.dateStyle, (unsigned long)formatter.timeStyle, formatter.dateTemplate,
           formatter.timeZone.name, formatter.locale.localeIdentifier]);
    NSDate *start = [NSDate dateWithTimeIntervalSince1970:1700000000];   // 2023-11-14 22:13:20
    NSArray<NSNumber *> *ends = @[@1700000000, @1700003000, @1700050000, @1700600000, @1705000000];
    NSArray<NSNumber *> *styles = @[@0, @1, @2, @3, @4];
    for (NSNumber *date in styles) {
        for (NSNumber *time in styles) {
            formatter.dateStyle = date.unsignedIntegerValue;
            formatter.timeStyle = time.unsignedIntegerValue;
            NSMutableArray *parts = [NSMutableArray array];
            for (NSNumber *end in ends) {
                [parts addObject:[NSString stringWithFormat:@"[%@]",
                                  [formatter stringFromDate:start toDate:[NSDate dateWithTimeIntervalSince1970:end.doubleValue]]]];
            }
            print([NSString stringWithFormat:@"interval %@/%@: %@", date, time, [parts componentsJoinedByString:@" "]]);
        }
    }
    for (NSString *template in @[@"yMMMd", @"MMMd", @"jm", @"yMd", @"EEEEMMMMd", @"yMMMdjmm"]) {
        formatter.dateTemplate = template;
        NSMutableArray *parts = [NSMutableArray array];
        for (NSNumber *end in ends) {
            [parts addObject:[NSString stringWithFormat:@"[%@]",
                              [formatter stringFromDate:start toDate:[NSDate dateWithTimeIntervalSince1970:end.doubleValue]]]];
        }
        print([NSString stringWithFormat:@"template %@ (date=%lu time=%lu): %@", formatter.dateTemplate,
               (unsigned long)formatter.dateStyle, (unsigned long)formatter.timeStyle, [parts componentsJoinedByString:@" "]]);
    }
    formatter.dateStyle = NSDateIntervalFormatterMediumStyle;
    print([NSString stringWithFormat:@"style after template: template=[%@]", formatter.dateTemplate]);
    formatter.timeStyle = NSDateIntervalFormatterShortStyle;
    NSDateInterval *interval = [[NSDateInterval alloc] initWithStartDate:start duration:7200];
    print([NSString stringWithFormat:@"dateInterval: [%@]", [formatter stringFromDateInterval:interval]]);
    print([NSString stringWithFormat:@"reversed: [%@]",
           [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:1700600000] toDate:start]]);
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"de_DE"];
    print([NSString stringWithFormat:@"de_DE: [%@]",
           [formatter stringFromDate:start toDate:[NSDate dateWithTimeIntervalSince1970:1700600000]]]);
    formatter.timeZone = [NSTimeZone timeZoneWithName:@"America/New_York"];
    formatter.locale = locale;
    print([NSString stringWithFormat:@"New York: [%@]",
           [formatter stringFromDate:start toDate:[NSDate dateWithTimeIntervalSince1970:1700050000]]]);
    formatter.timeZone = gmt;
    print([NSString stringWithFormat:@"objectValue: [%@] [%@]", show([formatter stringForObjectValue:interval]),
           show([formatter stringForObjectValue:start])]);
    NSCalendar *hebrew = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierHebrew];
    formatter.calendar = hebrew;
    formatter.timeStyle = NSDateIntervalFormatterNoStyle;
    print([NSString stringWithFormat:@"hebrew: [%@] [%@]", formatter.dateTemplate,
           [formatter stringFromDate:start toDate:[NSDate dateWithTimeIntervalSince1970:1700259200]]]);
    formatter.calendar = calendar;
    formatter.dateTemplate = nil;
    print([NSString stringWithFormat:@"no template: [%@] [%@]", show(formatter.dateTemplate),
           [formatter stringFromDate:start toDate:[NSDate dateWithTimeIntervalSince1970:1700600000]]]);
}

static void relativeDates(NSLocale *locale, NSTimeZone *gmt) {
    NSRelativeDateTimeFormatter *formatter = [[NSRelativeDateTimeFormatter alloc] init];
    formatter.locale = locale;
    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = gmt;
    calendar.locale = locale;
    formatter.calendar = calendar;
    print([NSString stringWithFormat:@"relative defaults style=%ld units=%ld context=%ld locale=%@", (long)formatter.dateTimeStyle,
           (long)formatter.unitsStyle, (long)formatter.formattingContext, formatter.locale.localeIdentifier]);
    // From now, so each spans the same units in any month or year.
    NSArray<NSNumber *> *intervals = @[@0, @1, @-1, @30, @-45, @59, @60, @-90, @3600, @-7200, @86400, @-86400, @172800,
                                       @-604800, @1209600, @2678400, @-5356800, @34560000, @-69120000, @0.4, @-1.6];
    NSArray *unitNames = @[@"full", @"spellOut", @"short", @"abbreviated"];
    for (NSInteger style = 0; style <= 1; style++) {
        for (NSInteger units = 0; units <= 3; units++) {
            formatter.dateTimeStyle = style;
            formatter.unitsStyle = units;
            NSMutableArray *parts = [NSMutableArray array];
            for (NSNumber *interval in intervals) {
                [parts addObject:[NSString stringWithFormat:@"[%@]", [formatter localizedStringFromTimeInterval:interval.doubleValue]]];
            }
            print([NSString stringWithFormat:@"%@ %@: %@", style ? @"named" : @"numeric", unitNames[units],
                   [parts componentsJoinedByString:@" "]]);
        }
    }
    formatter.unitsStyle = NSRelativeDateTimeFormatterUnitsStyleFull;
    NSDate *reference = [NSDate dateWithTimeIntervalSince1970:1700000000];
    for (NSInteger style = 0; style <= 1; style++) {
        formatter.dateTimeStyle = style;
        NSMutableArray *parts = [NSMutableArray array];
        for (NSNumber *offset in @[@0, @-3000, @7000, @-86400, @90000, @-180000, @700000, @-2700000, @40000000]) {
            [parts addObject:[NSString stringWithFormat:@"[%@]", [formatter localizedStringForDate:[reference dateByAddingTimeInterval:offset.doubleValue]
                                                                                   relativeToDate:reference]]];
        }
        print([NSString stringWithFormat:@"%@ dates: %@", style ? @"named" : @"numeric", [parts componentsJoinedByString:@" "]]);
    }
    NSMutableArray *componentParts = [NSMutableArray array];
    for (NSInteger style = 0; style <= 1; style++) {
        formatter.dateTimeStyle = style;
        for (NSInteger unit = 0; unit < 7; unit++) {
            for (NSNumber *value in @[@-1, @0, @2]) {
                NSDateComponents *components = [[NSDateComponents alloc] init];
                NSInteger count = value.integerValue;
                switch (unit) {
                    case 0: components.year = count; break;
                    case 1: components.month = count; break;
                    case 2: components.weekOfMonth = count; break;
                    case 3: components.day = count; break;
                    case 4: components.hour = count; break;
                    case 5: components.minute = count; break;
                    default: components.second = count; break;
                }
                [componentParts addObject:[NSString stringWithFormat:@"[%@]", [formatter localizedStringFromDateComponents:components]]];
            }
        }
        NSDateComponents *mixed = [[NSDateComponents alloc] init];
        mixed.day = 3;
        mixed.hour = -5;
        [componentParts addObject:[NSString stringWithFormat:@"[%@]", [formatter localizedStringFromDateComponents:mixed]]];
        NSDateComponents *zeros = [[NSDateComponents alloc] init];
        zeros.day = 0;
        zeros.hour = 0;
        [componentParts addObject:[NSString stringWithFormat:@"[%@]", [formatter localizedStringFromDateComponents:zeros]]];
        NSDateComponents *none = [[NSDateComponents alloc] init];
        none.nanosecond = 5;
        [componentParts addObject:[NSString stringWithFormat:@"[%@]", show([formatter localizedStringFromDateComponents:none])]];
        print([NSString stringWithFormat:@"%@ components: %@", style ? @"named" : @"numeric", [componentParts componentsJoinedByString:@" "]]);
        [componentParts removeAllObjects];
    }
    formatter.dateTimeStyle = NSRelativeDateTimeFormatterStyleNamed;
    for (NSInteger context = 0; context <= 5; context++) {
        formatter.formattingContext = context;
        print([NSString stringWithFormat:@"context %ld: [%@] [%@]", (long)context, [formatter localizedStringFromTimeInterval:-86400],
               [formatter localizedStringFromTimeInterval:7200]]);
    }
    formatter.formattingContext = NSFormattingContextUnknown;
    print([NSString stringWithFormat:@"objectValue: [%@] [%@]", show([formatter stringForObjectValue:[NSDate dateWithTimeIntervalSinceNow:-3 * 86400]]),
           show([formatter stringForObjectValue:@5])]);
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"fr_FR"];
    print([NSString stringWithFormat:@"fr_FR: [%@] [%@]", [formatter localizedStringFromTimeInterval:-172800],
           [formatter localizedStringFromTimeInterval:300]]);
}

static void lists(NSLocale *locale) {
    NSListFormatter *formatter = [[NSListFormatter alloc] init];
    formatter.locale = locale;
    print([NSString stringWithFormat:@"list defaults locale=%@ item=%@", formatter.locale.localeIdentifier, show(formatter.itemFormatter)]);
    NSArray *lists = @[@[], @[@"apples"], @[@"apples", @"pears"], @[@"apples", @"pears", @"plums"], @[@"a", @"b", @"c", @"d", @"e"]];
    NSMutableArray *parts = [NSMutableArray array];
    for (NSArray *items in lists) {
        [parts addObject:[NSString stringWithFormat:@"[%@]", show([formatter stringFromItems:items])]];
    }
    print([NSString stringWithFormat:@"list en_US: %@", [parts componentsJoinedByString:@" "]]);
    for (NSString *identifier in @[@"en_GB", @"de_DE", @"fr_FR", @"es_ES", @"ja_JP"]) {
        formatter.locale = [NSLocale localeWithLocaleIdentifier:identifier];
        print([NSString stringWithFormat:@"list %@: [%@] [%@]", identifier, [formatter stringFromItems:lists[2]],
               [formatter stringFromItems:lists[3]]]);
    }
    formatter.locale = locale;
    print([NSString stringWithFormat:@"list objects: [%@]", [formatter stringFromItems:@[@1, @2.5, @"x"]]]);
    NSNumberFormatter *numbers = [[NSNumberFormatter alloc] init];
    numbers.locale = locale;
    numbers.numberStyle = NSNumberFormatterPercentStyle;
    formatter.itemFormatter = numbers;
    print([NSString stringWithFormat:@"list percent: [%@] item=%d", [formatter stringFromItems:@[@0.25, @0.5, @1]],
           formatter.itemFormatter != nil]);
    print([NSString stringWithFormat:@"list objectValue: [%@] [%@]", show([formatter stringForObjectValue:@[@0.1, @0.2]]),
           show([formatter stringForObjectValue:@"x"])]);
    print([NSString stringWithFormat:@"joined: [%@]", [NSListFormatter localizedStringByJoiningStrings:@[@"red", @"green", @"blue"]]]);
}

static void masses(NSLocale *locale) {
    NSMassFormatter *formatter = [[NSMassFormatter alloc] init];
    formatter.numberFormatter.locale = locale;
    print([NSString stringWithFormat:@"mass defaults style=%ld person=%d max=%lu", (long)formatter.unitStyle, formatter.isForPersonMassUse,
           (unsigned long)formatter.numberFormatter.maximumFractionDigits]);
    NSArray<NSNumber *> *units = @[@(NSMassFormatterUnitGram), @(NSMassFormatterUnitKilogram), @(NSMassFormatterUnitOunce),
                                   @(NSMassFormatterUnitPound), @(NSMassFormatterUnitStone)];
    for (NSInteger style = 1; style <= 3; style++) {
        formatter.unitStyle = style;
        NSMutableArray *parts = [NSMutableArray array];
        for (NSNumber *unit in units) {
            [parts addObject:[NSString stringWithFormat:@"[%@|%@|%@]", [formatter stringFromValue:1 unit:unit.integerValue],
                              [formatter stringFromValue:2.5 unit:unit.integerValue],
                              [formatter unitStringFromValue:2 unit:unit.integerValue]]];
        }
        print([NSString stringWithFormat:@"mass style %ld: %@", (long)style, [parts componentsJoinedByString:@" "]]);
        NSMutableArray *kilos = [NSMutableArray array];
        for (NSNumber *kilograms in @[@0, @0.0005, @0.25, @1, @70, @1234.5678]) {
            NSMassFormatterUnit used = 0;
            NSString *unitString = [formatter unitStringFromKilograms:kilograms.doubleValue usedUnit:&used];
            [kilos addObject:[NSString stringWithFormat:@"[%@|%@ %ld]", [formatter stringFromKilograms:kilograms.doubleValue], unitString, (long)used]];
        }
        print([NSString stringWithFormat:@"mass kilograms %ld: %@", (long)style, [kilos componentsJoinedByString:@" "]]);
        formatter.forPersonMassUse = YES;
        print([NSString stringWithFormat:@"mass person %ld: [%@] [%@] [%@]", (long)style, [formatter stringFromKilograms:70],
               [formatter stringFromKilograms:3.2], [formatter stringFromKilograms:0]]);
        formatter.forPersonMassUse = NO;
    }
    id value = nil;
    NSString *error = nil;
    BOOL parsed = [formatter getObjectValue:&value forString:@"5 kg" errorDescription:&error];
    print([NSString stringWithFormat:@"mass parse: %d %@", parsed, show(value)]);
    print([NSString stringWithFormat:@"mass objectValue: [%@] [%@]", show([formatter stringForObjectValue:@2]),
           show([formatter stringForObjectValue:@"x"])]);
    NSNumberFormatter *numbers = [[NSNumberFormatter alloc] init];
    numbers.locale = locale;
    numbers.numberStyle = NSNumberFormatterDecimalStyle;
    numbers.minimumFractionDigits = 2;
    formatter.numberFormatter = numbers;
    formatter.unitStyle = NSFormattingUnitStyleMedium;
    print([NSString stringWithFormat:@"mass custom: [%@]", [formatter stringFromValue:1234.5 unit:NSMassFormatterUnitPound]]);
    NSMassFormatter *metric = [[NSMassFormatter alloc] init];
    metric.numberFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_GB"];
    NSMutableArray *metricParts = [NSMutableArray array];
    for (NSNumber *kilograms in @[@0, @0.25, @1, @1.5, @-2]) {
        NSMassFormatterUnit used = 0;
        NSString *unitString = [metric unitStringFromKilograms:kilograms.doubleValue usedUnit:&used];
        [metricParts addObject:[NSString stringWithFormat:@"[%@|%@ %ld]", [metric stringFromKilograms:kilograms.doubleValue], unitString, (long)used]];
    }
    print([NSString stringWithFormat:@"mass en_GB: %@", [metricParts componentsJoinedByString:@" "]]);
}

static void energies(NSLocale *locale) {
    NSEnergyFormatter *formatter = [[NSEnergyFormatter alloc] init];
    formatter.numberFormatter.locale = locale;
    print([NSString stringWithFormat:@"energy defaults style=%ld food=%d", (long)formatter.unitStyle, formatter.isForFoodEnergyUse]);
    NSArray<NSNumber *> *units = @[@(NSEnergyFormatterUnitJoule), @(NSEnergyFormatterUnitKilojoule),
                                   @(NSEnergyFormatterUnitCalorie), @(NSEnergyFormatterUnitKilocalorie)];
    for (NSInteger style = 1; style <= 3; style++) {
        formatter.unitStyle = style;
        NSMutableArray *parts = [NSMutableArray array];
        for (NSNumber *unit in units) {
            [parts addObject:[NSString stringWithFormat:@"[%@|%@|%@]", [formatter stringFromValue:1 unit:unit.integerValue],
                              [formatter stringFromValue:2.5 unit:unit.integerValue],
                              [formatter unitStringFromValue:2 unit:unit.integerValue]]];
        }
        print([NSString stringWithFormat:@"energy style %ld: %@", (long)style, [parts componentsJoinedByString:@" "]]);
        for (NSInteger food = 0; food <= 1; food++) {
            formatter.forFoodEnergyUse = food;
            NSMutableArray *joules = [NSMutableArray array];
            for (NSNumber *value in @[@0, @1, @500, @4184, @20000, @1000000]) {
                NSEnergyFormatterUnit used = 0;
                NSString *unitString = [formatter unitStringFromJoules:value.doubleValue usedUnit:&used];
                [joules addObject:[NSString stringWithFormat:@"[%@|%@ %ld]", [formatter stringFromJoules:value.doubleValue], unitString, (long)used]];
            }
            print([NSString stringWithFormat:@"energy joules %ld food=%ld: %@", (long)style, (long)food, [joules componentsJoinedByString:@" "]]);
        }
        formatter.forFoodEnergyUse = NO;
    }
    id value = nil;
    NSString *error = nil;
    BOOL parsed = [formatter getObjectValue:&value forString:@"5 kJ" errorDescription:&error];
    print([NSString stringWithFormat:@"energy parse: %d %@", parsed, show(value)]);
    print([NSString stringWithFormat:@"energy objectValue: [%@] [%@]", show([formatter stringForObjectValue:@4184]),
           show([formatter stringForObjectValue:@"x"])]);
    NSEnergyFormatter *metric = [[NSEnergyFormatter alloc] init];
    metric.numberFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_GB"];
    metric.forFoodEnergyUse = YES;
    NSMutableArray *metricParts = [NSMutableArray array];
    for (NSNumber *joules in @[@0, @500, @1000, @1001, @-5]) {
        NSEnergyFormatterUnit used = 0;
        NSString *unitString = [metric unitStringFromJoules:joules.doubleValue usedUnit:&used];
        [metricParts addObject:[NSString stringWithFormat:@"[%@|%@ %ld]", [metric stringFromJoules:joules.doubleValue], unitString, (long)used]];
    }
    print([NSString stringWithFormat:@"energy en_GB: %@", [metricParts componentsJoinedByString:@" "]]);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSLocale *locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
        NSTimeZone *gmt = [NSTimeZone timeZoneForSecondsFromGMT:0];
        personNames();
        dateIntervals(locale, gmt);
        relativeDates(locale, gmt);
        lists(locale);
        masses(locale);
        energies(locale);
    }
    return 0;
}
