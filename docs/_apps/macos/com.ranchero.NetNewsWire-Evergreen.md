---
name: NetNewsWire for Mac
bundle_id: "com.ranchero.NetNewsWire-Evergreen"
platform: macos
kind: app
tags: [Swift, ObjC, C++]
reports:
  - pr: 67
    date: 2026-11-06
    perry: "6f5d03ca"
    platform: macos
    cpu: arm64
    app_version: "7.2.1"
    hardware: Lenovo Duet 3
    os: Debian sid
    level: 3
    source: body
    notes: Launches and shows its sidebar, timeline and detail panes; the article pane is not shown yet.
  - pr: 72
    date: 2026-11-07
    perry: "9a0318bf"
    platform: macos
    cpu: arm64
    hardware: Lenovo Duet 3
    os: Debian sid
    level: 3
    source: body
    notes: Loads its feeds and shows a selected feed's articles in the timeline.
  - pr: 77
    date: 2026-11-07
    perry: "fc8f20d9"
    platform: macos
    cpu: arm64
    hardware: Lenovo Duet 3
    os: Debian sid
    level: 3
    source: body
    notes: The article pane shows the selected article through WPE WebKit.
  - pr: 81
    date: 2026-11-07
    perry: "44347d9c"
    platform: macos
    cpu: arm64
    hardware: Lenovo Duet 3
    os: Debian sid
    level: 4
    source: body
    notes: Article links open in the desktop's browser.
  - pr: 89
    date: 2026-11-07
    perry: "68615b9c"
    platform: macos
    cpu: arm64
    hardware: Lenovo Duet 3
    os: Debian sid
    level: 4
    source: body
    notes: Its timeline scrolls by touch with momentum, in frames of about 8 to 12 ms.
  - pr: 341
    date: 2026-11-24
    perry: "8e6d985f"
    platform: macos
    cpu: x86_64
    app_version: "7.3.1"
    hardware: HP Notebook
    os: Debian 13
    env:
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
      - "WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1"
    level: 3
    source: body
    notes: The x86_64 build reaches its main window with its menus, toolbar, sidebar, timeline and article pane; its default feeds don't appear yet.
  - pr: 364
    date: 2026-11-24
    perry: "bf61cc47"
    platform: macos
    cpu: x86_64
    app_version: "7.3.1"
    hardware: HP Notebook
    os: Debian 13
    env:
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
      - "WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1"
    level: 3
    source: body
    notes: The arrow keys move through the article list and between it and the article, and Tab moves between panes; only the list with the keyboard shows its selection in blue.
  - pr: 365
    date: 2026-11-24
    perry: "d4a5bce1"
    platform: macos
    cpu: x86_64
    app_version: "7.3.1"
    hardware: HP Notebook
    resolution: "1230x515@1"
    os: Debian 13
    env:
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
      - "WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1"
    level: 4
    source: body
    notes: Its default feeds load with their icons, articles and unread counts, and the selected article shows in the article pane; a few feed icons in ICO format don't show.
    screenshots:
      - url: https://github.com/user-attachments/assets/ba9450c7-a0a1-4be1-b488-51ea55bb0005
        caption: A Daring Fireball article, with the article list focused
  - pr: 374
    date: 2026-11-24
    perry: "eaed83a8"
    platform: macos
    cpu: x86_64
    app_version: "7.3.1"
    hardware: HP Notebook
    os: Debian 13
    env:
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
      - "WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1"
    level: 4
    source: body
    notes: Feed icons served as ICO files show, such as Julia Evans' and Michael Tsai's; inessential shows none, since its site serves an empty favicon.ico.
---

The x86_64 runs use the release from GitHub, a universal binary, in the
`perry-dev` image from the Dockerfile (Debian 13) on a Debian 12 laptop.
They need an x86_64 macOS Swift runtime (`PERRY_SWIFT_RUNTIME`) with
Perry's overlays and a `libswiftFoundation.dylib` built from
`Darwin/Foundation` for `x86_64-apple-macos15.0`. The app also needs the
images from `Scripts/extract-assets.sh`: it force-unwraps
`faviconTemplateImage`, a deepmap2 and vector rendition. Inside the
container, WebKit's web process can't make its bubblewrap sandbox, hence
`WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1`.
