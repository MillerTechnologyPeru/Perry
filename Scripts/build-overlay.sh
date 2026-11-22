#!/bin/bash
# Builds a Swift overlay of Perry's on a Mac with Xcode: Darwin/<Module>/Sources
# compiled as the Swift module <Module> over the SDK's Objective-C or C
# headers of the same name, as Apple builds its overlays, for iOS arm64 with
# library evolution, and linked as libswift<Module>.dylib in the directory
# given: the Swift runtime's (PERRY_SWIFT_RUNTIME), where the loader looks
# up a framework's Swift symbols.
#
# An overlay of additions (Darwin/<Name>/module-name names the module it
# adds to, say UIKit for Darwin/UIKitAdditions) is Swift API newer than
# that module's overlay: it is compiled as that module, for its symbols,
# and linked as libswift<Name>.dylib, which the loader looks in after the
# module's overlay.
#
# Usage: [PERRY_OVERLAY_PLATFORM=macosx] [PERRY_OVERLAY_TARGET=<triple>] Scripts/build-overlay.sh <Module> [output directory]
#   default output: .build/perry-swift-runtime
set -eu
cd "$(dirname "$0")/.."
[ "$(uname)" = Darwin ] || { echo "needs macOS with Xcode" >&2; exit 1; }
[ $# -ge 1 ] || { echo "usage: $0 <Module> [output directory]" >&2; exit 1; }

module=$1
out=${2:-.build/perry-swift-runtime}
work=.build/perry-overlays/$module
swift_module=$module
[ -f "Darwin/$module/module-name" ] && swift_module=$(tr -d '[:space:]' < "Darwin/$module/module-name")
# A macOS overlay (Darwin/<Module>/platform says macosx) is built over the
# macOS SDK, for Mac apps; PERRY_OVERLAY_PLATFORM=macosx builds any other
# for them too (CryptoKit for a Mac app's runtime directory).
platform=iphoneos
[ -f "Darwin/$module/platform" ] && platform=$(tr -d '[:space:]' < "Darwin/$module/platform")
platform=${PERRY_OVERLAY_PLATFORM:-$platform}
sdk=$(xcrun --sdk "$platform" --show-sdk-path)
target=arm64-apple-ios18.0
[ "$platform" = macosx ] && target=arm64-apple-macos15.0
# PERRY_OVERLAY_TARGET names another: x86_64-apple-macos15.0 for a Mac app
# on x86_64, x86_64-apple-ios18.0-macabi for a Mac Catalyst one.
target=${PERRY_OVERLAY_TARGET:-$target}
mkdir -p "$work" "$out"

# Declarations the SDK's public headers lack, in Darwin/<Module>/include.
includes=()
[ -d "Darwin/$module/include" ] && includes=(-I "Darwin/$module/include")

# Compiler flags of the module's own, one per line, in Darwin/<Module>/swiftc-flags.
flags=()
if [ -f "Darwin/$module/swiftc-flags" ]; then
    while IFS= read -r flag; do [ -n "$flag" ] && flags+=("$flag"); done < "Darwin/$module/swiftc-flags"
fi

# Mac Catalyst's frameworks and Swift modules are under the macOS SDK's
# System/iOSSupport, where its libraries are installed too.
install=/usr/lib/swift
case $target in *-macabi)
    install=/System/iOSSupport/usr/lib/swift
    support=$sdk/System/iOSSupport
    flags+=(-Fsystem "$support/System/Library/Frameworks" -I "$support/usr/lib/swift" -L "$support/usr/lib/swift"
            -Xcc -isystem -Xcc "$support/usr/include" -Xcc -iframework -Xcc "$support/System/Library/Frameworks") ;;
esac

# A module of libSystem's headers (os) has no framework to link.
framework=()
for dir in "$sdk/System/Library/Frameworks" "$sdk/System/iOSSupport/System/Library/Frameworks"; do
    [ -d "$dir/$swift_module.framework" ] && framework=(-framework "$swift_module")
done

sources=()
while IFS= read -r file; do sources+=("$file"); done < <(find "Darwin/$module/Sources" -name '*.swift' | sort)

xcrun --sdk "$platform" swiftc -target "$target" -sdk "$sdk" \
    -module-name "$swift_module" -parse-as-library -import-underlying-module \
    -enable-library-evolution -swift-version 5 -O -wmo \
    -emit-library -emit-module -emit-module-path "$work/$swift_module.swiftmodule" \
    ${includes[@]+"${includes[@]}"} ${flags[@]+"${flags[@]}"} "${sources[@]}" ${framework[@]+"${framework[@]}"} \
    -Xlinker -install_name -Xlinker "$install/libswift$module.dylib" \
    -o "$out/libswift$module.dylib"
echo "$out/libswift$module.dylib"
