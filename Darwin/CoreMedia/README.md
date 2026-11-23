# CoreMedia

Perry's Swift overlay of Core Media: `CMTime` and `CMTimeRange`'s
initializers, properties and operators, `Equatable` and `Comparable`, and
the `CMTIME_IS_…` and `CMTIMERANGE_IS_…` macros as functions, over Core
Media's C functions, as the Swift 5.0 overlay Xcode ships as a file had
them, which a runtime directory made for an x86_64 Mac app used to take.

Core Media's Swift API has since moved into the framework itself (its
`CoreMedia.swiftmodule` is in `CoreMedia.framework`, and the SDK's
`libswiftCoreMedia.tbd` lists no Swift symbols), so the 5.0 overlay is what
`libswiftCoreMedia.dylib` must still export: programs built against an SDK
with the overlay bind these symbols to it. Beside them it has the
framework's `Hashable` conformances of both types (equal times hash alike:
1/2 and 2/4 do); the framework's other Swift API (sample buffers, format
descriptions, tags, attachments) isn't here.

It is compiled as the module `CoreMedia` over the SDK's C headers, as
Apple builds its overlays, so its symbols are the overlay's:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh CoreMedia <runtime directory>

`swiftc-flags` gives it the `_swift_FORCE_LOAD_$_swiftCoreMedia` symbol
programs built against the overlay reference.

`Scripts/check-overlay.sh` compares its symbols with the Swift 5.0 overlay
and the SDK's `libswiftCoreMedia.tbd`: nothing is missing.
