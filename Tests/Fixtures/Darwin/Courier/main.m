// Data, URLs, UUIDs, JSON, errors and NSString's encodings, paths and
// searching, built on a Mac with Xcode. Prints only values that are the same
// on every run.
#import <Foundation/Foundation.h>

static void print(NSString *line) {
    printf("%s\n", line.UTF8String);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // NSData
        NSData *hello = [@"hello" dataUsingEncoding:NSUTF8StringEncoding];
        print([NSString stringWithFormat:@"%@ %lu %@", hello, (unsigned long)hello.length,
               [hello base64EncodedStringWithOptions:0]]);
        NSData *decoded = [[NSData alloc] initWithBase64EncodedString:@"d29ybGQ=" options:0];
        print([[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding]);
        NSMutableData *bytes = [NSMutableData dataWithLength:4];
        ((uint8_t *)bytes.mutableBytes)[1] = 0xab;
        uint8_t tail[] = {1, 2, 3};
        [bytes appendBytes:tail length:3];
        [bytes replaceBytesInRange:NSMakeRange(0, 1) withBytes:(uint8_t[]){0xff}];
        print([NSString stringWithFormat:@"%@ sub=%@ equal=%d", bytes, [bytes subdataWithRange:NSMakeRange(4, 3)],
               [bytes isEqualToData:[bytes copy]]]);
        uint8_t big[40];
        for (int i = 0; i < 40; i++) big[i] = (uint8_t)i;
        print([NSData dataWithBytes:big length:40].description);
        print([@"é" dataUsingEncoding:NSUTF16LittleEndianStringEncoding].description);
        print([NSString stringWithFormat:@"ascii nil %d", [@"é" dataUsingEncoding:NSASCIIStringEncoding] == nil]);

        // Files
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"perry-courier.txt"];
        NSError *error = nil;
        BOOL wrote = [@"line one\nline two" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
        NSString *read = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
        print([NSString stringWithFormat:@"wrote %d read %lu lines", wrote,
               (unsigned long)[read componentsSeparatedByString:@"\n"].count]);
        NSString *missing = [NSString stringWithContentsOfFile:@"/nonexistent/perry" encoding:NSUTF8StringEncoding
                                                         error:&error];
        print([NSString stringWithFormat:@"missing %@ domain %@ code %ld", missing, error.domain, (long)error.code]);

        // Paths
        NSString *file = @"/usr/local//lib/libz.1.dylib";
        print([NSString stringWithFormat:@"%@ | %@ | %@ | %@", file.lastPathComponent, file.pathExtension,
               file.stringByDeletingLastPathComponent, file.stringByDeletingPathExtension]);
        print([[@"/tmp/" stringByAppendingPathComponent:@"a"] stringByAppendingPathExtension:@"txt"]);
        print([@"/tmp/scratch/" pathComponents].description);
        print([NSString stringWithFormat:@"%@ %@ %d", [@"/" lastPathComponent], [@"name" stringByDeletingLastPathComponent],
               [@"relative/path" isAbsolutePath]]);

        // Searching
        NSString *text = @"The quick brown fox jumps over the lazy dog";
        NSRange fox = [text rangeOfString:@"fox"];
        NSRange the = [text rangeOfString:@"THE" options:NSCaseInsensitiveSearch | NSBackwardsSearch];
        print([NSString stringWithFormat:@"fox {%lu, %lu} the {%lu, %lu} cat %d", (unsigned long)fox.location,
               (unsigned long)fox.length, (unsigned long)the.location, (unsigned long)the.length,
               [text rangeOfString:@"cat"].location == NSNotFound]);
        print([NSString stringWithFormat:@"%@ | %@ | %@", [text substringToIndex:9], [text substringFromIndex:40],
               [text substringWithRange:NSMakeRange(10, 5)]]);
        print([[text stringByReplacingOccurrencesOfString:@"o" withString:@"0"] capitalizedString]);
        print([NSString stringWithFormat:@"%d %d %ld %d %lld", [text containsString:@"jumps"], [@"YES" boolValue],
               (long)[@"apple" caseInsensitiveCompare:@"APPLE"], [@" 42abc" intValue], [@"-9000000000" longLongValue]]);

        // URLs
        NSURL *url = [NSURL URLWithString:@"https://user@example.com:8080/a/b/report.pdf?x=1&y=2#top"];
        print([NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@ %@ %@", url.scheme, url.host, url.port, url.path, url.query,
               url.fragment, url.lastPathComponent, url.pathExtension]);
        print(url.URLByDeletingLastPathComponent.absoluteString);
        print([[url URLByDeletingPathExtension] URLByAppendingPathExtension:@"txt"].absoluteString);
        NSURL *fileURL = [NSURL fileURLWithPath:@"/tmp/some file.txt"];
        print([NSString stringWithFormat:@"%@ %d %@", fileURL, fileURL.isFileURL, fileURL.path]);
        print([[NSURL URLWithString:@"../c/d.html" relativeToURL:url] absoluteString]);
        print([NSString stringWithFormat:@"equal %d", [url isEqual:[NSURL URLWithString:url.absoluteString]]]);

        // UUIDs
        NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:@"e621e1f8-c36c-495a-93fc-0c247a3e6e5f"];
        uuid_t raw;
        [uuid getUUIDBytes:raw];
        print([NSString stringWithFormat:@"%@ %02x%02x %d %d", uuid.UUIDString, raw[0], raw[15],
               [[NSUUID alloc] initWithUUIDString:@"not a uuid"] == nil, [NSUUID UUID].UUIDString.length]);

        // JSON
        NSData *json = [@"{\"name\":\"Perry\",\"tags\":[\"a\",\"b\"],\"count\":3,\"ratio\":0.5,\"ok\":true,\"none\":null}"
                        dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *object = [NSJSONSerialization JSONObjectWithData:json options:0 error:&error];
        print([NSString stringWithFormat:@"%@ %@ %@ %@ %@ %d", object[@"name"], object[@"tags"][1], object[@"count"],
               object[@"ratio"], object[@"ok"], object[@"none"] == [NSNull null]]);
        NSData *written = [NSJSONSerialization dataWithJSONObject:@{@"b": @[@1, @2.5, @YES, [NSNull null]], @"a": @"x/y"}
                                                          options:NSJSONWritingSortedKeys error:&error];
        print([[NSString alloc] initWithData:written encoding:NSUTF8StringEncoding]);
        NSData *pretty = [NSJSONSerialization dataWithJSONObject:@{@"k": @[@1]}
                                                         options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                           error:&error];
        print([[NSString alloc] initWithData:pretty encoding:NSUTF8StringEncoding]);
        id bad = [NSJSONSerialization JSONObjectWithData:[@"{oops" dataUsingEncoding:NSUTF8StringEncoding] options:0
                                                   error:&error];
        print([NSString stringWithFormat:@"bad %@ %@ %ld valid %d %d", bad, error.domain, (long)error.code,
               [NSJSONSerialization isValidJSONObject:@[@1]], [NSJSONSerialization isValidJSONObject:@"x"]]);

        // Errors
        NSError *custom = [NSError errorWithDomain:@"com.example.courier" code:42 userInfo:nil];
        print(custom.localizedDescription);
        print(custom.description);
        NSError *described = [NSError errorWithDomain:@"Courier" code:7
                                             userInfo:@{NSLocalizedDescriptionKey: @"Package lost"}];
        print([NSString stringWithFormat:@"%@ | %@", described.localizedDescription, described]);
    }
    return 0;
}
