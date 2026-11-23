# GLKit

Perry's Swift overlay of GLKit: the element subscripts of the vector,
matrix and quaternion unions (`GLKMatrix4[i]` and the rest) and the
`_indexHomogeneousValue` they read through, written for Perry from the API
in the macOS SDK's `GLKit.swiftinterface`. It replaces the Swift 5.0
overlay Xcode ships, which a runtime directory made for an x86_64 Mac app
used to take.

It is compiled as the module `GLKit` over the SDK's headers, as Apple
builds its overlays, so its symbols are the overlay's:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh GLKit <runtime directory>

`swiftc-flags` makes it force-loadable (`-autolink-force-load`), as
Apple's is.

`Scripts/check-overlay.sh` compares its symbols with the Swift 5.0 overlay
and the SDK's `libswiftGLKit.tbd`: nothing is missing. The subscripts are
inlinable, so most programs carry their own copies.
