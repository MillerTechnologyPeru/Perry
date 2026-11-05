#!/bin/sh
# Builds Perry's Accessibility on a Mac with Xcode: Darwin/Accessibility,
# the Swift part of Apple's Accessibility.framework that attributed text
# needs (its attribute scope, which SwiftUI's holds). It is compiled for iOS
# arm64 as the module Accessibility with library evolution, so apps and
# SwiftUI built against Apple's bind to it by the same Swift symbols, and
# installed as Accessibility.framework/Accessibility in the directory given,
# the Swift runtime's (PERRY_SWIFT_RUNTIME), where the loader finds
# frameworks with Swift code.
#
# Usage: Scripts/build-accessibility.sh [output directory]
#   default output: .build/perry-swift-runtime
set -eu
cd "$(dirname "$0")/.."
[ "$(uname)" = Darwin ] || { echo "needs macOS with Xcode" >&2; exit 1; }

out=${1:-.build/perry-swift-runtime}
work=.build/perry-accessibility
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
target=arm64-apple-ios15.0
mkdir -p "$work" "$out/Accessibility.framework"

xcrun --sdk iphoneos swiftc -target "$target" -sdk "$sdk" -module-name Accessibility -parse-as-library \
    -enable-library-evolution -O -emit-library \
    -emit-module -emit-module-path "$work/Accessibility.swiftmodule" \
    $(find Darwin/Accessibility/Sources -name '*.swift' | sort) \
    -Xlinker -install_name -Xlinker /System/Library/Frameworks/Accessibility.framework/Accessibility \
    -Xlinker -not_for_dyld_shared_cache \
    -o "$out/Accessibility.framework/Accessibility"
echo "$out/Accessibility.framework/Accessibility"
