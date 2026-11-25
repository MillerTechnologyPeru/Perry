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
  - pr: 417
    date: 2026-11-25
    perry: "809aa7a0"
    platform: macos
    cpu: i386
    app_version: "3.0"
    hardware: Dell OptiPlex 7020
    os: Debian 13
    env:
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
      - "SDL_VIDEODRIVER=x11"
    level: 3
    source: body
    notes: Past the MobileMe welcome it makes its first site, opens its site window and its theme chooser, which lists the themes and page templates with their thumbnails. The pictures in the thumbnails are upside down; making a page from a template was not tried.
    screenshots:
      - url: https://github.com/user-attachments/assets/2dfb142b-d871-4a45-b0b2-2bef256834fe
        caption: The theme chooser with its theme and page thumbnails
---

iLife '09's web designer, run as its i386 slice under `perry32`. Its
archiving, shared with iWork's SF frameworks, registers `NSCalendarDate` for
dates and `CIFilter` for Core Image filters, so it quit at launch while both
were missing. It took `NSCalendarDate` in Foundation (#318), Core Image moved
from UIKit's provider to QuartzCore's so that Mac apps have it (#317), and
fixes to build it (#322). It calls `CFDateFormatterCreate` and related
functions, which are missing.

Making its first site took `objectForInfoDictionaryKey:` giving
InfoPlist.strings' localized `CFBundleName`, for its Application Support
folder, with `tempnam`, `getlogin` and `CopyProcessName` (#331, #336); its
theme chooser, the i386 struct-return forwarder popping its result pointer,
`NSDeviceCMYKColorSpace` and `dataCellForRow:` not sending itself to an
override (#384), bitmaps and layer images too big for a 32-bit address space
drawing nothing (#386), and the data symbols its frameworks link (#400). Its
thumbnails took `NSAffineTransform`, and archiving an `NSColor` with
`NSArchiver` took its typed stream (#409, #417). WPE's sandbox can't run the
host's 64-bit `xdg-dbus-proxy` for i386, so its web views abort unless
`DBUS_SESSION_BUS_ADDRESS` is unset.
