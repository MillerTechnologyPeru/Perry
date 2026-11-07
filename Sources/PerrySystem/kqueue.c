// kqueue and kevent over epoll. A kqueue is an epoll descriptor with a
// table of what was registered on it: reading and writing descriptors
// (EVFILT_READ, EVFILT_WRITE), timers (EVFILT_TIMER, a timerfd each) and
// user events (EVFILT_USER, which an eventfd of the queue's wakes it for).
// Events come back as Darwin's struct kevent, with EV_ADD, EV_DELETE,
// EV_ENABLE, EV_DISABLE, EV_ONESHOT, EV_CLEAR, EV_DISPATCH and EV_RECEIPT
// as Darwin treats them; other filters are refused with EINVAL.

#include "PerrySystem.h"

#include <errno.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/eventfd.h>
#include <sys/ioctl.h>
#include <sys/timerfd.h>
#include <time.h>
#include <unistd.h>

struct darwin_kevent {
    uintptr_t ident;
    int16_t filter;
    uint16_t flags;
    uint32_t fflags;
    intptr_t data;
    void *udata;
};

struct darwin_timespec { long tv_sec; long tv_nsec; };

enum {
    EVFILT_READ_ = -1, EVFILT_WRITE_ = -2, EVFILT_TIMER_ = -7, EVFILT_USER_ = -10,
    EV_ADD_ = 0x1, EV_DELETE_ = 0x2, EV_ENABLE_ = 0x4, EV_DISABLE_ = 0x8, EV_ONESHOT_ = 0x10,
    EV_CLEAR_ = 0x20, EV_RECEIPT_ = 0x40, EV_DISPATCH_ = 0x80, EV_ERROR_ = 0x4000, EV_EOF_ = 0x8000,
};

enum {
    NOTE_SECONDS_ = 0x1, NOTE_USECONDS_ = 0x2, NOTE_NSECONDS_ = 0x4, NOTE_ABSOLUTE_ = 0x8,
    NOTE_TRIGGER_ = 0x01000000, NOTE_FFLAGSMASK_ = 0x00ffffff, NOTE_FFCTRLMASK_ = 0xc0000000,
    NOTE_FFAND_ = 0x40000000, NOTE_FFOR_ = 0x80000000, NOTE_FFCOPY_ = 0xc0000000,
};

/// What epoll's data says a ready descriptor is.
enum { TAG_DESCRIPTOR = 1, TAG_TIMER = 2, TAG_WAKE = 3 };

typedef struct entry {
    uintptr_t ident;
    int16_t filter;
    uint16_t flags;         // EV_ONESHOT, EV_CLEAR, EV_DISPATCH as registered
    uint32_t fflags;
    intptr_t data;
    void *udata;
    bool enabled;
    bool triggered;         // a user event, until delivered
    int timer;              // a timer's timerfd, or -1
    struct entry *next;
} entry;

typedef struct queue {
    int epoll;
    int wake;               // eventfd for user events
    entry *entries;
    pthread_mutex_t lock;
} queue;

/// Queues by their descriptor: a queue made on a descriptor number
/// replaces whatever an earlier, since closed, queue there left.
enum { MAX_QUEUES = 4096 };
static queue *queues[MAX_QUEUES];
static pthread_mutex_t queues_lock = PTHREAD_MUTEX_INITIALIZER;

static void free_queue(queue *q) {
    for (entry *e = q->entries, *next; e; e = next) {
        next = e->next;
        if (e->timer >= 0) close(e->timer);
        free(e);
    }
    if (q->wake >= 0) close(q->wake);
    pthread_mutex_destroy(&q->lock);
    free(q);
}

static uint64_t tag(int kind, int fd) { return ((uint64_t)kind << 32) | (uint32_t)fd; }

int darwin_kqueue(void) DARWIN_SYMBOL(kqueue);
int darwin_kqueue(void) {
    int epoll = epoll_create1(EPOLL_CLOEXEC);
    if (epoll < 0) return -1;
    if (epoll >= MAX_QUEUES) {
        close(epoll);
        errno = EMFILE;
        return -1;
    }
    queue *q = calloc(1, sizeof(*q));
    q->epoll = epoll;
    q->wake = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
    pthread_mutex_init(&q->lock, NULL);
    struct epoll_event event = { .events = EPOLLIN, .data.u64 = tag(TAG_WAKE, q->wake) };
    epoll_ctl(epoll, EPOLL_CTL_ADD, q->wake, &event);
    pthread_mutex_lock(&queues_lock);
    queue *old = queues[epoll];
    queues[epoll] = q;
    pthread_mutex_unlock(&queues_lock);
    if (old) free_queue(old);
    return epoll;
}

static entry *find(queue *q, uintptr_t ident, int16_t filter) {
    for (entry *e = q->entries; e; e = e->next)
        if (e->ident == ident && e->filter == filter) return e;
    return NULL;
}

/// Points epoll at what a descriptor's read and write entries want.
static int update_descriptor(queue *q, int fd) {
    entry *read = find(q, (uintptr_t)fd, EVFILT_READ_), *write = find(q, (uintptr_t)fd, EVFILT_WRITE_);
    uint32_t events = 0;
    bool edge = true;
    if (read && read->enabled) { events |= EPOLLIN | EPOLLRDHUP; edge &= (read->flags & EV_CLEAR_) != 0; }
    if (write && write->enabled) { events |= EPOLLOUT; edge &= (write->flags & EV_CLEAR_) != 0; }
    if (!events) {
        epoll_ctl(q->epoll, EPOLL_CTL_DEL, fd, NULL);
        return 0;
    }
    if (edge) events |= EPOLLET;
    struct epoll_event event = { .events = events, .data.u64 = tag(TAG_DESCRIPTOR, fd) };
    if (epoll_ctl(q->epoll, EPOLL_CTL_MOD, fd, &event) == 0) return 0;
    if (errno != ENOENT) return -1;
    return epoll_ctl(q->epoll, EPOLL_CTL_ADD, fd, &event);
}

/// Arms a timer from its period in the units fflags name.
static int arm_timer(entry *e) {
    int64_t amount = e->data;
    int64_t nanoseconds = (e->fflags & NOTE_SECONDS_) ? amount * 1000000000LL
        : (e->fflags & NOTE_USECONDS_) ? amount * 1000LL
        : (e->fflags & NOTE_NSECONDS_) ? amount
        : amount * 1000000LL;
    if (nanoseconds <= 0) nanoseconds = 1;
    struct itimerspec spec = {0};
    spec.it_value.tv_sec = nanoseconds / 1000000000LL;
    spec.it_value.tv_nsec = nanoseconds % 1000000000LL;
    if (!(e->flags & EV_ONESHOT_) && !(e->fflags & NOTE_ABSOLUTE_)) spec.it_interval = spec.it_value;
    int flags = 0;
    if (e->fflags & NOTE_ABSOLUTE_) {
        // Absolute deadlines are wall-clock times.
        flags = TFD_TIMER_ABSTIME;
    }
    if (!e->enabled) memset(&spec, 0, sizeof(spec));
    return timerfd_settime(e->timer, flags, &spec, NULL);
}

static int apply_change(queue *q, const struct darwin_kevent *change) {
    int16_t filter = change->filter;
    if (filter != EVFILT_READ_ && filter != EVFILT_WRITE_ && filter != EVFILT_TIMER_ && filter != EVFILT_USER_)
        return EINVAL;
    entry *e = find(q, change->ident, filter);
    if (change->flags & EV_DELETE_) {
        if (!e) return ENOENT;
        for (entry **link = &q->entries; *link; link = &(*link)->next) {
            if (*link == e) { *link = e->next; break; }
        }
        if (e->timer >= 0) {
            epoll_ctl(q->epoll, EPOLL_CTL_DEL, e->timer, NULL);
            close(e->timer);
        }
        int fd = (int)e->ident;
        free(e);
        if (filter == EVFILT_READ_ || filter == EVFILT_WRITE_) update_descriptor(q, fd);
        return 0;
    }
    bool added = false;
    if (!e) {
        if (!(change->flags & EV_ADD_)) return ENOENT;
        e = calloc(1, sizeof(*e));
        e->ident = change->ident;
        e->filter = filter;
        e->timer = -1;
        e->enabled = true;
        e->next = q->entries;
        q->entries = e;
        added = true;
    }
    if (change->flags & EV_ADD_) {
        e->flags = change->flags & (EV_ONESHOT_ | EV_CLEAR_ | EV_DISPATCH_);
        e->udata = change->udata;
        if (filter != EVFILT_USER_) { e->fflags = change->fflags; e->data = change->data; }
    }
    if (change->flags & EV_ENABLE_) e->enabled = true;
    if (change->flags & EV_DISABLE_) e->enabled = false;
    switch (filter) {
    case EVFILT_READ_:
    case EVFILT_WRITE_:
        if (update_descriptor(q, (int)e->ident) != 0) {
            int error = errno;
            if (added) apply_change(q, &(struct darwin_kevent){ .ident = e->ident, .filter = filter, .flags = EV_DELETE_ });
            return error;
        }
        return 0;
    case EVFILT_TIMER_:
        if (e->timer < 0) {
            e->timer = timerfd_create((change->fflags & NOTE_ABSOLUTE_) ? CLOCK_REALTIME : CLOCK_MONOTONIC,
                                      TFD_CLOEXEC | TFD_NONBLOCK);
            if (e->timer < 0) return errno;
            struct epoll_event event = { .events = EPOLLIN, .data.u64 = tag(TAG_TIMER, e->timer) };
            epoll_ctl(q->epoll, EPOLL_CTL_ADD, e->timer, &event);
        }
        if ((change->flags & (EV_ADD_ | EV_ENABLE_ | EV_DISABLE_)) && arm_timer(e) != 0) return errno;
        return 0;
    case EVFILT_USER_: {
        uint32_t value = change->fflags & NOTE_FFLAGSMASK_;
        switch (change->fflags & NOTE_FFCTRLMASK_) {
        case NOTE_FFAND_: e->fflags &= value; break;
        case NOTE_FFOR_: e->fflags |= value; break;
        case NOTE_FFCOPY_: e->fflags = value; break;
        default: break;
        }
        if (change->fflags & NOTE_TRIGGER_) {
            e->triggered = true;
            uint64_t one = 1;
            (void)!write(q->wake, &one, sizeof(one));
        }
        return 0;
    }
    }
    return EINVAL;
}

/// After an entry's event is delivered: gone with EV_ONESHOT, disabled
/// with EV_DISPATCH, reset if a user event with EV_CLEAR.
static void delivered(queue *q, entry *e) {
    if (e->filter == EVFILT_USER_ && (e->flags & EV_CLEAR_)) e->triggered = false;
    if (e->flags & EV_ONESHOT_) {
        apply_change(q, &(struct darwin_kevent){ .ident = e->ident, .filter = e->filter, .flags = EV_DELETE_ });
    } else if (e->flags & EV_DISPATCH_) {
        e->enabled = false;
        if (e->filter == EVFILT_READ_ || e->filter == EVFILT_WRITE_) update_descriptor(q, (int)e->ident);
        if (e->filter == EVFILT_TIMER_) arm_timer(e);
    }
}

static void report(struct darwin_kevent *out, entry *e, uint16_t extra, intptr_t data) {
    *out = (struct darwin_kevent){ .ident = e->ident, .filter = e->filter, .flags = (uint16_t)(e->flags | extra),
                                   .fflags = e->filter == EVFILT_USER_ ? e->fflags : 0, .data = data, .udata = e->udata };
}

/// The user events triggered and enabled, as many as fit.
static int collect_user(queue *q, struct darwin_kevent *events, int capacity, int count) {
    for (entry *e = q->entries, *next; e && count < capacity; e = next) {
        next = e->next;
        if (e->filter != EVFILT_USER_ || !e->triggered || !e->enabled) continue;
        report(&events[count++], e, 0, 0);
        delivered(q, e);
    }
    return count;
}

int darwin_kevent(int kq, const struct darwin_kevent *changes, int change_count, struct darwin_kevent *events,
                  int event_count, const struct darwin_timespec *timeout) DARWIN_SYMBOL(kevent);
int darwin_kevent(int kq, const struct darwin_kevent *changes, int change_count, struct darwin_kevent *events,
                  int event_count, const struct darwin_timespec *timeout) {
    pthread_mutex_lock(&queues_lock);
    queue *q = kq >= 0 && kq < MAX_QUEUES ? queues[kq] : NULL;
    pthread_mutex_unlock(&queues_lock);
    if (!q) {
        errno = EBADF;
        return -1;
    }
    int count = 0;
    pthread_mutex_lock(&q->lock);
    for (int i = 0; i < change_count; i++) {
        int error = apply_change(q, &changes[i]);
        if (error || (changes[i].flags & EV_RECEIPT_)) {
            if (count < event_count) {
                events[count] = changes[i];
                events[count].flags = EV_ERROR_;
                events[count].data = perry_darwin_errno_from_linux(error);
                count++;
            } else if (error) {
                pthread_mutex_unlock(&q->lock);
                errno = error;
                return -1;
            }
        }
    }
    if (count || event_count <= 0) {
        pthread_mutex_unlock(&q->lock);
        return count;
    }
    count = collect_user(q, events, event_count, count);
    pthread_mutex_unlock(&q->lock);

    int wait = -1;
    if (count) wait = 0;
    else if (timeout) wait = (int)(timeout->tv_sec * 1000 + (timeout->tv_nsec + 999999) / 1000000);
    struct epoll_event ready[64];
    int capacity = event_count < 64 ? event_count : 64;
    int found = epoll_wait(q->epoll, ready, capacity, wait);
    if (found < 0) {
        if (errno == EINTR && count) return count;
        return count ? count : -1;
    }
    pthread_mutex_lock(&q->lock);
    for (int i = 0; i < found && count < event_count; i++) {
        int kind = (int)(ready[i].data.u64 >> 32), fd = (int)(uint32_t)ready[i].data.u64;
        uint32_t flags = ready[i].events;
        if (kind == TAG_WAKE) {
            uint64_t value;
            while (read(q->wake, &value, sizeof(value)) > 0) {}
            count = collect_user(q, events, event_count, count);
        } else if (kind == TAG_TIMER) {
            uint64_t expirations = 0;
            if (read(fd, &expirations, sizeof(expirations)) <= 0) continue;
            for (entry *e = q->entries; e; e = e->next) {
                if (e->filter != EVFILT_TIMER_ || e->timer != fd || !e->enabled) continue;
                report(&events[count++], e, 0, (intptr_t)expirations);
                delivered(q, e);
                break;
            }
        } else if (kind == TAG_DESCRIPTOR) {
            uint16_t eof = (flags & (EPOLLHUP | EPOLLRDHUP | EPOLLERR)) ? EV_EOF_ : 0;
            entry *read_entry = find(q, (uintptr_t)fd, EVFILT_READ_);
            if (read_entry && read_entry->enabled && (flags & (EPOLLIN | EPOLLHUP | EPOLLRDHUP | EPOLLERR))) {
                int available = 0;
                if (ioctl(fd, FIONREAD, &available) != 0) available = 1;
                report(&events[count++], read_entry, eof, available);
                delivered(q, read_entry);
            }
            entry *write_entry = find(q, (uintptr_t)fd, EVFILT_WRITE_);
            if (count < event_count && write_entry && write_entry->enabled && (flags & (EPOLLOUT | EPOLLHUP | EPOLLERR))) {
                report(&events[count++], write_entry, (flags & (EPOLLHUP | EPOLLERR)) ? EV_EOF_ : 0, 65536);
                delivered(q, write_entry);
            }
        }
    }
    pthread_mutex_unlock(&q->lock);
    return count;
}
