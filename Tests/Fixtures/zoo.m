// Objective-C classes, a category, protocols, a property, ARC and a block.
// There is no SDK, so the root class is declared here; the runtime defines it.
int printf(const char *, ...);
typedef struct objc_object *id;

__attribute__((objc_root_class))
@interface NSObject { id isa; }
+ (instancetype)alloc;
- (instancetype)init;
@end

@protocol Greeting
- (const char *)greeting;
@end

@interface Animal : NSObject <Greeting>
@property (nonatomic) int legs;
- (void)speak;
@end

@implementation Animal
- (const char *)greeting { return "..."; }
- (void)speak { printf("%s legs=%d\n", [self greeting], self.legs); }
@end

@interface Dog : Animal
@end

@implementation Dog
- (const char *)greeting { return "woof"; }
+ (void)load { printf("Dog +load\n"); }
@end

@protocol Wagging
- (void)wag;
@end

@interface Animal (Extras) <Wagging>
- (void)wag;
@end

@implementation Animal (Extras)
- (void)wag { printf("wag\n"); }
@end

int main(void) {
    // Calls into the Objective-C runtime; only --report is run until it exists.
    Dog *dog = [[Dog alloc] init];
    dog.legs = 4;
    [dog speak];
    void (^block)(void) = ^{ [dog wag]; };
    block();
    return 0;
}
