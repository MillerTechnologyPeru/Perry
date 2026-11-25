---
name: Age of Empires III
bundle_id: "com.macsoft.age3"
platform: macos
kind: game
developer: MacSoft
tags: [C++]
reports:
  - pr: 309
    date: 2026-11-23
    perry: "d84c867e"
    platform: macos
    cpu: i386
    app_version: "1.0.5"
    hardware: Dell OptiPlex 7020
    os: Debian 13
    graphics: OpenGL
    env:
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
      - "SDL_VIDEODRIVER=x11"
      - "PERRY_CONTAINER=~/Apps/aoe3/home"
    level: 2
    source: body
    notes: Shows its license agreement, then loads its data, sets up its AGL renderer and display modes and opens its 1024x768 game window, which stays black.
    screenshots:
      - url: https://github.com/user-attachments/assets/11fb70fd-a99d-45f3-8d29-5457a80ec98b
        caption: The license agreement, before the game's window
  - pr: 421
    date: 2026-11-25
    perry: "93fb066d"
    platform: macos
    cpu: i386
    app_version: "1.0.5"
    hardware: Dell OptiPlex 7020
    os: Debian 13
    resolution: "1024x768"
    graphics: OpenGL
    env:
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
      - "SDL_VIDEODRIVER=x11"
      - "PERRY_CONTAINER=~/perry-aoe3/home"
    level: 3
    source: body
    notes: The intro movies play, then the game loads its data, plays its music and draws its loading screen and main menu; the menu buttons have no labels. Play is untested.
    screenshots:
      - url: https://github.com/user-attachments/assets/bb64a21e-0aa6-4183-8e73-5dd65c1530c6
        caption: The main menu, its buttons without labels
      - url: https://github.com/user-attachments/assets/2d0e655c-9a70-4020-aaca-5b2ac9aad3fb
        caption: The loading screen
---

MacSoft's Carbon port, run as its i386 slice under `perry32`. Getting to its
game window took CFString characters past a string's end (#293),
`CreateNewPort` (#294), the application event loop's quit taken when it ends
(#307), libxml2's provider for i386 (#308), AGL contexts laid out with
OpenGL's dispatch table for `aglMacro.h`, a `GL_EXTENSIONS` short enough for
its 4 KB buffer and `GL_APPLE_vertex_array_object` (#309), and the Display
Manager's mode lists with a display ID like a Mac's (#310).

It rejects a Documents path with a period in it, so the default container
(`~/.perry/Containers/com.macsoft.age3`) won't do: `PERRY_CONTAINER` names
one without. It saves its settings, its license agreement among them, only
when it quits, so the agreement shows at each launch until it has quit once.
The copy tested lacks `EULA.rsrc`'s and its fonts' resource forks, so the
agreement's text is blank.

Past its game window it needed SANE's `num2dec`, `CGDisplayIsCaptured`,
QuickTime movie frames, any-case file names for libxml2, Carbon's fork calls,
fonts activated from memory with ATSUI text drawn through FreeType (#418),
and mutable strings that re-read the characters the game writes into their
external buffer (#421). Screen captures of its full-screen window come out
black; `PERRY_OPENGL_SNAPSHOT=<file>` saves its frames instead.
