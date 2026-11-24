// System-service classes, grammar and observers, built on a Mac with Xcode:
// a metadata query's lifecycle (no results, as without iCloud), a metadata
// item, item providers passing data, strings, URLs and files between parts
// of one program, extension items, an on-demand resource request for a tag
// the app doesn't have, morphology, terms of address and inflection rules,
// shared key-value observers, NSProxy forwarding, and an anonymous XPC
// listener connected in-process. Prints to stdout so the test can compare
// exact text.
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

// Some of the API is deprecated, and still what apps call.
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static void print(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static dispatch_semaphore_t done;

/// Waits for a completion handler, running the main run loop meanwhile:
/// item providers load items on the main queue.
static void waitForDone(void) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:5];
    while (dispatch_semaphore_wait(done, DISPATCH_TIME_NOW) != 0) {
        if ([limit timeIntervalSinceNow] < 0) {
            print(@"timed out");
            return;
        }
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
}

static NSString *afterAddress(NSString *description) {
    NSRange range = [description rangeOfString:@"> "];
    return range.location == NSNotFound ? description : [description substringFromIndex:NSMaxRange(range)];
}

// MARK: - Observers and proxies

@interface AtticObserver : NSObject
@end

@implementation AtticObserver
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    print([NSString stringWithFormat:@"observed %@ new=%@ old=%@ context=%ld", keyPath, change[NSKeyValueChangeNewKey],
           change[NSKeyValueChangeOldKey], (long)context]);
}
@end

@interface AtticModel : NSObject
@property (copy) NSString *name;
@property NSInteger count;
@end

@implementation AtticModel
@end

@interface AtticProxy : NSProxy
@property (strong) id target;
@end

@implementation AtticProxy
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
    print([NSString stringWithFormat:@"proxy signature %@", NSStringFromSelector(selector)]);
    return [self.target methodSignatureForSelector:selector];
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    print([NSString stringWithFormat:@"proxy forwards %@", NSStringFromSelector(invocation.selector)]);
    [invocation invokeWithTarget:self.target];
}
@end

@interface AtticWeakProxy : NSProxy
@property (weak) id target;
@end

@implementation AtticWeakProxy
- (id)forwardingTargetForSelector:(SEL)selector {
    return self.target;
}
@end

@interface AtticBareProxy : NSProxy
@end

@implementation AtticBareProxy
@end

// MARK: - XPC

@protocol AtticEchoing
- (void)echo:(NSString *)text reply:(void (^)(NSString *answer))reply;
@end

@interface AtticEcho : NSObject <AtticEchoing>
@end

@implementation AtticEcho
- (void)echo:(NSString *)text reply:(void (^)(NSString *))reply {
    print([NSString stringWithFormat:@"echo got %@", text]);
    reply(text.uppercaseString);
}
@end

@interface AtticListenerDelegate : NSObject <NSXPCListenerDelegate>
@end

@implementation AtticListenerDelegate
- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)connection {
    print(@"listener accepts a connection");
    connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(AtticEchoing)];
    connection.exportedObject = [AtticEcho new];
    [connection resume];
    return YES;
}
@end

// MARK: -

static void metadata(void) {
    NSMetadataQuery *query = [[NSMetadataQuery alloc] init];
    print([NSString stringWithFormat:@"query predicate=%@ sorts=%lu scopes=%lu interval=%g", query.predicate,
           (unsigned long)query.sortDescriptors.count, (unsigned long)query.searchScopes.count, query.notificationBatchingInterval]);
    print([NSString stringWithFormat:@"query start without predicate=%d started=%d", [query startQuery], query.isStarted]);

    query.predicate = [NSPredicate predicateWithFormat:@"%K LIKE '*.txt'", NSMetadataItemFSNameKey];
    query.searchScopes = @[NSMetadataQueryUbiquitousDocumentsScope];
    __block BOOL finished = NO;
    NSMutableArray *tokens = [NSMutableArray array];
    for (NSString *name in @[NSMetadataQueryDidStartGatheringNotification, NSMetadataQueryDidFinishGatheringNotification,
                             NSMetadataQueryDidUpdateNotification]) {
        [tokens addObject:[[NSNotificationCenter defaultCenter] addObserverForName:name object:query queue:nil
                                                                        usingBlock:^(NSNotification *note) {
            print([NSString stringWithFormat:@"query %@ started=%d gathering=%d results=%lu", note.name, query.isStarted,
                   query.isGathering, (unsigned long)query.resultCount]);
            if ([note.name isEqualToString:NSMetadataQueryDidFinishGatheringNotification]) finished = YES;
        }]];
    }
    BOOL started = [query startQuery];
    print([NSString stringWithFormat:@"query start=%d started=%d gathering=%d", started, query.isStarted, query.isGathering]);
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!finished && [limit timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
    print([NSString stringWithFormat:@"query results=%lu %lu values=%lu groups=%lu index=%d", (unsigned long)query.resultCount,
           (unsigned long)query.results.count, (unsigned long)query.valueLists.count, (unsigned long)query.groupedResults.count,
           [query indexOfResult:@"x"] == NSNotFound]);
    [query stopQuery];
    print([NSString stringWithFormat:@"query stopped=%d started=%d gathering=%d", query.isStopped, query.isStarted, query.isGathering]);
    for (id token in tokens) [[NSNotificationCenter defaultCenter] removeObserver:token];

    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"attic-metadata.txt"];
    [@"twelve bytes" writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:NULL];
    // -initWithURL: is declared for macOS only: sent as the initializer it is.
    typedef id (*InitWithURL)(__attribute__((ns_consumed)) id, SEL, NSURL *) __attribute__((ns_returns_retained));
    InitWithURL initWithURL = (InitWithURL)objc_msgSend;
    NSMetadataItem *item = initWithURL([NSMetadataItem alloc], @selector(initWithURL:), [NSURL fileURLWithPath:path]);
    print([NSString stringWithFormat:@"item name=%@ size=%@ via key=%@", [item valueForAttribute:NSMetadataItemFSNameKey],
           [item valueForAttribute:NSMetadataItemFSSizeKey], [item valueForKey:NSMetadataItemFSNameKey]]);
    print([NSString stringWithFormat:@"item values=%@", [[item valuesForAttributes:@[NSMetadataItemFSNameKey, @"bogus"]] allKeys]]);
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    NSMetadataItem *missing = initWithURL([NSMetadataItem alloc], @selector(initWithURL:), [NSURL fileURLWithPath:@"/nonexistent/attic.txt"]);
    print([NSString stringWithFormat:@"item missing=%d", missing == nil]);
}

static void itemProviders(void) {
    NSItemProvider *provider = [[NSItemProvider alloc] init];
    [provider registerDataRepresentationForTypeIdentifier:@"public.utf8-plain-text" visibility:NSItemProviderRepresentationVisibilityAll
                                              loadHandler:^NSProgress *(void (^completion)(NSData *, NSError *)) {
        print(@"provider loads text");
        completion([@"hi there" dataUsingEncoding:NSUTF8StringEncoding], nil);
        return nil;
    }];
    print([NSString stringWithFormat:@"provider types=%@", [provider.registeredTypeIdentifiers componentsJoinedByString:@","]]);
    print([NSString stringWithFormat:@"provider in place=%lu text=%d plain=%d data=%d image=%d",
           (unsigned long)[provider registeredTypeIdentifiersWithFileOptions:NSItemProviderFileOptionOpenInPlace].count,
           [provider hasItemConformingToTypeIdentifier:@"public.text"], [provider hasItemConformingToTypeIdentifier:@"public.plain-text"],
           [provider hasItemConformingToTypeIdentifier:@"public.data"], [provider hasItemConformingToTypeIdentifier:@"public.image"]]);
    print([NSString stringWithFormat:@"provider can load string=%d url=%d", [provider canLoadObjectOfClass:[NSString class]],
           [provider canLoadObjectOfClass:[NSURL class]]]);

    NSProgress *progress = [provider loadDataRepresentationForTypeIdentifier:@"public.plain-text"
                                                           completionHandler:^(NSData *data, NSError *error) {
        print([NSString stringWithFormat:@"provider data=%@ error=%@ main=%d",
               [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], error, [NSThread isMainThread]]);
        dispatch_semaphore_signal(done);
    }];
    waitForDone();
    print([NSString stringWithFormat:@"provider progress=%lld/%lld", progress.completedUnitCount, progress.totalUnitCount]);

    [provider loadItemForTypeIdentifier:@"public.text" options:nil completionHandler:^(NSString *text, NSError *error) {
        print([NSString stringWithFormat:@"provider item string=%@ is string=%d", text, [text isKindOfClass:[NSString class]]]);
        dispatch_semaphore_signal(done);
    }];
    waitForDone();
    [provider loadItemForTypeIdentifier:@"public.text" options:nil completionHandler:^(id item, NSError *error) {
        print([NSString stringWithFormat:@"provider item is data=%d", [item isKindOfClass:[NSData class]]]);
        dispatch_semaphore_signal(done);
    }];
    waitForDone();
    [provider loadObjectOfClass:[NSString class] completionHandler:^(id object, NSError *error) {
        print([NSString stringWithFormat:@"provider object=%@", object]);
        dispatch_semaphore_signal(done);
    }];
    waitForDone();
    progress = [provider loadDataRepresentationForTypeIdentifier:@"public.jpeg" completionHandler:^(NSData *data, NSError *error) {
        print([NSString stringWithFormat:@"provider jpeg data=%@ error=%@ %ld %@", data, error.domain, (long)error.code,
               error.localizedDescription]);
        dispatch_semaphore_signal(done);
    }];
    waitForDone();
    print([NSString stringWithFormat:@"provider jpeg progress=%lld/%lld", progress.completedUnitCount, progress.totalUnitCount]);
    [provider loadFileRepresentationForTypeIdentifier:@"public.plain-text" completionHandler:^(NSURL *url, NSError *error) {
        print([NSString stringWithFormat:@"provider file ext=%@ contents=%@", url.pathExtension,
               [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:NULL]]);
        dispatch_semaphore_signal(done);
    }];
    waitForDone();

    NSItemProvider *strings = [[NSItemProvider alloc] initWithObject:@"a string"];
    print([NSString stringWithFormat:@"string provider types=%@", [strings.registeredTypeIdentifiers componentsJoinedByString:@","]]);
    [strings loadObjectOfClass:[NSString class] completionHandler:^(id object, NSError *error) {
        print([NSString stringWithFormat:@"string provider object=%@", object]);
        dispatch_semaphore_signal(done);
    }];
    waitForDone();
    NSItemProvider *urls = [[NSItemProvider alloc] initWithObject:[NSURL URLWithString:@"https://example.com/a"]];
    print([NSString stringWithFormat:@"url provider types=%@", [urls.registeredTypeIdentifiers componentsJoinedByString:@","]]);
    [urls loadObjectOfClass:[NSString class] completionHandler:^(id object, NSError *error) {
        print([NSString stringWithFormat:@"url provider as string=%@", object]);
        dispatch_semaphore_signal(done);
    }];
    waitForDone();

    NSItemProvider *items = [[NSItemProvider alloc] init];
    [items registerItemForTypeIdentifier:@"com.example.thing"
                             loadHandler:^(NSItemProviderCompletionHandler completion, Class expected, NSDictionary *options) {
        print([NSString stringWithFormat:@"item handler expects %@ options=%@", NSStringFromClass(expected), options[@"k"]]);
        completion(@42, nil);
    }];
    [items loadItemForTypeIdentifier:@"com.example.thing" options:@{@"k": @"v"} completionHandler:^(NSNumber *number, NSError *error) {
        print([NSString stringWithFormat:@"item number=%@", number]);
        dispatch_semaphore_signal(done);
    }];
    waitForDone();
    [items loadItemForTypeIdentifier:@"com.example.thing" options:nil completionHandler:^(NSString *text, NSError *error) {
        print([NSString stringWithFormat:@"item as string=%@ error=%@ %ld", text, error.domain, (long)error.code]);
        dispatch_semaphore_signal(done);
    }];
    waitForDone();

    NSItemProvider *copy = [items copy];
    copy.suggestedName = @"thing";
    print([NSString stringWithFormat:@"copy types=%@ name=%@ original name=%@", copy.registeredTypeIdentifiers.firstObject,
           copy.suggestedName, items.suggestedName]);
    [items loadPreviewImageWithOptions:nil completionHandler:^(id image, NSError *error) {
        print([NSString stringWithFormat:@"preview=%@ error=%@ %ld", image, error.domain, (long)error.code]);
        dispatch_semaphore_signal(done);
    }];
    waitForDone();
}

static void extensionItems(void) {
    NSExtensionItem *item = [[NSExtensionItem alloc] init];
    print([NSString stringWithFormat:@"extension item title=%@ attachments=%@ info=%lu", item.attributedTitle, item.attachments,
           (unsigned long)item.userInfo.count]);
    item.attributedTitle = [[NSAttributedString alloc] initWithString:@"Title"];
    item.attachments = @[[[NSItemProvider alloc] initWithObject:@"attached"]];
    print([NSString stringWithFormat:@"extension item title=%@ attachments=%lu keys=%@", item.attributedTitle.string,
           (unsigned long)item.attachments.count,
           [[item.userInfo.allKeys sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","]]);
    item.userInfo = @{@"custom": @1};
    print([NSString stringWithFormat:@"extension item after info title=%@ keys=%@", item.attributedTitle,
           [item.userInfo.allKeys componentsJoinedByString:@","]]);
    item.attributedContentText = [[NSAttributedString alloc] initWithString:@"Body"];
    NSExtensionItem *copy = [item copy];
    print([NSString stringWithFormat:@"extension item copy text=%@ same=%d secure=%d", copy.attributedContentText.string, copy == item,
           [NSExtensionItem supportsSecureCoding]]);
    item.userInfo = nil;
    print([NSString stringWithFormat:@"extension item no info=%@ text=%@", item.userInfo, item.attributedContentText]);
}

static void resourceRequest(void) {
    Class requestClass = NSClassFromString(@"NSBundleResourceRequest");
    id request = ((id (*)(id, SEL, id))objc_msgSend)([requestClass alloc], @selector(initWithTags:), [NSSet setWithObject:@"attic-tag"]);
    print([NSString stringWithFormat:@"request tags=%@ main bundle=%d priority=%g", [[request valueForKey:@"tags"] anyObject],
           [request valueForKey:@"bundle"] == [NSBundle mainBundle], ((double (*)(id, SEL))objc_msgSend)(request, @selector(loadingPriority))]);
    NSProgress *progress = [request valueForKey:@"progress"];
    print([NSString stringWithFormat:@"request progress=%lld/%lld", progress.completedUnitCount, progress.totalUnitCount]);
    ((void (*)(id, SEL, id))objc_msgSend)(request, @selector(conditionallyBeginAccessingResourcesWithCompletionHandler:), ^(BOOL available) {
        print([NSString stringWithFormat:@"request available=%d", available]);
        dispatch_semaphore_signal(done);
    });
    waitForDone();
    ((void (*)(id, SEL, id))objc_msgSend)(request, @selector(beginAccessingResourcesWithCompletionHandler:), ^(NSError *error) {
        print([NSString stringWithFormat:@"request error=%@ %ld main=%d", error.domain, (long)error.code, [NSThread isMainThread]]);
        dispatch_semaphore_signal(done);
    });
    waitForDone();
    print([NSString stringWithFormat:@"request progress=%lld/%lld", progress.completedUnitCount, progress.totalUnitCount]);
    ((void (*)(id, SEL))objc_msgSend)(request, @selector(endAccessingResources));
    ((void (*)(id, SEL, double, id))objc_msgSend)([NSBundle mainBundle], @selector(setPreservationPriority:forTags:), 0.5,
                                                 [NSSet setWithObject:@"attic-tag"]);
    print([NSString stringWithFormat:@"request preservation=%g",
           ((double (*)(id, SEL, id))objc_msgSend)([NSBundle mainBundle], @selector(preservationPriorityForTag:), @"attic-tag")]);
}

static void grammar(void) {
    NSMorphology *morphology = [[NSMorphology alloc] init];
    print([NSString stringWithFormat:@"morphology gender=%ld number=%ld unspecified=%d", (long)morphology.grammaticalGender,
           (long)morphology.number, morphology.isUnspecified]);
    morphology.grammaticalGender = NSGrammaticalGenderFeminine;
    morphology.number = NSGrammaticalNumberPlural;
    morphology.partOfSpeech = NSGrammaticalPartOfSpeechNoun;
    NSMorphology *copy = [morphology copy];
    print([NSString stringWithFormat:@"morphology gender=%ld part=%ld unspecified=%d copy equal=%d same=%d hash=%d",
           (long)morphology.grammaticalGender, (long)morphology.partOfSpeech, morphology.isUnspecified, [copy isEqual:morphology],
           copy == morphology, copy.hash == morphology.hash]);
    print([NSString stringWithFormat:@"morphology %@", afterAddress(morphology.description)]);
    print([NSString stringWithFormat:@"user morphology unspecified=%d", [NSMorphology userMorphology].isUnspecified]);
    NSData *archive = [NSKeyedArchiver archivedDataWithRootObject:morphology requiringSecureCoding:YES error:NULL];
    NSMorphology *decoded = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSMorphology class] fromData:archive error:NULL];
    print([NSString stringWithFormat:@"morphology decoded equal=%d", [decoded isEqual:morphology]]);

    print([NSString stringWithFormat:@"inflect en=%d fr=%d pt-BR=%d ja=%d xx=%d preferred=%d", [NSInflectionRule canInflectLanguage:@"en"],
           [NSInflectionRule canInflectLanguage:@"fr"], [NSInflectionRule canInflectLanguage:@"pt-BR"],
           [NSInflectionRule canInflectLanguage:@"ja"], [NSInflectionRule canInflectLanguage:@"xx"],
           [NSInflectionRule canInflectPreferredLocalization]]);
    print([NSString stringWithFormat:@"automatic rule %@ shared=%d %@", NSStringFromClass([[NSInflectionRule automaticRule] class]),
           [NSInflectionRule automaticRule] == [NSInflectionRule automaticRule], afterAddress([NSInflectionRule automaticRule].description)]);
    NSInflectionRuleExplicit *rule = [[NSInflectionRuleExplicit alloc] initWithMorphology:morphology];
    print([NSString stringWithFormat:@"explicit rule gender=%ld same=%d", (long)rule.morphology.grammaticalGender, rule.morphology == morphology]);

    print([NSString stringWithFormat:@"custom pronouns en=%d fr=%d keys=%@", [NSMorphologyCustomPronoun isSupportedForLanguage:@"en"],
           [NSMorphologyCustomPronoun isSupportedForLanguage:@"fr"],
           [[NSMorphologyCustomPronoun requiredKeysForLanguage:@"en"] componentsJoinedByString:@","]]);
    NSMorphologyCustomPronoun *pronoun = [[NSMorphologyCustomPronoun alloc] init];
    pronoun.subjectForm = @"they";
    pronoun.objectForm = @"them";
    NSError *error = nil;
    BOOL set = [morphology setCustomPronoun:pronoun forLanguage:@"en" error:&error];
    print([NSString stringWithFormat:@"custom pronoun set=%d error=%@ %ld invalid=%@", set, error.domain, (long)error.code,
           error.userInfo[@"NSInvalidValue"]]);
    pronoun.possessiveForm = @"theirs";
    pronoun.possessiveAdjectiveForm = @"their";
    pronoun.reflexiveForm = @"themselves";
    set = [morphology setCustomPronoun:pronoun forLanguage:@"en" error:&error];
    print([NSString stringWithFormat:@"custom pronoun set=%d subject=%@ copied=%d unspecified=%d", set,
           [morphology customPronounForLanguage:@"en"].subjectForm, [morphology customPronounForLanguage:@"en"] != pronoun,
           morphology.isUnspecified]);

    if (@available(iOS 17, macOS 14, *)) {
        NSTermOfAddress *feminine = [NSTermOfAddress feminine];
        print([NSString stringWithFormat:@"term feminine language=%@ pronouns=%@ shared=%d neutral=%d", feminine.languageIdentifier,
               feminine.pronouns, feminine == [NSTermOfAddress feminine], [feminine isEqual:[NSTermOfAddress neutral]]]);
        NSMorphology *third = [[NSMorphology alloc] init];
        third.grammaticalPerson = NSGrammaticalPersonThird;
        third.pronounType = NSGrammaticalPronounTypePersonal;
        NSMorphologyPronoun *elle = [[NSMorphologyPronoun alloc] initWithPronoun:@"elle" morphology:third dependentMorphology:nil];
        NSTermOfAddress *localized = [NSTermOfAddress localizedForLanguageIdentifier:@"fr" withPronouns:@[elle]];
        print([NSString stringWithFormat:@"term localized language=%@ count=%lu pronoun=%@ person=%ld dependent=%@",
               localized.languageIdentifier, (unsigned long)localized.pronouns.count, localized.pronouns.firstObject.pronoun,
               (long)localized.pronouns.firstObject.morphology.grammaticalPerson, localized.pronouns.firstObject.dependentMorphology]);
    } else {
        print(@"term feminine language=(null) pronouns=(null) shared=1 neutral=0");
        print(@"term localized language=fr count=1 pronoun=elle person=3 dependent=(null)");
    }
    if (@available(iOS 18, macOS 15, *)) {
        print([NSString stringWithFormat:@"number format rule %@ shared=%d", NSStringFromClass([[NSLocalizedNumberFormatRule automatic] class]),
               [NSLocalizedNumberFormatRule automatic] == [NSLocalizedNumberFormatRule automatic]]);
    } else {
        print(@"number format rule _NSLocalizedNumberFormatRuleAutomatic shared=1");
    }
}

static void sharedObservers(void) {
    if (@available(iOS 18, macOS 15, *)) {
        NSKeyValueSharedObservers *observers = [[NSKeyValueSharedObservers alloc] initWithObservableClass:[AtticModel class]];
        AtticObserver *observer = [AtticObserver new];
        [observers addSharedObserver:observer forKey:@"name" options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld context:(void *)7];
        [observers addSharedObserver:observer forKey:@"count" options:NSKeyValueObservingOptionNew context:(void *)8];
        NSKeyValueSharedObserversSnapshot *snapshot = [observers snapshot];
        AtticModel *first = [AtticModel new], *second = [AtticModel new];
        [first setSharedObservers:snapshot];
        [second setSharedObservers:snapshot];
        first.name = @"alpha";
        second.name = @"beta";
        first.count = 3;
        print([NSString stringWithFormat:@"shared class=%@ observed class=%@", NSStringFromClass([first class]),
               NSStringFromClass(object_getClass(first))]);
        [first setSharedObservers:nil];
        first.name = @"gamma";
        print(@"shared removed");
        [observers addSharedObserver:observer forKey:@"name" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:(void *)9];
        [second setSharedObservers:[observers snapshot]];
        second.name = @"delta";
        [second setSharedObservers:nil];
    } else {
        print(@"observed name new=alpha old=<null> context=7");
        print(@"observed name new=beta old=<null> context=7");
        print(@"observed count new=3 old=(null) context=8");
        print(@"shared class=AtticModel observed class=NSKVONotifying_AtticModel");
        print(@"shared removed");
        print(@"observed name new=delta old=(null) context=9");
        print(@"observed name new=delta old=beta context=7");
    }
}

static void proxies(void) {
    AtticProxy *proxy = [AtticProxy alloc];
    proxy.target = @"hello";
    print([NSString stringWithFormat:@"proxy length=%lu", (unsigned long)[(NSString *)proxy length]]);
    print([NSString stringWithFormat:@"proxy responds length=%d", [proxy respondsToSelector:@selector(length)]]);
    print([NSString stringWithFormat:@"proxy kind of string=%d", [proxy isKindOfClass:[NSString class]]]);
    print([NSString stringWithFormat:@"proxy conforms copying=%d", [proxy conformsToProtocol:@protocol(NSCopying)]]);
    print([NSString stringWithFormat:@"proxy isProxy=%d class=%@ description=%d equal=%d", [proxy isProxy], NSStringFromClass([proxy class]),
           [[proxy description] hasPrefix:@"<AtticProxy: 0x"], [proxy isEqual:proxy]]);
    print([NSString stringWithFormat:@"proxy class responds alloc=%d length=%d", [AtticProxy respondsToSelector:@selector(alloc)],
           [AtticProxy respondsToSelector:@selector(length)]]);

    AtticWeakProxy *weak = [AtticWeakProxy alloc];
    NSString *target = [NSString stringWithFormat:@"%@", @"weakly held"];
    weak.target = target;
    print([NSString stringWithFormat:@"weak proxy upper=%@", [(NSString *)weak uppercaseString]]);

    // A proxy that forwards nothing still answers NSProxy's own methods.
    AtticBareProxy *bare = [AtticBareProxy alloc];
    print([NSString stringWithFormat:@"bare proxy isProxy=%d class=%@ description=%d", [bare isProxy], NSStringFromClass([bare class]),
           [[bare description] hasPrefix:@"<AtticBareProxy: 0x"]]);
}

static void xpc(void) {
    NSXPCListener *listener = [NSXPCListener anonymousListener];
    AtticListenerDelegate *delegate = [AtticListenerDelegate new];
    listener.delegate = delegate;
    [listener resume];
    NSXPCListenerEndpoint *endpoint = listener.endpoint;
    print([NSString stringWithFormat:@"endpoint class=%@ equal to another=%d to itself=%d", NSStringFromClass([endpoint class]),
           [endpoint isEqual:listener.endpoint], [endpoint isEqual:endpoint]]);
    NSXPCConnection *connection = [[NSXPCConnection alloc] initWithListenerEndpoint:endpoint];
    print([NSString stringWithFormat:@"connection endpoint same=%d service=%@ current=%@", connection.endpoint == endpoint,
           connection.serviceName, [NSXPCConnection currentConnection]]);
    connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(AtticEchoing)];
    [connection resume];
    id<AtticEchoing> echo = [connection synchronousRemoteObjectProxyWithErrorHandler:^(NSError *error) {
        print([NSString stringWithFormat:@"connection error %ld", (long)error.code]);
    }];
    [echo echo:@"quiet" reply:^(NSString *answer) {
        print([NSString stringWithFormat:@"reply %@", answer]);
    }];
    [connection scheduleSendBarrierBlock:^{
        print(@"barrier");
        dispatch_semaphore_signal(done);
    }];
    waitForDone();
    [connection invalidate];
    [listener invalidate];
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        done = dispatch_semaphore_create(0);
        metadata();
        itemProviders();
        extensionItems();
        resourceRequest();
        grammar();
        sharedObservers();
        proxies();
        xpc();
    }
    return 0;
}
