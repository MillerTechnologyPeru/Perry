# QuartzCore

Perry's Swift overlay of QuartzCore: `CATransform3D` bridged to `NSValue`
(so it goes in and out of animation values and key paths), and
`CAFrameRateRange`'s initializer, optional preferred rate and equality,
written for Perry from the API in the macOS SDK's
`QuartzCore.swiftinterface`. It replaces the Swift 5.0 overlay Xcode
ships, which a runtime directory made for an x86_64 Mac app used to take.

It is compiled as the module `QuartzCore` over the SDK's headers, as Apple
builds its overlays, so its symbols are the overlay's:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh QuartzCore <runtime directory>

`swiftc-flags` makes it force-loadable (`-autolink-force-load`), as
Apple's is.

The C struct keeps 0 for a frame rate range with no preferred rate; the
overlay shows that as `nil`, and stores `nil` as 0. A nil `NSValue`
bridges to an all-zero transform, as Objective-C messaging nil would
give.

`Scripts/check-overlay.sh` compares its symbols with the Swift 5.0 overlay
and the SDK's `libswiftQuartzCore.tbd`. What it still lacks:

- `CACornerRadii.==` and its `Equatable` conformance: `CACornerRadii` is
  in no public header, so there is no type to extend (Apple-private).
