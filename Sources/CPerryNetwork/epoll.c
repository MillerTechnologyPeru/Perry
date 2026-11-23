#include "CPerryNetwork.h"

#include <stddef.h>
#include <sys/epoll.h>

int perry_epoll_create(void) { return epoll_create1(EPOLL_CLOEXEC); }

int perry_epoll_watch(int epoll, int fd, int add, uint32_t events, uint64_t data) {
    struct epoll_event event = { .events = events | EPOLLONESHOT, .data.u64 = data };
    return epoll_ctl(epoll, add ? EPOLL_CTL_ADD : EPOLL_CTL_MOD, fd, &event);
}

int perry_epoll_remove(int epoll, int fd) { return epoll_ctl(epoll, EPOLL_CTL_DEL, fd, NULL); }

int perry_epoll_wait(int epoll, perry_epoll_event *events, int count) {
    struct epoll_event kernel[64];
    if (count > 64)
        count = 64;
    int ready = epoll_wait(epoll, kernel, count, -1);
    for (int i = 0; i < ready; i++) {
        events[i].events = kernel[i].events;
        events[i].data = kernel[i].data.u64;
    }
    return ready;
}
