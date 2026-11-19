---
name: TruckSmart
platform: ios
kind: app
reports:
  - pr: 21
    date: 2026-11-05
    perry: "b1c8bf49"
    arch: arm64
    app_version: "6.3"
    host: Lenovo Duet 3
    level: 2
    source: body
    notes: Launches, loads its sites from its API and shows its first-launch screen.
  - pr: 70
    date: 2026-11-06
    perry: "dcf412dc"
    arch: arm64
    app_version: "6.3"
    host: Lenovo Duet 3
    level: 3
    source: body
    notes: Gets past its splash and first-launch screen to the guest Home tab with live locations.
  - pr: 76
    date: 2026-11-07
    perry: "28bd9336"
    arch: arm64
    level: 3
    source: body
    notes: The Locations tab shows its map, drawn by MapLibre, with the app's site pins.
  - pr: 82
    date: 2026-11-07
    perry: "e0f6394e"
    arch: arm64
    level: 3
    source: body
    notes: "Map annotations draw as on the iPhone: rounded site bubbles with centered titles."
  - pr: 99
    date: 2026-11-07
    perry: "417a4f36"
    arch: arm64
    level: 3
    source: body
    notes: "Location search looks as on an iPhone: the map behind the search bar and the results list."
  - pr: 114
    date: 2026-11-09
    perry: "88907e4a"
    arch: arm64
    level: 3
    source: body
    notes: Starts again without aborting and no longer redraws while idle; list drags are still slow.
---
