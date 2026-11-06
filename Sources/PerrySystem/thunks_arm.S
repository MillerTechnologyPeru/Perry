// Assembly thunks between the Darwin armv7 ABI and glibc's armhf.
//
// Only functions whose arguments and results are each one 32-bit word pass
// through. Darwin packs 64-bit arguments without an even register pair,
// passes floating point in core registers and has a 64-bit off_t, where glibc
// armhf pairs registers, uses VFP registers and has a 32-bit off_t: lseek,
// pread, ftruncate, drand48 and the like need entry points that move their
// arguments, and are not here.

#if defined(__arm__) && defined(__ELF__)

    .syntax unified
    .arm

// PASSTHROUGH darwin_name, glibc_name
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
// Darwin's armv7 variadic arguments continue the fixed ones: the rest of
// r0-r3, then the caller's stack, as one run of 4-byte slots, and a va_list is
// a pointer into it. Spilling the unused argument registers just below the
// stack arguments makes that run, so the va_list is the spill's address. glibc
// reads 64-bit values from 8-byte aligned slots, which this does not give it:
// the targets are the repacking wrappers in stdio.c (_vprintf and the like),
// which copy 64-bit arguments to where glibc reads them.
.macro VARIADIC name, target, nfixed
    .globl \name
    .type \name, %function
    .p2align 2
\name:
    .if \nfixed == 1
    push {r1-r3}
    .elseif \nfixed == 2
    push {r2-r3}
    .elseif \nfixed == 3
    push {r3}
    .else
    .error "VARIADIC takes one to three fixed arguments"
    .endif
    mov r12, sp                 // the va_list
    push {r4, lr}
    mov r4, sp
    bic sp, sp, #7              // Darwin keeps its stack four-byte aligned
    mov r\nfixed, r12
    bl \target
    mov sp, r4
    pop {r4, lr}
    .if \nfixed == 1
    add sp, sp, #12
    .elseif \nfixed == 2
    add sp, sp, #8
    .else
    add sp, sp, #4
    .endif
    bx lr
    .size \name, . - \name
.endm

// VARIADIC_STACK darwin_name, va_function, fixed_count
//
// For four or five fixed arguments, whose variadic arguments are all on the
// caller's stack: the va_list is their address. The target takes the fixed
// arguments past r3 and then the va_list on its stack, in a frame aligned to
// 8 bytes.
.macro VARIADIC_STACK name, target, nfixed
    .if \nfixed != 4 && \nfixed != 5
    .error "VARIADIC_STACK takes four or five fixed arguments"
    .endif
    .globl \name
    .type \name, %function
    .p2align 2
\name:
    push {r4, r5, r6, lr}
    mov r4, sp
    add r5, sp, #16                 // the caller's stack arguments
    add r12, r5, #(4 * (\nfixed - 4))  // the va_list
    sub sp, sp, #8
    bic sp, sp, #7
    .if \nfixed == 5
    ldr r6, [r5]
    str r6, [sp]
    str r12, [sp, #4]
    .else
    str r12, [sp]
    .endif
    bl \target
    mov sp, r4
    pop {r4, r5, r6, pc}
    .size \name, . - \name
.endm

    .text

// MARK: - stdio
// Darwin's files are always large files, so fopen is glibc's fopen64.
VARIADIC _printf, _vprintf, 1
VARIADIC _fprintf, _vfprintf, 2
VARIADIC _dprintf, _vdprintf, 2
VARIADIC _sprintf, _vsprintf, 2
VARIADIC _snprintf, _vsnprintf, 3
VARIADIC _asprintf, _vasprintf, 2
VARIADIC _scanf, vscanf, 1
VARIADIC _fscanf, vfscanf, 2
VARIADIC _sscanf, vsscanf, 2
VARIADIC _syslog, _vsyslog, 2
VARIADIC _ioctl, perry_ioctl, 2
VARIADIC_STACK _snprintf_l, perry_darwin_vsnprintf_l, 4
VARIADIC_STACK _asl_log, perry_darwin_asl_log, 4
VARIADIC_STACK ___sprintf_chk, ___vsprintf_chk, 4
VARIADIC_STACK ___snprintf_chk, ___vsnprintf_chk, 5

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
PASSTHROUGH _fopen, fopen64
PASSTHROUGH _fdopen, fdopen
PASSTHROUGH _fileno, fileno
PASSTHROUGH _feof, feof
PASSTHROUGH _ferror, ferror
PASSTHROUGH _clearerr, clearerr
PASSTHROUGH _rewind, rewind
PASSTHROUGH _setvbuf, setvbuf
PASSTHROUGH _getline, getline
PASSTHROUGH _flockfile, flockfile
PASSTHROUGH _funlockfile, funlockfile

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
PASSTHROUGH _strcasestr, strcasestr
PASSTHROUGH _bzero, bzero
PASSTHROUGH ___bzero, bzero
PASSTHROUGH ___memcpy_chk, __memcpy_chk
PASSTHROUGH ___memmove_chk, __memmove_chk
PASSTHROUGH ___memset_chk, __memset_chk
PASSTHROUGH ___strcpy_chk, __strcpy_chk
PASSTHROUGH ___strcat_chk, __strcat_chk
PASSTHROUGH ___strncpy_chk, __strncpy_chk
PASSTHROUGH ___strncat_chk, __strncat_chk

// MARK: - memory and environment
PASSTHROUGH _free, free
PASSTHROUGH _getenv, getenv
PASSTHROUGH _setenv, setenv
PASSTHROUGH _unsetenv, unsetenv

// MARK: - files and processes
// open, openat and fcntl are variadic on Darwin; files.c reads their optional
// argument from the va_list.
VARIADIC _open, perry_vopen, 2
VARIADIC _openat, perry_vopenat, 3
VARIADIC _fcntl, perry_vfcntl, 2
VARIADIC_STACK _open_dprotected_np, perry_vopen_dprotected, 4

// MARK: - functions of words
// Their arguments and results are 32-bit words, or 64-bit results in r0 and
// r1, or a 64-bit argument that comes first, all of which pass the same.
// Darwin's structures they take are laid out as glibc's armhf ones: rusage,
// tm, timeval, utimbuf and iovec, with a 32-bit time_t on both.
// Those that take callbacks are in callbacks.c.
PASSTHROUGH __exit, _exit
PASSTHROUGH _abort, abort
PASSTHROUGH _abs, abs
PASSTHROUGH _atoi, atoi
PASSTHROUGH _atol, atol
PASSTHROUGH _atoll, atoll
PASSTHROUGH _backtrace, backtrace
PASSTHROUGH _backtrace_symbols, backtrace_symbols
PASSTHROUGH _bcopy, bcopy
PASSTHROUGH _execv, execv
PASSTHROUGH _execve, execve
PASSTHROUGH _exit, exit
PASSTHROUGH _flock, flock
PASSTHROUGH _fork, fork
PASSTHROUGH _fseek, fseek
PASSTHROUGH _ftell, ftell
PASSTHROUGH _getdomainname, getdomainname
PASSTHROUGH _getegid, getegid
PASSTHROUGH _geteuid, geteuid
PASSTHROUGH _getgid, getgid
PASSTHROUGH _gethostname, gethostname
PASSTHROUGH _getloadavg, getloadavg
PASSTHROUGH _getpid, getpid
PASSTHROUGH _getppid, getppid
PASSTHROUGH _getprotobyname, getprotobyname
PASSTHROUGH _getrusage, getrusage
PASSTHROUGH _getuid, getuid
PASSTHROUGH _if_nametoindex, if_nametoindex
PASSTHROUGH _inet_addr, inet_addr
PASSTHROUGH _inet_ntoa, inet_ntoa
PASSTHROUGH _labs, labs
PASSTHROUGH _listen, listen
PASSTHROUGH _llabs, llabs
PASSTHROUGH _localtime, localtime
PASSTHROUGH _localtime_r, localtime_r
PASSTHROUGH _mkstemp, mkstemp
PASSTHROUGH _pthread_attr_destroy, pthread_attr_destroy
PASSTHROUGH _pthread_attr_getstacksize, pthread_attr_getstacksize
PASSTHROUGH _pthread_attr_init, pthread_attr_init
PASSTHROUGH _pthread_cancel, pthread_cancel
PASSTHROUGH _pthread_detach, pthread_detach
PASSTHROUGH _pthread_equal, pthread_equal
PASSTHROUGH _pthread_exit, pthread_exit
PASSTHROUGH _pthread_join, pthread_join
PASSTHROUGH _pthread_self, pthread_self
PASSTHROUGH _rand, rand
PASSTHROUGH _random, random
PASSTHROUGH _setpgid, setpgid
PASSTHROUGH _shutdown, shutdown
PASSTHROUGH _sleep, sleep
PASSTHROUGH _srand, srand
PASSTHROUGH _srandom, srandom
PASSTHROUGH _stpcpy, stpcpy
PASSTHROUGH _strftime, strftime
PASSTHROUGH _strlcat, strlcat
PASSTHROUGH _strlcpy, strlcpy
PASSTHROUGH _strtol, strtol
PASSTHROUGH _strtoll, strtoll
PASSTHROUGH _strtoul, strtoul
PASSTHROUGH _strtoull, strtoull
PASSTHROUGH _usleep, usleep
PASSTHROUGH _utime, utime
PASSTHROUGH _utimes, utimes
PASSTHROUGH _waitpid, waitpid
PASSTHROUGH _wmemchr, wmemchr
PASSTHROUGH _writev, writev

PASSTHROUGH _read, read
PASSTHROUGH _write, write
PASSTHROUGH _close, close
PASSTHROUGH _dup, dup
PASSTHROUGH _dup2, dup2
PASSTHROUGH _pipe, pipe
PASSTHROUGH _fsync, fsync
PASSTHROUGH _unlink, unlink
PASSTHROUGH _rmdir, rmdir
PASSTHROUGH _isatty, isatty
PASSTHROUGH _access, access
PASSTHROUGH _chdir, chdir
PASSTHROUGH _mkdir, mkdir
PASSTHROUGH _symlink, symlink
PASSTHROUGH _link, link
PASSTHROUGH _readlink, readlink
PASSTHROUGH _rename, rename
PASSTHROUGH _chmod, chmod
PASSTHROUGH _fchmod, fchmod
PASSTHROUGH _chown, chown
PASSTHROUGH _fchown, fchown
PASSTHROUGH _fchdir, fchdir
PASSTHROUGH _umask, umask
PASSTHROUGH _time, time
PASSTHROUGH _nanosleep, nanosleep
PASSTHROUGH _gettimeofday, gettimeofday
PASSTHROUGH _mprotect, mprotect
PASSTHROUGH _mlock, mlock
PASSTHROUGH _munlock, munlock
PASSTHROUGH _getcwd, getcwd
PASSTHROUGH _getpagesize, getpagesize
PASSTHROUGH _munmap, munmap
PASSTHROUGH _sched_yield, sched_yield
PASSTHROUGH _arc4random, arc4random
PASSTHROUGH _arc4random_buf, arc4random_buf
PASSTHROUGH _arc4random_uniform, arc4random_uniform


// MARK: - 64-bit arguments
//
// Darwin passes a 64-bit argument in the next two registers or stack slots,
// whichever are free; glibc starts it at an even register or an 8-byte aligned
// slot. off_t is 64 bits on Darwin always, so these call glibc's *64 forms.
// Each adapter builds an 8-byte aligned frame, since Darwin does not keep one.

// f(a, off_t, int): the offset takes r1:r2 here and r2:r3 there, which moves
// the last argument to the stack.
.macro OFFSET_THEN_INT name, target
    .globl \name
    .type \name, %function
    .p2align 2
\name:
    push {r4, lr}
    mov r4, sp
    sub sp, sp, #8
    bic sp, sp, #7
    str r3, [sp]
    mov r3, r2
    mov r2, r1
    bl \target
    mov sp, r4
    pop {r4, pc}
    .size \name, . - \name
.endm

// f(a, off_t): r1:r2 becomes r2:r3.
.macro OFFSET_LAST name, target
    .globl \name
    .type \name, %function
    .p2align 2
\name:
    mov r3, r2
    mov r2, r1
    b \target
    .size \name, . - \name
.endm

// f(a, b, c, off_t): the offset starts in r3 and continues on the stack here,
// and wholly on the stack there, after the padding r3 becomes.
.macro THREE_THEN_OFFSET name, target
    .globl \name
    .type \name, %function
    .p2align 2
\name:
    push {r4, lr}
    mov r4, sp
    sub sp, sp, #8
    bic sp, sp, #7
    ldr r12, [r4, #8]
    str r3, [sp]
    str r12, [sp, #4]
    bl \target
    mov sp, r4
    pop {r4, pc}
    .size \name, . - \name
.endm

OFFSET_THEN_INT _lseek, lseek64
OFFSET_THEN_INT _fseeko, fseeko64
OFFSET_LAST _ftruncate, ftruncate64
OFFSET_LAST _truncate, truncate64
THREE_THEN_OFFSET _pread, pread64
THREE_THEN_OFFSET _pwrite, pwrite64
PASSTHROUGH _ftello, ftello64

// mmap(addr, length, protection, flags, fd, off_t): fd, then the offset, on
// the stack here; fd, padding, then the offset at an even slot there. The
// Darwin flags convert in perry_mmap (system.c).
    .globl _mmap
    .type _mmap, %function
    .p2align 2
_mmap:
    push {r4, lr}
    mov r4, sp
    sub sp, sp, #16
    bic sp, sp, #7
    ldr r12, [r4, #8]
    str r12, [sp]
    ldr r12, [r4, #12]
    str r12, [sp, #8]
    ldr r12, [r4, #16]
    str r12, [sp, #12]
    bl perry_mmap
    mov sp, r4
    pop {r4, pc}
    .size _mmap, . - _mmap

// void perry_sjlj_longjmp(void **jbuf): __builtin_longjmp's return to a
// Darwin function's exception dispatch (runtime.c). Its setjmp saved r7, the
// dispatch address (with the Thumb bit) and sp; the dispatch code reloads
// everything else from the frame.
    .globl perry_sjlj_longjmp
    .hidden perry_sjlj_longjmp
    .type perry_sjlj_longjmp, %function
    .p2align 2
perry_sjlj_longjmp:
    ldr r7, [r0]
    ldr r1, [r0, #4]
    ldr sp, [r0, #8]
    bx r1
    .size perry_sjlj_longjmp, . - perry_sjlj_longjmp

#endif

    .section .note.GNU-stack,"",%progbits
