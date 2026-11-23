# MapKit

Perry's Swift overlay of MapKit: `MKCoordinateSpan` bridged to `NSValue`,
as the Swift 5.0 overlay Xcode ships as a file had it, which a runtime
directory made for an x86_64 Mac app used to take.

MapKit's Swift API has since moved into the framework itself (its
`MapKit.swiftmodule` is in `MapKit.framework`, and the SDK's
`libswiftMapKit.tbd` lists no Swift symbols), so the 5.0 overlay is what
`libswiftMapKit.dylib` must still export: programs built against an SDK
with the overlay bind these symbols to it. Beside them it has the
framework's thin wrappers of `NS_REFINED_FOR_SWIFT` methods,
`MKMultiPoint.locations(at:)` and `MKGradientPolylineRenderer`'s
`locations` and `setColors(_:locations:)`; the framework's other Swift
API (`PlaceDescriptor`, `MKMapItem.Identifier`, the selection accessory's
styles) isn't here.

It is compiled as the module `MapKit` over the SDK's Objective-C headers,
as Apple builds its overlays, so its symbols are the overlay's:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh MapKit <runtime directory>

`swiftc-flags` gives it the `_swift_FORCE_LOAD_$_swiftMapKit` symbol
programs built against the overlay reference.

`Scripts/check-overlay.sh` compares its symbols with the Swift 5.0 overlay
and the SDK's `libswiftMapKit.tbd`: nothing is missing.
