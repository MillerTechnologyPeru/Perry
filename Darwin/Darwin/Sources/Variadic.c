// The C library's variadic functions that Darwin's Swift API calls with a
// fixed extra argument: called from C, which passes that argument as a
// variadic one, in a register on x86_64 and on the stack on arm64. A Swift
// prototype with the argument fixed puts it in a register on both.
//
// Hidden: System.swift calls them, and nothing outside the library.

#include <fcntl.h>
#include <semaphore.h>
#include <sys/ioctl.h>

#define HIDDEN __attribute__((visibility("hidden")))

HIDDEN int _perry_open(const char *path, int oflag, unsigned mode) {
    return open(path, oflag, (int)mode);
}

HIDDEN int _perry_openat(int fd, const char *path, int oflag, unsigned mode) {
    return openat(fd, path, oflag, (int)mode);
}

HIDDEN int _perry_fcntl(int fd, int cmd, long value) {
    return fcntl(fd, cmd, value);
}

HIDDEN int _perry_ioctl(int fd, unsigned long request, long value) {
    return ioctl(fd, request, value);
}

HIDDEN sem_t *_perry_sem_open(const char *name, int oflag, unsigned mode, unsigned value) {
    return sem_open(name, oflag, (int)mode, value);
}
