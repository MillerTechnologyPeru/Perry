#!/bin/sh
# Builds one of Perry's Swift frameworks with Xcode's SDKs: Darwin/<Module>,
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
. Scripts/darwin-toolchain.sh
[ $# -ge 1 ] || { echo "usage: $0 <Module> [output directory]" >&2; exit 1; }

module=$1
out=${2:-.build/perry-swift-runtime}
modules=.build/perry-frameworks/$module.swiftmodule
# PERRY_OVERLAY_PLATFORM and PERRY_OVERLAY_TARGET name another SDK and
# target, as for Scripts/build-overlay.sh: macosx and
# x86_64-apple-ios18.0-macabi for a Mac Catalyst app on x86_64. The
# interfaces are named for the target, as the compiler looks them up.
platform=${PERRY_OVERLAY_PLATFORM:-iphoneos}
sdk=$(darwin_sdk "$platform")
target=${PERRY_OVERLAY_TARGET:-${TARGET:-arm64-apple-ios18.0}}
interface=$(echo "$target" | sed -E 's/(ios|macos)[0-9.]+/\1/')
mkdir -p "$modules" "$out/$module.framework"

# Mac Catalyst's frameworks and Swift modules are under the macOS SDK's
# System/iOSSupport.
catalyst= install=
case $target in *-macabi)
    support=$sdk/System/iOSSupport
    install=/System/iOSSupport
    catalyst="-Fsystem $support/System/Library/Frameworks -I $support/usr/lib/swift -L $support/usr/lib/swift" ;;
esac

darwin_swiftc "$platform" -target "$target" -sdk "$sdk" -module-name "$module" -parse-as-library \
    -enable-library-evolution -language-mode 5 -O -emit-library $catalyst \
    -emit-module-interface-path "$modules/$interface.swiftinterface" \
    -emit-private-module-interface-path "$modules/$interface.private.swiftinterface" \
    $(find "Darwin/$module/Sources" -name '*.swift' | sort) \
    -Xlinker -install_name -Xlinker "$install/System/Library/Frameworks/$module.framework/$module" \
    -Xlinker -not_for_dyld_shared_cache \
    -o "$out/$module.framework/$module"
echo "$out/$module.framework/$module"
