// Foundation basics, built on a Mac with Xcode: strings and formatting,
// numbers, mutable arrays, fast enumeration and descriptions. Prints to
// stdout so the test can compare exact text.
#import <Foundation/Foundation.h>

static void print(NSString *line) {
    printf("%s\n", line.UTF8String);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        print([NSString stringWithFormat:@"%d|%5ld|%-3s|%.2f|%x|%c|%%|%@",
               -7, (long)42, "ab", 3.14159, 255u, 'Z', @"obj"]);
        print([NSString stringWithFormat:@"%@ %@ %@", @(12), @(2.5), @YES]);

        NSString *greeting = [@"Hello" stringByAppendingString:@", world"];
        print([NSString stringWithFormat:@"%@ (%lu) upper=%@ prefix=%d",
               greeting, (unsigned long)greeting.length, greeting.uppercaseString,
               [greeting hasPrefix:@"Hell"]]);
        print([NSString stringWithFormat:@"equal=%d compare=%ld",
               [greeting isEqualToString:@"Hello, world"], (long)[@"apple" compare:@"banana"]]);
        print([NSString stringWithFormat:@"unicode=%@ %lu", @"café ☕", (unsigned long)@"café ☕".length]);

        NSMutableArray<NSNumber *> *values = [NSMutableArray array];
        for (NSInteger i = 5; i > 0; i--) {
            [values addObject:@(i * 10)];
        }
        [values removeObjectAtIndex:0];
        [values insertObject:@99 atIndex:1];
        NSInteger total = 0;
        for (NSNumber *value in values) {
            total += value.integerValue;
        }
        print([NSString stringWithFormat:@"count=%lu total=%ld first=%@ last=%@",
               (unsigned long)values.count, (long)total, values.firstObject, values.lastObject]);

        NSArray *sorted = [values sortedArrayUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
            return [a compare:b];
        }];
        print([sorted componentsJoinedByString:@","]);
        print([NSString stringWithFormat:@"contains=%d index=%lu", [sorted containsObject:@99],
               (unsigned long)[sorted indexOfObject:@20]]);
        print([NSArray arrayWithObjects:@"x", @"y", nil].description);
    }
    return 0;
}
