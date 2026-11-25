#!/bin/sh
# Builds libPerryCarbon.so for 32-bit PowerPC Linux, the provider for
# Carbon.framework (and CoreServices' Gestalt and the like), into .build/ppc/bin
# beside perry.
#
# PPC_CC names a cross compiler for powerpc-linux-gnu with its sysroot, as for
# build-ppc-loader.sh. Linux's ppc returns every structure through memory, as
# Darwin's does, so unlike i386 nothing needs -freg-struct-return. Functions
# that take a structure by value (a Point, a Rect) do not match yet: Darwin
# passes one in its words and Linux through a pointer (Documentation/
# powerpc.md); those that take words and pointers, most of them, do.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
cc=${PPC_CC:?set PPC_CC to a powerpc-linux-gnu cross compiler}
out=$root/.build/ppc
mkdir -p "$out/bin" "$out/obj"
cd "$root"
cflags="-mcpu=7400 -fPIC -O1 -g -D_GNU_SOURCE -Wall -Wno-unused-function -ISources/CPerryCarbon/include -ISources/PerryInterface/include"
objects=""
for source in Sources/CPerryCarbon/*.c; do
    object=$out/obj/carbon-$(basename "$source").o
    "$cc" $cflags -c "$source" -o "$object" || failed=1
    objects="$objects $object"
done
[ -z "${failed:-}" ]
"$cc" -shared $objects -o "$out/bin/libPerryCarbon.so" -lm -lpthread -Wl,-z,defs
echo "$out/bin/libPerryCarbon.so"
