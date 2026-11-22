---
name: Prime Video
bundle_id: "com.amazon.aiv.AIVApp"
platform: maccatalyst
kind: app
tags: [Swift, ObjC]
reports:
  - pr: 276
    date: 2026-11-22
    perry: "3d09cce7"
    platform: maccatalyst
    cpu: x86_64
    app_version: "10.157"
    hardware: Dell OptiPlex 7020
    os: Debian 13
    env:
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
      - "PERRY_CRASH_REPORT=1"
    level: 1
    source: maintainer
    notes: Runs into its launch code (Weblab client, Crashlytics, keychain, network monitor, configuration), then crashes at UTType, which the x86_64 Swift runtime lacks; no screen confirmed. Run on an older source copy with these changes patched in.
---

The Mac App Store build, a universal Mac Catalyst app; its x86_64 slice was run.

It runs with the Swift runtime directory (`PERRY_SWIFT_RUNTIME`) the x86_64
WhatsApp report describes, with three pieces built on a Mac added to it:
`libswiftosAdditions.dylib` and `libswiftDispatchAdditions.dylib`
(`Scripts/build-overlay.sh`) and Perry's Combine (`Scripts/build-combine.sh`),
each with `PERRY_OVERLAY_PLATFORM=macosx` and
`PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0`.

Still missing for it on x86_64: the UniformTypeIdentifiers Swift overlay
(where it stops), SwiftUI and Charts, which most of its unresolved imports
name, and `+[NSAttributedString loadFromHTMLWithString:options:completionHandler:]`.
A run that stopped while Perry's keyed archiver lacked the app's `NSCoder`
category methods left an event log the app could not read back; its
container (`~/.perry/Containers/com.amazon.aiv.AIVApp`) had to be removed
before the next run.
