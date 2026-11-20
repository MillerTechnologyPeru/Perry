#!/bin/sh
# Downloads Debian's MangoHud for another architecture and the libraries it
# needs that a Perry setup doesn't have (fmt, spdlog, xkbcommon), and unpacks
# them into a folder, without installing anything. The architecture has to be
# added to dpkg (dpkg --add-architecture) for apt to know its packages.
#
# Usage: fetch.sh <i386 | armhf> <folder>
#   i386:  for perry32 on an x86 PC; preload mangohud/libMangoHud_dlsym.so and
#          mangohud/libMangoHud_opengl.so, or libMangoHud_shim.so where present.
#   armhf: for box86, which draws with the machine's armhf GL; preload
#          mangohud/libMangoHud_shim.so into box86 itself.
# The libraries end up in <folder>/usr/lib/<triplet>.
set -eu
[ $# -eq 2 ] || { echo "usage: $0 <i386 | armhf> <folder>" >&2; exit 2; }
arch=$1 out=$2
mkdir -p "$out/debs"
out=$(cd "$out" && pwd)
cd "$out/debs"

apt-get download "mangohud:$arch"
# Its dependencies that are libraries of its own, by real package name: a
# dependency can be a virtual package (libspdlog1.15-fmt10), provided by another.
for dep in $(dpkg-deb -f mangohud_*_"$arch".deb Depends | tr ',' '\n' | sed 's/(.*)//; s/|.*//; s/ //g' |
             grep -E '^(libfmt|libspdlog|libxkbcommon)'); do
    if apt-cache policy "$dep:$arch" | grep -q 'Candidate: [^(]'; then
        apt-get download "$dep:$arch"
    else
        provider=$(apt-cache showpkg "$dep:$arch" | sed -n '/^Reverse Provides:/,$p' | sed -n '2p' | cut -d' ' -f1)
        [ -n "$provider" ] && apt-get download "${provider%%:*}:$arch"
    fi
done
for deb in *.deb; do dpkg-deb -x "$deb" "$out"; done
find "$out/usr/lib" -name '*.so*' | sort
