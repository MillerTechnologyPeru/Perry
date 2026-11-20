---
name: N.O.V.A. 3
bundle_id: "com.gameloft.nova3"
platform: ios
kind: game
reports:
  - pr: 115
    date: 2026-11-09
    perry: "a84ccf33"
    platform: ios
    cpu: arm64
    hardware: Retroid Pocket Flip 2
    os: ROCKNIX
    level: 3
    source: body
    notes: Reaches its menu and consent dialog; touch input on the dialog does not work.
    screenshots:
      - url: https://github.com/user-attachments/assets/f4dade9b-4058-4b30-9d89-cbdfacfe867a
        caption: Title, drawn inside a portrait screen
---

The game draws its landscape picture inside a portrait screen. `PERRY_UIKIT_SCREEN=390x844@3 PERRY_UIKIT_ORIENTATION=portrait PERRY_UIKIT_DISPLAY_ROTATION=90` shows it upright.
