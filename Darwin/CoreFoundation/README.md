# CoreFoundation

Perry's Swift overlay of Core Foundation: `CGFloat` and `_CFObject` (the
equality and hashing of CF types, through `CFEqual` and `CFHash`), written
for Perry from the API in the macOS SDK's `CoreFoundation.swiftinterface`.
It replaces the Swift 5.0 overlay Xcode ships as a file, which a runtime
directory made for an x86_64 Mac app used to take.

It is compiled as the module `CoreFoundation` over the SDK's headers:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh CoreFoundation <runtime directory>

`Scripts/check-overlay.sh` compares its symbols with the Swift 5.0 overlay
and the SDK's `libswiftCoreFoundation.tbd`: nothing is missing.

`CGFloat` moved here from the CoreGraphics overlay; it keeps CoreGraphics'
names (`@_originallyDefinedIn`), as the SDK's does. Programs built against
a newer SDK bind it to this library, ones built against an older one to
libswiftCoreGraphics: a CoreGraphics overlay of Perry's should leave
`CGFloat` out, so both find this one (Perry's loader looks a Swift symbol
up in the other images when the library named lacks it). With a copy in
each, a program using both would see two types.
