#!/bin/sh
# run.sh with the MangoHud overlay: Debian's i386 MangoHud, unpacked by
# ../../../shared/mangohud/fetch.sh i386 into MANGOHUD_ROOT (default:
# .build/i386/mangohud in the Perry checkout).
self=$(readlink -f "$0")
here=$(dirname "$self")
: "${PERRY_ROOT:=$(cd "$here/../../../.." && pwd)}"
: "${MANGOHUD_ROOT:=$PERRY_ROOT/.build/i386/mangohud}"
lib=$MANGOHUD_ROOT/usr/lib/i386-linux-gnu
[ -e "$lib/mangohud/libMangoHud_opengl.so" ] || { echo "No i386 MangoHud in $MANGOHUD_ROOT: run Packaging/shared/mangohud/fetch.sh i386 $MANGOHUD_ROOT" >&2; exit 1; }
export PERRY_ROOT
export LD_LIBRARY_PATH="$lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LD_PRELOAD="$lib/mangohud/libMangoHud_dlsym.so:$lib/mangohud/libMangoHud_opengl.so"
exec "$here/run.sh" "$@"
