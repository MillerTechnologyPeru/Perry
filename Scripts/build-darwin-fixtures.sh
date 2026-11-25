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
# those libraries, and .xcdatamodeld models are compiled with momc.
#
# A fixture with a `no-reference` file records no output: one whose output
# depends on things only Perry's tests provide, such as a Bluetooth device.
#
# A fixture with an Entitlements.plist (the keychain needs some) records its
# output from the iOS Simulator instead of macOS: it is built for the
# simulator with the entitlements in __TEXT,__entitlements, as Xcode puts
# them, and run with simctl spawn on PERRY_SIMULATOR or the first iPhone
# simulator, which is booted if it is not running. One that calls
# UIApplicationMain is installed as an app and launched instead, as UIKit
# needs a bundle identifier.
#
# PERRY_FIXTURES_ARCH=x86_64 builds the fixtures for Perry on x86_64 instead,
# into .build/perry-fixtures/darwin-x86_64. There is no x86_64 iOS device,
# so each is the x86_64 program its reference comes from: the macOS or Mac
# Catalyst app, in a macOS bundle (<name>.app/Contents/MacOS/<name>), and
# for a fixture with an Entitlements.plist, or one that uses OpenGL ES,
# which Mac Catalyst doesn't have, the iOS Simulator program, in an iOS
# bundle. On an arm64 Mac the macOS apps run under Rosetta, and the
# simulator's reference comes from the same sources built for the simulator
# of the Mac's own architecture, the only one its runtime may have. A Swift
# fixture is its macOS program, which Perry runs on the x86_64 runtime
# directory (.build/perry-swift-runtime-x86_64). The default, arm64, builds
# the iOS apps described above.
#
# A reference run that fails or hangs fails the build, after the other
# fixtures are built, with what it printed to stderr. PERRY_FIXTURES_UNRECORDED
# names fixtures (separated by spaces) that may go without a reference
# instead, where the machine can't give one: CI's has no iCloud account.
set -eu
cd "$(dirname "$0")/.."
[ "$(uname)" = Darwin ] || { echo "needs macOS with Xcode" >&2; exit 1; }

arch=${PERRY_FIXTURES_ARCH:-arm64}
case $arch in
    arm64) out=.build/perry-fixtures/darwin ;;
    x86_64) out=.build/perry-fixtures/darwin-x86_64 ;;
    *) echo "PERRY_FIXTURES_ARCH is arm64 or x86_64, not $arch" >&2; exit 1 ;;
esac
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
macsdk=$(xcrun --sdk macosx --show-sdk-path)
deps=.build/perry-fixtures/sources
min=15.0
failed=""
warmed=""
mkdir -p "$out"

# Runs a command for at most $2 seconds, recording its stdout as fixture
# $1's reference, and once more if it fails or runs out of time: a
# simulator that has just booted can take longer than that to start a
# program. A second failure is kept for the end, without a reference.
record() {
    record_name=$1
    record_seconds=$2
    shift 2
    for record_attempt in 1 2; do
        if perl -e 'alarm shift; exec @ARGV' "$record_seconds" "$@" > "$out/$record_name.expected" 2> "$out/$record_name.stderr"; then
            rm -f "$out/$record_name.stderr"
            return 0
        fi
        echo "reference run $record_attempt of $record_name failed:" >&2
        tail -20 "$out/$record_name.stderr" >&2
    done
    rm -f "$out/$record_name.expected" "$out/$record_name.stderr"
    failed="$failed $record_name"
}

for src in Tests/Fixtures/Darwin/*/; do
    name=$(basename "$src")
    app="$out/$name.app"
    rm -rf "$app"
    # A Swift fixture, main.swift, built with swiftc for its MinimumOSVersion,
    # and for macOS for its reference. Perry runs it on the Swift runtime
    # directory of its architecture (Scripts/build-swift-runtime.sh and
    # Scripts/build-swift-overlays.sh). On x86_64 the macOS program is the
    # fixture as well.
    if [ -f "$src/main.swift" ]; then
        if [ "$arch" = x86_64 ]; then
            macos="$app/Contents"
            mkdir -p "$macos/MacOS"
            xcrun --sdk macosx swiftc -target x86_64-apple-macos14 -sdk "$macsdk" \
                -swift-version 5 -O -o "$macos/MacOS/$name" "$src"/*.swift
            cp "$src/Info.plist" "$macos/Info.plist"
            record "$name" 60 "$macos/MacOS/$name"
            echo "$app"
            continue
        fi
        mkdir -p "$app"
        swift_min=$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$src/Info.plist")
        xcrun --sdk iphoneos swiftc -target "arm64-apple-ios$swift_min" -sdk "$sdk" \
            -swift-version 5 -O -o "$app/$name" "$src"/*.swift
        plutil -convert binary1 -o "$app/Info.plist" "$src/Info.plist"
        macos="$out/macos/$name.app/Contents"
        rm -rf "$out/macos/$name.app"
        mkdir -p "$macos/MacOS"
        xcrun --sdk macosx swiftc -target arm64-apple-macos14 -sdk "$macsdk" \
            -swift-version 5 -O -o "$macos/MacOS/$name" "$src"/*.swift
        cp "$src/Info.plist" "$macos/Info.plist"
        record "$name" 60 "$macos/MacOS/$name"
        echo "$app"
        continue
    fi
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
    grep -q '<CoreData/' $sources && frameworks="$frameworks -framework CoreData"
    grep -q '<Security/' $sources && frameworks="$frameworks -framework Security"
    grep -q '<CoreBluetooth/' $sources && frameworks="$frameworks -framework CoreBluetooth"
    grep -q '<CFNetwork/' $sources && frameworks="$frameworks -framework CFNetwork"
    grep -q '<Metal/' $sources && frameworks="$frameworks -framework Metal"
    # OpenGL ES works on iOS, deprecated; the warnings are not the point.
    grep -q '<OpenGLES/' $sources && frameworks="$frameworks -framework OpenGLES -DGLES_SILENCE_DEPRECATION"
    grep -q '<GLKit/' $sources && frameworks="$frameworks -framework GLKit -framework OpenGLES -DGLES_SILENCE_DEPRECATION"
    grep -q '<WebKit/' $sources && frameworks="$frameworks -framework WebKit"

    # A fixture with an Entitlements.plist is recorded on the iOS Simulator,
    # and on x86_64 so is one that uses OpenGL ES, which Mac Catalyst
    # doesn't have. On x86_64 such a fixture is the x86_64 simulator
    # program, in an iOS bundle as the arm64 one is.
    simulated=""
    entitlements=""
    if [ -f "$src/Entitlements.plist" ]; then
        simulated=1
        entitlements="-Wl,-sectcreate,__TEXT,__entitlements,$src/Entitlements.plist"
    fi
    if [ "$arch" = x86_64 ]; then
        case "$frameworks" in *OpenGLES*) simulated=1 ;; esac
    fi
    ios_app=$simulated
    [ "$arch" = arm64 ] && ios_app=1
    if [ -n "$ios_app" ]; then
        mkdir -p "$app"
        if [ "$arch" = arm64 ]; then
            xcrun --sdk iphoneos clang -target "arm64-apple-ios$min" -isysroot "$sdk" \
                -fobjc-arc -fmodules -O1 $ios_includes \
                $frameworks $libraries \
                -o "$app/$name" $sources
        else
            xcrun --sdk iphonesimulator clang -target "x86_64-apple-ios$min-simulator" \
                -isysroot "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
                -fobjc-arc -fmodules -O1 $ios_includes \
                $frameworks $libraries $entitlements \
                -o "$app/$name" $sources
        fi
        plutil -convert binary1 -o "$app/Info.plist" "$src/Info.plist"
        # Metal shaders, built into default.metallib as Xcode builds them.
        if ls "$src"/*.metal >/dev/null 2>&1; then
            xcrun -sdk iphoneos metal -std=metal3.0 -mios-version-min=$min -o "$app/default.metallib" "$src"/*.metal
        fi
        # Core Data models, compiled as Xcode does.
        for data_model in "$src"/*.xcdatamodeld; do
            [ -d "$data_model" ] || continue
            model_name=$(basename "$data_model" .xcdatamodeld)
            xcrun momc --iphoneos-deployment-target "$min" "$data_model" "$app/$model_name.momd" >/dev/null
        done

        for resource in "$src"/*; do
            case "$resource" in
                *.m|*.metal|*/Info.plist|*/dependencies|*.xcdatamodeld|*/Entitlements.plist|*/no-reference) ;;
                *) cp "$resource" "$app/" ;;
            esac
        done
    fi

    if [ -n "$ios_app" ] && [ -f "$src/no-reference" ]; then
        echo "$app"
        continue
    fi

    if [ -n "$simulated" ]; then
        simulator="${PERRY_SIMULATOR:-$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ { print $2; exit }')}"
        xcrun simctl boot "$simulator" 2>/dev/null || true
        xcrun simctl bootstatus "$simulator" -b >/dev/null
        # A simulator that has just booted starts its first programs
        # slowly, WebKit's above all: one is run and waited for first.
        if [ -z "$warmed" ]; then
            xcrun simctl spawn "$simulator" launchctl list >/dev/null 2>&1 || true
            warmed=1
        fi
        # The simulator runs programs of the Mac's own architecture.
        simulator_arch=$arch
        [ "$arch" = x86_64 ] && simulator_arch=$(uname -m)
        simulator_binary="$out/simulator/$name"
        mkdir -p "$out/simulator"
        xcrun --sdk iphonesimulator clang -target "$simulator_arch-apple-ios$min-simulator" \
            -isysroot "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
            -fobjc-arc -fmodules -O1 $ios_includes $frameworks $libraries $entitlements \
            -o "$simulator_binary" $sources
        # The simulator's dyld can block opening binaries on an external
        # volume, so the fixture runs from a copy on the system disk.
        spawn_dir=$(mktemp -d)
        if grep -q UIApplicationMain $sources; then
            # UIKit apps need a bundle identifier: install and launch the
            # app, keeping its output without the launch's "id: pid" line.
            bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$src/Info.plist")
            sim_app="$spawn_dir/$name.app"
            mkdir -p "$sim_app"
            cp "$simulator_binary" "$src/Info.plist" "$sim_app/"
            codesign -s - -f ${entitlements:+--entitlements "$src/Entitlements.plist"} "$sim_app" 2>/dev/null
            xcrun simctl install "$simulator" "$sim_app"
            perl -e 'alarm 60; exec @ARGV' xcrun simctl launch --console-pty --terminate-running-process \
                "$simulator" "$bundle_id" 2>/dev/null | tr -d '\r' | grep -v "^$bundle_id: [0-9]*\$" \
                > "$out/$name.expected" || true
            xcrun simctl uninstall "$simulator" "$bundle_id"
        else
            cp "$simulator_binary" "$spawn_dir/$name"
            record "$name" 180 xcrun simctl spawn "$simulator" "$spawn_dir/$name"
        fi
        rm -rf "$spawn_dir"
        echo "$app"
        continue
    fi

    # The same app for macOS, whose bundle keeps everything under Contents:
    # beside the iOS app on arm64, and the fixture itself on x86_64.
    if [ "$arch" = arm64 ]; then
        macos="$out/macos/$name.app/Contents"
        rm -rf "$out/macos/$name.app"
    else
        macos="$app/Contents"
    fi
    mkdir -p "$macos/MacOS" "$macos/Resources"
    case "$frameworks" in
        *UIKit*)
            xcrun --sdk macosx clang -target "$arch-apple-ios$min-macabi" -isysroot "$macsdk" \
                -iframework "$macsdk/System/iOSSupport/System/Library/Frameworks" \
                -L"$macsdk/System/iOSSupport/usr/lib" \
                -fobjc-arc -fmodules -O1 $mac_includes \
                $frameworks $libraries \
                -o "$macos/MacOS/$name" $sources ;;
        *)
            xcrun --sdk macosx clang -target "$arch-apple-macos13" \
                -fobjc-arc -fmodules -O1 $mac_includes \
                $frameworks $libraries \
                -o "$macos/MacOS/$name" $sources ;;
    esac
    cp "$src/Info.plist" "$macos/Info.plist"
    if ls "$src"/*.metal >/dev/null 2>&1; then
        xcrun -sdk macosx metal -std=metal3.0 -mmacosx-version-min=13.0 -o "$macos/Resources/default.metallib" "$src"/*.metal
    fi
    for data_model in "$src"/*.xcdatamodeld; do
        [ -d "$data_model" ] || continue
        model_name=$(basename "$data_model" .xcdatamodeld)
        xcrun momc --macosx-deployment-target 13.0 "$data_model" "$macos/Resources/$model_name.momd" >/dev/null
    done

    for resource in "$src"/*; do
        case "$resource" in
            *.m|*.metal|*/Info.plist|*/dependencies|*.xcdatamodeld|*/Entitlements.plist|*/no-reference) ;;
            *) cp "$resource" "$macos/Resources/" ;;
        esac
    done

    if [ -f "$src/no-reference" ]; then
        echo "$app"
        continue
    fi

    # Mac Catalyst restores scene sessions an earlier run saved; each run
    # starts without them.
    bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$src/Info.plist")
    rm -rf "$HOME/Library/Saved Application State/$bundle_id~iosmac.savedState"
    # A hung reference run fails the build instead of stalling it.
    record "$name" 30 "$macos/MacOS/$name"
    echo "$app"
done

unexpected=""
for name in $failed; do
    case " ${PERRY_FIXTURES_UNRECORDED:-} " in
        *" $name "*) echo "no reference for $name, as PERRY_FIXTURES_UNRECORDED allows" ;;
        *) unexpected="$unexpected $name" ;;
    esac
done
[ -z "$unexpected" ] || { echo "reference runs failed:$unexpected" >&2; exit 1; }
