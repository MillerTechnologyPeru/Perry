---
name: NetNewsWire for iOS
bundle_id: "com.ranchero.NetNewsWire.iOS"
platform: ios
kind: app
tags: [Swift, ObjC, C++]
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
  - pr: 371
    date: 2026-11-24
    perry: "27336eab"
    platform: ios
    cpu: arm64
    app_version: "7.2"
    hardware: Lenovo Duet 3
    os: Debian sid
    level: 3
    source: body
    notes: "The App Store build shows its Feeds list: the smart feeds and a subscription list's feeds with their icons and unread counts. Opening a feed and selection weren't tried; the bottom toolbar isn't drawn."
    screenshots:
      - url: https://github.com/user-attachments/assets/3c05f1f5-606f-4778-9c49-3220a00c0703
        caption: Feeds list
---
