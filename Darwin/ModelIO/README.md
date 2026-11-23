# ModelIO

Perry's Swift overlay of ModelIO: the values of `MDLMatrix4x4Array` and of
the animated values (`MDLAnimatedScalar`, `...Vector2/3/4`,
`...Matrix4x4`, `...Quaternion`, and the scalar, vector and quaternion
arrays) as Swift arrays, over the Objective-C methods that take a buffer
and a count, written for Perry from the API in the macOS SDK's
`ModelIO.swiftinterface`. It replaces the Swift 5.0 overlay Xcode ships as
a file, which a runtime directory made for an x86_64 Mac app used to take.

It is compiled as the module `ModelIO` over the SDK's Objective-C headers,
as Apple builds its overlays, so its symbols are the overlay's:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh ModelIO <runtime directory>

The `reset(...:atTimes:)` methods of single animated values require as
many values as times, as the Objective-C methods take one count for both.

`Scripts/check-overlay.sh` compares its symbols with the Swift 5.0 overlay
and the SDK's `libswiftModelIO.tbd`: nothing is missing.
