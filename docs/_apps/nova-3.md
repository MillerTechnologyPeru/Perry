---
name: N.O.V.A. 3
platform: ios
kind: game
reports:
  - pr: 115
    date: 2026-11-09
    perry: "a84ccf33"
    arch: arm64
    host: Retroid Pocket Flip 2
    level: 3
    source: body
    notes: Reaches its menu and consent dialog; touch input on the dialog does not work.
---

The game draws its landscape picture inside a portrait screen. `PERRY_UIKIT_SCREEN=390x844@3 PERRY_UIKIT_ORIENTATION=portrait PERRY_UIKIT_DISPLAY_ROTATION=90` shows it upright.
