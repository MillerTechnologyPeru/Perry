---
name: Call of Duty 4
bundle_id: "com.aspyr.callofduty4.sp.steam"
platform: macos
kind: game
reports:
  - pr: 178
    date: 2026-11-17
    perry: "2898682f"
    platform: macos
    cpu: i386
    hardware: Dell OptiPlex 7020
    level: 2
    source: body
    notes: Gets through its launcher into the engine's initialization and main loop.
  - pr: 183
    date: 2026-11-18
    perry: "60e359ea"
    platform: macos
    cpu: i386
    hardware: Dell OptiPlex 7020
    level: 2
    source: body
    notes: Goes from its launcher through engine, sound, renderer and asset start-up into its main loop, where it renders frames.
---
