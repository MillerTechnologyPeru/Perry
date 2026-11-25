#!/bin/sh
# Downloads the Swift SDK for armv7 Debian trixie from
# swift-embedded-linux/armhf-debian into
# .toolchains/swift-VERSION-RELEASE-debian-trixie-armv7-sdk, where the armv7
# scripts (Scripts/build-armv7-*.sh) and Scripts/docker-test.sh find it.
# Swift's modules only load in the compiler that built them, so the SDK's
# version must be the host compiler's exactly: by default the perry-dev
# image's (PERRY_IMAGE), whose swift then builds for armv7 with
# PERRY_SWIFT=/usr/bin. Each release is checked against its SHA-256 below.
#
# Does nothing when that SDK is already there, so a CI cache keyed by this
# file and the version restores it. 230 MB to download, 800 MB unpacked.
# Usage: Scripts/setup-armv7-sdk.sh [version, such as 6.4.3]
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
version=${1:-$(docker run --rm --entrypoint swift "${PERRY_IMAGE:-perry-dev}" --version 2>/dev/null |
    sed -n 's/^Swift version \([0-9.]*\).*/\1/p')}
case $version in
6.4.0) sha256=0775b5a63c6cef53e40c5a5424e710f870052ae64290214afacb92f37f027fce ;;
6.4.1) sha256=024888032bf28e9c94b23dda48e36950462e84944eb4daaee02bb102b73d9ff2 ;;
6.4.2) sha256=255d42022e0c1aab96887d75ddf66c611f6c6e70c8ac297fa74d2fe053de9ebe ;;
6.4.3) sha256=243184bf809a3a17d36b9b411e353e8ad07585cdbff1129dd1bb969882352a0f ;;
*) echo "$0: no armv7 SDK is pinned for Swift '$version'; add its release's SHA-256" >&2; exit 1 ;;
esac
name=swift-$version-RELEASE-debian-trixie-armv7
out=$root/.toolchains/$name-sdk
if [ ! -d "$out/$name/debian-trixie/usr/lib/swift/linux" ]; then
    rm -rf "$out"
    mkdir -p "$out"
    curl -fsSLo "$out/sdk.tar.gz" \
        "https://github.com/swift-embedded-linux/armhf-debian/releases/download/$version/$name-sdk.tar.gz"
    echo "$sha256  $out/sdk.tar.gz" | sha256sum -c - >/dev/null
    tar -xzf "$out/sdk.tar.gz" -C "$out"
    rm "$out/sdk.tar.gz"
fi
echo "$out/$name/debian-trixie"
