#!/bin/sh
# Builds and tests Perry in an arm64 Linux container.
# Usage: Scripts/docker-test.sh [swift test arguments...]
# Linux build products go to .build/linux so they never mix with a macOS
# build; fixtures stay in .build/perry-fixtures, shared with the Mac.
set -eu
cd "$(dirname "$0")/.."
image=perry-dev
docker build --platform linux/arm64 -t "$image" .
# Docker Desktop on Apple silicon runs armv7 programs with qemu-arm, which
# finds Linux's armhf libraries in the armv7 SDK, when it is installed.
sdk=$(ls -d .toolchains/swift-*-armv7-sdk/*/debian-* 2>/dev/null | head -1)
# WebKit's web processes run without their bubblewrap sandbox, which can't
# make namespaces in a container; the tests' pages are their own.
exec docker run --rm --platform linux/arm64 \
    -e WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1 \
    -v "$PWD:/perry" \
    ${sdk:+-e QEMU_LD_PREFIX=/perry/$sdk} \
    "$image" \
    sh -c 'swift build --scratch-path .build/linux && swift test --scratch-path .build/linux "$@"' sh "$@"
