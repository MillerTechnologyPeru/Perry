#!/bin/sh
# Builds Apple's cctools and ld64 from cctools-port, at the commit pinned
# here, into .toolchains/cctools: the linker the i386 and armv7 fixture
# scripts (Scripts/build-i386-fixtures.sh, build-armv7-fixtures.sh,
# build-armv7-libcxx.sh) link Mach-O with, since lld's Mach-O port has
# neither architecture.
#
# Built in the perry-dev image (PERRY_IMAGE), where those scripts run it:
# ld64 needs libdispatch and the blocks runtime, which the image's Swift
# toolchain has in /usr/lib/swift/linux, and runs from there. There is no
# TAPI (system libraries are stub dylibs the fixture scripts make) and no LTO.
# The tools are named for i386-apple-darwin11; they take any architecture
# with -arch, so the arm-apple-darwin11 names are links to the same programs.
#
# Does nothing when .toolchains/cctools already has this commit's build, so
# a CI cache keyed by this file restores it. Takes about 2 minutes on 4
# cores and 20 MB.
# Usage: Scripts/build-cctools.sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
image=${PERRY_IMAGE:-perry-dev}
commit=ef969083aecf77dee1814d6961a06b88af23edef   # cctools 1035.1.102, ld64 957.1
sha256=5b0d18bba0dfd17258040e278b3d5454e8cfc88b97ff251ad8a6fc36cb41dc5d
out=$root/.toolchains/cctools

if [ -x "$out/bin/i386-apple-darwin11-ld" ] && [ "$(cat "$out/commit" 2>/dev/null)" = "$commit" ]; then
    echo "$out: cctools-port $commit"
    exit 0
fi
rm -rf "$out"
mkdir -p "$out"

# As root, for apt; the tree is handed back to the caller's user.
docker run --rm -v "$root:/perry" -e OWNER="$(id -u):$(id -g)" -e COMMIT="$commit" -e SHA256="$sha256" \
    -e DEBIAN_FRONTEND=noninteractive --entrypoint sh "$image" -euc '
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends make uuid-dev libbsd-dev >/dev/null
    work=$(mktemp -d)
    curl -fsSLo $work/cctools.tar.gz https://github.com/tpoechtrager/cctools-port/archive/$COMMIT.tar.gz
    echo "$SHA256  $work/cctools.tar.gz" | sha256sum -c - >/dev/null
    tar -xzf $work/cctools.tar.gz -C $work --strip-components=1
    cd $work/cctools
    # libdispatch and BlocksRuntime, from Swift'"'"'s toolchain, with a runpath
    # there.
    swift=/usr/lib/swift
    CFLAGS="-I$swift -I$swift/Block" CXXFLAGS="-I$swift -I$swift/Block" \
        LDFLAGS="-L$swift/linux -Wl,-rpath,$swift/linux" \
        ./configure --prefix=/perry/.toolchains/cctools --target=i386-apple-darwin11 >$work/configure.log 2>&1 ||
        { tail -40 $work/configure.log; exit 1; }
    make -j"$(nproc)" >$work/make.log 2>&1 || { grep -B2 -A10 "error" $work/make.log | head -80; exit 1; }
    make install >/dev/null
    cd /perry/.toolchains/cctools/bin
    for tool in i386-apple-darwin11-*; do
        ln -sf "$tool" "arm-apple-darwin11-${tool#i386-apple-darwin11-}"
    done
    echo "$COMMIT" > /perry/.toolchains/cctools/commit
    chown -R "$OWNER" /perry/.toolchains/cctools
    rm -rf $work
    ./i386-apple-darwin11-ld -v 2>&1 | head -1'
echo "$out"
