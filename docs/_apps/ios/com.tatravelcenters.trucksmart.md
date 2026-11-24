---
name: TruckSmart
bundle_id: "com.tatravelcenters.trucksmart"
platform: ios
kind: app
tags: [Swift]
reports:
  - pr: 21
    date: 2026-11-05
    perry: "b1c8bf49"
    platform: ios
    cpu: arm64
    app_version: "6.3"
    hardware: Lenovo Duet 3
    os: Debian sid
    level: 2
    source: body
    notes: Launches, loads its sites from its API and shows its first-launch screen.
    screenshots:
      - url: https://github.com/user-attachments/assets/11ec1031-9553-4535-837f-b48c3b773d75
        caption: First-launch screen
  - pr: 70
    date: 2026-11-06
    perry: "dcf412dc"
    platform: ios
    cpu: arm64
    app_version: "6.3"
    hardware: Lenovo Duet 3
    os: Debian sid
    level: 3
    source: body
    notes: Gets past its splash and first-launch screen to the guest Home tab with live locations.
    screenshots:
      - url: https://github.com/user-attachments/assets/1e9edd39-9346-4edf-9ea1-167e48b2e454
        caption: Services tab
  - pr: 76
    date: 2026-11-07
    perry: "28bd9336"
    platform: ios
    cpu: arm64
    hardware: Lenovo Duet 3
    os: Debian sid
    level: 3
    source: body
    notes: The Locations tab shows its map, drawn by MapLibre, with the app's site pins.
  - pr: 82
    date: 2026-11-07
    perry: "e0f6394e"
    platform: ios
    cpu: arm64
    hardware: Lenovo Duet 3
    os: Debian sid
    level: 3
    source: body
    notes: "Map annotations draw as on the iPhone: rounded site bubbles with centered titles."
  - pr: 99
    date: 2026-11-07
    perry: "417a4f36"
    platform: ios
    cpu: arm64
    hardware: Lenovo Duet 3
    os: Debian sid
    level: 3
    source: body
    notes: "Location search looks as on an iPhone: the map behind the search bar and the results list."
  - pr: 114
    date: 2026-11-09
    perry: "88907e4a"
    platform: ios
    cpu: arm64
    hardware: Lenovo Duet 3
    os: Debian sid
    level: 3
    source: body
    notes: Starts again without aborting and no longer redraws while idle; list drags are still slow.
  - pr: 295
    date: 2026-11-22
    perry: "27336eab"
    platform: ios
    cpu: arm64
    app_version: "6.3"
    hardware: Lenovo Duet 3
    os: Debian sid
    env:
      - "PERRY_OS_VERSION=26.0"
    level: 3
    source: body
    notes: "Run as an iOS 26 app on master's compositor with the pull request's SwiftUI: the Locations sheet is frosted over the map and the tab bar floats as a glass capsule. The sheet's rounded corners still come out square, and a scripted tap on the site card did not open its detail screen in this run."
  - pr: 355
    date: 2026-11-23
    perry: "92eec0df"
    platform: ios
    cpu: arm64
    app_version: "6.3"
    hardware: Lenovo Duet 3
    os: Debian sid
    env:
      - "PERRY_OS_VERSION=26.0"
    level: 3
    source: body
    notes: "Dragging the Locations map by hand, each pin's distance and title now stay with its marker; before, the text kept its place until the finger lifted. A drag still manages only about nine updates a second."
    screenshots:
      - url: https://github.com/user-attachments/assets/37aa78af-4038-4545-b616-039e1a56322b
        caption: Locations, with each pin's text at its marker
---
