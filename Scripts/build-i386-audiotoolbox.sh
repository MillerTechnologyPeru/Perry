#!/bin/sh
# Builds libPerryAudioToolbox.so for i386, the provider for AudioToolbox.framework
# (and CoreAudio's and AudioUnit's functions, which the loader sends to it),
# into .build/i386/bin beside perry32, which finds providers there. It plays
# through GStreamer or OpenAL, which it opens at run time.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$root/.build/i386/bin" "$root/.build/i386/obj"
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$root:/perry" -w /perry --entrypoint sh "${PERRY_IMAGE:-perry-dev}" -euc '
    sysroot=/perry/.toolchains/i386-sdk/sysroot out=.build/i386
    gcc=$(dirname "$(find $sysroot -name crtbegin.o | head -1)")
    # -freg-struct-return: small structures come back in eax:edx, as Darwin
    # returns them.
    cflags="--target=i686-linux-gnu --sysroot=$sysroot --gcc-install-dir=$gcc -march=i686 -msse2 -mfpmath=sse -fPIC -O1 -g -D_GNU_SOURCE -D_FILE_OFFSET_BITS=64 -freg-struct-return -Wall -Wno-unused-function -ISources/PerryAudioToolbox/include -ISources/PerryInterface/include"
    objects=""
    for source in Sources/PerryAudioToolbox/*.c; do
        name=$(basename "$source")
        object=$out/obj/audiotoolbox-$name.o
        clang $cflags -c "$source" -o "$object" || failed=1
        objects="$objects $object"
    done
    [ -z "${failed:-}" ]
    clang --target=i686-linux-gnu --sysroot=$sysroot --gcc-install-dir=$gcc -fuse-ld=lld -shared $objects \
        -o $out/bin/libPerryAudioToolbox.so -lm -lpthread -ldl -Wl,-z,defs'
echo "$root/.build/i386/bin/libPerryAudioToolbox.so"
