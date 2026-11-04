// File times Swift's Glibc module does not expose.
#define _GNU_SOURCE
#include "CPerryFoundation.h"

#include <fcntl.h>
#include <sys/stat.h>

// When a file was made: its birth time, which statx gives where the file
// system keeps it. False when it does not.
bool perry_foundation_birth_time(const char *path, int64_t *seconds, uint32_t *nanoseconds) {
    struct statx info;
    if (statx(AT_FDCWD, path, AT_SYMLINK_NOFOLLOW, STATX_BTIME, &info) != 0 || !(info.stx_mask & STATX_BTIME))
        return false;
    *seconds = info.stx_btime.tv_sec;
    *nanoseconds = info.stx_btime.tv_nsec;
    return true;
}
