// Collections, predicates and sort descriptors, built on a Mac with Xcode:
// the less common NSArray, NSOrderedSet, NSSet, NSDictionary and NSIndexSet
// methods, key-value coding through collections, NSPointerFunctions and the
// pointer collections, comparator sort descriptors, custom selector and
// compound predicates, and set, block and subquery expressions. Prints to
// stdout so the test can compare exact text.
#import <Foundation/Foundation.h>

static void say(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void say(NSString *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);
    printf("%s\n", line.UTF8String);
}

/// A collection's members joined by commas; a set's sorted first.
static NSString *J(id collection) {
    NSArray *items = [collection isKindOfClass:[NSSet class]]
        ? [[collection allObjects] sortedArrayUsingSelector:@selector(compare:)]
        : ([collection isKindOfClass:[NSOrderedSet class]] ? [collection array] : collection);
    NSMutableArray *parts = [NSMutableArray array];
    for (id item in items) [parts addObject:[item description]];
    return [parts componentsJoinedByString:@","];
}

/// An index set's indexes joined by commas.
static NSString *I(NSIndexSet *indexes) {
    NSMutableArray *parts = [NSMutableArray array];
    [indexes enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) { [parts addObject:@(index).description]; }];
    return [NSString stringWithFormat:@"[%@]", [parts componentsJoinedByString:@","]];
}

static NSInteger byLength(id a, id b, void *context) {
    NSUInteger x = [a length], y = [b length];
    return x < y ? NSOrderedAscending : x > y ? NSOrderedDescending : NSOrderedSame;
}

@interface Item : NSObject
@property (nonatomic) NSInteger level;
@end
@implementation Item
@end

@interface Watcher : NSObject
@property (nonatomic) NSInteger heard;
@end
@implementation Watcher
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    self.heard += 1;
    say(@"kvo: %@ -> %@", keyPath, change[NSKeyValueChangeNewKey]);
}
@end

static void arrays(void) {
    NSArray *letters = @[@"a", @"b", @"c", @"b", @"d"];
    say(@"indexOfObject:inRange: %lu %d", (unsigned long)[letters indexOfObject:@"b" inRange:NSMakeRange(2, 3)],
        [letters indexOfObject:@"d" inRange:NSMakeRange(0, 3)] == NSNotFound);
    say(@"firstObjectCommon: %@ %@", [letters firstObjectCommonWithArray:@[@"z", @"c", @"b"]],
        [letters firstObjectCommonWithArray:@[@"q"]]);
    NSMutableIndexSet *picks = [NSMutableIndexSet indexSetWithIndex:0];
    [picks addIndex:1];
    [picks addIndex:3];
    BOOL (^isB)(id, NSUInteger, BOOL *) = ^BOOL(id object, NSUInteger index, BOOL *stop) { return [object isEqual:@"b"]; };
    say(@"indexOfObjectAtIndexes: %lu reverse %lu", (unsigned long)[letters indexOfObjectAtIndexes:picks options:0 passingTest:isB],
        (unsigned long)[letters indexOfObjectAtIndexes:picks options:NSEnumerationReverse passingTest:isB]);
    say(@"indexesOfObjectsAtIndexes: %@", I([letters indexesOfObjectsAtIndexes:picks options:0 passingTest:isB]));
    say(@"pathsMatchingExtensions: %@", J([@[@"a.txt", @"b.TXT", @"c.png", @"d", @"e.txt"] pathsMatchingExtensions:@[@"txt", @"png"]]));
    NSArray *words = @[@"ccc", @"a", @"bb"];
    NSData *hint = [words sortedArrayHint];
    say(@"hint: %d sorted %@", hint != nil, J([words sortedArrayUsingFunction:byLength context:NULL hint:hint]));
    say(@"valueForKey: %@ @count %@", J([words valueForKey:@"length"]), [words valueForKey:@"@count"]);
    NSArray *records = @[[NSMutableDictionary dictionary], [NSMutableDictionary dictionaryWithObject:@1 forKey:@"x"]];
    [records setValue:@7 forKey:@"x"];
    say(@"setValue:forKey: %@", J([records valueForKey:@"x"]));

    Item *first = [Item new], *second = [Item new], *third = [Item new];
    NSArray *items = @[first, second, third];
    Watcher *watcher = [Watcher new];
    NSIndexSet *ends = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, 2)];
    [items addObserver:watcher toObjectsAtIndexes:ends forKeyPath:@"level" options:NSKeyValueObservingOptionNew context:NULL];
    first.level = 1;
    second.level = 2;
    third.level = 3;
    [items removeObserver:watcher fromObjectsAtIndexes:ends forKeyPath:@"level" context:NULL];
    third.level = 4;
    say(@"observed elements: heard %ld", (long)watcher.heard);
}

static void mutableArrays(void) {
    NSMutableArray *list = [@[@"a", @"b", @"a", @"c", @"a"] mutableCopy];
    [list removeObject:@"a" inRange:NSMakeRange(1, 3)];
    say(@"removeObject:inRange: %@", J(list));
    NSString *same = list[0];
    [list removeObjectIdenticalTo:same inRange:NSMakeRange(0, 1)];
    say(@"removeObjectIdenticalTo:inRange: %@", J(list));
    NSMutableArray *numbers = [@[@0, @1, @2, @3, @4] mutableCopy];
    NSUInteger doomed[] = {3, 0};
    [numbers removeObjectsFromIndices:doomed numIndices:2];
    say(@"removeObjectsFromIndices: %@", J(numbers));
    NSMutableIndexSet *spots = [NSMutableIndexSet indexSetWithIndex:0];
    [spots addIndex:2];
    [numbers replaceObjectsAtIndexes:spots withObjects:@[@10, @40]];
    say(@"replaceObjectsAtIndexes: %@", J(numbers));
    [numbers insertObjects:@[@7, @8] atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, 2)]];
    say(@"insertObjects:atIndexes: %@", J(numbers));
    [numbers removeObjectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 2)]];
    say(@"removeObjectsAtIndexes: %@", J(numbers));
    [numbers filterUsingPredicate:[NSPredicate predicateWithFormat:@"SELF > 8"]];
    say(@"filterUsingPredicate: %@", J(numbers));

    NSMutableArray *from = [@[@"a", @"b", @"c"] mutableCopy];
    NSOrderedCollectionDifference *difference = [@[@"b", @"c", @"d"] differenceFromArray:from];
    [from applyDifference:difference];
    say(@"applyDifference: %@", J(from));

    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"quiver-list.plist"];
    [@[@[@1], @{@"k": @"v"}] writeToFile:path atomically:YES];
    NSMutableArray *read = [NSMutableArray arrayWithContentsOfFile:path];
    [read[0] addObject:@2];
    NSMutableArray *again = [[NSMutableArray alloc] initWithContentsOfFile:path];
    [again addObject:@"more"];
    say(@"arrayWithContentsOfFile: %@ nested %@ count %lu", NSStringFromClass([read class]).length ? @"read" : @"-", J(read[0]),
        (unsigned long)again.count);
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    say(@"missing file: %d", [NSMutableArray arrayWithContentsOfFile:[path stringByAppendingString:@".none"]] == nil);
}

static void orderedSets(void) {
    NSMutableString *original = [NSMutableString stringWithString:@"m"];
    NSArray *source = @[@"x", original, @"y", @"z"];
    NSOrderedSet *copied = [NSOrderedSet orderedSetWithArray:source range:NSMakeRange(1, 2) copyItems:YES];
    NSOrderedSet *shared = [[NSOrderedSet alloc] initWithArray:source range:NSMakeRange(1, 2) copyItems:NO];
    say(@"withArray:range:copyItems: %@ copied %d shared %d", J(copied), copied[0] != original, shared[0] == original);
    id objects[] = {@"p", @"q", @"p"};
    say(@"withObjects:count: %@ init %@", J([NSOrderedSet orderedSetWithObjects:objects count:3]),
        J([[NSOrderedSet alloc] initWithObjects:objects count:2]));
    say(@"withSet:copyItems: %@ initWithSet %@", J([NSOrderedSet orderedSetWithSet:[NSSet setWithObject:@"s"] copyItems:YES]),
        J([[NSOrderedSet alloc] initWithSet:[NSSet setWithObject:@"t"] copyItems:NO]));
    NSOrderedSet *base = [NSOrderedSet orderedSetWithArray:@[@"d", @"a", @"c", @"b"]];
    say(@"initWithObject: %@ initWithArray:copyItems: %@ initWithOrderedSet:copyItems: %@",
        J([[NSOrderedSet alloc] initWithObject:@"o"]), J([[NSOrderedSet alloc] initWithArray:@[@"u", @"u", @"v"] copyItems:YES]),
        J([[NSOrderedSet alloc] initWithOrderedSet:base copyItems:YES]));
    say(@"initWithOrderedSet:range:copyItems: %@", J([[NSOrderedSet alloc] initWithOrderedSet:base range:NSMakeRange(1, 2) copyItems:NO]));
    NSOrderedSet *spaced = [NSOrderedSet orderedSetWithObjects:@"a b", @1, nil];
    say(@"description %@", spaced);
    say(@"descriptionWithLocale:indent: %@", [spaced descriptionWithLocale:nil indent:1]);
    say(@"descriptionWithLocale: %d", [[spaced descriptionWithLocale:nil] isEqual:spaced.description]);

    __unsafe_unretained id buffer[2];
    [base getObjects:buffer range:NSMakeRange(1, 2)];
    say(@"getObjects:range: %@ %@", buffer[0], buffer[1]);
    NSMutableArray *seen = [NSMutableArray array];
    [base enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(id object, NSUInteger index, BOOL *stop) {
        [seen addObject:[NSString stringWithFormat:@"%lu%@", (unsigned long)index, object]];
    }];
    [base enumerateObjectsAtIndexes:[NSIndexSet indexSetWithIndex:2] options:0 usingBlock:^(id object, NSUInteger index, BOOL *stop) {
        [seen addObject:[NSString stringWithFormat:@"at%lu%@", (unsigned long)index, object]];
    }];
    say(@"enumerate: %@", J(seen));
    BOOL (^early)(id, NSUInteger, BOOL *) = ^BOOL(id object, NSUInteger index, BOOL *stop) { return [object compare:@"c"] == NSOrderedAscending; };
    say(@"indexesOfObjectsPassingTest: %@ options %@ atIndexes %@ indexOf %lu", I([base indexesOfObjectsPassingTest:early]),
        I([base indexesOfObjectsWithOptions:NSEnumerationReverse passingTest:early]),
        I([base indexesOfObjectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(2, 2)] options:0 passingTest:early]),
        (unsigned long)[base indexOfObjectAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 4)] options:NSEnumerationReverse passingTest:early]);
    NSComparator compare = ^NSComparisonResult(id a, id b) { return [a compare:b]; };
    NSOrderedSet *sorted = [NSOrderedSet orderedSetWithArray:@[@10, @20, @30, @40]];
    say(@"indexOfObject:inSortedRange: %lu insertion %lu", (unsigned long)[sorted indexOfObject:@30 inSortedRange:NSMakeRange(0, 4) options:0 usingComparator:compare],
        (unsigned long)[sorted indexOfObject:@25 inSortedRange:NSMakeRange(0, 4) options:NSBinarySearchingInsertionIndex usingComparator:compare]);
    say(@"filteredOrderedSet: %@", J([base filteredOrderedSetUsingPredicate:[NSPredicate predicateWithFormat:@"SELF IN {'a', 'b', 'x'}"]]));
    say(@"enumerators: %@ / %@", J(base.objectEnumerator.allObjects), J(base.reverseObjectEnumerator.allObjects));
    say(@"sortedArrayUsingComparator: %@ options %@ descriptors %@", J([base sortedArrayUsingComparator:compare]),
        J([base sortedArrayWithOptions:NSSortStable usingComparator:compare]),
        J([base sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"self" ascending:NO]]]));
    NSOrderedSet *later = [NSOrderedSet orderedSetWithArray:@[@"a", @"c", @"e"]];
    NSOrderedCollectionDifference *difference = [later differenceFromOrderedSet:base];
    say(@"difference: +%lu -%lu applied %@", (unsigned long)difference.insertions.count, (unsigned long)difference.removals.count,
        J([base orderedSetByApplyingDifference:difference]));
    NSOrderedCollectionDifference *loose = [later differenceFromOrderedSet:base withOptions:0 usingEquivalenceTest:^BOOL(id a, id b) {
        return YES;
    }];
    say(@"difference with test: +%lu -%lu options %lu", (unsigned long)loose.insertions.count, (unsigned long)loose.removals.count,
        (unsigned long)[later differenceFromOrderedSet:base withOptions:NSOrderedCollectionDifferenceCalculationOmitInsertedObjects].insertions.count);
    say(@"valueForKey: %@ @count %@", J([base valueForKey:@"uppercaseString"]), [base valueForKey:@"@count"]);
    NSOrderedSet *boxes = [NSOrderedSet orderedSetWithObjects:[NSMutableDictionary dictionary], [NSMutableArray array], nil];
    [[NSOrderedSet orderedSetWithObject:boxes[0]] setValue:@"v" forKey:@"k"];
    say(@"setValue:forKey: %@", [boxes[0] objectForKey:@"k"]);
}

static void mutableOrderedSets(void) {
    NSMutableOrderedSet *set = [NSMutableOrderedSet orderedSetWithArray:@[@0, @1, @2, @3, @4, @5]];
    NSMutableIndexSet *moving = [NSMutableIndexSet indexSetWithIndex:1];
    [moving addIndex:4];
    [set moveObjectsAtIndexes:moving toIndex:2];
    say(@"moveObjectsAtIndexes: %@", J(set));
    id more[] = {@9, @0, @8};
    [set addObjects:more count:3];
    say(@"addObjects:count: %@", J(set));
    [set removeObjectsInRange:NSMakeRange(0, 2)];
    say(@"removeObjectsInRange: %@", J(set));
    [set removeObjectsAtIndexes:[NSIndexSet indexSetWithIndex:0]];
    say(@"removeObjectsAtIndexes: %@", J(set));
    [set insertObjects:@[@20, @21] atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, 2)]];
    say(@"insertObjects:atIndexes: %@", J(set));
    [set replaceObjectsAtIndexes:[NSIndexSet indexSetWithIndex:0] withObjects:@[@30]];
    say(@"replaceObjectsAtIndexes: %@", J(set));
    id swap[] = {@40, @41};
    [set replaceObjectsInRange:NSMakeRange(1, 2) withObjects:swap count:2];
    say(@"replaceObjectsInRange: %@", J(set));
    NSComparator descending = ^NSComparisonResult(id a, id b) { return [b compare:a]; };
    [set sortRange:NSMakeRange(0, 3) options:0 usingComparator:descending];
    say(@"sortRange: %@", J(set));
    [set sortUsingComparator:^NSComparisonResult(id a, id b) { return [a compare:b]; }];
    say(@"sortUsingComparator: %@", J(set));
    [set sortWithOptions:NSSortConcurrent usingComparator:descending];
    say(@"sortWithOptions: %@", J(set));
    [set sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"integerValue" ascending:YES]]];
    say(@"sortUsingDescriptors: %@", J(set));
    [set intersectSet:[NSSet setWithObjects:@8, @9, @30, @41, @99, nil]];
    say(@"intersectSet: %@", J(set));
    [set filterUsingPredicate:[NSPredicate predicateWithFormat:@"SELF < 40"]];
    say(@"filterUsingPredicate: %@", J(set));
    NSOrderedSet *target = [NSOrderedSet orderedSetWithArray:@[@1, @9, @30]];
    [set applyDifference:[target differenceFromOrderedSet:set]];
    say(@"applyDifference: %@", J(set));
}

static void sets(void) {
    NSSet *numbers = [NSSet setWithObjects:@3, @1, @2, nil];
    __block NSInteger total = 0;
    [numbers enumerateObjectsWithOptions:NSEnumerationConcurrent usingBlock:^(id object, BOOL *stop) {
        @synchronized (numbers) { total += [object integerValue]; }
    }];
    say(@"set enumerateObjectsWithOptions: %ld", (long)total);
    say(@"set sortedArrayUsingDescriptors: %@", J([numbers sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"self" ascending:NO]]]));
    say(@"set valueForKey: %@ @count %@", J([[NSSet setWithObjects:@"a", @"bb", nil] valueForKey:@"length"]), [numbers valueForKey:@"@count"]);
    NSMutableDictionary *box = [NSMutableDictionary dictionary];
    [[NSSet setWithObject:box] setValue:@"set" forKey:@"from"];
    say(@"set setValue:forKey: %@", box[@"from"]);
    NSMutableSet *mutable = [NSMutableSet setWithObjects:@1, @5, @10, nil];
    [mutable filterUsingPredicate:[NSPredicate predicateWithFormat:@"SELF >= 5"]];
    say(@"set filterUsingPredicate: %@", J(mutable));
    NSCountedSet *counted = [NSCountedSet setWithArray:@[@"k", @"k"]];
    say(@"counted objectEnumerator: %@ %lu", J(counted.objectEnumerator.allObjects), (unsigned long)[counted countForObject:@"k"]);
}

static void dictionaries(void) {
    NSDictionary *attributes = @{NSFileExtensionHidden: @YES, NSFileGroupOwnerAccountID: @20, NSFileGroupOwnerAccountName: @"staff",
                                 NSFileHFSCreatorCode: @1234, NSFileHFSTypeCode: @0x54455854, NSFileAppendOnly: @YES,
                                 NSFileOwnerAccountID: @501};
    say(@"file attributes: %d %@ %@ %u %u %d %@", attributes.fileExtensionHidden, attributes.fileGroupOwnerAccountID,
        attributes.fileGroupOwnerAccountName, (unsigned)attributes.fileHFSCreatorCode, (unsigned)attributes.fileHFSTypeCode,
        attributes.fileIsAppendOnly, attributes.fileOwnerAccountID);
    say(@"no file attributes: %d %d %u", @{}.fileExtensionHidden, @{}.fileOwnerAccountID == nil, (unsigned)@{}.fileHFSTypeCode);
    NSDictionary *scores = @{@"ann": @3, @"bob": @1, @"cy": @2};
    say(@"keysSortedByValueWithOptions: %@", J([scores keysSortedByValueWithOptions:NSSortStable usingComparator:^NSComparisonResult(id a, id b) {
        return [a compare:b];
    }]));
    __unsafe_unretained id values[3], keys[3];
    [scores getObjects:values andKeys:keys count:3];
    NSMutableArray *pairs = [NSMutableArray array];
    for (int i = 0; i < 3; i++) [pairs addObject:[NSString stringWithFormat:@"%@=%@", keys[i], values[i]]];
    say(@"getObjects:andKeys:count: %@", J([pairs sortedArrayUsingSelector:@selector(compare:)]));
    __block NSInteger sum = 0;
    [scores enumerateKeysAndObjectsWithOptions:NSEnumerationReverse usingBlock:^(id key, id value, BOOL *stop) { sum += [value integerValue]; }];
    say(@"enumerateKeysAndObjectsWithOptions: %ld", (long)sum);
    say(@"dictionary valueForKey: %@ @count %@", [scores valueForKey:@"bob"], [scores valueForKey:@"@count"]);
    id keySet = [NSDictionary sharedKeySetForKeys:@[@"a", @"b"]];
    NSMutableDictionary *sharing = [NSMutableDictionary dictionaryWithSharedKeySet:keySet];
    sharing[@"b"] = @2;
    sharing[@"a"] = @1;
    sharing[@"z"] = @26;
    say(@"dictionaryWithSharedKeySet: %lu %@ %@", (unsigned long)sharing.count, sharing[@"a"], sharing[@"z"]);
    [sharing setValue:nil forKey:@"z"];
    [sharing setValue:@3 forKey:@"c"];
    say(@"setValue:forKey: %@", J([sharing.allKeys sortedArrayUsingSelector:@selector(compare:)]));
}

static void indexSets(void) {
    NSIndexSet *ten = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 10)];
    BOOL (^even)(NSUInteger, BOOL *) = ^BOOL(NSUInteger index, BOOL *stop) { return index % 2 == 0; };
    say(@"indexesInRange: %@ reverse first %lu", I([ten indexesInRange:NSMakeRange(2, 5) options:NSEnumerationReverse passingTest:even]),
        (unsigned long)[ten indexInRange:NSMakeRange(2, 5) options:NSEnumerationReverse passingTest:even]);
    say(@"indexesWithOptions: %@ indexWithOptions %lu", I([ten indexesWithOptions:0 passingTest:^BOOL(NSUInteger index, BOOL *stop) {
        return index > 7;
    }]), (unsigned long)[ten indexWithOptions:NSEnumerationReverse passingTest:even]);
    NSMutableIndexSet *two = [NSMutableIndexSet indexSetWithIndexesInRange:NSMakeRange(1, 3)];
    [two addIndexesInRange:NSMakeRange(6, 3)];
    NSMutableArray *ranges = [NSMutableArray array];
    [two enumerateRangesInRange:NSMakeRange(2, 5) options:0 usingBlock:^(NSRange range, BOOL *stop) {
        [ranges addObject:NSStringFromRange(range)];
    }];
    [two enumerateRangesInRange:NSMakeRange(2, 5) options:NSEnumerationReverse usingBlock:^(NSRange range, BOOL *stop) {
        [ranges addObject:NSStringFromRange(range)];
    }];
    say(@"enumerateRangesInRange: %@", [ranges componentsJoinedByString:@" "]);
    NSMutableArray *indexes = [NSMutableArray array];
    [two enumerateIndexesInRange:NSMakeRange(2, 5) options:NSEnumerationReverse usingBlock:^(NSUInteger index, BOOL *stop) {
        [indexes addObject:@(index)];
        *stop = indexes.count == 2;
    }];
    say(@"enumerateIndexesInRange: %@", J(indexes));
}

static void pointerFunctions(void) {
    NSPointerFunctions *objects = [NSPointerFunctions pointerFunctionsWithOptions:NSPointerFunctionsStrongMemory];
    say(@"object functions: hash %d equal %d size %d description %d relinquish %d acquire %d", objects.hashFunction != NULL,
        objects.isEqualFunction != NULL, objects.sizeFunction != NULL, objects.descriptionFunction != NULL,
        objects.relinquishFunction != NULL, objects.acquireFunction != NULL);
    NSPointerFunctions *opaque = [[NSPointerFunctions alloc] initWithOptions:NSPointerFunctionsOpaqueMemory | NSPointerFunctionsOpaquePersonality];
    say(@"opaque functions: hash %d equal %d size %d description %d relinquish %d acquire %d", opaque.hashFunction != NULL,
        opaque.isEqualFunction != NULL, opaque.sizeFunction != NULL, opaque.descriptionFunction != NULL,
        opaque.relinquishFunction != NULL, opaque.acquireFunction != NULL);
    NSString *abc = [@"ab" stringByAppendingString:@"c"];
    say(@"object calls: hash %d equal %d description %@", objects.hashFunction((__bridge void *)abc, NULL) == abc.hash,
        objects.isEqualFunction((__bridge void *)abc, (__bridge void *)@"abc", NULL), objects.descriptionFunction((__bridge void *)abc));
    NSPointerFunctions *integers = [NSPointerFunctions pointerFunctionsWithOptions:NSPointerFunctionsOpaqueMemory | NSPointerFunctionsIntegerPersonality];
    say(@"integer calls: hash %lu equal %d %d", (unsigned long)integers.hashFunction((void *)7, NULL),
        integers.isEqualFunction((void *)7, (void *)7, NULL), integers.isEqualFunction((void *)7, (void *)8, NULL));
    NSPointerFunctions *weak = [NSPointerFunctions pointerFunctionsWithOptions:NSPointerFunctionsWeakMemory];
    say(@"barriers: %d %d weak %d %d", objects.usesStrongWriteBarrier, objects.usesWeakReadAndWriteBarriers,
        weak.usesStrongWriteBarrier, weak.usesWeakReadAndWriteBarriers);
    NSPointerFunctions *copy = [objects copy];
    copy.usesStrongWriteBarrier = YES;
    copy.sizeFunction = NULL;
    say(@"copy: %d %d original %d", copy.usesStrongWriteBarrier, copy.hashFunction != NULL, objects.usesStrongWriteBarrier);

    NSHashTable *table = [[NSHashTable alloc] initWithPointerFunctions:weak capacity:0];
    NSObject *member = [NSObject new];
    [table addObject:member];
    say(@"hash table: %lu weak %d", (unsigned long)table.count, table.pointerFunctions.usesWeakReadAndWriteBarriers);
    NSPointerFunctions *cStrings = [NSPointerFunctions pointerFunctionsWithOptions:NSPointerFunctionsOpaqueMemory | NSPointerFunctionsCStringPersonality];
    NSMapTable *map = [[NSMapTable alloc] initWithKeyPointerFunctions:cStrings valuePointerFunctions:objects capacity:0];
    [map setObject:@"value" forKey:(__bridge id)(void *)"key"];
    char key[4] = "key";
    say(@"map table: %@ %lu key functions %d value functions %d", [map objectForKey:(__bridge id)(void *)key], (unsigned long)map.count,
        map.keyPointerFunctions != nil, map.valuePointerFunctions.relinquishFunction != NULL);
    NSPointerArray *pointers = [NSPointerArray pointerArrayWithPointerFunctions:integers];
    [pointers addPointer:(void *)5];
    [pointers addPointer:NULL];
    NSPointerArray *more = [[NSPointerArray alloc] initWithPointerFunctions:integers];
    [more addPointer:(void *)6];
    say(@"pointer array: %lu %p %p functions %d", (unsigned long)pointers.count, [pointers pointerAtIndex:0], [more pointerAtIndex:0],
        pointers.pointerFunctions != nil);
}

static void sortDescriptors(void) {
    NSComparator compare = ^NSComparisonResult(id a, id b) { return [a compare:b]; };
    NSSortDescriptor *longest = [NSSortDescriptor sortDescriptorWithKey:@"length" ascending:NO comparator:compare];
    say(@"comparator descriptor: key %@ ascending %d selector %d comparator %d", longest.key, longest.ascending,
        longest.selector == NULL, longest.comparator != nil);
    say(@"sorted: %@ reversed: %@", J([@[@"ccc", @"a", @"bb"] sortedArrayUsingDescriptors:@[longest]]),
        J([@[@"ccc", @"a", @"bb"] sortedArrayUsingDescriptors:@[longest.reversedSortDescriptor]]));
    NSSortDescriptor *made = [[NSSortDescriptor alloc] initWithKey:nil ascending:YES comparator:compare];
    [made allowEvaluation];
    say(@"initWithKey:ascending:comparator: %ld %ld", (long)[made compareObject:@1 toObject:@2], (long)[made compareObject:@"b" toObject:@"a"]);
    say(@"selector descriptor comparator %d", [NSSortDescriptor sortDescriptorWithKey:@"x" ascending:YES].comparator == nil);
}

static void predicates(void) {
    NSComparisonPredicate *custom = (NSComparisonPredicate *)[NSComparisonPredicate
        predicateWithLeftExpression:[NSExpression expressionForKeyPath:@"name"]
                    rightExpression:[NSExpression expressionForConstantValue:@"x"]
                     customSelector:@selector(isEqualToString:)];
    say(@"custom: %@ type %lu selector %@ %d %d", custom, (unsigned long)custom.predicateOperatorType, NSStringFromSelector(custom.customSelector),
        [custom evaluateWithObject:@{@"name": @"x"}], [custom evaluateWithObject:@{@"name": @"y"}]);
    NSComparisonPredicate *initialized = [[NSComparisonPredicate alloc] initWithLeftExpression:[NSExpression expressionForKeyPath:@"name"]
        rightExpression:[NSExpression expressionForConstantValue:@"x"] customSelector:@selector(hasPrefix:)];
    say(@"initWithLeftExpression:customSelector: %@ %d", initialized, [initialized evaluateWithObject:@{@"name": @"xyz"}]);
    NSComparisonPredicate *any = [[NSComparisonPredicate alloc] initWithLeftExpression:[NSExpression expressionForKeyPath:@"a"]
        rightExpression:[NSExpression expressionForConstantValue:@"b"] modifier:NSAnyPredicateModifier
        type:NSBeginsWithPredicateOperatorType options:NSCaseInsensitivePredicateOption];
    say(@"initWithLeftExpression:modifier: %@ %d %d", any, [any evaluateWithObject:@{@"a": @[@"x", @"Bob"]}],
        [any evaluateWithObject:@{@"a": @[@"x"]}]);
    NSCompoundPredicate *either = [[NSCompoundPredicate alloc] initWithType:NSOrPredicateType
        subpredicates:@[[NSPredicate predicateWithValue:NO], [NSPredicate predicateWithFormat:@"a == 1"]]];
    [either allowEvaluation];
    say(@"initWithType:subpredicates: %@ type %lu %d", either, (unsigned long)either.compoundPredicateType, [either evaluateWithObject:@{@"a": @1}]);
}

static void expressions(void) {
    NSExpression *anyKey = [NSExpression expressionForAnyKey];
    say(@"anyKey: %@ type %lu", anyKey, (unsigned long)anyKey.expressionType);
    NSExpression *block = [NSExpression expressionForBlock:^id(id object, NSArray *arguments, NSMutableDictionary *context) {
        return @([object integerValue] + [arguments[0] integerValue] + (context ? 100 : 0));
    } arguments:@[[NSExpression expressionForConstantValue:@10]]];
    say(@"block: type %lu arguments %lu block %d value %@ with context %@", (unsigned long)block.expressionType,
        (unsigned long)block.arguments.count, block.expressionBlock != nil, [block expressionValueWithObject:@5 context:nil],
        [block expressionValueWithObject:@5 context:[NSMutableDictionary dictionary]]);
    NSExpression *left = [NSExpression expressionForConstantValue:@[@1, @2, @3]];
    NSExpression *right = [NSExpression expressionForConstantValue:@[@2, @3, @4]];
    for (NSExpression *operation in @[[NSExpression expressionForUnionSet:left with:right], [NSExpression expressionForIntersectSet:left with:right],
                                      [NSExpression expressionForMinusSet:left with:right]]) {
        id value = [operation expressionValueWithObject:nil context:nil];
        say(@"%@: type %lu left %@ right %@ value %@ set %d", operation, (unsigned long)operation.expressionType, operation.leftExpression,
            operation.rightExpression, J(value), [value isKindOfClass:[NSSet class]]);
    }
    NSExpression *keyed = [NSExpression expressionForUnionSet:[NSExpression expressionForKeyPath:@"s"] with:[NSExpression expressionForKeyPath:@"items"]];
    say(@"keyed union: %@", J([keyed expressionValueWithObject:@{@"s": [NSSet setWithObject:@9], @"items": @[@8, @9]} context:nil]));
    NSExpression *subquery = [NSExpression expressionForSubquery:[NSExpression expressionForKeyPath:@"items"] usingIteratorVariable:@"x"
                                                       predicate:[NSPredicate predicateWithFormat:@"$x > 1"]];
    say(@"subquery: %@ type %lu variable %@ collection %@ predicate %@ value %@", subquery, (unsigned long)subquery.expressionType,
        subquery.variable, subquery.collection, subquery.predicate, J([subquery expressionValueWithObject:@{@"items": @[@1, @2, @3]} context:nil]));
    NSExpression *typed = [[NSExpression alloc] initWithExpressionType:NSKeyPathExpressionType];
    NSExpression *evaluated = [[NSExpression alloc] initWithExpressionType:NSEvaluatedObjectExpressionType];
    [evaluated allowEvaluation];
    say(@"initWithExpressionType: %lu %lu", (unsigned long)typed.expressionType, (unsigned long)evaluated.expressionType);
}

static void differences(void) {
    NSMutableIndexSet *inserts = [NSMutableIndexSet indexSetWithIndex:0];
    [inserts addIndex:3];
    NSOrderedCollectionDifference *difference = [[NSOrderedCollectionDifference alloc] initWithInsertIndexes:inserts
        insertedObjects:@[@"a", @"d"] removeIndexes:[NSIndexSet indexSetWithIndex:1] removedObjects:@[@"x"]];
    NSMutableArray *parts = [NSMutableArray array];
    for (NSOrderedCollectionChange *change in difference.insertions) [parts addObject:[NSString stringWithFormat:@"+%@@%lu", change.object, (unsigned long)change.index]];
    for (NSOrderedCollectionChange *change in difference.removals) [parts addObject:[NSString stringWithFormat:@"-%@@%lu", change.object, (unsigned long)change.index]];
    say(@"difference %@ changes=%d", [parts componentsJoinedByString:@" "], difference.hasChanges);
    NSOrderedCollectionDifference *shifted = [difference differenceByTransformingChangesWithBlock:^NSOrderedCollectionChange *(NSOrderedCollectionChange *change) {
        return [NSOrderedCollectionChange changeWithObject:[change.object uppercaseString] type:change.changeType index:change.index + 10];
    }];
    [parts removeAllObjects];
    for (NSOrderedCollectionChange *change in shifted.insertions) [parts addObject:[NSString stringWithFormat:@"+%@@%lu", change.object, (unsigned long)change.index]];
    for (NSOrderedCollectionChange *change in shifted.removals) [parts addObject:[NSString stringWithFormat:@"-%@@%lu", change.object, (unsigned long)change.index]];
    say(@"transformed %@", [parts componentsJoinedByString:@" "]);
    NSArray *applied = [@[@"w", @"x", @"y"] arrayByApplyingDifference:difference];
    say(@"applied %@", [applied componentsJoinedByString:@","]);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        arrays();
        mutableArrays();
        orderedSets();
        mutableOrderedSets();
        sets();
        dictionaries();
        indexSets();
        pointerFunctions();
        sortDescriptors();
        predicates();
        expressions();
        differences();
    }
    return 0;
}
