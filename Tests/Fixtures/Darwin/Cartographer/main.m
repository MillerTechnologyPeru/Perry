// URLs, files, bundles, data, ports and streams, built on a Mac with Xcode:
// NSURL's relative file URLs, data representations, alias resolution and
// resource values; NSFileManager's comparing, linking and iCloud answers;
// NSFileVersion, NSFileSecurity, NSPurgeableData, NSData's compression,
// NSFileWrapper's serialized form, stream properties and port messages.
// Works in a new temporary directory and prints only names relative to it.
#import <Foundation/Foundation.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static void print(NSString *line) {
    printf("%s\n", line.UTF8String);
}

#define P(...) print([NSString stringWithFormat:__VA_ARGS__])

static NSString *hex(NSData *data) {
    NSMutableString *text = [NSMutableString string];
    const unsigned char *bytes = data.bytes;
    for (NSUInteger i = 0; i < data.length; i++) [text appendFormat:@"%02x", bytes[i]];
    return text;
}

static NSData *unhex(NSString *text) {
    NSMutableData *data = [NSMutableData data];
    for (NSUInteger i = 0; i + 1 < text.length; i += 2) {
        unsigned char byte = (unsigned char)strtoul([[text substringWithRange:NSMakeRange(i, 2)] UTF8String], NULL, 16);
        [data appendBytes:&byte length:1];
    }
    return data;
}

static NSString *text(NSData *data) {
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"(nil)";
}

/// Runs the run loop until `done` is set, or a while passes.
static void waitFor(volatile BOOL *done) {
    for (int i = 0; i < 100 && !*done; i++) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
}

/// What a port's delegate is given (NSPortMessage, whose header iOS lacks).
@protocol CartographerPortMessage
- (uint32_t)msgid;
- (NSArray *)components;
- (NSPort *)receivePort;
- (NSPort *)sendPort;
@end

@interface CartographerPortDelegate : NSObject <NSPortDelegate>
@property (nonatomic, strong) NSPort *reply;
@property (nonatomic) BOOL done;
@end

@implementation CartographerPortDelegate
- (void)handlePortMessage:(id)message {
    id<CartographerPortMessage> m = message;
    NSArray *parts = m.components;
    P(@"port message msgid=%u parts=%lu first=%@ secondIsReply=%d receive=%@ sendIsReply=%d", m.msgid,
      (unsigned long)parts.count, text(parts.firstObject), parts.count > 1 && parts[1] == self.reply,
      NSStringFromClass([m.receivePort class]), m.sendPort == self.reply);
    self.done = YES;
}
@end

static void urls(void) {
    NSURL *base = [NSURL fileURLWithPath:@"/tmp/base/" isDirectory:YES];
    NSURL *r = [NSURL fileURLWithPath:@"b.txt" relativeToURL:base];
    P(@"relative %@ | %@ | %@ | %@", r.relativeString, r.baseURL.absoluteString, r.absoluteString, r.path);
    r = [NSURL fileURLWithPath:@"/abs/b.txt" relativeToURL:base];
    P(@"absolute %@ | %@", r.relativeString, r.baseURL);
    r = [NSURL fileURLWithPath:@"d" isDirectory:YES relativeToURL:base];
    P(@"directory %@ | %@", r.relativeString, r.absoluteString);
    r = [[NSURL alloc] initFileURLWithPath:@"x y" relativeToURL:base];
    P(@"init %@ | %@", r.relativeString, r.absoluteString);
    r = [[NSURL alloc] initFileURLWithPath:@"e" isDirectory:NO relativeToURL:base];
    P(@"init directory %@ | %d", r.absoluteString, r.hasDirectoryPath);
    r = [NSURL fileURLWithFileSystemRepresentation:"q.txt" isDirectory:NO relativeToURL:base];
    P(@"file system %@ | %@", r.relativeString, r.absoluteString);
    r = [NSURL fileURLWithFileSystemRepresentation:"/q/" isDirectory:YES relativeToURL:base];
    P(@"file system absolute %@ | %@", r.relativeString, r.baseURL);

    char small[8], big[64];
    P(@"get small %d", [[NSURL fileURLWithPath:@"/tmp/abcdefghij"] getFileSystemRepresentation:small maxLength:sizeof small]);
    BOOL ok = [[NSURL fileURLWithPath:@"/tmp/abc"] getFileSystemRepresentation:big maxLength:sizeof big];
    P(@"get %d %s", ok, big);
    ok = [[NSURL URLWithString:@"http://x/y%20z"] getFileSystemRepresentation:big maxLength:sizeof big];
    P(@"get web %d %s", ok, big);

    NSURL *web = [NSURL URLWithString:@"http://example.com/a%20b?q=1#f"];
    P(@"data %@", text(web.dataRepresentation));
    P(@"data relative %@", text([NSURL URLWithString:@"c/d?x" relativeToURL:web].dataRepresentation));
    NSURL *fromData = [NSURL URLWithDataRepresentation:[@"path/x y" dataUsingEncoding:NSUTF8StringEncoding] relativeToURL:web];
    P(@"from data %@ | %@ | %@", fromData.relativeString, fromData.baseURL, fromData.absoluteString);
    fromData = [NSURL absoluteURLWithDataRepresentation:[@"path/x" dataUsingEncoding:NSUTF8StringEncoding] relativeToURL:web];
    P(@"absolute data %@ | %@", fromData.relativeString, fromData.baseURL);
    const unsigned char latin[] = {'a', 0xe9, 'b'};
    P(@"latin %@", [NSURL URLWithDataRepresentation:[NSData dataWithBytes:latin length:3] relativeToURL:nil].relativeString);
    P(@"init data %@", [[NSURL alloc] initWithDataRepresentation:[@"http://a/b" dataUsingEncoding:NSUTF8StringEncoding] relativeToURL:nil]);
    fromData = [[NSURL alloc] initAbsoluteURLWithDataRepresentation:[@"z" dataUsingEncoding:NSUTF8StringEncoding] relativeToURL:web];
    P(@"init absolute %@ base=%@", fromData, fromData.baseURL);
}

/// Keys newer than iOS 15 are named by their values, which are their names.
static void aliasesAndValues(void) {
    NSError *error = nil;
    NSURL *resolved = [NSURL URLByResolvingAliasFileAtURL:[NSURL fileURLWithPath:@"link.txt"] options:0 error:&error];
    P(@"alias link %@ %@", resolved.lastPathComponent, error);
    resolved = [NSURL URLByResolvingAliasFileAtURL:[NSURL fileURLWithPath:@"a.txt"] options:0 error:&error];
    P(@"alias file %@ %@", resolved.lastPathComponent, error);
    resolved = [NSURL URLByResolvingAliasFileAtURL:[NSURL fileURLWithPath:@"none.txt"] options:0 error:&error];
    P(@"alias missing %@ %@", resolved.lastPathComponent, error);
    resolved = [NSURL URLByResolvingAliasFileAtURL:[NSURL URLWithString:@"http://x/y"] options:0 error:&error];
    P(@"alias web %@ %@", resolved, error);

    NSURL *a = [NSURL fileURLWithPath:@"a.txt"];
    NSData *bookmark = [a bookmarkDataWithOptions:0 includingResourceValuesForKeys:nil relativeToURL:nil error:&error];
    BOOL stale = YES;
    NSURL *back = [[NSURL alloc] initByResolvingBookmarkData:bookmark options:0 relativeToURL:nil bookmarkDataIsStale:&stale error:&error];
    P(@"bookmark %@ stale=%d", back.lastPathComponent, stale);
    error = nil;
    back = [[NSURL alloc] initByResolvingBookmarkData:[NSData dataWithBytes:"junk" length:4] options:0 relativeToURL:nil
                                  bookmarkDataIsStale:&stale error:&error];
    P(@"bad bookmark %@ %@ %ld", back, error.domain, (long)error.code);

    error = nil;
    P(@"promised reachable %d %@", [a checkPromisedItemIsReachableAndReturnError:&error], error);
    P(@"promised missing %d %ld", [[NSURL fileURLWithPath:@"none"] checkPromisedItemIsReachableAndReturnError:&error], (long)error.code);
    id value = nil;
    [a getPromisedItemResourceValue:&value forKey:NSURLNameKey error:nil];
    P(@"promised name %@", value);
    NSDictionary *values = [a promisedItemResourceValuesForKeys:@[NSURLNameKey, NSURLIsDirectoryKey] error:nil];
    P(@"promised values %@ %@", values[NSURLNameKey], values[NSURLIsDirectoryKey]);

    NSURL *b = [NSURL fileURLWithPath:@"b.txt"];
    [b setTemporaryResourceValue:@"temporary" forKey:@"CartographerKey"];
    value = nil;
    [b getResourceValue:&value forKey:@"CartographerKey" error:nil];
    P(@"temporary %@", value);
    [b removeCachedResourceValueForKey:@"CartographerKey"];
    value = nil;
    [b getResourceValue:&value forKey:@"CartographerKey" error:nil];
    P(@"temporary removed %@", value);
    [b setTemporaryResourceValue:@"again" forKey:@"CartographerKey"];
    [b removeAllCachedResourceValues];
    value = nil;
    [b getResourceValue:&value forKey:@"CartographerKey" error:nil];
    P(@"all removed %@", value);

    NSArray *keys = @[NSURLFileResourceTypeKey, @"NSURLDirectoryEntryCountKey", NSURLIsSparseKey, NSURLIsAliasFileKey,
                      NSURLIsPackageKey, NSURLLabelNumberKey, NSURLIsPurgeableKey, NSURLMayShareFileContentKey,
                      NSURLTypeIdentifierKey, NSURLIsUbiquitousItemKey, NSURLUbiquitousItemDownloadingStatusKey,
                      NSURLIsVolumeKey, NSURLHasHiddenExtensionKey];
    for (NSString *name in @[@"a.txt", @"sub", @"link.txt"]) {
        NSURL *url = [NSURL fileURLWithPath:name];
        NSMutableArray *parts = [NSMutableArray array];
        for (NSString *key in keys) {
            id item = nil;
            [url getResourceValue:&item forKey:key error:nil];
            [parts addObject:[NSString stringWithFormat:@"%@", item ?: @"-"]];
        }
        id parent = nil;
        [url getResourceValue:&parent forKey:NSURLParentDirectoryURLKey error:nil];
        P(@"%@: %@ parent=%d", name, [parts componentsJoinedByString:@" "], [[parent path] isEqual:[[url URLByDeletingLastPathComponent] path]]);
    }

    struct stat info;
    lstat("a.txt", &info);
    id identifier = nil, content = nil, resource = nil, volume = nil, block = nil, attributes = nil;
    [a getResourceValue:&identifier forKey:@"NSURLFileIdentifierKey" error:nil];
    [a getResourceValue:&content forKey:NSURLFileContentIdentifierKey error:nil];
    [a getResourceValue:&resource forKey:NSURLFileResourceIdentifierKey error:nil];
    [a getResourceValue:&volume forKey:NSURLVolumeIdentifierKey error:nil];
    [a getResourceValue:&block forKey:NSURLPreferredIOBlockSizeKey error:nil];
    [a getResourceValue:&attributes forKey:NSURLMayHaveExtendedAttributesKey error:nil];
    P(@"identifier inode=%d content=%d resource=%lu volume=%lu block=%d attributes=%d",
      [identifier unsignedLongLongValue] == (unsigned long long)info.st_ino, [content isEqual:identifier],
      (unsigned long)[resource length], (unsigned long)[volume length], [block integerValue] > 0,
      [attributes isKindOfClass:[NSNumber class]]);

    NSMutableArray *kinds = [NSMutableArray array];
    for (NSString *key in @[NSURLVolumeSupportsAccessPermissionsKey, NSURLVolumeSupportsExclusiveRenamingKey,
                            NSURLVolumeSupportsFileCloningKey, NSURLVolumeSupportsFileProtectionKey,
                            NSURLVolumeSupportsImmutableFilesKey, NSURLVolumeSupportsSwapRenamingKey,
                            @"NSURLVolumeTypeNameKey", @"NSURLVolumeMountFromLocationKey", NSURLVolumeURLKey]) {
        id item = nil;
        [a getResourceValue:&item forKey:key error:nil];
        [kinds addObject:[item isKindOfClass:[NSNumber class]] ? @"number" : [item isKindOfClass:[NSString class]] ? @"string"
                         : [item isKindOfClass:[NSURL class]] ? @"url" : @"-"];
    }
    P(@"volume %@", [kinds componentsJoinedByString:@" "]);

    chmod("a.txt", 0644);
    NSFileSecurity *security = nil;
    [a getResourceValue:&security forKey:NSURLFileSecurityKey error:nil];
    uid_t owner = 0;
    mode_t mode = 0;
    BOOL hasOwner = CFFileSecurityGetOwner((__bridge CFFileSecurityRef)security, &owner);
    BOOL hasMode = CFFileSecurityGetMode((__bridge CFFileSecurityRef)security, &mode);
    P(@"security %@ kind=%d owner=%d mine=%d mode=%o regular=%d", NSStringFromClass([security class]),
      [security isKindOfClass:[NSFileSecurity class]], hasOwner, owner == getuid(), hasMode ? mode & 0777 : 0,
      (mode & S_IFMT) == S_IFREG);
}

static void fileManager(void) {
    NSFileManager *files = NSFileManager.defaultManager;
    P(@"equal ab=%d ac=%d aa=%d missing=%d dirs=%d", [files contentsEqualAtPath:@"a.txt" andPath:@"b.txt"],
      [files contentsEqualAtPath:@"a.txt" andPath:@"c.txt"], [files contentsEqualAtPath:@"a.txt" andPath:@"a.txt"],
      [files contentsEqualAtPath:@"a.txt" andPath:@"none"], [files contentsEqualAtPath:@"d1" andPath:@"d2"]);
    [@"2" writeToFile:@"d2/x/g" atomically:NO encoding:NSUTF8StringEncoding error:nil];
    P(@"equal after=%d directory-file=%d", [files contentsEqualAtPath:@"d1" andPath:@"d2"],
      [files contentsEqualAtPath:@"d1" andPath:@"a.txt"]);

    NSError *error = nil;
    BOOL ok = [files createSymbolicLinkAtURL:[NSURL fileURLWithPath:@"l1"] withDestinationURL:[NSURL fileURLWithPath:@"a.txt"] error:&error];
    NSString *destination = [files destinationOfSymbolicLinkAtPath:@"l1" error:nil];
    P(@"link url %d %@ absolute=%d", ok, destination.lastPathComponent, [destination hasPrefix:@"/"]);
    ok = [files createSymbolicLinkAtURL:[NSURL fileURLWithPath:@"l2"] withDestinationURL:[NSURL URLWithString:@"a.txt"] error:&error];
    P(@"link relative %d %@", ok, [files destinationOfSymbolicLinkAtPath:@"l2" error:nil]);
    ok = [files createSymbolicLinkAtURL:[NSURL fileURLWithPath:@"l2"] withDestinationURL:[NSURL URLWithString:@"a.txt"] error:&error];
    P(@"link exists %d %@ %ld", ok, error.domain, (long)error.code);
    ok = [files createSymbolicLinkAtPath:@"l4" pathContent:@"c.txt"];
    P(@"path content %d %@ again=%d missing=%@", ok, [files pathContentOfSymbolicLinkAtPath:@"l4"],
      [files createSymbolicLinkAtPath:@"l4" pathContent:@"c.txt"], [files pathContentOfSymbolicLinkAtPath:@"zz"]);

    ok = [files changeFileAttributes:@{NSFilePosixPermissions: @0600} atPath:@"c.txt"];
    P(@"change %d %@ missing=%d", ok, [files attributesOfItemAtPath:@"c.txt" error:nil][NSFilePosixPermissions],
      [files changeFileAttributes:@{NSFilePosixPermissions: @0600} atPath:@"zz"]);
    P(@"file system %d missing=%@", [files fileSystemAttributesAtPath:@"."][NSFileSystemSize] != nil,
      [files fileSystemAttributesAtPath:@"/nonexistent-cartographer"]);

    error = nil;
    ok = [files linkItemAtPath:@"a.txt" toPath:@"hard" error:&error];
    struct stat first, second;
    stat("a.txt", &first);
    stat("hard", &second);
    P(@"hard link %d %@ same=%d links=%d", ok, error, first.st_ino == second.st_ino, (int)first.st_nlink);
    ok = [files linkItemAtPath:@"a.txt" toPath:@"hard" error:&error];
    P(@"hard link exists %d %@ %ld", ok, error.domain, (long)error.code);
    error = nil;
    ok = [files linkItemAtPath:@"zz" toPath:@"hard2" error:&error];
    P(@"hard link missing %d %@ %ld", ok, error.domain, (long)error.code);
    error = nil;
    ok = [files linkItemAtURL:[NSURL fileURLWithPath:@"d1"] toURL:[NSURL fileURLWithPath:@"d3"] error:&error];
    stat("d1/x/f", &first);
    P(@"hard link directory %d %@ file=%d links=%d", ok, error, [files fileExistsAtPath:@"d3/x/f"], (int)first.st_nlink);

    error = nil;
    NSURL *published = [files URLForPublishingUbiquitousItemAtURL:[NSURL fileURLWithPath:@"a.txt"] expirationDate:nil error:&error];
    P(@"publish %@ %@ %ld %@", published, error.domain, (long)error.code, error.localizedDescription);

    __block BOOL done = NO;
    [files getFileProviderServicesForItemAtURL:[NSURL fileURLWithPath:@"a.txt"]
                             completionHandler:^(NSDictionary *services, NSError *failure) {
        P(@"services %@ %@ %ld", services, failure.domain, (long)failure.code);
        done = YES;
    }];
    waitFor(&done);
    NSArray *volumes = [files mountedVolumeURLsIncludingResourceValuesForKeys:nil options:0];
    P(@"volumes %d first=%@", volumes.count > 0, [volumes.firstObject absoluteString]);
}

static void versions(void) {
    NSURL *a = [NSURL fileURLWithPath:@"a.txt"];
    NSFileVersion *version = [NSFileVersion currentVersionOfItemAtURL:a];
    NSDate *modified = [NSFileManager.defaultManager attributesOfItemAtPath:@"a.txt" error:nil][NSFileModificationDate];
    P(@"version %@ %@ name=%@ saving=%@ conflict=%d resolved=%d local=%d thumbnail=%d originator=%@",
      NSStringFromClass([version class]), version.URL.lastPathComponent, version.localizedName,
      version.localizedNameOfSavingComputer, version.conflict, version.resolved, version.hasLocalContents,
      version.hasThumbnail, version.originatorNameComponents);
    id identifier = version.persistentIdentifier;
    P(@"version identifier dictionary=%d count=%lu date=%d", [identifier isKindOfClass:[NSDictionary class]],
      (unsigned long)[identifier count], fabs([version.modificationDate timeIntervalSinceDate:modified]) < 1);
    P(@"version others=%lu conflicts=%lu missing=%@", (unsigned long)[NSFileVersion otherVersionsOfItemAtURL:a].count,
      (unsigned long)[NSFileVersion unresolvedConflictVersionsOfItemAtURL:a].count,
      [NSFileVersion currentVersionOfItemAtURL:[NSURL fileURLWithPath:@"none"]]);
    NSError *error = nil;
    P(@"version remove others %d %@", [NSFileVersion removeOtherVersionsOfItemAtURL:a error:&error], error);
    P(@"version remove %d %@ %ld", [version removeAndReturnError:&error], error.domain, (long)error.code);
    NSFileVersion *again = [NSFileVersion versionOfItemAtURL:a forPersistentIdentifier:identifier];
    P(@"version by identifier %d equal=%d", again != nil, [again isEqual:version]);
    version.resolved = YES;
    P(@"version resolved %d", version.resolved);
    __block BOOL done = NO;
    [NSFileVersion getNonlocalVersionsOfItemAtURL:a completionHandler:^(NSArray *found, NSError *failure) {
        P(@"nonlocal %@ %@ %ld", found, failure.domain, (long)failure.code);
        done = YES;
    }];
    waitFor(&done);
}

static void security(void) {
    NSFileSecurity *made = [[NSFileSecurity alloc] init];
    P(@"file security %@ kind=%d", NSStringFromClass([made class]), [made isKindOfClass:[NSFileSecurity class]]);
    CFFileSecurityRef cf = CFFileSecurityCreate(NULL);
    CFFileSecuritySetOwner(cf, 7);
    CFFileSecuritySetGroup(cf, 8);
    CFFileSecuritySetMode(cf, 0644);
    NSFileSecurity *bridged = (__bridge_transfer NSFileSecurity *)cf;
    NSString *description = bridged.description;
    NSRange brace = [description rangeOfString:@"{"];
    P(@"cf security kind=%d %@", [bridged isKindOfClass:[NSFileSecurity class]],
      brace.location == NSNotFound ? description : [description substringFromIndex:brace.location]);
    NSFileSecurity *copy = [bridged copy];
    P(@"security copy %@ equal=%d supports=%d", NSStringFromClass([copy class]), [copy isEqual:bridged],
      [NSFileSecurity supportsSecureCoding]);
    NSError *error = nil;
    NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:bridged requiringSecureCoding:YES error:&error];
    NSFileSecurity *back = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSFileSecurity class] fromData:archive error:&error];
    gid_t group = 0;
    P(@"security archive %@ equal=%d group=%d %u", NSStringFromClass([back class]), [back isEqual:bridged],
      CFFileSecurityGetGroup((__bridge CFFileSecurityRef)back, &group), group);
}

static void purgeable(void) {
    NSPurgeableData *data = [NSPurgeableData dataWithBytes:"abc" length:3];
    P(@"purgeable %@ %@ length=%lu discarded=%d", NSStringFromClass([data class]), NSStringFromClass([[data class] superclass]),
      (unsigned long)data.length, data.isContentDiscarded);
    P(@"begin %d", [data beginContentAccess]);
    [data endContentAccess];
    [data endContentAccess];
    [data discardContentIfPossible];
    P(@"discarded %d begin=%d", data.isContentDiscarded, [data beginContentAccess]);

    NSPurgeableData *kept = [[NSPurgeableData alloc] initWithBytes:"hi" length:2];
    P(@"kept begin %d", [kept beginContentAccess]);
    [kept discardContentIfPossible];
    [kept endContentAccess];
    P(@"kept discarded %d length=%lu", kept.isContentDiscarded, (unsigned long)kept.length);
    [kept appendBytes:"!" length:1];
    P(@"kept %@ copy=%@", text(kept), text([kept copy]));
    [kept endContentAccess];
    [kept discardContentIfPossible];
    P(@"kept released discarded=%d begin=%d", kept.isContentDiscarded, [kept beginContentAccess]);
}

static void dataMethods(void) {
    NSData *decoded = [[NSData alloc] initWithBase64Encoding:@"aGVs\nbG8="];
    P(@"base64 %@", text(decoded));
    char *buffer = malloc(4);
    memcpy(buffer, "free", 4);
    P(@"no copy %@", text([[NSData alloc] initWithBytesNoCopy:buffer length:4]));

    NSData *source = [@"hello hello hello hello hello" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    NSData *zlib = [source compressedDataUsingAlgorithm:NSDataCompressionAlgorithmZlib error:&error];
    P(@"zlib %lu %@ %@", (unsigned long)zlib.length, hex(zlib), error);
    for (NSInteger algorithm = 0; algorithm < 4; algorithm++) {
        NSData *packed = [source compressedDataUsingAlgorithm:algorithm error:&error];
        NSData *unpacked = [packed decompressedDataUsingAlgorithm:algorithm error:&error];
        error = nil;
        NSData *bad = [[NSData dataWithBytes:"garbage!" length:8] decompressedDataUsingAlgorithm:algorithm error:&error];
        P(@"algorithm %ld round trip=%d bad=%@ %@ %ld", (long)algorithm, [unpacked isEqual:source], bad, error.domain, (long)error.code);
    }
    // What Darwin makes, for each algorithm.
    NSArray *darwin = @[
        @"6276786e1d00000015000000e668656c6c6f203806fbe26c6f060000000000000062767824",
        @"6276342d1d00000068656c6c6f2068656c6c6f2068656c6c6f2068656c6c6f2068656c6c6f62763424",
        @"fd377a585a000000ff12d9410200210116000000742fe5a3e0001c000c5d00341949ee8de9573ac6af0000000001201d50fd04d606729e7a010000000000595a",
        @"cb48cdc9c957c8c04e0200",
    ];
    for (NSInteger algorithm = 0; algorithm < 4; algorithm++) {
        NSData *unpacked = [unhex(darwin[algorithm]) decompressedDataUsingAlgorithm:algorithm error:&error];
        P(@"darwin %ld %@", (long)algorithm, text(unpacked));
    }
    error = nil;
    P(@"empty %@ %@", hex([[NSData data] compressedDataUsingAlgorithm:NSDataCompressionAlgorithmZlib error:&error]), error);
    P(@"empty decompressed %@ %ld", [[NSData data] decompressedDataUsingAlgorithm:NSDataCompressionAlgorithmZlib error:&error],
      (long)error.code);

    NSMutableData *mutable = [source mutableCopy];
    BOOL ok = [mutable compressUsingAlgorithm:NSDataCompressionAlgorithmZlib error:&error];
    P(@"mutable compress %d %lu", ok, (unsigned long)mutable.length);
    ok = [mutable decompressUsingAlgorithm:NSDataCompressionAlgorithmZlib error:&error];
    P(@"mutable decompress %d %d", ok, [mutable isEqual:source]);
    NSMutableData *junk = [NSMutableData dataWithBytes:"zz" length:2];
    error = nil;
    ok = [junk decompressUsingAlgorithm:NSDataCompressionAlgorithmZlib error:&error];
    P(@"mutable junk %d %lu %ld", ok, (unsigned long)junk.length, (long)error.code);
    NSMutableData *reset = [NSMutableData dataWithBytes:"abcdef" length:6];
    [reset resetBytesInRange:NSMakeRange(2, 2)];
    P(@"reset %@", hex(reset));
    [reset resetBytesInRange:NSMakeRange(4, 6)];
    P(@"reset grow %@", hex(reset));
}

static void wrappers(void) {
    NSFileWrapper *file = [[NSFileWrapper alloc] initRegularFileWithContents:[@"abc" dataUsingEncoding:NSUTF8StringEncoding]];
    file.preferredFilename = @"x.txt";
    NSFileWrapper *unnamed = [[NSFileWrapper alloc] initRegularFileWithContents:[@"abc" dataUsingEncoding:NSUTF8StringEncoding]];
    NSFileWrapper *folder = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{@"x.txt": file}];
    NSFileWrapper *inner = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{@"f": unnamed}];
    NSFileWrapper *outer = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{@"in": inner}];
    NSFileWrapper *link = [[NSFileWrapper alloc] initSymbolicLinkWithDestinationURL:[NSURL fileURLWithPath:@"/tmp/q"]];
    NSFileWrapper *links = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{@"l": link}];
    P(@"serialized %lu %lu %lu %lu %lu", (unsigned long)file.serializedRepresentation.length,
      (unsigned long)unnamed.serializedRepresentation.length, (unsigned long)folder.serializedRepresentation.length,
      (unsigned long)outer.serializedRepresentation.length, (unsigned long)links.serializedRepresentation.length);
    P(@"serialized file %@", [hex(file.serializedRepresentation) substringToIndex:24]);

    NSData *darwin = unhex(@"72746664000000000300000004000000020000002e2e130000005f5f405072656665727265644e616d65405f5f170000005f5f40555446385072656665727265644e616d65405f5f010000002e0b0000000d0000000d0000002600000001000000030000006162630100000005000000782e7478740100000005000000782e747874010000001e00000001000000020000002e2e1000000000000000b60100000200000001000000");
    NSFileWrapper *read = [[NSFileWrapper alloc] initWithSerializedRepresentation:darwin];
    P(@"read file regular=%d name=%@ contents=%@", read.isRegularFile, read.preferredFilename, text(read.regularFileContents));
    NSFileWrapper *nested = [[NSFileWrapper alloc] initWithSerializedRepresentation:outer.serializedRepresentation];
    NSFileWrapper *nestedInner = nested.fileWrappers[@"in"];
    P(@"read nested directory=%d inner=%d contents=%@", nested.isDirectory, nestedInner.isDirectory,
      text(nestedInner.fileWrappers[@"f"].regularFileContents));
    NSFileWrapper *readLinks = [[NSFileWrapper alloc] initWithSerializedRepresentation:links.serializedRepresentation];
    P(@"read link %d %@", readLinks.fileWrappers[@"l"].isSymbolicLink, readLinks.fileWrappers[@"l"].symbolicLinkDestinationURL.path);
    P(@"read junk %@", [[NSFileWrapper alloc] initWithSerializedRepresentation:[NSData dataWithBytes:"junk" length:4]]);
}

static void streams(void) {
    P(@"stream keys %@ %@ %@ %@", NSStreamFileCurrentOffsetKey, NSStreamSocketSecurityLevelKey,
      NSStreamSOCKSProxyHostKey, NSStreamDataWrittenToMemoryStreamKey);
    NSInputStream *input = [NSInputStream inputStreamWithData:[@"abcdef" dataUsingEncoding:NSUTF8StringEncoding]];
    [input open];
    uint8_t bytes[8] = {0};
    NSInteger count = [input read:bytes maxLength:3];
    P(@"input read %ld offset=%@", (long)count, [input propertyForKey:NSStreamFileCurrentOffsetKey]);
    BOOL ok = [input setProperty:@1 forKey:NSStreamFileCurrentOffsetKey];
    count = [input read:bytes maxLength:8];
    P(@"input seek %d %ld %.*s", ok, (long)count, (int)count, bytes);
    P(@"input custom %d %@", [input setProperty:@"value" forKey:@"CartographerKey"], [input propertyForKey:@"CartographerKey"]);
    [input close];

    NSOutputStream *memory = [NSOutputStream outputStreamToMemory];
    [memory open];
    [memory write:(const uint8_t *)"xyz" maxLength:3];
    P(@"memory %@", text([memory propertyForKey:NSStreamDataWrittenToMemoryStreamKey]));
    [memory close];

    NSOutputStream *file = [NSOutputStream outputStreamToFileAtPath:@"stream.txt" append:NO];
    [file open];
    [file write:(const uint8_t *)"12345" maxLength:5];
    P(@"file offset %@", [file propertyForKey:NSStreamFileCurrentOffsetKey]);
    [file close];
    NSInputStream *reading = [NSInputStream inputStreamWithFileAtPath:@"stream.txt"];
    [reading open];
    [reading setProperty:@2 forKey:NSStreamFileCurrentOffsetKey];
    count = [reading read:bytes maxLength:8];
    P(@"file seek %ld %.*s offset=%@", (long)count, (int)count, bytes, [reading propertyForKey:NSStreamFileCurrentOffsetKey]);
    [reading close];
}

static void ports(void) {
    NSPort *port = [NSPort port];
    NSPort *allocated = [[NSPort alloc] init];
    P(@"port %@ %@ named=%d reserved=%lu", NSStringFromClass([port class]), NSStringFromClass([allocated class]),
      [(NSMachPort *)allocated machPort] != 0, (unsigned long)port.reservedSpaceLength);
    P(@"mach null %@", [NSMachPort portWithMachPort:0]);
    NSMessagePort *message = [[NSMessagePort alloc] init];
    P(@"message port %@ %@ valid=%d reserved=%lu", NSStringFromClass([message class]),
      NSStringFromClass([[message class] superclass]), message.isValid, (unsigned long)message.reservedSpaceLength);
    __block int notes = 0;
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:NSPortDidBecomeInvalidNotification object:message
                                                                     queue:nil usingBlock:^(NSNotification *note) { notes++; }];
    [message invalidate];
    [message invalidate];
    P(@"invalidated valid=%d notes=%d", message.isValid, notes);
    [[NSNotificationCenter defaultCenter] removeObserver:observer];

    NSMachPort *receiver = [[NSMachPort alloc] init];
    CartographerPortDelegate *delegate = [CartographerPortDelegate new];
    NSMachPort *reply = [[NSMachPort alloc] init];
    delegate.reply = reply;
    receiver.delegate = (id<NSMachPortDelegate>)delegate;
    [[NSRunLoop currentRunLoop] addPort:receiver forMode:NSDefaultRunLoopMode];
    NSMutableArray *parts = [@[[@"hi" dataUsingEncoding:NSUTF8StringEncoding], reply] mutableCopy];
    BOOL sent = [receiver sendBeforeDate:[NSDate dateWithTimeIntervalSinceNow:1] msgid:3 components:parts from:reply reserved:0];
    P(@"sent %d copy=%d", sent, [receiver copy] == receiver);
    for (int i = 0; i < 100 && !delegate.done; i++) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
    [[NSRunLoop currentRunLoop] removePort:receiver forMode:NSDefaultRunLoopMode];
}

static void coordination(void) {
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    NSString *purpose = coordinator.purposeIdentifier;
    coordinator.purposeIdentifier = @"cartographer";
    P(@"coordinator purpose=%lu set=%@ presenters=%lu", (unsigned long)purpose.length, coordinator.purposeIdentifier,
      (unsigned long)[NSFileCoordinator filePresenters].count);
    NSError *error = nil;
    __block BOOL accessed = NO;
    [coordinator prepareForReadingItemsAtURLs:@[[NSURL fileURLWithPath:@"a.txt"]] options:0 writingItemsAtURLs:@[] options:0
                                        error:&error byAccessor:^(void (^completion)(void)) {
        accessed = YES;
        completion();
    }];
    P(@"prepared %d %@", accessed, error);
    NSURL *from = [NSURL fileURLWithPath:@"moving.txt"], *to = [NSURL fileURLWithPath:@"moved.txt"];
    [@"m" writeToURL:from atomically:NO encoding:NSUTF8StringEncoding error:nil];
    [coordinator coordinateWritingItemAtURL:from options:NSFileCoordinatorWritingForMoving writingItemAtURL:to
                                    options:NSFileCoordinatorWritingForReplacing error:&error
                                 byAccessor:^(NSURL *source, NSURL *destination) {
        [coordinator itemAtURL:source willMoveToURL:destination];
        BOOL moved = [NSFileManager.defaultManager moveItemAtURL:source toURL:destination error:nil];
        [coordinator itemAtURL:source didMoveToURL:destination];
        P(@"moved %d %@", moved, destination.lastPathComponent);
    }];
}

static void bundles(void) {
    NSFileManager *files = NSFileManager.defaultManager;
    [files createDirectoryAtPath:@"Fake.bundle/en.lproj" withIntermediateDirectories:YES attributes:nil error:nil];
    [@"x" writeToFile:@"Fake.bundle/x.txt" atomically:NO encoding:NSUTF8StringEncoding error:nil];
    [@"y" writeToFile:@"Fake.bundle/y.txt" atomically:NO encoding:NSUTF8StringEncoding error:nil];
    [@"y" writeToFile:@"Fake.bundle/en.lproj/y.txt" atomically:NO encoding:NSUTF8StringEncoding error:nil];
    [@"z" writeToFile:@"Fake.bundle/en.lproj/z.txt" atomically:NO encoding:NSUTF8StringEncoding error:nil];
    NSURL *bundleURL = [NSURL fileURLWithPath:@"Fake.bundle" isDirectory:YES];
    NSURL *found = [NSBundle URLForResource:@"x" withExtension:@"txt" subdirectory:nil inBundleWithURL:bundleURL];
    NSArray *all = [NSBundle URLsForResourcesWithExtension:@"txt" subdirectory:nil inBundleWithURL:bundleURL];
    P(@"bundle url %@ all=%lu", found.lastPathComponent, (unsigned long)all.count);
    NSBundle *bundle = [NSBundle bundleWithURL:bundleURL];
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *path in [bundle pathsForResourcesOfType:@"txt" inDirectory:nil forLocalization:@"en"]) {
        [names addObject:[[path stringByDeletingLastPathComponent].lastPathComponent stringByAppendingPathComponent:path.lastPathComponent]];
    }
    [names sortUsingSelector:@selector(compare:)];
    P(@"localized paths %@", [names componentsJoinedByString:@" "]);
    NSArray *urls = [bundle URLsForResourcesWithExtension:@"txt" subdirectory:nil localization:@"en"];
    P(@"localized urls %lu", (unsigned long)urls.count);
    NSArray *architectures = NSBundle.mainBundle.executableArchitectures;
    P(@"architectures %@", [architectures componentsJoinedByString:@","]);
}

int main(int argc, char *argv[]) {
    // Each line out as it's printed, so a crash keeps the lines before it.
    setvbuf(stdout, NULL, _IOLBF, 0);
    @autoreleasepool {
        char template[1024];
        snprintf(template, sizeof template, "%s/cartographer-XXXXXX",
                 [NSTemporaryDirectory() stringByStandardizingPath].fileSystemRepresentation);
        char *directory = mkdtemp(template);
        if (!directory || chdir(directory) != 0) {
            print(@"no temporary directory");
            return 1;
        }
        NSFileManager *files = NSFileManager.defaultManager;
        [@"hello" writeToFile:@"a.txt" atomically:NO encoding:NSUTF8StringEncoding error:nil];
        [@"hello" writeToFile:@"b.txt" atomically:NO encoding:NSUTF8StringEncoding error:nil];
        [@"world" writeToFile:@"c.txt" atomically:NO encoding:NSUTF8StringEncoding error:nil];
        [files createDirectoryAtPath:@"sub" withIntermediateDirectories:NO attributes:nil error:nil];
        [@"x" writeToFile:@"sub/one" atomically:NO encoding:NSUTF8StringEncoding error:nil];
        [@"y" writeToFile:@"sub/.two" atomically:NO encoding:NSUTF8StringEncoding error:nil];
        [files createDirectoryAtPath:@"d1/x" withIntermediateDirectories:YES attributes:nil error:nil];
        [files createDirectoryAtPath:@"d2/x" withIntermediateDirectories:YES attributes:nil error:nil];
        [@"1" writeToFile:@"d1/x/f" atomically:NO encoding:NSUTF8StringEncoding error:nil];
        [@"1" writeToFile:@"d2/x/f" atomically:NO encoding:NSUTF8StringEncoding error:nil];
        symlink("a.txt", "link.txt");

        urls();
        aliasesAndValues();
        fileManager();
        versions();
        security();
        purgeable();
        dataMethods();
        wrappers();
        streams();
        ports();
        coordination();
        bundles();

        [files removeItemAtPath:[NSString stringWithUTF8String:directory] error:nil];
    }
    return 0;
}
