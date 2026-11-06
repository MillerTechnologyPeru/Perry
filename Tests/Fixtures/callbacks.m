// Darwin functions that Linux's libraries call back: qsort's and bsearch's
// comparators, a thread's start routine, a thread-specific value's
// destructor, pthread_once's initializer, atexit's handler, dispatch's
// blocks and functions, and the deallocations its autorelease pools drain.
// Darwin's armv7 code may change r9, which Linux's keeps across calls, so
// each of them changes it. It prints the same on any Darwin, so a Mac records
// what it prints.
#include "darwin.h"

// Where Darwin's code may use r9 as scratch, as Apple's compiler does.
#if defined(__arm__)
#define SCRATCH_R9() __asm__ volatile("mov r9, #0x5a" ::: "r9")
#else
#define SCRATCH_R9() ((void)0)
#endif

#if __LP64__
#define ONCE_OPAQUE 8
#else
#define ONCE_OPAQUE 4
#endif
typedef struct { long sig; char opaque[ONCE_OPAQUE]; } pthread_once_t;
typedef struct _opaque_pthread_t *pthread_t;
typedef unsigned long pthread_key_t;
#define PTHREAD_ONCE_INIT {0x30B1BCBA, {0}}
int pthread_create(pthread_t *, const void *, void *(*)(void *), void *);
int pthread_join(pthread_t, void **);
int pthread_once(pthread_once_t *, void (*)(void));
int pthread_key_create(pthread_key_t *, void (*)(void *));
int pthread_setspecific(pthread_key_t, const void *);

void qsort(void *, size_t, size_t, int (*)(const void *, const void *));
void *bsearch(const void *, const void *, size_t, size_t, int (*)(const void *, const void *));
int atexit(void (*)(void));

typedef struct dispatch_queue_s *dispatch_queue_t;
typedef struct dispatch_queue_attr_s *dispatch_queue_attr_t;
typedef struct dispatch_group_s *dispatch_group_t;
typedef unsigned long long dispatch_time_t;
#define DISPATCH_TIME_FOREVER (~0ull)
dispatch_queue_t dispatch_queue_create(const char *, dispatch_queue_attr_t);
dispatch_queue_t dispatch_get_global_queue(long, unsigned long);
dispatch_queue_attr_t dispatch_queue_attr_make_with_autorelease_frequency(dispatch_queue_attr_t, unsigned long);
void dispatch_sync(dispatch_queue_t, void (^)(void));
void dispatch_sync_f(dispatch_queue_t, void *, void (*)(void *));
void dispatch_async(dispatch_queue_t, void (^)(void));
void dispatch_async_f(dispatch_queue_t, void *, void (*)(void *));
void dispatch_barrier_sync_f(dispatch_queue_t, void *, void (*)(void *));
void dispatch_apply(size_t, dispatch_queue_t, void (^)(size_t));
void dispatch_apply_f(size_t, dispatch_queue_t, void *, void (*)(void *, size_t));
dispatch_group_t dispatch_group_create(void);
void dispatch_group_async(dispatch_group_t, dispatch_queue_t, void (^)(void));
void dispatch_group_async_f(dispatch_group_t, dispatch_queue_t, void *, void (*)(void *));
long dispatch_group_wait(dispatch_group_t, dispatch_time_t);

typedef struct objc_object *id;
__attribute__((objc_root_class))
@interface NSObject { id isa; }
+ (instancetype)new;
@end

static int deallocs;

@interface Scratch : NSObject
@end

@implementation Scratch
- (void)dealloc {
    SCRATCH_R9();
    __atomic_fetch_add(&deallocs, 1, __ATOMIC_SEQ_CST);
}
@end

static int compare(const void *a, const void *b) {
    SCRATCH_R9();
    int x = *(const int *)a, y = *(const int *)b;
    return x < y ? -1 : x > y;
}

static void *start(void *argument) {
    SCRATCH_R9();
    return (char *)argument + 1;
}

static int destroyed;
static void destroy(void *value) {
    SCRATCH_R9();
    destroyed += *(int *)value;
}

static pthread_key_t specific;
static void *keep(void *value) {
    pthread_setspecific(specific, value);
    return 0;
}

static int initialized;
static void initialize(void) {
    SCRATCH_R9();
    initialized++;
}

static void finish(void) {
    SCRATCH_R9();
    printf("atexit\n");
}

static int work;
static void count(void *context) {
    SCRATCH_R9();
    __atomic_fetch_add(&work, *(int *)context, __ATOMIC_SEQ_CST);
}

static void countIndex(void *context, size_t index) {
    SCRATCH_R9();
    __atomic_fetch_add((int *)context, (int)index, __ATOMIC_SEQ_CST);
}

int main(void) {
    int numbers[200];
    // A shuffle without division, which armv7 has no instruction for.
    for (int i = 0, n = 0; i < 200; i++, n = n + 119 < 200 ? n + 119 : n + 119 - 200)
        numbers[i] = n;
    qsort(numbers, 200, sizeof(int), compare);
    int sorted = 1;
    for (int i = 0; i < 200; i++)
        sorted &= numbers[i] == i;
    int key = 123;
    int *found = bsearch(&key, numbers, 200, sizeof(int), compare);
    printf("qsort %d bsearch %d\n", sorted, found ? (int)(found - numbers) : -1);

    char text[] = "thread";
    pthread_t threads[4];
    for (int i = 0; i < 4; i++)
        pthread_create(&threads[i], NULL, start, text + i);
    for (int i = 0; i < 4; i++) {
        void *result;
        pthread_join(threads[i], &result);
        printf(i ? " %s" : "%s", (char *)result);
    }
    printf("\n");

    pthread_key_create(&specific, destroy);
    static int values[4] = { 1, 2, 3, 4 };
    for (int i = 0; i < 4; i++) {
        pthread_t thread;
        pthread_create(&thread, NULL, keep, &values[i]);
        pthread_join(thread, NULL);
    }
    printf("destroyed %d\n", destroyed);

    static pthread_once_t once = PTHREAD_ONCE_INIT;
    pthread_once(&once, initialize);
    pthread_once(&once, initialize);
    printf("once %d\n", initialized);
    atexit(finish);

    dispatch_queue_t serial = dispatch_queue_create("serial", NULL);
    dispatch_queue_t global = dispatch_get_global_queue(0, 0);
    int one = 1, ten = 10, hundred = 100;
    dispatch_sync_f(serial, &one, count);
    dispatch_barrier_sync_f(serial, &ten, count);
    dispatch_sync(serial, ^{
        SCRATCH_R9();
        work += 1000;
    });
    for (int i = 0; i < 50; i++)
        dispatch_async_f(serial, &hundred, count);
    for (int i = 0; i < 50; i++)
        dispatch_async(global, ^{
            SCRATCH_R9();
            __atomic_fetch_add(&work, 10000, __ATOMIC_SEQ_CST);
        });
    dispatch_group_t group = dispatch_group_create();
    for (int i = 0; i < 20; i++) {
        dispatch_group_async(group, global, ^{
            SCRATCH_R9();
            __atomic_fetch_add(&work, 1000000, __ATOMIC_SEQ_CST);
        });
        dispatch_group_async_f(group, serial, &one, count);
    }
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    __block int indexes = 0;
    dispatch_apply(10, global, ^(size_t index) {
        SCRATCH_R9();
        __atomic_fetch_add(&indexes, (int)index, __ATOMIC_SEQ_CST);
    });
    dispatch_apply_f(10, global, &indexes, countIndex);
    dispatch_sync(serial, ^{});
    // The global queue's 50 blocks may still be running: wait for them.
    while (__atomic_load_n(&work, __ATOMIC_SEQ_CST) != 1 + 10 + 1000 + 5000 + 500000 + 20000000 + 20)
        ;
    printf("work %d indexes %d\n", work, indexes);

    // Objects a work item autoreleases are released as it finishes, by
    // dispatch, whose frames are below.
    dispatch_queue_t pooled = dispatch_queue_create("pooled", dispatch_queue_attr_make_with_autorelease_frequency(NULL, 1));
    for (int i = 0; i < 10; i++)
        dispatch_async(pooled, ^{
            __autoreleasing Scratch *scratch = [Scratch new];
            (void)scratch;
            SCRATCH_R9();
        });
    dispatch_sync(pooled, ^{});
    printf("deallocs %d\n", deallocs);
    return 0;
}
