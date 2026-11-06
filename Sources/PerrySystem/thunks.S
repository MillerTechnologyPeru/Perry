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
VARIADIC _sprintf, perry_vsprintf, 2
VARIADIC _snprintf, perry_vsnprintf, 3
VARIADIC _snprintf_l, perry_vsnprintf_l, 4
VARIADIC _ioctl, perry_ioctl, 2
VARIADIC _asl_log, perry_asl_log, 4
VARIADIC _asprintf, vasprintf, 2
VARIADIC _scanf, vscanf, 1
VARIADIC _fscanf, vfscanf, 2
VARIADIC _sscanf, vsscanf, 2
VARIADIC _swscanf, vswscanf, 2
VARIADIC ___sprintf_chk, perry_vsprintf_chk, 4
VARIADIC ___snprintf_chk, perry_vsnprintf_chk, 5
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
PASSTHROUGH _flock, flock

// open, openat and fcntl are variadic on Darwin.
VARIADIC _open, perry_vopen, 2
VARIADIC _open_dprotected_np, perry_vopen_dprotected, 4
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
PASSTHROUGH _writev, writev
PASSTHROUGH _drand48, drand48
PASSTHROUGH _wmemchr, wmemchr
PASSTHROUGH _wmemcpy, wmemcpy
PASSTHROUGH _wmemcmp, wmemcmp
PASSTHROUGH _wcslen, wcslen
PASSTHROUGH _wcscpy, wcscpy
PASSTHROUGH _wcsncpy, wcsncpy
PASSTHROUGH _wcscmp, wcscmp
PASSTHROUGH _wcsncmp, wcsncmp
PASSTHROUGH _wcschr, wcschr
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
PASSTHROUGH _free, free
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
// The C locale's; the locale argument is ignored. long double is double on
// Darwin arm64.
PASSTHROUGH _strtod_l, strtod
PASSTHROUGH _strtof_l, strtof
PASSTHROUGH _strtold_l, strtod
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
PASSTHROUGH _stpcpy, stpcpy
PASSTHROUGH _strlcat, strlcat
PASSTHROUGH _strlcpy, strlcpy
PASSTHROUGH _strftime, strftime
PASSTHROUGH _localtime_r, localtime_r
PASSTHROUGH _modf, modf
PASSTHROUGH _logb, logb
PASSTHROUGH _scalbn, scalbn
PASSTHROUGH _cabs, cabs
PASSTHROUGH _getrusage, getrusage
PASSTHROUGH _utime, utime
PASSTHROUGH _utimes, utimes
PASSTHROUGH _mkstemp, mkstemp
PASSTHROUGH _mktemp, mktemp
PASSTHROUGH _memccpy, memccpy
PASSTHROUGH _pthread_atfork, pthread_atfork
PASSTHROUGH _getprotobyname, getprotobyname
PASSTHROUGH _if_nametoindex, if_nametoindex
PASSTHROUGH _fork, fork
PASSTHROUGH _execv, execv
PASSTHROUGH _execve, execve
PASSTHROUGH _div, div
PASSTHROUGH _ldiv, ldiv
PASSTHROUGH _ldexpf, ldexpf
PASSTHROUGH _wcscat, wcscat
PASSTHROUGH _gmtime_r, gmtime_r
PASSTHROUGH _basename, __xpg_basename
PASSTHROUGH _dirname, dirname
PASSTHROUGH _alarm, alarm
PASSTHROUGH _getdtablesize, getdtablesize
PASSTHROUGH _setbuf, setbuf
PASSTHROUGH _setuid, setuid
PASSTHROUGH _setgid, setgid
PASSTHROUGH _waitpid, waitpid
PASSTHROUGH _setpgid, setpgid
PASSTHROUGH _getloadavg, getloadavg
PASSTHROUGH _getdomainname, getdomainname
PASSTHROUGH _gethostname, gethostname
PASSTHROUGH _backtrace, backtrace
PASSTHROUGH _backtrace_symbols, backtrace_symbols
PASSTHROUGH _pthread_exit, pthread_exit
PASSTHROUGH __Unwind_Backtrace, _Unwind_Backtrace
PASSTHROUGH __Unwind_GetIP, _Unwind_GetIP
PASSTHROUGH "_fopen$DARWIN_EXTSN", fopen
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
PASSTHROUGH _gmtime, gmtime
PASSTHROUGH _mktime, mktime
PASSTHROUGH _fseeko, fseeko
PASSTHROUGH _ftello, ftello
PASSTHROUGH _remove, remove
PASSTHROUGH _system, system
PASSTHROUGH _isdigit, isdigit
PASSTHROUGH _isspace, isspace
PASSTHROUGH _fnmatch, fnmatch
PASSTHROUGH _inet_aton, inet_aton
PASSTHROUGH _gethostbyname, gethostbyname
PASSTHROUGH _wcstol, wcstol
PASSTHROUGH _wcstof, wcstof
PASSTHROUGH _wcstombs, wcstombs
PASSTHROUGH _mbstowcs, mbstowcs
PASSTHROUGH _ecvt, ecvt
PASSTHROUGH _fcvt, fcvt
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
PASSTHROUGH _exp2, exp2
PASSTHROUGH _log2, log2
PASSTHROUGH _remainder, remainder
PASSTHROUGH _remquo, remquo
PASSTHROUGH _lgamma_r, lgamma_r
PASSTHROUGH _jn, jn
PASSTHROUGH _yn, yn
PASSTHROUGH _asinf, asinf
PASSTHROUGH _acoshf, acoshf
PASSTHROUGH _asinhf, asinhf
PASSTHROUGH _atanhf, atanhf
PASSTHROUGH _coshf, coshf
PASSTHROUGH _sinhf, sinhf
PASSTHROUGH _tanhf, tanhf
PASSTHROUGH _cbrtf, cbrtf
PASSTHROUGH _copysign, copysign
PASSTHROUGH _copysignf, copysignf
PASSTHROUGH _erff, erff
PASSTHROUGH _erfcf, erfcf
PASSTHROUGH _exp2f, exp2f
PASSTHROUGH _expm1f, expm1f
PASSTHROUGH _log1pf, log1pf
PASSTHROUGH _log2f, log2f
PASSTHROUGH _logbf, logbf
PASSTHROUGH _fdimf, fdimf
PASSTHROUGH _hypotf, hypotf
PASSTHROUGH _nanf, nanf
PASSTHROUGH _nextafterf, nextafterf
PASSTHROUGH _remainderf, remainderf
PASSTHROUGH _remquof, remquof
PASSTHROUGH _lgammaf_r, lgammaf_r
PASSTHROUGH _tgammaf, tgammaf
PASSTHROUGH _nextafter, nextafter
// long double is double on Darwin arm64.
PASSTHROUGH _fmodl, fmod
PASSTHROUGH _lgammal_r, lgamma_r
PASSTHROUGH _llroundl, llround

// MARK: - compiler runtime
// 128-bit division, which Darwin's libSystem exports (compiler-rt's).
PASSTHROUGH ___divti3, __divti3
PASSTHROUGH ___modti3, __modti3
PASSTHROUGH ___udivti3, __udivti3
PASSTHROUGH ___umodti3, __umodti3

// MARK: - setjmp

// Darwin's arm64 jmp_buf is 192 bytes, glibc's 312, so glibc's setjmp
// would write past the app's buffer: the callee-saved registers, the frame
// and link registers, sp and d8-d15 are saved here in 168 of Darwin's 192.
// The signal mask is not saved or restored.
.macro SETJMP name
    .globl \name
    .type \name, %function
    .p2align 2
\name:
    stp x19, x20, [x0, #0]
    stp x21, x22, [x0, #16]
    stp x23, x24, [x0, #32]
    stp x25, x26, [x0, #48]
    stp x27, x28, [x0, #64]
    stp x29, x30, [x0, #80]
    mov x9, sp
    str x9, [x0, #96]
    stp d8, d9, [x0, #104]
    stp d10, d11, [x0, #120]
    stp d12, d13, [x0, #136]
    stp d14, d15, [x0, #152]
    mov w0, #0
    ret
    .size \name, . - \name
.endm

// Returns from the matching setjmp with the value, or 1 for 0.
.macro LONGJMP name
    .globl \name
    .type \name, %function
    .p2align 2
\name:
    ldp x19, x20, [x0, #0]
    ldp x21, x22, [x0, #16]
    ldp x23, x24, [x0, #32]
    ldp x25, x26, [x0, #48]
    ldp x27, x28, [x0, #64]
    ldp x29, x30, [x0, #80]
    ldr x9, [x0, #96]
    mov sp, x9
    ldp d8, d9, [x0, #104]
    ldp d10, d11, [x0, #120]
    ldp d12, d13, [x0, #136]
    ldp d14, d15, [x0, #152]
    cmp w1, #0
    csinc w0, w1, wzr, ne
    ret
    .size \name, . - \name
.endm

SETJMP _setjmp
SETJMP __setjmp
LONGJMP _longjmp
LONGJMP __longjmp
// sigsetjmp's buffer is setjmp's and one more int; the mask isn't kept.
SETJMP _sigsetjmp
LONGJMP _siglongjmp

// More of libc and libm, which Linux's have with the same ABI. Darwin's
// long double is double on arm64: its l functions are the double ones.
// nexttoward takes a long double second argument, which is a double too.
PASSTHROUGH _getgroups, getgroups
PASSTHROUGH _acosh, acosh
PASSTHROUGH _asinh, asinh
PASSTHROUGH _atanh, atanh
PASSTHROUGH _cbrt, cbrt
PASSTHROUGH _cosh, cosh
PASSTHROUGH _erf, erf
PASSTHROUGH _erfc, erfc
PASSTHROUGH _expm1, expm1
PASSTHROUGH _fdim, fdim
PASSTHROUGH _hypot, hypot
PASSTHROUGH _lgamma, lgamma
PASSTHROUGH _lgammaf, lgammaf
PASSTHROUGH _log1p, log1p
PASSTHROUGH _nan, nan
PASSTHROUGH _sinh, sinh
PASSTHROUGH _tanh, tanh
PASSTHROUGH _tgamma, tgamma
PASSTHROUGH _ilogb, ilogb
PASSTHROUGH _ilogbf, ilogbf
PASSTHROUGH _scalbln, scalbln
PASSTHROUGH _scalblnf, scalblnf
PASSTHROUGH _scalbnf, scalbnf
PASSTHROUGH _frexpf, frexpf
PASSTHROUGH _strcoll, strcoll
PASSTHROUGH _strxfrm, strxfrm
PASSTHROUGH _strsep, strsep
PASSTHROUGH _rand_r, rand_r
PASSTHROUGH _sync, sync
PASSTHROUGH _getwchar, getwchar
PASSTHROUGH _mblen, mblen
PASSTHROUGH _wctomb, wctomb
PASSTHROUGH _wcstod, wcstod
PASSTHROUGH _wcstoll, wcstoll
PASSTHROUGH _wcstoul, wcstoul
PASSTHROUGH _wcstoull, wcstoull
PASSTHROUGH _wmemset, wmemset
PASSTHROUGH _wctob, wctob
PASSTHROUGH _btowc, btowc
PASSTHROUGH _imaxabs, imaxabs
PASSTHROUGH _strtoimax, strtoimax
PASSTHROUGH _strtoumax, strtoumax
PASSTHROUGH _lldiv, lldiv
PASSTHROUGH _timegm, timegm
PASSTHROUGH _clock, clock
PASSTHROUGH _ctime, ctime
PASSTHROUGH _asctime, asctime
PASSTHROUGH _closelog, closelog
PASSTHROUGH _openlog, openlog
PASSTHROUGH _execvp, execvp
PASSTHROUGH _wait4, wait4
PASSTHROUGH _pause, pause
PASSTHROUGH _posix_madvise, posix_madvise
PASSTHROUGH _if_indextoname, if_indextoname
PASSTHROUGH _j0, j0
PASSTHROUGH _j1, j1
PASSTHROUGH _y0, y0
PASSTHROUGH _y1, y1
PASSTHROUGH _mbsrtowcs, mbsrtowcs
PASSTHROUGH _towctrans, towctrans
PASSTHROUGH _wctrans, wctrans
PASSTHROUGH _wctype, wctype
PASSTHROUGH _strptime, strptime
PASSTHROUGH _feclearexcept, feclearexcept
PASSTHROUGH _fetestexcept, fetestexcept
PASSTHROUGH _feraiseexcept, feraiseexcept
PASSTHROUGH _fegetround, fegetround
PASSTHROUGH _fesetround, fesetround
PASSTHROUGH _cabsf, cabsf
PASSTHROUGH _cacos, cacos
PASSTHROUGH _cacosf, cacosf
PASSTHROUGH _cacosh, cacosh
PASSTHROUGH _cacoshf, cacoshf
PASSTHROUGH _carg, carg
PASSTHROUGH _cargf, cargf
PASSTHROUGH _casin, casin
PASSTHROUGH _casinf, casinf
PASSTHROUGH _casinh, casinh
PASSTHROUGH _casinhf, casinhf
PASSTHROUGH _catan, catan
PASSTHROUGH _catanf, catanf
PASSTHROUGH _catanh, catanh
PASSTHROUGH _catanhf, catanhf
PASSTHROUGH _ccos, ccos
PASSTHROUGH _ccosf, ccosf
PASSTHROUGH _ccosh, ccosh
PASSTHROUGH _ccoshf, ccoshf
PASSTHROUGH _cexp, cexp
PASSTHROUGH _cexpf, cexpf
PASSTHROUGH _clog, clog
PASSTHROUGH _clogf, clogf
PASSTHROUGH _cpow, cpow
PASSTHROUGH _cpowf, cpowf
PASSTHROUGH _cproj, cproj
PASSTHROUGH _cprojf, cprojf
PASSTHROUGH _csin, csin
PASSTHROUGH _csinf, csinf
PASSTHROUGH _csinh, csinh
PASSTHROUGH _csinhf, csinhf
PASSTHROUGH _csqrt, csqrt
PASSTHROUGH _csqrtf, csqrtf
PASSTHROUGH _ctan, ctan
PASSTHROUGH _ctanf, ctanf
PASSTHROUGH _ctanh, ctanh
PASSTHROUGH _ctanhf, ctanhf
PASSTHROUGH _acoshl, acosh
PASSTHROUGH _asinhl, asinh
PASSTHROUGH _atanhl, atanh
PASSTHROUGH _cbrtl, cbrt
PASSTHROUGH _erfl, erf
PASSTHROUGH _erfcl, erfc
PASSTHROUGH _expm1l, expm1
PASSTHROUGH _fdiml, fdim
PASSTHROUGH _lgammal, lgamma
PASSTHROUGH _log1pl, log1p
PASSTHROUGH _nanl, nan
PASSTHROUGH _tgammal, tgamma
PASSTHROUGH _logbl, logb
PASSTHROUGH _nextafterl, nextafter
PASSTHROUGH _remainderl, remainder
PASSTHROUGH _remquol, remquo
PASSTHROUGH _scalbnl, scalbn
PASSTHROUGH _scalblnl, scalbln
PASSTHROUGH _ilogbl, ilogb
PASSTHROUGH _cabsl, cabs
PASSTHROUGH _cacosl, cacos
PASSTHROUGH _cacoshl, cacosh
PASSTHROUGH _cargl, carg
PASSTHROUGH _casinl, casin
PASSTHROUGH _casinhl, casinh
PASSTHROUGH _catanl, catan
PASSTHROUGH _catanhl, catanh
PASSTHROUGH _ccosl, ccos
PASSTHROUGH _ccoshl, ccosh
PASSTHROUGH _cexpl, cexp
PASSTHROUGH _clogl, clog
PASSTHROUGH _cpowl, cpow
PASSTHROUGH _cprojl, cproj
PASSTHROUGH _csinl, csin
PASSTHROUGH _csinhl, csinh
PASSTHROUGH _csqrtl, csqrt
PASSTHROUGH _ctanl, ctan
PASSTHROUGH _ctanhl, ctanh
PASSTHROUGH _nexttoward, nextafter

#endif

.section .note.GNU-stack, "", %progbits
