---
name: Microsoft Teams
bundle_id: "com.microsoft.skype.teams"
platform: ios
kind: app
reports:
  - pr: 211
    date: 2026-11-19
    perry: "1fa36511"
    platform: ios
    cpu: arm64
    app_version: "8.20.1"
    hardware: Lenovo Duet 3
    level: 2
    source: body
    notes: Shows its sign-in screen; signing in needs a real account.
---

Needs `PERRY_OS_VERSION=18.0` and `Scripts/extract-assets.sh` run on the app.
