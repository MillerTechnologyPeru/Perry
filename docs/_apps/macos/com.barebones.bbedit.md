---
name: BBEdit
bundle_id: "com.barebones.bbedit"
platform: macos
kind: app
developer: Bare Bones Software
tags: [ObjC, Swift, C++]
reports:
  - pr: 416
    date: 2026-11-25
    perry: "ffd17110"
    platform: macos
    cpu: x86_64
    app_version: "16.1.1"
    hardware: HP Notebook
    os: Debian 13
    env:
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
    level: 1
    source: maintainer
    notes: Starts past its crash reporter and Software Update and builds its menus, then aborts on a corrupted heap before showing a window.
---

This is the Developer ID build from barebones.com, which has an x86_64
slice; the Mac App Store edition of 16.1.1 is arm64 only. Its menus ask for
`PasteboardCreate`, which isn't there yet, just before the heap is found
corrupted.
