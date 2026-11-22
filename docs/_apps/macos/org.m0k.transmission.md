---
name: Transmission
bundle_id: "org.m0k.transmission"
platform: macos
kind: app
developer: Transmission Project
tags: [ObjC]
reports:
  - pr: 274
    date: 2026-11-22
    perry: "faba4457"
    platform: macos
    cpu: i386
    app_version: "2.42"
    hardware: Dell OptiPlex 7020
    resolution: "515x333"
    env:
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
    os: Debian 13
    level: 3
    source: body
    notes: Shows its legal alert, then its main window with the menu bar, the full toolbar, the filter bar and the status bar, and idles at about 2% CPU. Adding a torrent was not tried.
    screenshots:
      - url: https://github.com/user-attachments/assets/2ffc4cf2-830e-4d29-8b81-be0845b24d5f
        caption: The main window with its toolbar icons, Quick Look's included
---

The BitTorrent client's last release for Leopard, run as its i386 slice under
`perry32`. Getting it to its main window took a section-slide overflow fix in
the Objective-C runtime (#270), the i386 System and loader builds brought up
to date, bringing in `kqueue` and the libobjc fallback for Sparkle's
`objc_msgSend` bound to WebKit (#273), and toolbar items that pass their image
to their button (#274). Its `libcrypto.0.9.7` calls and the keychain are
stubs, and `NSLevelIndicatorCell` and `NSPredicateEditorRowTemplate`, which
its peer and filter views subclass, are missing. The non-PIE executable loads
at 0x1000, so the host needs `vm.mmap_min_addr` at 4096.
