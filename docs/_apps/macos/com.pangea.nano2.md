---
name: Nanosaur 2
bundle_id: "com.pangea.nano2"
platform: macos
kind: game
developer: Pangea Software
reports:
  - pr: 285
    date: 2026-11-22
    perry: "f7459ef5"
    platform: macos
    cpu: i386
    app_version: "2.0.7"
    hardware: Dell OptiPlex 7020
    os: Debian 13
    graphics: OpenGL
    env:
      - "PERRY_UNIMPLEMENTED=continue"
      - "PERRY_OBJC_UNRECOGNIZED=continue"
      - "SDL_VIDEODRIVER=x11"
    level: 2
    source: body
    notes: Finds its data and the keyboard, shows its registration dialog and, from Demo, its video mode dialog with working pop-up, radio and checkbox controls. Choosing Set to start the game fails to make its OpenGL window on X11.
    screenshots:
      - url: https://github.com/user-attachments/assets/5bdaf66f-4910-4533-8279-a6215a991f10
        caption: The video mode dialog
      - url: https://github.com/user-attachments/assets/78208ba0-bb6c-4b56-becf-cf12c20d8708
        caption: The registration dialog, with its serial number field
---

Pangea's Carbon game, run as its i386 slice under `perry32`. Getting to its
dialogs took Carbon's default folder starting in `Contents/MacOS` and Mac
paths' leading `::` (#280), the keyboard as a HID device in the I/O Registry
with its device interface (#281), i386 CFNumbers of `long` being a word
(#282), and real pop-up buttons, checkboxes, radio groups, group boxes and
text fields from its nib (#285).

Its data's resource forks must be AppleDouble files (`._name`) beside their
files; an HFS+ image extracted with 7-Zip leaves them as `name:rsrc`, which
need converting. Preferences aren't saved yet (`DirCreate` is missing), so
both dialogs come back each launch. Starting the game ends with SDL unable to
make a GLES window surface on X11; sound loading also calls `dtox80`,
`HNoPurge` and `GetSoundHeaderOffset`, which are missing.
