---
name: Crunchyroll
bundle_id: "com.crunchyroll.iphone"
platform: ios
kind: app
tags: [Swift, ObjC]
reports:
  - pr: 247
    date: 2026-11-20
    perry: "efbdec20"
    platform: ios
    cpu: arm64
    app_version: "4.124.0"
    hardware: Lenovo Duet 3
    os: Debian sid
    env:
      - "PERRY_OS_VERSION=18.0"
    level: 2
    source: body
    notes: Starts to its welcome screen and opens its web sign-in sheet, whose redirect reaches the app. One real sign-in completed and then crashed; the fix for that crash has not been tested with another sign-in.
---
