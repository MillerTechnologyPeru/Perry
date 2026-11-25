#!/bin/sh
# Builds Perry's Combine with Xcode's SDKs: Darwin/Combine, OpenCombine
# made to stand in for Apple's Combine.framework. It is compiled for iOS
# arm64 as the module Combine with library evolution, so apps built
# against Apple's bind to it by the same Swift symbols, and installed as
# Combine.framework/Combine in the directory given, the Swift runtime's
# (PERRY_SWIFT_RUNTIME), where the loader finds frameworks with Swift code.
#
# Usage: Scripts/build-combine.sh [output directory]
#   default output: .build/perry-swift-runtime
set -eu
cd "$(dirname "$0")/.."
. Scripts/darwin-toolchain.sh

out=${1:-.build/perry-swift-runtime}
work=.build/perry-combine
# PERRY_OVERLAY_PLATFORM and PERRY_OVERLAY_TARGET name another SDK and
# target, as for Scripts/build-overlay.sh: macosx and x86_64-apple-macos15.0
# for a Mac app on x86_64.
platform=${PERRY_OVERLAY_PLATFORM:-iphoneos}
sdk=$(darwin_sdk "$platform")
target=${PERRY_OVERLAY_TARGET:-arm64-apple-ios15.0}
mkdir -p "$work" "$out/Combine.framework"

darwin_clangxx "$platform" -target "$target" -isysroot "$sdk" -std=c++17 -O2 -Wno-\#warnings \
    -I Darwin/Combine/Helpers/include -c Darwin/Combine/Helpers/COpenCombineHelpers.cpp -o "$work/helpers.o"

darwin_swiftc "$platform" -target "$target" -sdk "$sdk" -module-name Combine -parse-as-library \
    -enable-library-evolution -O -emit-library \
    -emit-module -emit-module-path "$work/Combine.swiftmodule" \
    -I Darwin/Combine/Helpers/include \
    $(find Darwin/Combine/Sources -name '*.swift' | sort) "$work/helpers.o" -lc++ \
    -Xlinker -install_name -Xlinker /System/Library/Frameworks/Combine.framework/Combine -Xlinker -not_for_dyld_shared_cache \
    -o "$out/Combine.framework/Combine"
echo "$out/Combine.framework/Combine"
