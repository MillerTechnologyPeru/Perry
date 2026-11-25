// The Time Manager: tasks a program installs, primed to run once after a
// delay, each time they're primed. Mac OS X runs them on a thread of their
// own, apart from the program's; so do these. RAD's Bink decodes and reads
// its movies from them.

#include "PerryCarbon.h"

#include <pthread.h>
#include <stdbool.h>
#include <stdlib.h>
#include <time.h>

#pragma pack(push, 2)
typedef struct TMTask {
    void *qLink;
    int16_t qType;
    void (*tmAddr)(struct TMTask *);
    int32_t tmCount;
    int32_t tmWakeUp;
    int32_t tmReserved;
} TMTask;
#pragma pack(pop)

typedef struct primed {
    TMTask *task;
    double due;
    struct primed *next;
} primed;

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed;
static primed *queue;
static bool started;

static double now(void) {
    struct timespec time;
    clock_gettime(CLOCK_MONOTONIC, &time);
    return (double)time.tv_sec + (double)time.tv_nsec / 1e9;
}

static void *run_tasks(void *unused) {
    (void)unused;
    pthread_mutex_lock(&lock);
    for (;;) {
        if (!queue) {
            pthread_cond_wait(&changed, &lock);
            continue;
        }
        primed **earliest = &queue;
        for (primed **each = &queue; *each; each = &(*each)->next)
            if ((*each)->due < (*earliest)->due) earliest = each;
        double wait = (*earliest)->due - now();
        if (wait > 0) {
            struct timespec until;
            clock_gettime(CLOCK_MONOTONIC, &until);
            long nanoseconds = until.tv_nsec + (long)((wait - (double)(long)wait) * 1e9);
            until.tv_sec += (time_t)wait + nanoseconds / 1000000000;
            until.tv_nsec = nanoseconds % 1000000000;
            pthread_cond_timedwait(&changed, &lock, &until);
            continue;
        }
        primed *due = *earliest;
        *earliest = due->next;
        TMTask *task = due->task;
        free(due);
        // The task runs without the lock: it may prime itself again.
        pthread_mutex_unlock(&lock);
        if (task->tmAddr) task->tmAddr(task);
        pthread_mutex_lock(&lock);
    }
    return NULL;
}

static void start(void) {
    if (started) return;
    started = true;
    pthread_condattr_t attributes;
    pthread_condattr_init(&attributes);
    pthread_condattr_setclock(&attributes, CLOCK_MONOTONIC);
    pthread_cond_init(&changed, &attributes);
    pthread_condattr_destroy(&attributes);
    pthread_t thread;
    pthread_create(&thread, NULL, run_tasks, NULL);
    pthread_detach(thread);
}

/// Takes a task out of the queue; whether it was in it.
static bool unprime(TMTask *task) {
    for (primed **each = &queue; *each; each = &(*each)->next)
        if ((*each)->task == task) {
            primed *found = *each;
            *each = found->next;
            free(found);
            return true;
        }
    return false;
}

typedef void (*TimerUPP)(TMTask *);

TimerUPP carbon_NewTimerUPP(TimerUPP procedure) CARBON_SYMBOL(NewTimerUPP);
TimerUPP carbon_NewTimerUPP(TimerUPP procedure) { return procedure; }

void carbon_DisposeTimerUPP(TimerUPP procedure) CARBON_SYMBOL(DisposeTimerUPP);
void carbon_DisposeTimerUPP(TimerUPP procedure) { (void)procedure; }

void carbon_InvokeTimerUPP(TMTask *task, TimerUPP procedure) CARBON_SYMBOL(InvokeTimerUPP);
void carbon_InvokeTimerUPP(TMTask *task, TimerUPP procedure) {
    if (procedure) procedure(task);
}

/// Installing a task readies it; it runs once primed.
OSErr carbon_InstallTimeTask(TMTask *task) CARBON_SYMBOL(InstallTimeTask);
OSErr carbon_InstallTimeTask(TMTask *task) {
    if (!task) return paramErr;
    task->tmCount = 0;
    return noErr;
}

OSErr carbon_InstallXTimeTask(TMTask *task) CARBON_SYMBOL(InstallXTimeTask);
OSErr carbon_InstallXTimeTask(TMTask *task) { return carbon_InstallTimeTask(task); }

OSErr carbon_InsTime(TMTask *task) CARBON_SYMBOL(InsTime);
OSErr carbon_InsTime(TMTask *task) { return carbon_InstallTimeTask(task); }

OSErr carbon_InsXTime(TMTask *task) CARBON_SYMBOL(InsXTime);
OSErr carbon_InsXTime(TMTask *task) { return carbon_InstallTimeTask(task); }

/// Runs the task after `count` milliseconds, or -`count` microseconds.
OSErr carbon_PrimeTime(TMTask *task, int32_t count) CARBON_SYMBOL(PrimeTime);
OSErr carbon_PrimeTime(TMTask *task, int32_t count) {
    if (!task) return paramErr;
    primed *made = malloc(sizeof *made);
    if (!made) return memFullErr;
    double delay = count >= 0 ? (double)count / 1e3 : -(double)count / 1e6;
    pthread_mutex_lock(&lock);
    start();
    unprime(task);
    *made = (primed){task, now() + delay, queue};
    queue = made;
    pthread_cond_signal(&changed);
    pthread_mutex_unlock(&lock);
    return noErr;
}

/// Takes the task out; its count is what was left of its time, in
/// milliseconds (none, here, once it has run).
OSErr carbon_RemoveTimeTask(TMTask *task) CARBON_SYMBOL(RemoveTimeTask);
OSErr carbon_RemoveTimeTask(TMTask *task) {
    if (!task) return paramErr;
    pthread_mutex_lock(&lock);
    double left = 0;
    for (primed *each = queue; each; each = each->next)
        if (each->task == task) left = each->due - now();
    unprime(task);
    pthread_mutex_unlock(&lock);
    task->tmCount = left > 0 ? (int32_t)(left * 1e3) : 0;
    return noErr;
}

OSErr carbon_RmvTime(TMTask *task) CARBON_SYMBOL(RmvTime);
OSErr carbon_RmvTime(TMTask *task) { return carbon_RemoveTimeTask(task); }

// MARK: - Open Transport's atomic arithmetic

int32_t carbon_OTAtomicAdd32(int32_t amount, int32_t *value) CARBON_SYMBOL(OTAtomicAdd32);
int32_t carbon_OTAtomicAdd32(int32_t amount, int32_t *value) {
    return __atomic_add_fetch(value, amount, __ATOMIC_SEQ_CST);
}

int16_t carbon_OTAtomicAdd16(int32_t amount, int16_t *value) CARBON_SYMBOL(OTAtomicAdd16);
int16_t carbon_OTAtomicAdd16(int32_t amount, int16_t *value) {
    return __atomic_add_fetch(value, (int16_t)amount, __ATOMIC_SEQ_CST);
}
