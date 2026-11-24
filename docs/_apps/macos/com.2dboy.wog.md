---
name: World of Goo
bundle_id: "com.2dboy.wog"
platform: macos
kind: game
developer: 2D BOY
tags: [C++]
reports:
  - date: 2026-11-23
    perry: "b98a3875"
    platform: macos
    cpu: ppc
    app_version: "1.30"
    hardware: QEMU user mode (PowerPC 7400) on Dell OptiPlex 7020
    os: Swift Linux
    env:
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
    level: 1
    source: maintainer
    notes: The original PowerPC build gets through its libraries' initializers and its startup code into main, then crashes in CFStringGetCharacters, which took its CFRange as Linux passes one. There is no ppc provider yet for OpenGL, AGL, IOKit, CoreAudio or libcurl.
---

The 2008 retail Mac build: a Carbon program drawing through AGL and OpenGL,
with irrKlang (`libirrklang.dylib`) for sound, built for PowerPC only. Steam's
later Intel build is [its own listing](com.2dboy.worldofgoo.steam.html).

Getting it to `main` took four fixes for Mac programs of its age and for
Darwin's PowerPC calling convention, which differs from Linux's (#356):

- the loader runs initializers and `main` from a frame laid out as a Darwin
  caller's, since irrKlang's C++ constructors saved their return addresses
  over the loader's own frame;
- libSystem exports `__keymgr_global`, which GCC 4.0's startup code reads;
- `__dyld_func_lookup` gives crt1 libSystem's `_dyld_image_count` and
  `_dyld_get_image_name`, which it walks looking for libobjc;
- CoreFoundation's functions that take a `CFRange` take it as Darwin passes
  it, in two words.

The last of these is not yet tested with the game.
