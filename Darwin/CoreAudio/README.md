# CoreAudio

Perry's Swift overlay of Core Audio, written for Perry from the API in the
macOS SDK's `CoreAudio.swiftinterface`: the audio hardware's objects as
classes (`AudioHardwareSystem`, devices, aggregate devices, clocks,
streams, controls, boxes, plug-ins, processes and taps, each property a
selector of `AudioHardware.h`, with listeners telling delegates of
changes), `AudioBuffer` and `AudioBufferList` as buffer pointers and
collections, `AudioChannelLayout` through pointers to it and as
`ManagedAudioChannelLayout`, a copy-on-write layout owning its memory,
and `CATapDescription`'s process IDs as Swift numbers. It replaces the
Swift 5.0 overlay Xcode ships as a file, which a runtime directory made
for an x86_64 Mac app used to take.

It is compiled as the module `CoreAudio` over the SDK's C and Objective-C
headers, as Apple builds its overlays, so its symbols are the overlay's:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh CoreAudio <runtime directory>

`swiftc-flags` gives it the `_swift_FORCE_LOAD_$_swiftCoreAudio` symbol
programs built against the overlay reference.

`Scripts/check-overlay.sh` compares its symbols with the Swift 5.0 overlay
and the SDK's `libswiftCoreAudio.tbd`. What it still lacks (6) are the
initializing entry points (`fc`) of `CATapDescription`'s six convenience
initializers, which Swift doesn't emit for an Objective-C class; the
allocating ones programs call are there.

Where the behaviour is Perry's own rather than a thin wrapper:

- an object listed by another (a system's devices, a device's streams) is
  made as the class of the Core Audio class it reports, so an aggregate
  device is an `AudioHardwareAggregateDevice`;
- a device's `clock` is the clock device of its clock UID, or the device
  itself when it names none; an aggregate's `clockSource` is its clock
  device, else its main subdevice, and `setClockSource(_:)` sets the one
  or the other by the object's class;
- `usesVariableBufferFrameSizes` is whether the device has the variable
  buffer property and it isn't zero; `toggleHogMode()` takes hog mode
  when the process hasn't it and gives it up when it has;
- the async `setPropertyData(address:qualifier:data:)` sets the property
  and reads back the value it took into `data`;
- `ManagedAudioChannelLayout.setAllToUnknown()` makes the layout one of
  channel descriptions, each with the unknown label and no flags or
  coordinates.
