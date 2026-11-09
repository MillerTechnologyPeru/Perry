// Assembly thunks between Darwin's i386 ABI and glibc's.
//
// Both pass every argument on the stack in the same words, 64-bit ones
// included, and return the same registers, except that Darwin returns
// structures of 1, 2, 4 or 8 bytes in eax:edx where glibc returns them through
// a pointer (no function here does). So these are jumps, to the same
// functions as armv7's thunks. Darwin's off_t is always 64 bits, so the
// functions with one call glibc's *64 forms.

#if defined(__i386__) && defined(__ELF__)

    .text

// Shared objects find their imports through ebx on i386, which belongs to
// the caller here; ecx is free at a function's entry.
    .hidden perry_i386_pc_ecx
    .type perry_i386_pc_ecx, @function
perry_i386_pc_ecx:
    movl (%esp), %ecx
    ret

// PASSTHROUGH darwin_name, glibc_name
.macro PASSTHROUGH name, target
    .globl \name
    .type \name, @function
    .p2align 4
\name:
    call perry_i386_pc_ecx
    addl $_GLOBAL_OFFSET_TABLE_, %ecx
    jmp *\target@GOT(%ecx)
    .size \name, . - \name
.endm

// VARIADIC darwin_name, va_function, fixed_count
//
// A va_list is a pointer to the words after the fixed arguments, on both
// systems: the thunk calls the v* function with the fixed arguments again
// and that pointer after them. The frame keeps Darwin's 16-byte alignment.
.macro VARIADIC name, target, nfixed
    .globl \name
    .type \name, @function
    .p2align 4
\name:
    pushl %ebp
    movl %esp, %ebp
    pushl %ebx
    subl $(4 * (\nfixed + 1) + 28), %esp
    andl $-16, %esp
    .set index, 0
    .rept \nfixed
    movl (8 + 4 * index)(%ebp), %eax
    movl %eax, (4 * index)(%esp)
    .set index, index + 1
    .endr
    leal (8 + 4 * \nfixed)(%ebp), %eax
    movl %eax, (4 * \nfixed)(%esp)
    call perry_i386_pc_ecx
    addl $_GLOBAL_OFFSET_TABLE_, %ecx
    movl %ecx, %ebx
    call \target@PLT
    movl -4(%ebp), %ebx
    leave
    ret
    .size \name, . - \name
.endm

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
VARIADIC _snprintf_l, perry_darwin_vsnprintf_l, 4
VARIADIC _asprintf_l, perry_darwin_vasprintf_l, 3
VARIADIC _sscanf_l, perry_darwin_vsscanf_l, 3
VARIADIC _swprintf, _vswprintf, 3
VARIADIC _asl_log, perry_darwin_asl_log, 4
VARIADIC ___sprintf_chk, ___vsprintf_chk, 4
VARIADIC ___snprintf_chk, ___vsnprintf_chk, 5
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
PASSTHROUGH _fopen, perry_fopen
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
PASSTHROUGH _free, free
PASSTHROUGH _getenv, getenv
PASSTHROUGH _setenv, setenv
PASSTHROUGH _unsetenv, unsetenv
VARIADIC _open, perry_vopen, 2
VARIADIC _openat, perry_vopenat, 3
VARIADIC _sem_open, perry_vsem_open, 2
VARIADIC _fcntl, perry_vfcntl, 2
VARIADIC _open_dprotected_np, perry_vopen_dprotected, 4
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
PASSTHROUGH _vfork, fork
PASSTHROUGH _fseek, fseek
PASSTHROUGH _ftell, ftell
PASSTHROUGH _getdomainname, getdomainname
PASSTHROUGH _getegid, getegid
PASSTHROUGH _geteuid, geteuid
PASSTHROUGH _getgid, getgid
PASSTHROUGH _gethostname, gethostname
PASSTHROUGH _getloadavg, getloadavg
PASSTHROUGH _getpid, getpid
PASSTHROUGH _gethostbyname, gethostbyname
PASSTHROUGH _inet_aton, inet_aton
PASSTHROUGH _remove, remove
PASSTHROUGH _getppid, getppid
PASSTHROUGH _getprotobyname, getprotobyname
PASSTHROUGH _getrusage, getrusage
PASSTHROUGH _getuid, getuid
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
PASSTHROUGH _wmemcmp, wmemcmp
PASSTHROUGH _wcslen, wcslen
PASSTHROUGH _wcstol, wcstol
PASSTHROUGH _wcstoul, wcstoul
PASSTHROUGH _wcstoll, wcstoll
PASSTHROUGH _wcstoull, wcstoull
PASSTHROUGH _fputwc, fputwc
PASSTHROUGH _getwc, getwc
PASSTHROUGH _ungetwc, ungetwc
PASSTHROUGH _catopen, catopen
PASSTHROUGH _catgets, catgets
PASSTHROUGH _catclose, catclose
PASSTHROUGH _writev, writev
PASSTHROUGH _read, read
PASSTHROUGH _write, write
PASSTHROUGH _close, close
PASSTHROUGH _closelog, closelog
PASSTHROUGH _openlog, openlog
PASSTHROUGH _dup, dup
PASSTHROUGH _dup2, dup2
PASSTHROUGH _pipe, pipe
PASSTHROUGH _fsync, fsync
PASSTHROUGH _unlink, unlink
PASSTHROUGH _rmdir, rmdir
PASSTHROUGH _isatty, isatty
PASSTHROUGH _access, perry_access
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
PASSTHROUGH _munmap, munmap
PASSTHROUGH _sched_yield, sched_yield
PASSTHROUGH _arc4random, arc4random
PASSTHROUGH _arc4random_buf, arc4random_buf
PASSTHROUGH _arc4random_uniform, arc4random_uniform
PASSTHROUGH _ftello, ftello64
PASSTHROUGH _lseek, lseek64
PASSTHROUGH _fseeko, fseeko64
PASSTHROUGH _ftruncate, ftruncate64
PASSTHROUGH _truncate, truncate64
PASSTHROUGH _pread, pread64
PASSTHROUGH _pwrite, pwrite64

// The unwinder, for C++ exceptions.
PASSTHROUGH __Unwind_Backtrace, _Unwind_Backtrace
PASSTHROUGH __Unwind_GetIP, _Unwind_GetIP
PASSTHROUGH __Unwind_Resume, _Unwind_Resume
PASSTHROUGH __Unwind_RaiseException, _Unwind_RaiseException
PASSTHROUGH __Unwind_Resume_or_Rethrow, _Unwind_Resume_or_Rethrow
PASSTHROUGH __Unwind_DeleteException, _Unwind_DeleteException
PASSTHROUGH __Unwind_ForcedUnwind, _Unwind_ForcedUnwind
PASSTHROUGH __Unwind_GetLanguageSpecificData, _Unwind_GetLanguageSpecificData
PASSTHROUGH __Unwind_GetRegionStart, _Unwind_GetRegionStart
PASSTHROUGH __Unwind_GetIPInfo, _Unwind_GetIPInfo
PASSTHROUGH __Unwind_SetIP, _Unwind_SetIP
PASSTHROUGH __Unwind_GetGR, _Unwind_GetGR
PASSTHROUGH __Unwind_SetGR, _Unwind_SetGR
PASSTHROUGH __Unwind_GetCFA, _Unwind_GetCFA
PASSTHROUGH __Unwind_GetDataRelBase, _Unwind_GetDataRelBase
PASSTHROUGH __Unwind_GetTextRelBase, _Unwind_GetTextRelBase
PASSTHROUGH __Unwind_FindEnclosingFunction, _Unwind_FindEnclosingFunction
PASSTHROUGH _gmtime, gmtime
PASSTHROUGH _gmtime_r, gmtime_r
PASSTHROUGH _mbstowcs, mbstowcs
PASSTHROUGH _wcstombs, wcstombs
PASSTHROUGH _wcschr, wcschr
PASSTHROUGH _wcscmp, wcscmp
PASSTHROUGH _wcscpy, wcscpy
PASSTHROUGH _wcsncmp, wcsncmp
PASSTHROUGH _wcsncpy, wcsncpy
PASSTHROUGH _fputws, fputws
PASSTHROUGH _rindex, rindex
PASSTHROUGH _setlogmask, setlogmask
PASSTHROUGH _swscanf, swscanf
PASSTHROUGH _tmpfile, tmpfile

// MARK: - setjmp
//
// Darwin's i386 jmp_buf is 18 words, glibc's smaller and a different shape, so
// these keep what a call preserves, and the floating point control words. The
// signal mask is not kept.
.macro SETJMP name
    .globl \name
    .type \name, @function
    .p2align 4
\name:
    movl 4(%esp), %eax
    movl %ebx, 0(%eax)
    movl %esi, 4(%eax)
    movl %edi, 8(%eax)
    movl %ebp, 12(%eax)
    leal 4(%esp), %ecx
    movl %ecx, 16(%eax)
    movl (%esp), %ecx
    movl %ecx, 20(%eax)
    stmxcsr 24(%eax)
    fnstcw 28(%eax)
    xorl %eax, %eax
    ret
    .size \name, . - \name
.endm

.macro LONGJMP name
    .globl \name
    .type \name, @function
    .p2align 4
\name:
    movl 4(%esp), %ecx
    movl 8(%esp), %eax
    movl 0(%ecx), %ebx
    movl 4(%ecx), %esi
    movl 8(%ecx), %edi
    movl 12(%ecx), %ebp
    movl 16(%ecx), %esp
    ldmxcsr 24(%ecx)
    fldcw 28(%ecx)
    movl 20(%ecx), %edx
    testl %eax, %eax
    jnz 1f
    movl $1, %eax
1:  jmp *%edx
    .size \name, . - \name
.endm

SETJMP _setjmp
SETJMP __setjmp
LONGJMP _longjmp
LONGJMP __longjmp
// sigsetjmp's buffer is setjmp's and one more int; the mask isn't kept.
SETJMP _sigsetjmp
LONGJMP _siglongjmp

#endif

    .section .note.GNU-stack,"",%progbits
