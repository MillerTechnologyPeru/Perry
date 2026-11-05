#!/bin/sh
# Installs the C libraries Perry's providers build on into the armv7 SDK's
# sysroot: Debian trixie's armhf packages (the SDK's own Debian), which apt in
# a container downloads with their dependencies, unpacked over the sysroot,
# and Perry's libperry-sqlite3 and liblzfse, built for armv7 from the
# sources the Dockerfile pins. The same sysroot is QEMU_LD_PREFIX for armv7
# programs under qemu, so the libraries providers open at run time (SDL3,
# Mesa, OpenAL, GStreamer) are installed too.
# Usage: Scripts/build-armv7-sysroot.sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
sdk=$(cd .toolchains && ls -d swift-*-armv7-sdk/*/debian-* | head -1)
llvm=$(cd .toolchains && ls -d LLVM-*/bin | head -1)

# The Dockerfile's libraries, for armhf.
packages="libxml2-dev zlib1g-dev libbz2-dev libexpat1-dev libssl-dev openssl-provider-legacy liblzma-dev
  liblz4-dev libbrotli-dev libpng-dev libjpeg62-turbo-dev libgif-dev libwebp-dev libheif-dev
  libcairo2-dev libfreetype-dev libfontconfig-dev libopenblas-dev libjavascriptcoregtk-4.1-dev
  libopenal1 libgstreamer1.0-0 libgstreamer-plugins-base1.0-0 gstreamer1.0-plugins-base
  gstreamer1.0-plugins-good gstreamer1.0-libav libsdl3-0 libgl1-mesa-dri libegl1 libgles2 libgles1
  libgl1 libglx-mesa0 libegl-mesa0 libgbm1"

docker run --rm --platform linux/arm64 -v "$root:/perry" -e SDK="/perry/.toolchains/$sdk" \
    -e LLVM="/perry/.toolchains/$llvm" -e PACKAGES="$packages" debian:trixie sh -euc '
    dpkg --add-architecture armhf
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends ca-certificates curl xz-utils >/dev/null
    debs=/tmp/debs
    mkdir -p $debs/partial
    # Downloads the packages and every armhf one they need; the arm64
    # system they are resolved against has none of them.
    apt-get install -y -qq --download-only --no-install-recommends -o Dir::Cache::archives=$debs \
        $(for p in $PACKAGES; do printf "%s:armhf " $p; done) >/dev/null
    for deb in $debs/*.deb; do
        case $(basename $deb) in
        # The SDK has its own C library and compiler runtime.
        libc6_* | libc6-dev_* | libgcc-s1_* | libstdc++6_* | libstdc++-*-dev_* | gcc-*-base_* | \
        linux-libc-dev_* | libcrypt1_* | libcrypt-dev_* | *_arm64.deb) continue ;;
        esac
        dpkg-deb -x $deb $SDK
    done
    # Links to absolute paths would leave the sysroot: point them inside
    # it, relatively, so that it can move.
    find $SDK -type l | while read -r link; do
        target=$(readlink "$link")
        case $target in /*) ln -sfnr "$SDK$target" "$link" ;; esac
    done
    echo "unpacked $(ls $debs/*.deb | wc -l) packages"

    cc="$LLVM/clang --target=armv7-linux-gnueabihf --sysroot=$SDK -march=armv7-a -mfloat-abi=hard -fuse-ld=lld -O2 -fPIC"
    lib=$SDK/usr/lib/arm-linux-gnueabihf

    # SQLite as the iOS SDK has it, as the Dockerfile builds it.
    curl -fsSLo /tmp/sqlite.tar.gz https://www.sqlite.org/2026/sqlite-autoconf-3540000.tar.gz
    echo "134ec0802dda5795816e25d25872d20b312cb3973438c49b30bc40b7705ea9ed  /tmp/sqlite.tar.gz" | sha256sum -c - >/dev/null
    mkdir /tmp/sqlite && tar -xzf /tmp/sqlite.tar.gz -C /tmp/sqlite --strip-components=1
    flags=$(sed -n "/libperry-sqlite3.so -Wl,-soname/,/sqlite3.c/p" /perry/Dockerfile | tr " \\\\" "\n\n" | grep "^-D" | tr "\n" " ")
    echo "sqlite3 with $(echo $flags | wc -w) of the Dockerfile'"'"'s options"
    $cc -shared -o $lib/libperry-sqlite3.so -Wl,-soname,libperry-sqlite3.so $flags /tmp/sqlite/sqlite3.c -lm

    # LZFSE, as the Dockerfile builds it.
    curl -fsSLo /tmp/lzfse.tar.gz https://github.com/lzfse/lzfse/archive/refs/tags/lzfse-1.0.tar.gz
    echo "cf85f373f09e9177c0b21dbfbb427efaedc02d035d2aade65eb58a3cbf9ad267  /tmp/lzfse.tar.gz" | sha256sum -c - >/dev/null
    mkdir /tmp/lzfse && tar -xzf /tmp/lzfse.tar.gz -C /tmp/lzfse --strip-components=1
    for f in lzfse_decode.c lzfse_decode_base.c lzfse_encode.c lzfse_encode_base.c lzfse_fse.c lzvn_decode_base.c lzvn_encode_base.c; do
        $cc -c /tmp/lzfse/src/$f -o /tmp/lzfse/$f.o
    done
    $LLVM/llvm-ar rcs $lib/liblzfse.a /tmp/lzfse/*.o
    cp /tmp/lzfse/src/lzfse.h $SDK/usr/include/
    echo "built libperry-sqlite3 and liblzfse"
'
