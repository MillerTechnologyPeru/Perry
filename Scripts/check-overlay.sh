#!/bin/bash
# Lists the Swift symbols a reference overlay exports that one of Perry's
# doesn't, demangled: what programs built against the reference can call
# that Perry's overlay would leave unresolved. Run on a Mac with Xcode.
#
# Usage: Scripts/check-overlay.sh <Perry's dylib> <reference>...
#   A reference is a dylib (Xcode's Swift 5.0 overlay) or an SDK's .tbd
#   stub (what the current OS exports); the missing symbols are those of
#   any of them.
#   PERRY_CHECK_ARCH: the dylibs' slice to compare (default x86_64)
#   PERRY_CHECK_MANGLED=1 prints the mangled names beside the demangled ones.
#
# Example, for Dispatch:
#   Scripts/check-overlay.sh .build/perry-swift-runtime/libswiftDispatch.dylib \
#     "$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-5.0/macosx/libswiftDispatch.dylib" \
#     "$(xcrun --sdk macosx --show-sdk-path)/usr/lib/swift/libswiftDispatch.tbd"
set -eu
[ $# -ge 2 ] || { echo "usage: $0 <Perry's dylib> <reference>..." >&2; exit 1; }
perry=$1
shift
arch=${PERRY_CHECK_ARCH:-x86_64}
symbols() {
    case $1 in
    *.tbd) grep -o "'_\$s[^']*'" "$1" | tr -d "'" ;;
    *) xcrun nm -arch "$arch" -gU "$1" | awk '$3 ~ /^_\$s/ { print $3 }' ;;
    esac
}
missing=$(comm -23 <(for reference in "$@"; do symbols "$reference"; done | sort -u) <(symbols "$perry" | sort -u))
if [ -z "$missing" ]; then
    echo "$(basename "$perry"): nothing missing" >&2
    exit 0
fi
if [ "${PERRY_CHECK_MANGLED:-0}" = 1 ]; then
    echo "$missing" | xcrun swift-demangle
else
    echo "$missing" | xcrun swift-demangle --simplified --compact
fi
echo "$(basename "$perry"): $(echo "$missing" | wc -l | tr -d ' ') missing" >&2
exit 1
