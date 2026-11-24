// Multiprocessing Services' tasks, queues and events, over pthreads: a
// task is a thread, started through libSystem's pthread_create so that it
// is set up as the program's own threads are; a queue holds messages of
// three words, waited for in turn; an event is a set of flags that a wait
// takes and clears. Critical regions and semaphores are CoreServices'.
//
// A Duration is milliseconds when positive and microseconds when negative;
// kDurationImmediate (0) doesn't wait and kDurationForever (0x7fffffff)
// waits without end.

#include "PerryCarbon.h"

#include <errno.h>
#include <pthread.h>
#include <sched.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define LIBSYSTEM "/usr/lib/libSystem.B.dylib"

enum { kMPTimeoutErr = -29296, kMPDeletedErr = -29295, kMPInsufficientResourcesErr = -29298, kMPInvalidIDErr = -29299 };
#define kDurationForever 0x7fffffff

/// The time a wait of `duration` ends, by the clock condition variables
/// here wait on.
static struct timespec deadline_after(int32_t duration) {
    struct timespec deadline;
    clock_gettime(CLOCK_MONOTONIC, &deadline);
    int64_t nanoseconds = duration >= 0 ? (int64_t)duration * 1000000 : -(int64_t)duration * 1000;
    deadline.tv_sec += (time_t)(nanoseconds / 1000000000);
    deadline.tv_nsec += (long)(nanoseconds % 1000000000);
    if (deadline.tv_nsec >= 1000000000) {
        deadline.tv_sec += 1;
        deadline.tv_nsec -= 1000000000;
    }
    return deadline;
}

static void condition_init(pthread_cond_t *condition) {
    pthread_condattr_t attributes;
    pthread_condattr_init(&attributes);
    pthread_condattr_setclock(&attributes, CLOCK_MONOTONIC);
    pthread_cond_init(condition, &attributes);
    pthread_condattr_destroy(&attributes);
}

/// Waits on the condition, its mutex held, as long as `duration` allows:
/// false when the time ran out.
static bool wait_for(pthread_cond_t *condition, pthread_mutex_t *mutex, int32_t duration, const struct timespec *deadline) {
    if (duration == kDurationForever) return pthread_cond_wait(condition, mutex) == 0;
    return pthread_cond_timedwait(condition, mutex, deadline) != ETIMEDOUT;
}

// MARK: - Queues

typedef struct queue_message {
    void *words[3];
    struct queue_message *next;
} queue_message;

#define MP_QUEUE_MAGIC 0x4d505155u   // 'MPQU'

typedef struct {
    uint32_t magic;
    pthread_mutex_t mutex;
    pthread_cond_t condition;
    queue_message *first, *last;
} mp_queue;

static mp_queue *queue_from(void *pointer) {
    mp_queue *queue = pointer;
    return queue && queue->magic == MP_QUEUE_MAGIC ? queue : NULL;
}

OSStatus carbon_MPCreateQueue(void **out) CARBON_SYMBOL(MPCreateQueue);
OSStatus carbon_MPCreateQueue(void **out) {
    if (!out) return paramErr;
    mp_queue *queue = calloc(1, sizeof *queue);
    if (!queue) return kMPInsufficientResourcesErr;
    queue->magic = MP_QUEUE_MAGIC;
    pthread_mutex_init(&queue->mutex, NULL);
    condition_init(&queue->condition);
    *out = queue;
    return noErr;
}

/// A deleted queue's waiters are told so; its memory is kept, as a task
/// may be about to notify it.
OSStatus carbon_MPDeleteQueue(void *identifier) CARBON_SYMBOL(MPDeleteQueue);
OSStatus carbon_MPDeleteQueue(void *identifier) {
    mp_queue *queue = queue_from(identifier);
    if (!queue) return kMPInvalidIDErr;
    pthread_mutex_lock(&queue->mutex);
    queue->magic = 0;
    while (queue->first) {
        queue_message *message = queue->first;
        queue->first = message->next;
        free(message);
    }
    queue->last = NULL;
    pthread_cond_broadcast(&queue->condition);
    pthread_mutex_unlock(&queue->mutex);
    return noErr;
}

OSStatus carbon_MPSetQueueReserve(void *identifier, uint32_t count) CARBON_SYMBOL(MPSetQueueReserve);
OSStatus carbon_MPSetQueueReserve(void *identifier, uint32_t count) {
    (void)count;
    return queue_from(identifier) ? noErr : kMPInvalidIDErr;
}

OSStatus carbon_MPNotifyQueue(void *identifier, void *first, void *second, void *third) CARBON_SYMBOL(MPNotifyQueue);
OSStatus carbon_MPNotifyQueue(void *identifier, void *first, void *second, void *third) {
    mp_queue *queue = queue_from(identifier);
    if (!queue) return kMPInvalidIDErr;
    queue_message *message = calloc(1, sizeof *message);
    if (!message) return kMPInsufficientResourcesErr;
    message->words[0] = first; message->words[1] = second; message->words[2] = third;
    CARBON_TRACE("queue %p: notified %p %p %p", identifier, first, second, third);
    pthread_mutex_lock(&queue->mutex);
    if (queue->last) queue->last->next = message; else queue->first = message;
    queue->last = message;
    pthread_cond_signal(&queue->condition);
    pthread_mutex_unlock(&queue->mutex);
    return noErr;
}

OSStatus carbon_MPWaitOnQueue(void *identifier, void **first, void **second, void **third, int32_t timeout) CARBON_SYMBOL(MPWaitOnQueue);
OSStatus carbon_MPWaitOnQueue(void *identifier, void **first, void **second, void **third, int32_t timeout) {
    mp_queue *queue = queue_from(identifier);
    if (!queue) return kMPInvalidIDErr;
    struct timespec deadline = deadline_after(timeout);
    pthread_mutex_lock(&queue->mutex);
    while (!queue->first && queue->magic == MP_QUEUE_MAGIC) {
        if (timeout == 0 || !wait_for(&queue->condition, &queue->mutex, timeout, &deadline)) break;
    }
    queue_message *message = queue->first;
    OSStatus status = queue->magic != MP_QUEUE_MAGIC ? kMPDeletedErr : message ? noErr : kMPTimeoutErr;
    if (status == noErr) {
        queue->first = message->next;
        if (!queue->first) queue->last = NULL;
    }
    pthread_mutex_unlock(&queue->mutex);
    CARBON_TRACE("queue %p: waited %d, status %d", identifier, timeout, (int)status);
    if (status != noErr) return status;
    if (first) *first = message->words[0];
    if (second) *second = message->words[1];
    if (third) *third = message->words[2];
    free(message);
    return noErr;
}

// MARK: - Events

#define MP_EVENT_MAGIC 0x4d504556u   // 'MPEV'

typedef struct {
    uint32_t magic;
    pthread_mutex_t mutex;
    pthread_cond_t condition;
    uint32_t flags;
} mp_event;

static mp_event *event_from(void *pointer) {
    mp_event *event = pointer;
    return event && event->magic == MP_EVENT_MAGIC ? event : NULL;
}

OSStatus carbon_MPCreateEvent(void **out) CARBON_SYMBOL(MPCreateEvent);
OSStatus carbon_MPCreateEvent(void **out) {
    if (!out) return paramErr;
    mp_event *event = calloc(1, sizeof *event);
    if (!event) return kMPInsufficientResourcesErr;
    event->magic = MP_EVENT_MAGIC;
    pthread_mutex_init(&event->mutex, NULL);
    condition_init(&event->condition);
    *out = event;
    return noErr;
}

OSStatus carbon_MPDeleteEvent(void *identifier) CARBON_SYMBOL(MPDeleteEvent);
OSStatus carbon_MPDeleteEvent(void *identifier) {
    mp_event *event = event_from(identifier);
    if (!event) return kMPInvalidIDErr;
    pthread_mutex_lock(&event->mutex);
    event->magic = 0;
    pthread_cond_broadcast(&event->condition);
    pthread_mutex_unlock(&event->mutex);
    return noErr;
}

/// Adds flags to the event's: a waiter takes them all.
OSStatus carbon_MPSetEvent(void *identifier, uint32_t flags) CARBON_SYMBOL(MPSetEvent);
OSStatus carbon_MPSetEvent(void *identifier, uint32_t flags) {
    mp_event *event = event_from(identifier);
    if (!event) return kMPInvalidIDErr;
    CARBON_TRACE("event %p: set %#x", identifier, flags);
    pthread_mutex_lock(&event->mutex);
    event->flags |= flags;
    pthread_cond_signal(&event->condition);
    pthread_mutex_unlock(&event->mutex);
    return noErr;
}

OSStatus carbon_MPWaitForEvent(void *identifier, uint32_t *flags, int32_t timeout) CARBON_SYMBOL(MPWaitForEvent);
OSStatus carbon_MPWaitForEvent(void *identifier, uint32_t *flags, int32_t timeout) {
    mp_event *event = event_from(identifier);
    if (!event) return kMPInvalidIDErr;
    struct timespec deadline = deadline_after(timeout);
    pthread_mutex_lock(&event->mutex);
    while (!event->flags && event->magic == MP_EVENT_MAGIC) {
        if (timeout == 0 || !wait_for(&event->condition, &event->mutex, timeout, &deadline)) break;
    }
    OSStatus status = event->magic != MP_EVENT_MAGIC ? kMPDeletedErr : event->flags ? noErr : kMPTimeoutErr;
    if (flags) *flags = event->flags;
    CARBON_TRACE("event %p: waited %d, status %d, flags %#x", identifier, timeout, (int)status, event->flags);
    if (status == noErr) event->flags = 0;
    pthread_mutex_unlock(&event->mutex);
    return status;
}

// MARK: - Tasks

#define MP_TASK_MAGIC 0x4d50544bu   // 'MPTK'

typedef struct {
    uint32_t magic;
    OSStatus (*entry)(void *);
    void *parameter;
    void *queue;
    void *termination[2];
    pthread_t thread;
    bool started;
} mp_task;

static _Thread_local mp_task *current_task;

/// The task that is running: a thread that is no task has an ID of its
/// own all the same.
void *carbon_MPCurrentTaskID(void) CARBON_SYMBOL(MPCurrentTaskID);
void *carbon_MPCurrentTaskID(void) {
    static _Thread_local char other;
    return current_task ? (void *)current_task : (void *)&other;
}

/// A task that ended tells its queue: the two words it was made with, and
/// its result.
static void task_ended(mp_task *task, OSStatus result) {
    CARBON_TRACE("task %p ended with %d", (void *)task, (int)result);
    if (task->queue) carbon_MPNotifyQueue(task->queue, task->termination[0], task->termination[1], (void *)(intptr_t)result);
    task->magic = 0;
}

static void task_cancelled(void *context) { task_ended(context, -1); }

static void *task_main(void *context) {
    mp_task *task = context;
    current_task = task;
    task->thread = pthread_self();
    task->started = true;
    OSStatus result = noErr;
    pthread_cleanup_push(task_cancelled, task);
    result = task->entry(task->parameter);
    pthread_cleanup_pop(0);
    task_ended(task, result);
    return NULL;
}

/// OSStatus MPCreateTask(TaskProc entry, void *parameter, ByteCount
/// stackSize, MPQueueID notifyQueue, void *terminationParameter1, void
/// *terminationParameter2, MPTaskOptions, MPTaskID *task).
OSStatus carbon_MPCreateTask(OSStatus (*entry)(void *), void *parameter, uint32_t stack, void *queue, void *first, void *second,
                             uint32_t options, void **out) CARBON_SYMBOL(MPCreateTask);
OSStatus carbon_MPCreateTask(OSStatus (*entry)(void *), void *parameter, uint32_t stack, void *queue, void *first, void *second,
                             uint32_t options, void **out) {
    (void)stack; (void)options;
    if (!entry) return paramErr;
    // libSystem's, which readies a thread for the program's code; its
    // pthread_t is a word here.
    static int (*create)(void **, const void *, void *(*)(void *), void *);
    if (!create) create = (int (*)(void **, const void *, void *(*)(void *), void *))carbon_function(LIBSYSTEM, "_pthread_create");
    mp_task *task = calloc(1, sizeof *task);
    if (!task) return kMPInsufficientResourcesErr;
    task->magic = MP_TASK_MAGIC;
    task->entry = entry;
    task->parameter = parameter;
    task->queue = queue;
    task->termination[0] = first;
    task->termination[1] = second;
    if (out) *out = task;
    void *thread = NULL;
    int error = create ? create(&thread, NULL, task_main, task) : ENOSYS;
    if (error != 0) {
        CARBON_TRACE("task: not started (%d)", error);
        if (out) *out = NULL;
        free(task);
        return kMPInsufficientResourcesErr;
    }
    CARBON_TRACE("task %p started", (void *)task);
    return noErr;
}

/// Ends another task where it next waits; the task's queue is told.
OSStatus carbon_MPTerminateTask(void *identifier, OSStatus status) CARBON_SYMBOL(MPTerminateTask);
OSStatus carbon_MPTerminateTask(void *identifier, OSStatus status) {
    (void)status;
    mp_task *task = identifier;
    if (!task || task->magic != MP_TASK_MAGIC) return kMPInvalidIDErr;
    if (task->started) pthread_cancel(task->thread);
    return noErr;
}

OSStatus carbon_MPSetTaskWeight(void *identifier, uint32_t weight) CARBON_SYMBOL(MPSetTaskWeight);
OSStatus carbon_MPSetTaskWeight(void *identifier, uint32_t weight) {
    (void)identifier; (void)weight;
    return noErr;
}

/// Ends the task that calls it, with its result.
void carbon_MPExit(OSStatus status) CARBON_SYMBOL(MPExit);
void carbon_MPExit(OSStatus status) {
    if (current_task) task_ended(current_task, status);
    pthread_exit(NULL);
}

void carbon_MPYield(void) CARBON_SYMBOL(MPYield);
void carbon_MPYield(void) { sched_yield(); }
