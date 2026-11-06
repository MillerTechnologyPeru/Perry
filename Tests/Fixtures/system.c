// libSystem's threads, math, signals and sockets, through Darwin's types:
// pthread objects at Darwin's sizes and with its static initializers,
// libm's floating-point functions (which armv7 Darwin passes in core
// registers), a SA_SIGINFO handler reading Darwin's machine context, and a
// socket timeout in Darwin's struct timeval. It prints the same on any
// Darwin, so a Mac records what it prints.
#include "darwin.h"

#if __LP64__
#define MUTEX_OPAQUE 56
#define COND_OPAQUE 40
#define RWLOCK_OPAQUE 192
#define ONCE_OPAQUE 8
#define ATTR_OPAQUE 56
#else
#define MUTEX_OPAQUE 40
#define COND_OPAQUE 24
#define RWLOCK_OPAQUE 124
#define ONCE_OPAQUE 4
#define ATTR_OPAQUE 36
#endif

typedef struct { long sig; char opaque[MUTEX_OPAQUE]; } pthread_mutex_t;
typedef struct { long sig; char opaque[COND_OPAQUE]; } pthread_cond_t;
typedef struct { long sig; char opaque[RWLOCK_OPAQUE]; } pthread_rwlock_t;
typedef struct { long sig; char opaque[ONCE_OPAQUE]; } pthread_once_t;
typedef struct { long sig; char opaque[ATTR_OPAQUE]; } pthread_attr_t;
typedef struct _opaque_pthread_t *pthread_t;
typedef unsigned long pthread_key_t;
#define PTHREAD_MUTEX_INITIALIZER {0x32AAABA7, {0}}
#define PTHREAD_COND_INITIALIZER {0x3CB0B1BB, {0}}
#define PTHREAD_RWLOCK_INITIALIZER {0x2DA8B3B4, {0}}
#define PTHREAD_ONCE_INIT {0x30B1BCBA, {0}}

typedef long time_t;
struct timespec { time_t tv_sec; long tv_nsec; };
struct timeval { time_t tv_sec; int tv_usec; };

int pthread_create(pthread_t *, const pthread_attr_t *, void *(*)(void *), void *);
int pthread_join(pthread_t, void **);
int pthread_attr_init(pthread_attr_t *);
int pthread_attr_setstacksize(pthread_attr_t *, size_t);
int pthread_attr_destroy(pthread_attr_t *);
int pthread_mutex_lock(pthread_mutex_t *);
int pthread_mutex_unlock(pthread_mutex_t *);
int pthread_cond_wait(pthread_cond_t *, pthread_mutex_t *);
int pthread_cond_timedwait(pthread_cond_t *, pthread_mutex_t *, const struct timespec *);
int pthread_cond_broadcast(pthread_cond_t *);
int pthread_rwlock_rdlock(pthread_rwlock_t *);
int pthread_rwlock_wrlock(pthread_rwlock_t *);
int pthread_rwlock_unlock(pthread_rwlock_t *);
int pthread_once(pthread_once_t *, void (*)(void));
int pthread_key_create(pthread_key_t *, void (*)(void *));
int pthread_setspecific(pthread_key_t, const void *);
void *pthread_getspecific(pthread_key_t);
int gettimeofday(struct timeval *, void *);

double sin(double), cos(double), sqrt(double), floor(double), exp(double), log(double);
double pow(double, double), atan2(double, double), fmod(double, double), hypot(double, double);
double ldexp(double, int), frexp(double, int *), modf(double, double *), jn(int, double);
float sinf(float), powf(float, float), sqrtf(float), fmaf(float, float, float);
long lround(double);
double atof(const char *), strtod(const char *, char **);
float strtof(const char *, char **);
void qsort(void *, size_t, size_t, int (*)(const void *, const void *));

typedef struct { int signo, error, code, pid, uid, status; void *address; void *value; long band; unsigned long pad[7]; } siginfo_t;
struct sigaction_darwin { void (*handler)(int, siginfo_t *, void *); unsigned int mask; int flags; };
int sigaction(int, const struct sigaction_darwin *, struct sigaction_darwin *);
int raise(int);
int sigprocmask(int, const unsigned int *, unsigned int *);
#define SIG_SETMASK 3
#define SIGUSR1 30
#define SA_SIGINFO 0x40

int socketpair(int, int, int, int *);
int setsockopt(int, int, int, const void *, unsigned int);
int getsockopt(int, int, int, void *, unsigned int *);
int close(int);
#define AF_UNIX 1
#define SOCK_STREAM 1
#define SOL_SOCKET 0xffff
#define SO_RCVTIMEO 0x1006

// MARK: - Threads

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static pthread_rwlock_t table = PTHREAD_RWLOCK_INITIALIZER;
static pthread_once_t once = PTHREAD_ONCE_INIT;
static pthread_key_t key;
static int counter, ready, onces;

static void count_once(void) { onces++; }

static void *worker(void *argument) {
    long index = (long)argument;
    pthread_once(&once, count_once);
    pthread_setspecific(key, (void *)(index * 10));
    for (int i = 0; i < 1000; i++) {
        pthread_mutex_lock(&lock);
        counter++;
        pthread_mutex_unlock(&lock);
    }
    pthread_rwlock_rdlock(&table);
    pthread_rwlock_unlock(&table);
    pthread_mutex_lock(&lock);
    ready++;
    pthread_cond_broadcast(&changed);
    pthread_mutex_unlock(&lock);
    return (void *)((long)pthread_getspecific(key) + 1);
}

static void threads(void) {
    pthread_key_create(&key, 0);
    pthread_attr_t attributes;
    pthread_attr_init(&attributes);
    pthread_attr_setstacksize(&attributes, 256 * 1024);
    pthread_t threads[4];
    for (long i = 0; i < 4; i++)
        pthread_create(&threads[i], &attributes, worker, (void *)i);
    pthread_attr_destroy(&attributes);
    pthread_mutex_lock(&lock);
    while (ready < 4)
        pthread_cond_wait(&changed, &lock);
    pthread_mutex_unlock(&lock);
    long results = 0;
    for (int i = 0; i < 4; i++) {
        void *result;
        pthread_join(threads[i], &result);
        results += (long)result;
    }
    pthread_rwlock_wrlock(&table);
    pthread_rwlock_unlock(&table);
    struct timeval now;
    gettimeofday(&now, 0);
    struct timespec soon = { now.tv_sec, (long)now.tv_usec * 1000 + 20000000 };
    if (soon.tv_nsec >= 1000000000) { soon.tv_sec++; soon.tv_nsec -= 1000000000; }
    pthread_mutex_lock(&lock);
    int timed_out = pthread_cond_timedwait(&changed, &lock, &soon);
    pthread_mutex_unlock(&lock);
    printf("threads counter %d once %d results %ld timedwait %d\n", counter, onces, results, timed_out);
}

// MARK: - Math

static int compare(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return x < y ? -1 : x > y;
}

// Inputs the compiler cannot fold, so each call reaches libSystem.
static volatile double half = 0.5, two = 2.0, minus_two_and_half = -2.5, one = 1.0, ten = 10.0, minus_one = -1.0;
static volatile double seven_and_half = 7.5, three = 3.0, four = 4.0, three_quarters = 0.75, forty_eight = 48.0;
static volatile double minus_three_and_three_quarters = -3.75, one_and_half = 1.5;
static volatile float quarter = 0.25f, one_and_half_f = 1.5f, three_f = 3.0f, ten_f = 10.0f, two_f = 2.0f, half_f = 0.5f;
static volatile int sixteen_exponent = 4, second_order = 2;

static void math(void) {
    int exponent;
    double whole, fraction = modf(minus_three_and_three_quarters, &whole);
    double mantissa = frexp(forty_eight, &exponent);
    printf("math %.6f %.6f %.6f %.6f %.6f %.6f\n", sin(half), cos(half), sqrt(two), floor(minus_two_and_half), exp(one),
           log(ten));
    printf("math2 %.6f %.6f %.6f %.6f %.6f\n", pow(two, half), atan2(one, minus_one), fmod(seven_and_half, two),
           hypot(three, four), ldexp(three_quarters, sixteen_exponent));
    printf("math3 %.3f %d %.3f %.3f %.6f %ld\n", mantissa, exponent, whole, fraction, jn(second_order, one_and_half),
           lround(minus_two_and_half));
    printf("float %.5f %.5f %.5f %.5f\n", sinf(quarter), powf(one_and_half_f, three_f), sqrtf(ten_f),
           fmaf(two_f, three_f, half_f));
    printf("convert %.4f %.4f %.4f\n", atof("6.25"), strtod("-1e3", 0), strtof("0.125", 0));
    double values[] = { 3.5, -1.25, 10.0, 0.0, 2.75 };
    qsort(values, 5, sizeof(double), compare);
    printf("sorted %.2f %.2f %.2f %.2f %.2f\n", values[0], values[1], values[2], values[3], values[4]);
}

// MARK: - Signals

static int handled;
static int had_context;

static void handler(int signal, siginfo_t *info, void *context) {
    handled = signal == SIGUSR1 && info->signo == SIGUSR1;
    had_context = context != 0;
}

static void signals(void) {
    // A parent can start a program with signals blocked.
    unsigned int none = 0;
    sigprocmask(SIG_SETMASK, &none, 0);
    struct sigaction_darwin action = { handler, 0, SA_SIGINFO };
    sigaction(SIGUSR1, &action, 0);
    raise(SIGUSR1);
    printf("signal handled %d context %d\n", handled, had_context);
}

// MARK: - Sockets

static void sockets(void) {
    int pair[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, pair) != 0) {
        printf("socketpair failed\n");
        return;
    }
    struct timeval timeout = { 2, 500000 }, read_back = { 0, 0 };
    unsigned int size = sizeof(read_back);
    setsockopt(pair[0], SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    getsockopt(pair[0], SOL_SOCKET, SO_RCVTIMEO, &read_back, &size);
    printf("timeout %ld %d size %u\n", (long)read_back.tv_sec, read_back.tv_usec, size == sizeof(read_back));
    close(pair[0]);
    close(pair[1]);
}

int main(void) {
    threads();
    math();
    signals();
    sockets();
    return 0;
}
