#!/bin/bash
# Builds Perry's System with Xcode's SDKs (on a Mac, or in perry-dev under
# Scripts/docker-darwin.sh): apple/swift-system at a pinned release,
# compiled as the module System, as Apple builds libswiftSystem from the
# same sources, rather than as the package's SystemPackage. It is built
# with library evolution, the availability Apple's build gives each release
# (the package's own table, as SYSTEM_ABI_STABLE has it), and the Swift 6
# language mode, with Darwin/System/Sources added: the entry points Apple's
# library exports that the sources now declare differently. CSystem's C
# shims are linked in. IORing, Linux's, is left out.
#
# swift-system is Apache 2.0 licensed, so it is fetched, not copied here.
#
# Usage: [PERRY_OVERLAY_PLATFORM=macosx] [PERRY_OVERLAY_TARGET=<triple>] Scripts/build-system.sh [output directory]
#   default output: .build/perry-swift-runtime
set -eu
cd "$(dirname "$0")/.."
. Scripts/darwin-toolchain.sh

out=${1:-.build/perry-swift-runtime}
work=.build/perry-system
platform=${PERRY_OVERLAY_PLATFORM:-iphoneos}
sdk=$(darwin_sdk "$platform")
target=${PERRY_OVERLAY_TARGET:-arm64-apple-ios18.0}
mkdir -p "$work" "$out"

# swift-system 1.8.1.
commit=869129b7bf4ecc57b97d0193ad29690ca2134750
source=$work/swift-system
if [ ! -e "$source/.perry-commit" ] || [ "$(cat "$source/.perry-commit")" != "$commit" ]; then
    rm -rf "$source"; mkdir -p "$source"
    git -C "$source" init -q
    git -C "$source" fetch -q --depth 1 https://github.com/apple/swift-system.git "$commit"
    git -C "$source" checkout -q FETCH_HEAD
    echo "$commit" > "$source/.perry-commit"
fi

# Each release's availability, from the manifest's table.
availability=()
while IFS='"' read -r _ version _ platforms _; do
    availability+=(-enable-experimental-feature "AvailabilityMacro=System $version:$platforms")
done < <(grep -E '^\s*Available\("' "$source/Package.swift")

install=/usr/lib/swift
catalyst=()
case $target in *-macabi)
    install=/System/iOSSupport/usr/lib/swift
    catalyst=(-Fsystem "$sdk/System/iOSSupport/System/Library/Frameworks") ;;
esac

sources=()
while IFS= read -r file; do sources+=("$file"); done < <(
    { find "$source/Sources/System" -name '*.swift' -not -path '*/IORing/*'; find Darwin/System/Sources -name '*.swift'; } | sort)
darwin_clang "$platform" -target "$target" -isysroot "$sdk" -O2 -fPIC -I "$source/Sources/CSystem/include" \
    -c "$source/Sources/CSystem/shims.c" -o "$work/shims.o"
# The protocol requirements base descriptor of MachPortRight, which has no
# requirements, is its protocol descriptor, as for Intents'.
darwin_swiftc "$platform" -target "$target" -sdk "$sdk" ${catalyst[@]+"${catalyst[@]}"} \
    -module-name System -module-link-name swiftSystem -parse-as-library \
    -enable-library-evolution -swift-version 6 -O -wmo -D SYSTEM_PACKAGE_DARWIN \
    -enable-experimental-feature Lifetimes -enable-upcoming-feature MemberImportVisibility "${availability[@]}" \
    -I "$source/Sources/CSystem/include" \
    -emit-library -emit-module -emit-module-path "$work/System.swiftmodule" \
    "${sources[@]}" "$work/shims.o" \
    -Xlinker -alias -Xlinker '_$s6System13MachPortRightMp' -Xlinker '_$s6System13MachPortRightTL' \
    -Xlinker -install_name -Xlinker "$install/libswiftSystem.dylib" \
    -o "$out/libswiftSystem.dylib"
echo "$out/libswiftSystem.dylib"
