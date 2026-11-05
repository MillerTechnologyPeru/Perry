#!/bin/sh
# Builds libPerrySystem.so for armv7, the provider for libSystem, into
# .build/armv7/bin beside perry32, which finds providers there. Only the
# files that have been brought to Darwin's armv7 ABI are built.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
llvm=$(ls -d "$root"/.toolchains/LLVM-*/bin | head -1)
sdk=${PERRY_ARMV7_SDK:-$(ls -d "$root"/.toolchains/swift-*-armv7-sdk/*/debian-* | head -1)}
out=$root/.build/armv7
mkdir -p "$out/bin" "$out/obj"

cflags="--target=armv7-linux-gnueabihf --sysroot=$sdk -march=armv7-a -mfloat-abi=hard -fPIC -O1 -g -D_GNU_SOURCE -D_FILE_OFFSET_BITS=64
  -I$root/Sources/PerrySystem/include -I$root/Sources/PerryInterface/include"

objects=""
for name in thunks_arm.S stdio.c vaformat.c runtime.c errno.c system.c files.c blocks.c malloc.c ctype.c; do
    object=$out/obj/system-$name.o
    # shellcheck disable=SC2086
    "$llvm/clang" $cflags -c "$root/Sources/PerrySystem/$name" -o "$object"
    objects="$objects $object"
done
# shellcheck disable=SC2086
"$llvm/clang" --target=armv7-linux-gnueabihf --sysroot="$sdk" -fuse-ld=lld -shared $objects \
    -o "$out/bin/libPerrySystem.so" -lm
echo "$out/bin/libPerrySystem.so"
