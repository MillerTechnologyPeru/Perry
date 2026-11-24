// CFStringTokenizer: words, word boundaries, sentences, paragraphs and line
// breaks, sub-tokens, attributes and language guesses, built on a Mac with
// Xcode. Its texts avoid abbreviations and Japanese words, which Darwin's
// tokenizer splits its own way.
#import <Foundation/Foundation.h>

static void print(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static NSString *tokens(NSString *text, CFRange range, CFOptionFlags unit, NSString *localeName) {
    CFLocaleRef locale = localeName ? CFLocaleCreate(NULL, (__bridge CFStringRef)localeName) : NULL;
    CFStringTokenizerRef tokenizer = CFStringTokenizerCreate(NULL, (__bridge CFStringRef)text, range, unit, locale);
    NSMutableArray *found = [NSMutableArray array];
    CFStringTokenizerTokenType type;
    while ((type = CFStringTokenizerAdvanceToNextToken(tokenizer)) != kCFStringTokenizerTokenNone) {
        CFRange token = CFStringTokenizerGetCurrentTokenRange(tokenizer);
        NSString *piece = [[text substringWithRange:NSMakeRange(token.location, token.length)]
                           stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
        [found addObject:[NSString stringWithFormat:@"[%@]%lx", piece, (unsigned long)type]];
    }
    CFRange after = CFStringTokenizerGetCurrentTokenRange(tokenizer);
    CFRelease(tokenizer);
    if (locale) CFRelease(locale);
    return [NSString stringWithFormat:@"%@ end {%ld, %ld}", [found componentsJoinedByString:@" "], (long)after.location, (long)after.length];
}

static NSString *range(CFRange range) { return [NSString stringWithFormat:@"{%ld, %ld}", (long)range.location, (long)range.length]; }

int main(void) {
    @autoreleasepool {
        NSString *text = @"Hello, world! It's 3.14 pm. Café x2.\n\nNew paragraph here.";
        CFRange all = CFRangeMake(0, text.length);
        print([NSString stringWithFormat:@"type %d", CFGetTypeID(CFStringTokenizerCreate(NULL, CFSTR("a"), CFRangeMake(0, 1), 0, NULL))
               == CFStringTokenizerGetTypeID()]);
        print([NSString stringWithFormat:@"words %@", tokens(text, all, kCFStringTokenizerUnitWord, @"en_US")]);
        print([NSString stringWithFormat:@"boundaries %@", tokens(text, all, kCFStringTokenizerUnitWordBoundary, @"en_US")]);
        print([NSString stringWithFormat:@"sentences %@", tokens(text, all, kCFStringTokenizerUnitSentence, @"en_US")]);
        print([NSString stringWithFormat:@"paragraphs %@", tokens(text, all, kCFStringTokenizerUnitParagraph, @"en_US")]);
        print([NSString stringWithFormat:@"lines %@", tokens(text, all, kCFStringTokenizerUnitLineBreak, @"en_US")]);
        print([NSString stringWithFormat:@"no locale %@", tokens(@"one two", CFRangeMake(0, 7), kCFStringTokenizerUnitWord, nil)]);
        print([NSString stringWithFormat:@"part %@", tokens(text, CFRangeMake(7, 12), kCFStringTokenizerUnitWord, nil)]);
        print([NSString stringWithFormat:@"empty %@", tokens(@"", CFRangeMake(0, 0), kCFStringTokenizerUnitWord, nil)]);

        CFStringTokenizerRef tokenizer = CFStringTokenizerCreate(NULL, (__bridge CFStringRef)text, all, kCFStringTokenizerUnitWord, NULL);
        CFStringTokenizerTokenType type = CFStringTokenizerGoToTokenAtIndex(tokenizer, 9);
        NSString *at9 = [NSString stringWithFormat:@"%lx %@", (unsigned long)type, range(CFStringTokenizerGetCurrentTokenRange(tokenizer))];
        type = CFStringTokenizerGoToTokenAtIndex(tokenizer, 5);
        NSString *at5 = [NSString stringWithFormat:@"%lx %@", (unsigned long)type, range(CFStringTokenizerGetCurrentTokenRange(tokenizer))];
        type = CFStringTokenizerAdvanceToNextToken(tokenizer);
        NSString *after5 = [NSString stringWithFormat:@"%lx %@", (unsigned long)type, range(CFStringTokenizerGetCurrentTokenRange(tokenizer))];
        print([NSString stringWithFormat:@"at 9 %@ at 5 %@ next %@", at9, at5, after5]);
        CFStringTokenizerSetString(tokenizer, CFSTR("a b"), CFRangeMake(0, 3));
        type = CFStringTokenizerAdvanceToNextToken(tokenizer);
        print([NSString stringWithFormat:@"set %lx %@", (unsigned long)type, range(CFStringTokenizerGetCurrentTokenRange(tokenizer))]);
        CFRelease(tokenizer);

        NSString *mixed = @"3.14 x2 Café Привет well-known";
        CFStringTokenizerRef detailed = CFStringTokenizerCreate(NULL, (__bridge CFStringRef)mixed, CFRangeMake(0, mixed.length),
            kCFStringTokenizerUnitWord | kCFStringTokenizerAttributeLanguage | kCFStringTokenizerAttributeLatinTranscription, NULL);
        while ((type = CFStringTokenizerAdvanceToNextToken(detailed))) {
            CFRange token = CFStringTokenizerGetCurrentTokenRange(detailed);
            CFRange subs[8];
            CFMutableArrayRef derived = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
            CFIndex count = CFStringTokenizerGetCurrentSubTokens(detailed, subs, 8, derived);
            NSMutableArray *parts = [NSMutableArray array];
            for (CFIndex i = 0; i < count; i++) [parts addObject:[mixed substringWithRange:NSMakeRange(subs[i].location, subs[i].length)]];
            NSString *language = CFBridgingRelease(CFStringTokenizerCopyCurrentTokenAttribute(detailed, kCFStringTokenizerAttributeLanguage));
            NSString *latin = CFBridgingRelease(CFStringTokenizerCopyCurrentTokenAttribute(detailed, kCFStringTokenizerAttributeLatinTranscription));
            print([NSString stringWithFormat:@"[%@] %lx subs %@ derived %@ language %@ latin %@",
                   [mixed substringWithRange:NSMakeRange(token.location, token.length)], (unsigned long)type,
                   [parts componentsJoinedByString:@"|"], [(__bridge NSArray *)derived componentsJoinedByString:@"|"],
                   language ?: @"-", latin ?: @"-"]);
            CFRelease(derived);
        }
        CFRelease(detailed);

        CFStringTokenizerRef plain = CFStringTokenizerCreate(NULL, CFSTR("word"), CFRangeMake(0, 4), kCFStringTokenizerUnitWord, NULL);
        CFStringTokenizerAdvanceToNextToken(plain);
        NSString *unasked = CFBridgingRelease(CFStringTokenizerCopyCurrentTokenAttribute(plain, kCFStringTokenizerAttributeLatinTranscription));
        print([NSString stringWithFormat:@"unasked %@", unasked ?: @"-"]);

        NSArray *samples = @[@"The quick brown fox jumps over the lazy dog.", @"Le chat est sur la table avec les enfants.",
                             @"El perro corre en el parque con los niños.", @"Il gatto è sul tavolo con i bambini.",
                             @"Dies ist ein deutscher Satz mit vielen Wörtern.", @"これは日本語の文です。", @"안녕하세요 세계", @"你好世界",
                             @"x", @""];
        NSMutableArray *languages = [NSMutableArray array];
        for (NSString *sample in samples) {
            CFStringRef language = CFStringTokenizerCopyBestStringLanguage((__bridge CFStringRef)sample, CFRangeMake(0, sample.length));
            [languages addObject:language ? (__bridge_transfer NSString *)language : @"-"];
        }
        print([NSString stringWithFormat:@"languages %@", [languages componentsJoinedByString:@" "]]);
    }
    return 0;
}
