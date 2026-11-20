---
name: Hyper Light Drifter
bundle_id: "com.abylight.hyperlightdrifter"
platform: ios
kind: game
tags: [ObjC]
reports:
  - pr: 226
    date: 2026-11-19
    perry: "24ee2b05"
    platform: ios
    cpu: arm64
    app_version: "1.1.7"
    hardware: Lenovo Duet 3
    os: Debian sid
    resolution: "932x430@3"
    graphics: OpenGL ES 2
    fps: "51-58"
    env:
      - "PERRY_GAMECONTROLLER_KEYBOARD=1"
    level: 3
    source: body
    notes: Reaches its title screen and gameplay, but frames are skipped as the game's presents and Perry's window drift apart, and only Return reaches the keyboard's gamepad.
    screenshots:
      - url: https://github.com/user-attachments/assets/b15172d5-a238-4356-a4f5-ec53b6af7e1b
        caption: Gameplay in the opening room
      - url: https://github.com/user-attachments/assets/9000245d-d8f9-48c4-b996-4ead0538c011
        caption: Title screen
---

A GameMaker game. It presents a steady 60 frames a second, but MangoHud
measures Perry's window at 51 to 58 on average, with 1% lows of 24 to 33:
frames are skipped or shown twice. Its touch controls work;
`PERRY_GAMECONTROLLER_KEYBOARD` makes the keyboard a controller, which the
game sees, but letters and Space don't reach SDL's keyboard state yet.
