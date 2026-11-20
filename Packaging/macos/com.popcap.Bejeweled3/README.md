# Bejeweled 3

PopCap's Bejeweled 3, the Mac build Steam sells (app 78000), an i386 app.
Compatibility: [docs/_apps/macos/com.popcap.Bejeweled3.md](../../../docs/_apps/macos/com.popcap.Bejeweled3.md).

## Getting the game

Steam on Linux installs the Windows version. The Mac build is its depot
78011: with the game in your library, open `steam://open/console` and run

```
download_depot 78000 78011
```

Steam puts it in
`~/.local/share/Steam/ubuntu12_32/steamapps/content/app_78000/depot_78011/Bejeweled 3.app`.

Every launcher sets `PERRY_UNIMPLEMENTED=continue` and
`PERRY_OBJC_UNRECOGNIZED=continue`, which the game needs.

## linux: an x86 PC

Tested on a Dell OptiPlex 7020 running Debian 13, with Steam.

| File | |
| --- | --- |
| `linux/run.sh` | runs the game with perry32 from the checkout holding it, with Steam's app ID for its leaderboards and achievements |
| `linux/run-mangohud.sh` | the same with the MangoHud overlay |
| `linux/com.popcap.Bejeweled3.desktop` | the desktop entry |

Build i386 Perry (`Scripts/build-i386-*.sh`), then:

```sh
ln -s "$PWD/Packaging/macos/com.popcap.Bejeweled3/linux/run.sh" ~/.local/bin/com.popcap.Bejeweled3
cp Packaging/macos/com.popcap.Bejeweled3/linux/com.popcap.Bejeweled3.desktop ~/.local/share/applications/
```

`GAME` overrides where the game is. For MangoHud, unpack Debian's i386 one
first: `Packaging/shared/mangohud/fetch.sh i386 .build/i386/mangohud`.

## box86: desktop ARM Linux

Tested on a Lenovo Duet 3 running Debian sid (aarch64, with the `armhf`
architecture added), on GNOME, in a window: full screen doesn't work.

| File | |
| --- | --- |
| `box86/run.sh` | runs the game under box86 in an X11 window; `PERRY_MANGOHUD=1` adds MangoHud |
| `box86/run-mangohud.sh` | the same with MangoHud |
| `box86/com.popcap.Bejeweled3.desktop` | the desktop entry |

Make a runtime folder with
`Packaging/shared/box86/install-runtime.sh <machine> ~/Perry-i386` (see
[its README](../../shared/box86/README.md) for box86 and the shims), copy the
game to `~/Games/Bejeweled 3.app`, then on the machine link `run.sh` into
`~/.local/bin` as `com.popcap.Bejeweled3` and copy the desktop entry, as
above. For MangoHud: `fetch.sh armhf ~/Perry-i386/mangohud` there.

## portmaster: ROCKNIX

Tested on a Retroid Pocket 5 running ROCKNIX 20261101, full screen, with
sound and the controller.

| File | Goes in |
| --- | --- |
| `portmaster/Bejeweled 3.sh` | `roms/ports/`, where it's listed under Ports |
| `portmaster/bejeweled3/run.sh` | `roms/ports/bejeweled3/`; runs the game under box86, also over ssh; `PERRY_MANGOHUD=1` adds MangoHud |
| `portmaster/bejeweled3/bejeweled3.gptk` | `roms/ports/bejeweled3/`: the controls |

The game goes in `roms/ports/bejeweled3/Bejeweled 3.app`, and the runtime in
`/storage/perry-i386`: `install-runtime.sh root@<device> /storage/perry-i386`,
plus box86 built as the runtime's README says, as `/storage/perry-i386/box86`.

| Control | |
| --- | --- |
| Left stick | moves the mouse pointer |
| A or R1 | click |
| L1 | right-click |
| B or Start | Escape |
| Select + Start | quit |

## Icon

The desktop entries use the icon `com.popcap.Bejeweled3`, from the game's
own `Contents/Resources/bej3.icns`:

```sh
icns2png -x "Bejeweled 3.app/Contents/Resources/bej3.icns"    # Debian's icnsutils
mkdir -p ~/.local/share/icons/hicolor/512x512/apps
cp bej3_512x512x32.png ~/.local/share/icons/hicolor/512x512/apps/com.popcap.Bejeweled3.png
```
