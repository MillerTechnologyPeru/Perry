#import <CloudKit/CloudKit.h>
#import <Foundation/Foundation.h>

// Asks CloudKit what it can do: the account status, then a fetch of one
// record and a query, as an app does at launch, and prints each answer.
// Without an iCloud account these report no account and not authenticated.

static void await(void (^start)(dispatch_semaphore_t done)) {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    start(done);
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC));
}

int main(int argc, char **argv) {
    @autoreleasepool {
        CKContainer *container = [CKContainer defaultContainer];
        await(^(dispatch_semaphore_t done) {
            [container accountStatusWithCompletionHandler:^(CKAccountStatus status, NSError *error) {
                printf("account status %ld, error %s\n", (long)status, error ? error.domain.UTF8String : "none");
                dispatch_semaphore_signal(done);
            }];
        });
        CKDatabase *database = [container publicCloudDatabase];
        await(^(dispatch_semaphore_t done) {
            CKRecordID *identifier = [[CKRecordID alloc] initWithRecordName:@"probe"];
            [database fetchRecordWithID:identifier completionHandler:^(CKRecord *record, NSError *error) {
                printf("fetch: record %s, error %s %ld\n", record ? "found" : "none",
                       error ? error.domain.UTF8String : "none", (long)error.code);
                dispatch_semaphore_signal(done);
            }];
        });
        await(^(dispatch_semaphore_t done) {
            CKQuery *query = [[CKQuery alloc] initWithRecordType:@"Probe" predicate:[NSPredicate predicateWithValue:YES]];
            [database performQuery:query inZoneWithID:nil completionHandler:^(NSArray<CKRecord *> *records, NSError *error) {
                printf("query: %lu records, error %s %ld\n", (unsigned long)records.count,
                       error ? error.domain.UTF8String : "none", (long)error.code);
                dispatch_semaphore_signal(done);
            }];
        });
    }
    return 0;
}
