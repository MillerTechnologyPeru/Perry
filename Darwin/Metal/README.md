# Metal

Perry's Swift overlay of Metal: the array and range forms of the encoder,
buffer, texture, residency set and function table calls (over the
Swift-private pointer-and-count and `NSRange` ones), the device's sample
positions, timestamps and mesh pipelines, `MTLLogContainer`, the async
waits of command buffers and shared events, the rasterization-rate and
tensor-extent initializers, and Metal 4's queues, encoders, compiler and
archives, written for Perry from the API in the macOS SDK's
`Metal.swiftinterface`. It replaces the Swift 5.0 overlay Xcode ships,
which a runtime directory made for an x86_64 Mac app used to take.

It is compiled as the module `Metal` over the SDK's headers, as Apple
builds its overlays, so its symbols are the overlay's:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh Metal <runtime directory>

`swiftc-flags` makes it force-loadable (`-autolink-force-load`), as
Apple's is.

Where it differs from Apple's:

- `MTLCommandBuffer.scheduled()` and `completed()` wait for the buffer with
  `waitUntilScheduled`/`waitUntilCompleted` on a thread of their own; the
  interface's inlinable code on macOS 26 and later sends Metal's private
  `__waitUntil…Async:` messages instead, which `__MTLObjCProxy` declares as
  the interface does.
- `MTLSharedEvent.valueSignaled(_:)` listens with a listener of its own
  rather than the shared one of macOS 26.
- The Metal 4 compiler's async calls wrap the completion-handler forms.

`Scripts/check-overlay.sh` compares its symbols with the Swift 5.0 overlay
and the SDK's `libswiftMetal.tbd`. What it still lacks are the
initializing entry points (`fc`) of the convenience initializers on
Objective-C classes, which Swift doesn't emit for them (only a subclass's
initializer would call one); the allocating ones programs call are there:

- `MTLTensorExtents.init(_:)`
- `MTLRasterizationRateLayerDescriptor.init(horizontal:vertical:)`
- `MTLRasterizationRateMapDescriptor.init(screenSize:label:)`,
  `init(screenSize:layer:label:)` and `init(screenSize:layers:label:)`
