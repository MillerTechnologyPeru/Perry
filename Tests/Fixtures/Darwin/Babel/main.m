// Expat, parsing in chunks with each kind of handler, namespaces, another
// encoding and errors; and iconv, converting between encodings with its
// errors (errno in Darwin's numbering) and controls.

#import <Foundation/Foundation.h>
#include <errno.h>
#include <expat.h>
#include <iconv.h>
#include <stdio.h>
#include <string.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static NSString *utf8(const XML_Char *text, int length) {
    return [[NSString alloc] initWithBytes:text length:(NSUInteger)length encoding:NSUTF8StringEncoding];
}

// MARK: - Expat

typedef struct {
    NSMutableString *text;
    int depth;
} Context;

static void XMLCALL startElement(void *data, const XML_Char *name, const XML_Char **attributes) {
    Context *context = data;
    NSMutableArray *pairs = [NSMutableArray array];
    for (int i = 0; attributes[i]; i += 2) {
        [pairs addObject:[NSString stringWithFormat:@"%@=%@", [NSString stringWithUTF8String:attributes[i]],
                          [NSString stringWithUTF8String:attributes[i + 1]]]];
    }
    say([NSString stringWithFormat:@"%*sstart %@ {%@}", context->depth * 2, "", [NSString stringWithUTF8String:name],
         [pairs componentsJoinedByString:@", "]]);
    context->depth++;
    [context->text setString:@""];
}

static void XMLCALL endElement(void *data, const XML_Char *name) {
    Context *context = data;
    NSString *text = [context->text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    context->depth--;
    say([NSString stringWithFormat:@"%*send %@%@", context->depth * 2, "", [NSString stringWithUTF8String:name],
         text.length ? [NSString stringWithFormat:@" text '%@'", text] : @""]);
    [context->text setString:@""];
}

static void XMLCALL characters(void *data, const XML_Char *text, int length) {
    [((Context *)data)->text appendString:utf8(text, length)];
}

static void XMLCALL comment(void *data, const XML_Char *text) {
    say([NSString stringWithFormat:@"comment '%s'", text]);
}

static void XMLCALL instruction(void *data, const XML_Char *target, const XML_Char *value) {
    say([NSString stringWithFormat:@"instruction %s '%s'", target, value]);
}

static void XMLCALL declaration(void *data, const XML_Char *version, const XML_Char *encoding, int standalone) {
    say([NSString stringWithFormat:@"declaration %s %s standalone %d", version ?: "-", encoding ?: "-", standalone]);
}

static void XMLCALL startCDATA(void *data) { say(@"CDATA starts"); }
static void XMLCALL endCDATA(void *data) { say(@"CDATA ends"); }

static void XMLCALL startNamespace(void *data, const XML_Char *prefix, const XML_Char *uri) {
    say([NSString stringWithFormat:@"namespace %s = %s", prefix ?: "(default)", uri]);
}

static void XMLCALL endNamespace(void *data, const XML_Char *prefix) {
    say([NSString stringWithFormat:@"namespace %s ends", prefix ?: "(default)"]);
}

static void parse(XML_Parser parser, const char *document, size_t piece, NSString *title) {
    say([NSString stringWithFormat:@"== %@", title]);
    Context context = {[NSMutableString string], 0};
    XML_SetUserData(parser, &context);
    XML_SetElementHandler(parser, startElement, endElement);
    XML_SetCharacterDataHandler(parser, characters);
    XML_SetCommentHandler(parser, comment);
    XML_SetProcessingInstructionHandler(parser, instruction);
    XML_SetXmlDeclHandler(parser, declaration);
    XML_SetCdataSectionHandler(parser, startCDATA, endCDATA);
    size_t length = strlen(document);
    enum XML_Status status = XML_STATUS_OK;
    for (size_t offset = 0; offset < length && status == XML_STATUS_OK; offset += piece) {
        size_t take = MIN(piece, length - offset);
        status = XML_Parse(parser, document + offset, (int)take, offset + take == length);
    }
    if (status != XML_STATUS_OK) {
        enum XML_Error code = XML_GetErrorCode(parser);
        say([NSString stringWithFormat:@"error %d '%s' at %lu:%lu", code, XML_ErrorString(code),
             (unsigned long)XML_GetCurrentLineNumber(parser), (unsigned long)XML_GetCurrentColumnNumber(parser)]);
    } else {
        say(@"parsed");
    }
    XML_ParserFree(parser);
}

static void expat(void) {
    const char *catalog =
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        "<!DOCTYPE shelf [<!ENTITY who \"the reader\">]>\n"
        "<?render mode=\"fast\"?>\n"
        "<shelf owner=\"Zoë\" xmlns:p=\"urn:price\">\n"
        "  <!-- best first -->\n"
        "  <book id=\"1\" p:cost=\"9.50\">Solaris &amp; more for &who;</book>\n"
        "  <note><![CDATA[<raw> & text]]></note>\n"
        "  <empty/>\n"
        "</shelf>\n";
    parse(XML_ParserCreate(NULL), catalog, 7, @"in 7-byte pieces");

    XML_Parser namespaced = XML_ParserCreateNS(NULL, '|');
    XML_SetNamespaceDeclHandler(namespaced, startNamespace, endNamespace);
    parse(namespaced, "<a xmlns=\"urn:a\" xmlns:b=\"urn:b\"><b:c b:d=\"1\" e=\"2\"/></a>", 1000, @"with namespaces");

    // ISO-8859-1 bytes, delivered as UTF-8.
    parse(XML_ParserCreate(NULL), "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?><city name=\"Z\xfcrich\">K\xf6ln</city>",
          1000, @"ISO-8859-1");

    parse(XML_ParserCreate(NULL), "<a>\n  <b>text</a>", 1000, @"mismatched tag");
    parse(XML_ParserCreate(NULL), "<a>&undefined;</a>", 1000, @"undefined entity");
    parse(XML_ParserCreate(NULL), "<a><b>", 1000, @"unclosed");
}

// MARK: - iconv

static NSString *hex(const char *bytes, size_t length) {
    NSMutableString *text = [NSMutableString string];
    for (size_t i = 0; i < length; i++) {
        [text appendFormat:@"%02x", (uint8_t)bytes[i]];
    }
    return text;
}

static void convert(const char *to, const char *from, const char *input, size_t length, size_t room) {
    iconv_t converter = iconv_open(to, from);
    if (converter == (iconv_t)-1) {
        say([NSString stringWithFormat:@"%s <- %s: iconv_open failed, errno %d", to, from, errno]);
        return;
    }
    char output[256];
    char *in = (char *)input, *out = output;
    size_t inLeft = length, outLeft = room;
    errno = 0;
    size_t result = iconv(converter, &in, &inLeft, &out, &outLeft);
    int error = result == (size_t)-1 ? errno : 0;
    say([NSString stringWithFormat:@"%s <- %s: result %ld, errno %d, consumed %zu, wrote %@", to, from,
         result == (size_t)-1 ? -1L : (long)result, error, length - inLeft, hex(output, room - outLeft)]);
    iconv_close(converter);
}

static void iconvChecks(void) {
    const char *polish = "Zażółć gęślą jaźń";
    convert("ISO-8859-2", "UTF-8", polish, strlen(polish), 256);
    convert("UTF-16LE", "UTF-8", "A€😀", strlen("A€😀"), 256);
    convert("UTF-16BE", "UTF-8", "A€😀", strlen("A€😀"), 256);
    convert("WINDOWS-1252", "UTF-8", "€5 “quoted”", strlen("€5 “quoted”"), 256);
    convert("UTF-8", "ISO-8859-1", "caf\xe9", 4, 256);
    convert("ASCII", "UTF-8", "naïve", strlen("naïve"), 256);
    convert("UTF-16LE", "UTF-8", polish, strlen(polish), 9);
    convert("UTF-16LE", "UTF-8", "ab\xc3", 3, 256);
    convert("NO-SUCH-ENCODING", "UTF-8", "x", 1, 256);

    iconv_t converter = iconv_open("UTF-16LE", "UTF-8");
    int value = -1;
    int status = iconvctl(converter, ICONV_GET_TRANSLITERATE, &value);
    say([NSString stringWithFormat:@"iconvctl get transliterate: %d, %d", status, value]);
    size_t reset = iconv(converter, NULL, NULL, NULL, NULL);
    say([NSString stringWithFormat:@"reset %zu", reset]);
    iconv_close(converter);
}

int main(void) {
    @autoreleasepool {
        expat();
        iconvChecks();
    }
    return 0;
}
