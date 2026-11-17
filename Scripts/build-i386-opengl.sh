#!/bin/sh
# Builds libPerryOpenGL.so for i386, the provider for OpenGL.framework (and AGL), into
# .build/i386/bin beside perry32, which finds providers there.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$root/.build/i386/bin" "$root/.build/i386/obj"
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$root:/perry" -w /perry --entrypoint sh perry-dev -euc '
    sysroot=/perry/.toolchains/i386-sdk/sysroot out=.build/i386
    gcc=$(dirname "$(find $sysroot -name crtbegin.o | head -1)")
    # -freg-struct-return: small structures come back in eax:edx, as Darwin
    # returns them.
    cflags="--target=i686-linux-gnu --sysroot=$sysroot --gcc-install-dir=$gcc -march=i686 -msse2 -mfpmath=sse -fPIC -O1 -g -D_GNU_SOURCE -freg-struct-return -Wall -Wno-unused-function -ISources/PerryOpenGL/include -ISources/CPerryWrapped/include -ISources/PerryInterface/include"
    objects=""
    for source in Sources/PerryOpenGL/*.c Sources/CPerryWrapped/wrapped.c; do
        name=$(basename "$source")
        object=$out/obj/opengl-$name.o
        clang $cflags -c "$source" -o "$object" || failed=1
        objects="$objects $object"
    done
    [ -z "${failed:-}" ]
    clang --target=i686-linux-gnu --sysroot=$sysroot --gcc-install-dir=$gcc -fuse-ld=lld -shared $objects \
        -o $out/bin/libPerryOpenGL.so -lm -lpthread -ldl -Wl,-z,defs'
echo "$root/.build/i386/bin/libPerryOpenGL.so"
