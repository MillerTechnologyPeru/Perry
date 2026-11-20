---
name: Bejeweled 3
bundle_id: "com.popcap.Bejeweled3"
platform: macos
kind: game
tags: [C++, SexyAppFramework]
reports:
  - pr: 128
    date: 2026-11-09
    perry: "9137b869"
    platform: macos
    cpu: i386
    hardware: Dell OptiPlex 7020
    os: Debian 13
    env:
      - "PERRY_UNIMPLEMENTED=continue"
    graphics: OpenGL
    level: 3
    source: body
    notes: Loads, draws in OpenGL, plays sound and reaches a Classic game board.
  - pr: 129
    date: 2026-11-09
    perry: "86dfce96"
    platform: macos
    cpu: i386
    hardware: Lenovo Duet 3
    os: Debian sid
    graphics: OpenGL
    level: 2
    source: screenshot
    notes: Runs under box86 on the Duet 3 to its main menu.
    screenshots:
      - url: https://github.com/user-attachments/assets/bdb2ef98-d0fb-471d-a5da-eda6e7d4b3df
        caption: Main menu
  - pr: 221
    date: 2026-11-19
    perry: "8ab75200"
    platform: macos
    cpu: i386
    hardware: Dell OptiPlex 7020
    os: Debian 13
    resolution: "1024x768"
    env:
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
      - "SteamAppId=78000"
    graphics: OpenGL
    fps: 60
    level: 5
    source: maintainer
    notes: Everything tested works, with Steam running.
  - pr: 221
    date: 2026-11-19
    perry: "8ab75200"
    platform: macos
    cpu: i386
    hardware: Lenovo Duet 3
    os: Debian sid
    resolution: "1024x768"
    env:
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
    graphics: OpenGL
    fps: 60
    level: 5
    source: maintainer
    notes: Everything tested works under box86, in a window; full screen does not work.
  - pr: 221
    date: 2026-11-19
    perry: "8ab75200"
    platform: macos
    cpu: i386
    hardware: Retroid Pocket 5
    os: ROCKNIX 20261101
    resolution: "1920x1080"
    env:
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
    graphics: OpenGL
    fps: 60
    level: 5
    source: maintainer
    notes: Everything tested works under box86, with sound and a controller.
---

Needs `PERRY_UNIMPLEMENTED=continue` and `PERRY_OBJC_UNRECOGNIZED=continue`.
With Steam running, set `SteamAppId=78000`.

On the Duet 3 and Retroid Pocket 5 it runs under box86 (built from
`bb716a2`; ROCKNIX's 0.3.9 crashes at start-up) with the i386 Debian
libraries Perry is built against, and a small preloaded library that gives
box86 glibc 2.38's `__isoc23_*` functions it lacks, and `capget` and
`capset` where no armhf libcap is installed. On the Retroid Pocket 5, a
PortMaster script starts it with gptokeyb mapping the left stick to the
mouse, and GLib and GStreamer are taken from the i386 libraries for sound.
