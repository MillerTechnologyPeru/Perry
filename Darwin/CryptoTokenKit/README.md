# CryptoTokenKit

Perry's Swift overlay of CryptoTokenKit: `TKSmartCard`'s APDU
transmission with Swift types (`send(ins:p1:p2:data:le:reply:)`, its
throwing and async forms) and `withSession(_:)`, written for Perry from
the API in the macOS SDK's `CryptoTokenKit.swiftinterface`, over the
Objective-C methods the header refines for Swift. It replaces the Swift
5.0 overlay Xcode ships as a file, which a runtime directory made for an
x86_64 Mac app used to take.

It is compiled as the module `CryptoTokenKit` over the SDK's headers:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh CryptoTokenKit <runtime directory>

`Scripts/check-overlay.sh` against the Swift 5.0 overlay and the SDK's
`libswiftCryptoTokenKit.tbd` (which only re-exports the framework) reports
nothing missing. The async `send` is `@backDeployed` in the SDK; here it is
an ordinary function, so its symbol is exported for clients that call it.
