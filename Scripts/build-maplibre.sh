#!/bin/bash
# Builds libPerryMapLibre.so, the map PerryMapKit's map views draw: MapLibre
# Native's core (BSD 2-clause, built from its own repository, not copied
# into Perry) with Perry's C interface over it (Scripts/maplibre), for
# Linux, in Docker on Debian sid. It renders offscreen with EGL and OpenGL
# ES, and needs at run time the libraries it links: libcurl, libuv, ICU,
# libpng, libjpeg, libwebp, libEGL and glvnd's libOpenGL.
#
# MapLibre is fetched at the commit below, with its submodules, unless
# MAPLIBRE_SOURCE names a checkout to build instead. PERRY_MAPLIBRE_PLATFORM
# picks Docker's platform (default linux/arm64).
#
# Usage: Scripts/build-maplibre.sh [output directory]
#   default output: .build/perry-maplibre/out
set -eu
cd "$(dirname "$0")/.."

commit=d1b09a891050bf9eadca9e5fc7c71fb70d7b002c
repository=https://github.com/maplibre/maplibre-native.git
platform=${PERRY_MAPLIBRE_PLATFORM:-linux/arm64}

root=$PWD
work=$root/.build/perry-maplibre
out=${1:-$work/out}
case $out in /*) ;; *) out=$root/$out ;; esac
mkdir -p "$work" "$out"

source=${MAPLIBRE_SOURCE:-$work/maplibre-native}
if [ -z "${MAPLIBRE_SOURCE:-}" ] && ! { [ -e "$source/.perry-commit" ] && [ "$(cat "$source/.perry-commit")" = $commit ]; }; then
    rm -rf "$source"; mkdir -p "$source"
    git -C "$source" init -q
    git -C "$source" fetch -q --depth 1 $repository $commit
    git -C "$source" checkout -q FETCH_HEAD
    git -C "$source" submodule update -q --init --recursive --depth 1
    echo $commit > "$source/.perry-commit"
fi

# The build directory is per platform, inside the source, which the
# container sees as /mln.
build=build-perry-${platform//\//-}
docker run --rm --platform "$platform" \
    -v "$source:/mln" -v "$root/Scripts/maplibre:/perry-maplibre:ro" -v "$out:/out" -w /mln debian:sid sh -euc "
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends build-essential clang cmake ninja-build \
    pkg-config git ca-certificates libcurl4-openssl-dev libuv1-dev libpng-dev libicu-dev libjpeg-dev libwebp-dev \
    libegl-dev libgles-dev libglvnd-dev zlib1g-dev libsqlite3-dev >/dev/null
cmake -S . -B $build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_PROJECT_INCLUDE=/perry-maplibre/perry.cmake \
    -DMLN_WITH_OPENGL=ON -DMLN_WITH_EGL=ON -DMLN_WITH_X11=OFF -DMLN_WITH_GLFW=OFF -DMLN_WITH_WERROR=OFF >/dev/null
cmake --build $build --target PerryMapLibre
strip --strip-unneeded -o /out/libPerryMapLibre.so $build/libPerryMapLibre.so
"
echo "$out/libPerryMapLibre.so"
