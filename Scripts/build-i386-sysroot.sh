#!/bin/sh
# Installs the C libraries Perry's providers build on into the i386 SDK's
# sysroot: Debian trixie's i386 packages, and Perry's libperry-sqlite3,
# liblzfse and libperry-cmark-gfm, built from the sources the Dockerfile pins,
# natively in a 32-bit container. Run after Scripts/build-i386-sdk.sh.
# Usage: Scripts/build-i386-sysroot.sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
sysroot=$root/.toolchains/i386-sdk/sysroot
[ -d "$sysroot/usr/lib/swift" ] || { echo "build the SDK first: Scripts/build-i386-sdk.sh" >&2; exit 1; }

docker run --rm --platform linux/386 -e OWNER="$(id -u):$(id -g)" -v "$root:/perry:ro" -v "$sysroot:/out" debian:trixie sh -euc '
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends ca-certificates curl xz-utils gcc g++ make cmake ninja-build \
        libxml2-dev zlib1g-dev libbz2-dev libexpat1-dev libssl-dev openssl-provider-legacy liblzma-dev \
        liblz4-dev libbrotli-dev libpng-dev libjpeg62-turbo-dev libgif-dev libwebp-dev libheif-dev \
        libcairo2-dev libfreetype-dev libfontconfig-dev libopenblas-dev libjavascriptcoregtk-4.1-dev \
        libopenal1 libgstreamer1.0-0 libgstreamer-plugins-base1.0-0 gstreamer1.0-plugins-base \
        gstreamer1.0-plugins-good gstreamer1.0-libav libsdl3-0 libsdl3-dev libgl1-mesa-dri libegl1 libgles2 libgles1 \
        libgl1 libglx-mesa0 libegl-mesa0 libgbm1 >/dev/null 2>&1
    lib=/usr/lib/i386-linux-gnu

    # SQLite as the Dockerfile builds it.
    curl -fsSLo /tmp/sqlite.tar.gz https://www.sqlite.org/2026/sqlite-autoconf-3540000.tar.gz
    echo "134ec0802dda5795816e25d25872d20b312cb3973438c49b30bc40b7705ea9ed  /tmp/sqlite.tar.gz" | sha256sum -c - >/dev/null
    mkdir /tmp/sqlite && tar -xzf /tmp/sqlite.tar.gz -C /tmp/sqlite --strip-components=1
    flags=$(sed -n "/libperry-sqlite3.so -Wl,-soname/,/sqlite3.c/p" /perry/Dockerfile | tr " \\\\" "\n\n" | grep "^-D" | tr "\n" " ")
    gcc -O2 -fPIC -shared -o $lib/libperry-sqlite3.so -Wl,-soname,libperry-sqlite3.so $flags /tmp/sqlite/sqlite3.c -lm

    # LZFSE, as the Dockerfile builds it.
    curl -fsSLo /tmp/lzfse.tar.gz https://github.com/lzfse/lzfse/archive/refs/tags/lzfse-1.0.tar.gz
    echo "cf85f373f09e9177c0b21dbfbb427efaedc02d035d2aade65eb58a3cbf9ad267  /tmp/lzfse.tar.gz" | sha256sum -c - >/dev/null
    mkdir /tmp/lzfse && tar -xzf /tmp/lzfse.tar.gz -C /tmp/lzfse --strip-components=1
    for f in lzfse_decode lzfse_decode_base lzfse_encode lzfse_encode_base lzfse_fse lzvn_decode_base lzvn_encode_base; do
        gcc -O2 -fPIC -c /tmp/lzfse/src/$f.c -o /tmp/lzfse/$f.o
    done
    ar rcs $lib/liblzfse.a /tmp/lzfse/*.o
    cp /tmp/lzfse/src/lzfse.h /usr/include/

    # swift-cmark, as the Dockerfile builds it.
    curl -fsSLo /tmp/cmark.tar.gz https://github.com/swiftlang/swift-cmark/archive/437611671145d47e6d9679761b8a5987766f4ae5.tar.gz
    echo "bcc825cecd1710cdca28f7cc0a74423a691966be2f3a4c6fa8739a2009ed5bf2  /tmp/cmark.tar.gz" | sha256sum -c - >/dev/null
    mkdir /tmp/cmark && tar -xzf /tmp/cmark.tar.gz -C /tmp/cmark --strip-components=1
    cmake -G Ninja -S /tmp/cmark -B /tmp/cmark-build -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_TESTING=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON >/dev/null
    ninja -C /tmp/cmark-build libcmark-gfm libcmark-gfm-extensions >/dev/null
    cp /tmp/cmark-build/src/libcmark-gfm.a $lib/libperry-cmark-gfm.a
    cp /tmp/cmark-build/extensions/libcmark-gfm-extensions.a $lib/libperry-cmark-gfm-extensions.a
    mkdir -p /usr/include/perry-cmark-gfm
    cp /tmp/cmark/src/include/*.h /tmp/cmark/extensions/include/*.h /tmp/cmark-build/src/*.h /tmp/cmark-build/extensions/*.h /usr/include/perry-cmark-gfm/ 2>/dev/null || true

    # Over the sysroot, keeping the Swift libraries already there.
    tar -C / -cf - usr/include usr/lib lib usr/share/pkgconfig 2>/dev/null | tar -C /out -xf -
    find /out -type l | while read -r link; do
        target=$(readlink "$link")
        case $target in /*) ln -sfnr "/out$target" "$link" ;; esac
    done
    # update-alternatives links OpenBLAS into the library directory through
    # /etc/alternatives, which is not copied: link it directly.
    for name in libopenblas.so libopenblas.so.0 libopenblas.a libblas.so libblas.so.3 libblas.a liblapack.so liblapack.so.3 liblapack.a; do
        [ -e /out$lib/openblas-pthread/$name ] && ln -sfn openblas-pthread/$name /out$lib/$name
    done
    chown -R "$OWNER" /out
    echo done'
