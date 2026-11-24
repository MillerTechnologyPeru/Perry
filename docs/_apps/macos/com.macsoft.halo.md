---
name: "Halo: Combat Evolved"
bundle_id: "com.macsoft.halo"
platform: macos
kind: game
developer: MacSoft
tags: [C++, Carbon]
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
---

A Carbon application for PowerPC and Intel, run with the 32-bit Perry. It
checks for its disc through IOKit, so the disc's image is mounted and named
with `PERRY_DISCS`. The folder given as `PERRY_CONTAINER` must have no
period in its path: Halo refuses a Documents folder whose path has one.
