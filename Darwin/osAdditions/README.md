# osAdditions

Swift API of the `os` module newer than the Swift 5.0 overlay Xcode ships
as a file (`libswiftos.dylib`, which has `os_log` and `os_signpost` only):
`Logger`, `OSSignposter`, `OSSignpostIntervalState` and
`OSAllocatedUnfairLock`. A runtime directory made from that overlay, as an
x86_64 Mac app's is, needs these beside it; one made from a Simulator
runtime has them in its own `libswiftos.dylib`.

The logging and signpost methods themselves are transparent in the SDK and
compiled into the programs that call them: they need only the types, their
stored handles and the few functions here.

Build for a Mac app's runtime directory:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh osAdditions <runtime directory>
