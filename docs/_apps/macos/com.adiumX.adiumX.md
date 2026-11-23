---
name: Adium
bundle_id: "com.adiumX.adiumX"
platform: macos
kind: app
developer: The Adium Team
tags: [ObjC]
reports:
  - pr: 289
    date: 2026-11-23
    perry: "6d004f5c"
    platform: macos
    cpu: i386
    app_version: "1.4.5"
    hardware: Dell OptiPlex 7020
    os: Debian 13
    env:
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
      - "SDL_VIDEODRIVER=x11"
    level: 2
    source: body
    notes: Opens its Setup Assistant, Sparkle's update prompt and the contact list, offline, and stays up. The Setup Assistant's artwork is blank; signing in to an account was not tried.
---

The chat client's last release for Leopard, run as its i386 slice under
`perry32`. Its plug-ins subclass classes in its own `Adium.framework`, which
took images registered with the runtime after the libraries they link (#287).
It also took `NSTextAttachment`, which it subclasses (#288), and Icon
Services' icon refs and families, aliases and `DirCreate` for the Growl it
bundles (#289).
