// Darwin's FILE. Darwin's stdio macros (getc_unlocked, putc_unlocked,
// feof_unlocked, fileno_unlocked, which compilers such as GCC use
// throughout) read and write a stream's fields themselves: its buffer
// pointer _p, its read and write counts _r and _w, its flags and its file
// descriptor. So a Mac program is given streams laid out as Darwin's
// struct __sFILE, each standing for a glibc stream. Their counts stay at
// zero, so every character goes through __srget and __swbuf, which read
// and write the glibc stream. Each stdio function that takes a stream finds
// the glibc one first. A glibc stream passed in from elsewhere is taken as
// it is.

#define _GNU_SOURCE
#include "PerrySystem.h"

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>

FILE *perry_fopen(const char *path, const char *mode);

typedef struct darwin_file {
    unsigned char *p;           // _p: the next character in the buffer
    int r;                      // _r: characters left to read in it
    int w;                      // _w: room left to write in it
    short flags;                // _flags: __SEOF and __SERR among them
    short file;                 // _file: the file descriptor
    struct { unsigned char *base; int size; } bf;
    int lbfsize;                // _lbfsize: 0, or -size when line buffered
    void *cookie;               // _cookie: the glibc stream, here
    int (*close)(void *);       // _close: marks a stream of Perry's
    int (*read)(void *, char *, int);
    int64_t (*seek)(void *, int64_t, int);
    int (*write)(void *, const char *, int);
    struct { unsigned char *base; int size; } ub;
    void *extra;
    int ur;
    unsigned char ubuf[3];
    unsigned char nbuf[1];
    struct { unsigned char *base; int size; } lb;
    int blksize;
    int64_t offset;
} darwin_file;

#if defined(__x86_64__) || defined(__aarch64__)
_Static_assert(sizeof(darwin_file) == 152, "Darwin's FILE is 152 bytes");
#endif

enum { DARWIN_SEOF = 0x0020, DARWIN_SERR = 0x0040 };

static int marker(void *cookie) { (void)cookie; return 0; }

// The glibc stream a stream given by a Mac program stands for.
FILE *perry_stdio_stream(FILE *stream) {
    darwin_file *file = (darwin_file *)stream;
    if (file && file->close == marker) return (FILE *)file->cookie;
    return stream;
}

static darwin_file *wrap(FILE *stream) {
    if (!stream) return NULL;
    darwin_file *file = calloc(1, sizeof *file);
    if (!file) return NULL;
    file->cookie = stream;
    file->close = marker;
    file->file = (short)fileno(stream);
    return file;
}

// The flags the macros read, after the glibc stream was used.
static void sync_flags(FILE *stream) {
    darwin_file *file = (darwin_file *)stream;
    if (!file || file->close != marker) return;
    FILE *real = file->cookie;
    file->flags = (short)((feof(real) ? DARWIN_SEOF : 0) | (ferror(real) ? DARWIN_SERR : 0));
    file->r = 0;
    file->w = 0;
}

#define REAL(stream) perry_stdio_stream(stream)

// MARK: - Standard streams

// Darwin declares `extern FILE *__stdinp` and friends.
FILE *darwin_stdinp DARWIN_SYMBOL(__stdinp);
FILE *darwin_stdoutp DARWIN_SYMBOL(__stdoutp);
FILE *darwin_stderrp DARWIN_SYMBOL(__stderrp);

__attribute__((constructor)) static void init_streams(void) {
    darwin_stdinp = (FILE *)wrap(stdin);
    darwin_stdoutp = (FILE *)wrap(stdout);
    darwin_stderrp = (FILE *)wrap(stderr);
}

// MARK: - The macros' slow paths

// getc's, when the buffer is empty (always, here).
int darwin_srget(FILE *stream) DARWIN_SYMBOL(__srget);
int darwin_srget(FILE *stream) {
    int c = getc(REAL(stream));
    sync_flags(stream);
    return c;
}

// putc's, when the buffer is full (always, here).
int darwin_swbuf(int c, FILE *stream) DARWIN_SYMBOL(__swbuf);
int darwin_swbuf(int c, FILE *stream) {
    int result = putc(c, REAL(stream));
    sync_flags(stream);
    return result;
}

// MARK: - Opening and closing

FILE *darwin_fopen(const char *path, const char *mode) DARWIN_SYMBOL(fopen);
FILE *darwin_fopen(const char *path, const char *mode) { return (FILE *)wrap(perry_fopen(path, mode)); }

FILE *darwin_fopen_extsn(const char *path, const char *mode) __asm__("_fopen$DARWIN_EXTSN");
FILE *darwin_fopen_extsn(const char *path, const char *mode) { return darwin_fopen(path, mode); }

FILE *darwin_fdopen(int fd, const char *mode) DARWIN_SYMBOL(fdopen);
FILE *darwin_fdopen(int fd, const char *mode) { return (FILE *)wrap(fdopen(fd, mode)); }

// The same stream, now on the file at `path` (or `path` NULL: in a new mode).
FILE *darwin_freopen(const char *path, const char *mode, FILE *stream) DARWIN_SYMBOL(freopen);
FILE *darwin_freopen(const char *path, const char *mode, FILE *stream) {
    FILE *real = freopen(path, mode, REAL(stream));
    if (!real) return NULL;
    darwin_file *file = (darwin_file *)stream;
    if (file && file->close == marker) {
        file->cookie = real;
        file->file = (short)fileno(real);
        sync_flags(stream);
        return stream;
    }
    return (FILE *)wrap(real);
}

FILE *darwin_popen(const char *command, const char *mode) DARWIN_SYMBOL(popen);
FILE *darwin_popen(const char *command, const char *mode) { return (FILE *)wrap(popen(command, mode)); }

int darwin_pclose(FILE *stream) DARWIN_SYMBOL(pclose);
int darwin_pclose(FILE *stream) {
    FILE *real = REAL(stream);
    if (real != stream) free(stream);
    return pclose(real);
}

FILE *darwin_tmpfile(void) DARWIN_SYMBOL(tmpfile);
FILE *darwin_tmpfile(void) { return (FILE *)wrap(tmpfile()); }

// Closing no stream: Darwin's fclose fails with EFAULT, where glibc's reads
// the stream it wasn't given. Destructors of file classes rely on it.
int darwin_fclose(FILE *stream) DARWIN_SYMBOL(fclose);
int darwin_fclose(FILE *stream) {
    if (stream == NULL) {
        errno = EFAULT;
        return EOF;
    }
    FILE *real = REAL(stream);
    // The standard streams' stand-ins stay, closed or not.
    if (real != stream && stream != darwin_stdinp && stream != darwin_stdoutp && stream != darwin_stderrp) free(stream);
    return fclose(real);
}

// MARK: - Reading and writing

#define STREAM_FUNCTION(type, name, params, call) \
    type darwin_##name params DARWIN_SYMBOL(name); \
    type darwin_##name params { type result = call; sync_flags(stream); return result; }

STREAM_FUNCTION(int, fgetc, (FILE *stream), fgetc(REAL(stream)))
STREAM_FUNCTION(int, getc, (FILE *stream), getc(REAL(stream)))
STREAM_FUNCTION(int, getc_unlocked, (FILE *stream), getc_unlocked(REAL(stream)))
STREAM_FUNCTION(int, fputc, (int c, FILE *stream), fputc(c, REAL(stream)))
STREAM_FUNCTION(int, putc, (int c, FILE *stream), putc(c, REAL(stream)))
STREAM_FUNCTION(int, putc_unlocked, (int c, FILE *stream), putc_unlocked(c, REAL(stream)))
STREAM_FUNCTION(int, ungetc, (int c, FILE *stream), ungetc(c, REAL(stream)))
STREAM_FUNCTION(int, fputs, (const char *s, FILE *stream), fputs(s, REAL(stream)))
STREAM_FUNCTION(char *, fgets, (char *s, int size, FILE *stream), fgets(s, size, REAL(stream)))
STREAM_FUNCTION(size_t, fwrite, (const void *p, size_t size, size_t count, FILE *stream), fwrite(p, size, count, REAL(stream)))
STREAM_FUNCTION(size_t, fread, (void *p, size_t size, size_t count, FILE *stream), fread(p, size, count, REAL(stream)))
STREAM_FUNCTION(ssize_t, getline, (char **line, size_t *size, FILE *stream), getline(line, size, REAL(stream)))
STREAM_FUNCTION(ssize_t, getdelim, (char **line, size_t *size, int delimiter, FILE *stream), getdelim(line, size, delimiter, REAL(stream)))
STREAM_FUNCTION(int, fseek, (FILE *stream, long offset, int whence), fseek(REAL(stream), offset, whence))
STREAM_FUNCTION(long, ftell, (FILE *stream), ftell(REAL(stream)))
STREAM_FUNCTION(int, fseeko, (FILE *stream, off_t offset, int whence), fseeko(REAL(stream), offset, whence))
STREAM_FUNCTION(off_t, ftello, (FILE *stream), ftello(REAL(stream)))
STREAM_FUNCTION(int, feof, (FILE *stream), feof(REAL(stream)))
STREAM_FUNCTION(int, ferror, (FILE *stream), ferror(REAL(stream)))
STREAM_FUNCTION(int, fileno, (FILE *stream), fileno(REAL(stream)))
STREAM_FUNCTION(int, setvbuf, (FILE *stream, char *buffer, int mode, size_t size), setvbuf(REAL(stream), buffer, mode, size))

// fflush(NULL) flushes every stream.
int darwin_fflush(FILE *stream) DARWIN_SYMBOL(fflush);
int darwin_fflush(FILE *stream) { return fflush(stream ? REAL(stream) : NULL); }

void darwin_clearerr(FILE *stream) DARWIN_SYMBOL(clearerr);
void darwin_clearerr(FILE *stream) { clearerr(REAL(stream)); sync_flags(stream); }

void darwin_rewind(FILE *stream) DARWIN_SYMBOL(rewind);
void darwin_rewind(FILE *stream) { rewind(REAL(stream)); sync_flags(stream); }

void darwin_setbuf(FILE *stream, char *buffer) DARWIN_SYMBOL(setbuf);
void darwin_setbuf(FILE *stream, char *buffer) { setbuf(REAL(stream), buffer); }

void darwin_setlinebuf(FILE *stream) DARWIN_SYMBOL(setlinebuf);
void darwin_setlinebuf(FILE *stream) { setlinebuf(REAL(stream)); }

void darwin_flockfile(FILE *stream) DARWIN_SYMBOL(flockfile);
void darwin_flockfile(FILE *stream) { flockfile(REAL(stream)); }

void darwin_funlockfile(FILE *stream) DARWIN_SYMBOL(funlockfile);
void darwin_funlockfile(FILE *stream) { funlockfile(REAL(stream)); }

int darwin_ftrylockfile(FILE *stream) DARWIN_SYMBOL(ftrylockfile);
int darwin_ftrylockfile(FILE *stream) { return ftrylockfile(REAL(stream)); }

// A stream's position: Darwin's fpos_t is an offset, glibc's a structure.
int darwin_fgetpos(FILE *stream, int64_t *position) DARWIN_SYMBOL(fgetpos);
int darwin_fgetpos(FILE *stream, int64_t *position) {
    off_t offset = ftello(REAL(stream));
    if (offset < 0) return -1;
    *position = offset;
    return 0;
}

int darwin_fsetpos(FILE *stream, const int64_t *position) DARWIN_SYMBOL(fsetpos);
int darwin_fsetpos(FILE *stream, const int64_t *position) {
    int result = fseeko(REAL(stream), (off_t)*position, SEEK_SET);
    sync_flags(stream);
    return result;
}

void darwin_setbuffer(FILE *stream, char *buffer, int size) DARWIN_SYMBOL(setbuffer);
void darwin_setbuffer(FILE *stream, char *buffer, int size) {
    setvbuf(REAL(stream), buffer, buffer ? _IOFBF : _IONBF, buffer ? (size_t)size : 0);
}
