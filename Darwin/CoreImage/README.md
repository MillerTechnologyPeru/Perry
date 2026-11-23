# CoreImage

Perry's Swift overlay of CoreImage. Neither the Swift 5.0 overlay Xcode
ships nor the macOS SDK's `CoreImage.swiftinterface` has API of its own
(the Swift API is the framework's Objective-C one): the library is there
for the symbol programs built against the SDK force-load,
`__swift_FORCE_LOAD_$_swiftCoreImage`, which `swiftc-flags` makes it
export.

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh CoreImage <runtime directory>

`Scripts/check-overlay.sh` compares its symbols with the Swift 5.0 overlay
and the SDK's `libswiftCoreImage.tbd`: nothing is missing.
