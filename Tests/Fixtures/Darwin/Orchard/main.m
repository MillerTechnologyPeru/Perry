// CoreFoundation's other collections: bags, binary heaps, bit vectors and
// trees, built on a Mac with Xcode. A bag's order is its hash's, so its
// values are printed sorted.
#import <Foundation/Foundation.h>

static void print(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

static NSString *joined(NSArray *values) { return [values componentsJoinedByString:@","]; }

static NSArray *sortedBag(CFBagRef bag) {
    CFIndex count = CFBagGetCount(bag);
    const void **values = malloc(sizeof(void *) * (count ? count : 1));
    CFBagGetValues(bag, values);
    NSMutableArray *strings = [NSMutableArray array];
    for (CFIndex i = 0; i < count; i++) [strings addObject:(__bridge NSString *)values[i]];
    free(values);
    return [strings sortedArrayUsingSelector:@selector(compare:)];
}

static void countApplied(const void *value, void *context) { *(int *)context += 1; }

static void bags(void) {
    CFStringRef words[] = {CFSTR("pear"), CFSTR("apple"), CFSTR("pear"), CFSTR("fig"), CFSTR("pear")};
    CFBagRef bag = CFBagCreate(NULL, (const void **)words, 5, &kCFTypeBagCallBacks);
    print([NSString stringWithFormat:@"bag type %d count %ld pears %ld figs %ld kiwis %ld contains %d %d",
           CFGetTypeID(bag) == CFBagGetTypeID(), (long)CFBagGetCount(bag), (long)CFBagGetCountOfValue(bag, CFSTR("pear")),
           (long)CFBagGetCountOfValue(bag, CFSTR("fig")), (long)CFBagGetCountOfValue(bag, CFSTR("kiwi")),
           CFBagContainsValue(bag, CFSTR("apple")), CFBagContainsValue(bag, CFSTR("kiwi"))]);
    print([NSString stringWithFormat:@"bag values %@", joined(sortedBag(bag))]);

    CFMutableBagRef mutable = CFBagCreateMutableCopy(NULL, 0, bag);
    CFBagAddValue(mutable, CFSTR("kiwi"));
    CFBagRemoveValue(mutable, CFSTR("pear"));
    CFBagRemoveValue(mutable, CFSTR("fig"));
    CFBagRemoveValue(mutable, CFSTR("plum"));
    NSString *found = nil;
    const void *value = NULL;
    Boolean present = CFBagGetValueIfPresent(mutable, CFSTR("kiwi"), &value);
    found = (__bridge NSString *)value;
    int applied = 0;
    CFBagApplyFunction(mutable, countApplied, &applied);
    print([NSString stringWithFormat:@"mutable %ld %@ present %d %@ applied %d equal %d", (long)CFBagGetCount(mutable),
           joined(sortedBag(mutable)), present, found, applied, CFEqual(bag, mutable)]);

    CFBagRef copy = CFBagCreateCopy(NULL, bag);
    print([NSString stringWithFormat:@"copy equal %d", CFEqual(bag, copy)]);
    CFBagSetValue(mutable, CFSTR("grape"));
    CFBagReplaceValue(mutable, CFSTR("melon"));
    CFBagRemoveAllValues(mutable);
    print([NSString stringWithFormat:@"emptied %ld", (long)CFBagGetCount(mutable)]);

    // Without callbacks: pointers, compared as pointers.
    CFMutableBagRef numbers = CFBagCreateMutable(NULL, 0, NULL);
    for (intptr_t n = 1; n <= 3; n++) {
        for (intptr_t times = 0; times < n; times++) CFBagAddValue(numbers, (const void *)n);
    }
    print([NSString stringWithFormat:@"numbers %ld of 3: %ld", (long)CFBagGetCount(numbers),
           (long)CFBagGetCountOfValue(numbers, (const void *)3)]);
}

static CFComparisonResult compareIntegers(const void *a, const void *b, void *info) {
    intptr_t x = (intptr_t)a, y = (intptr_t)b;
    // Info is the direction: 1 ascending, -1 descending.
    intptr_t direction = (intptr_t)info;
    if (x == y) return kCFCompareEqualTo;
    return (x < y) == (direction > 0) ? kCFCompareLessThan : kCFCompareGreaterThan;
}

static void collect(const void *value, void *context) {
    [(__bridge NSMutableArray *)context addObject:@((intptr_t)value)];
}

static void heaps(void) {
    CFBinaryHeapRef strings = CFBinaryHeapCreate(NULL, 0, &kCFStringBinaryHeapCallBacks, NULL);
    for (NSString *word in @[@"melon", @"apple", @"kiwi", @"banana", @"apple"]) {
        CFBinaryHeapAddValue(strings, (__bridge CFStringRef)word);
    }
    CFIndex count = CFBinaryHeapGetCount(strings);
    const void *values[8];
    CFBinaryHeapGetValues(strings, values);
    NSMutableArray *ordered = [NSMutableArray array];
    for (CFIndex i = 0; i < count; i++) [ordered addObject:(__bridge NSString *)values[i]];
    print([NSString stringWithFormat:@"heap type %d count %ld values %@ minimum %@ apples %ld kiwi %d fig %d",
           CFGetTypeID(strings) == CFBinaryHeapGetTypeID(), (long)count, joined(ordered),
           (__bridge NSString *)CFBinaryHeapGetMinimum(strings), (long)CFBinaryHeapGetCountOfValue(strings, CFSTR("apple")),
           CFBinaryHeapContainsValue(strings, CFSTR("kiwi")), CFBinaryHeapContainsValue(strings, CFSTR("fig"))]);

    NSMutableArray *popped = [NSMutableArray array];
    const void *minimum = NULL;
    while (CFBinaryHeapGetMinimumIfPresent(strings, &minimum)) {
        [popped addObject:(__bridge NSString *)minimum];
        CFBinaryHeapRemoveMinimumValue(strings);
    }
    print([NSString stringWithFormat:@"popped %@ left %ld", joined(popped), (long)CFBinaryHeapGetCount(strings)]);

    CFBinaryHeapCallBacks integers = {0, NULL, NULL, NULL, compareIntegers};
    CFBinaryHeapCompareContext descending = {0, (void *)-1, NULL, NULL, NULL};
    CFBinaryHeapRef heap = CFBinaryHeapCreate(NULL, 0, &integers, &descending);
    for (intptr_t n = 1; n <= 9; n += 2) CFBinaryHeapAddValue(heap, (const void *)n);
    CFBinaryHeapAddValue(heap, (const void *)4);
    NSMutableArray *applied = [NSMutableArray array];
    CFBinaryHeapApplyFunction(heap, collect, (__bridge void *)applied);
    CFBinaryHeapRef copy = CFBinaryHeapCreateCopy(NULL, 0, heap);
    CFBinaryHeapRemoveMinimumValue(copy);
    print([NSString stringWithFormat:@"descending %@ copy minimum %ld", joined(applied), (long)(intptr_t)CFBinaryHeapGetMinimum(copy)]);
    CFBinaryHeapRemoveAllValues(heap);
    print([NSString stringWithFormat:@"cleared %ld present %d", (long)CFBinaryHeapGetCount(heap),
           CFBinaryHeapGetMinimumIfPresent(heap, &minimum)]);
}

static NSString *bitString(CFBitVectorRef vector) {
    NSMutableString *string = [NSMutableString string];
    for (CFIndex i = 0; i < CFBitVectorGetCount(vector); i++) [string appendString:CFBitVectorGetBitAtIndex(vector, i) ? @"1" : @"0"];
    return string;
}

static void bitVectors(void) {
    UInt8 bytes[] = {0xA5, 0x0F};
    CFBitVectorRef vector = CFBitVectorCreate(NULL, bytes, 12);
    print([NSString stringWithFormat:@"bits type %d %@ count %ld ones %ld zeros in 4..8 %ld", CFGetTypeID(vector) == CFBitVectorGetTypeID(),
           bitString(vector), (long)CFBitVectorGetCount(vector), (long)CFBitVectorGetCountOfBit(vector, CFRangeMake(0, 12), 1),
           (long)CFBitVectorGetCountOfBit(vector, CFRangeMake(4, 4), 0)]);
    print([NSString stringWithFormat:@"first one %ld last one %ld first zero after 8 %ld in 0..4 %ld contains %d %d",
           (long)CFBitVectorGetFirstIndexOfBit(vector, CFRangeMake(0, 12), 1),
           (long)CFBitVectorGetLastIndexOfBit(vector, CFRangeMake(0, 12), 1),
           (long)CFBitVectorGetFirstIndexOfBit(vector, CFRangeMake(8, 4), 0),
           (long)CFBitVectorGetFirstIndexOfBit(vector, CFRangeMake(0, 4), 0) ,
           CFBitVectorContainsBit(vector, CFRangeMake(8, 4), 1), CFBitVectorContainsBit(vector, CFRangeMake(4, 4), 1)]);
    // Ranges that start on a byte, or stay in one: Darwin's packing of
    // others that cross a byte isn't consistent.
    UInt8 out[3] = {0xFF, 0xFF, 0xFF};
    CFBitVectorGetBits(vector, CFRangeMake(0, 12), out);
    UInt8 part[2] = {0xFF, 0xFF};
    CFBitVectorGetBits(vector, CFRangeMake(3, 5), part);
    print([NSString stringWithFormat:@"bytes of 0..12 %02X %02X %02X of 3..8 %02X %02X", out[0], out[1], out[2], part[0], part[1]]);

    CFMutableBitVectorRef mutable = CFBitVectorCreateMutableCopy(NULL, 0, vector);
    CFBitVectorSetCount(mutable, 16);
    CFBitVectorFlipBitAtIndex(mutable, 0);
    CFBitVectorFlipBits(mutable, CFRangeMake(12, 4));
    CFBitVectorSetBitAtIndex(mutable, 1, 1);
    CFBitVectorSetBits(mutable, CFRangeMake(4, 3), 1);
    print([NSString stringWithFormat:@"mutable %@ equal %d copy equal %d", bitString(mutable), CFEqual(vector, mutable),
           CFEqual(vector, CFBitVectorCreateCopy(NULL, vector))]);
    CFBitVectorSetCount(mutable, 5);
    print([NSString stringWithFormat:@"shrunk %@", bitString(mutable)]);
    CFBitVectorSetAllBits(mutable, 1);
    print([NSString stringWithFormat:@"all %@", bitString(mutable)]);
    CFMutableBitVectorRef empty = CFBitVectorCreateMutable(NULL, 0);
    print([NSString stringWithFormat:@"empty %ld", (long)CFBitVectorGetCount(empty)]);
}

static NSString *name(CFTreeRef tree) {
    if (!tree) return @"-";
    CFTreeContext context;
    CFTreeGetContext(tree, &context);
    return (__bridge NSString *)context.info;
}

static CFTreeRef node(NSString *label) {
    CFTreeContext context = {0, (__bridge void *)label, CFRetain, CFRelease, CFCopyDescription};
    return CFTreeCreate(NULL, &context);
}

static NSString *children(CFTreeRef tree) {
    NSMutableArray *names = [NSMutableArray array];
    for (CFTreeRef child = CFTreeGetFirstChild(tree); child; child = CFTreeGetNextSibling(child)) [names addObject:name(child)];
    return joined(names);
}

static CFComparisonResult byName(const void *a, const void *b, void *context) {
    return (CFComparisonResult)[name((CFTreeRef)a) compare:name((CFTreeRef)b)];
}

static void addName(const void *value, void *context) { [(__bridge NSMutableArray *)context addObject:name((CFTreeRef)value)]; }

static void trees(void) {
    CFTreeRef root = node(@"root");
    CFTreeRef pear = node(@"pear"), apple = node(@"apple"), fig = node(@"fig"), seed = node(@"seed");
    CFTreeAppendChild(root, pear);
    CFTreeAppendChild(root, apple);
    CFTreePrependChild(root, fig);
    CFTreeAppendChild(apple, seed);
    print([NSString stringWithFormat:@"tree type %d children %@ count %ld second %@ parent %@ root %@ none %@",
           CFGetTypeID(root) == CFTreeGetTypeID(), children(root), (long)CFTreeGetChildCount(root),
           name(CFTreeGetChildAtIndex(root, 1)), name(CFTreeGetParent(seed)), name(CFTreeFindRoot(seed)),
           name(CFTreeGetChildAtIndex(root, 5))]);
    CFTreeRef all[4];
    CFTreeGetChildren(root, all);
    NSMutableArray *applied = [NSMutableArray array];
    CFTreeApplyFunctionToChildren(root, addName, (__bridge void *)applied);
    print([NSString stringWithFormat:@"got %@,%@,%@ applied %@ retain %ld", name(all[0]), name(all[1]), name(all[2]),
           joined(applied), (long)CFGetRetainCount(pear)]);

    CFTreeSortChildren(root, byName, NULL);
    print([NSString stringWithFormat:@"sorted %@", children(root)]);
    CFTreeRemove(apple);
    print([NSString stringWithFormat:@"removed %@ parent %@ retain %ld seed root %@", children(root), name(CFTreeGetParent(apple)),
           (long)CFGetRetainCount(apple), name(CFTreeFindRoot(seed))]);
    CFTreeInsertSibling(fig, apple);
    print([NSString stringWithFormat:@"inserted %@", children(root)]);

    CFTreeContext renamed = {0, (__bridge void *)@"orchard", CFRetain, CFRelease, CFCopyDescription};
    CFTreeSetContext(root, &renamed);
    CFTreeRemoveAllChildren(root);
    print([NSString stringWithFormat:@"renamed %@ children %ld pear parent %@", name(root), (long)CFTreeGetChildCount(root),
           name(CFTreeGetParent(pear))]);
}

int main(void) {
    @autoreleasepool {
        bags();
        heaps();
        bitVectors();
        trees();
    }
    return 0;
}
