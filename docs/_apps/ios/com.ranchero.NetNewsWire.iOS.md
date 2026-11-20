---
name: NetNewsWire for iOS
bundle_id: "com.ranchero.NetNewsWire.iOS"
platform: ios
kind: app
reports:
  - pr: 103
    date: 2026-11-08
    perry: "3777379e"
    platform: ios
    cpu: arm64
    hardware: Lenovo Duet 3
    os: Debian sid
    level: 3
    source: body
    notes: Its Feeds list runs, idles without redrawing and scrolls cheaply.
  - pr: 121
    date: 2026-11-09
    perry: "0a708780"
    platform: ios
    cpu: arm64
    hardware: Lenovo Duet 3
    os: Debian sid
    level: 3
    source: body
    notes: Its feed list draws separators and rounded cards as iOS does.
---
