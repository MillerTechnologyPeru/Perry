---
name: TextMate
bundle_id: "com.macromates.TextMate"
platform: macos
kind: app
tags: [ObjC, C++]
reports:
  - pr: 61
    date: 2026-11-06
    perry: "c69df9a5"
    platform: macos
    cpu: arm64
    hardware: Lenovo Duet 3
    os: Debian sid
    level: 4
    source: body
    notes: Runs, lays out as on macOS, follows dark mode, takes typing, and its status bar menus work.
    screenshots:
      - url: https://github.com/user-attachments/assets/583ae095-704f-4392-945b-34402596610f
        caption: Editor with the language menu
  - pr: 62
    date: 2026-11-06
    perry: "473396e0"
    platform: macos
    cpu: arm64
    hardware: Lenovo Duet 3
    os: Debian sid
    level: 4
    source: body
    notes: Bundle commands run from submenus, and tabs and syntax colors draw.
  - pr: 415
    date: 2026-11-25
    perry: "01c90075"
    platform: macos
    cpu: x86_64
    app_version: "2.0.23"
    hardware: HP Notebook
    os: Debian 13
    level: 4
    source: maintainer
    notes: The x86_64 build runs with no missing functions or selectors logged; its editor, gutter and status bar draw and it takes typing.
---

On x86_64 TextMate looks its home folder up with `getpwuid`, and retries
until it finds it, so it needs a user database entry for the user it runs
as (a container may not have one). Its bundles are read from
`~/Library/Application Support/TextMate/Managed`, here a copy of a Mac's.
