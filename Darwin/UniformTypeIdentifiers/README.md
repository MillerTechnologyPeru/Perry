# UniformTypeIdentifiers

The Swift overlay of UniformTypeIdentifiers (`libswiftUniformTypeIdentifiers.dylib`):
the `UTType` and `UTTagClass` values over the Objective-C `UTType` class,
which Perry's provider has. The Swift 5.0 overlays Xcode ships as files
have none, the framework being newer, so a runtime directory made from
them, as an x86_64 Mac app's is, needs this one; one made from a Simulator
runtime has Apple's.

`NSItemProvider`'s methods that take a `UTType` and
`URLResourceValues.contentType` are not here.

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh UniformTypeIdentifiers <runtime directory>
