// Foundation's text and collection classes: regular expressions and their
// matches, scanners, attributed strings, URL components and query items,
// index sets, ordered and counted sets, and caches.

#import <Foundation/Foundation.h>
#include <stdio.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static NSString *range(NSRange range) {
    return range.location == NSNotFound ? @"{NSNotFound}" : NSStringFromRange(range);
}

static void regularExpressions(void) {
    NSError *error = nil;
    NSRegularExpression *dates = [NSRegularExpression regularExpressionWithPattern:@"(\\d{4})-(\\d{2})-(\\d{2})"
                                                                           options:0 error:&error];
    NSString *text = @"Due 2024-03-10, paid 2024-04-01; late? 1999-12-31.";
    NSArray<NSTextCheckingResult *> *matches = [dates matchesInString:text options:0 range:NSMakeRange(0, text.length)];
    NSMutableArray *found = [NSMutableArray array];
    for (NSTextCheckingResult *match in matches) {
        [found addObject:[NSString stringWithFormat:@"%@ %@/%@ %@", [text substringWithRange:match.range],
                          [text substringWithRange:[match rangeAtIndex:2]], [text substringWithRange:[match rangeAtIndex:3]],
                          range(match.range)]];
    }
    say([NSString stringWithFormat:@"matches: %lu, groups %lu, %@; error %@", (unsigned long)matches.count,
         (unsigned long)dates.numberOfCaptureGroups, [found componentsJoinedByString:@"; "], error]);

    NSTextCheckingResult *first = [dates firstMatchInString:text options:0 range:NSMakeRange(10, text.length - 10)];
    NSUInteger count = [dates numberOfMatchesInString:text options:0 range:NSMakeRange(0, text.length)];
    NSRange firstRange = [dates rangeOfFirstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    NSString *swapped = [dates stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length)
                                                   withTemplate:@"$3.$2.$1"];
    say([NSString stringWithFormat:@"first after 10: %@, count %lu, range %@, replaced '%@'", [text substringWithRange:first.range],
         (unsigned long)count, range(firstRange), swapped]);

    NSRegularExpression *named = [NSRegularExpression regularExpressionWithPattern:@"(?<word>[a-z]+)@(?<host>[a-z.]+)"
                                                                           options:NSRegularExpressionCaseInsensitive error:nil];
    NSTextCheckingResult *mail = [named firstMatchInString:@"Mail Ada@Example.org now" options:0 range:NSMakeRange(0, 24)];
    say([NSString stringWithFormat:@"named: %@ %@, ranges %lu", [@"Mail Ada@Example.org now" substringWithRange:[mail rangeWithName:@"word"]],
         [@"Mail Ada@Example.org now" substringWithRange:[mail rangeWithName:@"host"]], (unsigned long)mail.numberOfRanges]);

    NSMutableString *mutable = [@"a1b22c333" mutableCopy];
    NSUInteger replaced = [[NSRegularExpression regularExpressionWithPattern:@"\\d+" options:0 error:nil]
        replaceMatchesInString:mutable options:0 range:NSMakeRange(0, mutable.length) withTemplate:@"<$0>"];
    NSRegularExpression *bad = [NSRegularExpression regularExpressionWithPattern:@"(unclosed" options:0 error:&error];
    say([NSString stringWithFormat:@"replace: %lu '%@', bad %@ %@ %ld, escaped %@ %@", (unsigned long)replaced, mutable, bad,
         error.domain, (long)error.code, [NSRegularExpression escapedPatternForString:@"a.b*c"],
         [NSRegularExpression escapedTemplateForString:@"$1\\"]]);

    NSRegularExpression *lines = [NSRegularExpression regularExpressionWithPattern:@"^\\w+$"
                                                                           options:NSRegularExpressionAnchorsMatchLines error:nil];
    NSMutableArray *blocks = [NSMutableArray array];
    [lines enumerateMatchesInString:@"one\ntwo three\nfour" options:0 range:NSMakeRange(0, 18)
                         usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
        [blocks addObject:NSStringFromRange(result.range)];
    }];
    NSRange search = [@"Hello, World" rangeOfString:@"w[a-z]+" options:NSRegularExpressionSearch | NSCaseInsensitiveSearch];
    say([NSString stringWithFormat:@"lines: %@; string search %@; pattern %@ options %lu", [blocks componentsJoinedByString:@" "],
         range(search), lines.pattern, (unsigned long)lines.options]);
}

static void scanners(void) {
    NSScanner *scanner = [NSScanner scannerWithString:@"  42 apples, 3.5 kg; 0x1F total=-7 end"];
    NSInteger apples = 0;
    NSString *word = nil;
    double weight = 0;
    unsigned hexValue = 0;
    NSInteger total = 0;
    BOOL a = [scanner scanInteger:&apples];
    BOOL b = [scanner scanCharactersFromSet:NSCharacterSet.letterCharacterSet intoString:&word];
    [scanner scanString:@"," intoString:NULL];
    BOOL c = [scanner scanDouble:&weight];
    [scanner scanUpToString:@";" intoString:NULL];
    [scanner scanString:@";" intoString:NULL];
    BOOL d = [scanner scanHexInt:&hexValue];
    NSString *upTo = nil;
    [scanner scanUpToCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"="] intoString:&upTo];
    [scanner scanString:@"=" intoString:NULL];
    BOOL e = [scanner scanInteger:&total];
    say([NSString stringWithFormat:@"scanner: %d %ld, %d '%@', %d %.1f, %d %u, '%@', %d %ld, at %lu end %d", a, (long)apples, b, word,
         c, weight, d, hexValue, upTo, e, (long)total, (unsigned long)scanner.scanLocation, scanner.isAtEnd]);

    NSScanner *strict = [NSScanner scannerWithString:@"abc 12"];
    strict.charactersToBeSkipped = nil;
    NSInteger number = 0;
    BOOL failed = [strict scanInteger:&number];
    strict.scanLocation = 4;
    BOOL succeeded = [strict scanInteger:&number];
    strict.caseSensitive = NO;
    NSScanner *cased = [NSScanner scannerWithString:@"HELLO there"];
    cased.caseSensitive = NO;
    BOOL insensitive = [cased scanString:@"hello" intoString:NULL];
    long long big = 0;
    float single = 0;
    BOOL f = [[NSScanner scannerWithString:@"9223372036854775807"] scanLongLong:&big];
    BOOL g = [[NSScanner scannerWithString:@"-1.25e2"] scanFloat:&single];
    say([NSString stringWithFormat:@"scanner rules: %d then %d %ld, case %d, long long %d %lld, float %d %.2f", failed, succeeded,
         (long)number, insensitive, f, big, g, single]);
}

static void attributedStrings(void) {
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:@"Hello, world"
                                                                             attributes:@{@"weight": @"regular"}];
    [text addAttribute:@"weight" value:@"bold" range:NSMakeRange(0, 5)];
    [text addAttribute:@"link" value:@"https://example.com" range:NSMakeRange(7, 5)];
    NSRange effective;
    NSDictionary *at0 = [text attributesAtIndex:0 effectiveRange:&effective];
    NSRange linkRange;
    id link = [text attribute:@"link" atIndex:8 effectiveRange:&linkRange];
    NSMutableArray *runs = [NSMutableArray array];
    [text enumerateAttributesInRange:NSMakeRange(0, text.length) options:0
                          usingBlock:^(NSDictionary *attributes, NSRange range, BOOL *stop) {
        [runs addObject:[NSString stringWithFormat:@"%@:%@%@", NSStringFromRange(range), attributes[@"weight"],
                         attributes[@"link"] ? @"+link" : @""]];
    }];
    say([NSString stringWithFormat:@"attributed: '%@' %lu, at 0 %@ %@, link %@ %@, runs %@", text.string, (unsigned long)text.length,
         at0[@"weight"], NSStringFromRange(effective), link, NSStringFromRange(linkRange), [runs componentsJoinedByString:@" "]]);

    [text replaceCharactersInRange:NSMakeRange(0, 5) withString:@"Goodbye"];
    [text appendAttributedString:[[NSAttributedString alloc] initWithString:@"!" attributes:@{@"weight": @"heavy"}]];
    [text removeAttribute:@"link" range:NSMakeRange(0, text.length)];
    [text deleteCharactersInRange:NSMakeRange(7, 1)];
    NSMutableArray *after = [NSMutableArray array];
    [text enumerateAttribute:@"weight" inRange:NSMakeRange(0, text.length) options:0
                  usingBlock:^(id value, NSRange range, BOOL *stop) {
        [after addObject:[NSString stringWithFormat:@"%@=%@", NSStringFromRange(range), value]];
    }];
    NSAttributedString *sub = [text attributedSubstringFromRange:NSMakeRange(2, 4)];
    NSAttributedString *copy = [text copy];
    say([NSString stringWithFormat:@"edited: '%@', %@, sub '%@' %@, equal copy %d, plain equal %d", text.string,
         [after componentsJoinedByString:@" "], sub.string, [sub attribute:@"weight" atIndex:0 effectiveRange:NULL],
         [copy isEqualToAttributedString:text], [[[NSAttributedString alloc] initWithString:@"x"] isEqual:[[NSAttributedString alloc] initWithString:@"x"]]]);
}

static void urlComponents(void) {
    NSURLComponents *components = [NSURLComponents componentsWithString:@"https://user:pw@example.com:8443/a%20b/c?q=one%20two&flag&x=1#frag"];
    say([NSString stringWithFormat:@"components: %@ %@ %@ %@ %@ path '%@' encoded '%@' query '%@' fragment %@", components.scheme,
         components.user, components.password, components.host, components.port, components.path, components.percentEncodedPath,
         components.query, components.fragment]);
    NSMutableArray *items = [NSMutableArray array];
    for (NSURLQueryItem *item in components.queryItems) [items addObject:[NSString stringWithFormat:@"%@=%@", item.name, item.value]];
    say([NSString stringWithFormat:@"items: %@", [items componentsJoinedByString:@" "]]);

    NSURLComponents *built = [NSURLComponents new];
    built.scheme = @"https";
    built.host = @"api.example.com";
    built.path = @"/v1/search items";
    built.queryItems = @[[NSURLQueryItem queryItemWithName:@"q" value:@"café & tea"], [NSURLQueryItem queryItemWithName:@"page" value:@"2"],
                         [NSURLQueryItem queryItemWithName:@"empty" value:nil]];
    built.fragment = @"top";
    say([NSString stringWithFormat:@"built: %@ | %@ | %@", built.string, built.URL.absoluteString, built.percentEncodedQuery]);
    NSURLComponents *fromURL = [NSURLComponents componentsWithURL:[NSURL URLWithString:@"http://h/p?a=1"] resolvingAgainstBaseURL:NO];
    fromURL.queryItems = nil;
    say([NSString stringWithFormat:@"rangeOfHost %@, cleared %@, invalid %@", NSStringFromRange(components.rangeOfHost), fromURL.string,
         [NSURLComponents componentsWithString:@"http://[::1"]]);
}

static void collections(void) {
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSetWithIndexesInRange:NSMakeRange(2, 4)];
    [indexes addIndex:10];
    [indexes addIndexesInRange:NSMakeRange(11, 2)];
    [indexes removeIndex:3];
    NSMutableArray *ranges = [NSMutableArray array];
    [indexes enumerateRangesUsingBlock:^(NSRange range, BOOL *stop) { [ranges addObject:NSStringFromRange(range)]; }];
    say([NSString stringWithFormat:@"indexes: count %lu, first %lu last %lu, contains 4 %d 3 %d, greater than 5: %lu, ranges %@, shifted %@",
         (unsigned long)indexes.count, (unsigned long)indexes.firstIndex, (unsigned long)indexes.lastIndex,
         [indexes containsIndex:4], [indexes containsIndex:3], (unsigned long)[indexes indexGreaterThanIndex:5],
         [ranges componentsJoinedByString:@" "], ({ NSMutableIndexSet *s = [indexes mutableCopy]; [s shiftIndexesStartingAtIndex:10 by:-5];
           NSMutableArray *a = [NSMutableArray array]; [s enumerateIndexesUsingBlock:^(NSUInteger i, BOOL *st) { [a addObject:@(i)]; }];
           [a componentsJoinedByString:@","]; })]);
    NSArray *letters = @[@"a", @"b", @"c", @"d", @"e", @"f"];
    say([NSString stringWithFormat:@"objectsAtIndexes: %@", [[letters objectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, 3)]]
                                                              componentsJoinedByString:@""]]);

    NSMutableOrderedSet *ordered = [NSMutableOrderedSet orderedSetWithArray:@[@"x", @"y", @"x", @"z"]];
    [ordered insertObject:@"w" atIndex:0];
    [ordered addObject:@"y"];
    [ordered removeObject:@"z"];
    say([NSString stringWithFormat:@"ordered: %@, index of y %lu, contains x %d, first %@ last %@",
         [ordered.array componentsJoinedByString:@","], (unsigned long)[ordered indexOfObject:@"y"], [ordered containsObject:@"x"],
         ordered.firstObject, ordered.lastObject]);

    NSCountedSet *counted = [NSCountedSet setWithArray:@[@"a", @"b", @"a", @"c", @"a", @"b"]];
    [counted removeObject:@"c"];
    say([NSString stringWithFormat:@"counted: a %lu b %lu c %lu, distinct %lu", (unsigned long)[counted countForObject:@"a"],
         (unsigned long)[counted countForObject:@"b"], (unsigned long)[counted countForObject:@"c"], (unsigned long)counted.count]);

    NSCache *cache = [NSCache new];
    cache.name = @"thumbnails";
    cache.countLimit = 2;
    [cache setObject:@"one" forKey:@1];
    [cache setObject:@"two" forKey:@2 cost:5];
    [cache setObject:@"three" forKey:@3];
    NSUInteger kept = ([cache objectForKey:@1] != nil) + ([cache objectForKey:@2] != nil) + ([cache objectForKey:@3] != nil);
    [cache removeObjectForKey:@3];
    say([NSString stringWithFormat:@"cache: %@ limit %lu, kept %lu, three %@ after removal, two %@", cache.name,
         (unsigned long)cache.countLimit, (unsigned long)kept, [cache objectForKey:@3], [cache objectForKey:@2]]);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        regularExpressions();
        scanners();
        attributedStrings();
        urlComponents();
        collections();
    }
    return 0;
}
