---
name: "Age of Empires II: Definitive Edition"
bundle_id: "com.feralinteractive.ageofempires2"
platform: macos
kind: game
reports:
  - pr: 37
    date: 2026-11-06
    perry: "d48da509"
    platform: macos
    cpu: arm64
    hardware: Parallels VM on an arm64 Mac
    level: 1
    source: body
    notes: Gets through Feral's start-up and initializes Steam, then its game run returns before making a window.
  - pr: 42
    date: 2026-11-06
    perry: "603ea877"
    platform: macos
    cpu: arm64
    hardware: Parallels VM on an arm64 Mac
    level: 2
    source: body
    notes: Shows Feral's pre-game launcher, with its JavaScript talking to the game.
    screenshots:
      - url: https://github.com/user-attachments/assets/3fe4dab5-5e4a-43e8-88ff-b710f7e40c28
        caption: Feral launcher with the usage statistics dialog
  - pr: 44
    date: 2026-11-06
    perry: "838ee6a8"
    platform: macos
    cpu: arm64
    hardware: Parallels VM on an arm64 Mac
    level: 1
    source: body
    notes: Gets past the launcher's PLAY button, then stops at Metal function constants.
  - pr: 50
    date: 2026-11-06
    perry: "2a102c85"
    platform: macos
    cpu: arm64
    hardware: Parallels VM on an arm64 Mac
    level: 2
    source: body
    notes: Reaches its own window, where it shows its emblem.
  - pr: 56
    date: 2026-11-06
    perry: "da34c623"
    platform: macos
    cpu: arm64
    hardware: Lenovo Duet 3
    level: 1
    source: body
    notes: Loads its data and renders about 9 frames a second, but the window stays black; needs swap on an 8 GB device.
---

Feral's macOS arm64 build from Steam.
