#!/bin/sh
# Assembles Darwin's Swift runtime for Perry (PERRY_SWIFT_RUNTIME) on a Mac
# with Xcode: the libraries iOS keeps in /usr/lib/swift, which Swift apps
# built for iOS 12.2 or later link instead of embedding them.
#
# They come from the newest iOS Simulator runtime installed, its arm64
# slices: the same Swift code as a device's, without pointer
# authentication, which Perry cannot run. Since iOS 17 several overlays
# there (Foundation's, UIKit's, CoreGraphics'…) are only re-exports of
# their framework, which carries the Swift code itself, or links to it;
# Perry's frameworks have no Swift in them, so those come instead from the
# Swift 5.0 overlays Xcode keeps for apps that embed the runtime, which
# have the Swift code. Overlays with neither are left out.
#
# Usage: Scripts/swift-runtime.sh [output directory]
#   default output: .build/perry-swift-runtime
set -eu
cd "$(dirname "$0")/.."
[ "$(uname)" = Darwin ] || { echo "needs macOS with Xcode" >&2; exit 1; }

out=${1:-.build/perry-swift-runtime}
# The newest iOS runtime simctl knows, wherever it is mounted: iOS 27's are
# cryptexes, mounted under /private/var/run/com.apple.security.cryptexd.
runtime=$(xcrun simctl runtime list -j 2>/dev/null | /usr/bin/python3 -c '
import json, sys
runtimes = [r for r in json.load(sys.stdin).values()
            if r.get("platformIdentifier", "").endswith("iphonesimulator") and r.get("runtimeBundlePath")]
runtimes.sort(key=lambda r: [int(p) for p in r.get("version", "0").split(".")])
print(runtimes[-1]["runtimeBundlePath"] if runtimes else "")' || true)
[ -n "$runtime" ] || runtime=$(ls -d /Library/Developer/CoreSimulator/Volumes/*/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS*.simruntime \
              /Library/Developer/CoreSimulator/Profiles/Runtimes/iOS*.simruntime 2>/dev/null | sort -V | tail -1)
[ -n "$runtime" ] || { echo "no iOS Simulator runtime installed (Xcode > Settings > Components)" >&2; exit 1; }
swift_dir="$runtime/Contents/Resources/RuntimeRoot/usr/lib/swift"
# From iOS 27 the runtime's core libraries are only in the simulator's dyld
# shared cache, not files.
[ -f "$swift_dir/libswiftCore.dylib" ] || {
    echo "$(basename "$runtime") keeps libswiftCore only in its shared cache; use a runtime before iOS 27" >&2
    exit 1
}
overlays="$(dirname "$(xcrun --find swift)")/../lib/swift-5.0/iphoneos"
[ -d "$overlays" ] || { echo "no Swift 5.0 overlays at $overlays" >&2; exit 1; }

mkdir -p "$out"
echo "runtime: $swift_dir"
echo "overlays: $overlays"

for library in "$swift_dir"/*.dylib; do
    name=$(basename "$library")
    reexports=$(otool -arch arm64 -l "$library" 2>/dev/null | grep -A2 LC_REEXPORT_DYLIB | grep ' name /System/' || true)
    if [ -L "$library" ] || [ -n "$reexports" ]; then
        if [ -f "$overlays/$name" ]; then
            cp "$overlays/$name" "$out/$name"
            echo "$name: Swift 5.0 overlay"
        else
            echo "$name: left out, its Swift code is in its framework"
        fi
        continue
    fi
    if lipo "$library" -verify_arch arm64 2>/dev/null; then
        lipo "$library" -thin arm64 -output "$out/$name" 2>/dev/null || cp "$library" "$out/$name"
    fi
done
echo "PERRY_SWIFT_RUNTIME=$(cd "$out" && pwd)"
