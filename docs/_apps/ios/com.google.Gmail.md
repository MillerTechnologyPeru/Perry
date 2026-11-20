---
name: Gmail
bundle_id: "com.google.Gmail"
platform: ios
kind: app
reports:
  - pr: 213
    date: 2026-11-19
    perry: "cdfc5f4a"
    platform: ios
    cpu: arm64
    app_version: "6.0.261109"
    hardware: Lenovo Duet 3
    level: 2
    source: body
    notes: Shows its welcome screen with its Sign In button; signing in needs a real account.
    screenshots:
      - url: https://github.com/user-attachments/assets/343e9a7a-654a-4472-9a45-97adcf81c357
        caption: Welcome screen
---

Needs `PERRY_OS_VERSION=18.0` and `Scripts/extract-assets.sh` run on the app.
