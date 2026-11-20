---
name: Flow Free
bundle_id: "com.bigduckgames.flow"
platform: ios
kind: game
tags: [ObjC, Swift, Cocos2D]
reports:
  - pr: 238
    date: 2026-11-20
    perry: "22fc21f5"
    platform: ios
    cpu: arm64
    app_version: "5.0"
    hardware: Lenovo Duet 3
    os: Debian sid
    resolution: "430x932@3"
    graphics: OpenGL ES 1
    env:
      - "PERRY_OS_VERSION=17.0"
    level: 1
    source: body
    notes: Runs past its start-up and ad SDKs and presents frames, but every frame is white.
    screenshots:
      - url: https://github.com/user-attachments/assets/2031216c-93da-49a0-9653-8af487cfe458
        caption: White frames from its OpenGL ES 1 view
---

A Cocos2D game drawing with OpenGL ES 1. Its frames are white so far; two
GL_INVALID_FRAMEBUFFER_OPERATION errors point at drawing into an incomplete
framebuffer. `PERRY_OS_VERSION=17.0` keeps its ad code off AdAttributionKit,
which Perry doesn't have.
