# MetalKit

Perry's Swift overlay of MetalKit: the throwing forms of
`MTKMesh.newMeshes(asset:device:)`,
`MTKModelIOVertexDescriptorFromMetalWithError` and
`MTKMetalVertexDescriptorFromModelIOWithError`, over the Objective-C calls
that report errors through an `NSError` out parameter (Swift-private in
the headers). Written for Perry from the API in the macOS SDK's
`MetalKit.swiftinterface`, it replaces the Swift 5.0 overlay Xcode ships,
which a runtime directory made for an x86_64 Mac app used to take.

It is compiled as the module `MetalKit` over the SDK's headers, as Apple
builds its overlays, so its symbols are the overlay's:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh MetalKit <runtime directory>

`swiftc-flags` makes it force-loadable (`-autolink-force-load`), as
Apple's is.

`Scripts/check-overlay.sh` compares its symbols with the Swift 5.0 overlay
and the SDK's `libswiftMetalKit.tbd`: nothing is missing.
