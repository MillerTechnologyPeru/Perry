# NaturalLanguage

Perry's Swift overlay of Natural Language, written for Perry from the API
in the macOS SDK's `NaturalLanguage.swiftinterface`: the tokenizer's,
tagger's and contextual embedding result's ranges as ranges of a
String's indices, and the embeddings', models' and language recognizer's
vectors, distances and scores as Swift numbers, over the methods the
headers mark `NS_REFINED_FOR_SWIFT`. It replaces the Swift 5.0 overlay
Xcode ships as a file, which a runtime directory made for an x86_64 Mac
app used to take.

It is compiled as the module `NaturalLanguage` over the SDK's
Objective-C headers, as Apple builds its overlays, so its symbols are the
overlay's:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh NaturalLanguage <runtime directory>

`swiftc-flags` gives it the `_swift_FORCE_LOAD_$_swiftNaturalLanguage`
symbol programs built against the overlay reference.

`Scripts/check-overlay.sh` compares its symbols with the Swift 5.0 overlay
and the SDK's `libswiftNaturalLanguage.tbd`: nothing is missing.

A range the framework returns that doesn't fall on the string's
characters (NSNotFound, or one splitting a character) becomes the nearest
range of the string's UTF-16 indices rather than a trap.
