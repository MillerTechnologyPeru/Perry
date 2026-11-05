#!/bin/bash
# Builds Perry's WebKit for Swift on a Mac with Xcode: WebKit's Swift
# overlay (Darwin/WebKit/Sources: WebPage), as libswiftWebKit.dylib, where
# the loader looks up WebKit.framework's Swift symbols, and SwiftUI's
# WebView (Darwin/WebKit/SwiftUI), as _WebKit_SwiftUI.framework, which apps
# that import SwiftUI and WebKit link. Both go in the directory given, the
# Swift runtime's (PERRY_SWIFT_RUNTIME). They are compiled for iOS arm64
# with library evolution against the SDK's interfaces, so apps built
# against Apple's bind to them by the same Swift symbols; the web views
# beneath them are Perry's UIKit's.
#
# Usage: Scripts/build-webkit.sh [output directory]
#   default output: .build/perry-swift-runtime
set -eu
cd "$(dirname "$0")/.."
[ "$(uname)" = Darwin ] || { echo "needs macOS with Xcode" >&2; exit 1; }

out=${1:-.build/perry-swift-runtime}
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
target=arm64-apple-ios18.0

Scripts/build-overlay.sh WebKit "$out"

# Against the overlay just built, whose module is in its work directory.
mkdir -p "$out/_WebKit_SwiftUI.framework"
xcrun --sdk iphoneos swiftc -target "$target" -sdk "$sdk" -module-name _WebKit_SwiftUI -parse-as-library \
    -enable-library-evolution -swift-version 5 -enable-upcoming-feature IsolatedDefaultValues -O -wmo \
    -emit-library -emit-module -emit-module-path .build/perry-overlays/_WebKit_SwiftUI/_WebKit_SwiftUI.swiftmodule \
    -I .build/perry-overlays/WebKit \
    $(find Darwin/WebKit/SwiftUI -name '*.swift' | sort) \
    -framework SwiftUI -framework WebKit -L "$out" -lswiftWebKit \
    -Xlinker -install_name -Xlinker /System/Library/Frameworks/_WebKit_SwiftUI.framework/_WebKit_SwiftUI \
    -Xlinker -not_for_dyld_shared_cache \
    -o "$out/_WebKit_SwiftUI.framework/_WebKit_SwiftUI"
echo "$out/_WebKit_SwiftUI.framework/_WebKit_SwiftUI"
