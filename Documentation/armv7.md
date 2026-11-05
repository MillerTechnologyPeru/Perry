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
  errno, setjmp-and-longjmp unwinder registration, and `thunks_arm.S` with the
  functions whose arguments and results are each one 32-bit word. Variadic
  printf and scanf read integers, pointers and strings; `long long` and
  `double` conversions need the format-driven repack described above.
- libobjc (`libPerryobjc.so` for armv7): `objc_msgSend` and its stret and super
  forms, message forwarding and block trampolines in ARM assembly; the Swift
  runtime reads metadata at the pointer width's offsets (`Layout`).
- Not yet: exceptions (`@throw`, unwinding through registered contexts), the
  rest of libSystem for Darwin's armv7 layouts and calling convention (files,
  sockets, pthreads, mach, 64-bit arguments), Foundation, UIKit, the other
  providers, `objc_msgForward_stret`, and classic relocations (iOS before 3.1).

## Building and running

    Scripts/build-armv7-loader.sh              # .build/armv7/bin/perry32
    Scripts/build-armv7-system.sh              # .build/armv7/bin/libPerrySystem.so
    Scripts/build-host-macros.sh               # .build/macros/PerryObjCMacros
    Scripts/build-armv7-objc.sh                # .build/armv7/bin/libPerryobjc.so
    Scripts/build-armv7-fixtures.sh 6.0 hello.c runtime.m
    .build/armv7/bin/perry32 .build/perry-fixtures/armv7/runtime

`Scripts/build-armv7-fixtures.sh` links with `arm-apple-darwin11-ld` from
cctools-port, installed under `.toolchains/cctools`. The armv7 Swift modules
are compiled with `swiftc` directly (`build-armv7-objc.sh`), and the macro
plugin against the swift-syntax libraries the toolchain ships, because
SwiftPM's build of swift-syntax needs more memory than a 4 GB machine has.
