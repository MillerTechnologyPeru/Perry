---
name: Xcode
bundle_id: "com.apple.Xcode"
platform: macos
kind: app
reports:
  - pr: 186
    date: 2026-11-18
    perry: "970ed8c3"
    platform: macos
    cpu: x86_64
    app_version: "3.2.6"
    hardware: Dell OptiPlex 7020
    level: 1
    source: body
    notes: Loads its frameworks and plug-ins, then stops before showing a window.
  - pr: 188
    date: 2026-11-18
    perry: "5cd27808"
    platform: macos
    cpu: x86_64
    app_version: "3.2.6"
    hardware: Dell OptiPlex 7020
    level: 1
    source: body
    notes: Gets through launch and waits in its event loop.
  - pr: 189
    date: 2026-11-18
    perry: "9628fc83"
    platform: macos
    cpu: x86_64
    app_version: "3.2.6"
    hardware: Dell OptiPlex 7020
    level: 2
    source: body
    notes: Gets through launch to its Welcome to Xcode window.
  - pr: 190
    date: 2026-11-18
    perry: "f5b7ccd4"
    platform: macos
    cpu: x86_64
    app_version: "3.2.6"
    hardware: Dell OptiPlex 7020
    level: 2
    source: body
    notes: The welcome window opens at its real size, with its PDF header art.
  - pr: 191
    date: 2026-11-18
    perry: "424c112e"
    platform: macos
    cpu: x86_64
    app_version: "3.2.6"
    hardware: Dell OptiPlex 7020
    level: 2
    source: body
    notes: The welcome window shows its header art, start items and Recent Projects panel.
  - pr: 193
    date: 2026-11-18
    perry: "8a8ec414"
    platform: macos
    cpu: x86_64
    app_version: "3.2.6"
    hardware: Dell OptiPlex 7020
    level: 3
    source: body
    notes: Create a new Xcode project opens the New Project assistant; template icons and option check boxes don't draw.
  - pr: 197
    date: 2026-11-18
    perry: "8afb6ac5"
    platform: macos
    cpu: x86_64
    app_version: "3.2.6"
    hardware: Dell OptiPlex 7020
    level: 3
    source: body
    notes: Saving a new project instantiates the Cocoa Application template, and typedstream nibs load.
  - pr: 202
    date: 2026-11-18
    perry: "62f08c53"
    platform: macos
    cpu: x86_64
    app_version: "3.2.6"
    hardware: Dell OptiPlex 7020
    level: 3
    source: body
    notes: Opens a project in its project window, with Groups & Files and the menu bar.
  - pr: 203
    date: 2026-11-19
    perry: "9dc1eb22"
    platform: macos
    cpu: x86_64
    app_version: "3.2.6"
    hardware: Dell OptiPlex 7020
    level: 3
    source: body
    notes: The project window fills its window; file and column-header icons are missing.
    screenshots:
      - url: https://github.com/user-attachments/assets/c8b7182f-4b91-42d7-9935-e6dd7b1c096f
        caption: Project window without icons
  - pr: 205
    date: 2026-11-19
    perry: "b685664b"
    platform: macos
    cpu: x86_64
    app_version: "3.2.6"
    hardware: Dell OptiPlex 7020
    level: 3
    source: body
    notes: The project window shows Xcode's own icons and toolbar buttons.
    screenshots:
      - url: https://github.com/user-attachments/assets/fb6fc9cc-b65c-4ce0-a662-75bc11724ee0
        caption: Project window with icons
  - pr: 206
    date: 2026-11-19
    perry: "db24d63a"
    platform: macos
    cpu: x86_64
    app_version: "3.2.6"
    hardware: Dell OptiPlex 7020
    level: 3
    source: body
    notes: Its toolbar is labelled, target boxes are checked, and projects save without crashing.
  - pr: 208
    date: 2026-11-19
    perry: "837de1b7"
    platform: macos
    cpu: x86_64
    app_version: "3.2.6"
    hardware: Dell OptiPlex 7020
    level: 3
    source: body
    notes: Its gcc-4.2 and ld compile and link a hello world program that Perry runs.
  - pr: 209
    date: 2026-11-19
    perry: "7e42e7a8"
    platform: macos
    cpu: x86_64
    app_version: "3.2.6"
    hardware: Dell OptiPlex 7020
    level: 3
    source: body
    notes: Its toolbar search field shows, with its menu and placeholder.
    screenshots:
      - url: https://github.com/user-attachments/assets/faf0994a-93eb-46fe-aafc-86952ba2c576
        caption: Project window with toolbar search field
  - pr: 214
    date: 2026-11-19
    perry: "dd92de5c"
    platform: macos
    cpu: x86_64
    app_version: "3.2.6"
    hardware: Dell OptiPlex 7020
    level: 3
    source: body
    notes: Opening source files, the project inspector and menus no longer crashes or hangs.
---

Xcode 3.2.6 from Mac OS X 10.6, the x86_64 slice.
