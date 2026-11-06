# 32-bit ARM (armv7) support

Perry runs armv7 iOS binaries, Objective-C and C only (no Swift apps, no
SwiftUI), for iOS 2 through 10.

## Architecture

A process is either AArch64 or AArch32, so armv7 Mach-O cannot be mapped into
`perry`. The loader and every provider are built a second time for
`armv7-unknown-linux-gnueabihf` and run as a 32-bit process, `perry32`. `perry`
looks at a program's architectures (`perry_macho_architectures`) and runs
`perry32`, beside it or at `$PERRY32`, when the program has armv7 code and no
arm64 code. The kernel must run 32-bit ARM programs (`CONFIG_COMPAT`, and
cores with AArch32 at EL0; `dmesg` says `32-bit EL0 Support`).

`PerryLoaderCore` is one source for both: `mach_header_t`, `segment_command_t`
and `section_t` name the structures of the loader's own pointer width.

## Toolchain

Providers are Swift, so they need Swift for armv7. The Swift 6.4.0 SDK from
swift-embedded-linux/armhf-debian provides it. With the Swift 6.4.0 toolchain
for the host (the SDK is built against exactly 6.4.0):

    swiftc -target armv7-unknown-linux-gnueabihf -use-ld=lld \
        -Xcc --gcc-toolchain=$SDK/usr -resource-dir $SDK/usr/lib/swift \
        -sdk $SDK -latomic -tools-directory $HOST_SWIFT_BIN hello.swift

`Scripts/build-armv7-loader.sh` builds `perry32` with clang from `.toolchains`.

Linking armv7 Mach-O test programs needs a linker that supports it: lld's
Mach-O port does not, Apple's `ld64` (cctools-port) does.

## Darwin armv7 ABI, against Linux's armhf

Checked with clang for `armv7-apple-ios` against `armv7-linux-gnueabihf`.

- `char` is signed on Darwin, unsigned on Linux.
- 64-bit integers and doubles are 4-byte aligned, in structs too: `struct {
  char c; long long x; double d; }` is 16 bytes on Darwin, 24 on Linux.
- Arguments of 64 bits are not aligned to an even register pair: for
  `f(int a, long long b, int c)` Darwin passes `b` in r1:r2 and `c` in r3;
  Linux passes `b` in r2:r3 and `c` on the stack. Every provider function with
  a 64-bit parameter (`off_t`, `int64_t`, `double` in soft-float) needs an
  entry that moves them.
- Darwin passes floating point in core registers (soft-float); Linux armhf
  passes it in VFP registers.
- Variadic arguments are laid out contiguously from r1 on: a 64-bit value takes
  the next two words wherever they are, and a double can be split between r3 and
  the stack. `va_list` is a pointer to that area. glibc's `v*` functions expect
  AAPCS alignment, so libSystem's printf family has to repack the arguments by
  reading the format.
- The stack is 4-byte aligned at calls on Darwin (`S32`), 8 on Linux. Entry
  points that call into C on Linux realign the stack (see `tlv_thunk.S`).
- `long double` is `double` on both.
- A structure over 4 bytes is returned through a pointer the caller passes
  in r0, so the receiver and selector of a message returning one are in r1
  and r2: `objc_msgSend_stret`. `ObjCValue.objCReturnsIndirectly` says
  which results need it, and `ObjCRuntime.msgSend(returning:)` picks the
  send.
- r9 is a scratch register in Darwin's code (since iOS 3) and callee-saved in
  Linux's. Perry's armv7 code is built with `-ffixed-r9`, so it keeps nothing
  there across a call into Darwin code. Linux libraries do, so where one calls
  back into Darwin code, directly or through Perry's, r9 is saved around it:
  libSystem's `qsort`, `pthread_create`, `atexit` and thread-specific
  destructors (`PERRY_KEEP_R9`, `callbacks.c`), and libdispatch's work
  functions, Foundation's threads and libxml2's SAX callbacks
  (`keepingLinuxRegisters`). `callbacks.m` changes r9 in each such callback.
- Functions are Thumb or ARM; a function pointer's low bit says which. Export
  trie addresses and `N_ARM_THUMB_DEF` symbols carry it. Providers' `dlsym`
  results already have it.
- iOS before 6 starts executables with `LC_UNIXTHREAD`; Perry calls `_main`.
- Images before iOS 3.1 have no `LC_DYLD_INFO` (classic relocations): not yet.

## Status

armv7 C and Objective-C programs run, built with ld64 for iOS 5 (`LC_UNIXTHREAD`)
and iOS 6 (`LC_MAIN`), under `perry32` or through `perry`, which hands them
over. The Objective-C runtime fixture (`runtime.m`: `+initialize`, super sends,
introspection, ARC deallocation, `__weak`, associated objects, autorelease
pools, unrecognized selectors) prints what it does on arm64, byte for byte.

- Loader: 32-bit headers, segments, fat slice choice, `LC_UNIXTHREAD`, dyld
  info rebase and bind, unresolved-import stubs, `tlv_get_addr` and the
  Objective-C report for armv7. Chained fixups stay 64-bit.
- libSystem (`libPerrySystem.so` for armv7): the streams, process startup,
  errno, setjmp-and-longjmp unwinder registration, `mmap` with Darwin's flags,
  and `thunks_arm.S`: the functions whose arguments and results are each one
  32-bit word pass through, and `lseek`, `pread`, `pwrite`, `ftruncate`,
  `truncate`, `fseeko`, `ftello` and `mmap` have adapters that move their
  64-bit offsets and call glibc's *64 forms. The printf family repacks its
  variadic arguments by reading the format (`vaformat.c`), so `long long` and
  floating-point conversions are read as on arm64. `fopen` is `fopen64`, since
  Darwin's files are always large files. Files (`files.c`) work: `open` and
  `fcntl` through their variadic thunks, the 108-byte `struct stat` that
  Darwin's armv7 lays out with 4-byte alignment, `dirent`, errno numbers.
  All of libSystem's sources build for armv7. pthread objects have Darwin's
  32-bit sizes (mutex 44 bytes, condition 28, read-write lock 128, once 8)
  and 32-bit signatures; glibc's armhf objects fit inside them. libm and the
  rest of libc's floating point (`strtod`, `atof`, `difftime`, `drand48`)
  are wrappers in `math.c` with `pcs("aapcs")` (`DARWIN_FLOAT_ABI`), which
  takes and returns floating point in core registers; `jn` and `yn`, whose
  double follows an int, take its two words. Signal handlers and
  `thread_get_state` see Darwin's 32-bit machine context (`PerryContext.h`:
  r0-r12, sp, lr, pc, cpsr; the VFP registers from Linux's `uc_regspace`;
  the exception state). `dyld.c` and `mach.c` read 32-bit Mach-O headers,
  segments and sections (`MachO.h`), and `getsectbynamefromheader` finds a
  32-bit image's sections. The device is an iPhone 4S (`iPhone4,1`, N94AP,
  CPU_TYPE_ARM, armv7) with 4 KB pages. `system.c` checks threads, libm,
  signal handlers and socket options against macOS.
- libobjc (`libPerryobjc.so` for armv7): `objc_msgSend` and its stret and super
  forms, message forwarding and block trampolines in ARM assembly; the Swift
  runtime reads metadata at the pointer width's offsets (`Layout`).
- Foundation (`libPerryFoundation.so`, with `libPerrydispatch.so`): the
  `foundation_abi.m` fixture prints what macOS's Foundation does. Variadic
  functions and methods (`variadic_arm.S`) pass a pointer to Darwin's
  contiguous argument words, which `DarwinArguments` reads a word at a time,
  or two for `long long` and `double`. KVO's setter (`kvo_arm.S`) passes on
  r0-r3 and 16 words of stack arguments. KVC calls accessors with structures
  through C function types, as Darwin's armv7 passes them in words and
  returns those over 4 bytes through a pointer in r0. Literals, blocks,
  callbacks and the fast enumeration state are read at word offsets
  (`DarwinLayout`). Exported number constants have 8-byte slots, and a
  `CGFloat` constant is a float.
- Floating point and 64-bit integers between Darwin code and Swift: Darwin
  passes `float` and `double` in core registers, where Swift on armhf passes
  them in VFP registers, and passes 64-bit values in the next two words,
  where armhf aligns them to an even register pair. On 32-bit, `ObjCValue`
  gives `Double`, `Int64` and `UInt64` the ABI type `ObjCWordPair` (a C
  structure of two words, which armhf passes word by word as Darwin does)
  and the result type `UInt64` (r0 and r1), and `Float` a `UInt32`. The
  macros' method thunks and message sends use them, so Objective-C methods
  are right both ways. C entry points with such parameters or results name
  them as `Double.ObjCType` and `Double.ObjCResultType` and convert them
  (Foundation's CF time and date functions, libdispatch's times and
  offsets); the same types are the native ones on arm64. The type encodings
  are 32-bit Darwin's: `NSInteger` is `i`, `BOOL` `c`, offsets in words.
- Exceptions: Darwin's armv7 code registers a setjmp context in each
  function with handlers or cleanups, and libSystem unwinds through them in
  two phases, as libunwind's Unwind-sjlj.c does (`runtime.c`), longjmping to
  the handler's dispatch code (`perry_sjlj_longjmp`). libobjc's personality
  routine reads LLVM's SjLj exception tables and matches catch clauses by
  class, `id` or catch-all (`exceptions_arm.c`), with `objc_exception_throw`,
  `objc_exception_rethrow`, `objc_begin_catch` and `objc_end_catch`.
  Foundation's `OBJC_EHTYPE_$_NSException` has no class, since NSException's
  is made at startup, and is matched by name. An exception Foundation raises
  unwinds through its Swift frames to the program's handler; one none
  catches goes to the uncaught exception handler. Without
  `-fobjc-arc-exceptions`, ARC does not release objects an exception leaves,
  as on Darwin. `exceptions.m` checks this against macOS. arm64 still cannot
  unwind Mach-O frames.
- Graphics: `CGFloat` is a float on armv7, as on 32-bit Darwin, in the C
  geometry (`PERRY_CGFLOAT`) and in CoreGraphics, QuartzCore, UIKit and
  MapKit; their code converts where CGFloats meet the doubles Cairo, SDL
  and Core Animation's arithmetic use. Geometry crosses Objective-C methods
  as its words (`ObjCStructure`, `ObjCWords4` for a CGRect), since Darwin
  passes structures of floats in core registers. C functions with floating
  point or geometry are `@DarwinC("_Name")`: the macro exports a wrapper
  under the Darwin name that takes those as their ObjCType, and the function
  unchanged as `perry_native_Name`, which QuartzCore's and UIKit's bindings
  for CoreGraphics prefer, so providers call each other as Swift does. The
  loader loads Foundation's provider with CoreGraphics', as CoreGraphics
  links CoreFoundation. `graphics.c` checks geometry, transforms, colors,
  paths and drawing against macOS. libdispatch's Darwin objects and blocks
  are laid out at the word size (`DarwinLayout`). `uikit_abi.m` checks a
  view's geometry, a subclass's `-sizeThatFits:`, `-pointInside:withEvent:`
  and `-drawRect:` as UIKit calls them, colors and Bézier paths against Mac
  Catalyst, with no display.
- Not yet: C++ exceptions (`__gxx_personality_sj0`), the remaining files.c
  entry points, the rest of Foundation's coverage, UIKit's live view and
  apps on armv7, the variadic formats and `double` functions of the wrapped
  libraries (SQLite, libxml2, zlib) and r9 around the Darwin callbacks they
  call, r9 around libdispatch's finalizers and the destructors of
  thread-specific keys past the reserved ones, `objc_msgForward_stret`, and
  classic relocations (iOS before 3.1).

## Building and running

    Scripts/build-armv7-loader.sh              # .build/armv7/bin/perry32
    Scripts/build-armv7-system.sh              # .build/armv7/bin/libPerrySystem.so
    Scripts/build-host-macros.sh               # .build/macros/PerryObjCMacros
    Scripts/build-armv7-objc.sh                # .build/armv7/bin/libPerryobjc.so
    Scripts/build-armv7-fixtures.sh 6.0 hello.c runtime.m foundation_abi.m
    .build/armv7/bin/perry32 .build/perry-fixtures/armv7/runtime

`Scripts/build-armv7-fixtures.sh` compiles with `-mfloat-abi=softfp`, as
Apple's armv7 code is built, and links with `arm-apple-darwin11-ld` from
cctools-port, installed under `.toolchains/cctools`.

The Swift providers build with SwiftPM in the arm64 Linux container, on a
machine with the memory for swift-syntax (a 4 GB one does not have it):

    Scripts/build-armv7-swiftpm.sh             # Perryobjc, Perrydispatch, PerryFoundation
    Scripts/build-armv7-swiftpm.sh Perryobjc   # one product

They go to `.build/armv7-pm/armv7-unknown-linux-gnueabihf/release`, built
with the 6.4.0 toolchain the SDK matches, and are copied to `.build/armv7/bin`
beside `perry32`. SwiftPM runs the macros and the
provider generator on the host; pkg-config reads the SDK's `.pc` files, so
libxml2 is the SDK's armv7 build. A library's runpath names the SDK as the
container sees it (`/perry/.toolchains/...`), so elsewhere put the SDK's
`usr/lib/swift/linux` on `LD_LIBRARY_PATH`.

Apple silicon has no AArch32, but Docker Desktop runs armv7 programs with
qemu-arm, which finds Linux's armhf libraries through `QEMU_LD_PREFIX`.
`Scripts/docker-test.sh` sets it to the SDK, so the armv7 tests
(`ARMv7Tests`) run with the rest wherever `perry32`, its providers and the
fixtures are built. A machine whose kernel runs 32-bit ARM programs needs
nothing more. qemu-user returns nothing for a 32-bit program's
`SO_RCVTIMEO`, so under qemu the `system.c` test leaves that line out. The `libPerryobjc.so` SwiftPM builds runs the fixtures as the
one `build-armv7-objc.sh` builds does. On a machine without the memory,
`build-armv7-objc.sh` compiles the modules with `swiftc` directly and
`build-host-macros.sh` the macro plugin against the swift-syntax libraries
the toolchain ships.
