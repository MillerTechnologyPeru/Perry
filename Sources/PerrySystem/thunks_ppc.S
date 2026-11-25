// Assembly thunks between Darwin's 32-bit PowerPC ABI and glibc's (SysV).
//
// Only functions whose arguments and results are each one 32-bit word pass
// through: those go in r3-r10 on both. Darwin packs 64-bit arguments without
// an aligned register pair, passes floating point in f1-f13 while skipping
// the GPRs it would take, and has a 64-bit off_t, where glibc pairs registers
// (r3:r4, r5:r6, ...) and skips none: lseek, pread, ftruncate, ldexp and the
// like need entry points that move their arguments.
//
// glibc's functions are reached through a word in .data.rel.ro rather than
// the PLT, whose stubs in a shared object need r30, the caller's register
// here. r0, r11, r12 and ctr are free at a call in both ABIs. r2, Linux's
// thread pointer, is right on entry: Darwin code calls these through the
// loader's stubs, which set it.

#if defined(__powerpc__) && !defined(__powerpc64__) && defined(__ELF__)

// Jumps to the function whose address is in the word at \slot, with lr and
// the arguments as they are.
.macro JUMP_THROUGH slot
    mflr %r0
    bcl 20, 31, 1f
1:  mflr %r12
    mtlr %r0
    addis %r12, %r12, (\slot - 1b)@ha
    lwz %r12, (\slot - 1b)@l(%r12)
    mtctr %r12
    bctr
.endm

// Calls it, from a frame of the caller's own.
.macro CALL_THROUGH slot
    bcl 20, 31, 1f
1:  mflr %r12
    addis %r12, %r12, (\slot - 1b)@ha
    lwz %r12, (\slot - 1b)@l(%r12)
    mtctr %r12
    bctrl
.endm

// The word for \target, made once.
.macro SLOT target
    .ifndef .Lslot_\target
    .pushsection .data.rel.ro, "aw"
    .p2align 2
.Lslot_\target:
    .long \target
    .popsection
    .endif
.endm

// PASSTHROUGH darwin_name, glibc_name
.macro PASSTHROUGH name, target
    SLOT \target
    .globl \name
    .type \name, @function
    .p2align 2
\name:
    JUMP_THROUGH .Lslot_\target
    .size \name, . - \name
.endm

// VARIADIC darwin_name, va_function, fixed_count
//
// Darwin's caller reserves words for r3-r10 at 24(r1), before its stack
// arguments, so spilling the registers there makes one run of the variadic
// arguments, in 4-byte slots. Darwin's va_list is a pointer into it. The
// targets take that pointer (stdio.c's _vprintf and the like, which repack
// 64-bit arguments for glibc).
.macro VARIADIC name, target, nfixed
    SLOT \target
    .globl \name
    .type \name, @function
    .p2align 2
\name:
    stw %r3, 24(%r1)
    stw %r4, 28(%r1)
    stw %r5, 32(%r1)
    stw %r6, 36(%r1)
    stw %r7, 40(%r1)
    stw %r8, 44(%r1)
    stw %r9, 48(%r1)
    stw %r10, 52(%r1)
    addi \nfixed + 3, %r1, 24 + 4 * \nfixed
    JUMP_THROUGH .Lslot_\target
    .size \name, . - \name
.endm

// VARIADIC_GLIBC darwin_name, va_function, fixed_count
//
// The same for a target that takes glibc's va_list, a structure: one whose
// register counts are used up, so that every argument is read from its
// overflow area, the Darwin arguments. Their values are words and pointers.
.macro VARIADIC_GLIBC name, target, nfixed
    SLOT \target
    .globl \name
    .type \name, @function
    .p2align 2
\name:
    stw %r3, 24(%r1)
    stw %r4, 28(%r1)
    stw %r5, 32(%r1)
    stw %r6, 36(%r1)
    stw %r7, 40(%r1)
    stw %r8, 44(%r1)
    stw %r9, 48(%r1)
    stw %r10, 52(%r1)
    addi %r11, %r1, 24 + 4 * \nfixed
    mflr %r0
    stwu %r1, -32(%r1)
    stw %r0, 28(%r1)
    li %r0, 8
    stb %r0, 8(%r1)                 // gpr
    stb %r0, 9(%r1)                 // fpr
    stw %r11, 12(%r1)               // overflow_arg_area
    li %r0, 0
    stw %r0, 16(%r1)                // reg_save_area
    addi \nfixed + 3, %r1, 8
    CALL_THROUGH .Lslot_\target
    lwz %r0, 28(%r1)
    mtlr %r0
    addi %r1, %r1, 32
    blr
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
VARIADIC_GLIBC _scanf, vscanf, 1
VARIADIC _fscanf, _vfscanf, 2
VARIADIC_GLIBC _sscanf, vsscanf, 2
VARIADIC_GLIBC _swscanf, vswscanf, 2
VARIADIC _syslog, _vsyslog, 2
VARIADIC_GLIBC _ioctl, perry_ioctl, 2
VARIADIC _snprintf_l, perry_darwin_vsnprintf_l, 4
VARIADIC _asprintf_l, perry_darwin_vasprintf_l, 3
VARIADIC _sscanf_l, perry_darwin_vsscanf_l, 3
VARIADIC _swprintf, _vswprintf, 3
VARIADIC _asl_log, perry_darwin_asl_log, 4
VARIADIC ___sprintf_chk, ___vsprintf_chk, 4
VARIADIC ___snprintf_chk, ___vsnprintf_chk, 5

PASSTHROUGH _puts, puts
PASSTHROUGH _putchar, putchar
PASSTHROUGH _getchar, getchar

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
VARIADIC_GLIBC _open, perry_vopen, 2
VARIADIC_GLIBC _openat, perry_vopenat, 3
VARIADIC_GLIBC _sem_open, perry_vsem_open, 2
VARIADIC_GLIBC _fcntl, perry_vfcntl, 2
VARIADIC_GLIBC _open_dprotected_np, perry_vopen_dprotected, 4

// MARK: - functions of words
// Their arguments and results are 32-bit words, or 64-bit results in r3 and
// r4, or a 64-bit argument that comes first, all of which pass the same.
// Darwin's structures they take are laid out as glibc's ppc ones: rusage,
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
PASSTHROUGH _exit, exit
PASSTHROUGH _flock, flock
PASSTHROUGH _fork, fork
// vfork as fork: the child gets its own copy, which is safe for what a
// vfork child may do (exec or _exit), where vfork itself shares the stack.
PASSTHROUGH _vfork, fork
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
PASSTHROUGH _getservbyname, getservbyname
PASSTHROUGH _getservbyport, getservbyport
PASSTHROUGH _getrusage, getrusage
PASSTHROUGH _getuid, getuid
PASSTHROUGH _inet_addr, inet_addr
PASSTHROUGH _inet_ntoa, inet_ntoa
PASSTHROUGH _labs, labs
PASSTHROUGH _listen, listen
PASSTHROUGH _llabs, llabs
PASSTHROUGH _localtime, localtime
PASSTHROUGH _localtime_r, localtime_r
PASSTHROUGH _gmtime, gmtime
PASSTHROUGH _gmtime_r, gmtime_r
PASSTHROUGH _mkstemp, mkstemp
PASSTHROUGH _pthread_attr_destroy, pthread_attr_destroy
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
PASSTHROUGH _strtouq, strtoull
PASSTHROUGH _usleep, usleep
PASSTHROUGH _utime, utime
PASSTHROUGH _utimes, utimes
PASSTHROUGH _waitpid, waitpid
PASSTHROUGH _wmemchr, wmemchr
PASSTHROUGH _wmemcmp, wmemcmp
PASSTHROUGH _wcslen, wcslen
PASSTHROUGH _wcscat, wcscat
PASSTHROUGH _wcschr, wcschr
PASSTHROUGH _wcscmp, wcscmp
PASSTHROUGH _wcscpy, wcscpy
PASSTHROUGH _wcsncmp, wcsncmp
PASSTHROUGH _wcsncpy, wcsncpy
PASSTHROUGH _wcsrchr, wcsrchr
PASSTHROUGH _wcsstr, wcsstr
PASSTHROUGH _wcstol, wcstol
PASSTHROUGH _wcstoul, wcstoul
PASSTHROUGH _wcstoll, wcstoll
PASSTHROUGH _wcstoull, wcstoull
PASSTHROUGH _wcstombs, wcstombs
PASSTHROUGH _mbstowcs, mbstowcs
PASSTHROUGH _wcspbrk, wcspbrk
PASSTHROUGH _wcsspn, wcsspn
PASSTHROUGH _wcscspn, wcscspn
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

// MARK: - 64-bit arguments
//
// Darwin passes a 64-bit argument in the next two registers; glibc starts it
// at r3, r5, r7 or r9. off_t is 64 bits on Darwin always, so these call
// glibc's *64 forms.

// f(a, off_t, int): r4:r5 and r6 become r5:r6 and r7.
.macro OFFSET_THEN_INT name, target
    SLOT \target
    .globl \name
    .type \name, @function
    .p2align 2
\name:
    mr %r7, %r6
    mr %r6, %r5
    mr %r5, %r4
    JUMP_THROUGH .Lslot_\target
    .size \name, . - \name
.endm

// f(a, off_t): r4:r5 becomes r5:r6.
.macro OFFSET_LAST name, target
    SLOT \target
    .globl \name
    .type \name, @function
    .p2align 2
\name:
    mr %r6, %r5
    mr %r5, %r4
    JUMP_THROUGH .Lslot_\target
    .size \name, . - \name
.endm

// f(a, b, c, off_t): r6:r7 becomes r7:r8.
.macro THREE_THEN_OFFSET name, target
    SLOT \target
    .globl \name
    .type \name, @function
    .p2align 2
\name:
    mr %r8, %r7
    mr %r7, %r6
    JUMP_THROUGH .Lslot_\target
    .size \name, . - \name
.endm

OFFSET_THEN_INT _lseek, lseek64
OFFSET_LAST _ftruncate, ftruncate64
OFFSET_LAST _truncate, truncate64
THREE_THEN_OFFSET _pread, pread64
THREE_THEN_OFFSET _pwrite, pwrite64

// fseeko on a Darwin stream, which stands for a glibc one (darwin_file.c).
    .globl _fseeko
    .type _fseeko, @function
    .p2align 2
_fseeko:
    mr %r7, %r6
    mr %r6, %r5
    mr %r5, %r4
    b perry_fseeko
    .size _fseeko, . - _fseeko

// mmap(addr, length, protection, flags, fd, off_t): r8:r9 becomes r9:r10.
// The Darwin flags convert in perry_mmap (system.c).
    .globl _mmap
    .type _mmap, @function
    .p2align 2
_mmap:
    mr %r10, %r9
    mr %r9, %r8
    b perry_mmap
    .size _mmap, . - _mmap

// MARK: - setjmp
//
// Darwin's ppc jmp_buf is 192 words (and sigjmp_buf one more), glibc's a
// different shape, so glibc's setjmp cannot fill it. These keep what a call
// preserves: r1, lr, cr, r13-r31, then f14-f31 and the FPSCR, in 64 of them.
// The vector registers and the signal mask are not kept.
.macro SETJMP name
    .globl \name
    .type \name, @function
    .p2align 2
\name:
    mflr %r0
    stw %r1, 0(%r3)
    stw %r0, 4(%r3)
    mfcr %r0
    stw %r0, 8(%r3)
    stmw %r13, 12(%r3)
    stfd %f14, 96(%r3)
    stfd %f15, 104(%r3)
    stfd %f16, 112(%r3)
    stfd %f17, 120(%r3)
    stfd %f18, 128(%r3)
    stfd %f19, 136(%r3)
    stfd %f20, 144(%r3)
    stfd %f21, 152(%r3)
    stfd %f22, 160(%r3)
    stfd %f23, 168(%r3)
    stfd %f24, 176(%r3)
    stfd %f25, 184(%r3)
    stfd %f26, 192(%r3)
    stfd %f27, 200(%r3)
    stfd %f28, 208(%r3)
    stfd %f29, 216(%r3)
    stfd %f30, 224(%r3)
    stfd %f31, 232(%r3)
    mffs %f0
    stfd %f0, 240(%r3)
    li %r3, 0
    blr
    .size \name, . - \name
.endm

// Returns from the matching setjmp with the value, or 1 for 0.
.macro LONGJMP name
    .globl \name
    .type \name, @function
    .p2align 2
\name:
    lfd %f0, 240(%r3)
    mtfsf 0xff, %f0
    lfd %f14, 96(%r3)
    lfd %f15, 104(%r3)
    lfd %f16, 112(%r3)
    lfd %f17, 120(%r3)
    lfd %f18, 128(%r3)
    lfd %f19, 136(%r3)
    lfd %f20, 144(%r3)
    lfd %f21, 152(%r3)
    lfd %f22, 160(%r3)
    lfd %f23, 168(%r3)
    lfd %f24, 176(%r3)
    lfd %f25, 184(%r3)
    lfd %f26, 192(%r3)
    lfd %f27, 200(%r3)
    lfd %f28, 208(%r3)
    lfd %f29, 216(%r3)
    lfd %f30, 224(%r3)
    lfd %f31, 232(%r3)
    lmw %r13, 12(%r3)
    lwz %r0, 8(%r3)
    mtcr %r0
    lwz %r0, 4(%r3)
    mtlr %r0
    lwz %r1, 0(%r3)
    mr. %r3, %r4
    bnelr
    li %r3, 1
    blr
    .size \name, . - \name
.endm

SETJMP _setjmp
SETJMP __setjmp
SETJMP _sigsetjmp
LONGJMP _longjmp
LONGJMP __longjmp
LONGJMP _siglongjmp

#endif

    .section .note.GNU-stack,"",%progbits
