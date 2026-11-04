#!/bin/sh
# Builds perry32, the loader as a 32-bit ARM program, with the LLVM and Swift
# armv7 SDK under .toolchains, into .build/armv7/bin. It runs armv7 iOS
# binaries on a kernel that runs 32-bit ARM programs.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
llvm=$(ls -d "$root"/.toolchains/LLVM-*/bin | head -1)
sdk=${PERRY_ARMV7_SDK:-$(ls -d "$root"/.toolchains/swift-*-armv7-sdk/*/debian-* | head -1)}
out=$root/.build/armv7
mkdir -p "$out/bin" "$out/obj"

cflags="--target=armv7-linux-gnueabihf --sysroot=$sdk -march=armv7-a -mfloat-abi=hard -fPIC -O1 -g -D_GNU_SOURCE
  -I$root/Sources/PerryLoaderCore/include -I$root/Sources/PerryInterface/include"

objects=""
for source in "$root"/Sources/PerryLoaderCore/*.c "$root"/Sources/PerryLoaderCore/*.S "$root"/Sources/PerryInterface/interface.c "$root"/Sources/PerryLoader/main.c; do
    object=$out/obj/loader-$(basename "$source").o
    # shellcheck disable=SC2086
    "$llvm/clang" $cflags -c "$source" -o "$object"
    objects="$objects $object"
done
# shellcheck disable=SC2086
"$llvm/clang" --target=armv7-linux-gnueabihf --sysroot="$sdk" -fuse-ld=lld $objects -o "$out/bin/perry32" -ldl -lpthread
echo "$out/bin/perry32"
