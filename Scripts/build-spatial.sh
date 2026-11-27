#!/bin/sh
# The SDK's libSpatial.tbd exports no symbols: Spatial's API is implemented
# inline and in libswiftSpatial. Supply its empty Darwin load dependency.
set -eu
cd "$(dirname "$0")/.."
. Scripts/darwin-toolchain.sh
out=${1:-.build/perry-swift-runtime}
mkdir -p "$out"
printf '%s\n' '/* Spatial has no out-of-line C API. */' | \
    darwin_clang iphoneos -target arm64-apple-ios18.0 -isysroot "$(darwin_sdk iphoneos)" \
    -x c -dynamiclib - -Wl,-install_name,/usr/lib/libSpatial.dylib \
    -o "$out/libSpatial.dylib"
echo "$out/libSpatial.dylib"
