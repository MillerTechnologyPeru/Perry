---
name: Bean
bundle_id: "com.SevenYearsDreaming.Bean"
platform: macos
kind: app
developer: James Hoover
tags: [ObjC]
reports:
  - pr: 257
    date: 2026-11-21
    perry: "6f05abc3"
    platform: macos
    cpu: i386
    app_version: "2.4.5"
    hardware: Dell OptiPlex 7020
    os: Debian 13
    resolution: "791x699"
    env:
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
    level: 3
    source: body
    notes: Launches and shows its full Cocoa UI, the document window with its menu bar, toolbar and editing area, which fills the window once the scroll view grows its text view to the clip view's width. The page draws dark rather than as a white sheet.
    screenshots:
      - url: https://github.com/user-attachments/assets/421cafa6-848f-4ad2-8ee3-216359953ca0
        caption: The untitled document window, its editing area filling the width
  - date: 2026-11-23
    perry: "6eb937e2"
    platform: macos
    cpu: ppc
    app_version: "2.4.5"
    hardware: QEMU mac99 (PowerPC G4)
    os: Swift Linux
    env:
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
      - "SDL_VIDEO_DRIVER=wayland"
      - "SDL_RENDER_DRIVER=software"
    level: 3
    source: maintainer
    notes: Its PowerPC slice launches on 32-bit PowerPC Linux and shows the document window with its menu bar, toolbar, white page and status bar. The status bar's word count reads "(null)" and another of its fields shows a stray number.
---

A small i386 Cocoa word processor, nib-based on AppKit with some Carbon.
It launches under `perry32` and brings up its document window with the full
menu bar and toolbar. Its text view loaded narrower than the window until
the scroll view was taught to grow a filling document view to its clip
view's width; the editing area now fills the window. The page still draws
dark rather than as a white sheet. Needs `PERRY_UNIMPLEMENTED=continue` and
`PERRY_OBJC_UNRECOGNIZED=continue`, and the i386 build itself needs the
`NSView.encode(with:)` overflow fix to compile.

Its PowerPC slice runs under `perry` built for 32-bit PowerPC Linux, in a
sway session on an emulated G4 (QEMU's mac99), with the loader translating between Darwin's ppc
calling convention and Linux's (see
[Documentation/powerpc.md](https://github.com/MillerTechnologyPeru/Perry/blob/master/Documentation/powerpc.md)).
The window comes up with the right colors only with a Mesa that labels its
software-rendered Wayland buffers by their byte order; stock Mesa on
big-endian hands them to the compositor with red, green, blue and alpha
mixed up, so grey draws lavender and black blue. The status bar shows
"Words: (null)" and a stray number beside the line count.
