#!/bin/bash
# Runs one of the scripts that build for Apple's platforms (they source
# Scripts/darwin-toolchain.sh) in perry-dev under Docker on a Mac, with the
# selected Xcode's SDKs, in place of Xcode's own compilers.
#
# Docker Desktop shares no /Applications, so the parts of Xcode's Developer
# directory the build reads are copied once into a volume named for its
# build (perry-xcode-27B52 say), mounted read-only at /Developer: the
# iPhoneOS, iPhoneSimulator and MacOSX SDKs, their platforms'
# Developer/Library (XCTest), and the toolchain's usr/lib/swift and
# usr/lib/clang. In the copy, the SDKs' .tbd stubs lose the arm64e.x1
# targets Xcode 27 lists beside arm64e, which LLVM's ld64.lld rejects
# (each one's arm64e target, which it links arm64 against, stays).
# Clang's module cache is kept in the volume perry-darwin-module-cache.
#
# Usage: Scripts/docker-darwin.sh <command> [arguments...]
#   e.g. Scripts/docker-darwin.sh Scripts/build-overlay.sh Dispatch .build/perry-swift-runtime
#   PERRY_IMAGE: the image (default perry-dev; Scripts/docker-test.sh builds it)
#   DEVELOPER_DIR: the Xcode to copy, as xcrun takes it (default xcode-select -p)
# The command gets the PERRY_* variables set here, CONFIGURATION and
# GitHub Actions' GITHUB_*.
set -eu
cd "$(dirname "$0")/.."
[ $# -ge 1 ] || { echo "usage: $0 <command> [arguments...]" >&2; exit 1; }
[ "$(uname)" = Darwin ] || { echo "runs on a Mac, with Xcode and Docker" >&2; exit 1; }

image=${PERRY_IMAGE:-perry-dev}
developer=${DEVELOPER_DIR:-$(xcode-select -p)}
build=$(/usr/libexec/PlistBuddy -c 'Print :ProductBuildVersion' "$developer/../version.plist")
volume=perry-xcode-$build
case $(uname -m) in
    x86_64) platform=linux/amd64 ;;
    *) platform=linux/arm64 ;;
esac

if ! docker run --rm -v "$volume:/Developer:ro" "$image" test -e /Developer/.perry-complete 2>/dev/null; then
    echo "copying $developer ($build) into the volume $volume"
    docker volume rm -f "$volume" >/dev/null
    toolchain=Toolchains/XcodeDefault.xctoolchain/usr/lib
    parts=()
    for sdk in iPhoneOS iPhoneSimulator MacOSX; do
        [ -d "$developer/Platforms/$sdk.platform" ] || continue
        parts+=("Platforms/$sdk.platform/Developer/SDKs/$sdk.sdk" "Platforms/$sdk.platform/Developer/Library")
    done
    # Only the toolchain's libraries for these platforms.
    COPYFILE_DISABLE=1 tar --no-xattrs -cf - -C "$developer" \
        --exclude "$toolchain/swift/appletv*" --exclude "$toolchain/swift/watch*" --exclude "$toolchain/swift/xr*" \
        --exclude "$toolchain/swift-5.*" --exclude '*.a' \
        "${parts[@]}" "$toolchain/swift" "$toolchain/clang" |
        docker run --rm -i --platform "$platform" -v "$volume:/Developer" "$image" sh -euc '
            tar -xf - -C /Developer --warning=no-unknown-keyword
            python3 -I - /Developer/Platforms <<"EOF"
import os, re, sys
for root, dirs, files in os.walk(sys.argv[1]):
    for name in files:
        path = os.path.join(root, name)
        if not name.endswith(".tbd") or os.path.islink(path):
            continue
        with open(path, encoding="utf-8", errors="surrogateescape") as f:
            text = f.read()
        if "arm64e.x1-" not in text:
            continue
        text = re.sub(r",\s*arm64e\.x1-[a-z]+", "", text)
        text = re.sub(r"arm64e\.x1-[a-z]+\s*,\s*", "", text)
        with open(path, "w", encoding="utf-8", errors="surrogateescape") as f:
            f.write(text)
EOF
            touch /Developer/.perry-complete'
fi

env_args=()
for name in $(compgen -e); do
    case $name in
    PERRY_IMAGE | PERRY_DEVELOPER_DIR | PERRY_MODULE_CACHE | PERRY_LLVM_BIN) ;;
    PERRY_* | GITHUB_* | CONFIGURATION) env_args+=(-e "$name") ;;
    esac
done
exec docker run --rm --platform "$platform" \
    -v "$PWD:/perry" -w /perry \
    -v "$volume:/Developer:ro" \
    -v perry-darwin-module-cache:/module-cache \
    ${env_args[@]+"${env_args[@]}"} \
    "$image" "$@"
