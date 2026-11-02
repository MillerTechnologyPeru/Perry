// libSystem's POSIX layer where Darwin's ABI differs from Linux's: pthread
// mutexes, conditions, read-write locks and once with their static
// initializers; open's flags, stat, directories, fcntl and file locks;
// select, poll and sendmsg with file descriptor passing; clocks, mmap,
// uname, sysconf and arc4random.

#import <Foundation/Foundation.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/uio.h>
#include <sys/utsname.h>
#include <time.h>
#include <unistd.h>
#include <mach/mach_time.h>

static void say(NSString *line) {
    printf("%s\n", line.UTF8String);
    fflush(stdout);
}

// MARK: - Threads

static pthread_mutex_t counterLock = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t recursiveLock = PTHREAD_RECURSIVE_MUTEX_INITIALIZER;
static pthread_cond_t ready = PTHREAD_COND_INITIALIZER;
static pthread_rwlock_t table = PTHREAD_RWLOCK_INITIALIZER;
static pthread_once_t onceToken = PTHREAD_ONCE_INIT;
static int counter, onceCount, readers, signalled;

static void *addThousand(void *unused) {
    for (int i = 0; i < 1000; i++) {
        pthread_mutex_lock(&counterLock);
        counter++;
        pthread_mutex_unlock(&counterLock);
    }
    return (void *)(long)7;
}

static void runOnce(void) { onceCount++; }

static void *waiter(void *unused) {
    pthread_mutex_lock(&counterLock);
    while (!signalled) pthread_cond_wait(&ready, &counterLock);
    pthread_mutex_unlock(&counterLock);
    return NULL;
}

static void *reader(void *unused) {
    pthread_rwlock_rdlock(&table);
    __sync_fetch_and_add(&readers, 1);
    usleep(5000);
    pthread_rwlock_unlock(&table);
    return NULL;
}

static void threads(void) {
    pthread_t workers[4];
    for (int i = 0; i < 4; i++) pthread_create(&workers[i], NULL, addThousand, NULL);
    void *result = NULL;
    for (int i = 0; i < 4; i++) pthread_join(workers[i], &result);
    say([NSString stringWithFormat:@"mutex: %d, result %ld", counter, (long)result]);

    int first = pthread_mutex_lock(&recursiveLock);
    int second = pthread_mutex_lock(&recursiveLock);
    int tried = pthread_mutex_trylock(&counterLock);
    int busy = 0;
    pthread_mutex_unlock(&counterLock);
    pthread_mutex_unlock(&recursiveLock);
    pthread_mutex_unlock(&recursiveLock);

    pthread_mutexattr_t attributes;
    pthread_mutexattr_init(&attributes);
    pthread_mutexattr_settype(&attributes, PTHREAD_MUTEX_ERRORCHECK);
    int type = -1;
    pthread_mutexattr_gettype(&attributes, &type);
    pthread_mutex_t checked;
    pthread_mutex_init(&checked, &attributes);
    pthread_mutexattr_destroy(&attributes);
    pthread_mutex_lock(&checked);
    int again = pthread_mutex_lock(&checked);
    pthread_mutex_unlock(&checked);
    int notOwned = pthread_mutex_unlock(&checked);
    pthread_mutex_destroy(&checked);
    pthread_mutex_lock(&counterLock);
    busy = pthread_mutex_trylock(&counterLock);
    pthread_mutex_unlock(&counterLock);
    say([NSString stringWithFormat:@"locks: recursive %d %d, trylock %d then %d (EBUSY %d), errorcheck type %d relock %d (EDEADLK %d) unlock %d (EPERM %d)",
         first, second, tried, busy, EBUSY, type, again, EDEADLK, notOwned, EPERM]);

    pthread_t waiting;
    pthread_create(&waiting, NULL, waiter, NULL);
    usleep(10000);
    pthread_mutex_lock(&counterLock);
    signalled = 1;
    pthread_cond_broadcast(&ready);
    pthread_mutex_unlock(&counterLock);
    pthread_join(waiting, NULL);

    pthread_mutex_lock(&counterLock);
    struct timespec deadline;
    struct timeval now;
    gettimeofday(&now, NULL);
    deadline.tv_sec = now.tv_sec;
    deadline.tv_nsec = now.tv_usec * 1000 + 20 * 1000000;
    if (deadline.tv_nsec >= 1000000000) { deadline.tv_sec++; deadline.tv_nsec -= 1000000000; }
    int timedOut = pthread_cond_timedwait(&ready, &counterLock, &deadline);
    pthread_mutex_unlock(&counterLock);
    say([NSString stringWithFormat:@"condition: woken, timed wait %d (ETIMEDOUT %d)", timedOut, ETIMEDOUT]);

    pthread_t readerThreads[3];
    for (int i = 0; i < 3; i++) pthread_create(&readerThreads[i], NULL, reader, NULL);
    for (int i = 0; i < 3; i++) pthread_join(readerThreads[i], NULL);
    pthread_rwlock_wrlock(&table);
    int writeBusy = pthread_rwlock_tryrdlock(&table);
    pthread_rwlock_unlock(&table);
    for (int i = 0; i < 3; i++) pthread_once(&onceToken, runOnce);
    say([NSString stringWithFormat:@"rwlock: %d readers, tryrdlock while writing %d; once %d", readers, writeBusy, onceCount]);

    pthread_attr_t threadAttributes;
    pthread_attr_init(&threadAttributes);
    pthread_attr_setdetachstate(&threadAttributes, PTHREAD_CREATE_DETACHED);
    int detach = -1;
    pthread_attr_getdetachstate(&threadAttributes, &detach);
    size_t stack = 0;
    pthread_attr_setstacksize(&threadAttributes, 1 << 20);
    pthread_attr_getstacksize(&threadAttributes, &stack);
    pthread_attr_destroy(&threadAttributes);

    static pthread_key_t key;
    pthread_key_create(&key, NULL);
    pthread_setspecific(key, (void *)0x42);
    pthread_setname_np("bedrock-main");
    char name[64] = {0};
    pthread_getname_np(pthread_self(), name, sizeof(name));
    say([NSString stringWithFormat:@"attributes: detached %d (%d), stack %zu, specific %p, name %s, main %d", detach,
         PTHREAD_CREATE_DETACHED, stack, pthread_getspecific(key), name, pthread_main_np()]);
}

// MARK: - Files

static NSString *directory;

static const char *path(NSString *name) {
    return [directory stringByAppendingPathComponent:name].fileSystemRepresentation;
}

static void files(void) {
    directory = [NSTemporaryDirectory() stringByAppendingPathComponent:
                 [NSString stringWithFormat:@"bedrock-%d", getpid()]];
    mkdir(directory.fileSystemRepresentation, 0755);

    int fd = open(path(@"a.txt"), O_WRONLY | O_CREAT | O_TRUNC, 0640);
    write(fd, "hello, world\n", 13);
    close(fd);
    int exclusive = open(path(@"a.txt"), O_WRONLY | O_CREAT | O_EXCL, 0600);
    int exclusiveErrno = errno;
    fd = open(path(@"a.txt"), O_WRONLY | O_APPEND);
    write(fd, "more\n", 5);
    close(fd);
    fd = open(path(@"a.txt"), O_RDONLY | O_CLOEXEC);
    char buffer[64] = {0};
    ssize_t count = read(fd, buffer, sizeof(buffer) - 1);
    int descriptorFlags = fcntl(fd, F_GETFD);
    say([NSString stringWithFormat:@"open: read %zd, exclusive %d errno %d (EEXIST %d), cloexec %d", count,
         exclusive, exclusiveErrno, EEXIST, descriptorFlags & FD_CLOEXEC]);

    struct stat info;
    fstat(fd, &info);
    struct stat byPath;
    stat(path(@"a.txt"), &byPath);
    say([NSString stringWithFormat:@"stat: size %lld, regular %d, mode %o, links %d, same inode %d, mtime set %d, blksize %d",
         (long long)info.st_size, S_ISREG(info.st_mode), info.st_mode & 0777, info.st_nlink, info.st_ino == byPath.st_ino,
         info.st_mtimespec.tv_sec > 1600000000, info.st_blksize > 0]);
    close(fd);

    symlink("a.txt", path(@"link"));
    struct stat linkInfo, followed;
    lstat(path(@"link"), &linkInfo);
    stat(path(@"link"), &followed);
    int dirfd = open(directory.fileSystemRepresentation, O_RDONLY | O_DIRECTORY);
    struct stat at;
    fstatat(dirfd, "link", &at, AT_SYMLINK_NOFOLLOW);
    struct stat cwdAt;
    int cwdResult = fstatat(AT_FDCWD, path(@"a.txt"), &cwdAt, 0);
    say([NSString stringWithFormat:@"links: lstat symlink %d, stat regular %d, fstatat symlink %d, AT_FDCWD %d size %lld",
         S_ISLNK(linkInfo.st_mode), S_ISREG(followed.st_mode), S_ISLNK(at.st_mode), cwdResult, (long long)cwdAt.st_size]);

    mkdir(path(@"sub"), 0700);
    close(open(path(@"b.dat"), O_CREAT | O_WRONLY, 0600));
    DIR *listing = opendir(directory.fileSystemRepresentation);
    NSMutableArray *entries = [NSMutableArray array];
    struct dirent *entry;
    while ((entry = readdir(listing))) {
        if (entry->d_name[0] == '.') continue;
        const char *kind = entry->d_type == DT_DIR ? "dir" : entry->d_type == DT_LNK ? "link" : entry->d_type == DT_REG ? "file" : "?";
        [entries addObject:[NSString stringWithFormat:@"%s:%s:%d", entry->d_name, kind, entry->d_namlen]];
    }
    closedir(listing);
    [entries sortUsingSelector:@selector(compare:)];
    say([NSString stringWithFormat:@"readdir: %@", [entries componentsJoinedByString:@" "]]);

    fd = open(path(@"a.txt"), O_RDWR);
    int statusFlags = fcntl(fd, F_GETFL);
    fcntl(fd, F_SETFL, statusFlags | O_NONBLOCK | O_APPEND);
    int updated = fcntl(fd, F_GETFL);
    int duplicate = fcntl(fd, F_DUPFD_CLOEXEC, 50);
    struct flock lock = {0};
    lock.l_type = F_WRLCK;
    lock.l_whence = SEEK_SET;
    lock.l_start = 0;
    lock.l_len = 4;
    int locked = fcntl(fd, F_SETLK, &lock);
    struct flock query = {0};
    query.l_type = F_RDLCK;
    query.l_whence = SEEK_SET;
    query.l_len = 4;
    fcntl(fd, F_GETLK, &query);
    char gotPath[PATH_MAX] = {0};
    int pathResult = fcntl(fd, F_GETPATH, gotPath);
    say([NSString stringWithFormat:@"fcntl: access %d, nonblock %d append %d, dup >= 50 %d cloexec %d, setlk %d, getlk own lock %d, path %d %@",
         statusFlags & O_ACCMODE, (updated & O_NONBLOCK) != 0, (updated & O_APPEND) != 0, duplicate >= 50,
         fcntl(duplicate, F_GETFD) & FD_CLOEXEC, locked, query.l_type == F_UNLCK, pathResult,
         [@(gotPath) lastPathComponent]]);
    close(duplicate);

    ftruncate(fd, 5);
    lseek(fd, 0, SEEK_SET);
    memset(buffer, 0, sizeof(buffer));
    pread(fd, buffer, 5, 0);
    close(fd);
    rename(path(@"a.txt"), path(@"c.txt"));
    int exists = access(path(@"c.txt"), R_OK | W_OK);
    int missing = access(path(@"a.txt"), F_OK);
    say([NSString stringWithFormat:@"files: truncated '%s', renamed %d, old %d errno %d", buffer, exists, missing, errno]);

    unlink(path(@"c.txt"));
    unlink(path(@"b.dat"));
    unlink(path(@"link"));
    rmdir(path(@"sub"));
    close(dirfd);
    int removed = rmdir(directory.fileSystemRepresentation);
    say([NSString stringWithFormat:@"cleanup: %d", removed]);
}

// MARK: - Descriptors

static void descriptors(void) {
    int pipeEnds[2];
    pipe(pipeEnds);
    fd_set readable;
    FD_ZERO(&readable);
    FD_SET(pipeEnds[0], &readable);
    struct timeval wait = {0, 20000};
    int none = select(pipeEnds[0] + 1, &readable, NULL, NULL, &wait);
    write(pipeEnds[1], "x", 1);
    FD_ZERO(&readable);
    FD_SET(pipeEnds[0], &readable);
    wait.tv_sec = 1;
    wait.tv_usec = 0;
    int one = select(pipeEnds[0] + 1, &readable, NULL, NULL, &wait);
    struct pollfd poller = {pipeEnds[0], POLLIN | POLLRDNORM, 0};
    int polled = poll(&poller, 1, 100);
    say([NSString stringWithFormat:@"select: %d then %d set %d; poll %d in %d rdnorm %d", none, one,
         FD_ISSET(pipeEnds[0], &readable) != 0, polled, (poller.revents & POLLIN) != 0, (poller.revents & POLLRDNORM) != 0]);

    int pair[2];
    socketpair(AF_UNIX, SOCK_STREAM, 0, pair);
    char text[] = "fd attached";
    struct iovec vector = {text, sizeof(text)};
    char control[CMSG_SPACE(sizeof(int))];
    memset(control, 0, sizeof(control));
    struct msghdr message = {0};
    message.msg_iov = &vector;
    message.msg_iovlen = 1;
    message.msg_control = control;
    message.msg_controllen = sizeof(control);
    struct cmsghdr *header = CMSG_FIRSTHDR(&message);
    header->cmsg_level = SOL_SOCKET;
    header->cmsg_type = SCM_RIGHTS;
    header->cmsg_len = CMSG_LEN(sizeof(int));
    memcpy(CMSG_DATA(header), &pipeEnds[1], sizeof(int));
    ssize_t sent = sendmsg(pair[0], &message, 0);

    char received[64] = {0};
    struct iovec into = {received, sizeof(received)};
    char incoming[CMSG_SPACE(sizeof(int))];
    struct msghdr reply = {0};
    reply.msg_iov = &into;
    reply.msg_iovlen = 1;
    reply.msg_control = incoming;
    reply.msg_controllen = sizeof(incoming);
    ssize_t got = recvmsg(pair[1], &reply, 0);
    struct cmsghdr *arrived = CMSG_FIRSTHDR(&reply);
    int passed = -1;
    if (arrived && arrived->cmsg_type == SCM_RIGHTS) memcpy(&passed, CMSG_DATA(arrived), sizeof(int));
    write(passed, "y", 1);
    char drained[4] = {0};
    read(pipeEnds[0], drained, 2);
    say([NSString stringWithFormat:@"sendmsg: sent %zd got %zd '%s', control %u level %d, passed fd works '%s'", sent, got,
         received, (unsigned)reply.msg_controllen, arrived ? arrived->cmsg_level == SOL_SOCKET : -1, drained]);

    struct timeval timeout = {0, 50000};
    setsockopt(pair[1], SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    struct timeval readBack = {0};
    socklen_t length = sizeof(readBack);
    getsockopt(pair[1], SOL_SOCKET, SO_RCVTIMEO, &readBack, &length);
    ssize_t timedRead = recv(pair[1], received, sizeof(received), 0);
    say([NSString stringWithFormat:@"timeouts: %ld.%06d, recv %zd errno %d (EAGAIN %d)", (long)readBack.tv_sec,
         readBack.tv_usec, timedRead, errno, EAGAIN]);
    close(pair[0]);
    close(pair[1]);
    close(pipeEnds[0]);
    close(pipeEnds[1]);
    close(passed);
}

// MARK: - System

static void system_(void) {
    struct timespec monotonic, realtime, raw, uptime;
    clock_gettime(CLOCK_MONOTONIC, &monotonic);
    clock_gettime(CLOCK_REALTIME, &realtime);
    clock_gettime(CLOCK_MONOTONIC_RAW, &raw);
    clock_gettime(CLOCK_UPTIME_RAW, &uptime);
    uint64_t start = mach_absolute_time();
    struct timespec nap = {0, 20000000};
    nanosleep(&nap, NULL);
    uint64_t end = mach_absolute_time();
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    uint64_t nanoseconds = (end - start) * timebase.numer / timebase.denom;
    uint64_t slept = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - (uint64_t)uptime.tv_sec * 1000000000ull - (uint64_t)uptime.tv_nsec;
    struct timeval day;
    gettimeofday(&day, NULL);
    say([NSString stringWithFormat:@"clocks: realtime matches %d, monotonic %d, slept %d %d, usec range %d",
         llabs((long long)realtime.tv_sec - (long long)time(NULL)) <= 1, monotonic.tv_sec >= 0 && raw.tv_sec >= 0,
         nanoseconds >= 20000000 && nanoseconds < 500000000, slept >= 20000000, day.tv_usec >= 0 && day.tv_usec < 1000000]);

    size_t page = (size_t)getpagesize();
    char *anonymous = mmap(NULL, page * 2, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
    strcpy(anonymous + page, "mapped");
    int synced = msync(anonymous, page, MS_SYNC);
    int advised = madvise(anonymous, page, MADV_FREE);
    int protectedResult = mprotect(anonymous, page, PROT_READ);
    NSString *contents = @(anonymous + page);
    int unmapped = munmap(anonymous, page * 2);
    say([NSString stringWithFormat:@"mmap: %d '%@', msync %d, madvise %d, mprotect %d, munmap %d",
         anonymous != MAP_FAILED, contents, synced, advised, protectedResult, unmapped]);

    struct utsname names;
    uname(&names);
    say([NSString stringWithFormat:@"uname: sysname %d, machine %d, release %d", strlen(names.sysname) > 0,
         strlen(names.machine) > 0, strlen(names.release) > 0]);
    say([NSString stringWithFormat:@"sysconf: processors %d %d, page %d, open max %d, ticks %ld",
         sysconf(_SC_NPROCESSORS_ONLN) > 0, sysconf(_SC_NPROCESSORS_CONF) >= sysconf(_SC_NPROCESSORS_ONLN),
         sysconf(_SC_PAGESIZE) == (long)page, sysconf(_SC_OPEN_MAX) > 0, sysconf(_SC_CLK_TCK)]);

    uint8_t bytes[32] = {0};
    arc4random_buf(bytes, sizeof(bytes));
    int nonzero = 0;
    for (int i = 0; i < 32; i++) nonzero += bytes[i] != 0;
    uint32_t bounded = 1;
    for (int i = 0; i < 100; i++) bounded &= arc4random_uniform(10) < 10;
    say([NSString stringWithFormat:@"random: buffer filled %d, uniform bounded %d, arc4random %d", nonzero > 20, bounded,
         arc4random() != arc4random()]);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        threads();
        files();
        descriptors();
        system_();
    }
    return 0;
}
