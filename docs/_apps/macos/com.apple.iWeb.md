---
name: iWeb
bundle_id: "com.apple.iWeb"
platform: macos
kind: app
developer: Apple
tags: [ObjC]
reports:
  - pr: 322
    date: 2026-11-23
    perry: "89c0710f"
    platform: macos
    cpu: i386
    app_version: "3.0"
    hardware: Dell OptiPlex 7020
    os: Debian 13
    env:
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
      - "SDL_VIDEODRIVER=x11"
    level: 2
    source: body
    notes: Loads its iWork-based frameworks and opens its MobileMe welcome window with the menu bar. The window's picture is blank and its longer labels are cut short; its template chooser has not been reached.
    screenshots:
      - url: https://github.com/user-attachments/assets/825f6b26-8bb1-48f1-bd94-4323bed44a2c
        caption: The MobileMe welcome window
---

iLife '09's web designer, run as its i386 slice under `perry32`. Its
archiving, shared with iWork's SF frameworks, registers `NSCalendarDate` for
dates and `CIFilter` for Core Image filters, so it quit at launch while both
were missing. It took `NSCalendarDate` in Foundation (#318), Core Image moved
from UIKit's provider to QuartzCore's so that Mac apps have it (#317), and
fixes to build it (#322). It calls `CFDateFormatterCreate` and related
functions, which are missing.
