#!/bin/sh
# Compiles the Metal Shading Language sources an app built at run time, which
# Perry writes to its source cache (PERRY_METAL_SOURCES) as <key>.metal, into
# <key>.metallib beside them, on a Mac with Xcode's Metal compiler. Perry
# loads those for -newLibraryWithSource:options:error:, as metal2vulkan
# reads compiled libraries only. Sources already compiled are skipped.
# <metal_stdlib> is included first, as Metal's run-time compiler includes
# it: some apps' sources use its types without including it.
# Usage: Scripts/compile-metal-sources.sh <directory> [iOS deployment target]
set -eu
[ "$(uname)" = Darwin ] || { echo "needs macOS with Xcode" >&2; exit 1; }
dir=${1:?usage: $0 <directory> [iOS version]}
min=${2:-16.0}
compiled=0 failed=0
for source in "$dir"/*.metal; do
    [ -e "$source" ] || continue
    library="${source%.metal}.metallib"
    [ -e "$library" ] && continue
    if xcrun -sdk iphoneos metal -mios-version-min="$min" -include metal_stdlib -w -o "$library" "$source" 2>"${source%.metal}.log"; then
        rm -f "${source%.metal}.log"
        compiled=$((compiled + 1))
    else
        echo "failed: $source (see ${source%.metal}.log)" >&2
        failed=$((failed + 1))
    fi
done
echo "compiled $compiled, failed $failed"
