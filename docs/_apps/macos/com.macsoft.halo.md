---
name: "Halo: Combat Evolved"
bundle_id: "com.macsoft.halo"
platform: macos
kind: game
developer: MacSoft
tags: [C++]
reports:
  - pr: 348
    date: 2026-11-23
    perry: "0e63869b"
    platform: macos
    cpu: i386
    app_version: "2.0"
    hardware: Dell OptiPlex 7020
    os: Debian 13
    resolution: "800x600"
    graphics: OpenGL
    env:
      - "PERRY_DISCS=Halo Universal=~/perry-halo/cd/mnt"
      - "PERRY_CONTAINER=~/perry-halo/container-ub"
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
    level: 3
    source: body
    notes: The Universal Binary release finds its disc, takes its product key, shows its graphics settings and reaches its main menu; the campaign's opening scene draws in 3D with its character models black. Sound and play are untested.
    screenshots:
      - url: https://github.com/user-attachments/assets/686517cc-a721-456d-bdbc-7add241017b0
        caption: The main menu
      - url: https://github.com/user-attachments/assets/6b34b2b4-2f04-46e1-8bb3-2274bdd2087b
        caption: The graphics settings window
  - pr: 349
    date: 2026-11-23
    perry: "38c2001a"
    platform: macos
    cpu: i386
    app_version: "2.0"
    hardware: Dell OptiPlex 7020
    os: Debian 13
    resolution: "800x600"
    graphics: OpenGL
    env:
      - "PERRY_DISCS=Halo Universal=~/perry-halo/cd/mnt"
      - "PERRY_CONTAINER=~/perry-halo/container-ub"
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
    level: 3
    source: body
    notes: With auxiliary color buffers the campaign's first level draws lit, with its characters in color, and the main menu shows its ring background. Sound and play are untested.
    screenshots:
      - url: https://github.com/user-attachments/assets/23a0f940-748b-4516-b318-097510a6cf7a
        caption: The first level
  - pr: 358
    date: 2026-11-23
    perry: "c18f0574"
    platform: macos
    cpu: i386
    app_version: "2.0"
    hardware: Dell OptiPlex 7020
    os: Debian 13
    resolution: "800x600"
    graphics: OpenGL
    env:
      - "PERRY_DISCS=Halo Universal=~/perry-halo/cd/mnt"
      - "PERRY_CONTAINER=~/perry-halo/container-ub"
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
    level: 3
    source: body
    notes: The main menu's music plays through the Sound Manager's channels, without gaps in a recording of the output. Sound in a level and play are untested.
  - pr: 361
    date: 2026-11-24
    perry: "c604b8e2"
    platform: macos
    cpu: i386
    app_version: "2.0"
    hardware: Dell OptiPlex 7020
    os: Debian 13
    resolution: "800x600"
    graphics: OpenGL
    env:
      - "PERRY_DISCS=Halo Universal=~/perry-halo/cd/mnt"
      - "PERRY_CONTAINER=~/perry-halo/container-ub"
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
    level: 3
    source: body
    notes: Its loading picture, a TIFF in a PICT resource, shows while it starts, and none of Carbon's functions it calls are missing. Sound in a level and play are untested.
    screenshots:
      - url: https://github.com/user-attachments/assets/1d43b507-bd94-4760-b118-c32ee6ed9c5b
        caption: The loading picture
---

A Carbon application for PowerPC and Intel, run with the 32-bit Perry. It
checks for its disc through IOKit, so the disc's image is mounted and named
with `PERRY_DISCS`. The folder given as `PERRY_CONTAINER` must have no
period in its path: Halo refuses a Documents folder whose path has one.
