#!/bin/sh
# Builds .build/armv7/bin/libc++.1.dylib: LLVM's libc++ and libc++abi for
# armv7 iOS, a Mach-O library the loader maps for a program's
# /usr/lib/libc++.1.dylib (it looks beside perry32 for any library of
# /usr/lib before a provider). On armv7, Darwin and Linux pass arguments and
# lay out structures differently, and a program's C++ is mostly inlined code
# that shares its objects with the library, so libc++ can't be a Linux build
# as it is on arm64.
#
# Run on the host, with Docker: the libraries are built in the container
# with the LLVM under .toolchains, against the C headers of an iOS SDK
# (IOS_SDK, or Xcode's), copied to .build/armv7/ios-sdk. They are linked into
# one library by Apple's ld64 (cctools-port, .toolchains/cctools) against a
# stub libSystem made from what they import, which Perry's libSystem
# provider has.
#
# usage: Scripts/build-armv7-libcxx.sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

sdk=${IOS_SDK:-$(xcrun --sdk iphoneos --show-sdk-path)}
out=.build/armv7
mkdir -p "$out/ios-sdk/usr" "$out/bin"
rm -rf "$out/ios-sdk/usr/include"
cp -R "$sdk/usr/include" "$out/ios-sdk/usr/include"

docker run --rm -v "$root:/perry" -w /perry perry-dev sh -eu -c '
llvm=$(ls -d /perry/.toolchains/LLVM-*/bin | head -1)
ld=/perry/.toolchains/cctools/bin/arm-apple-darwin11-ld
blocks=$(ls -d /perry/.toolchains/swift-*-RELEASE-*/usr/lib/swift/linux | head -1)
export LD_LIBRARY_PATH="$blocks"
sdk=/perry/.build/armv7/ios-sdk
work=/perry/.build/armv7/libcxx
target=armv7-apple-ios10.0
mkdir -p "$work"

# LLVM 19.1.7, the runtimes and what their CMake needs.
if [ ! -d "$work/llvm/runtimes" ]; then
    curl -fsSLo "$work/llvm.tar.xz" \
        https://github.com/llvm/llvm-project/releases/download/llvmorg-19.1.7/llvm-project-19.1.7.src.tar.xz
    echo "82401fea7b79d0078043f7598b835284d6650a75b93e64b6f761ea7b63097501  $work/llvm.tar.xz" | sha256sum -c -
    mkdir -p "$work/llvm"
    tar -xJf "$work/llvm.tar.xz" -C "$work/llvm" --strip-components=1 \
        llvm-project-19.1.7.src/runtimes llvm-project-19.1.7.src/libcxx llvm-project-19.1.7.src/libcxxabi \
        llvm-project-19.1.7.src/libunwind llvm-project-19.1.7.src/cmake llvm-project-19.1.7.src/llvm/cmake \
        llvm-project-19.1.7.src/llvm/utils
    rm "$work/llvm.tar.xz"
fi

# Static libraries for a target CMake does not know (Generic), as Apple
# builds them: softfp, SjLj exceptions (clang chooses them for armv7 iOS),
# no filesystem library (the SDK of the time has no <filesystem> support
# the library needs), no C11 aligned_alloc in old iOS.
flags="-target $target -isysroot $sdk -mfloat-abi=softfp -D_LIBCPP_HAS_NO_C11_ALIGNED_ALLOC -U__STRICT_ANSI__ -fno-stack-protector"
cmake -G Ninja -S "$work/llvm/runtimes" -B "$work/build" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=Generic -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    -DCMAKE_C_COMPILER="$llvm/clang" -DCMAKE_CXX_COMPILER="$llvm/clang++" -DCMAKE_ASM_COMPILER="$llvm/clang" \
    -DCMAKE_AR="$llvm/llvm-ar" -DCMAKE_RANLIB="$llvm/llvm-ranlib" \
    -DCMAKE_C_FLAGS="$flags" -DCMAKE_CXX_FLAGS="$flags" -DCMAKE_ASM_FLAGS="$flags" \
    -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi" \
    -DLIBCXX_ENABLE_SHARED=OFF -DLIBCXXABI_ENABLE_SHARED=OFF \
    -DLIBCXX_ENABLE_STATIC=ON -DLIBCXXABI_ENABLE_STATIC=ON \
    -DLIBCXX_CXX_ABI=libcxxabi -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON \
    -DLIBCXX_ENABLE_FILESYSTEM=OFF -DLIBCXX_ENABLE_RANDOM_DEVICE=ON -DLIBCXX_ENABLE_LOCALIZATION=ON \
    -DLIBCXX_HAS_PTHREAD_API=ON -DLIBCXXABI_HAS_PTHREAD_API=ON \
    -DLIBCXXABI_USE_LLVM_UNWINDER=OFF -DLIBCXXABI_ENABLE_NEW_DELETE_DEFINITIONS=ON \
    -DLIBCXX_INCLUDE_TESTS=OFF -DLIBCXX_INCLUDE_BENCHMARKS=OFF -DLIBCXXABI_INCLUDE_TESTS=OFF \
    -DLIBCXX_INCLUDE_DOCS=OFF > "$work/cmake.log" 2>&1 || { tail -40 "$work/cmake.log"; exit 1; }
ninja -C "$work/build" cxx_static cxxabi_static > "$work/ninja.log" 2>&1 || { grep -B2 -A8 "error:" "$work/ninja.log" | head -80; exit 1; }

# The stub libSystem: every symbol the libraries leave undefined, which
# Perry binds to its own libSystem provider by name. Its object is named
# exit-asm.o, which ld64 lets a dylib omit libSystem for.
lib="$work/build/lib"
"$llvm/llvm-nm" -u "$lib/libc++.a" 2>/dev/null | awk "NF == 2 && \$1 == \"U\" { print \$2 } NF == 1 && \$1 !~ /:\$/ { print \$1 }" \
    | sort -u > "$work/imports.txt"
"$llvm/llvm-nm" --defined-only "$lib/libc++.a" 2>/dev/null | awk "NF == 3 { print \$3 }" | sort -u > "$work/defined.txt"
comm -23 "$work/imports.txt" "$work/defined.txt" | grep -v "^dyld_stub_binder\$" > "$work/system.txt" || true
mkdir -p "$work/stub"
awk "{ printf \"char s%d[16] __asm__(\\\"%s\\\");\\n\", NR, \$1 }" "$work/system.txt" > "$work/stub/stub.c"
echo "void binder(void) __asm__(\"dyld_stub_binder\"); void binder(void) {}" >> "$work/stub/stub.c"
"$llvm/clang" -target "$target" -fno-builtin -w -c "$work/stub/stub.c" -o "$work/stub/exit-asm.o"
"$ld" -arch armv7 -dylib -install_name /usr/lib/libSystem.B.dylib -ios_version_min 10.0 \
    -o "$work/stub/libSystem.dylib" "$work/stub/exit-asm.o" 2>&1 | grep -v "directory not found" || true

# libc++.a holds libc++abi too (LIBCXX_ENABLE_STATIC_ABI_LIBRARY).
rm -f /perry/.build/armv7/bin/libc++.1.dylib
"$ld" -arch armv7 -dylib -ios_version_min 10.0 -install_name /usr/lib/libc++.1.dylib \
    -all_load "$lib/libc++.a" "$work/stub/libSystem.dylib" \
    -o /perry/.build/armv7/bin/libc++.1.dylib > "$work/link.log" 2>&1 || { grep -v "directory not found" "$work/link.log" | head -40; exit 1; }
echo "/perry/.build/armv7/bin/libc++.1.dylib: $(wc -l < "$work/system.txt") imports from libSystem"
'
