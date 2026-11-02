// libxml2 from Objective-C: KissXML (parsing, queries, XPath, editing and
// serializing a tree over libxml2), then libxml2's variadic API called
// directly: string formatting, the text writer's format functions, the
// parser's error reporters and a custom generic error handler.

#import <Foundation/Foundation.h>
#import <libxml/parser.h>
#import <libxml/xmlwriter.h>
#import "DDXML.h"
#include <stdarg.h>
#include <stdio.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static NSString *const sample =
    @"<?xml version=\"1.0\"?>"
    @"<library xmlns:dc=\"http://purl.org/dc/elements/1.1/\" city=\"Kraków\">"
    @"<book id=\"1\" lang=\"en\"><dc:title>Dune</dc:title><year>1965</year></book>"
    @"<book id=\"2\"><dc:title>Solaris &amp; more</dc:title><year>1961</year></book>"
    @"<!-- shelved -->"
    @"</library>";

static void kissXML(void) {
    NSError *error = nil;
    DDXMLDocument *document = [[DDXMLDocument alloc] initWithXMLString:sample options:0 error:&error];
    DDXMLElement *library = document.rootElement;
    say([NSString stringWithFormat:@"root %@, children %lu, city %@", library.name,
         (unsigned long)library.childCount, [library attributeForName:@"city"].stringValue]);

    for (DDXMLElement *book in [library elementsForName:@"book"]) {
        DDXMLElement *title = [book elementsForLocalName:@"title" URI:@"http://purl.org/dc/elements/1.1/"].firstObject;
        say([NSString stringWithFormat:@"book %@: %@ (%@), title prefix %@, lang %@",
             [book attributeForName:@"id"].stringValue, title.stringValue,
             [book elementForName:@"year"].stringValue, title.prefix,
             [book attributeForName:@"lang"].stringValue ?: @"none"]);
    }

    NSArray *old = [document nodesForXPath:@"//book[year < 1964]/@id" error:&error];
    say([NSString stringWithFormat:@"XPath: %lu result, id %@", (unsigned long)old.count, [old.firstObject stringValue]]);
    NSMutableArray *titles = [NSMutableArray array];
    for (DDXMLNode *text in [library nodesForXPath:@"//dc:title/text()" error:&error]) {
        [titles addObject:text.stringValue];
    }
    say([NSString stringWithFormat:@"titles %@", [titles componentsJoinedByString:@" | "]]);
    DDXMLNode *comment = library.children.lastObject;
    say([NSString stringWithFormat:@"last child kind %lu, text '%@'", (unsigned long)comment.kind, comment.stringValue]);

    // Editing.
    DDXMLElement *added = [DDXMLElement elementWithName:@"book"];
    [added addAttributeWithName:@"id" stringValue:@"3"];
    [added addChild:[DDXMLElement elementWithName:@"year" stringValue:@"1974"]];
    [library insertChild:added atIndex:0];
    [library removeChildAtIndex:library.childCount - 1];
    [[library attributeForName:@"city"] setStringValue:@"Gdańsk <old>"];
    say([NSString stringWithFormat:@"edited: %@", library.XMLString]);
    say([NSString stringWithFormat:@"pretty:\n%@", [document XMLStringWithOptions:DDXMLNodePrettyPrint]]);

    // A tree built from nothing.
    DDXMLElement *feed = [DDXMLElement elementWithName:@"feed"];
    [feed addNamespace:[DDXMLNode namespaceWithName:@"" stringValue:@"http://www.w3.org/2005/Atom"]];
    DDXMLElement *entry = [DDXMLElement elementWithName:@"entry"];
    [entry addChild:[DDXMLElement elementWithName:@"title" stringValue:@"5 < 7 & \"quotes\""]];
    [feed addChild:entry];
    DDXMLElement *copy = [entry copy];
    [feed addChild:copy];
    say([NSString stringWithFormat:@"built: %@, entries %lu, copy has parent %d", feed.XMLString,
         (unsigned long)[feed elementsForName:@"entry"].count, copy.parent == feed]);
    [entry detach];
    say([NSString stringWithFormat:@"detached: %@ / %@", feed.XMLString, entry.XMLString]);

    DDXMLDocument *broken = [[DDXMLDocument alloc] initWithXMLString:@"<open><unclosed></open>" options:0 error:&error];
    say([NSString stringWithFormat:@"broken: document %d, error %@ %ld", broken != nil, error.domain, (long)error.code]);
}

// MARK: - libxml2's variadic API

static NSMutableString *reported;

/// A generic error handler: Darwin code, called with Darwin's varargs.
static void collect(void *context, const char *msg, ...) {
    va_list ap;
    va_start(ap, msg);
    char line[512];
    vsnprintf(line, sizeof line, msg, ap);
    va_end(ap);
    [(__bridge NSMutableString *)context appendFormat:@"%s", line];
}

static int formatInto(xmlChar *buffer, int size, const char *format, ...) {
    va_list ap;
    va_start(ap, format);
    int length = xmlStrVPrintf(buffer, size, format, ap);
    va_end(ap);
    return length;
}

static void variadicAPI(void) {
    xmlChar buffer[128];
    int length = xmlStrPrintf(buffer, sizeof buffer, "%s has %d books, %.1f%% read, %c%c", "library", 3, 62.5, 'o', 'k');
    say([NSString stringWithFormat:@"xmlStrPrintf %d: %s", length, buffer]);
    length = formatInto(buffer, sizeof buffer, "%05d|%-6s|%x|%ld", 42, "pad", 255, 1234567890123L);
    say([NSString stringWithFormat:@"xmlStrVPrintf %d: %s", length, buffer]);

    xmlBufferPtr output = xmlBufferCreate();
    xmlTextWriterPtr writer = xmlNewTextWriterMemory(output, 0);
    xmlTextWriterSetIndent(writer, 1);
    xmlTextWriterStartDocument(writer, NULL, "UTF-8", NULL);
    xmlTextWriterWriteFormatComment(writer, "generated by %s, run %d", "scribe", 7);
    xmlTextWriterStartElement(writer, BAD_CAST "report");
    xmlTextWriterWriteFormatAttribute(writer, BAD_CAST "count", "%d", 3);
    xmlTextWriterWriteFormatAttributeNS(writer, BAD_CAST "x", BAD_CAST "unit", BAD_CAST "urn:units", "%s-%d", "kg", 2);
    xmlTextWriterWriteFormatElement(writer, BAD_CAST "total", "%.2f", 12.5);
    xmlTextWriterWriteFormatElementNS(writer, BAD_CAST "x", BAD_CAST "note", BAD_CAST "urn:units", "%s & %s", "a", "b");
    xmlTextWriterStartElement(writer, BAD_CAST "body");
    xmlTextWriterWriteFormatString(writer, "%d < %d", 1, 2);
    xmlTextWriterWriteFormatCDATA(writer, "raw %s", "<data>");
    xmlTextWriterEndElement(writer);
    xmlTextWriterWriteFormatPI(writer, BAD_CAST "render", "mode=\"%s\"", "fast");
    xmlTextWriterEndDocument(writer);
    xmlFreeTextWriter(writer);
    say([NSString stringWithFormat:@"writer:\n%s", (const char *)xmlBufferContent(output)]);
    xmlBufferFree(output);

    // Errors go to a handler of ours, Darwin code that libxml2 calls back.
    reported = [NSMutableString string];
    xmlSetStructuredErrorFunc(NULL, NULL);
    xmlSetGenericErrorFunc((__bridge void *)reported, collect);
    xmlDocPtr bad = xmlReadMemory("<a><b>text</a>", 14, "memory.xml", NULL, 0);
    say([NSString stringWithFormat:@"read: document %d, errors:\n%@", bad != NULL, reported]);
    if (bad) xmlFreeDoc(bad);

    [reported setString:@""];
    xmlParserWarning(NULL, "warning %d of %s\n", 1, "two");
    xmlParserError(NULL, "error %s\n", "here");
    xmlGenericError(xmlGenericErrorContext, "direct %d%%\n", 100);
    say([NSString stringWithFormat:@"reported:\n%@", reported]);
    say([NSString stringWithFormat:@"handler is ours %d", xmlGenericError == collect]);

    xmlChar *copied = xmlStrdup(BAD_CAST "freed by xmlFree");
    say([NSString stringWithFormat:@"%s, length %d", copied, xmlStrlen(copied)]);
    xmlFree(copied);
}

int main(void) {
    @autoreleasepool {
        kissXML();
        variadicAPI();
    }
    return 0;
}
