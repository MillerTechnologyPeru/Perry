#!/bin/sh
# Builds Perry's MarketplaceKit on a Mac with Xcode: Darwin/MarketplaceKit,
# the part of Apple's MarketplaceKit.framework that apps' libraries ask
# where the app was installed from (AppDistributor). It is compiled for iOS
# arm64 as the module MarketplaceKit with library evolution, so apps built
# against Apple's bind to it by the same Swift symbols, and installed as
# MarketplaceKit.framework/MarketplaceKit in the directory given, the Swift
# runtime's (PERRY_SWIFT_RUNTIME), where the loader finds frameworks with
# Swift code.
#
# Usage: Scripts/build-marketplacekit.sh [output directory]
#   default output: .build/perry-swift-runtime
set -eu
cd "$(dirname "$0")/.."
[ "$(uname)" = Darwin ] || { echo "needs macOS with Xcode" >&2; exit 1; }

out=${1:-.build/perry-swift-runtime}
work=.build/perry-marketplacekit
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
target=arm64-apple-ios15.0
mkdir -p "$work" "$out/MarketplaceKit.framework"

xcrun --sdk iphoneos swiftc -target "$target" -sdk "$sdk" -module-name MarketplaceKit -parse-as-library \
    -enable-library-evolution -O -emit-library \
    -emit-module -emit-module-path "$work/MarketplaceKit.swiftmodule" \
    $(find Darwin/MarketplaceKit/Sources -name '*.swift' | sort) \
    -Xlinker -install_name -Xlinker /System/Library/Frameworks/MarketplaceKit.framework/MarketplaceKit \
    -Xlinker -not_for_dyld_shared_cache \
    -o "$out/MarketplaceKit.framework/MarketplaceKit"
echo "$out/MarketplaceKit.framework/MarketplaceKit"
