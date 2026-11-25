# Halo

MacSoft's Halo: Combat Evolved, the Universal Binary release (2.0), run as
its i386 half.
Compatibility: [docs/_apps/macos/com.macsoft.halo.md](../../../docs/_apps/macos/com.macsoft.halo.md).

## Getting the game

Install it from your own disc: `Halo.pkg` on the disc holds `Halo.app`. The
game looks for its disc each time it starts, so the disc's contents go
beside it, and the launcher names them as a mounted disc
(`PERRY_DISCS="Halo Universal=<folder>"`). It asks for your product key the
first time.

The launcher sets `PERRY_UNIMPLEMENTED=continue` and
`PERRY_OBJC_UNRECOGNIZED=continue`, and a container (`PERRY_CONTAINER`) whose
path has no period in it: Halo refuses a Documents folder with one.

## portmaster: ROCKNIX

| File | Goes in |
| --- | --- |
| `portmaster/Halo.sh` | `roms/ports/`, where it's listed under Ports |
| `portmaster/halo/run.sh` | `roms/ports/halo/`; runs the game under box86, also over ssh; `PERRY_MANGOHUD=1` adds MangoHud |
| `portmaster/halo/halo.gptk` | `roms/ports/halo/`: the controls |

The game goes in `roms/ports/halo/Halo.app`, the disc's contents in
`roms/ports/halo/disc`, and the runtime in `/storage/perry-i386`:
`Packaging/shared/box86/install-runtime.sh root@<device> /storage/perry-i386`,
plus box86 built as [the runtime's README](../../shared/box86/README.md)
says, as `/storage/perry-i386/box86`. Preferences, profiles and saved games
are kept in `roms/ports/halo/conf`.

The game plays full screen by switching the display to a resolution of its
own, 800×600 at first. The launcher runs it in gamescope, where there is
one, with a screen of that size scaled to the device's; `HALO_SCREEN` gives
another size (`HALO_SCREEN=1024x768`), which the game's Video settings then
offer, and `HALO_SCREEN=off` leaves gamescope out.

| Control | |
| --- | --- |
| Left stick | walk (W A S D) |
| Right stick | look (the mouse) |
| R2 | fire, and click in menus |
| L2 | throw a grenade |
| A | jump |
| B | melee |
| X | reload |
| Y | switch weapon |
| L1 | action |
| R1 | switch grenade |
| L3 | crouch |
| R3 | zoom |
| D-pad up | flashlight |
| D-pad down | Return |
| Start | Escape |
| Select + Start | quit |
