// Bundles, process info, threads, user defaults and the file manager, built
// on a Mac with Xcode. The app carries two resources and custom Info.plist
// keys; output is the same on every run.
#import <Foundation/Foundation.h>
#include <unistd.h>

static void print(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

@interface Reporter : NSObject
@end

@implementation Reporter
- (void)report:(NSString *)message {
    print([NSString stringWithFormat:@"%@ (reported on main %d)", message, [NSThread isMainThread]]);
}
- (void)finish {
    print(@"finish");
    CFRunLoopStop(CFRunLoopGetMain());
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // NSBundle
        NSBundle *bundle = [NSBundle mainBundle];
        print([NSString stringWithFormat:@"%@ %@ %@", bundle.bundleIdentifier, bundle.bundlePath.lastPathComponent,
               bundle.executablePath.lastPathComponent]);
        print([NSString stringWithFormat:@"%@ v%@ %@", [bundle objectForInfoDictionaryKey:@"PerryGreeting"],
               bundle.infoDictionary[@"CFBundleShortVersionString"],
               [bundle.infoDictionary[@"PerryNumbers"] componentsJoinedByString:@"+"]]);
        NSString *greetingPath = [bundle pathForResource:@"greeting" ofType:@"txt"];
        NSString *greeting = [NSString stringWithContentsOfFile:greetingPath encoding:NSUTF8StringEncoding error:nil];
        print([NSString stringWithFormat:@"%@: %@", greetingPath.lastPathComponent,
               [greeting stringByReplacingOccurrencesOfString:@"\n" withString:@""]]);
        NSURL *configURL = [bundle URLForResource:@"config" withExtension:@"json"];
        NSDictionary *config = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:configURL]
                                                               options:0 error:nil];
        print([NSString stringWithFormat:@"%@ %@ missing %@ txt %lu", configURL.lastPathComponent, config[@"mode"],
               [bundle pathForResource:@"absent" ofType:@"txt"], (unsigned long)[bundle pathsForResourcesOfType:@"txt"
                                                                                                    inDirectory:nil].count]);
        print([bundle localizedStringForKey:@"Hello" value:@"Bonjour" table:nil]);

        // NSProcessInfo
        NSProcessInfo *process = [NSProcessInfo processInfo];
        print([NSString stringWithFormat:@"%lu %@ pid %d home %d at least 1.0 %d", (unsigned long)process.arguments.count,
               process.processName, process.processIdentifier == getpid(), process.environment[@"HOME"] != nil,
               [process isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){1, 0, 0}]]);

        // NSThread and performs between threads
        print([NSString stringWithFormat:@"main %d %d", [NSThread isMainThread],
               [NSThread currentThread] == [NSThread mainThread]]);
        [NSThread currentThread].threadDictionary[@"slot"] = @"kept";
        Reporter *reporter = [Reporter new];
        [NSThread detachNewThreadWithBlock:^{
            [NSThread currentThread].name = @"worker";
            NSInteger sum = 0;
            for (NSInteger i = 1; i <= 100; i++) sum += i;
            [NSThread sleepForTimeInterval:0.01];
            NSString *message = [NSString stringWithFormat:@"%@ main %d sum %ld", [NSThread currentThread].name,
                                 [NSThread isMainThread], (long)sum];
            [reporter performSelectorOnMainThread:@selector(report:) withObject:message waitUntilDone:YES];
            [reporter performSelectorOnMainThread:@selector(finish) withObject:nil waitUntilDone:NO];
        }];
        CFRunLoopRun();
        print([NSString stringWithFormat:@"slot %@", [NSThread currentThread].threadDictionary[@"slot"]]);

        // NSUserDefaults
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        for (NSString *key in @[@"perry.count", @"perry.flag", @"perry.list"]) [defaults removeObjectForKey:key];
        [defaults registerDefaults:@{@"perry.count": @3, @"perry.flag": @YES}];
        NSInteger registered = [defaults integerForKey:@"perry.count"];
        [defaults setInteger:7 forKey:@"perry.count"];
        NSInteger set = [defaults integerForKey:@"perry.count"];
        [defaults setObject:@"42" forKey:@"perry.count"];
        [defaults setObject:@[@1, @"a"] forKey:@"perry.list"];
        print([NSString stringWithFormat:@"defaults %ld %ld %ld %@ flag %d list %lu missing %@", (long)registered, (long)set,
               (long)[defaults integerForKey:@"perry.count"], [defaults stringForKey:@"perry.count"],
               [defaults boolForKey:@"perry.flag"], (unsigned long)[defaults arrayForKey:@"perry.list"].count,
               [defaults objectForKey:@"perry.none"]]);
        [defaults removeObjectForKey:@"perry.count"];
        [defaults removeObjectForKey:@"perry.list"];
        print([NSString stringWithFormat:@"after removal %ld", (long)[defaults integerForKey:@"perry.count"]]);

        // NSFileManager
        NSFileManager *files = [NSFileManager defaultManager];
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:@"perry-satchel"];
        [files removeItemAtPath:root error:nil];
        NSError *error = nil;
        BOOL made = [files createDirectoryAtPath:[root stringByAppendingPathComponent:@"a/b"]
                     withIntermediateDirectories:YES attributes:nil error:&error];
        NSString *file = [root stringByAppendingPathComponent:@"a/note.txt"];
        BOOL created = [files createFileAtPath:file contents:[@"twelve bytes" dataUsingEncoding:NSUTF8StringEncoding]
                                    attributes:nil];
        BOOL copied = [files copyItemAtPath:file toPath:[root stringByAppendingPathComponent:@"a/copy.txt"] error:&error];
        BOOL moved = [files moveItemAtPath:[root stringByAppendingPathComponent:@"a/copy.txt"]
                                    toPath:[root stringByAppendingPathComponent:@"a/b/moved.txt"] error:&error];
        NSArray *listing = [[files contentsOfDirectoryAtPath:[root stringByAppendingPathComponent:@"a"] error:&error]
                            sortedArrayUsingSelector:@selector(compare:)];
        NSDictionary *attributes = [files attributesOfItemAtPath:file error:&error];
        BOOL isDirectory = NO;
        BOOL exists = [files fileExistsAtPath:[root stringByAppendingPathComponent:@"a/b"] isDirectory:&isDirectory];
        print([NSString stringWithFormat:@"files %d %d %d %d %@ size %@ %@ dir %d %d", made, created, copied, moved,
               [listing componentsJoinedByString:@","], attributes[NSFileSize],
               [attributes[NSFileType] isEqualToString:NSFileTypeRegular] ? @"regular" : @"other", exists, isDirectory]);
        print([NSString stringWithFormat:@"subpaths %@ contents %@", [[[files subpathsOfDirectoryAtPath:root error:nil]
                sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","], [[NSString alloc] initWithData:[files contentsAtPath:file]
                                                                      encoding:NSUTF8StringEncoding]]);
        BOOL removed = [files removeItemAtPath:root error:&error];
        BOOL missing = [files removeItemAtPath:root error:&error];
        print([NSString stringWithFormat:@"removed %d again %d error %@ exists %d", removed, missing, error.domain,
               [files fileExistsAtPath:root]]);
        NSURL *documents = [files URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        print([NSString stringWithFormat:@"documents %@", documents.lastPathComponent]);
    }
    return 0;
}
