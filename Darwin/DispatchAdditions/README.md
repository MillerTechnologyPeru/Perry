# DispatchAdditions

Swift API of the `Dispatch` overlay newer than the Swift 5.0 copy Xcode
ships as a file: `DispatchQueue`'s conformance to Combine's `Scheduler`,
with its `SchedulerTimeType` and `SchedulerOptions`. A runtime directory
made from that overlay, as an x86_64 Mac app's is, needs it beside
`libswiftDispatch.dylib`; one made from a Simulator runtime has it there.

It is compiled as the module `Dispatch` over the C headers, as other
additions are, so it declares again the overlay's types its API names
(`DispatchTime`, `DispatchQoS`), laid out as the overlay's are.

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh DispatchAdditions <runtime directory>
