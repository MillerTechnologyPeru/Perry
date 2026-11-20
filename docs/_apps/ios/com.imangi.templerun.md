---
name: Temple Run
bundle_id: "com.imangi.templerun"
platform: ios
kind: game
tags: [ObjC, C++, Unity]
reports:
  - pr: 64
    date: 2026-11-06
    perry: "7184cfe1"
    platform: ios
    cpu: arm64
    app_version: "1.43"
    hardware: Retroid Pocket Flip 2
    os: ROCKNIX
    resolution: "390x844@3"
    graphics: Metal
    fps: 30
    env:
      - "PERRY_UIKIT_SCREEN=390x844@3"
      - "PERRY_UIKIT_ORIENTATION=portrait"
    level: 2
    source: body
    notes: Reaches its first screen with Unity on Metal; not playable yet.
    screenshots:
      - url: https://github.com/user-attachments/assets/d5ee9f5f-7f47-4f54-8360-1b0a803165b3
        caption: First screen
  - pr: 66
    date: 2026-11-06
    perry: "fa5f0ced"
    platform: ios
    cpu: arm64
    app_version: "1.19.1"
    hardware: Retroid Pocket Flip 2
    os: ROCKNIX
    resolution: "390x844@3"
    graphics: OpenGL ES 2
    fps: 60
    env:
      - "PERRY_UIKIT_SCREEN=390x844@3"
      - "PERRY_UIKIT_ORIENTATION=portrait"
    level: 2
    source: body
    notes: Reaches its loading screen on OpenGL ES 2; not playable yet.
    screenshots:
      - url: https://github.com/user-attachments/assets/63e78cfe-0300-4b1e-b59a-7665115c7ec5
        caption: Loading screen
---
