// Assembly thunks between the Darwin arm64 ABI and glibc.

#if defined(__aarch64__) && defined(__ELF__)

// PASSTHROUGH darwin_name, glibc_name
//
// For functions whose Darwin and glibc ABIs are identical: a direct branch,
// so the Darwin symbol costs nothing over calling glibc.
.macro PASSTHROUGH name, target
    .globl \name
    .type \name, %function
    .p2align 2
\name:
    b \target
    .size \name, . - \name
.endm

// VARIADIC darwin_name, va_function, fixed_count
//
// Apple's arm64 ABI passes every variadic argument on the stack in 8-byte
// slots, while AAPCS64 (Linux) starts them in registers. This thunk builds
// an AAPCS64 va_list whose register save areas are empty (gr_offs and
// vr_offs are 0), so va_arg reads every argument from the caller's stack,
// then calls the glibc v* function with the va_list as the next argument.
// A va_list is a 32-byte struct and is passed by reference.
.macro VARIADIC name, target, nfixed
    .globl \name
    .type \name, %function
    .p2align 2
\name:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    add x9, sp, #48             // variadic arguments start at the caller's sp
    stp x9, xzr, [sp, #16]      // __stack, __gr_top
    stp xzr, xzr, [sp, #32]     // __vr_top, __gr_offs = 0, __vr_offs = 0
    add x\nfixed, sp, #16
    bl \target
    ldp x29, x30, [sp], #48
    ret
    .size \name, . - \name
.endm

.text

// MARK: - stdio
VARIADIC _printf, vprintf, 1
VARIADIC _fprintf, vfprintf, 2
VARIADIC _dprintf, vdprintf, 2
VARIADIC _sprintf, vsprintf, 2
VARIADIC _snprintf, vsnprintf, 3
VARIADIC _asprintf, vasprintf, 2
VARIADIC _scanf, vscanf, 1
VARIADIC _fscanf, vfscanf, 2
VARIADIC _sscanf, vsscanf, 2
VARIADIC ___sprintf_chk, __vsprintf_chk, 4
VARIADIC ___snprintf_chk, __vsnprintf_chk, 5
VARIADIC _syslog, vsyslog, 2

// The v* variants take a Darwin va_list (a plain pointer to stack slots)
// and are implemented in stdio.c.


// File descriptors, threads and sockets whose ABIs agree. Calls that take
// socket addresses or options are converted in sockets.c.
PASSTHROUGH _read, read
PASSTHROUGH _write, write
PASSTHROUGH _close, close
PASSTHROUGH _pread, pread
PASSTHROUGH _pwrite, pwrite
PASSTHROUGH _lseek, lseek
PASSTHROUGH _dup, dup
PASSTHROUGH _dup2, dup2
PASSTHROUGH _pipe, pipe
PASSTHROUGH _fsync, fsync
PASSTHROUGH _unlink, unlink
PASSTHROUGH _rmdir, rmdir
PASSTHROUGH _isatty, isatty
PASSTHROUGH _listen, listen
PASSTHROUGH _shutdown, shutdown
PASSTHROUGH _inet_addr, inet_addr
PASSTHROUGH _inet_ntoa, inet_ntoa
PASSTHROUGH _sched_yield, sched_yield
PASSTHROUGH _pthread_create, pthread_create
PASSTHROUGH _pthread_join, pthread_join
PASSTHROUGH _pthread_detach, pthread_detach
PASSTHROUGH _pthread_self, pthread_self
PASSTHROUGH _pthread_equal, pthread_equal
PASSTHROUGH _pthread_attr_init, pthread_attr_init
PASSTHROUGH _pthread_attr_destroy, pthread_attr_destroy
PASSTHROUGH _pthread_attr_setstacksize, pthread_attr_setstacksize
PASSTHROUGH _pthread_attr_getstacksize, pthread_attr_getstacksize
PASSTHROUGH _access, access
PASSTHROUGH _mkdir, mkdir
PASSTHROUGH _symlink, symlink
PASSTHROUGH _link, link
PASSTHROUGH _readlink, readlink
PASSTHROUGH _rename, rename
PASSTHROUGH _truncate, truncate
PASSTHROUGH _ftruncate, ftruncate
PASSTHROUGH _chmod, chmod
PASSTHROUGH _fchmod, fchmod
PASSTHROUGH _chown, chown
PASSTHROUGH _fchown, fchown
PASSTHROUGH _chdir, chdir
PASSTHROUGH _fchdir, fchdir
PASSTHROUGH _getcwd, getcwd
PASSTHROUGH _umask, umask
PASSTHROUGH _getpagesize, getpagesize
PASSTHROUGH _time, time
PASSTHROUGH _nanosleep, nanosleep
PASSTHROUGH _gettimeofday, gettimeofday
PASSTHROUGH _munmap, munmap
PASSTHROUGH _mprotect, mprotect
PASSTHROUGH _mlock, mlock
PASSTHROUGH _munlock, munlock
PASSTHROUGH _arc4random, arc4random
PASSTHROUGH _arc4random_buf, arc4random_buf
PASSTHROUGH _arc4random_uniform, arc4random_uniform

// open, openat and fcntl are variadic on Darwin.
VARIADIC _open, perry_vopen, 2
VARIADIC _openat, perry_vopenat, 3
VARIADIC _fcntl, perry_vfcntl, 2

// ___chkstk_darwin probes each page of a large stack frame, which Darwin
// needs below its guard pages; Linux grows stacks on its own.
    .globl ___chkstk_darwin
    .type ___chkstk_darwin, %function
    .p2align 2
___chkstk_darwin:
    ret
    .size ___chkstk_darwin, . - ___chkstk_darwin

PASSTHROUGH _puts, puts
PASSTHROUGH _putchar, putchar
PASSTHROUGH _fputs, fputs
PASSTHROUGH _fputc, fputc
PASSTHROUGH _putc, putc
PASSTHROUGH _fgetc, fgetc
PASSTHROUGH _getc, getc
PASSTHROUGH _getchar, getchar
PASSTHROUGH _fgets, fgets
PASSTHROUGH _ungetc, ungetc
PASSTHROUGH _fwrite, fwrite
PASSTHROUGH _fread, fread
PASSTHROUGH _fflush, fflush
PASSTHROUGH _fclose, fclose
PASSTHROUGH _fopen, fopen
PASSTHROUGH _fdopen, fdopen
PASSTHROUGH _fileno, fileno
PASSTHROUGH _feof, feof
PASSTHROUGH _ferror, ferror
PASSTHROUGH _clearerr, clearerr
PASSTHROUGH _rewind, rewind
PASSTHROUGH _setvbuf, setvbuf

// MARK: - string
PASSTHROUGH _strlen, strlen
PASSTHROUGH _strnlen, strnlen
PASSTHROUGH _strcmp, strcmp
PASSTHROUGH _strncmp, strncmp
PASSTHROUGH _strcasecmp, strcasecmp
PASSTHROUGH _strncasecmp, strncasecmp
PASSTHROUGH _strcpy, strcpy
PASSTHROUGH _strncpy, strncpy
PASSTHROUGH _strcat, strcat
PASSTHROUGH _strncat, strncat
PASSTHROUGH _strchr, strchr
PASSTHROUGH _strrchr, strrchr
PASSTHROUGH _strstr, strstr
PASSTHROUGH _strdup, strdup
PASSTHROUGH _strndup, strndup
PASSTHROUGH _strspn, strspn
PASSTHROUGH _strcspn, strcspn
PASSTHROUGH _strpbrk, strpbrk
PASSTHROUGH _strtok, strtok
PASSTHROUGH _strtok_r, strtok_r
PASSTHROUGH _memcpy, memcpy
PASSTHROUGH _memmove, memmove
PASSTHROUGH _memset, memset
PASSTHROUGH _memcmp, memcmp
PASSTHROUGH _memchr, memchr
PASSTHROUGH _bzero, bzero
PASSTHROUGH ___bzero, bzero
PASSTHROUGH ___memcpy_chk, __memcpy_chk
PASSTHROUGH ___memmove_chk, __memmove_chk
PASSTHROUGH ___memset_chk, __memset_chk
PASSTHROUGH ___strcpy_chk, __strcpy_chk
PASSTHROUGH ___strcat_chk, __strcat_chk
PASSTHROUGH ___strncpy_chk, __strncpy_chk
PASSTHROUGH ___strncat_chk, __strncat_chk

// MARK: - stdlib
PASSTHROUGH _malloc, malloc
PASSTHROUGH _calloc, calloc
PASSTHROUGH _realloc, realloc
PASSTHROUGH _free, free
PASSTHROUGH _posix_memalign, posix_memalign
PASSTHROUGH _aligned_alloc, aligned_alloc
PASSTHROUGH _getenv, getenv
PASSTHROUGH _setenv, setenv
PASSTHROUGH _unsetenv, unsetenv
PASSTHROUGH _atoi, atoi
PASSTHROUGH _atol, atol
PASSTHROUGH _atoll, atoll
PASSTHROUGH _atof, atof
PASSTHROUGH _strtol, strtol
PASSTHROUGH _strtoul, strtoul
PASSTHROUGH _strtoll, strtoll
PASSTHROUGH _strtoull, strtoull
PASSTHROUGH _strtod, strtod
PASSTHROUGH _strtof, strtof
PASSTHROUGH _abs, abs
PASSTHROUGH _labs, labs
PASSTHROUGH _llabs, llabs
PASSTHROUGH _qsort, qsort
PASSTHROUGH _bsearch, bsearch
PASSTHROUGH _rand, rand
PASSTHROUGH _srand, srand
PASSTHROUGH _random, random
PASSTHROUGH _srandom, srandom
PASSTHROUGH _abort, abort
PASSTHROUGH _exit, exit
PASSTHROUGH __exit, _exit
PASSTHROUGH _atexit, atexit
PASSTHROUGH ___cxa_atexit, __cxa_atexit
PASSTHROUGH _acosf, acosf
PASSTHROUGH _atanf, atanf
PASSTHROUGH _frexp, frexp
PASSTHROUGH _ldexp, ldexp
PASSTHROUGH _log10f, log10f
PASSTHROUGH _lround, lround
PASSTHROUGH _lroundf, lroundf
PASSTHROUGH _modff, modff
PASSTHROUGH ___exp10f, exp10f
PASSTHROUGH ___exp10, exp10
PASSTHROUGH _bcopy, bcopy
PASSTHROUGH _difftime, difftime
PASSTHROUGH _fseek, fseek
PASSTHROUGH _ftell, ftell
PASSTHROUGH _localtime, localtime
PASSTHROUGH _pthread_cancel, pthread_cancel

// MARK: - unistd

PASSTHROUGH _getpid, getpid
PASSTHROUGH _getppid, getppid
PASSTHROUGH _getuid, getuid
PASSTHROUGH _geteuid, geteuid
PASSTHROUGH _getgid, getgid
PASSTHROUGH _getegid, getegid
PASSTHROUGH _sleep, sleep
PASSTHROUGH _usleep, usleep

// MARK: - math
PASSTHROUGH _sin, sin
PASSTHROUGH _cos, cos
PASSTHROUGH _tan, tan
PASSTHROUGH _asin, asin
PASSTHROUGH _acos, acos
PASSTHROUGH _atan, atan
PASSTHROUGH _atan2, atan2
PASSTHROUGH _sqrt, sqrt
PASSTHROUGH _pow, pow
PASSTHROUGH _exp, exp
PASSTHROUGH _log, log
PASSTHROUGH _log10, log10
PASSTHROUGH _floor, floor
PASSTHROUGH _ceil, ceil
PASSTHROUGH _round, round
PASSTHROUGH _fmod, fmod
PASSTHROUGH _sinf, sinf
PASSTHROUGH _cosf, cosf
PASSTHROUGH _tanf, tanf
PASSTHROUGH _atan2f, atan2f
PASSTHROUGH _sqrtf, sqrtf
PASSTHROUGH _powf, powf
PASSTHROUGH _expf, expf
PASSTHROUGH _logf, logf
PASSTHROUGH _floorf, floorf
PASSTHROUGH _ceilf, ceilf
PASSTHROUGH _roundf, roundf
PASSTHROUGH _fmodf, fmodf

#endif

.section .note.GNU-stack, "", %progbits
