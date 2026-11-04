#!/bin/bash
# Builds a Swift overlay of Perry's on a Mac with Xcode: Darwin/<Module>/Sources
# compiled as the Swift module <Module> over the SDK's Objective-C or C
# headers of the same name, as Apple builds its overlays, for iOS arm64 with
# library evolution, and linked as libswift<Module>.dylib in the directory
# given: the Swift runtime's (PERRY_SWIFT_RUNTIME), where the loader looks
# up a framework's Swift symbols.
#
# Usage: Scripts/build-overlay.sh <Module> [output directory]
#   default output: .build/perry-swift-runtime
set -eu
cd "$(dirname "$0")/.."
[ "$(uname)" = Darwin ] || { echo "needs macOS with Xcode" >&2; exit 1; }
[ $# -ge 1 ] || { echo "usage: $0 <Module> [output directory]" >&2; exit 1; }

module=$1
out=${2:-.build/perry-swift-runtime}
work=.build/perry-overlays/$module
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
target=arm64-apple-ios18.0
mkdir -p "$work" "$out"

# Declarations the SDK's public headers lack, in Darwin/<Module>/include.
includes=()
[ -d "Darwin/$module/include" ] && includes=(-I "Darwin/$module/include")

sources=()
while IFS= read -r file; do sources+=("$file"); done < <(find "Darwin/$module/Sources" -name '*.swift' | sort)

xcrun --sdk iphoneos swiftc -target "$target" -sdk "$sdk" \
    -module-name "$module" -parse-as-library -import-underlying-module \
    -enable-library-evolution -swift-version 5 -O -wmo \
    -emit-library -emit-module -emit-module-path "$work/$module.swiftmodule" \
    "${includes[@]}" "${sources[@]}" -framework "$module" \
    -Xlinker -install_name -Xlinker "/usr/lib/swift/libswift$module.dylib" \
    -o "$out/libswift$module.dylib"
echo "$out/libswift$module.dylib"
