// Results narrower than 32 bits, which arm64 Darwin's callee extends to 32:
// code built for it, as this is with -O1, uses w0 as it comes back, so
// `int x = [n shortValue]` prints whatever is above the short. Each value is
// read into an int, unsigned or long through a function the compiler can't
// see into, and printed from there. Built on a Mac with Xcode; prints to
// stdout so the test can compare exact text.
#import <Foundation/Foundation.h>

// Not inlined, so the call's result is the register as the method left it.
__attribute__((noinline)) static int shortOf(NSNumber *n) { return n.shortValue; }
__attribute__((noinline)) static unsigned unsignedShortOf(NSNumber *n) { return n.unsignedShortValue; }
__attribute__((noinline)) static int charOf(NSNumber *n) { return n.charValue; }
__attribute__((noinline)) static unsigned unsignedCharOf(NSNumber *n) { return n.unsignedCharValue; }
__attribute__((noinline)) static unsigned boolOf(NSNumber *n) { return n.boolValue; }

// The same through a long, for code that widens further.
__attribute__((noinline)) static long longShortOf(NSNumber *n) { return n.shortValue; }
__attribute__((noinline)) static unsigned long longUnsignedShortOf(NSNumber *n) { return n.unsignedShortValue; }

static void print(NSString *label, NSNumber *n) {
    printf("%s: short %d ushort %u char %d uchar %u bool %u long %ld ulong %lu\n", label.UTF8String,
           shortOf(n), unsignedShortOf(n), charOf(n), unsignedCharOf(n), boolOf(n), longShortOf(n),
           longUnsignedShortOf(n));
    fflush(stdout);
}

// An object of the app's, whose narrow results Foundation reads through
// key-value coding.
@interface Gauge : NSObject
@property (nonatomic) short level;
@property (nonatomic) unsigned short reading;
@property (nonatomic) char mark;
@property (nonatomic) unsigned char notch;
@property (nonatomic) BOOL calibrated;
@end

@implementation Gauge
@end

int main(void) {
    @autoreleasepool {
        print(@"70000", @70000);
        print(@"-1", @(-1));
        print(@"200", @200);
        print(@"-129", @(-129));
        print(@"65535", @65535);
        print(@"256", @256);
        print(@"0", @0);
        print(@"-70000", @(-70000));
        print(@"4294967295", @4294967295LL);
        print(@"short -2", [NSNumber numberWithShort:-2]);
        print(@"uchar 255", [NSNumber numberWithUnsignedChar:255]);
        print(@"bool YES", @YES);

        print(@"decimal 123456789012345678.9", [NSDecimalNumber decimalNumberWithString:@"123456789012345678.9"]);
        print(@"decimal -123456789012345678.9", [NSDecimalNumber decimalNumberWithString:@"-123456789012345678.9"]);
        print(@"decimal 70000.5", [NSDecimalNumber decimalNumberWithString:@"70000.5"]);
        print(@"decimal -1", [NSDecimalNumber decimalNumberWithString:@"-1"]);
        print(@"decimal 300", [NSDecimalNumber decimalNumberWithString:@"300"]);
        print(@"decimal 0", [NSDecimalNumber zero]);

        Gauge *gauge = [[Gauge alloc] init];
        gauge.level = -2;
        gauge.reading = 65000;
        gauge.mark = -100;
        gauge.notch = 250;
        gauge.calibrated = YES;
        for (NSString *key in @[@"level", @"reading", @"mark", @"notch", @"calibrated"]) {
            printf("gauge %s: %s\n", key.UTF8String, [[gauge valueForKey:key] description].UTF8String);
        }
        fflush(stdout);
    }
    return 0;
}
