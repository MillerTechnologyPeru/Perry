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
  - date: 2026-11-20
    perry: "e105e433"
    platform: maccatalyst
    cpu: x86_64
    app_version: "26.46.17"
    hardware: Dell OptiPlex 7020
    resolution: "1024x699@1"
    os: Debian 13
    env:
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
      - "PERRY_CRASH_REPORT=1"
      - "PERRY_OS_VERSION=15.2"
    level: 2
    source: maintainer
    notes: Reaches its welcome screen (title, text and Continue button) in about 40 seconds; the Lottie artwork above the title and the Terms link below are missing.
    screenshots:
      - url: https://github.com/user-attachments/assets/dec53a4c-1131-4940-bf22-c40657bf3946
        caption: Welcome screen
  - pr: 250
    date: 2026-11-21
    perry: "927028f5"
    platform: maccatalyst
    cpu: x86_64
    app_version: "26.46.17"
    hardware: Dell OptiPlex 7020
    resolution: "1024x699@1"
    os: Debian 13
    env:
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
      - "PERRY_CRASH_REPORT=1"
      - "PERRY_OS_VERSION=15.2"
    level: 2
    source: screenshot
    notes: The welcome screen shows its animated artwork; two of its speech bubbles come out partly square, and the Terms link is still missing.
    screenshots:
      - url: https://github.com/user-attachments/assets/35a826a6-6558-41c3-a6c7-a5130a6063f8
        caption: Welcome screen with its artwork
---

The Mac build is the one `whatsapp.com/download/mac` leads to (a universal Mac Catalyst app that uses SwiftUI). The Duet 3's libraries came from several builds around that commit, so its report's commit is the closest known. The Mac arm64 slice needs a CPU with ARMv8.4 (untried on the Retroid handhelds).

The x86_64 slice runs with a Swift runtime directory (`PERRY_SWIFT_RUNTIME`) that holds swift.org's macOS runtime for x86_64 and x86_64 Mach-O builds of Perry's Darwin Swift libraries (Foundation, Combine, the UIKit, Core Data and Network overlays and the stub frameworks), made on a Mac. `Scripts/extract-assets.sh` has to be run on the app first for its images and animations. `PERRY_OS_VERSION=15.2` keeps it off its macOS 26 code, which calls Speech's `SpeechTranscriber` (26.1) and where its Continue button came out colourless (it is built on a visual effect view there). Continue was not pressed: it accepts WhatsApp's terms.
