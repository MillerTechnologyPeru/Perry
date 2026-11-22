---
name: Mactracker
bundle_id: "ca.ianpage.Mactracker"
platform: ios
kind: app
tags: [ObjC]
reports:
  - pr: 28
    date: 2026-11-06
    perry: "2152ee8e"
    platform: ios
    cpu: arm64
    app_version: "5.1.2"
    hardware: Lenovo Duet 3
    os: Debian sid
    level: 4
    source: body
    notes: Its categories, model lists and model pages work.
    screenshots:
      - url: https://github.com/user-attachments/assets/99b2282b-d710-4404-a5cc-b5582479f8ff
        caption: Categories
      - url: https://github.com/user-attachments/assets/5a3b64fe-e1fe-466b-848d-3313d4e8474a
        caption: Model page
  - pr: 31
    date: 2026-11-06
    perry: "8ec22668"
    platform: ios
    cpu: arm64
    hardware: Lenovo Duet 3
    os: Debian sid
    level: 4
    source: body
    notes: Its Trivia screen, model page tabs and editing screens' bars work.
    screenshots:
      - url: https://github.com/user-attachments/assets/f7a20d6d-7ada-473a-8e80-223df4488a5f
        caption: Trivia
  - pr: 33
    date: 2026-11-06
    perry: "63e95537"
    platform: ios
    cpu: arm64
    hardware: Lenovo Duet 3
    os: Debian sid
    level: 4
    source: body
    notes: Every screen opens.
  - pr: 40
    date: 2026-11-06
    perry: "b4caa7b6"
    platform: ios
    cpu: arm64
    hardware: Lenovo Duet 3
    os: Debian sid
    level: 4
    source: body
    notes: "Search works: typing filters its lists and a result opens its model page."
  - pr: 41
    date: 2026-11-06
    perry: "6d1dc45a"
    platform: ios
    cpu: arm64
    hardware: Lenovo Duet 3
    os: Debian sid
    level: 4
    source: body
    notes: Its Favorites list, sort menu and deleting a favorite work.
  - pr: 43
    date: 2026-11-06
    perry: "49b82206"
    platform: ios
    cpu: arm64
    hardware: Lenovo Duet 3
    os: Debian sid
    level: 4
    source: body
    notes: Its Compare screen, Trivia pictures and My Models date picker work.
    screenshots:
      - url: https://github.com/user-attachments/assets/c358421c-fa42-4c38-a11d-be60d5d073d2
        caption: Compare screen
  - pr: 261
    date: 2026-11-21
    perry: "3a2980f8"
    platform: ios
    cpu: arm64
    app_version: "5.1.2"
    hardware: Lenovo Duet 3
    os: Debian sid
    resolution: "488x1055"
    env:
      - "PERRY_OS_VERSION=17.0"
      - "PERRY_UIKIT_SCREEN=iphone"
    level: 4
    source: body
    notes: Its categories, model lists and model pages draw as on iOS 17 in light and dark, with inset cards, section titles, disclosure chevrons and symbols in the bar. A model page's header stays light in the dark appearance, and list rows do not grow for wrapped subtitles.
    screenshots:
      - url: https://github.com/user-attachments/assets/e06614f3-d26e-4513-961b-06998c955c82
        caption: Categories, dark
      - url: https://github.com/user-attachments/assets/938252dd-4397-436d-8dca-ee60f9ed7fc5
        caption: Model list, dark
      - url: https://github.com/user-attachments/assets/1ac15977-a13b-4269-a28b-7ccc59ef4e1d
        caption: Model page
---
