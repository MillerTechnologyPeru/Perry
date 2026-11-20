---
name: YouTube
bundle_id: "com.google.ios.youtube"
platform: ios
kind: app
reports:
  - pr: 132
    date: 2026-11-10
    perry: "ace489bc"
    platform: ios
    cpu: arm64
    app_version: "21.44.4"
    hardware: Lenovo Duet 3
    os: Debian sid
    level: 1
    source: body
    notes: Runs about 10 seconds with no window, then crashes.
  - pr: 147
    date: 2026-11-13
    perry: "49726763"
    platform: ios
    cpu: arm64
    app_version: "21.44.4"
    hardware: Lenovo Duet 3
    os: Debian sid
    level: 3
    source: body
    notes: Runs for minutes signed in and shows its home screen; the feed is empty.
  - pr: 156
    date: 2026-11-15
    perry: "3ce725d9"
    platform: ios
    cpu: arm64
    app_version: "21.44.4"
    hardware: Lenovo Duet 3
    os: Debian sid
    level: 3
    source: body
    notes: "Shows its Home feed: cells, images and text."
    screenshots:
      - url: https://github.com/user-attachments/assets/ef6038fe-f78b-4dfe-a99f-d2069d13b794
        caption: Home feed
---
