---
name: ioquake3 (old-Mac port)
bundle_id: "org.ioquake.ioquake3.oldmac"
platform: macos
kind: game
developer: Matthew Deaves
tags: [ObjC]
reports:
  - pr: 326
    date: 2026-11-23
    perry: "d9882f40"
    platform: macos
    cpu: x86_64
    app_version: "1.36-oldmac-v0.6.21"
    hardware: Dell OptiPlex 7020
    os: Debian 13
    resolution: "1024x768"
    graphics: OpenGL
    env:
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
    level: 3
    source: body
    notes: The x86_64 slice loads with its bundled SDL 1.2, reads Quake III Arena's data, starts its OpenGL renderer and sound and draws the main menu in a window. Input, sound output and starting a match were not tried; full screen, its default, opens no window.
    screenshots:
      - url: https://github.com/user-attachments/assets/c6f2bedb-ddde-4055-80c5-01c01a220944
        caption: Main menu
---

The release ships no game data: it needs Quake III Arena's `pak0.pk3` to
`pak8.pk3` in a `baseq3` folder beside the app. Run it with
`+set r_fullscreen 0`.
