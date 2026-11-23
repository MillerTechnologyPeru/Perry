#!/bin/sh
# Builds perry, the loader, for 32-bit big-endian PowerPC Linux, into
# .build/ppc/bin. It runs ppc Mac binaries on a G4 or later.
#
# PPC_CC names a cross compiler for powerpc-linux-gnu with its sysroot (such as
# swift-linux's powerpc-swift-linux-gnu-gcc). Under qemu-user:
#     qemu-ppc-static -cpu 7400 -L $SYSROOT .build/ppc/bin/perry Program.app
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
cc=${PPC_CC:?set PPC_CC to a powerpc-linux-gnu cross compiler}
out=$root/.build/ppc
mkdir -p "$out/bin" "$out/obj"
cd "$root"
cflags="-mcpu=7400 -fPIC -O1 -g -Wall -Wno-unused-function -Wno-format-truncation -D_FILE_OFFSET_BITS=64 -ISources/PerryLoaderCore/include -ISources/PerryInterface/include"
objects=""
for source in Sources/PerryLoaderCore/*.c Sources/PerryLoaderCore/*.S Sources/PerryInterface/interface.c Sources/PerryLoader/*.c; do
    object=$out/obj/loader-$(basename "$source").o
    $cc $cflags -c "$source" -o "$object"
    objects="$objects $object"
done
# Executables from before Mac OS X 10.5 are not position independent: they
# load at 0x1000 and run from there. So perry is linked at a fixed address far
# above them and the libraries they bring.
$cc -no-pie -Wl,-Ttext-segment=0x70000000 $objects -o "$out/bin/perry" -ldl -lpthread
echo "$out/bin/perry"
