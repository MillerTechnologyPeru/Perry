#!/bin/sh
# Builds one of Perry's Swift frameworks on a Mac with Xcode: Darwin/<Module>,
# the Swift code of an Apple framework that has no Objective-C part Perry's
# providers stand in for (Accessibility's attribute scope,
# DeveloperToolsSupport's resources). It is compiled for iOS arm64 as the
# module <Module> with library evolution, so apps and SwiftUI built against
# Apple's bind to it by the same Swift symbols, and installed as
# <Module>.framework/<Module> in the directory given, the Swift runtime's
# (PERRY_SWIFT_RUNTIME), where the loader finds frameworks with Swift code.
# Its module interfaces go to .build/perry-frameworks, for Perry's other
# Swift frameworks to build against in place of the SDK's.
#
# Usage: Scripts/build-framework.sh <Module> [output directory]
#   default output: .build/perry-swift-runtime
#   TARGET overrides the deployment target (default arm64-apple-ios18.0).
set -eu
cd "$(dirname "$0")/.."
[ "$(uname)" = Darwin ] || { echo "needs macOS with Xcode" >&2; exit 1; }
[ $# -ge 1 ] || { echo "usage: $0 <Module> [output directory]" >&2; exit 1; }

module=$1
out=${2:-.build/perry-swift-runtime}
modules=.build/perry-frameworks/$module.swiftmodule
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
target=${TARGET:-arm64-apple-ios18.0}
mkdir -p "$modules" "$out/$module.framework"

xcrun --sdk iphoneos swiftc -target "$target" -sdk "$sdk" -module-name "$module" -parse-as-library \
    -enable-library-evolution -language-mode 5 -O -emit-library \
    -emit-module-interface-path "$modules/arm64-apple-ios.swiftinterface" \
    -emit-private-module-interface-path "$modules/arm64-apple-ios.private.swiftinterface" \
    $(find "Darwin/$module/Sources" -name '*.swift' | sort) \
    -Xlinker -install_name -Xlinker "/System/Library/Frameworks/$module.framework/$module" \
    -Xlinker -not_for_dyld_shared_cache \
    -o "$out/$module.framework/$module"
echo "$out/$module.framework/$module"
