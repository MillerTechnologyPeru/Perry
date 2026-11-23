---
name: World of Goo
bundle_id: "com.2dboy.worldofgoo.steam"
platform: macos
kind: game
developer: 2D BOY
tags: [C++, ObjC]
reports:
  - pr: 314
    date: 2026-11-23
    perry: "676e8304"
    platform: macos
    cpu: x86_64
    app_version: "1.0"
    hardware: Dell OptiPlex 7020
    os: Debian 13
    resolution: "1024x768"
    graphics: OpenGL
    env:
      - "SteamAppId=22000"
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
    level: 5
    source: maintainer
    notes: Steam's Mac build (25111706) plays, drawing its levels through SDL and OpenGL once CoreVideo's display links exist. The maintainer played it and found mouse, keyboard and sound working.
    screenshots:
      - url: https://github.com/user-attachments/assets/e0a024fa-32b9-45ff-a83f-162b3a960cbb
        caption: In a level
---

The Steam build's `Info.plist` has no `CFBundleIdentifier`; the identifier
here is one made for this listing. It needs the Linux Steam client running
and signed in, which Perry's Steam provider connects to, and `SteamAppId=22000`
when it is not started from Steam.
