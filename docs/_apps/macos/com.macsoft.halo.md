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
    level: 4
    source: maintainer
    notes: Its loading picture, a TIFF in a PICT resource, shows while it starts, and none of Carbon's functions it calls are missing. The maintainer played it and found sound and play working. Multiplayer is untested, and its libcrypto.0.9.7 is not available.
    screenshots:
      - url: https://github.com/user-attachments/assets/1d43b507-bd94-4760-b118-c32ee6ed9c5b
        caption: The loading picture
  - pr: 370
    date: 2026-11-24
    perry: "d5b1aeac"
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
    level: 4
    source: maintainer
    notes: Its VSYNC frame rate setting holds its swaps to the display, about 54 frames a second in a level that ran at 93 without it, by MangoHud's overlay. The maintainer played it and found sound and play working. Multiplayer is untested.
    screenshots:
      - url: https://github.com/user-attachments/assets/4263b7b7-a43a-4efb-94a6-e45e363f36d8
        caption: A level, with MangoHud's overlay
  - pr: 392
    date: 2026-11-24
    perry: "d69b9c78"
    platform: macos
    cpu: i386
    app_version: "2.0"
    hardware: Retroid Pocket 5
    os: ROCKNIX 20261101
    packaging: Packaging/macos/com.macsoft.halo/portmaster
    resolution: "800x600"
    graphics: OpenGL
    env:
      - "PERRY_DISCS=Halo Universal=roms/ports/halo/disc"
      - "PERRY_CONTAINER=roms/ports/halo/conf"
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
      - "BOX86_MMAP_BASE=0x48000000"
    level: 3
    source: body
    notes: Under box86 it finds its disc, shows its graphics settings and reaches its main menu, in a window. The settings window's labels and button titles are not drawn there. Sound, the controller mapping and play are untested.
    screenshots:
      - url: https://github.com/user-attachments/assets/e1f19426-188e-45b5-8a54-06a6ea0868a0
        caption: The main menu on the Retroid Pocket 5
  - pr: 397
    date: 2026-11-24
    perry: "0d08f6f7"
    platform: macos
    cpu: i386
    app_version: "2.0"
    hardware: Retroid Pocket 5
    os: ROCKNIX 20261101
    packaging: Packaging/macos/com.macsoft.halo/portmaster
    resolution: "800x600"
    graphics: OpenGL
    env:
      - "PERRY_DISCS=Halo Universal=roms/ports/halo/disc"
      - "PERRY_CONTAINER=roms/ports/halo/conf"
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
      - "BOX86_MMAP_BASE=0x48000000"
    level: 3
    source: body
    notes: Under box86 its settings window shows its text. Run in gamescope (HALO_SCREEN=800x600) the main menu is full screen, its 800x600 scaled to the screen's height, but gamescope often aborts as the game starts, so the launcher leaves it out and the game plays in a window. Sound, the controller mapping and play are untested.
    screenshots:
      - url: https://github.com/user-attachments/assets/994d0749-ac77-4775-86e0-cfaf0c3b0882
        caption: The main menu full screen on the Retroid Pocket 5, in gamescope
      - url: https://github.com/user-attachments/assets/51b3074b-0404-4b8d-a451-9542bcb9b22b
        caption: The graphics settings window on the Retroid Pocket 5
  - pr: 406
    date: 2026-11-24
    perry: "f5df3494"
    platform: macos
    cpu: i386
    app_version: "2.0"
    hardware: Retroid Pocket 5
    os: ROCKNIX 20261101
    packaging: Packaging/macos/com.macsoft.halo/portmaster
    resolution: "1920x1080"
    graphics: OpenGL
    env:
      - "PERRY_DISCS=Halo Universal=roms/ports/halo/disc"
      - "PERRY_CONTAINER=roms/ports/halo/conf"
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
      - "BOX86_MMAP_BASE=0x48000000"
    level: 4
    source: maintainer
    fps: 120
    notes: Under box86 it plays full screen without gamescope. Its Video Setup now offers the screen's own 1920x1080, which it plays at, at about 115 to 127 frames a second in the first level by MangoHud; at its first 800x600 Perry scales the picture to the screen. Its VSync setting doesn't hold it to 60 here. The maintainer played it with the pad through gptokeyb (D-pad and Start in menus, the right stick as the mouse) and found sound and play working. Touch doesn't place its pointer.
    screenshots:
      - url: https://github.com/user-attachments/assets/eb77e3b0-2a43-4880-aa01-6990c0a94786
        caption: The first level at 1920x1080 on the Retroid Pocket 5, with MangoHud's overlay
      - url: https://github.com/user-attachments/assets/1a311782-dab1-473e-b62f-d9e95fed30a1
        caption: The first level on the Retroid Pocket 5
      - url: https://github.com/user-attachments/assets/23fc3df2-cf25-4c1e-bba7-b68c72ab8364
        caption: The main menu full screen on the Retroid Pocket 5
---

A Carbon application for PowerPC and Intel, run with the 32-bit Perry. It
checks for its disc through IOKit, so the disc's image is mounted and named
with `PERRY_DISCS`. The folder given as `PERRY_CONTAINER` must have no
period in its path: Halo refuses a Documents folder whose path has one.

On the Retroid Pocket 5 it runs under box86, started by a PortMaster script
with gptokeyb for the controls. Halo keeps its game state at 0x40000000,
where box86 would put its own pages, so box86 is built with
`Packaging/shared/box86/box86-mmap-base.patch` and the launcher sets
`BOX86_MMAP_BASE=0x48000000`. It plays full screen by switching the
display to a resolution of its own, which the device's screen hasn't got:
Perry shows the game's window full screen at the screen's size and scales
what it draws to fit.
