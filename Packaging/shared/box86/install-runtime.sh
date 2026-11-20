#!/bin/sh
# Copies i386 Perry and the i386 libraries it runs with to an ARM Linux
# machine over ssh, for box86: a runtime folder that launchers name as
# PERRY_ROOT. Builds libc23box.so first. Needs only ssh and tar there.
#
# Usage: install-runtime.sh <ssh destination> <folder there>
#   e.g. install-runtime.sh root@RetroidPocket5.local /storage/perry-i386
#
# Run from a Perry checkout with .build/i386/bin built and the i386 SDK in
# .toolchains/i386-sdk (Scripts/build-i386-*.sh). A libperrybox.so, which
# isn't built here, is copied too when PERRY_BOX_SHIM names one; see README.md.
set -eu
[ $# -eq 2 ] || { echo "usage: $0 <ssh destination> <folder there>" >&2; exit 2; }
host=$1 dir=$2
root=$(cd "$(dirname "$0")/../../.." && pwd)
here=$(cd "$(dirname "$0")" && pwd)
sysroot=$root/.toolchains/i386-sdk/sysroot
[ -x "$root/.build/i386/bin/perry32" ] || { echo "no .build/i386/bin/perry32: build i386 Perry first" >&2; exit 1; }
[ -d "$sysroot/usr/lib/i386-linux-gnu" ] || { echo "no i386 sysroot in .toolchains/i386-sdk" >&2; exit 1; }

# The shim, against the sysroot's glibc.
out=$root/.build/i386/box86
mkdir -p "$out"
gcc_dir=$(dirname "$(find "$sysroot/usr/lib/gcc" -name crtbegin.o | head -n 1)")
clang --target=i686-linux-gnu --sysroot="$sysroot" --gcc-install-dir="$gcc_dir" -fuse-ld=lld \
    -shared -fPIC -O1 -Wl,--version-script="$here/libc23box.map" \
    "$here/libc23box.c" -o "$out/libc23box.so"

ssh "$host" "mkdir -p '$dir/bin' '$dir/sysroot/usr/lib' '$dir/gst-plugins'"

# Perry. libPerryCFNetwork's i386 libcurl needs Kerberos and libunistring
# functions box86 doesn't have, and nothing here needs the network.
(cd "$root/.build/i386/bin" && tar czf - --exclude=libPerryCFNetwork.so .) |
    ssh "$host" "tar xzf - -C '$dir/bin'"

# The libraries Perry is built against.
(cd "$sysroot/usr/lib" && tar czf - swift/linux i386-linux-gnu) |
    ssh "$host" "tar xzf - -C '$dir/sysroot/usr/lib'"

# The shims.
ssh "$host" "cat > '$dir/libc23box.so'" < "$out/libc23box.so"
if [ -n "${PERRY_BOX_SHIM:-}" ]; then
    ssh "$host" "cat > '$dir/libperrybox.so'" < "$PERRY_BOX_SHIM"
fi

# The GStreamer plugins Perry's audio uses, alone: loading all of them under
# box86 is slow, and some need libraries it doesn't have.
ssh "$host" "cd '$dir/gst-plugins' && for p in app audioconvert audioresample autodetect coreelements pulseaudio volume; do ln -sf \"../sysroot/usr/lib/i386-linux-gnu/gstreamer-1.0/libgst\$p.so\" .; done"

echo "Installed in $host:$dir"
