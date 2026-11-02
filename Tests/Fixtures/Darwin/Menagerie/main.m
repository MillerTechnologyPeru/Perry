// An Objective-C app built on a Mac with Xcode against the real iPhoneOS SDK,
// so its metadata is what Apple's toolchain emits: relative method lists,
// objc_msgSend selector stubs, Foundation classes and constant strings.
#import <Foundation/Foundation.h>

@protocol Greeting <NSObject>
- (NSString *)greeting;
@end

@interface Animal : NSObject <Greeting>
@property (nonatomic, copy) NSString *name;
@property (nonatomic) NSInteger legs;
- (instancetype)initWithName:(NSString *)name legs:(NSInteger)legs;
- (NSString *)describe;
@end

@implementation Animal
- (instancetype)initWithName:(NSString *)name legs:(NSInteger)legs {
    if ((self = [super init])) {
        _name = [name copy];
        _legs = legs;
    }
    return self;
}
- (NSString *)greeting { return @"..."; }
- (NSString *)describe {
    return [NSString stringWithFormat:@"%@ says %@ on %ld legs", self.name, [self greeting], (long)self.legs];
}
@end

@interface Dog : Animal
@end

@implementation Dog
- (NSString *)greeting { return @"woof"; }
+ (void)load { printf("Dog +load\n"); }
@end

@interface Animal (Sorting)
- (NSComparisonResult)compareByLegs:(Animal *)other;
@end

@implementation Animal (Sorting)
- (NSComparisonResult)compareByLegs:(Animal *)other {
    return [@(self.legs) compare:@(other.legs)];
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSArray<Animal *> *zoo = @[
            [[Dog alloc] initWithName:@"Rex" legs:4],
            [[Animal alloc] initWithName:@"Kiwi" legs:2],
        ];
        NSArray *sorted = [zoo sortedArrayUsingSelector:@selector(compareByLegs:)];
        [sorted enumerateObjectsUsingBlock:^(Animal *animal, NSUInteger index, BOOL *stop) {
            NSLog(@"%lu: %@", (unsigned long)index, [animal describe]);
        }];
    }
    return 0;
}
