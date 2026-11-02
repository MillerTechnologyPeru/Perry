#!/bin/sh
# Builds the Objective-C fixtures in Tests/Fixtures/Darwin on a Mac with
# Xcode and the real iPhoneOS SDK. Output goes to .build/perry-fixtures/darwin,
# which the Linux tests (Scripts/docker-test.sh) pick up when present.
#
# Each fixture is also built as a macOS app and run here; its stdout, from
# real Foundation, is saved as <name>.expected for the tests to compare
# against. Fixtures that import UIKit are built for Mac Catalyst instead,
# which runs the iOS UIKit. Files in a fixture's directory other than
# sources and Info.plist are the app's resources.
set -eu
cd "$(dirname "$0")/.."
[ "$(uname)" = Darwin ] || { echo "needs macOS with Xcode" >&2; exit 1; }

sdk=$(xcrun --sdk iphoneos --show-sdk-path)
macsdk=$(xcrun --sdk macosx --show-sdk-path)
out=.build/perry-fixtures/darwin
min=15.0

for src in Tests/Fixtures/Darwin/*/; do
    name=$(basename "$src")
    app="$out/$name.app"
    rm -rf "$app"
    mkdir -p "$app"
    if grep -q '<UIKit/' "$src"/*.m; then frameworks="-framework Foundation -framework UIKit"; else frameworks="-framework Foundation"; fi
    xcrun --sdk iphoneos clang -target "arm64-apple-ios$min" -isysroot "$sdk" \
        -fobjc-arc -fmodules -O1 \
        $frameworks \
        -o "$app/$name" "$src"/*.m
    plutil -convert binary1 -o "$app/Info.plist" "$src/Info.plist"

    # The same app for macOS, whose bundle keeps everything under Contents.
    macos="$out/macos/$name.app/Contents"
    rm -rf "$out/macos/$name.app"
    mkdir -p "$macos/MacOS" "$macos/Resources"
    case "$frameworks" in
        *UIKit*)
            xcrun --sdk macosx clang -target "arm64-apple-ios$min-macabi" -isysroot "$macsdk" \
                -iframework "$macsdk/System/iOSSupport/System/Library/Frameworks" \
                -L"$macsdk/System/iOSSupport/usr/lib" \
                -fobjc-arc -fmodules -O1 \
                $frameworks \
                -o "$macos/MacOS/$name" "$src"/*.m ;;
        *)
            xcrun --sdk macosx clang -target arm64-apple-macos13 \
                -fobjc-arc -fmodules -O1 \
                $frameworks \
                -o "$macos/MacOS/$name" "$src"/*.m ;;
    esac
    cp "$src/Info.plist" "$macos/Info.plist"

    for resource in "$src"/*; do
        case "$resource" in
            *.m|*/Info.plist) ;;
            *) cp "$resource" "$app/"; cp "$resource" "$macos/Resources/" ;;
        esac
    done

    # A hung reference run fails the build instead of stalling it.
    perl -e 'alarm 30; exec @ARGV' "$macos/MacOS/$name" > "$out/$name.expected" 2>/dev/null
    echo "$app"
done
