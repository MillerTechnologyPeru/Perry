#ifndef CPERRY_NETWORK_H
#define CPERRY_NETWORK_H

// epoll for libPerryNetwork's socket thread, which Swift's Glibc module
// doesn't import. Events are copied out of the kernel's epoll_event, which
// is packed on x86_64, into a plain structure.

#include <stdint.h>

enum {
    PERRY_EPOLL_IN = 0x001,
    PERRY_EPOLL_OUT = 0x004,
    PERRY_EPOLL_ERR = 0x008,
    PERRY_EPOLL_HUP = 0x010,
};

typedef struct perry_epoll_event {
    uint32_t events;
    uint64_t data;
} perry_epoll_event;

/// A new epoll descriptor (close-on-exec), or -1.
int perry_epoll_create(void);

/// Adds `fd` (add != 0) or changes what it waits for, one-shot.
int perry_epoll_watch(int epoll, int fd, int add, uint32_t events, uint64_t data);

int perry_epoll_remove(int epoll, int fd);

/// Waits for up to `count` events; their number, or -1 with errno set.
int perry_epoll_wait(int epoll, perry_epoll_event *events, int count);

#endif
