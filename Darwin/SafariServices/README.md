# SafariServices

Perry's Swift overlay of SafariServices: `SFSafariServicesAvailable(_:)`,
written for Perry from the API in the macOS SDK's
`SafariServices.swiftinterface`. It replaces the Swift 5.0 overlay Xcode
ships as a file, which a runtime directory made for an x86_64 Mac app used
to take.

It is compiled as the module `SafariServices` over the SDK's headers:

    PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 Scripts/build-overlay.sh SafariServices <runtime directory>

`Scripts/check-overlay.sh` against the Swift 5.0 overlay and the SDK's
`libswiftSafariServices.tbd` reports nothing missing.

The framework tells which version of it is present through two data
symbols its header keeps from Swift, `_SFSafariServicesAvailable` and
`_SFSafariServicesVersion`, both weak imports. They are looked up with
`dlsym`, so a runtime without them answers that Safari Services isn't
available rather than failing to load.
