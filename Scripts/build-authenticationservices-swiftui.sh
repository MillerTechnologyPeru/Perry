#!/bin/sh
# Builds Perry's _AuthenticationServices_SwiftUI on a Mac with Xcode:
# Darwin/_AuthenticationServices_SwiftUI, the Swift framework
# AuthenticationServices' SwiftUI API is in (AuthenticationServices'
# cross-import overlay with SwiftUI). It is compiled for iOS arm64 as the module
# _AuthenticationServices_SwiftUI with library evolution, against Perry's SwiftUI (the
# OpenSwiftUI module, whose ABI name is SwiftUI, which build-swiftui.sh
# builds first), so apps built against Apple's bind to it by the same Swift
# symbols, and installed as _AuthenticationServices_SwiftUI.framework/_AuthenticationServices_SwiftUI in the
# directory given, the Swift runtime's (PERRY_SWIFT_RUNTIME).
#
# It shares OpenSwiftUI's package name, as _MapKit_SwiftUI's build does,
# and builds over the same copy of the SDK's UIKit interface SwiftUI does.
#
# Usage: Scripts/build-authenticationservices-swiftui.sh [output directory]
#   default output: .build/perry-swift-runtime
set -eu
cd "$(dirname "$0")/.."
[ "$(uname)" = Darwin ] || { echo "needs macOS with Xcode" >&2; exit 1; }

root=$PWD
out=${1:-.build/perry-swift-runtime}
case $out in /*) ;; *) out=$root/$out ;; esac
work=$root/.build/perry-swiftui
products=$work/spm/out/Products/Release-iphoneos
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
target=arm64-apple-ios18.0
packages=$root/Darwin/SwiftUI
[ -e "$products/OpenSwiftUI.swiftmodule" ] && [ -e "$out/SwiftUI.framework/SwiftUI" ] || {
    echo "build Perry's SwiftUI first: CONFIGURATION=release Scripts/build-swiftui.sh" >&2
    exit 1
}
mkdir -p "$out/_AuthenticationServices_SwiftUI.framework"

# The C modules OpenSwiftUI's Swift modules import.
set --
for module in OpenRenderBox/Sources/OpenRenderBoxShimsCxx/include/OpenRenderBox \
    OpenRenderBox/Sources/OpenRenderBoxCxx/include Compute/Sources/ComputeCxx/include \
    Compute/Sources/Utilities/include Compute/Sources/Platform/include \
    OpenSwiftUI/Sources/COpenSwiftUI OpenSwiftUI/Sources/OpenSwiftUI_SPI; do
    set -- "$@" -Xcc "-fmodule-map-file=$packages/$module/module.modulemap" -Xcc "-I$packages/$module"
done

xcrun --sdk iphoneos swiftc -target "$target" -sdk "$sdk" -module-name _AuthenticationServices_SwiftUI -parse-as-library \
    -enable-library-evolution -swift-version 5 -O -suppress-warnings -package-name openswiftui \
    -I "$work/sdk" -I "$products" "$@" -Xcc -DOPENSWIFTUI_LINK_COREUI=0 \
    -emit-library $(find Darwin/_AuthenticationServices_SwiftUI/Sources -name '*.swift' | sort) \
    "$out/SwiftUI.framework/SwiftUI" -framework UIKit -framework AuthenticationServices \
    -Xlinker -install_name -Xlinker /System/Library/Frameworks/_AuthenticationServices_SwiftUI.framework/_AuthenticationServices_SwiftUI \
    -Xlinker -not_for_dyld_shared_cache \
    -o "$out/_AuthenticationServices_SwiftUI.framework/_AuthenticationServices_SwiftUI"
echo "$out/_AuthenticationServices_SwiftUI.framework/_AuthenticationServices_SwiftUI"
