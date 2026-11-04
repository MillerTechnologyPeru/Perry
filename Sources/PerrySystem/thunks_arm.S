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
// the format's integers, pointers and strings read right, and its long long
// and double conversions do not yet.
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
VARIADIC _syslog, vsyslog, 2

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
PASSTHROUGH _malloc, malloc
PASSTHROUGH _calloc, calloc
PASSTHROUGH _realloc, realloc
PASSTHROUGH _free, free
PASSTHROUGH _posix_memalign, posix_memalign
PASSTHROUGH _aligned_alloc, aligned_alloc
PASSTHROUGH _getenv, getenv
PASSTHROUGH _setenv, setenv
PASSTHROUGH _unsetenv, unsetenv

// MARK: - files and processes
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
PASSTHROUGH _getcwd, getcwd
PASSTHROUGH _getpagesize, getpagesize
PASSTHROUGH _sched_yield, sched_yield
PASSTHROUGH _arc4random, arc4random
PASSTHROUGH _arc4random_buf, arc4random_buf
PASSTHROUGH _arc4random_uniform, arc4random_uniform

#endif

    .section .note.GNU-stack,"",%progbits
