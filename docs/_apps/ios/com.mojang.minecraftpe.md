---
name: Minecraft
bundle_id: "com.mojang.minecraftpe"
platform: ios
kind: game
reports:
  - pr: 80
    date: 2026-11-07
    perry: "dbb48139"
    platform: ios
    cpu: arm64
    app_version: "1.26.62"
    hardware: Retroid Pocket Flip 2
    os: ROCKNIX
    level: 1
    source: body
    notes: Gets through start-up into its Metal renderer; no menu is drawn yet.
  - pr: 84
    date: 2026-11-07
    perry: "294bc030"
    platform: ios
    cpu: arm64
    app_version: "1.18.12"
    hardware: Retroid Pocket Flip 2
    os: ROCKNIX
    level: 2
    source: body
    notes: Runs its loading screen at 60 frames a second; it more often stops at 33% than reaching the title screen.
    screenshots:
      - url: https://github.com/user-attachments/assets/5f63e7ac-6d2f-4d32-be45-c9a2364c76b5
        caption: Loading screen
---
