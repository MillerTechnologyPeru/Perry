// Darwin errno over glibc errno.
//
// Darwin code reads and writes errno through the pointer returned by
// __error(). Values differ from Linux above 34 (and for EAGAIN/EDEADLK), so
// each thread keeps a Darwin-numbered copy that is synchronised with glibc's
// errno whenever __error() is called.

#include "PerrySystem.h"

#include <errno.h>
#include <stddef.h>

static const struct { int linux_value, darwin_value; } errno_map[] = {
    { EPERM, 1 }, { ENOENT, 2 }, { ESRCH, 3 }, { EINTR, 4 }, { EIO, 5 }, { ENXIO, 6 },
    { E2BIG, 7 }, { ENOEXEC, 8 }, { EBADF, 9 }, { ECHILD, 10 }, { EDEADLK, 11 },
    { ENOMEM, 12 }, { EACCES, 13 }, { EFAULT, 14 }, { ENOTBLK, 15 }, { EBUSY, 16 },
    { EEXIST, 17 }, { EXDEV, 18 }, { ENODEV, 19 }, { ENOTDIR, 20 }, { EISDIR, 21 },
    { EINVAL, 22 }, { ENFILE, 23 }, { EMFILE, 24 }, { ENOTTY, 25 }, { ETXTBSY, 26 },
    { EFBIG, 27 }, { ENOSPC, 28 }, { ESPIPE, 29 }, { EROFS, 30 }, { EMLINK, 31 },
    { EPIPE, 32 }, { EDOM, 33 }, { ERANGE, 34 }, { EAGAIN, 35 }, { EINPROGRESS, 36 },
    { EALREADY, 37 }, { ENOTSOCK, 38 }, { EDESTADDRREQ, 39 }, { EMSGSIZE, 40 },
    { EPROTOTYPE, 41 }, { ENOPROTOOPT, 42 }, { EPROTONOSUPPORT, 43 },
    { ESOCKTNOSUPPORT, 44 }, { ENOTSUP, 45 }, { EPFNOSUPPORT, 46 }, { EAFNOSUPPORT, 47 },
    { EADDRINUSE, 48 }, { EADDRNOTAVAIL, 49 }, { ENETDOWN, 50 }, { ENETUNREACH, 51 },
    { ENETRESET, 52 }, { ECONNABORTED, 53 }, { ECONNRESET, 54 }, { ENOBUFS, 55 },
    { EISCONN, 56 }, { ENOTCONN, 57 }, { ESHUTDOWN, 58 }, { ETOOMANYREFS, 59 },
    { ETIMEDOUT, 60 }, { ECONNREFUSED, 61 }, { ELOOP, 62 }, { ENAMETOOLONG, 63 },
    { EHOSTDOWN, 64 }, { EHOSTUNREACH, 65 }, { ENOTEMPTY, 66 }, { EUSERS, 68 },
    { EDQUOT, 69 }, { ESTALE, 70 }, { EREMOTE, 71 }, { ENOLCK, 77 }, { ENOSYS, 78 },
    { EOVERFLOW, 84 }, { ECANCELED, 89 }, { EIDRM, 90 }, { ENOMSG, 91 }, { EILSEQ, 92 },
    { EBADMSG, 94 }, { EMULTIHOP, 95 }, { ENODATA, 96 }, { ENOLINK, 97 }, { ENOSR, 98 },
    { ENOSTR, 99 }, { EPROTO, 100 }, { ETIME, 101 }, { ENOTRECOVERABLE, 104 },
    { EOWNERDEAD, 105 },
};

#define ERRNO_MAP_COUNT (sizeof(errno_map) / sizeof(errno_map[0]))

int perry_darwin_errno_from_linux(int value) {
    if (value == 0)
        return 0;
    // On Linux EOPNOTSUPP == ENOTSUP; Darwin has both, ENOTSUP is the usual one.
    for (size_t i = 0; i < ERRNO_MAP_COUNT; i++)
        if (errno_map[i].linux_value == value)
            return errno_map[i].darwin_value;
    return 22; // EINVAL
}

int perry_linux_errno_from_darwin(int value) {
    if (value == 0)
        return 0;
    if (value == 102) // EOPNOTSUPP
        return EOPNOTSUPP;
    for (size_t i = 0; i < ERRNO_MAP_COUNT; i++)
        if (errno_map[i].darwin_value == value)
            return errno_map[i].linux_value;
    return EINVAL;
}

static _Thread_local struct {
    int darwin;             // the value Darwin code sees and writes
    int published_darwin;   // what __error() last stored in `darwin`
    int published_linux;    // glibc errno at that time
} state;

int *darwin_error(void) {
    if (errno != state.published_linux) {
        // glibc changed errno since the last call: it wins.
        state.darwin = perry_darwin_errno_from_linux(errno);
    } else if (state.darwin != state.published_darwin) {
        // Darwin code wrote errno (typically `errno = 0`): propagate it.
        errno = perry_linux_errno_from_darwin(state.darwin);
    }
    state.published_darwin = state.darwin;
    state.published_linux = errno;
    return &state.darwin;
}
