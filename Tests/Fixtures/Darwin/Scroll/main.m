// CFXMLParser, CFXMLNode and CFXMLTree, the Mac's XML API before
// NSXMLParser, built on a Mac with Xcode. iOS's SDK doesn't declare them,
// so the types are declared here as macOS's CFXMLNode.h and CFXMLParser.h
// have them, and the functions are found with dlsym: Darwin's in macOS's
// CoreFoundation, for the reference, and Perry's.
#import <Foundation/Foundation.h>
#include <dlfcn.h>

#include <TargetConditionals.h>
#if TARGET_OS_IPHONE
typedef const struct __CFXMLNode *CFXMLNodeRef;
typedef struct __CFXMLParser *CFXMLParserRef;
typedef CFTreeRef CFXMLTreeRef;
typedef CFIndex CFXMLNodeTypeCode;
typedef CFIndex CFXMLParserStatusCode;
enum { kCFXMLNodeTypeDocument = 1, kCFXMLNodeTypeElement = 2, kCFXMLNodeTypeProcessingInstruction = 4,
       kCFXMLNodeTypeText = 6, kCFXMLNodeTypeEntity = 9, kCFXMLNodeTypeEntityReference = 10, kCFXMLNodeTypeDocumentType = 11,
       kCFXMLNodeTypeElementTypeDeclaration = 14, kCFXMLNodeTypeAttributeListDeclaration = 15 };
enum { kCFXMLParserSkipMetaData = 2, kCFXMLParserReplacePhysicalEntities = 4, kCFXMLParserSkipWhitespace = 8 };
typedef struct { CFDictionaryRef attributes; CFArrayRef attributeOrder; Boolean isEmpty; char _reserved[3]; } CFXMLElementInfo;
typedef struct { CFStringRef dataString; } CFXMLProcessingInstructionInfo;
typedef struct { CFURLRef sourceURL; CFStringEncoding encoding; } CFXMLDocumentInfo;
typedef struct { CFURLRef systemID; CFStringRef publicID; } CFXMLExternalID;
typedef struct { CFXMLExternalID externalID; } CFXMLDocumentTypeInfo;
typedef struct { CFStringRef contentDescription; } CFXMLElementTypeDeclarationInfo;
typedef struct { CFStringRef attributeName; CFStringRef typeString; CFStringRef defaultString; } CFXMLAttributeDeclarationInfo;
typedef struct { CFIndex numberOfAttributes; CFXMLAttributeDeclarationInfo *attributes; } CFXMLAttributeListDeclarationInfo;
typedef struct { int entityType; CFStringRef replacementText; CFXMLExternalID entityID; CFStringRef notationName; } CFXMLEntityInfo;
typedef struct { int entityType; } CFXMLEntityReferenceInfo;
typedef struct {
    CFIndex version;
    void *(*createXMLStructure)(CFXMLParserRef, CFXMLNodeRef, void *);
    void (*addChild)(CFXMLParserRef, void *, void *, void *);
    void (*endXMLStructure)(CFXMLParserRef, void *, void *);
    CFDataRef (*resolveExternalEntity)(CFXMLParserRef, CFXMLExternalID *, void *);
    Boolean (*handleError)(CFXMLParserRef, CFXMLParserStatusCode, void *);
} CFXMLParserCallBacks;
#endif

#define FUNCTION(result, name, ...) static result (*X_##name)(__VA_ARGS__)
FUNCTION(CFTypeID, CFXMLNodeGetTypeID, void);
FUNCTION(CFTypeID, CFXMLParserGetTypeID, void);
FUNCTION(CFXMLNodeRef, CFXMLNodeCreate, CFAllocatorRef, CFXMLNodeTypeCode, CFStringRef, const void *, CFIndex);
FUNCTION(CFXMLNodeRef, CFXMLNodeCreateCopy, CFAllocatorRef, CFXMLNodeRef);
FUNCTION(CFXMLNodeTypeCode, CFXMLNodeGetTypeCode, CFXMLNodeRef);
FUNCTION(CFStringRef, CFXMLNodeGetString, CFXMLNodeRef);
FUNCTION(const void *, CFXMLNodeGetInfoPtr, CFXMLNodeRef);
FUNCTION(CFIndex, CFXMLNodeGetVersion, CFXMLNodeRef);
FUNCTION(CFXMLParserRef, CFXMLParserCreate, CFAllocatorRef, CFDataRef, CFURLRef, CFOptionFlags, CFIndex, CFXMLParserCallBacks *, void *);
FUNCTION(Boolean, CFXMLParserParse, CFXMLParserRef);
FUNCTION(CFXMLParserStatusCode, CFXMLParserGetStatusCode, CFXMLParserRef);
FUNCTION(CFStringRef, CFXMLParserCopyErrorDescription, CFXMLParserRef);
FUNCTION(CFIndex, CFXMLParserGetLineNumber, CFXMLParserRef);
FUNCTION(CFIndex, CFXMLParserGetLocation, CFXMLParserRef);
FUNCTION(void *, CFXMLParserGetDocument, CFXMLParserRef);
FUNCTION(CFXMLTreeRef, CFXMLTreeCreateFromData, CFAllocatorRef, CFDataRef, CFURLRef, CFOptionFlags, CFIndex);
FUNCTION(CFXMLTreeRef, CFXMLTreeCreateFromDataWithError, CFAllocatorRef, CFDataRef, CFURLRef, CFOptionFlags, CFIndex, CFDictionaryRef *);
FUNCTION(CFXMLTreeRef, CFXMLTreeCreateWithNode, CFAllocatorRef, CFXMLNodeRef);
FUNCTION(CFXMLNodeRef, CFXMLTreeGetNode, CFXMLTreeRef);
FUNCTION(CFDataRef, CFXMLTreeCreateXMLData, CFAllocatorRef, CFXMLTreeRef);
FUNCTION(CFStringRef, CFXMLCreateStringByEscapingEntities, CFAllocatorRef, CFStringRef, CFDictionaryRef);
FUNCTION(CFStringRef, CFXMLCreateStringByUnescapingEntities, CFAllocatorRef, CFStringRef, CFDictionaryRef);

#define FIND(name) X_##name = dlsym(RTLD_DEFAULT, #name); if (!X_##name) { printf("missing %s\n", #name); return 1; }

static void print(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static NSString *flat(CFStringRef string) {
    return string ? [(__bridge NSString *)string stringByReplacingOccurrencesOfString:@"\n" withString:@"|"] : @"(null)";
}

static long counter;

static void *create(CFXMLParserRef parser, CFXMLNodeRef node, void *info) {
    CFXMLNodeTypeCode type = X_CFXMLNodeGetTypeCode(node);
    const void *details = X_CFXMLNodeGetInfoPtr(node);
    NSMutableString *line = [NSMutableString stringWithFormat:@"create %ld [%@] v%ld", (long)type, flat(X_CFXMLNodeGetString(node)),
                             (long)X_CFXMLNodeGetVersion(node)];
    if (type == kCFXMLNodeTypeElement) {
        const CFXMLElementInfo *element = details;
        [line appendFormat:@" empty %d attributes", element->isEmpty];
        for (CFIndex i = 0; element->attributeOrder && i < CFArrayGetCount(element->attributeOrder); i++) {
            CFStringRef key = CFArrayGetValueAtIndex(element->attributeOrder, i);
            [line appendFormat:@" %@=%@", key, CFDictionaryGetValue(element->attributes, key)];
        }
    } else if (type == kCFXMLNodeTypeProcessingInstruction) {
        [line appendFormat:@" data [%@]", flat(((const CFXMLProcessingInstructionInfo *)details)->dataString)];
    } else if (type == kCFXMLNodeTypeDocument) {
        const CFXMLDocumentInfo *document = details;
        [line appendFormat:@" encoding %u url %d", (unsigned)document->encoding, document->sourceURL != NULL];
    } else if (type == kCFXMLNodeTypeDocumentType) {
        const CFXMLDocumentTypeInfo *doctype = details;
        [line appendFormat:@" system %@ public %@", doctype->externalID.systemID ? (__bridge NSString *)CFURLGetString(doctype->externalID.systemID) : @"-",
                           flat(doctype->externalID.publicID)];
    } else if (type == kCFXMLNodeTypeEntityReference) {
        [line appendFormat:@" entity type %d", ((const CFXMLEntityReferenceInfo *)details)->entityType];
    } else if (type == kCFXMLNodeTypeEntity) {
        const CFXMLEntityInfo *entity = details;
        [line appendFormat:@" entity type %d text [%@]", entity->entityType, flat(entity->replacementText)];
    } else if (type == kCFXMLNodeTypeElementTypeDeclaration) {
        [line appendFormat:@" content [%@]", flat(((const CFXMLElementTypeDeclarationInfo *)details)->contentDescription)];
    } else if (type == kCFXMLNodeTypeAttributeListDeclaration) {
        const CFXMLAttributeListDeclarationInfo *list = details;
        [line appendFormat:@" %ld", (long)list->numberOfAttributes];
        for (CFIndex i = 0; i < list->numberOfAttributes; i++) {
            [line appendFormat:@" (%@ %@ %@)", list->attributes[i].attributeName, list->attributes[i].typeString, list->attributes[i].defaultString];
        }
    }
    [line appendFormat:@" line %ld location %ld", (long)X_CFXMLParserGetLineNumber(parser), (long)X_CFXMLParserGetLocation(parser)];
    print(line);
    return (void *)++counter;
}

static void addChild(CFXMLParserRef parser, void *parent, void *child, void *info) {
    print([NSString stringWithFormat:@"add %ld <- %ld", (long)parent, (long)child]);
}

static void end(CFXMLParserRef parser, void *structure, void *info) { print([NSString stringWithFormat:@"end %ld", (long)structure]); }

static Boolean handleError(CFXMLParserRef parser, CFXMLParserStatusCode code, void *info) {
    print([NSString stringWithFormat:@"error %ld", (long)code]);
    return false;
}

static void parse(NSString *label, const char *xml, CFOptionFlags options) {
    print([NSString stringWithFormat:@"== %@ options %lu", label, (unsigned long)options]);
    counter = 0;
    CFDataRef data = CFDataCreate(NULL, (const UInt8 *)xml, strlen(xml));
    CFXMLParserCallBacks callbacks = {0, create, addChild, end, NULL, handleError};
    CFXMLParserRef parser = X_CFXMLParserCreate(NULL, data, NULL, options, 1, &callbacks, NULL);
    print([NSString stringWithFormat:@"parser type %d", CFGetTypeID(parser) == X_CFXMLParserGetTypeID()]);
    Boolean parsed = X_CFXMLParserParse(parser);
    CFStringRef description = X_CFXMLParserCopyErrorDescription(parser);
    print([NSString stringWithFormat:@"parsed %d status %ld document %ld error [%@] line %ld", parsed, (long)X_CFXMLParserGetStatusCode(parser),
           (long)X_CFXMLParserGetDocument(parser), description ? (__bridge NSString *)description : @"-", (long)X_CFXMLParserGetLineNumber(parser)]);
    if (description) CFRelease(description);
    CFRelease(parser);
    CFRelease(data);
}

int main(void) {
    @autoreleasepool {
        FIND(CFXMLNodeGetTypeID) FIND(CFXMLParserGetTypeID) FIND(CFXMLNodeCreate) FIND(CFXMLNodeCreateCopy) FIND(CFXMLNodeGetTypeCode)
        FIND(CFXMLNodeGetString) FIND(CFXMLNodeGetInfoPtr) FIND(CFXMLNodeGetVersion) FIND(CFXMLParserCreate) FIND(CFXMLParserParse)
        FIND(CFXMLParserGetStatusCode) FIND(CFXMLParserCopyErrorDescription) FIND(CFXMLParserGetLineNumber) FIND(CFXMLParserGetLocation)
        FIND(CFXMLParserGetDocument) FIND(CFXMLTreeCreateFromData) FIND(CFXMLTreeCreateFromDataWithError) FIND(CFXMLTreeCreateWithNode)
        FIND(CFXMLTreeGetNode) FIND(CFXMLTreeCreateXMLData) FIND(CFXMLCreateStringByEscapingEntities) FIND(CFXMLCreateStringByUnescapingEntities)

        const char *document = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE note SYSTEM \"note.dtd\" [\n<!ELEMENT note (to,body)>\n"
            "<!ATTLIST note id CDATA #IMPLIED>\n<!ENTITY who \"World\">\n]>\n<!-- a comment -->\n<?app run fast?>\n"
            "<note id=\"1\" lang='en'>\n  <to>A &amp; B &#65;&#x42; &who;</to>\n  <body><![CDATA[x < y]]></body>\n  <empty/>\n</note>\n";
        parse(@"everything", document, 0);
        parse(@"no whitespace or metadata", document, kCFXMLParserSkipWhitespace | kCFXMLParserSkipMetaData);
        parse(@"entities replaced", document, kCFXMLParserReplacePhysicalEntities | kCFXMLParserSkipWhitespace);
        parse(@"mismatched", "<a><b></a>", 0);
        parse(@"unclosed", "<a>text", 0);

        print([NSString stringWithFormat:@"escaped [%@]", CFBridgingRelease(X_CFXMLCreateStringByEscapingEntities(NULL, CFSTR("a < b & c > \"d\" 'e'"), NULL))]);
        print([NSString stringWithFormat:@"unescaped [%@]", CFBridgingRelease(X_CFXMLCreateStringByUnescapingEntities(NULL,
               CFSTR("&lt;x&gt; &amp; &#65;&#x42; &quot;&apos; &bogus;"), NULL))]);

        const char *small = "<r a=\"1\"><c>t</c><d/></r>";
        CFDataRef data = CFDataCreate(NULL, (const UInt8 *)small, strlen(small));
        CFXMLTreeRef tree = X_CFXMLTreeCreateFromData(NULL, data, NULL, kCFXMLParserSkipWhitespace, 1);
        CFXMLTreeRef root = CFTreeGetFirstChild(tree);
        print([NSString stringWithFormat:@"tree children %ld document %d root [%@] children %ld", (long)CFTreeGetChildCount(tree),
               X_CFXMLNodeGetTypeCode(X_CFXMLTreeGetNode(tree)) == kCFXMLNodeTypeDocument, X_CFXMLNodeGetString(X_CFXMLTreeGetNode(root)),
               (long)CFTreeGetChildCount(root)]);
        CFDataRef written = X_CFXMLTreeCreateXMLData(NULL, tree);
        print([NSString stringWithFormat:@"written [%.*s]", (int)CFDataGetLength(written), CFDataGetBytePtr(written)]);
        CFRelease(written);
        CFRelease(tree);
        CFRelease(data);

        CFDictionaryRef error = NULL;
        CFDataRef bad = CFDataCreate(NULL, (const UInt8 *)"<a><b></a>", 10);
        CFXMLTreeRef failed = X_CFXMLTreeCreateFromDataWithError(NULL, bad, NULL, 0, 1, &error);
        NSDictionary *details = (__bridge NSDictionary *)error;
        print([NSString stringWithFormat:@"failed %d %@ line %@ location %@ status %@", failed != NULL, details[@"kCFXMLTreeErrorDescription"],
               details[@"kCFXMLTreeErrorLineNumber"], details[@"kCFXMLTreeErrorLocation"], details[@"kCFXMLTreeErrorStatusCode"]]);

        CFXMLNodeRef text = X_CFXMLNodeCreate(NULL, kCFXMLNodeTypeText, CFSTR("hi"), NULL, 1);
        CFXMLNodeRef copy = X_CFXMLNodeCreateCopy(NULL, text);
        CFXMLElementInfo elementInfo = {(__bridge CFDictionaryRef)@{@"k": @"v"}, (__bridge CFArrayRef)@[@"k"], true};
        CFXMLNodeRef element = X_CFXMLNodeCreate(NULL, kCFXMLNodeTypeElement, CFSTR("e"), &elementInfo, 1);
        CFXMLTreeRef made = X_CFXMLTreeCreateWithNode(NULL, element);
        CFXMLTreeRef child = X_CFXMLTreeCreateWithNode(NULL, text);
        CFTreeAppendChild(made, child);
        CFDataRef out = X_CFXMLTreeCreateXMLData(NULL, made);
        print([NSString stringWithFormat:@"node type %d text [%@] copy [%@] equal %d made [%.*s]", CFGetTypeID(text) == X_CFXMLNodeGetTypeID(),
               X_CFXMLNodeGetString(text), X_CFXMLNodeGetString(copy), CFEqual(text, copy), (int)CFDataGetLength(out), CFDataGetBytePtr(out)]);
    }
    return 0;
}
