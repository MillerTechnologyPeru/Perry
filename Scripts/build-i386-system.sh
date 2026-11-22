#!/bin/sh
# Builds libPerrySystem.so for i386, the provider for libSystem, into
# .build/i386/bin beside perry32, which finds providers there.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$root/.build/i386/bin" "$root/.build/i386/obj"
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$root:/perry" -w /perry --entrypoint sh perry-dev -euc '
    sysroot=/perry/.toolchains/i386-sdk/sysroot out=.build/i386
    gcc=$(dirname "$(find $sysroot -name crtbegin.o | head -1)")
    # -freg-struct-return: small structures come back in eax:edx, as Darwin
    # returns them.
    cflags="--target=i686-linux-gnu --sysroot=$sysroot --gcc-install-dir=$gcc -march=i686 -msse2 -mfpmath=sse -fPIC -O1 -g -D_GNU_SOURCE -D_FILE_OFFSET_BITS=64 -freg-struct-return -ISources/PerrySystem/include -ISources/PerryInterface/include"
    objects=""
    # Every C source, as SwiftPM builds the target, and the i386 thunks.
    for name in thunks_i386.S $(cd Sources/PerrySystem && ls *.c); do
        object=$out/obj/system-$name.o
        clang $cflags -c "Sources/PerrySystem/$name" -o "$object" || failed=1
        objects="$objects $object"
    done
    [ -z "${failed:-}" ]
    clang --target=i686-linux-gnu --sysroot=$sysroot --gcc-install-dir=$gcc -fuse-ld=lld -shared $objects \
        -o $out/bin/libPerrySystem.so -lm -lpthread -ldl -latomic -Wl,-z,defs'
echo "$root/.build/i386/bin/libPerrySystem.so"
