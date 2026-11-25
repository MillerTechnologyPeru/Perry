---
name: Pay Up Sucker
bundle_id: "com.app.otlwtv"
platform: ios
kind: app
tags: [Swift, SwiftUI]
reports:
  - pr: 442
    date: 2026-11-25
    perry: "11e08fc7"
    platform: ios
    cpu: arm64
    app_version: "2.0.2"
    hardware: Lenovo Duet 3
    os: Debian sid
    env:
      - "PERRY_OS_VERSION=18.0"
    level: 3
    source: body
    notes: "Opens to its sign-in screen, drawn as on iOS, and stays up. Signing in, the tabs and video weren't tried. Needs its asset catalogs decoded with Scripts/extract-assets.sh."
    screenshots:
      - url: https://github.com/user-attachments/assets/db845f70-3998-4f34-a65d-744e3e88cca6
        caption: Sign-in screen
---
