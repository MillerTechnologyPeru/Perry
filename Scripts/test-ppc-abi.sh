#!/bin/sh
# Checks the loader's moves between Darwin's ppc ABI and Linux's
# (ppc_abi.c) against code Apple's own compiler made: Xcode 3.2.6's ppc cc1,
# run under perry32, compiles Tests/Fixtures/ppc_abi_darwin.c, whose calls
# and functions take floats, doubles, long longs and structures; its
# assembly is made ELF (darwin-ppc-asm-to-elf.py) and linked with
# ppc_abi_linux.c, the Linux side, which has the C signatures the Swift
# providers give those types, and the loader's sources. It runs under
# qemu-ppc, and every line names what it got and what it wants.
#
# XCODE3, PERRY32 and LD_LIBRARY_PATH as for build-ppc-fixtures.sh; PPC_CC
# as for build-ppc-loader.sh; PPC_SYSROOT the target's libraries for
# qemu-ppc.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
xcode=${XCODE3:?set XCODE3 to the Developer directory of Xcode 3.2.6}
perry32=${PERRY32:-$root/.build/i386/bin/perry32}
cc=${PPC_CC:?set PPC_CC to a powerpc-linux-gnu cross compiler}
sysroot=${PPC_SYSROOT:?set PPC_SYSROOT to the ppc target libraries}
as=$(dirname "$cc")/$(basename "$cc" | sed 's/gcc$/as/')
out=$root/.build/ppc/abi-test
mkdir -p "$out"
"$perry32" "$xcode/usr/libexec/gcc/powerpc-apple-darwin10/4.2.1/cc1" -quiet -isysroot "$xcode/SDKs/MacOSX10.6.sdk" \
    -mmacosx-version-min=10.5 -mdynamic-no-pic -O1 -auxbase ppc_abi_darwin \
    "$root/Tests/Fixtures/ppc_abi_darwin.c" -o "$out/darwin.s"
python3 -I "$root/Scripts/darwin-ppc-asm-to-elf.py" "$out/darwin.s" "$out/darwin_elf.s"
"$as" -mregnames -mppc -many "$out/darwin_elf.s" -o "$out/darwin.o"
core=$root/Sources/PerryLoaderCore
"$cc" -mcpu=7400 -O1 -g -Wall -Wno-unused-function -I"$core/include" -I"$root/Sources/PerryInterface/include" \
    "$root/Tests/Fixtures/ppc_abi_linux.c" "$out/darwin.o" "$core/ppc_abi.c" "$core/ppc_abi.S" \
    "$core/ppc_thread.c" "$core/log.c" -rdynamic -o "$out/ppc_abi" -ldl -lpthread
qemu-ppc-static -cpu 7400 -L "$sysroot" "$out/ppc_abi"
