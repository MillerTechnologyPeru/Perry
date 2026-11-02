// NSXMLParser: the delegate's events for a document read from the bundle,
// without and with namespace processing; positions; a malformed document;
// and a delegate that aborts.

#import <Foundation/Foundation.h>
#include <stdio.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

/// Text with newlines and tabs visible.
static NSString *shown(NSString *text) {
    if (!text) return @"nil";
    NSString *escaped = [text stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    return [NSString stringWithFormat:@"'%@'", [escaped stringByReplacingOccurrencesOfString:@"\t" withString:@"\\t"]];
}

static NSString *sorted(NSDictionary<NSString *, NSString *> *attributes) {
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSString *key in [attributes.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        [pairs addObject:[NSString stringWithFormat:@"%@=%@", key, attributes[key]]];
    }
    return [NSString stringWithFormat:@"{%@}", [pairs componentsJoinedByString:@", "]];
}

@interface Logger : NSObject <NSXMLParserDelegate>
@property (nonatomic, copy) NSString *stopAt;
@end

@implementation Logger

- (void)parserDidStartDocument:(NSXMLParser *)parser {
    say(@"start document");
}

- (void)parserDidEndDocument:(NSXMLParser *)parser {
    say(@"end document");
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)name namespaceURI:(NSString *)uri
 qualifiedName:(NSString *)qName attributes:(NSDictionary<NSString *, NSString *> *)attributes {
    say([NSString stringWithFormat:@"start %@ uri %@ qname %@ attributes %@ at %ld:%ld", name, uri ?: @"nil",
         qName ?: @"nil", sorted(attributes), (long)parser.lineNumber, (long)parser.columnNumber]);
    if ([name isEqualToString:self.stopAt]) {
        [parser abortParsing];
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)name namespaceURI:(NSString *)uri
 qualifiedName:(NSString *)qName {
    say([NSString stringWithFormat:@"end %@ uri %@ qname %@", name, uri ?: @"nil", qName ?: @"nil"]);
}

- (void)parser:(NSXMLParser *)parser didStartMappingPrefix:(NSString *)prefix toURI:(NSString *)uri {
    say([NSString stringWithFormat:@"map prefix %@ to %@", shown(prefix), uri]);
}

- (void)parser:(NSXMLParser *)parser didEndMappingPrefix:(NSString *)prefix {
    say([NSString stringWithFormat:@"unmap prefix %@", shown(prefix)]);
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    say([NSString stringWithFormat:@"characters %@", shown(string)]);
}

- (void)parser:(NSXMLParser *)parser foundIgnorableWhitespace:(NSString *)whitespace {
    say([NSString stringWithFormat:@"ignorable %@", shown(whitespace)]);
}

- (void)parser:(NSXMLParser *)parser foundCDATA:(NSData *)CDATABlock {
    NSString *text = [[NSString alloc] initWithData:CDATABlock encoding:NSUTF8StringEncoding];
    say([NSString stringWithFormat:@"CDATA %@", shown(text)]);
}

- (void)parser:(NSXMLParser *)parser foundComment:(NSString *)comment {
    say([NSString stringWithFormat:@"comment %@", shown(comment)]);
}

- (void)parser:(NSXMLParser *)parser foundProcessingInstructionWithTarget:(NSString *)target data:(NSString *)data {
    say([NSString stringWithFormat:@"instruction %@ data %@", target, shown(data)]);
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)error {
    say([NSString stringWithFormat:@"error %@ %ld at %ld:%ld", error.domain, (long)error.code,
         (long)parser.lineNumber, (long)parser.columnNumber]);
}

@end

static void run(NSXMLParser *parser, Logger *logger, NSString *title) {
    say([NSString stringWithFormat:@"== %@", title]);
    parser.delegate = logger;
    BOOL parsed = [parser parse];
    NSError *error = parser.parserError;
    say([NSString stringWithFormat:@"parsed %d, error %@ %ld, delegate kept %d", parsed, error.domain ?: @"nil",
         (long)error.code, parser.delegate == logger]);
}

int main(void) {
    @autoreleasepool {
        NSURL *url = [NSBundle.mainBundle URLForResource:@"catalog" withExtension:@"xml"];
        Logger *logger = [[Logger alloc] init];

        NSXMLParser *plain = [[NSXMLParser alloc] initWithContentsOfURL:url];
        say([NSString stringWithFormat:@"defaults: namespaces %d, prefixes %d, external entities %d",
             plain.shouldProcessNamespaces, plain.shouldReportNamespacePrefixes,
             plain.shouldResolveExternalEntities]);
        run(plain, logger, @"without namespaces");

        NSXMLParser *namespaced = [[NSXMLParser alloc] initWithData:[NSData dataWithContentsOfURL:url]];
        namespaced.shouldProcessNamespaces = YES;
        namespaced.shouldReportNamespacePrefixes = YES;
        run(namespaced, logger, @"with namespaces and prefixes");

        NSData *broken = [@"<a>\n  <b>text</a>" dataUsingEncoding:NSUTF8StringEncoding];
        run([[NSXMLParser alloc] initWithData:broken], logger, @"malformed");

        logger.stopAt = @"stop";
        NSData *aborting = [@"<list><item/><stop/><item/></list>" dataUsingEncoding:NSUTF8StringEncoding];
        run([[NSXMLParser alloc] initWithData:aborting], logger, @"aborted");
    }
    return 0;
}
