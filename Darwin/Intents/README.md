# Intents

Perry's Swift overlay of Intents, written for Perry from the API in the
macOS SDK's `Intents.swiftinterface`: the intents', responses',
reservations' and resolution results' initializers and properties with
optional Swift numbers in place of the NSNumbers the headers refine for
Swift, `INShortcut` and `INMediaDestination` as Swift enums bridged to
their Objective-C classes, `INParameter` and image parameters named by key
path, and `NSString.deferredLocalizedIntentsString`. It replaces the Swift
5.0 overlay Xcode ships as a file, which a runtime directory made for an
x86_64 Mac app used to take.

It is compiled as the module `Intents` over the SDK's Objective-C headers,
as Apple builds its overlays, so its symbols are the overlay's:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh Intents <runtime directory>

`swiftc-flags` gives it the `_swift_FORCE_LOAD_$_swiftIntents` symbol
programs built against the overlay reference, and aliases the protocol
requirements base descriptor of `_INIntentSetImageKeyPath` to its protocol
descriptor: the protocol has no requirements, so nothing is reached
through the base, but Apple's compiler exported it and today's doesn't.

`Scripts/check-overlay.sh` compares its symbols with the Swift 5.0 overlay
and the SDK's `libswiftIntents.tbd`. What it still lacks (37) are the
initializing entry points (`fc`) of the convenience initializers on
Objective-C classes (`INFocusStatus(isFocused:)`, `INParameter(keyPath:)`
and those of the intents and reservations), which Swift doesn't emit for
them; the allocating ones programs call are there.

Where the behaviour is Perry's own rather than a thin wrapper:

- most of this API (the car, ride, media, workout, call, task, photo and
  reservation intents, `INParameter`, `INMediaDestination`, image
  parameters) is unavailable on macOS, as in the SDK: it's here for the
  symbols the SDK's stub lists for the library it shares with Mac Catalyst;
- `INSetProfileInCarIntent`'s older initializers, which named a profile's
  label, all go to the designated initializer, the label as the name;
  `INCallRecord`'s caller becomes its one participant;
- `INShortcut(intent:)` is nil when Intents finds the intent invalid for a
  shortcut, as the Objective-C initializer is; the enums' descriptions are
  Perry's own.
