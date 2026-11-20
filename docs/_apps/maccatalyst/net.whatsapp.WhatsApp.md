---
name: WhatsApp
bundle_id: "net.whatsapp.WhatsApp"
platform: maccatalyst
kind: app
tags: [Swift, ObjC, C++]
reports:
  - date: 2026-11-20
    perry: "552daf78"
    platform: maccatalyst
    cpu: x86_64
    app_version: "26.46.17"
    hardware: Dell OptiPlex 7020
    os: Debian 13
    env:
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
      - "PERRY_CRASH_REPORT=1"
    level: 1
    source: maintainer
    notes: Loads its frameworks, then crashes at start-up before a window; Perry has no macOS Swift runtime, SwiftUI or Combine for x86_64 yet.
---

The Mac build is the one `whatsapp.com/download/mac` leads to (a universal Mac Catalyst app that uses SwiftUI). On the Lenovo Duet 3 its arm64 slice runs for about 28 seconds and then stops on an ARMv8.4 instruction (`ldapur`) that the Duet's CPU does not have, so the Mac slice needs a newer arm64 CPU or a build for older ones.
