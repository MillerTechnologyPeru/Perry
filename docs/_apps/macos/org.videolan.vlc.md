---
name: VLC
bundle_id: "org.videolan.vlc"
platform: macos
kind: app
developer: VideoLAN
tags: [C, ObjC]
reports:
  - pr: 299
    date: 2026-11-23
    perry: "798db2ea"
    platform: macos
    cpu: x86_64
    app_version: "3.0.17.3"
    hardware: Dell OptiPlex 7020
    os: Debian 13
    env:
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
      - "SDL_VIDEODRIVER=x11"
    level: 3
    source: body
    notes: Shows its main window with the toolbar, search, sidebar, drop zone, playback controls and full menu bar. The playlist title wraps and the time label overlaps the rewind button; playing media was not tried.
    screenshots:
      - url: https://github.com/user-attachments/assets/c439463d-4fdd-4b59-a4a2-3d97c950c3ad
        caption: The main window without the Fullscreen Controls panel, before the sidebar's color was fixed
      - url: https://github.com/user-attachments/assets/c5b64586-50d8-4451-97d0-1b6309745a98
        caption: The sidebar in the source list's light gray, Playlist selected
---

The media player's x86_64 build under `perry`. It took windows at alpha 0
kept hidden, for the Fullscreen Controls panel it fades in, and `NSAlert`'s
legacy constructor (#298), and the source list background system color for
its sidebar (#299). It links libc++, so `perry` needs `libperry-c++` and
`libperry-c++abi`, which outside the `perry-dev` image are on its
`LD_LIBRARY_PATH` from a folder they were copied to.
