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
own, 800×600 at first. The device's screen has no such mode, so Perry shows
the game full screen at the screen's size and scales its picture to fit;
the game's Video settings offer the usual sizes up to the screen's own.
`HALO_SCREEN=800x600` has the launcher run it in gamescope instead, which
isn't the default: on ROCKNIX's sway gamescope often aborts as the game
starts, and the game ends with it.

The right stick moves the mouse at a third of gptokeyb's usual speed
(`mouse_scale` in `halo.gptk`); Halo's own Mouse Setup changes it further.

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
| D-pad up, down | up and down in menus |
| D-pad left | flashlight |
| D-pad right | exchange weapon |
| Start | Enter: choose in menus |
| Select | Escape: back in menus, pause in a game |
| Select + Start | quit |
