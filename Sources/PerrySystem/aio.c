// POSIX asynchronous I/O in Darwin's struct aiocb, which glibc's doesn't
// match: each read or write happens when it is queued, with pread or
// pwrite, and its result is kept until aio_return collects it. aio_error
// so never reports EINPROGRESS, and aio_suspend never waits.

#include "PerrySystem.h"

#include <errno.h>
#include <pthread.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>
#include <unistd.h>

/// Darwin's struct aiocb, as far as the fields used here. Its 64-bit offset
/// is aligned to 4 bytes on armv7, which puts the buffer at 12.
#if defined(__arm__) || defined(__i386__)
#pragma pack(push, 4)
#endif
struct darwin_aiocb {
    int aio_fildes;
    int64_t aio_offset;
    volatile void *aio_buf;
    size_t aio_nbytes;
    int aio_reqprio;
    // struct sigevent aio_sigevent and int aio_lio_opcode follow.
};
#if defined(__arm__) || defined(__i386__)
#pragma pack(pop)
_Static_assert(offsetof(struct darwin_aiocb, aio_buf) == 12, "aio_buf is at 12 on Darwin armv7");
#endif

struct result {
    const struct darwin_aiocb *control;
    ssize_t value;
    int error;      // Darwin-numbered, 0 when it succeeded
};

static struct result results[256];
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;

static int record(const struct darwin_aiocb *control, ssize_t value) {
    int error = value < 0 ? perry_darwin_errno_from_linux(errno) : 0;
    pthread_mutex_lock(&lock);
    struct result *slot = NULL;
    for (size_t i = 0; i < sizeof results / sizeof *results; i++) {
        if (results[i].control == control) { slot = &results[i]; break; }
        if (!slot && !results[i].control) slot = &results[i];
    }
    if (slot) *slot = (struct result){ control, value, error };
    pthread_mutex_unlock(&lock);
    if (!slot) {
        errno = EAGAIN;
        return -1;
    }
    return 0;
}

static struct result *find(const struct darwin_aiocb *control) {
    for (size_t i = 0; i < sizeof results / sizeof *results; i++) {
        if (control && results[i].control == control) return &results[i];
    }
    return NULL;
}

int darwin_aio_read(struct darwin_aiocb *control) DARWIN_SYMBOL(aio_read);
int darwin_aio_read(struct darwin_aiocb *control) {
    if (!control) { errno = EINVAL; return -1; }
    return record(control, pread(control->aio_fildes, (void *)control->aio_buf, control->aio_nbytes, control->aio_offset));
}

int darwin_aio_write(struct darwin_aiocb *control) DARWIN_SYMBOL(aio_write);
int darwin_aio_write(struct darwin_aiocb *control) {
    if (!control) { errno = EINVAL; return -1; }
    return record(control, pwrite(control->aio_fildes, (const void *)control->aio_buf, control->aio_nbytes, control->aio_offset));
}

/// 0 once the operation succeeded, its Darwin errno if it failed.
int darwin_aio_error(const struct darwin_aiocb *control) DARWIN_SYMBOL(aio_error);
int darwin_aio_error(const struct darwin_aiocb *control) {
    pthread_mutex_lock(&lock);
    struct result *slot = find(control);
    int error = slot ? slot->error : -1;
    pthread_mutex_unlock(&lock);
    if (error < 0) { errno = EINVAL; return -1; }
    return error;
}

/// The operation's result, once; it is forgotten after.
ssize_t darwin_aio_return(struct darwin_aiocb *control) DARWIN_SYMBOL(aio_return);
ssize_t darwin_aio_return(struct darwin_aiocb *control) {
    pthread_mutex_lock(&lock);
    struct result *slot = find(control);
    struct result found = slot ? *slot : (struct result){ 0 };
    if (slot) slot->control = NULL;
    pthread_mutex_unlock(&lock);
    if (!found.control) { errno = EINVAL; return -1; }
    if (found.value < 0) errno = perry_linux_errno_from_darwin(found.error);
    return found.value;
}

/// Every operation has already completed.
int darwin_aio_suspend(const struct darwin_aiocb *const list[], int count, const void *timeout) DARWIN_SYMBOL(aio_suspend);
int darwin_aio_suspend(const struct darwin_aiocb *const list[], int count, const void *timeout) { return 0; }

/// Nothing is ever in progress to cancel: AIO_ALLDONE.
int darwin_aio_cancel(int fd, struct darwin_aiocb *control) DARWIN_SYMBOL(aio_cancel);
int darwin_aio_cancel(int fd, struct darwin_aiocb *control) { return 0x2; }
