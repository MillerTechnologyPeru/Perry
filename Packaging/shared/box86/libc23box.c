// glibc functions box86's libc bridge lacks, for i386 Perry built against
// glibc 2.38 or newer, as the older names box86 does wrap. Preloaded with
// BOX86_LD_PRELOAD; libc23box.map gives each its glibc version, which the
// libraries asking for it name.
#include <stdarg.h>
#include <stdio.h>
#include <wchar.h>

unsigned long strtoul(const char *, char **, int);
int __isoc99_vfscanf(FILE *, const char *, va_list);
int __isoc99_vscanf(const char *, va_list);
int __isoc99_vsscanf(const char *, const char *, va_list);
int __isoc99_vswscanf(const wchar_t *, const wchar_t *, va_list);

// C23's scanf and strtol families, which take 0b numbers: as C99's.
unsigned long __isoc23_strtoul(const char *s, char **e, int b) { return strtoul(s, e, b); }
int __isoc23_vfscanf(FILE *f, const char *t, va_list a) { return __isoc99_vfscanf(f, t, a); }
int __isoc23_vscanf(const char *t, va_list a) { return __isoc99_vscanf(t, a); }
int __isoc23_vsscanf(const char *s, const char *t, va_list a) { return __isoc99_vsscanf(s, t, a); }
int __isoc23_vswscanf(const wchar_t *s, const wchar_t *t, va_list a) { return __isoc99_vswscanf(s, t, a); }

// capget and capset, for the i386 libcap where no native one is installed:
// the i386 system calls.
long syscall(long, ...);
int capget(void *header, void *data) { return (int)syscall(184, header, data); }
int capset(void *header, const void *data) { return (int)syscall(185, header, data); }
