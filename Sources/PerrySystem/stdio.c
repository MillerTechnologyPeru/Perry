// Darwin stdio: standard stream variables and va_list functions.

#define _GNU_SOURCE
#include "PerrySystem.h"

#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include <wchar.h>

// MARK: - Standard streams

// Darwin declares `extern FILE *__stdinp` and friends. Darwin code only uses
// FILE * opaquely through functions, so glibc streams are handed out as-is.
FILE *darwin_stdinp DARWIN_SYMBOL(__stdinp);
FILE *darwin_stdoutp DARWIN_SYMBOL(__stdoutp);
FILE *darwin_stderrp DARWIN_SYMBOL(__stderrp);

__attribute__((constructor)) static void init_streams(void) {
    darwin_stdinp = stdin;
    darwin_stdoutp = stdout;
    darwin_stderrp = stderr;
}

// MARK: - Darwin va_list

// A Darwin arm64 va_list is a pointer to 8-byte stack slots. An AAPCS64
// va_list with empty register save areas reads the same slots.
typedef struct aapcs64_va_list {
    void *stack;
    void *gr_top;
    void *vr_top;
    int gr_offs;
    int vr_offs;
} aapcs64_va_list;

_Static_assert(sizeof(aapcs64_va_list) == sizeof(va_list), "unexpected va_list layout");

#define DARWIN_VA(name, darwin_ap) \
    va_list name; \
    do { \
        aapcs64_va_list tmp_ = { (darwin_ap), NULL, NULL, 0, 0 }; \
        memcpy(&name, &tmp_, sizeof(name)); \
    } while (0)

typedef void *darwin_va_list;

int darwin_vprintf(const char *fmt, darwin_va_list ap) DARWIN_SYMBOL(vprintf);
int darwin_vprintf(const char *fmt, darwin_va_list ap) {
    DARWIN_VA(va, ap);
    return vprintf(fmt, va);
}

int darwin_vfprintf(FILE *f, const char *fmt, darwin_va_list ap) DARWIN_SYMBOL(vfprintf);
int darwin_vfprintf(FILE *f, const char *fmt, darwin_va_list ap) {
    DARWIN_VA(va, ap);
    return vfprintf(f, fmt, va);
}

int darwin_vdprintf(int fd, const char *fmt, darwin_va_list ap) DARWIN_SYMBOL(vdprintf);
int darwin_vdprintf(int fd, const char *fmt, darwin_va_list ap) {
    DARWIN_VA(va, ap);
    return vdprintf(fd, fmt, va);
}

// Formatting into a string that is also one of the strings formatted, as in
// snprintf(path, size, "%s.%s", path, "bin"): Darwin's gives the text the
// arguments had when it was called, which programs lean on (Monopoly names
// its particle files so), where glibc's clears the destination before it
// reads them. So the text is made elsewhere, then copied in.

int perry_vsnprintf(char *buf, size_t size, const char *fmt, va_list arguments) {
    char local[512];
    char *text = local;
    va_list again;
    va_copy(again, arguments);
    int length = vsnprintf(local, sizeof local, fmt, arguments);
    if (length >= (int)sizeof local) {
        text = malloc((size_t)length + 1);
        if (!text) {
            va_end(again);
            return -1;
        }
        vsnprintf(text, (size_t)length + 1, fmt, again);
    }
    va_end(again);
    if (length >= 0 && size > 0 && buf) {
        size_t copied = (size_t)length < size - 1 ? (size_t)length : size - 1;
        memmove(buf, text, copied);
        buf[copied] = 0;
    }
    if (text != local) free(text);
    return length;
}

int perry_vsprintf(char *buf, const char *fmt, va_list arguments) { return perry_vsnprintf(buf, SIZE_MAX, fmt, arguments); }

// The checked forms, which the compiler calls with the destination's size
// when it knows it (-1 when it doesn't): the text is cut to fit, where
// Darwin's would abort.

int perry_vsprintf_chk(char *buf, int flag, size_t slen, const char *fmt, va_list arguments) {
    (void)flag;
    return perry_vsnprintf(buf, slen, fmt, arguments);
}

int perry_vsnprintf_chk(char *buf, size_t maxlen, int flag, size_t slen, const char *fmt, va_list arguments) {
    (void)flag;
    return perry_vsnprintf(buf, maxlen < slen ? maxlen : slen, fmt, arguments);
}

int darwin_vsprintf(char *buf, const char *fmt, darwin_va_list ap) DARWIN_SYMBOL(vsprintf);
int darwin_vsprintf(char *buf, const char *fmt, darwin_va_list ap) {
    DARWIN_VA(va, ap);
    return perry_vsprintf(buf, fmt, va);
}

int darwin_vsnprintf(char *buf, size_t size, const char *fmt, darwin_va_list ap) DARWIN_SYMBOL(vsnprintf);
int darwin_vsnprintf(char *buf, size_t size, const char *fmt, darwin_va_list ap) {
    DARWIN_VA(va, ap);
    return perry_vsnprintf(buf, size, fmt, va);
}

int darwin_vswprintf(wchar_t *buf, size_t size, const wchar_t *fmt, darwin_va_list ap) DARWIN_SYMBOL(vswprintf);
int darwin_vswprintf(wchar_t *buf, size_t size, const wchar_t *fmt, darwin_va_list ap) {
    DARWIN_VA(va, ap);
    return vswprintf(buf, size, fmt, va);
}

int darwin_vasprintf(char **out, const char *fmt, darwin_va_list ap) DARWIN_SYMBOL(vasprintf);
int darwin_vasprintf(char **out, const char *fmt, darwin_va_list ap) {
    DARWIN_VA(va, ap);
    return vasprintf(out, fmt, va);
}

int darwin_vscanf(const char *fmt, darwin_va_list ap) DARWIN_SYMBOL(vscanf);
int darwin_vscanf(const char *fmt, darwin_va_list ap) {
    DARWIN_VA(va, ap);
    return vscanf(fmt, va);
}

int darwin_vfscanf(FILE *f, const char *fmt, darwin_va_list ap) DARWIN_SYMBOL(vfscanf);
int darwin_vfscanf(FILE *f, const char *fmt, darwin_va_list ap) {
    DARWIN_VA(va, ap);
    return vfscanf(f, fmt, va);
}

int darwin_vsscanf(const char *str, const char *fmt, darwin_va_list ap) DARWIN_SYMBOL(vsscanf);
int darwin_vsscanf(const char *str, const char *fmt, darwin_va_list ap) {
    DARWIN_VA(va, ap);
    return vsscanf(str, fmt, va);
}

void darwin_vsyslog(int priority, const char *fmt, darwin_va_list ap) DARWIN_SYMBOL(vsyslog);
void darwin_vsyslog(int priority, const char *fmt, darwin_va_list ap) {
    DARWIN_VA(va, ap);
    vsyslog(priority, fmt, va);
}

int darwin_vsprintf_chk(char *buf, int flag, size_t slen, const char *fmt, darwin_va_list ap) DARWIN_SYMBOL(__vsprintf_chk);
int darwin_vsprintf_chk(char *buf, int flag, size_t slen, const char *fmt, darwin_va_list ap) {
    DARWIN_VA(va, ap);
    return perry_vsprintf_chk(buf, flag, slen, fmt, va);
}

int darwin_vsnprintf_chk(char *buf, size_t maxlen, int flag, size_t slen, const char *fmt, darwin_va_list ap)
    DARWIN_SYMBOL(__vsnprintf_chk);
int darwin_vsnprintf_chk(char *buf, size_t maxlen, int flag, size_t slen, const char *fmt, darwin_va_list ap) {
    DARWIN_VA(va, ap);
    return perry_vsnprintf_chk(buf, maxlen, flag, slen, fmt, va);
}

// MARK: - Errors

char *darwin_strerror(int darwin_errno) DARWIN_SYMBOL(strerror);
char *darwin_strerror(int darwin_errno) {
    return strerror(perry_linux_errno_from_darwin(darwin_errno));
}

void darwin_perror(const char *prefix) DARWIN_SYMBOL(perror);
void darwin_perror(const char *prefix) {
    const char *message = darwin_strerror(*darwin_error());
    if (prefix && *prefix)
        fprintf(stderr, "%s: %s\n", prefix, message);
    else
        fprintf(stderr, "%s\n", message);
}

// MARK: - %p

// Darwin prints pointers as 0x followed by lowercase hex, "0x0" for NULL,
// where glibc prints "(nil)". glibc's printf takes a handler for the
// conversion, which every printf function then uses.
#include <printf.h>

static int darwin_pointer(FILE *stream, const struct printf_info *info, const void *const *args) {
    const void *pointer = *(const void *const *)args[0];
    char digits[32];
    snprintf(digits, sizeof(digits), "0x%lx", (unsigned long)pointer);
    return fprintf(stream, info->left ? "%-*s" : "%*s", info->width, digits);
}

static int darwin_pointer_arguments(const struct printf_info *info, size_t count, int *types, int *sizes) {
    if (count > 0) types[0] = PA_POINTER;
    return 1;
}

__attribute__((constructor)) static void init_pointer_conversion(void) {
    register_printf_specifier('p', darwin_pointer, darwin_pointer_arguments);
}

// snprintf_l's body: the C locale's formatting, whatever locale is given.
int perry_vsnprintf_l(char *buf, size_t size, void *locale, const char *fmt, va_list arguments) {
    (void)locale;
    return perry_vsnprintf(buf, size, fmt, arguments);
}

// putc's slow path, which Darwin's putc macro calls when the buffer fills.
int darwin_swbuf(int c, FILE *f) DARWIN_SYMBOL(__swbuf);
int darwin_swbuf(int c, FILE *f) { return fputc(c, f); }
