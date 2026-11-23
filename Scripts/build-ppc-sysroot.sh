#!/bin/sh
# Builds the C libraries Perry makes itself, from the sources the Dockerfile
# pins, for 32-bit big-endian PowerPC Linux: libperry-sqlite3, liblzfse and
# libperry-cmark-gfm (swift-cmark). They go into their own prefix,
# .toolchains/ppc-sysroot (or PPC_PREFIX), beside the ppc SDK's sysroot,
# which has the rest (libxml2, cairo and the like): unlike i386's, the ppc
# sysroot is the SDK's (swift-linux's), so nothing here writes into it.
#
# PPC_CC names a cross compiler for powerpc-linux-gnu with its sysroot, as for
# build-ppc-loader.sh; its g++ beside it builds swift-cmark. Builds then pass
#     -Xcc -I$PPC_PREFIX/usr/include -Xlinker -L$PPC_PREFIX/usr/lib
# and libperry-sqlite3.so goes beside the providers, or on LD_LIBRARY_PATH.
#
# Usage: Scripts/build-ppc-sysroot.sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
cc=${PPC_CC:?set PPC_CC to a powerpc-linux-gnu cross compiler}
cxx=$(dirname "$cc")/$(basename "$cc" | sed 's/gcc$/g++/')
ar=$(dirname "$cc")/$(basename "$cc" | sed 's/gcc$/ar/')
prefix=${PPC_PREFIX:-$root/.toolchains/ppc-sysroot}
lib=$prefix/usr/lib
include=$prefix/usr/include
mkdir -p "$lib" "$include"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fetch() {   # url sha256 directory
    curl -fsSLo "$work/archive.tar.gz" "$1"
    echo "$2  $work/archive.tar.gz" | sha256sum -c - >/dev/null
    mkdir -p "$3"
    tar -xzf "$work/archive.tar.gz" -C "$3" --strip-components=1
    rm "$work/archive.tar.gz"
}

# SQLite as the Dockerfile builds it, with its compile options.
fetch https://www.sqlite.org/2026/sqlite-autoconf-3540000.tar.gz \
    134ec0802dda5795816e25d25872d20b312cb3973438c49b30bc40b7705ea9ed "$work/sqlite"
flags=$(sed -n "/libperry-sqlite3.so -Wl,-soname/,/sqlite3.c/p" "$root/Dockerfile" | tr " \\\\" "\n\n" | grep "^-D" | tr "\n" " ")
"$cc" -O2 -fPIC -shared -o "$lib/libperry-sqlite3.so" -Wl,-soname,libperry-sqlite3.so $flags "$work/sqlite/sqlite3.c" -lm

# LZFSE, as the Dockerfile builds it.
fetch https://github.com/lzfse/lzfse/archive/refs/tags/lzfse-1.0.tar.gz \
    cf85f373f09e9177c0b21dbfbb427efaedc02d035d2aade65eb58a3cbf9ad267 "$work/lzfse"
for f in lzfse_decode lzfse_decode_base lzfse_encode lzfse_encode_base lzfse_fse lzvn_decode_base lzvn_encode_base; do
    "$cc" -O2 -fPIC -c "$work/lzfse/src/$f.c" -o "$work/lzfse/$f.o"
done
rm -f "$lib/liblzfse.a"
"$ar" rcs "$lib/liblzfse.a" "$work"/lzfse/*.o
cp "$work/lzfse/src/lzfse.h" "$include/"

# swift-cmark, as the Dockerfile builds it, named libperry-cmark-gfm.
fetch https://github.com/swiftlang/swift-cmark/archive/437611671145d47e6d9679761b8a5987766f4ae5.tar.gz \
    bcc825cecd1710cdca28f7cc0a74423a691966be2f3a4c6fa8739a2009ed5bf2 "$work/cmark"
cmake -G Ninja -S "$work/cmark" -B "$work/cmark-build" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TESTING=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_SYSTEM_NAME=Linux \
    -DCMAKE_SYSTEM_PROCESSOR=powerpc -DCMAKE_C_COMPILER="$cc" -DCMAKE_CXX_COMPILER="$cxx" >/dev/null
ninja -C "$work/cmark-build" libcmark-gfm libcmark-gfm-extensions >/dev/null
cp "$work/cmark-build/src/libcmark-gfm.a" "$lib/libperry-cmark-gfm.a"
cp "$work/cmark-build/extensions/libcmark-gfm-extensions.a" "$lib/libperry-cmark-gfm-extensions.a"
mkdir -p "$include/perry-cmark-gfm"
cp "$work"/cmark/src/include/*.h "$work"/cmark/extensions/include/*.h "$work"/cmark-build/src/*.h \
    "$work"/cmark-build/extensions/*.h "$include/perry-cmark-gfm/" 2>/dev/null || true

echo "$prefix"
