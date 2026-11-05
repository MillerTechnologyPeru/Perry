// Markdown as Foundation imports it: NSAttributedString's Markdown
// initializers with each syntax and option, presentation intents, inline
// presentation intents, links, images, list delimiters, tables, source
// positions, extended attributes and failures, and the localized attributed
// strings SwiftUI's Text reads.

#import <Foundation/Foundation.h>
#include <stdio.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static NSString *escaped(NSString *text) {
    return [[text stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"]
        stringByReplacingOccurrencesOfString:@"\t" withString:@"\\t"];
}

static NSString *intent(NSPresentationIntent *intent) {
    NSMutableArray *parts = [NSMutableArray array];
    for (NSPresentationIntent *current = intent; current; current = current.parentIntent) {
        NSString *extra = @"";
        switch (current.intentKind) {
            case NSPresentationIntentKindHeader: extra = [NSString stringWithFormat:@" level %ld", (long)current.headerLevel]; break;
            case NSPresentationIntentKindListItem: extra = [NSString stringWithFormat:@" ordinal %ld", (long)current.ordinal]; break;
            case NSPresentationIntentKindCodeBlock: extra = [NSString stringWithFormat:@" hint %@", current.languageHint ?: @"none"]; break;
            case NSPresentationIntentKindTable:
                extra = [NSString stringWithFormat:@" columns %ld aligned %@", (long)current.columnCount,
                         [current.columnAlignments componentsJoinedByString:@","]];
                break;
            case NSPresentationIntentKindTableRow: extra = [NSString stringWithFormat:@" row %ld", (long)current.row]; break;
            case NSPresentationIntentKindTableCell: extra = [NSString stringWithFormat:@" column %ld", (long)current.column]; break;
            default: break;
        }
        [parts addObject:[NSString stringWithFormat:@"%ld#%ld%@ indent %ld", (long)current.intentKind, (long)current.identity,
                          extra, (long)current.indentationLevel]];
    }
    return [parts componentsJoinedByString:@" < "];
}

static NSString *value(id value) {
    if ([value isKindOfClass:[NSPresentationIntent class]]) return intent(value);
    if ([value isKindOfClass:[NSAttributedStringMarkdownSourcePosition class]]) {
        NSAttributedStringMarkdownSourcePosition *position = value;
        return [NSString stringWithFormat:@"%ld:%ld-%ld:%ld", (long)position.startLine, (long)position.startColumn,
                (long)position.endLine, (long)position.endColumn];
    }
    if ([value isKindOfClass:[NSURL class]]) {
        NSURL *url = value;
        return url.baseURL ? [NSString stringWithFormat:@"%@ (in %@) = %@", url.relativeString, url.baseURL.absoluteString,
                              url.absoluteString] : url.absoluteString;
    }
    if ([value isKindOfClass:[NSString class]]) return [NSString stringWithFormat:@"'%@'", value];
    return [value description];
}

static void runs(NSAttributedString *string) {
    [string enumerateAttributesInRange:NSMakeRange(0, string.length) options:0
                            usingBlock:^(NSDictionary *attributes, NSRange range, BOOL *stop) {
        NSMutableArray *parts = [NSMutableArray array];
        for (NSString *key in [attributes.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            [parts addObject:[NSString stringWithFormat:@"%@=%@", key, value(attributes[key])]];
        }
        say([NSString stringWithFormat:@"  '%@' %@", escaped([string.string substringWithRange:range]),
             [parts componentsJoinedByString:@"; "]]);
    }];
}

static NSAttributedStringMarkdownParsingOptions *options(NSAttributedStringMarkdownInterpretedSyntax syntax, BOOL extended,
                                                         NSAttributedStringMarkdownParsingFailurePolicy policy, BOOL positions) {
    NSAttributedStringMarkdownParsingOptions *options = [[NSAttributedStringMarkdownParsingOptions alloc] init];
    options.interpretedSyntax = syntax;
    options.allowsExtendedAttributes = extended;
    options.failurePolicy = policy;
    options.appliesSourcePositionAttributes = positions;
    return options;
}

static void parse(NSString *label, NSString *markdown, NSAttributedStringMarkdownParsingOptions *options, NSURL *base) {
    NSError *error = nil;
    NSAttributedString *string = [[NSAttributedString alloc] initWithMarkdownString:markdown options:options
                                                                            baseURL:base error:&error];
    if (!string) {
        say([NSString stringWithFormat:@"%@: nil, error %@ %ld", label, error.domain, (long)error.code]);
        return;
    }
    say([NSString stringWithFormat:@"%@: '%@' (%lu)", label, escaped(string.string), (unsigned long)string.length]);
    runs(string);
}

static void syntaxes(void) {
    NSString *inline_ = @"Hello **bold**, *italic*, ***both***, `code`, ~~gone~~ and ~one~.";
    NSString *blocks = @"# Title\n\nPara one\nsoft line  \nhard\n\n## Sub\n\n> quote\n> more\n\n---\n\n"
                       @"```swift extra\nlet x = 1\n```\n\n    indented";
    NSString *spaced = @"  leading  spaces\n\nnext *em*  ";
    for (NSInteger syntax = 0; syntax <= 2; syntax++) {
        NSAttributedStringMarkdownParsingOptions *o = options(syntax, NO, NSAttributedStringMarkdownParsingFailureReturnError, NO);
        parse([NSString stringWithFormat:@"inline %ld", (long)syntax], inline_, o, nil);
        parse([NSString stringWithFormat:@"blocks %ld", (long)syntax], blocks, o, nil);
        parse([NSString stringWithFormat:@"spaced %ld", (long)syntax], spaced, o, nil);
    }
}

static void structure(void) {
    NSAttributedStringMarkdownParsingOptions *full = options(NSAttributedStringMarkdownInterpretedSyntaxFull, NO,
                                                             NSAttributedStringMarkdownParsingFailureReturnError, NO);
    parse(@"lists", @"- one\n- two\n  - nested\n\n1. first\n2. second\n\n3) three\n\n* star\n+ plus", full, nil);
    parse(@"nesting", @"> > deep\n\n- a\n\n  > q\n\n> - x\n>   - y", full, nil);
    parse(@"table", @"| a | b | c |\n|:-|-:|:-:|\n| 1 | **2** | 3 |\n| 4 | 5 |", full, nil);
    parse(@"html", @"<b>bold</b> &amp; \\*esc\\* &copy;\n\n<div>\nblock\n</div>", full, nil);
    parse(@"empty", @"", full, nil);
    parse(@"breaks", @"a\n***\n\n```\n```\n\n#", full, nil);
}

static void links(void) {
    NSAttributedStringMarkdownParsingOptions *full = options(NSAttributedStringMarkdownInterpretedSyntaxFull, NO,
                                                             NSAttributedStringMarkdownParsingFailureReturnError, NO);
    NSString *markdown = @"[abs](https://apple.com) [rel](b/c) [titled](u \"T\") ![img](pic.png \"alt\") ![](i.png) "
                         @"<https://auto.example> www.ex.com x@y.com [ref][r] **[bold link](z)**\n\n[r]: https://r.example";
    parse(@"links", markdown, full, nil);
    parse(@"links in base", markdown, full, [NSURL URLWithString:@"https://example.com/a/"]);
}

static void positions(void) {
    parse(@"positions", @"# T\n\nab **c** é ü\n\n- item", options(NSAttributedStringMarkdownInterpretedSyntaxFull, NO,
                                                                     NSAttributedStringMarkdownParsingFailureReturnError, YES), nil);
    NSString *source = @"x\né **bold**";
    NSAttributedStringMarkdownSourcePosition *position =
        [[NSAttributedStringMarkdownSourcePosition alloc] initWithStartLine:2 startColumn:6 endLine:2 endColumn:9];
    NSRange range = [position rangeInString:source];
    say([NSString stringWithFormat:@"range: %@ '%@', equal %d, copy equal %d", NSStringFromRange(range),
         [source substringWithRange:range],
         [position isEqual:[[NSAttributedStringMarkdownSourcePosition alloc] initWithStartLine:2 startColumn:6 endLine:2 endColumn:9]],
         [[position copy] isEqual:position]]);
}

static void extendedAttributes(void) {
    NSString *markdown = @"^[Hi](inflect: true) and ^[x](foo: 1, bar: 'two') ^[outer ^[inner](foo: 2)](foo: 3)";
    parse(@"ignored", markdown, options(NSAttributedStringMarkdownInterpretedSyntaxFull, NO,
                                        NSAttributedStringMarkdownParsingFailureReturnError, NO), nil);
    parse(@"extended", markdown, options(NSAttributedStringMarkdownInterpretedSyntaxInlineOnlyPreservingWhitespace, YES,
                                         NSAttributedStringMarkdownParsingFailureReturnError, NO), nil);
    parse(@"bad", @"a ^[bad](inflect: ) b", options(NSAttributedStringMarkdownInterpretedSyntaxFull, YES,
                                                    NSAttributedStringMarkdownParsingFailureReturnError, NO), nil);
    parse(@"bad, partial", @"a ^[bad](inflect: ) b", options(NSAttributedStringMarkdownInterpretedSyntaxFull, YES,
                                                             NSAttributedStringMarkdownParsingFailureReturnPartiallyParsedIfPossible, NO), nil);
}

static void intents(void) {
    NSPresentationIntent *list = [NSPresentationIntent orderedListIntentWithIdentity:1 nestedInsideIntent:nil];
    NSPresentationIntent *item = [NSPresentationIntent listItemIntentWithIdentity:2 ordinal:3 nestedInsideIntent:list];
    NSPresentationIntent *quote = [NSPresentationIntent blockQuoteIntentWithIdentity:3 nestedInsideIntent:item];
    NSPresentationIntent *code = [NSPresentationIntent codeBlockIntentWithIdentity:4 languageHint:@"c" nestedInsideIntent:quote];
    NSPresentationIntent *table = [NSPresentationIntent tableIntentWithIdentity:5 columnCount:3 alignments:@[@2, @0, @1] nestedInsideIntent:nil];
    NSPresentationIntent *other = [NSPresentationIntent listItemIntentWithIdentity:9 ordinal:3
        nestedInsideIntent:[NSPresentationIntent orderedListIntentWithIdentity:8 nestedInsideIntent:nil]];
    say([NSString stringWithFormat:@"intents: %@ | %@", intent(code), intent(table)]);
    say([NSString stringWithFormat:@"intents: equal %d, equivalent %d, same equal %d, copy equal %d, header %ld",
         [item isEqual:other], [item isEquivalentToPresentationIntent:other],
         [item isEqual:[NSPresentationIntent listItemIntentWithIdentity:2 ordinal:3 nestedInsideIntent:list]],
         [[item copy] isEqual:item], (long)[NSPresentationIntent headerIntentWithIdentity:1 level:4 nestedInsideIntent:nil].headerLevel]);
    NSAttributedStringMarkdownParsingOptions *options = [[NSAttributedStringMarkdownParsingOptions alloc] init];
    NSAttributedStringMarkdownParsingOptions *copy = [options copy];
    copy.allowsExtendedAttributes = YES;
    say([NSString stringWithFormat:@"options: %d %ld %ld %@ %d, copy %d", options.allowsExtendedAttributes,
         (long)options.interpretedSyntax, (long)options.failurePolicy, options.languageCode,
         options.appliesSourcePositionAttributes, copy.allowsExtendedAttributes]);
}

static void sources(void) {
    NSError *error = nil;
    NSData *data = [@"*from* data" dataUsingEncoding:NSUTF8StringEncoding];
    NSAttributedString *string = [[NSAttributedString alloc] initWithMarkdown:data options:nil baseURL:nil error:&error];
    say([NSString stringWithFormat:@"data: '%@'", string.string]);
    runs(string);
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"quill.md"];
    [@"## From a file" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    string = [[NSAttributedString alloc] initWithContentsOfMarkdownFileAtURL:[NSURL fileURLWithPath:path] options:nil
                                                                     baseURL:nil error:&error];
    say([NSString stringWithFormat:@"file: '%@'", string.string]);
    runs(string);
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    string = [[NSAttributedString alloc] initWithContentsOfMarkdownFileAtURL:[NSURL fileURLWithPath:path] options:nil
                                                                     baseURL:nil error:&error];
    say([NSString stringWithFormat:@"missing file: %@, error %@ %ld", string, error.domain, (long)error.code]);
}

static void localized(void) {
    NSBundle *bundle = [NSBundle mainBundle];
    for (NSString *key in @[@"greeting", @"plain", @"missing *key*"]) {
        NSAttributedString *string = [bundle localizedAttributedStringForKey:key value:nil table:nil];
        say([NSString stringWithFormat:@"localized %@: '%@'", key, escaped(string.string)]);
        runs(string);
    }
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        syntaxes();
        structure();
        links();
        positions();
        extendedAttributes();
        intents();
        sources();
        localized();
    }
    return 0;
}
