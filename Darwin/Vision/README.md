# Vision

Perry's Swift overlay of Vision: `VNFaceLandmarkRegion2D`'s points as
arrays of `CGPoint`, as the Swift 5.0 overlay Xcode ships as a file had
them, which a runtime directory made for an x86_64 Mac app used to take.

Vision's Swift API has since moved into the framework itself (the SDK's
`usr/lib/swift/Vision.swiftmodule` only re-exports it, and its
`libswiftVision.tbd` lists no Swift symbols), so the 5.0 overlay is what
`libswiftVision.dylib` must still export: programs built against an SDK
with the overlay bind these symbols to it. Beside them it has the
framework's `precisionEstimatesPerPoint` and
`VNFaceObservation.faceCaptureQuality` as Floats, the same thin kind of
wrapper; the rest of the framework's Swift API (the Swift request and
observation types of macOS 15) isn't here.

It is compiled as the module `Vision` over the SDK's Objective-C headers,
as Apple builds its overlays, so its symbols are the overlay's:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh Vision <runtime directory>

`swiftc-flags` gives it the `_swift_FORCE_LOAD_$_swiftVision` symbol
programs built against the overlay reference.

`Scripts/check-overlay.sh` compares its symbols with the Swift 5.0 overlay
and the SDK's `libswiftVision.tbd`: nothing is missing.

The Objective-C getters these properties shadow are reached through an
`@objc` protocol declaring their selectors, as Swift code in the module
can't name them past its own declarations.
