#!/bin/sh
# Builds the Objective-C fixtures in Tests/Fixtures/Darwin on a Mac with
# Xcode and the real iPhoneOS SDK. Output goes to .build/perry-fixtures/darwin,
# which the Linux tests (Scripts/docker-test.sh) pick up when present.
#
# Each fixture is also built as a macOS app and run here; its stdout, from
# real Foundation, is saved as <name>.expected for the tests to compare
# against. Fixtures that import UIKit are built for Mac Catalyst instead,
# which runs the iOS UIKit. Files in a fixture's directory other than
# sources, Info.plist and `dependencies` are the app's resources.
#
# A fixture's `dependencies` file lists third-party sources it builds with,
# one per line: a git URL, a commit and the directory of sources in it. They
# are cloned into .build/perry-fixtures/sources rather than kept here.
# Sources that include <libxml/…>, <zlib.h> and the like are linked with
# those libraries.
set -eu
cd "$(dirname "$0")/.."
[ "$(uname)" = Darwin ] || { echo "needs macOS with Xcode" >&2; exit 1; }

sdk=$(xcrun --sdk iphoneos --show-sdk-path)
macsdk=$(xcrun --sdk macosx --show-sdk-path)
out=.build/perry-fixtures/darwin
deps=.build/perry-fixtures/sources
min=15.0

for src in Tests/Fixtures/Darwin/*/; do
    name=$(basename "$src")
    app="$out/$name.app"
    rm -rf "$app"
    mkdir -p "$app"
    sources=$(ls "$src"/*.m)
    includes=""
    if [ -f "$src/dependencies" ]; then
        while read -r url commit dir; do
            [ -n "$url" ] || continue
            checkout="$deps/$(basename "$url" .git)"
            if [ ! -d "$checkout" ]; then
                git clone -q "$url" "$checkout"
            fi
            git -C "$checkout" checkout -q "$commit"
            sources="$sources $(find "$checkout/$dir" -name '*.m' | sort)"
            for header_dir in $(find "$checkout/$dir" -name '*.h' -exec dirname {} \; | sort -u); do
                includes="$includes -I$header_dir"
            done
        done < "$src/dependencies"
    fi
    if grep -q '<UIKit/' $sources; then frameworks="-framework Foundation -framework UIKit"; else frameworks="-framework Foundation"; fi
    libraries=""
    ios_includes="$includes"
    mac_includes="$includes"
    if grep -q '<libxml/' $sources; then
        libraries="-lxml2"
        ios_includes="$ios_includes -I$sdk/usr/include/libxml2"
        mac_includes="$mac_includes -I$macsdk/usr/include/libxml2"
    fi
    # Other system libraries, by the header a source includes.
    grep -q '<zlib.h>' $sources && libraries="$libraries -lz"
    grep -q '<bzlib.h>' $sources && libraries="$libraries -lbz2"
    grep -q '<compression.h>' $sources && libraries="$libraries -lcompression"
    grep -q '<sqlite3.h>' $sources && libraries="$libraries -lsqlite3"
    grep -q '<expat.h>' $sources && libraries="$libraries -lexpat"
    grep -q '<iconv.h>' $sources && libraries="$libraries -liconv"
    xcrun --sdk iphoneos clang -target "arm64-apple-ios$min" -isysroot "$sdk" \
        -fobjc-arc -fmodules -O1 $ios_includes \
        $frameworks $libraries \
        -o "$app/$name" $sources
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
                -fobjc-arc -fmodules -O1 $mac_includes \
                $frameworks $libraries \
                -o "$macos/MacOS/$name" $sources ;;
        *)
            xcrun --sdk macosx clang -target arm64-apple-macos13 \
                -fobjc-arc -fmodules -O1 $mac_includes \
                $frameworks $libraries \
                -o "$macos/MacOS/$name" $sources ;;
    esac
    cp "$src/Info.plist" "$macos/Info.plist"

    for resource in "$src"/*; do
        case "$resource" in
            *.m|*/Info.plist|*/dependencies) ;;
            *) cp "$resource" "$app/"; cp "$resource" "$macos/Resources/" ;;
        esac
    done

    # A hung reference run fails the build instead of stalling it.
    perl -e 'alarm 30; exec @ARGV' "$macos/MacOS/$name" > "$out/$name.expected" 2>/dev/null
    echo "$app"
done
