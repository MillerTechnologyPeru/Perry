// Minimal Darwin libc declarations for test fixtures. There is no Apple SDK
// in the build environment, so fixtures declare what they use here and link
// against sdk/libSystem.tbd.
#ifndef FIXTURE_DARWIN_H
#define FIXTURE_DARWIN_H

typedef unsigned long size_t;
typedef __builtin_va_list va_list;
#define va_start(ap, last) __builtin_va_start(ap, last)
#define va_end(ap) __builtin_va_end(ap)
#define NULL ((void *)0)

typedef struct __sFILE FILE;
extern FILE *__stdoutp;
extern FILE *__stderrp;
#define stdout __stdoutp
#define stderr __stderrp

int printf(const char *, ...);
int fprintf(FILE *, const char *, ...);
int snprintf(char *, size_t, const char *, ...);
int vsnprintf(char *, size_t, const char *, va_list);
int puts(const char *);
int fflush(FILE *);
FILE *fopen(const char *, const char *);

long strtol(const char *, char **, int);
size_t strlen(const char *);
int strcmp(const char *, const char *);
char *strerror(int);
void *malloc(size_t);
void free(void *);
void exit(int) __attribute__((noreturn));

int *__error(void);
#define errno (*__error())
#define ENOENT 2
#define ERANGE 34

#endif
