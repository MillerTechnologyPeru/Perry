---
name: Microsoft Authenticator
bundle_id: "com.microsoft.azureauthenticator"
platform: ios
kind: app
reports:
  - pr: 215
    date: 2026-11-19
    perry: "ed44b512"
    platform: ios
    cpu: arm64
    app_version: "6.8.58"
    hardware: Lenovo Duet 3
    level: 3
    source: body
    notes: Reaches its full main screen; adding an account needs a real sign-in.
    screenshots:
      - url: https://github.com/user-attachments/assets/01807e5a-1817-417b-a5b5-4a36d033834e
        caption: Main screen
---

Needs `PERRY_OS_VERSION=18.0` and `Scripts/extract-assets.sh` run on the app.
