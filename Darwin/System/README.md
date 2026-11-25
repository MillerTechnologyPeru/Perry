# System

Perry's System is apple/swift-system, fetched at a pinned release (1.8.1)
by `Scripts/build-system.sh` and compiled as the module `System`, as Apple
builds `libswiftSystem` from the same sources: library evolution, each
release's availability from the package's table, the Swift 6 language
mode, CSystem's C shims linked in, and Linux's IORing left out. swift-system
is Apache 2.0 licensed, so it is not copied here; `Sources/` holds only
what Perry adds:

- `ABI.swift`: `FileDescriptor`'s `_duplicate(as:retryOnInterrupt:)` and
  `_read(into:retryOnInterrupt:)` under the symbols of their throwing forms,
  which Apple's library exports and the sources no longer declare,
  forwarding to the non-throwing ones.

The script also aliases `MachPortRight`'s protocol requirements base
descriptor to its protocol descriptor: the protocol has no requirements,
and Apple's compiler exported one that today's doesn't.

    Scripts/build-system.sh <runtime directory>
    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-system.sh <runtime directory>

`Scripts/check-overlay.sh` finds nothing missing against the iOS
Simulator's `libswiftSystem.dylib`. Against the SDKs' `libswiftSystem.tbd`
it lists what iOS and macOS 27 add that the open-source releases don't
have: `SensitiveRawBuffer`, and on macOS `Mach.Port`'s context
(`init(name:context:)`, `_context`, `relinquish()`,
`withBorrowedName(body:)`).
