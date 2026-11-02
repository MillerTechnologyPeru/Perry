// libPerryiconv: the provider for /usr/lib/libiconv.2.dylib.
//
// Darwin's iconv is a separate library; glibc's is part of libc, so this
// provider defines the API itself rather than binding by name, which would
// let any libc symbol through. The conversion handle is opaque and the
// calls have the same ABI, so iconv_open, iconv and iconv_close call
// glibc's; errno comes back in Darwin's numbering through libSystem.
// Encoding names are glibc's, which know Darwin's common ones; UTF-8-MAC
// (decomposed UTF-8) is not among them.

#define _GNU_SOURCE
#include "PerryIconv.h"

#include <errno.h>
#include <iconv.h>
#include <stddef.h>

#define DARWIN_SYMBOL(name) __asm__("_" #name) __attribute__((visibility("default"), used))

iconv_t darwin_iconv_open(const char *to, const char *from) DARWIN_SYMBOL(iconv_open);
size_t darwin_iconv(iconv_t cd, char **in, size_t *in_left, char **out, size_t *out_left) DARWIN_SYMBOL(iconv);
int darwin_iconv_close(iconv_t cd) DARWIN_SYMBOL(iconv_close);
int darwin_iconvctl(iconv_t cd, int request, void *argument) DARWIN_SYMBOL(iconvctl);

iconv_t darwin_iconv_open(const char *to, const char *from) {
    return iconv_open(to, from);
}

size_t darwin_iconv(iconv_t cd, char **in, size_t *in_left, char **out, size_t *out_left) {
    return iconv(cd, in, in_left, out, out_left);
}

int darwin_iconv_close(iconv_t cd) {
    return iconv_close(cd);
}

// iconvctl requests, from Darwin's <iconv.h>.
enum {
    ICONV_TRIVIALP = 0,
    ICONV_GET_TRANSLITERATE = 1,
    ICONV_SET_TRANSLITERATE = 2,
    ICONV_GET_DISCARD_ILSEQ = 3,
    ICONV_SET_DISCARD_ILSEQ = 4,
};

/// glibc fixes transliteration and discarding when the converter is opened
/// (the //TRANSLIT and //IGNORE suffixes), so this reports them off and
/// refuses to change them; other requests are unsupported.
int darwin_iconvctl(iconv_t cd, int request, void *argument) {
    if (cd == (iconv_t)-1) {
        errno = EBADF;
        return -1;
    }
    switch (request) {
    case ICONV_TRIVIALP:
    case ICONV_GET_TRANSLITERATE:
    case ICONV_GET_DISCARD_ILSEQ:
        if (argument)
            *(int *)argument = 0;
        return 0;
    default:
        errno = EINVAL;
        return -1;
    }
}
