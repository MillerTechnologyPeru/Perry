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
  - pr: 234
    date: 2026-11-20
    perry: "0fa6c14d"
    platform: macos
    cpu: x86_64
    app_version: "2.1"
    hardware: Dell OptiPlex 7020
    os: Debian 13
    resolution: "553x415"
    env:
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
    level: 4
    source: maintainer
    notes: With the new CoreWLAN provider the interface table lists the Wi-Fi device and its MAC address, and a scan returns the networks around it. The app lists only WEP networks, the ones it cracks; with none nearby its results stay empty, but the scan and every CWNetwork accessor work.
    screenshots:
      - url: https://github.com/user-attachments/assets/32da5458-3695-4dc1-ad8c-906374cc0485
        caption: The interface table with the Wi-Fi device and its MAC
      - url: https://github.com/user-attachments/assets/0d639c7c-873d-4750-869e-45503f1ad629
        caption: Scanned networks, with the app's WEP-only filter lifted
---

An x86_64 Cocoa app. CoreWLAN now runs over NetworkManager's D-Bus API, so the
interface table lists the Wi-Fi device and its MAC, and the scan finds the
networks around it. The app itself shows only WEP networks (the ones it
cracks with the bundled aircrack-ng), so where none are nearby its own results
list is empty. Needs `PERRY_UNIMPLEMENTED=continue` and
`PERRY_OBJC_UNRECOGNIZED=continue`.
