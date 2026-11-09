// A sampling profiler for finding where a program's main thread spends its
// time: with PERRY_PROFILE set to a path, a timer on the main thread's CPU
// clock interrupts it PERRY_PROFILE_HZ times a second of its running time
// (250 by default), and each interruption appends a line to the path: the
// interrupted pc and the return addresses up its frame-pointer chain, in
// hexadecimal. `<path>.images` lists what those addresses are in: each
// Mach-O image's base, size and path, then the process's executable
// mappings (the Linux libraries), rewritten as images load. With
// PERRY_PROFILE_ALL=1 the timer is on the process's CPU clock instead and
// samples whichever thread is running, each line starting with its thread
// id ("t1234"), to see what other threads do. The handler
// only reads the stack and writes, so a sample taken anywhere is safe;
// Scripts/perry-profile.py turns the two files into a report.

#define _GNU_SOURCE
#include "image.h"
#include "log.h"

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ucontext.h>
#include <time.h>
#include <unistd.h>

static perry_loader *profile_loader;
static int profile_fd = -1;
static char profile_images_path[4096];
static unsigned profile_image_count;
static unsigned long profile_samples;
static int profile_all;

/// Appends `value` in hexadecimal to `out`, with no allocation.
static char *put_hex(char *out, uintptr_t value) {
    char digits[2 * sizeof(uintptr_t)];
    int n = 0;
    do {
        digits[n++] = "0123456789abcdef"[value & 15];
        value >>= 4;
    } while (value);
    while (n)
        *out++ = digits[--n];
    return out;
}

static void put_all(int fd, const char *data, size_t length) {
    while (length) {
        ssize_t written = write(fd, data, length);
        if (written <= 0)
            return;
        data += written;
        length -= (size_t)written;
    }
}

/// Rewrites the images file: the Mach-O images, then the executable
/// mappings of /proc/self/maps.
static void write_images(void) {
    int fd = open(profile_images_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0)
        return;
    char line[4352];
    for (perry_image *image = profile_loader->images; image; image = image->next) {
        char *out = line;
        memcpy(out, "macho ", 6), out += 6;
        out = put_hex(out, (uintptr_t)image->base), *out++ = ' ';
        out = put_hex(out, (uintptr_t)image->vm_size), *out++ = ' ';
        const char *path = image->path ? image->path : "?";
        size_t length = strlen(path);
        if (length > 4096)
            length = 4096;
        memcpy(out, path, length), out += length;
        *out++ = '\n';
        put_all(fd, line, (size_t)(out - line));
    }
    int maps = open("/proc/self/maps", O_RDONLY);
    if (maps >= 0) {
        char buffer[8192];
        ssize_t got;
        while ((got = read(maps, buffer, sizeof(buffer))) > 0)
            put_all(fd, buffer, (size_t)got);
        close(maps);
    }
    close(fd);
}

static void profile_handler(int signal, siginfo_t *info, void *raw_context) {
    (void)signal, (void)info;
    int saved = errno;
    ucontext_t *context = raw_context;
    mcontext_t *machine = &context->uc_mcontext;
    char line[64 * 17 + 24];
    char *out = line;
    if (profile_all) {
        *out++ = 't';
        out = put_hex(out, (uintptr_t)gettid());
        *out++ = ' ';
    }
#if defined(__arm__)
    uintptr_t pc = machine->arm_pc, fp = machine->arm_r7, low = machine->arm_sp;
    const uintptr_t alignment = 3;
#elif defined(__x86_64__)
    uintptr_t pc = (uintptr_t)machine->gregs[REG_RIP], fp = (uintptr_t)machine->gregs[REG_RBP], low = (uintptr_t)machine->gregs[REG_RSP];
    const uintptr_t alignment = 7;
#else
    uintptr_t pc = machine->pc, fp = machine->regs[29], low = machine->sp;
    const uintptr_t alignment = 7;
#endif
    out = put_hex(out, pc);
    // Frame records are {previous fp, return address}, ascending the stack.
    for (int frame = 0; frame < 63 && fp && (fp & alignment) == 0 && fp >= low && fp - low < (64 << 20); frame++) {
        uintptr_t *record = (uintptr_t *)fp;
        uintptr_t next = record[0], ret = record[1];
        if (!ret)
            break;
        *out++ = ' ';
        out = put_hex(out, ret);
        low = fp;
        fp = next;
    }
    *out++ = '\n';
    put_all(profile_fd, line, (size_t)(out - line));
    // Images load as the program runs: the map follows them.
    unsigned count = 0;
    for (perry_image *image = profile_loader->images; image; image = image->next)
        count++;
    if (count != profile_image_count || ++profile_samples % 2000 == 0) {
        profile_image_count = count;
        write_images();
    }
    errno = saved;
}

void perry_install_profiler(perry_loader *loader) {
    const char *path = getenv("PERRY_PROFILE");
    if (!path || !*path)
        return;
    profile_loader = loader;
    profile_fd = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_APPEND, 0644);
    if (profile_fd < 0)
        perry_fatal("PERRY_PROFILE: cannot open %s", path);
    snprintf(profile_images_path, sizeof(profile_images_path), "%s.images", path);
    write_images();

    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_sigaction = profile_handler;
    action.sa_flags = SA_SIGINFO | SA_RESTART;
    sigemptyset(&action.sa_mask);
    sigaction(SIGPROF, &action, NULL);

    // A timer on this thread's CPU clock, signalling this thread; or on the
    // process's, signalling whichever thread runs.
    const char *all = getenv("PERRY_PROFILE_ALL");
    profile_all = all && *all && strcmp(all, "0") != 0;
    clockid_t clock = CLOCK_PROCESS_CPUTIME_ID;
    if (!profile_all && pthread_getcpuclockid(pthread_self(), &clock) != 0)
        perry_fatal("PERRY_PROFILE: no CPU clock for the main thread");
    struct sigevent event;
    memset(&event, 0, sizeof(event));
    event.sigev_signo = SIGPROF;
    if (profile_all) {
        event.sigev_notify = SIGEV_SIGNAL;
    } else {
        event.sigev_notify = SIGEV_THREAD_ID;
        event._sigev_un._tid = gettid();
    }
    timer_t timer;
    if (timer_create(clock, &event, &timer) != 0)
        perry_fatal("PERRY_PROFILE: cannot make the timer");
    const char *rate = getenv("PERRY_PROFILE_HZ");
    long hz = rate ? strtol(rate, NULL, 10) : 250;
    if (hz < 1 || hz > 10000)
        hz = 250;
    long interval = 1000000000L / hz;
    struct itimerspec spec = { .it_interval = { interval / 1000000000L, interval % 1000000000L },
                               .it_value = { interval / 1000000000L, interval % 1000000000L } };
    timer_settime(timer, 0, &spec, NULL);
}
