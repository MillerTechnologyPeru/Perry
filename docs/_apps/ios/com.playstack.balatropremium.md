---
name: Balatro
bundle_id: "com.playstack.balatropremium"
platform: ios
kind: game
tags: [ObjC, Lua]
reports:
  - pr: 232
    date: 2026-11-20
    perry: "bfefd8a4"
    platform: ios
    cpu: arm64
    app_version: "1.0.25"
    hardware: Lenovo Duet 3
    os: Debian sid
    resolution: "932x430@3"
    fps: "21-52"
    env:
      - "PERRY_METAL=0"
    level: 3
    source: body
    notes: Gets past its cloud save load to the first blind and its tutorial, but is slow at full resolution, limited by the GPU's fill rate.
    screenshots:
      - url: https://github.com/user-attachments/assets/4060a319-5797-46e6-a776-b59ce4465f7e
        caption: First blind with the tutorial
      - url: https://github.com/user-attachments/assets/b52bbd7a-b794-4886-9523-bf063dd93b94
        caption: Intro
---

A LÖVE game, run on OpenGL ES with `PERRY_METAL=0`. Its frame rate follows
the pixels drawn: 20.9 frames a second on average at 932x430@3, 37.3 at
@2 and 51.5 at @1. CloudKit answers as if no iCloud account is signed in,
so saves stay local.
