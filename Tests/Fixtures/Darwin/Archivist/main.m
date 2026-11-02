// Property lists (XML, binary and OpenStep, reading, writing and
// validation) and keyed archives (a graph of an app's NSSecureCoding class
// with a cycle, collections and Foundation values; secure decoding; an
// archiver with its own keys in XML). Archives are printed as XML property
// lists, so their structure is compared exactly.

#import <Foundation/Foundation.h>
#include <stdio.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static NSString *xml(id plist) {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

static NSString *archiveXML(NSData *archive) {
    NSPropertyListFormat format = 0;
    id plist = [NSPropertyListSerialization propertyListWithData:archive options:0 format:&format error:NULL];
    return [NSString stringWithFormat:@"format %lu\n%@", (unsigned long)format, xml(plist)];
}

@interface Note : NSObject <NSSecureCoding>
@property (copy) NSString *title;
@property NSInteger count;
@property BOOL done;
@property double score;
@property (copy) NSArray<NSString *> *tags;
@property (weak) Note *parent;
@property (strong) Note *child;
@property (copy) NSData *payload;
@property (copy) NSDate *created;
@property (copy) NSDictionary<NSString *, NSNumber *> *extra;
@end

@implementation Note
+ (BOOL)supportsSecureCoding { return YES; }
- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.title forKey:@"title"];
    [coder encodeInteger:self.count forKey:@"count"];
    [coder encodeBool:self.done forKey:@"done"];
    [coder encodeDouble:self.score forKey:@"score"];
    [coder encodeObject:self.tags forKey:@"tags"];
    [coder encodeConditionalObject:self.parent forKey:@"parent"];
    [coder encodeObject:self.child forKey:@"child"];
    [coder encodeObject:self.payload forKey:@"payload"];
    [coder encodeObject:self.created forKey:@"created"];
    [coder encodeObject:self.extra forKey:@"extra"];
    [coder encodeInt32:-7 forKey:@"small"];
}
- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super init])) {
        _title = [coder decodeObjectOfClass:NSString.class forKey:@"title"];
        _count = [coder decodeIntegerForKey:@"count"];
        _done = [coder decodeBoolForKey:@"done"];
        _score = [coder decodeDoubleForKey:@"score"];
        _tags = [coder decodeArrayOfObjectsOfClass:NSString.class forKey:@"tags"];
        _parent = [coder decodeObjectOfClass:Note.class forKey:@"parent"];
        _child = [coder decodeObjectOfClass:Note.class forKey:@"child"];
        _payload = [coder decodeObjectOfClass:NSData.class forKey:@"payload"];
        _created = [coder decodeObjectOfClass:NSDate.class forKey:@"created"];
        _extra = [coder decodeDictionaryWithKeysOfClass:NSString.class objectsOfClass:NSNumber.class forKey:@"extra"];
    }
    return self;
}
@end

static void propertyLists(void) {
    NSDictionary *plist = @{
        @"name": @"Perry & <friends>",
        @"count": @42,
        @"ratio": @0.25,
        @"negative": @-3,
        @"enabled": @YES,
        @"disabled": @NO,
        @"when": [NSDate dateWithTimeIntervalSince1970:1710052215],
        @"bytes": [@"hi!" dataUsingEncoding:NSUTF8StringEncoding],
        @"list": @[@"a", @1, @[], @{}],
        @"nested": @{@"z": @"last", @"a": @"first"},
        @"unicode": @"café ✓",
    };
    say(xml(plist));

    NSError *error = nil;
    NSData *binary = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
    NSPropertyListFormat format = 0;
    id back = [NSPropertyListSerialization propertyListWithData:binary options:NSPropertyListImmutable format:&format error:NULL];
    say([NSString stringWithFormat:@"binary: %@, round trip %d, format %lu, error %@",
         [[NSString alloc] initWithData:[binary subdataWithRange:NSMakeRange(0, 8)] encoding:NSASCIIStringEncoding],
         [back isEqual:plist], (unsigned long)format, error]);

    NSData *openStep = [@"{ name = \"Open Step\"; list = (a, \"b c\", <0102ff>); nested = { key = value; }; }" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *parsed = [NSPropertyListSerialization propertyListWithData:openStep options:0 format:&format error:&error];
    say([NSString stringWithFormat:@"openstep: format %lu, %@ / %@ / %@ / %@", (unsigned long)format, parsed[@"name"],
         [parsed[@"list"] componentsJoinedByString:@"|"], parsed[@"nested"][@"key"], [parsed[@"list"][2] class] == nil ? @"?" :
         @([parsed[@"list"][2] isKindOfClass:NSData.class])]);

    NSDictionary *mutable = [NSPropertyListSerialization propertyListWithData:[xml(@{@"a": @[@"x"]}) dataUsingEncoding:NSUTF8StringEncoding]
                                                                      options:NSPropertyListMutableContainers format:&format error:NULL];
    NSDictionary *immutable = [NSPropertyListSerialization propertyListWithData:binary options:NSPropertyListImmutable format:NULL error:NULL];
    say([NSString stringWithFormat:@"mutability: format %lu, mutable %d %d, immutable %d",
         (unsigned long)format, [mutable isKindOfClass:NSMutableDictionary.class], [mutable[@"a"] isKindOfClass:NSMutableArray.class],
         [immutable isKindOfClass:NSMutableDictionary.class]]);

    id corrupt = [NSPropertyListSerialization propertyListWithData:[@"<plist><dict><key>x</dict>" dataUsingEncoding:NSUTF8StringEncoding]
                                                           options:0 format:NULL error:&error];
    NSError *writeError = nil;
    NSData *invalid = [NSPropertyListSerialization dataWithPropertyList:@{@"null": NSNull.null} format:NSPropertyListXMLFormat_v1_0
                                                                options:0 error:&writeError];
    say([NSString stringWithFormat:@"errors: %@ %@ %ld; write %@ %@ %ld; valid %d %d %d", corrupt, error.domain, (long)error.code, invalid,
         writeError.domain, (long)writeError.code,
         [NSPropertyListSerialization propertyList:plist isValidForFormat:NSPropertyListXMLFormat_v1_0],
         [NSPropertyListSerialization propertyList:@[NSNull.null] isValidForFormat:NSPropertyListBinaryFormat_v1_0],
         [NSPropertyListSerialization propertyList:@{@1: @"x"} isValidForFormat:NSPropertyListXMLFormat_v1_0]]);
}

static void archives(void) {
    Note *root = [Note new];
    root.title = @"Groceries";
    root.count = 3;
    root.done = NO;
    root.score = 4.5;
    root.tags = @[@"home", @"weekly"];
    root.payload = [@"xyz" dataUsingEncoding:NSUTF8StringEncoding];
    root.created = [NSDate dateWithTimeIntervalSinceReferenceDate:700000000];
    root.extra = @{@"priority": @2};
    Note *child = [Note new];
    child.title = @"Milk";
    child.done = YES;
    child.parent = root;
    root.child = child;

    NSError *error = nil;
    NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:root requiringSecureCoding:YES error:&error];
    say([NSString stringWithFormat:@"archive: error %@", error]);
    say(archiveXML(archive));

    Note *decoded = [NSKeyedUnarchiver unarchivedObjectOfClass:Note.class fromData:archive error:&error];
    say([NSString stringWithFormat:@"decoded: %@ %ld %d %.1f %@ %@ %@ %@, child %@ %d, cycle %d, error %@", decoded.title, (long)decoded.count,
         decoded.done, decoded.score, [decoded.tags componentsJoinedByString:@","],
         [[NSString alloc] initWithData:decoded.payload encoding:NSUTF8StringEncoding],
         @(decoded.created.timeIntervalSinceReferenceDate), decoded.extra[@"priority"], decoded.child.title, decoded.child.done,
         decoded.child.parent == decoded, error]);

    NSError *classError = nil;
    id wrong = [NSKeyedUnarchiver unarchivedObjectOfClass:NSString.class fromData:archive error:&classError];
    say([NSString stringWithFormat:@"wrong class: %@ %@ %ld", wrong, classError.domain, (long)classError.code]);

    NSData *collection = [NSKeyedArchiver archivedDataWithRootObject:@[@"one", @2, @3.5, @YES, [NSNull null],
        [NSURL URLWithString:@"https://example.com/a"], [NSSet setWithObject:@"s"], [@"mut" mutableCopy],
        [[NSUUID alloc] initWithUUIDString:@"E621E1F8-C36C-495A-93FC-0C247A3E6E5F"]] requiringSecureCoding:NO error:NULL];
    say(archiveXML(collection));
    NSArray *roundTrip = [NSKeyedUnarchiver unarchivedObjectOfClasses:[NSSet setWithObjects:NSArray.class, NSString.class, NSNumber.class,
        NSNull.class, NSURL.class, NSSet.class, NSUUID.class, nil] fromData:collection error:&error];
    say([NSString stringWithFormat:@"collection: %lu items, %@ %@ %@ %@, error %@", (unsigned long)roundTrip.count, roundTrip[0],
         [roundTrip[5] absoluteString], [roundTrip[8] UUIDString], [roundTrip[7] class] == nil ? @"?" : @([roundTrip[7] isKindOfClass:NSString.class]),
         error]);

    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initRequiringSecureCoding:NO];
    archiver.outputFormat = NSPropertyListXMLFormat_v1_0;
    [archiver encodeObject:@"hello" forKey:@"greeting"];
    [archiver encodeInteger:42 forKey:@"answer"];
    [archiver encodeBool:YES forKey:@"flag"];
    [archiver encodeObject:nil forKey:@"nothing"];
    [archiver finishEncoding];
    NSData *encoded = archiver.encodedData;
    say([[NSString alloc] initWithData:encoded encoding:NSUTF8StringEncoding]);
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData:encoded error:NULL];
    unarchiver.requiresSecureCoding = NO;
    say([NSString stringWithFormat:@"read back: %@ %ld %d, nothing %@, has answer %d missing %d",
         [unarchiver decodeObjectForKey:@"greeting"], (long)[unarchiver decodeIntegerForKey:@"answer"],
         [unarchiver decodeBoolForKey:@"flag"], [unarchiver decodeObjectForKey:@"nothing"],
         [unarchiver containsValueForKey:@"answer"], [unarchiver containsValueForKey:@"missing"]]);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        propertyLists();
        archives();
    }
    return 0;
}
