#!/bin/sh
# Builds the Objective-C fixtures in Tests/Fixtures/Darwin on a Mac with
# Xcode and the real iPhoneOS SDK. Output goes to .build/perry-fixtures/darwin,
# which the Linux tests (Scripts/docker-test.sh) pick up when present.
set -eu
cd "$(dirname "$0")/.."
[ "$(uname)" = Darwin ] || { echo "needs macOS with Xcode" >&2; exit 1; }

sdk=$(xcrun --sdk iphoneos --show-sdk-path)
out=.build/perry-fixtures/darwin
min=15.0

for src in Tests/Fixtures/Darwin/*/; do
    name=$(basename "$src")
    app="$out/$name.app"
    rm -rf "$app"
    mkdir -p "$app"
    xcrun --sdk iphoneos clang -target "arm64-apple-ios$min" -isysroot "$sdk" \
        -fobjc-arc -fmodules -O1 \
        -framework Foundation \
        -o "$app/$name" "$src"/*.m
    plutil -convert binary1 -o "$app/Info.plist" "$src/Info.plist"
    echo "$app"
done
