# IOKit

Perry's Swift overlay of IOKit: the `kIOReturn…` error codes, which the
header builds with the `iokit_common_err()` macro Swift doesn't import,
written for Perry from the API in the macOS SDK's `IOKit.swiftinterface`.
It replaces the Swift 5.0 overlay Xcode ships, which a runtime directory
made for an x86_64 Mac app used to take.

It is compiled as the module `IOKit` over the SDK's C headers, as Apple
builds its overlays, so its symbols are the overlay's:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh IOKit <runtime directory>

`swiftc-flags` makes it force-loadable (`-autolink-force-load`), as
Apple's is: programs built against the SDK reference
`__swift_FORCE_LOAD_$_swiftIOKit`.

`Scripts/check-overlay.sh` compares its symbols with the Swift 5.0 overlay
and the SDK's `libswiftIOKit.tbd`: nothing is missing.
