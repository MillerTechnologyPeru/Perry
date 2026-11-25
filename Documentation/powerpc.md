# 32-bit PowerPC (ppc) support

Perry runs ppc Mac binaries (Mac OS X 10.3 through 10.5) on 32-bit
big-endian PowerPC Linux, on a G4 or later, or under qemu-ppc with
`-cpu 7400`. Unlike armv7 and i386, ppc has no 64-bit host to hand off from:
`perry` itself is the ppc program, and its providers are ppc Linux
libraries.

## Building and running

The loader and the C providers build with a powerpc-linux-gnu cross
toolchain, such as swift-linux's, or Debian's and Ubuntu's
`gcc-powerpc-linux-gnu` (and `g++-powerpc-linux-gnu` for
build-ppc-sysroot.sh), whose libraries are in `/usr/powerpc-linux-gnu`:

    PPC_CC=.../powerpc-swift-linux-gnu-gcc Scripts/build-ppc-loader.sh   # .build/ppc/bin/perry
    PPC_CC=powerpc-linux-gnu-gcc Scripts/build-ppc-carbon.sh            # .build/ppc/bin/libPerryCarbon.so
    PPC_CC=powerpc-linux-gnu-gcc Scripts/build-ppc-sysroot.sh           # .toolchains/ppc-sysroot

`Scripts/test-ppc-smoke.sh` runs what they built under qemu-ppc: `perry`
starts, reads its options and refuses a file that is not a ppc Mach-O, and
each library resolves its own. CI builds and checks them so (on Ubuntu, with
`qemu-user`); it has no ppc Mac program to run, since those need Xcode 3.2.6.

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
- Linux to Darwin: a Darwin function saves its lr at 8(r1) of its caller's
  frame, where Linux code keeps its own registers (Swift's code saves r30
  there), and may store r3-r10 from 24(r1). So Linux code calls Darwin code
  from a frame laid out as a Darwin caller's, keeping r2 around the call:
  `PERRY_DARWIN_CALL` in the loader, for initializers and `main`; the
  loader's sends, for messages; and for the rest a stub
  (`perry_ppc_linux_callable`) that branches to
  `perry_ppc_darwin_from_linux`, which makes that frame. Providers ask for
  it with `darwinCallable` (Swift) or `PERRY_DARWIN_FUNCTION` (C): blocks'
  invoke functions (`ObjCBlock.function(as:)` and each provider's
  `Blocks`), libdispatch's work functions and finalizers, `qsort`'s and
  `bsearch`'s comparators, thread start routines, exit handlers,
  thread-specific destructors and the once functions. Its arguments must be
  words, or floating point after every word. Still to do: Darwin function
  pointers that providers keep as callbacks (CoreFoundation's collection
  and run loop callbacks, libxml2's).
- Signals: the kernel enters a handler with r2 as the interrupted code left
  it, so Perry's handlers (libSystem's, which calls the program's, and the
  loader's crash and profiling handlers) are entered through the r2 stub,
  and `sigaltstack`'s stacks are noted in the table too.

## Methods and functions with floating point or structures

A method or function whose arguments are words, pointers and objects passes
the same on both, and most do. One that takes a `double`, a `float` (a
`CGFloat`), a `long long` or a structure (`NSRect`) does not: Darwin passes
a double or float in an FPR and skips the GPRs it would have taken, a
structure in its words, and a long long in the next two words; Linux skips
no GPRs, passes every structure through a pointer, and aligns a long long to
an even register pair.

**C functions** (`@DarwinC`) take Darwin's arguments where Darwin leaves
them. On ppc the macro gives `__darwin_<name>` a parameter list that puts,
under Linux's rules, each argument in Darwin's register: a double or float as
itself (an FPR on both), followed by `UInt32` words standing for the GPRs
Darwin skips; a long long and a structure as their words, which the body
reassembles (`PPCWords`). Results pass the same on both (r3, r3:r4, f1, or
a structure through a pointer in r3). This costs nothing at run time. It
holds while the arguments fit in r3-r10 and f1-f8; past them the two stack
areas differ (Darwin's has room for the register arguments, at 24(r1);
Linux's starts at 8(r1)), so such a function is exported instead as
`perry_ppc_moved_<name>` with its 32-bit ObjCType signature, and
`perry_ppc_types_<name>` gives its type encoding: the loader binds it
through a stub that moves the arguments by that encoding. `libSystem`'s math
functions use the same padding by hand (`math.c`). Providers call each
other's such functions by their `perry_native_` names, with Swift's types.

**Methods** carry their type encodings in the Objective-C runtime already, so
they are moved by encoding at run time (`ppc_abi.c`, `ppc_abi.S`). On ppc,
as on i386 and 64-bit, ObjCValue's types are the types themselves (a
`Double` is a `Double`, a `CGRect` a `CGRect`), and the loader moves
arguments between Darwin's places and where Linux's ABI puts those types:
doubles and floats in f1-f8, a long long in an even register pair, a
structure through a pointer to a copy. A provider's method is added as its
Darwin entry, a stub that takes Darwin's arguments and calls the Swift
implementation with them where Linux has them. A provider's sends go through
the loader's sends (`perry_ppc_send` and its forms), which call the method
as Darwin code would. Both are driven by the method's encoding, so a
provider's send to another provider's method arrives as it left, and Swift's
sends and methods, the macros' and those written by hand, are right as they
are.

**NSInvocation and key-value coding** call a method's IMP with arguments
they hold as bytes. On ppc every IMP is Darwin code or a provider's Darwin
entry, so they give the loader the bytes and the encoding
(`perry_ppc_call_darwin_values`, through Foundation's `DarwinCalls`), which
lays them out as Darwin's caller would and reads the result from r3, r3:r4,
f1 or memory. Forwarding (`-forwardInvocation:`), which would capture a
message's arguments into an NSInvocation, is not done on ppc yet.

`Scripts/test-ppc-abi.sh` checks the moves against code Apple's own GCC
compiled, and `Tests/Fixtures/ppc_runtime.m`, built with
`Scripts/build-ppc-fixtures.sh`, the callbacks, signals, NSInvocation and
key-value coding under perry.

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
