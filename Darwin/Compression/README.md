# Compression

The Swift overlay of libcompression (`libswiftCompression.dylib`):
`OutputFilter` and `InputFilter`, with `Algorithm`, `FilterOperation` and
`FilterError`, over the library's `compression_stream`, which Perry's
provider has. The Swift 5.0 overlays Xcode ships as files have none, so a
runtime directory made from them, as an x86_64 Mac app's is, needs this
one; one made from a Simulator runtime has Apple's.

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh Compression <runtime directory>
