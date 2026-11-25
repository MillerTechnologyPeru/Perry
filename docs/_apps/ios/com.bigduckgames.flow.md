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
  - pr: 256
    date: 2026-11-21
    perry: "81d3d3e0"
    platform: ios
    cpu: arm64
    app_version: "5.0"
    hardware: Lenovo Duet 3
    os: Debian sid
    resolution: "430x932@3"
    graphics: OpenGL ES 1
    env:
      - "PERRY_OS_VERSION=17.0"
    level: 2
    source: body
    notes: Its main menu draws, with its banner ad; it keeps running.
    screenshots:
      - url: https://github.com/user-attachments/assets/e78d4205-519a-40cb-a2e5-17554b3ca8ed
        caption: Main menu with its banner ad
  - date: 2026-11-25
    perry: "258bff15"
    platform: ios
    cpu: arm64
    app_version: "5.0"
    hardware: Parallels VM on an arm64 Mac
    os: Debian 13
    resolution: "430x932@3"
    graphics: OpenGL ES 1
    env:
      - "PERRY_OS_VERSION=17.0"
      - "LIBGL_ALWAYS_SOFTWARE=1"
    level: 3
    source: maintainer
    notes: Its main menu draws with both banner ads and it keeps running, on Mesa's software renderer; play is untested.
    screenshots:
      - url: https://github.com/user-attachments/assets/9f7a1e33-915a-4765-9de4-7b3ce5a40cf9
        caption: Main menu with both banner ads
---

A Cocos2D game drawing with OpenGL ES 1. Its frames were white while its draws
went to the compositor's GL context, where its framebuffer doesn't exist; with
the app's context kept current, the main menu draws. Its ad SDK MolocoSDK
force-unwraps an icon from its asset catalog stored in CoreUI's palette-img
compression, which Perry now decodes. `PERRY_OS_VERSION=17.0` keeps its ad code off
AdAttributionKit, which Perry doesn't have.

In the Parallels VM the GPU driver, virgl, draws every fixed-function textured
quad black, so all of the game's sprites came out black and only the banner ads
(drawn with shaders) showed. Mesa's software renderer (`LIBGL_ALWAYS_SOFTWARE=1`)
draws them.
