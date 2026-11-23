---
name: Xcode 4
bundle_id: "com.apple.dt.Xcode"
platform: macos
kind: app
developer: Apple
tags: [ObjC]
reports:
  - pr: 290
    date: 2026-11-22
    perry: "e7634f19"
    platform: macos
    cpu: x86_64
    app_version: "4.6"
    hardware: Dell OptiPlex 7020
    os: Debian 13
    env:
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
    level: 2
    source: body
    notes: Launches to the Xcode License Agreement window with its text; the components page after Agree doesn't draw.
    screenshots:
      - url: https://github.com/user-attachments/assets/4aba58cc-7c2e-4823-a158-706974a9a1cf
        caption: The Xcode License Agreement
      - url: https://github.com/user-attachments/assets/b1002d9f-484d-4d15-a6c9-3141d314a3b3
        caption: After Agree, the components page doesn't draw
---

Xcode 4.6 (4H127) requires the garbage collector, which Perry reports on
for it while keeping every object, as it does for Xcode 3.

Its libc++ is Perry's `libperry-c++`. Where that isn't installed
system-wide, as the Dockerfile installs it, `LD_LIBRARY_PATH` has to name
its folder, or `libperry-c++abi.so.1` isn't found and every libc++ import
is unresolved.

Xcode keeps a plug-in cache in Perry's container
(`tmp/Caches/com.apple.DeveloperTools/4.6 (4H127)/Xcode/PlugInCache.xcplugincache`).
One written by a Perry that couldn't read the plug-ins leaves Xcode without
its extension points ("Xcode Failed to Launch") until it is deleted.

Broken:

- After Agree, the page that installs additional components doesn't draw:
  the window's transition uses `-[NSView animator]` and
  `-cacheDisplayInRect:toBitmapImageRep:`. The page would install Apple's
  packages with an administrator's rights.
- File system events are never delivered, so Xcode doesn't see files
  changed outside it.
