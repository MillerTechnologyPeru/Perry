#!/bin/sh
# Bejeweled 3's Mac build on an x86 PC, through perry32. Arguments go to the
# game. PERRY_ROOT is a Perry checkout with i386 Perry built (default: the one
# holding this script); GAME is the app (default: Steam's download of its Mac
# depot, see ../README.md).
self=$(readlink -f "$0")
: "${PERRY_ROOT:=$(cd "$(dirname "$self")/../../../.." && pwd)}"
: "${GAME:=$HOME/.local/share/Steam/ubuntu12_32/steamapps/content/app_78000/depot_78011/Bejeweled 3.app}"
sysroot=$PERRY_ROOT/.toolchains/i386-sdk/sysroot
export LD_LIBRARY_PATH="$PERRY_ROOT/.build/i386/bin:$sysroot/usr/lib/swift/linux:$sysroot/usr/lib/i386-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
# Steam's leaderboards and achievements, when Steam is running.
export SteamAppId=78000 SteamGameId=78000
export PERRY_UNIMPLEMENTED=continue PERRY_OBJC_UNRECOGNIZED=continue
# The desktop entry's StartupWMClass.
export SDL_APP_ID=com.popcap.Bejeweled3
exec "$PERRY_ROOT/.build/i386/bin/perry32" "$GAME" "$@"
