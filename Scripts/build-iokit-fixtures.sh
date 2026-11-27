#!/bin/sh
# Build Darwin ARM64 probes for IOKit integration under Perry on Linux.
set -eu
cd "$(dirname "$0")/.."
out="$PWD/.build/iokit-fixtures"
mkdir -p "$out/module-cache"
xcrun clang -arch arm64 -mmacosx-version-min=13.0 Tests/Fixtures/iokit_phase1.c -framework IOKit -framework CoreFoundation -o "$out/iokit_phase1"
xcrun clang -arch arm64 -mmacosx-version-min=13.0 Tests/Fixtures/iokit_appkit.m -framework AppKit -framework IOKit -o "$out/iokit_appkit"
xcrun swiftc -module-cache-path "$out/module-cache" -target arm64-apple-macosx13.0 Tests/Fixtures/iokit_swiftui.swift -o "$out/iokit_swiftui"
printf 'Fixtures built in %s\n' "$out"
