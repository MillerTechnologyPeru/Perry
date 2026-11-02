// Key-value observing: automatic notifications from setters and
// -setValue:forKey:, the change dictionary for each option, the class an
// observed object reports, manual notifications, dependent keys, key paths
// through other objects, to-many changes, contexts and removal.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stdio.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

typedef struct {
    double x, y;
} Spot;

@interface Person : NSObject
@property (copy) NSString *firstName;
@property (copy) NSString *lastName;
@property (readonly) NSString *fullName;
@property NSInteger age;
@property double height;
@property BOOL active;
@property char grade;
@property float weight;
@property NSRange span;
@property Spot spot;
@property (strong) Person *friend;
@property (copy) NSString *quiet;
@property (strong) NSMutableArray *items;
@property (copy) NSURL *URL;
@end

@implementation Person
+ (NSSet *)keyPathsForValuesAffectingFullName {
    return [NSSet setWithObjects:@"firstName", @"lastName", nil];
}
+ (BOOL)automaticallyNotifiesObserversOfQuiet {
    return NO;
}
- (NSString *)fullName {
    return [NSString stringWithFormat:@"%@ %@", self.firstName, self.lastName];
}
- (void)setQuietManually:(NSString *)quiet {
    [self willChangeValueForKey:@"quiet"];
    _quiet = [quiet copy];
    [self didChangeValueForKey:@"quiet"];
}
- (void)insertItem:(id)item atIndex:(NSUInteger)index {
    NSIndexSet *indexes = [NSIndexSet indexSetWithIndex:index];
    [self willChange:NSKeyValueChangeInsertion valuesAtIndexes:indexes forKey:@"items"];
    [_items insertObject:item atIndex:index];
    [self didChange:NSKeyValueChangeInsertion valuesAtIndexes:indexes forKey:@"items"];
}
- (void)removeItemAtIndex:(NSUInteger)index {
    NSIndexSet *indexes = [NSIndexSet indexSetWithIndex:index];
    [self willChange:NSKeyValueChangeRemoval valuesAtIndexes:indexes forKey:@"items"];
    [_items removeObjectAtIndex:index];
    [self didChange:NSKeyValueChangeRemoval valuesAtIndexes:indexes forKey:@"items"];
}
@end

static NSString *describe(id value) {
    if (value == nil) return @"nil";
    if (value == [NSNull null]) return @"<null>";
    if ([value isKindOfClass:NSValue.class] && ![value isKindOfClass:NSNumber.class]) {
        return [NSString stringWithFormat:@"%s %@", [value objCType], value];
    }
    if ([value isKindOfClass:NSIndexSet.class]) {
        NSMutableArray *list = [NSMutableArray array];
        [value enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) { [list addObject:@(index)]; }];
        return [NSString stringWithFormat:@"indexes[%@]", [list componentsJoinedByString:@","]];
    }
    if ([value isKindOfClass:NSArray.class]) return [NSString stringWithFormat:@"[%@]", [value componentsJoinedByString:@","]];
    return [value description];
}

@interface Watcher : NSObject
@property (copy) NSString *name;
@property NSInteger count;
@end

@implementation Watcher
- (instancetype)initWithName:(NSString *)name {
    if ((self = [super init])) _name = name;
    return self;
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    self.count++;
    NSArray *keys = [change.allKeys sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *key in keys) {
        [parts addObject:[NSString stringWithFormat:@"%@=%@", key, describe(change[key])]];
    }
    say([NSString stringWithFormat:@"%@: %@ of %@ (%s) {%@}", self.name, keyPath, [object class],
         context ? (const char *)context : "no context", [parts componentsJoinedByString:@" "]]);
}
@end

static NSString *classes(id object) {
    return [NSString stringWithFormat:@"class %@, isa %s", [object class], object_getClassName(object)];
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        Person *person = [Person new];
        person.firstName = @"Ada";
        person.lastName = @"Lovelace";
        person.items = [NSMutableArray arrayWithObjects:@"a", @"b", nil];
        Watcher *watcher = [[Watcher alloc] initWithName:@"w1"];
        Watcher *other = [[Watcher alloc] initWithName:@"w2"];
        static char nameContext[] = "name context";

        say([NSString stringWithFormat:@"before: %@", classes(person)]);
        [person addObserver:watcher forKeyPath:@"firstName"
                    options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld context:nameContext];
        say([NSString stringWithFormat:@"observing: %@, superclass %@, responds %d", classes(person),
             class_getSuperclass(object_getClass(person)), [person respondsToSelector:@selector(setFirstName:)]]);
        person.firstName = @"Augusta";
        [person setValue:@"Ada" forKey:@"firstName"];
        person.firstName = nil;
        person.firstName = @"Ada";

        // Each option.
        [person addObserver:watcher forKeyPath:@"age" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:NULL];
        person.age = 36;
        [person addObserver:watcher forKeyPath:@"height" options:NSKeyValueObservingOptionPrior | NSKeyValueObservingOptionOld context:NULL];
        person.height = 1.65;
        [person addObserver:watcher forKeyPath:@"active" options:0 context:NULL];
        person.active = YES;

        // Scalars and structures of each kind.
        NSKeyValueObservingOptions both = NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld;
        for (NSString *key in @[@"grade", @"weight", @"span", @"spot", @"URL"]) {
            [person addObserver:watcher forKeyPath:key options:both context:NULL];
        }
        person.grade = 'A';
        person.weight = 52.5f;
        person.span = NSMakeRange(3, 4);
        person.spot = (Spot){1.5, -2};
        person.URL = [NSURL URLWithString:@"https://example.com"];
        say([NSString stringWithFormat:@"values: %c %.1f %@ %.1f,%.1f %@", person.grade, person.weight,
             NSStringFromRange(person.span), person.spot.x, person.spot.y, person.URL]);

        // Two observers of one key, in order, and a dependent key.
        [person addObserver:other forKeyPath:@"firstName" options:NSKeyValueObservingOptionNew context:NULL];
        [person addObserver:other forKeyPath:@"fullName" options:both context:NULL];
        person.firstName = @"Countess";
        person.lastName = @"of Lovelace";

        // Manual notifications only.
        [person addObserver:watcher forKeyPath:@"quiet" options:both context:NULL];
        person.quiet = @"silent";
        [person setQuietManually:@"loud"];

        // A key path through another object, which is replaced.
        Person *friend = [Person new];
        friend.firstName = @"Charles";
        person.friend = friend;
        [person addObserver:other forKeyPath:@"friend.firstName" options:both context:NULL];
        friend.firstName = @"Charlie";
        Person *replacement = [Person new];
        replacement.firstName = @"Mary";
        person.friend = replacement;
        friend.firstName = @"ignored";
        replacement.firstName = @"Mary Somerville";
        person.friend = nil;

        // To-many changes.
        [person addObserver:watcher forKeyPath:@"items" options:both context:NULL];
        [person insertItem:@"z" atIndex:1];
        [person removeItemAtIndex:0];
        person.items = [NSMutableArray arrayWithObject:@"new"];

        // Removal: by context, then all; the class goes back.
        [person removeObserver:watcher forKeyPath:@"firstName" context:nameContext];
        person.firstName = @"Ada";
        [person removeObserver:other forKeyPath:@"firstName"];
        [person removeObserver:other forKeyPath:@"fullName"];
        [person removeObserver:other forKeyPath:@"friend.firstName"];
        for (NSString *key in @[@"age", @"height", @"active", @"grade", @"weight", @"span", @"spot", @"URL", @"quiet", @"items"]) {
            [person removeObserver:watcher forKeyPath:key];
        }
        person.age = 99;
        say([NSString stringWithFormat:@"after: %@, %ld and %ld notifications", classes(person), (long)watcher.count, (long)other.count]);

        // Another instance of the class is unaffected; observing a second
        // instance reuses the class.
        Person *stranger = [Person new];
        say([NSString stringWithFormat:@"stranger: %@", classes(stranger)]);
        [stranger addObserver:watcher forKeyPath:@"age" options:NSKeyValueObservingOptionNew context:NULL];
        [person addObserver:watcher forKeyPath:@"lastName" options:NSKeyValueObservingOptionNew context:NULL];
        say([NSString stringWithFormat:@"both: %@ / %@, same %d", classes(stranger), classes(person),
             object_getClass(stranger) == object_getClass(person)]);
        stranger.age = 7;
        person.age = 8;
        person.lastName = @"Byron";
        [stranger removeObserver:watcher forKeyPath:@"age"];
        [person removeObserver:watcher forKeyPath:@"lastName"];
        say([NSString stringWithFormat:@"done: %@, %ld notifications", classes(stranger), (long)watcher.count]);
    }
    return 0;
}
