#!/bin/sh
# Decodes the images in an app's asset catalogs on a Mac, with macOS's own
# CoreUI, into <catalog>.images directories of <name>@<scale>x.png beside
# each Assets.car, which Perry reads for renditions it can't decode itself:
# CoreUI's deepmap2 compression, which Apple hasn't documented and which
# Xcode uses for most images from iOS 17 on. Then the SF Symbols the app
# names, rendered by macOS into <App>.app/SFSymbols (Scripts/extract-symbols).
# Usage: Scripts/extract-assets.sh <App.app>...
set -eu
cd "$(dirname "$0")/.."
[ "$(uname)" = Darwin ] || { echo "needs macOS" >&2; exit 1; }
[ $# -gt 0 ] || { echo "usage: $0 <App.app>..." >&2; exit 1; }
tool=.build/extract-assets/extract-assets
symbols=.build/extract-assets/extract-symbols
mkdir -p "$(dirname "$tool")"
if [ ! -x "$tool" ] || [ Scripts/extract-assets/main.swift -nt "$tool" ]; then
    xcrun --sdk macosx swiftc -O -o "$tool" Scripts/extract-assets/main.swift
fi
if [ ! -x "$symbols" ] || [ Scripts/extract-symbols/main.swift -nt "$symbols" ]; then
    xcrun --sdk macosx swiftc -O -o "$symbols" Scripts/extract-symbols/main.swift
fi
for app in "$@"; do
    find "$app" -name Assets.car -print0 | xargs -0 "$tool"
    # The SF Symbols the app names, rendered by macOS into <App>.app/SFSymbols.
    "$symbols" "$app"
done
