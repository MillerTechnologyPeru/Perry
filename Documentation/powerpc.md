# 32-bit PowerPC (ppc) support

Perry runs ppc Mac binaries (Mac OS X 10.3 through 10.5) on 32-bit
big-endian PowerPC Linux, on a G4 or later, or under qemu-ppc with
`-cpu 7400`. Unlike armv7 and i386, ppc has no 64-bit host to hand off from:
`perry` itself is the ppc program, and its providers are ppc Linux
libraries.

## Building and running

The loader and the C providers build with a powerpc-linux-gnu cross
toolchain, such as swift-linux's:

    PPC_CC=.../powerpc-swift-linux-gnu-gcc Scripts/build-ppc-loader.sh   # .build/ppc/bin/perry

The Swift providers build with SwiftPM and a ppc destination, which names the
cross compiler, the sysroot and the Swift SDK:

    swift build --build-system native --destination toolchain.json \
        --scratch-path .build/ppc-pm -c release --product PerrySystem

Under qemu-user, with the target's libraries at `$TARGET`:

    PERRY_LIBRARY_PATH=.build/ppc-pm/powerpc-unknown-linux-gnu/release \
        qemu-ppc-static -cpu 7400 -L $TARGET \
        -E LD_LIBRARY_PATH=.build/ppc-pm/powerpc-unknown-linux-gnu/release \
        .build/ppc/bin/perry Program.app

Test programs are built with Xcode 3.2.6's own ppc toolchain, run under
Perry on the host, since today's clang has no ppc Darwin target and current
ld64 has dropped ppc: its cc1 (i386) under `perry32`, its as and ld (x86_64)
under `perry`, against the 10.6 SDK's ppc stubs:

    XCODE3=.../Xcode-3.2.6/Developer Scripts/build-ppc-fixtures.sh hello.c

`hello.c` built so prints its arguments and exits with 7 under the ppc
`perry`: crt1's start, `__dyld`, r2 stubs (GCC's code uses r2 for
addresses), and `printf$LDBL128` through the variadic thunk.

## Darwin ppc ABI, against Linux's (SysV ppc32)

- Both are big-endian, so Mach-O files are read in place. Universal headers,
  which the little-endian loaders swap, are already in host order here.
- `char` is signed on Darwin, unsigned on Linux.
- **r2 is a scratch register in Darwin's code and the thread pointer on
  Linux.** Bean's 300 KB of code writes r2 in about 2,900 instructions
  (`lis r2,6; lwz r2,-4088(r2)` loads a symbol pointer). glibc reads
  thread-local variables through r2 (errno, malloc's caches), and Linux
  compilers never reload it. So r2 has to be right at every call from
  Darwin code into Linux code, and again whenever Darwin code returns to Linux
  code. See "The thread pointer" below.
- `long long` arguments go in the next two GPRs on Darwin, and in an aligned
  pair (r3:r4, r5:r6, r7:r8, r9:r10) on Linux.
- Darwin passes floating point in f1-f13 and also skips the GPRs they would
  take (two for a double, one for a float). Linux uses f1-f8 and skips no
  GPRs. So `f(double, int)` takes the int in r5 on Darwin and in r3 on Linux.
- Darwin passes structures by value, in GPRs and then the parameter area;
  Linux passes a pointer to a copy.
- Stack arguments: Darwin's parameter area starts at 24(r1), after a 24-byte
  linkage area, and reserves words for r3-r10. Linux's starts at 8(r1). The
  9th word of arguments is at 56(r1) on Darwin and at 8(r1) on Linux.
- The return address is saved in the caller's frame at 8(r1) on Darwin and
  at 4(r1) on Linux.
- Structures come back through a pointer in r3 on both (Linux's GCC
  returns even an 8-byte structure in memory), so the receiver and selector of a message that
  returns one are in r4 and r5: `objc_msgSend_stret`.
- `va_list` is a pointer to the argument words on Darwin and a structure
  (register counts, the overflow area, the save area) on Linux. libSystem's
  printf family builds one from the other (`stdio.c`), repacking the
  arguments by reading the format, since Darwin aligns 64-bit values to 4
  bytes there and Linux to 8 (`vaformat.c`).
- In structures, `long long` is 8-byte aligned on both, and `double` 4-byte
  aligned on Darwin past the first member, 8 on Linux.
- `long double` is IBM's 128-bit double-double on both (Mac OS X 10.4 and
  later). Functions that take one have a `$LDBL128` variant on Darwin, which
  the loader binds to the plain name.
- Apple's GCC sends messages with `bla 0xfffeff00`, an absolute branch to
  the commpage's objc_msgSend (Bean has 9,708 of them, and 311 `ba` tail
  calls). On 32-bit Linux that address is the kernel's, so the loader turns
  each into a relative branch to an island just past the image, which jumps
  to libobjc's objc_msgSend.
- Images from before Mac OS X 10.6 have no `LC_DYLD_INFO`: they are bound
  through the indirect symbol table and relocations, as i386's are, and crt1
  reaches dyld through `__DATA,__dyld`.

## The thread pointer

r2 is found again from the stack pointer (`ppc_thread.c`). A table with a word
for each 4 KB page of the address space (4 MB, reserved and filled only where
there are stacks) holds the thread pointer of the thread whose stack is
there. The loader notes the main thread's stack when it starts. `perry`
exports a `pthread_create`, which takes the place of glibc's for every
library in the process, so each thread, libdispatch's too, notes its own
before it runs anything. Then seven instructions set r2 using only r0, r11,
r12 and cr0, which are scratch at a call in both ABIs:

    rlwinm r11, r1, 22, 10, 29;  lis/ori r12, table;  lwzx r0, r11, r12
    cmpwi r0, 0;  beq 1f;  mr r2, r0

- Darwin to Linux: what the loader binds a Darwin import to, when it is a
  function of a Linux library and not data (`dladdr1`'s symbol type), is a
  stub that sets r2 and jumps to it. So are `__dyld`'s entries and the
  unresolved-import stubs. Still to do: `objc_msgSend`, before it jumps to a
  method, and function pointers to Linux code that Darwin code calls
  directly (an IMP from `-methodForSelector:`, a block's invoke, `dlsym`'s
  results).
- Linux to Darwin: Linux code that calls Darwin code keeps r2 around the call
  (`PERRY_DARWIN_CALL` in the loader, for initializers and `main`;
  `PERRY_KEEP_R9` in libSystem, as armv7 keeps r9, for `qsort`'s
  comparators, thread start routines, exit handlers and thread-specific
  destructors). Still to do: libdispatch's work functions, Foundation's
  threads, libxml2's callbacks, signal handlers, and messages that providers
  send to the program's objects.

## Methods and functions with floating point or structures

A method or function whose arguments are words, pointers and objects passes
the same on both, and most do. One that takes a `double`, a `float` (a
`CGFloat`), a `long long` or a structure (`NSRect`) does not, and the 32-bit
ObjCValue types armv7 uses can't make it pass: Linux's ppc passes every
structure, `ObjCWordPair` and `ObjCWords4` included, through a pointer, and
one parameter cannot stand for the GPRs Darwin skips after a floating-point
argument. The plan is to translate by the method's type encoding, which the
macros already emit: an assembly entry takes Darwin's r3-r10, f1-f13 and
parameter area, and calls the Swift implementation with the arguments where
Linux's ABI puts them (libffi's `ffi_call`, or a small encoding-driven
shuffle of its own), and the reverse for sends from providers to the
program's methods. C entry points with such parameters (`ldexp`, `modf`,
CoreGraphics' functions) get the same moves as thunks.

## Status

- Loader: fat slices, the ppc CPU type, `LC_UNIXTHREAD`'s srr0, crt1's start
  on a kernel-style stack, classic binding and `__dyld`, unresolved-import
  stubs and the ppc crash and profiler register views. Bean's ppc slice
  is mapped at 0x1000 and bound to libPerrySystem and libPerryobjc. libobjc
  reads its classes and categories from the old ABI's `__OBJC` metadata
  (warning only of AppKit's classes, which are not built yet), its
  initializers run, and it reaches `NSApplicationMain` from `main` under
  qemu-ppc. The r2 stubs work under
  qemu-ppc with r2 wrecked before the call: `errno` and `__thread`
  variables read right, on the main thread and on a second one.
- libSystem: the C sources build for ppc. Done: the printf family's
  `va_list` and argument repacking, block trampolines, signal contexts as
  Darwin's ppc thread states, and the 32-bit file layouts from before 64-bit
  inodes.
- libobjc: `objc_msgSend` and its stret and super forms, message forwarding
  (`msgsend_ppc.S`), and the old ABI's exception entry points over Darwin's
  ppc jmp_buf. libSystem's thunks (`thunks_ppc.S`): word-only functions pass
  through, variadic functions spill r3-r10 into the caller's parameter area
  (with a glibc va_list built over it for `open`, `fcntl`, `ioctl` and
  `scanf`), 64-bit offsets move to aligned pairs, and setjmp keeps r1, lr,
  cr, r13-r31, f14-f31 and the FPSCR.
- Not yet: the rest of the thread pointer, floating-point and structure
  arguments (above), and the Swift providers past libobjc.
