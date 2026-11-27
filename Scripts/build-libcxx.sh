#!/bin/bash
# Build Darwin ARM64 libc++ with libc++abi for Perry, using Xcode's iOS SDK.
# Usage: Scripts/build-libcxx.sh [output directory]
# PERRY_LLVM_SOURCE may select an existing LLVM source checkout.
set -eu
cd "$(dirname "$0")/.."
[ "$(uname)" = Darwin ] || { echo "needs macOS with Xcode" >&2; exit 1; }
root=$PWD
work="$root/.build/perry-libcxx"
out=${1:-$root/.build/perry-swift-runtime}
revision=fb5f84d903a3b4e7aea15cd5666598a46f56c833
source=${PERRY_LLVM_SOURCE:-$root/.build/swift-source/llvm-project}
if [ ! -f "$source/runtimes/CMakeLists.txt" ]; then
    source="$work/llvm-project"
    if [ ! -d "$source/.git" ]; then
        mkdir -p "$source"
        git -C "$source" init -q
        git -C "$source" sparse-checkout init --cone
        git -C "$source" sparse-checkout set runtimes libcxx libcxxabi cmake llvm/cmake llvm/utils
        git -C "$source" fetch --depth 1 --filter=blob:none https://github.com/swiftlang/llvm-project.git "$revision"
        git -C "$source" checkout -q FETCH_HEAD
    fi
fi
if [ -z "${PERRY_LLVM_SOURCE:-}" ] && [ "$(git -C "$source" rev-parse HEAD)" != "$revision" ]; then
    echo "LLVM revision differs from $revision; set PERRY_LLVM_SOURCE to use it explicitly" >&2
    exit 1
fi
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
mkdir -p "$out"
# Darwin is required here: this LLVM revision treats CMAKE_SYSTEM_NAME=iOS
# as an ELF target in HandleLLVMOptions and adds the unsupported -z flag.
cmake -G Ninja -S "$source/runtimes" -B "$work/darwin" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_SYSTEM_NAME=Darwin \
    -DCMAKE_C_COMPILER="$(xcrun -f clang)" -DCMAKE_CXX_COMPILER="$(xcrun -f clang++)" \
    -DCMAKE_C_COMPILER_TARGET=arm64-apple-ios18.0 -DCMAKE_CXX_COMPILER_TARGET=arm64-apple-ios18.0 \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_SYSROOT="$sdk" -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 \
    -DCMAKE_C_FLAGS=-mcpu=apple-a7 -DCMAKE_CXX_FLAGS=-mcpu=apple-a7 \
    '-DLLVM_ENABLE_RUNTIMES=libcxx;libcxxabi' -DLIBCXXABI_USE_LLVM_UNWINDER=OFF \
    -DLIBCXX_ENABLE_SHARED=ON -DLIBCXX_ENABLE_STATIC=OFF \
    -DLIBCXXABI_ENABLE_SHARED=OFF -DLIBCXXABI_ENABLE_STATIC=ON \
    -DLIBCXX_STATICALLY_LINK_ABI_IN_SHARED_LIBRARY=ON \
    -DLIBCXX_INCLUDE_TESTS=OFF -DLIBCXXABI_INCLUDE_TESTS=OFF -DLIBCXX_INCLUDE_BENCHMARKS=OFF
cmake --build "$work/darwin" --target cxx --parallel "${PERRY_BUILD_JOBS:-8}"
cp "$work/darwin/lib/libc++.1.0.dylib" "$out/libc++.1.dylib"
xcrun install_name_tool -id /usr/lib/libc++.1.dylib "$out/libc++.1.dylib"
echo "$out/libc++.1.dylib (add this directory to PERRY_LIBRARY_PATH)"
