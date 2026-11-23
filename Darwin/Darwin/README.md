# Darwin

Perry's Swift overlay of the C library: `DarwinBoolean`, `POSIXErrorCode`,
`MachErrorCode` and `errno`, the `<math.h>` overloads for `Float` and
`Float80` and the generic ones over `FloatingPoint`, the `<float.h>` and
`<math.h>` constants, `stdin`/`stdout`/`stderr`, the fixed forms of
`open`, `openat`, `fcntl`, `ioctl` and `sem_open`, `dprintf` and
`snprintf`, the file modes, signal handlers and terminal ioctl requests the
headers define as macros, `timeval`/`timespec` and `Duration`, and
`audit_token_t` as a value; written for Perry from the API in the macOS
SDK's `Darwin.swiftinterface` and the interfaces of the modules newer SDKs
split it into (`_DarwinFoundation1`, `_DarwinFoundation2`,
`_DarwinFoundation3`, `_Builtin_float`). It replaces the Swift 5.0
overlay Xcode ships as a file, which a runtime directory made for an
x86_64 Mac app used to take.

It is compiled as the module `Darwin` over the SDK's C headers:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh Darwin <runtime directory>

`include/` holds an interface for each split module that is the C module
alone: the SDK's Swift overlays of them declare, under the module name
`Darwin`, what this overlay declares itself, and would collide with it.

`Scripts/check-overlay.sh` compares its symbols with the Swift 5.0 overlay
and the SDK's `.tbd` stubs; with all of them nothing is missing:

    Scripts/check-overlay.sh <dylib> "$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-5.0/macosx/libswiftDarwin.dylib" \
      "$(xcrun --sdk macosx --show-sdk-path)"/usr/lib/swift/libswift{Darwin,_DarwinFoundation1,_DarwinFoundation2,_DarwinFoundation3,_Builtin_float}.tbd

Programs built against a newer SDK link the split libraries
(`libswift_DarwinFoundation1.dylib` and the rest) by name, where the SDK's
`libswiftDarwin` re-exports them; this one library defines all their
symbols, so a runtime directory needs those names to lead here.

How some of it behaves:

- A variadic C function (`open` with a mode, `fcntl` and `ioctl` with an
  argument, `sem_open`) is called through a prototype of its own with the
  extra argument fixed, which the x86_64 calling convention passes as it
  passes a variadic one. An arm64 build would need these in C.
- `fork()` and `vfork()` call the C functions; Swift marks them unavailable
  to programs, so none do.
- `TIOCGETD` and `TIOCSETD` are `<sys/ttycom.h>`'s requests, not the old
  ones `USE_OLD_TTY` defines; every other request is computed as `_IO`,
  `_IOR` and `_IOW` compute it, `TIOCREMOTE` (gone from the headers) as it
  was.
- `ilogb` answers as the C function does for zero, NaN (`INT_MIN`) and
  infinity (`INT_MAX`).
- `errno` is read and written where `__error()` points; `environ` is
  `*_NSGetEnviron()`.
