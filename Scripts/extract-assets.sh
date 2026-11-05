#!/bin/sh
# Decodes the images in an app's asset catalogs on a Mac, with macOS's own
# CoreUI, into <catalog>.images directories of <name>@<scale>x.png beside
# each Assets.car, which Perry reads for renditions it can't decode itself:
# CoreUI's deepmap2 compression, which Apple hasn't documented and which
# Xcode uses for most images from iOS 17 on.
# Usage: Scripts/extract-assets.sh <App.app>...
set -eu
cd "$(dirname "$0")/.."
[ "$(uname)" = Darwin ] || { echo "needs macOS" >&2; exit 1; }
[ $# -gt 0 ] || { echo "usage: $0 <App.app>..." >&2; exit 1; }
tool=.build/extract-assets/extract-assets
mkdir -p "$(dirname "$tool")"
if [ ! -x "$tool" ] || [ Scripts/extract-assets/main.swift -nt "$tool" ]; then
    xcrun --sdk macosx swiftc -O -o "$tool" Scripts/extract-assets/main.swift
fi
for app in "$@"; do
    find "$app" -name Assets.car -print0 | xargs -0 "$tool"
done
