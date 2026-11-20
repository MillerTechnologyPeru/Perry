# Packaging

Launchers, desktop entries and port scripts for running apps with Perry on
particular systems. Nothing here is built into Perry: these are the files
that sit beside an app on a device, kept so a working setup can be repeated.

## Layout

```
Packaging/
├── shared/                 pieces several apps use
│   ├── box86/              running i386 Perry on 32- and 64-bit ARM
│   └── mangohud/           the MangoHud overlay for i386 and armhf
└── <platform>/<bundle id>/ one app, as in docs/_apps/<platform>/<bundle id>.md
    ├── README.md           what each file does and where it goes
    ├── linux/              an x86 PC running Perry natively
    ├── box86/              a desktop ARM Linux running i386 Perry under box86
    └── portmaster/         ROCKNIX and other PortMaster systems
```

The folders under an app are named for how it runs, not for a device, so
one launcher serves every machine of that kind. Each app's README says which
machines it was tested on.

## Conventions

- **No app files.** Only launchers and settings go here. The app comes from
  the user's own copy; a launcher says where it looks for it.
- **No binaries.** Anything that has to be built or downloaded is described
  in the README beside it, with the commands that make it.
- **No personal paths.** Scripts read `PERRY_ROOT` for Perry (a checkout, or
  a runtime folder made by `shared/box86/install-runtime.sh`) and `GAME` for
  the app bundle, with defaults a README states.
- **Desktop entries** are named for the app's bundle ID, and their
  `StartupWMClass` matches the `SDL_APP_ID` the launcher sets, so the desktop
  groups the window under its icon.
- A compatibility report can point to the folder it ran with, in its
  `packaging` field.
