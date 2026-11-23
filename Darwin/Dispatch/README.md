# Dispatch

Perry's Swift overlay of Dispatch: `DispatchQueue`, `DispatchWorkItem`,
`DispatchGroup`, `DispatchSemaphore`, `DispatchSource`, `DispatchData`,
`DispatchIO`, the time and QoS types, queues as Swift concurrency
executors and as Combine schedulers, written for Perry from the API in the
macOS SDK's `Dispatch.swiftinterface`. It replaces the Swift 5.0 overlay
Xcode ships as a file, which a runtime directory made for an x86_64 Mac app
used to take, and the additions that were needed beside it.

It is compiled as the module `Dispatch` over the SDK's C headers, as Apple
builds its overlays, so its symbols are the overlay's:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh Dispatch <runtime directory>

`Scripts/check-overlay.sh` compares its symbols with the Swift 5.0 overlay
and the SDK's `libswiftDispatch.tbd`. What it still lacks:

- the initializing entry points (`fc`) of the convenience initializers on
  `DispatchQueue`, `DispatchSerialQueue`, `DispatchConcurrentQueue`,
  `DispatchWorkloop` and `DispatchIO`, which only a subclass's initializer
  calls (these classes can't be subclassed in Swift); the allocating ones
  programs call are there;
- `DispatchSource.makeExclavesNotificationSource`, private to Apple.

The headers leave some C functions and data out of Swift (they point to
this API instead): those are declared with `@_silgen_name`, and the
library's data (the main queue, the concurrent attribute, the source types,
the empty data and the data destructors) is reached through its symbols'
addresses.
