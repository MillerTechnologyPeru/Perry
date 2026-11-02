// Core Data: a compiled model from the bundle; SQLite stores saved,
// reopened and fetched with predicates, sorting and limits; relationships
// and their inverses, cascade deletes, validation, unsaved changes in
// fetches, rollback, save notifications and a background context;
// in-memory and binary stores; and a model built in code.

#import <CoreData/CoreData.h>
#import <Foundation/Foundation.h>
#include <stdio.h>
#include <unistd.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

@class Book;

@interface Author : NSManagedObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) int64_t born;
@property (nonatomic, retain) NSSet<Book *> *books;
@end

@interface Author (CoreDataGeneratedAccessors)
- (void)addBooksObject:(Book *)value;
- (void)removeBooksObject:(Book *)value;
- (void)addBooks:(NSSet<Book *> *)values;
@end

@implementation Author
@dynamic name, born, books;
@end

static int awakened;

@interface Book : NSManagedObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic) double price;
@property (nonatomic, copy) NSDate *published;
@property (nonatomic) BOOL inPrint;
@property (nonatomic, retain) Author *author;
@end

@implementation Book
@dynamic title, price, published, inPrint, author;

- (void)awakeFromInsert {
    [super awakeFromInsert];
    awakened++;
}
@end

/// Values of a key, sorted, joined.
static NSString *list(id<NSFastEnumeration> objects, NSString *key) {
    NSMutableArray *values = [NSMutableArray array];
    for (NSManagedObject *object in objects) {
        [values addObject:[[object valueForKey:key] description] ?: @"nil"];
    }
    return [[values sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@", "];
}

/// Values of a key, in order.
static NSString *ordered(NSArray *objects, NSString *key) {
    NSMutableArray *values = [NSMutableArray array];
    for (NSManagedObject *object in objects) {
        [values addObject:[[object valueForKey:key] description] ?: @"nil"];
    }
    return [values componentsJoinedByString:@", "];
}

static NSArray *fetch(NSManagedObjectContext *context, NSString *entity, NSPredicate *predicate, NSArray *sorts) {
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:entity];
    request.predicate = predicate;
    request.sortDescriptors = sorts;
    NSError *error;
    NSArray *results = [context executeFetchRequest:request error:&error];
    if (!results) say([NSString stringWithFormat:@"fetch failed: %@ %ld", error.domain, (long)error.code]);
    return results;
}

static NSPersistentContainer *openContainer(NSString *type, NSURL *url) {
    NSPersistentContainer *container = [NSPersistentContainer persistentContainerWithName:@"Library"];
    NSPersistentStoreDescription *description = [NSPersistentStoreDescription persistentStoreDescriptionWithURL:url];
    description.type = type;
    container.persistentStoreDescriptions = @[description];
    __block int handled = 0;
    __block NSError *loadError;
    [container loadPersistentStoresWithCompletionHandler:^(NSPersistentStoreDescription *loaded, NSError *error) {
        handled++;
        loadError = error;
    }];
    NSPersistentStore *store = container.persistentStoreCoordinator.persistentStores.firstObject;
    say([NSString stringWithFormat:@"loaded %@: handler %d, error %@, stores %lu", store.type, handled,
         loadError ? @"yes" : @"nil", (unsigned long)container.persistentStoreCoordinator.persistentStores.count]);
    return container;
}

static void model(NSManagedObjectModel *model) {
    NSArray *entities = [model.entities sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]]];
    for (NSEntityDescription *entity in entities) {
        NSMutableArray *parts = [NSMutableArray array];
        for (NSString *name in [entity.attributesByName.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            NSAttributeDescription *attribute = entity.attributesByName[name];
            [parts addObject:[NSString stringWithFormat:@"%@:%lu%@%@", name, (unsigned long)attribute.attributeType,
                              attribute.optional ? @"?" : @"", attribute.defaultValue ? [@"=" stringByAppendingString:[attribute.defaultValue description]] : @""]];
        }
        for (NSString *name in [entity.relationshipsByName.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            NSRelationshipDescription *relationship = entity.relationshipsByName[name];
            [parts addObject:[NSString stringWithFormat:@"%@->%@%@ inverse %@ rule %lu", name, relationship.destinationEntity.name,
                              relationship.toMany ? @"*" : @"", relationship.inverseRelationship.name,
                              (unsigned long)relationship.deleteRule]];
        }
        say([NSString stringWithFormat:@"entity %@ (%@): %@", entity.name, entity.managedObjectClassName,
             [parts componentsJoinedByString:@"; "]]);
    }
}

int main(void) {
    @autoreleasepool {
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"shelf-%d.sqlite", getpid()]];
        NSURL *url = [NSURL fileURLWithPath:path];

        __block NSUInteger saves = 0;
        id observer = [NSNotificationCenter.defaultCenter addObserverForName:NSManagedObjectContextDidSaveNotification
                                                                      object:nil queue:nil usingBlock:^(NSNotification *note) {
            saves++;
            say([NSString stringWithFormat:@"  did save: inserted %lu, updated %lu, deleted %lu",
                 (unsigned long)[note.userInfo[NSInsertedObjectsKey] count],
                 (unsigned long)[note.userInfo[NSUpdatedObjectsKey] count],
                 (unsigned long)[note.userInfo[NSDeletedObjectsKey] count]]);
        }];

        // MARK: SQLite
        NSPersistentContainer *container = openContainer(NSSQLiteStoreType, url);
        model(container.managedObjectModel);
        NSManagedObjectContext *context = container.viewContext;

        Author *lem = [NSEntityDescription insertNewObjectForEntityForName:@"Author" inManagedObjectContext:context];
        lem.name = @"Stanisław Lem";
        lem.born = 1921;
        Author *herbert = [[Author alloc] initWithContext:context];
        herbert.name = @"Frank Herbert";
        herbert.born = 1920;
        NSArray *catalog = @[@[@"Solaris", @12.5, lem], @[@"The Cyberiad", @9.99, lem], @[@"Dune", @15.0, herbert],
                             @[@"Children of Dune", @11.25, herbert]];
        for (NSArray *entry in catalog) {
            Book *book = [[Book alloc] initWithContext:context];
            book.title = entry[0];
            book.price = [entry[1] doubleValue];
            if (entry[2] == lem) book.author = lem; else [herbert addBooksObject:book];
        }
        Book *first = lem.books.anyObject;
        say([NSString stringWithFormat:@"inserted: %lu objects, awakened %d, lem has %lu books, herbert %lu, inverse %@",
             (unsigned long)context.insertedObjects.count, awakened, (unsigned long)lem.books.count,
             (unsigned long)herbert.books.count, first.author.name]);
        say([NSString stringWithFormat:@"defaults: born %lld, price %.1f, inPrint %d, published %@; temporary %d, changes %d",
             [[NSEntityDescription insertNewObjectForEntityForName:@"Author" inManagedObjectContext:context] born],
             [(Book *)[[Book alloc] initWithContext:context] price], first.inPrint, first.published,
             lem.objectID.isTemporaryID, context.hasChanges]);
        [context rollback];
        say([NSString stringWithFormat:@"after rollback: %lu inserted, changes %d", (unsigned long)context.insertedObjects.count,
             context.hasChanges]);

        // Again, and saved.
        lem = [[Author alloc] initWithContext:context];
        lem.name = @"Stanisław Lem";
        lem.born = 1921;
        herbert = [[Author alloc] initWithContext:context];
        herbert.name = @"Frank Herbert";
        herbert.born = 1920;
        for (NSArray *entry in catalog) {
            Book *book = [[Book alloc] initWithContext:context];
            book.title = entry[0];
            book.price = [entry[1] doubleValue];
            book.published = [NSDate dateWithTimeIntervalSinceReferenceDate:-1000000000];
            book.author = entry[2] == lem || entry[2] != herbert ? ([entry[0] hasSuffix:@"Dune"] ? herbert : lem) : herbert;
        }
        NSError *error;
        BOOL saved = [context save:&error];
        // Which row is p1 depends on set order, so only the URI's shape is shown.
        NSURL *uri = lem.objectID.URIRepresentation;
        NSString *row = uri.lastPathComponent;
        say([NSString stringWithFormat:@"saved %d: temporary %d, URI %@://…/%@/p%d, changes %d, saves %lu", saved,
             lem.objectID.isTemporaryID, uri.scheme, uri.pathComponents[1],
             [row hasPrefix:@"p"] && [row substringFromIndex:1].integerValue > 0, context.hasChanges, (unsigned long)saves]);

        // Fetching.
        NSSortDescriptor *byTitle = [NSSortDescriptor sortDescriptorWithKey:@"title" ascending:YES];
        NSSortDescriptor *byPrice = [NSSortDescriptor sortDescriptorWithKey:@"price" ascending:NO];
        say([NSString stringWithFormat:@"all books: %@", ordered(fetch(context, @"Book", nil, @[byTitle]), @"title")]);
        say([NSString stringWithFormat:@"over 10, priciest first: %@",
             ordered(fetch(context, @"Book", [NSPredicate predicateWithFormat:@"price > %f", 10.0], @[byPrice]), @"title")]);
        say([NSString stringWithFormat:@"containing 'dune', any case: %@",
             ordered(fetch(context, @"Book", [NSPredicate predicateWithFormat:@"title CONTAINS[c] %@", @"dune"], @[byTitle]), @"title")]);
        say([NSString stringWithFormat:@"by lem: %@",
             ordered(fetch(context, @"Book", [NSPredicate predicateWithFormat:@"author == %@", lem], @[byTitle]), @"title")]);
        say([NSString stringWithFormat:@"titles in a set, or under 10: %@",
             ordered(fetch(context, @"Book", [NSPredicate predicateWithFormat:@"title IN %@ OR price < 10",
                                              @[@"Solaris", @"Dune"]], @[byTitle]), @"title")]);
        say([NSString stringWithFormat:@"born between: %@",
             ordered(fetch(context, @"Author", [NSPredicate predicateWithFormat:@"born BETWEEN {1919, 1920}"], nil), @"name")]);
        NSFetchRequest *page = [NSFetchRequest fetchRequestWithEntityName:@"Book"];
        page.sortDescriptors = @[byTitle];
        page.fetchOffset = 1;
        page.fetchLimit = 2;
        say([NSString stringWithFormat:@"page: %@, count %lu", ordered([context executeFetchRequest:page error:nil], @"title"),
             (unsigned long)[context countForFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Book"] error:nil]]);
        NSFetchRequest *ids = [NSFetchRequest fetchRequestWithEntityName:@"Author"];
        ids.resultType = NSManagedObjectIDResultType;
        NSArray *authorIDs = [context executeFetchRequest:ids error:nil];
        say([NSString stringWithFormat:@"IDs: %lu, first is an ID %d, object %@", (unsigned long)authorIDs.count,
             [authorIDs.firstObject isKindOfClass:NSManagedObjectID.class],
             [[context objectWithID:authorIDs.firstObject] valueForKey:@"name"] ? @"found" : @"missing"]);
        Book *again = fetch(context, @"Book", [NSPredicate predicateWithFormat:@"title == 'Dune'"], nil).firstObject;
        say([NSString stringWithFormat:@"uniqued %d, author %@, KVC price %@, published %.0f", again.author == herbert,
             again.author.name, [again valueForKey:@"price"], again.published.timeIntervalSinceReferenceDate]);

        // Updates, unsaved changes in fetches, and saving them.
        again.price = 16;
        Book *draft = [[Book alloc] initWithContext:context];
        draft.title = @"Dune Messiah";
        draft.price = 13;
        draft.author = herbert;
        say([NSString stringWithFormat:@"unsaved: updated %lu, inserted %lu, herbert's books %@, fetch sees %@",
             (unsigned long)context.updatedObjects.count, (unsigned long)context.insertedObjects.count,
             list(herbert.books, @"title"),
             ordered(fetch(context, @"Book", [NSPredicate predicateWithFormat:@"title BEGINSWITH 'Dune'"], @[byTitle]), @"title")]);
        say([NSString stringWithFormat:@"changed values of Dune: %@", [again.changedValues.allKeys componentsJoinedByString:@","]]);
        [context save:nil];

        // Validation.
        Book *untitled = [[Book alloc] initWithContext:context];
        untitled.price = 1;
        saved = [context save:&error];
        say([NSString stringWithFormat:@"untitled: saved %d, %@ %ld, key %@, '%@'", saved, error.domain, (long)error.code,
             error.userInfo[NSValidationKeyErrorKey], error.localizedDescription]);
        [[Book alloc] initWithContext:context];
        saved = [context save:&error];
        say([NSString stringWithFormat:@"two untitled: saved %d, code %ld, keys %@, '%@'", saved, (long)error.code,
             [error.userInfo.allKeys componentsJoinedByString:@","], error.localizedDescription]);
        [context rollback];

        // Deleting with cascade.
        [context deleteObject:lem];
        say([NSString stringWithFormat:@"deleted lem: deleted %lu, isDeleted %d, solaris remains in fetch %lu",
             (unsigned long)context.deletedObjects.count, lem.isDeleted,
             (unsigned long)fetch(context, @"Book", [NSPredicate predicateWithFormat:@"title == 'Solaris'"], nil).count]);
        [context save:nil];
        say([NSString stringWithFormat:@"after cascade: books %@", ordered(fetch(context, @"Book", nil, @[byTitle]), @"title")]);

        // A background context.
        NSManagedObjectContext *background = [container newBackgroundContext];
        [background performBlockAndWait:^{
            Author *le = [[Author alloc] initWithContext:background];
            le.name = @"Ursula K. Le Guin";
            le.born = 1929;
            Book *book = [[Book alloc] initWithContext:background];
            book.title = @"The Dispossessed";
            book.author = le;
            [background save:nil];
        }];
        say([NSString stringWithFormat:@"after background save: authors %@",
             list(fetch(context, @"Author", nil, nil), @"name")]);

        // Reopened.
        container = nil;
        context = nil;
        NSPersistentContainer *reopened = openContainer(NSSQLiteStoreType, url);
        NSManagedObjectContext *fresh = reopened.viewContext;
        NSArray *books = fetch(fresh, @"Book", nil, @[byTitle]);
        NSMutableArray *lines = [NSMutableArray array];
        for (Book *book in books) {
            [lines addObject:[NSString stringWithFormat:@"%@ (%@, %.2f, %d)", book.title, book.author.name, book.price, book.inPrint]];
        }
        say([NSString stringWithFormat:@"reopened: %@", [lines componentsJoinedByString:@"; "]]);
        [reopened.persistentStoreCoordinator destroyPersistentStoreAtURL:url withType:NSSQLiteStoreType options:nil error:nil];

        // MARK: In memory, and binary
        for (NSString *type in @[NSInMemoryStoreType, NSBinaryStoreType]) {
            NSURL *storeURL = [type isEqual:NSBinaryStoreType]
                ? [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
                                          [NSString stringWithFormat:@"shelf-%d.binary", getpid()]]]
                : [NSURL fileURLWithPath:@"/dev/null"];
            NSPersistentContainer *memory = openContainer(type, storeURL);
            Author *author = [[Author alloc] initWithContext:memory.viewContext];
            author.name = @"Italo Calvino";
            [memory.viewContext save:nil];
            say([NSString stringWithFormat:@"  %@ store: %@", type, list(fetch(memory.viewContext, @"Author", nil, nil), @"name")]);
            [[NSFileManager defaultManager] removeItemAtURL:storeURL error:nil];
        }

        // MARK: A model in code
        NSEntityDescription *note = [[NSEntityDescription alloc] init];
        note.name = @"Note";
        NSAttributeDescription *text = [[NSAttributeDescription alloc] init];
        text.name = @"text";
        text.attributeType = NSStringAttributeType;
        text.optional = NO;
        NSAttributeDescription *rank = [[NSAttributeDescription alloc] init];
        rank.name = @"rank";
        rank.attributeType = NSInteger32AttributeType;
        rank.defaultValue = @5;
        note.properties = @[text, rank];
        NSManagedObjectModel *built = [[NSManagedObjectModel alloc] init];
        built.entities = @[note];
        NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:built];
        [coordinator addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil options:nil error:nil];
        NSManagedObjectContext *plain = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        plain.persistentStoreCoordinator = coordinator;
        for (NSString *words in @[@"buy milk", @"call mom", @"write code"]) {
            NSManagedObject *object = [NSEntityDescription insertNewObjectForEntityForName:@"Note" inManagedObjectContext:plain];
            [object setValue:words forKey:@"text"];
            if ([words hasPrefix:@"call"]) [object setValue:@1 forKey:@"rank"];
        }
        [plain save:nil];
        NSArray *notes = fetch(plain, @"Note", [NSPredicate predicateWithFormat:@"rank >= 5"],
                               @[[NSSortDescriptor sortDescriptorWithKey:@"text" ascending:NO]]);
        say([NSString stringWithFormat:@"notes: %@, class %@, entity %@", ordered(notes, @"text"),
             NSStringFromClass([notes.firstObject class]), [notes.firstObject entity].name]);

        [NSNotificationCenter.defaultCenter removeObserver:observer];
        say([NSString stringWithFormat:@"saves %lu", (unsigned long)saves]);
    }
    return 0;
}
