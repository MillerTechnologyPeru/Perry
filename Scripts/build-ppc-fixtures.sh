#!/bin/sh
# Builds ppc Mac test programs from the C fixtures with Xcode 3.2.6's own ppc
# toolchain, run under Perry: today's clang has no ppc Darwin target, and
# current ld64 has dropped ppc. Xcode's cc1 is an i386 program (perry32 runs
# it), and its as and ld are x86_64 ones (perry runs them). They link against
# the 10.6 SDK's ppc stubs and start with crt1.10.5.o (LC_UNIXTHREAD).
#
# XCODE3 names Xcode 3.2.6's Developer directory. PERRY and PERRY32 name the
# host's loaders (default: .build/x86_64-host/debug/perry and
# .build/i386/bin/perry32); perry32's providers need i386's Swift runtime on
# LD_LIBRARY_PATH.
#
# usage: build-ppc-fixtures.sh [fixture.c ...]   (default: hello.c)
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
xcode=${XCODE3:?set XCODE3 to the Developer directory of Xcode 3.2.6}
perry=${PERRY:-$root/.build/x86_64-host/debug/perry}
perry32=${PERRY32:-$root/.build/i386/bin/perry32}
sdk=$xcode/SDKs/MacOSX10.6.sdk
gcc=$xcode/usr/lib/gcc/powerpc-apple-darwin10/4.2.1
out=$root/.build/perry-fixtures/ppc
mkdir -p "$out"
for fixture in ${*:-hello.c}; do
    name=${fixture%.*}
    "$perry32" "$xcode/usr/libexec/gcc/powerpc-apple-darwin10/4.2.1/cc1" -quiet -isysroot "$sdk" \
        -iprefix "$gcc/" -isystem "$gcc/include" -I "$root/Tests/Fixtures/include" -D__DYNAMIC__ \
        -mmacosx-version-min=10.5 -std=gnu99 -O2 -auxbase "$name" "$root/Tests/Fixtures/$fixture" -o "$out/$name.s"
    "$perry" "$xcode/usr/libexec/gcc/darwin/ppc/as" -arch ppc -o "$out/$name.o" "$out/$name.s"
    "$perry" "$xcode/usr/bin/ld" -arch ppc -macosx_version_min 10.5 -syslibroot "$sdk" -o "$out/$name" \
        "$sdk/usr/lib/crt1.10.5.o" "$out/$name.o" -lSystem
    echo "$out/$name"
done
