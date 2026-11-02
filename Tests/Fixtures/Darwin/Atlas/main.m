// Foundation collections, built on a Mac with Xcode: dictionaries, sets,
// mutable strings and constant collection literals. Prints to stdout; where
// Foundation leaves an order undefined (set members, dictionary keys) the
// output is sorted first.
#import <Foundation/Foundation.h>

static void print(NSString *line) {
    printf("%s\n", line.UTF8String);
}

static NSArray *sorted(id<NSFastEnumeration> collection) {
    NSMutableArray *items = [NSMutableArray array];
    for (id item in collection) {
        [items addObject:item];
    }
    return [items sortedArrayUsingSelector:@selector(compare:)];
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // Literals of constants become static objects.
        NSArray *planets = @[@"Mercury", @"Venus", @"Earth"];
        NSDictionary *moons = @{@"Earth": @1, @"Mars": @2, @"Jupiter": @95};
        print([NSString stringWithFormat:@"%lu planets, %lu moons entries, Mars=%@ Pluto=%@",
               (unsigned long)planets.count, (unsigned long)moons.count, moons[@"Mars"], moons[@"Pluto"]]);
        print([sorted(moons) componentsJoinedByString:@" "]);
        print(moons.description);

        NSMutableDictionary *catalog = [NSMutableDictionary dictionary];
        catalog[@"name"] = @"Atlas";
        catalog[@"planets"] = planets;
        catalog[@"count"] = @(planets.count);
        catalog[@"note"] = @"a b";
        [catalog setObject:@"temporary" forKey:@"drop"];
        [catalog removeObjectForKey:@"drop"];
        catalog[@"count"] = @4;
        print(catalog.description);

        __block NSInteger total = 0;
        [moons enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSNumber *count, BOOL *stop) {
            total += count.integerValue;
        }];
        print([NSString stringWithFormat:@"total moons %ld", (long)total]);
        NSDictionary *pairs = [NSDictionary dictionaryWithObjectsAndKeys:@"one", @1, @"two", @2, nil];
        print([NSString stringWithFormat:@"pairs %@ %@ %lu", pairs[@1], pairs[@2], (unsigned long)pairs.count]);
        print([NSString stringWithFormat:@"equal %d", [moons isEqualToDictionary:[moons mutableCopy]]]);

        NSMutableSet *inner = [NSMutableSet setWithArray:@[@"Mercury", @"Venus", @"Earth", @"Mars"]];
        NSSet *giants = [NSSet setWithObjects:@"Jupiter", @"Saturn", @"Mars", nil];
        [inner addObject:@"Earth"];
        print([NSString stringWithFormat:@"inner %lu contains Mars %d Pluto %d",
               (unsigned long)inner.count, [inner containsObject:@"Mars"], [inner containsObject:@"Pluto"]]);
        NSMutableSet *all = [inner mutableCopy];
        [all unionSet:giants];
        [inner minusSet:giants];
        print([sorted(all) componentsJoinedByString:@","]);
        print([sorted(inner) componentsJoinedByString:@","]);
        print([NSString stringWithFormat:@"subset %d intersects %d",
               [inner isSubsetOfSet:all], [inner intersectsSet:giants]]);

        NSMutableString *text = [NSMutableString stringWithCapacity:16];
        [text appendString:@"Hello"];
        [text appendFormat:@", %@ #%d", @"world", 7];
        [text insertString:@"!" atIndex:5];
        [text deleteCharactersInRange:NSMakeRange(0, 1)];
        [text replaceCharactersInRange:NSMakeRange(0, 4) withString:@"J"];
        NSString *frozen = [text copy];
        [text setString:@"changed"];
        print([NSString stringWithFormat:@"%@ | %@ | %lu", frozen, text, (unsigned long)frozen.length]);

        NSArray *slice = [@[@1, @2, @3, @4, @5] subarrayWithRange:NSMakeRange(1, 3)];
        print([slice componentsJoinedByString:@"-"]);
        print(@[@"plain", @"two words", @"café", @[@1, @{@"k": @"v"}]].description);
    }
    return 0;
}
