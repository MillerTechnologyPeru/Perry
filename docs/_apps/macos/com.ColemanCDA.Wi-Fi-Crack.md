---
name: Wi-Fi Crack
bundle_id: "com.ColemanCDA.Wi-Fi-Crack"
platform: macos
kind: app
developer: Alsey Coleman Miller
tags: [ObjC]
reports:
  - pr: 231
    date: 2026-11-20
    perry: "0d59f1ed"
    platform: macos
    cpu: x86_64
    app_version: "2.1"
    hardware: Dell OptiPlex 7020
    os: Debian 13
    resolution: "553x415"
    env:
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
    level: 3
    source: body
    notes: Launches and shows its full Cocoa UI, the interface-selection table and its buttons. The table stays empty, as Perry has no CoreWLAN to find Wi-Fi interfaces with.
    screenshots:
      - url: https://github.com/user-attachments/assets/4f3bb9d4-c522-4f38-b5ea-92690c92e082
        caption: The interface-selection window
---

An x86_64 Cocoa app. Perry has no CoreWLAN, so `CWInterface` and `CWNetwork`
are unavailable and the interface table stays empty; the rest of the UI
loads. Needs `PERRY_UNIMPLEMENTED=continue` and
`PERRY_OBJC_UNRECOGNIZED=continue`.
