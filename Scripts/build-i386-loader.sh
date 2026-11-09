#!/bin/sh
# Builds perry32, the loader as a 32-bit x86 program, with the perry-dev image's
# clang and the sysroot of Scripts/build-i386-sdk.sh, into .build/i386/bin. It
# runs i386 Mac binaries.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$root/.build/i386/bin" "$root/.build/i386/obj"
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$root:/perry" -w /perry --entrypoint sh perry-dev -euc '
    sysroot=/perry/.toolchains/i386-sdk/sysroot out=.build/i386
    gcc=$(dirname "$(find $sysroot -name crtbegin.o | head -1)")
    cflags="--target=i686-linux-gnu --sysroot=$sysroot --gcc-install-dir=$gcc -march=i686 -msse2 -mfpmath=sse -fPIC -O1 -g -D_GNU_SOURCE -D_FILE_OFFSET_BITS=64 -ISources/PerryLoaderCore/include -ISources/PerryInterface/include"
    objects=""
    for source in Sources/PerryLoaderCore/*.c Sources/PerryLoaderCore/*.S Sources/PerryInterface/interface.c Sources/PerryLoader/main.c; do
        object=$out/obj/loader-$(basename "$source").o
        clang $cflags -c "$source" -o "$object"
        objects="$objects $object"
    done
    # Executables from before 10.7 are not position independent: they load at
    # 0x1000 and run from there, where the kernel would put a
    # position-independent perry32 and its heap. So perry32 is linked at a
    # fixed address far above them.
    clang --target=i686-linux-gnu --sysroot=$sysroot --gcc-install-dir=$gcc -fuse-ld=lld -no-pie -Wl,--image-base=0x70000000 \
        $objects -o $out/bin/perry32 -ldl -lpthread'
echo "$root/.build/i386/bin/perry32"
