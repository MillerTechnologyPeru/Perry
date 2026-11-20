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
  - date: 2026-11-20
    perry: "e3820e47"
    platform: maccatalyst
    cpu: arm64
    app_version: "26.46.17"
    hardware: Lenovo Duet 3
    os: Debian sid
    env:
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
      - "PERRY_KEEP_CRASH_HANDLERS=segv,bus,abrt,trap,fpe"
      - "PERRY_OS_VERSION=18.0"
    level: 1
    source: maintainer
    notes: Loads and runs for about 28 seconds, then stops on an ARMv8.4 instruction (ldapur) in its arm64 slice that the Duet's CPU does not have; no window.
---

The Mac build is the one `whatsapp.com/download/mac` leads to (a universal Mac Catalyst app that uses SwiftUI). The Duet 3's libraries came from several builds around that commit, so its report's commit is the closest known. The Mac arm64 slice needs a CPU with ARMv8.4 (untried on the Retroid handhelds).
