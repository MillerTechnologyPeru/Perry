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
agreement's text is blank. The game window is black: it idles in its event
loop after `num2dec` and `CGDisplayIsCaptured`, which are missing.
