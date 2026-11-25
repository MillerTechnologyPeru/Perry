#!/bin/bash
# Builds all of Perry's Swift overlays and Swift frameworks on a Mac with
# Xcode 27, one script after another in the order they need, into a Swift
# runtime directory (PERRY_SWIFT_RUNTIME). For arm64 that is the directory
# Scripts/swift-runtime.sh assembles, on a Mac with an iOS Simulator
# runtime before iOS 27; nothing here needs it, so the overlays can be
# built into an empty directory and the runtime laid under them later,
# as long as Perry's libraries are the ones kept where both have a file.
#
# arm64 is iOS's set: UIKit's additions and CoreText's overlay, WebKit,
# the Swift frameworks with DeveloperToolsSupport first, Accessibility,
# Combine, MarketplaceKit, Foundation, SwiftUI (optimized) and the SwiftUI
# cross-import overlays, which build against SwiftUI's modules.
#
# x86_64 is Mac apps': the overlays written from the macOS SDK's
# interfaces (Darwin/<Module>/README.md), AppKit's, CreateML's and
# XCTest's among them, TabularData, CryptoKit, Combine and Foundation for
# macOS (x86_64-apple-macos15.0), and UIKit's additions,
# DeveloperToolsSupport, Accessibility and SwiftUI for Mac Catalyst
# (x86_64-apple-ios18.0-macabi), whose libraries sit beside them, as on a
# Mac. The macOS overlays are not iOS's: several use macOS-only API, and
# Darwin's calls variadic C functions as x86_64 passes their arguments;
# for iOS the runtime keeps the simulator's and Xcode's.
#
# A step that fails stops the build, naming the step and the command to run
# it again; each step's time is printed as it ends and all of them at the
# end (and in the job's summary on GitHub Actions). Foundation's and
# SwiftUI's builds fetch their pinned packages from github.com (and
# SwiftPM swift-syntax's prebuilt macro support from download.swift.org),
# into .build/perry-foundation and .build/perry-swiftui; nothing needs a
# simulator.
#
# Usage: Scripts/build-swift-overlays.sh [output directory] [arm64|x86_64]
#   default output: .build/perry-swift-runtime (arm64),
#     .build/perry-swift-runtime-x86_64 (x86_64)
#   PERRY_OVERLAY_ARCH: the architecture, when not given (default arm64)
set -eu
cd "$(dirname "$0")/.."
[ "$(uname)" = Darwin ] || { echo "needs macOS with Xcode" >&2; exit 1; }

arch=${2:-${PERRY_OVERLAY_ARCH:-arm64}}
case $arch in
    arm64) out=${1:-.build/perry-swift-runtime} ;;
    x86_64) out=${1:-.build/perry-swift-runtime-x86_64} ;;
    *) echo "usage: $0 [output directory] [arm64|x86_64]" >&2; exit 1 ;;
esac
mkdir -p "$out"
out=$(cd "$out" && pwd)

# The overlays are written against the Xcode 27 SDKs' interfaces.
sdk_version=$(xcrun --sdk iphoneos --show-sdk-version)
[ "${sdk_version%%.*}" -ge 27 ] || {
    echo "Perry's overlays need Xcode 27's SDKs; $(xcode-select -p) has iOS $sdk_version (select another with xcode-select or DEVELOPER_DIR)" >&2
    exit 1
}
unset PERRY_OVERLAY_PLATFORM PERRY_OVERLAY_TARGET TARGET CONFIGURATION

steps=() seconds=()
# Runs one step: a label, then the command.
step() {
    local label=$1 start status
    shift
    [ -n "${GITHUB_ACTIONS:-}" ] && echo "::group::$label"
    echo "==> $label: $*"
    start=$(date +%s)
    status=0
    "$@" || status=$?
    [ -n "${GITHUB_ACTIONS:-}" ] && echo "::endgroup::"
    steps+=("$label") seconds+=($(($(date +%s) - start)))
    if [ $status -ne 0 ]; then
        echo "build-swift-overlays: $label failed ($status) after ${seconds[${#seconds[@]}-1]}s; to run it again:" >&2
        echo "    $*" >&2
        [ -n "${GITHUB_ACTIONS:-}" ] && echo "::error title=build-swift-overlays::$label failed: $*"
        exit $status
    fi
    echo "<== $label: ${seconds[${#seconds[@]}-1]}s"
}
# The same, for a macOS (macos) or Mac Catalyst (catalyst) x86_64 build.
macos() { step "$1 (macOS)" env PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-macos15.0 "${@:2}"; }
catalyst() { step "$1 (Mac Catalyst)" env PERRY_OVERLAY_PLATFORM=macosx PERRY_OVERLAY_TARGET=x86_64-apple-ios18.0-macabi "${@:2}"; }

# The overlays Scripts/build-overlay.sh builds for macOS, written from its
# SDK's interfaces; the last three are macOS's own (Darwin/<Module>/platform).
mac_overlays=(AVFoundation Accelerate CloudKit Compression Contacts CoreAudio CoreData CoreFoundation CoreGraphics
              CoreImage CoreLocation CoreMedia CoreText CryptoTokenKit Darwin Dispatch GLKit GameplayKit IOKit Intents
              MapKit Metal MetalKit ModelIO NaturalLanguage Network ObjectiveC OpenCL Photos QuartzCore SafariServices
              SceneKit SpriteKit UniformTypeIdentifiers Vision XPC os simd AppKit CreateML XCTest)
# Scripts/build-framework.sh's, after DeveloperToolsSupport, which SwiftUI
# builds against.
frameworks=(ActivityKit AppIntents CryptoKit DeclaredAgeRange GroupActivities MusicKit StoreKit TabularData TipKit
            WeatherKit WidgetKit)

total=$(date +%s)
if [ "$arch" = arm64 ]; then
    for module in UIKitAdditions CoreText; do
        step "$module" Scripts/build-overlay.sh "$module" "$out"
    done
    step WebKit Scripts/build-webkit.sh "$out"
    for module in DeveloperToolsSupport "${frameworks[@]}"; do
        step "$module" Scripts/build-framework.sh "$module" "$out"
    done
    step Accessibility Scripts/build-accessibility.sh "$out"
    step Combine Scripts/build-combine.sh "$out"
    step MarketplaceKit Scripts/build-marketplacekit.sh "$out"
    step Foundation Scripts/build-foundation.sh "$out"
    step SwiftUI env CONFIGURATION=release Scripts/build-swiftui.sh "$out"
    step _MapKit_SwiftUI Scripts/build-mapkit-swiftui.sh "$out"
    step _StoreKit_SwiftUI Scripts/build-storekit-swiftui.sh "$out"
    step _AuthenticationServices_SwiftUI Scripts/build-authenticationservices-swiftui.sh "$out"
else
    for module in "${mac_overlays[@]}"; do
        macos "$module" Scripts/build-overlay.sh "$module" "$out"
    done
    for module in TabularData CryptoKit; do
        macos "$module" Scripts/build-framework.sh "$module" "$out"
    done
    macos Combine Scripts/build-combine.sh "$out"
    macos Foundation Scripts/build-foundation.sh "$out"
    catalyst UIKitAdditions Scripts/build-overlay.sh UIKitAdditions "$out"
    catalyst DeveloperToolsSupport Scripts/build-framework.sh DeveloperToolsSupport "$out"
    catalyst Accessibility Scripts/build-accessibility.sh "$out"
    catalyst SwiftUI env CONFIGURATION=release Scripts/build-swiftui.sh "$out"
fi
total=$(($(date +%s) - total))

echo
echo "Built Perry's $arch overlays into $out in ${total}s:"
for i in "${!steps[@]}"; do printf '%6ss  %s\n' "${seconds[$i]}" "${steps[$i]}"; done
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        echo "### Swift overlays ($arch): ${total}s"
        echo
        echo "| Step | Seconds |"
        echo "| --- | ---: |"
        for i in "${!steps[@]}"; do echo "| ${steps[$i]} | ${seconds[$i]} |"; done
    } >> "$GITHUB_STEP_SUMMARY"
fi
echo "PERRY_SWIFT_RUNTIME=$out"
