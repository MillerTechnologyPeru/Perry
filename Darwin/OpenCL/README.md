# OpenCL

Perry's Swift overlay of OpenCL: `clSetKernelArgsListAPPLE`, whose C form
takes varargs Swift doesn't import; the overlay passes Swift's `CVarArg`s
through the `va_list` form, `clSetKernelArgsVaListAPPLE`. Written for
Perry from the API in the macOS SDK's `OpenCL.swiftinterface`, it replaces
the Swift 5.0 overlay Xcode ships, which a runtime directory made for an
x86_64 Mac app used to take.

It is compiled as the module `OpenCL` over the SDK's C headers, as Apple
builds its overlays, so its symbols are the overlay's:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh OpenCL <runtime directory>

`swiftc-flags` makes it force-loadable (`-autolink-force-load`), as
Apple's is.

`Scripts/check-overlay.sh` compares its symbols with the Swift 5.0 overlay
and the SDK's `libswiftOpenCL.tbd`: nothing is missing.
