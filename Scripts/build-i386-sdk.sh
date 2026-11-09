#!/bin/sh
# Builds Swift's runtime, libdispatch and Foundation for i686 Linux, which
# Swift does not ship, into .toolchains/i386-sdk/sysroot: an SDK for building
# Perry's providers as 32-bit x86 programs. The compiler is the one in the
# perry-dev image; the libraries are built from the Swift sources of its exact
# version, against Debian's i386 packages.
#
# Takes about an hour and 15 GB. Usage: Scripts/build-i386-sdk.sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
tag=${PERRY_SWIFT_TAG:-swift-6.4.2-RELEASE}
work=$root/.toolchains/i386-sdk
mkdir -p "$work/src"

# The C libraries, from Debian's i386 packages, with absolute links made
# relative so the sysroot can move.
if [ ! -e "$work/sysroot/usr/include/stdio.h" ]; then
    mkdir -p "$work/sysroot"
    docker run --rm --platform linux/386 -e OWNER="$(id -u):$(id -g)" -v "$work/sysroot:/out" debian:trixie sh -euc '
        apt-get update -qq
        apt-get install -y -qq --no-install-recommends libc6-dev libgcc-14-dev libstdc++-14-dev libstdc++6 \
            linux-libc-dev zlib1g-dev libicu-dev libcurl4-openssl-dev libxml2-dev libsystemd-dev >/dev/null 2>&1
        tar -C / -cf - usr/include usr/lib lib 2>/dev/null | tar -C /out -xf -
        find /out -type l | while read -r link; do
            target=$(readlink "$link")
            case $target in /*) ln -sfnr "/out$target" "$link" ;; esac
        done
        chown -R "$OWNER" /out'
fi

for repository in swift llvm-project swift-syntax swift-experimental-string-processing \
    swift-corelibs-libdispatch swift-corelibs-foundation swift-foundation swift-foundation-icu; do
    [ -d "$work/src/$repository/.git" ] ||
        git clone -q --depth 1 --branch "$tag" "https://github.com/swiftlang/$repository.git" "$work/src/$repository"
done
# Versioned on its own; the release's update-checkout configuration says which.
[ -d "$work/src/swift-collections/.git" ] ||
    git clone -q --depth 1 --branch "1.1.6" https://github.com/apple/swift-collections.git "$work/src/swift-collections"

docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$root:/perry" --entrypoint bash perry-dev -euxc '
    work=/perry/.toolchains/i386-sdk src=$work/src sysroot=$work/sysroot build=$work/build
    target=i686-unknown-linux-gnu
    mkdir -p $build
    gcc=$(dirname "$(find $sysroot -name crtbegin.o | head -1)")

    # Darwin requires SSE2 of every Intel Mac, and files are always large.
    extra="-march=i686 -msse2 -mfpmath=sse -D_FILE_OFFSET_BITS=64"
    cflags="-w -fuse-ld=lld --sysroot=$sysroot --gcc-install-dir=$gcc -target $target $extra"
    linkflags="--sysroot=$sysroot --gcc-install-dir=$gcc -target $target $extra"
    swiftcc=""
    for flag in $extra; do swiftcc="$swiftcc -Xcc $flag"; done
    swiftflags="-target $target -use-ld=lld -sdk $sysroot -resource-dir $build/swift/lib/swift $swiftcc"

    toolchain=$build/toolchain.cmake
    cat > $toolchain <<EOT
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR i686)
set(CMAKE_SYSROOT $sysroot)
set(CMAKE_LIBRARY_ARCHITECTURE i386-linux-gnu)
set(CMAKE_C_COMPILER_TARGET $target)
set(CMAKE_CXX_COMPILER_TARGET $target)
set(CMAKE_Swift_COMPILER_TARGET $target)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
EOT

    # Only configured: the runtime reads its CMake modules.
    cmake -S $src/llvm-project/llvm -B $build/llvm -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ -DLLVM_TARGETS_TO_BUILD=X86 -DLLVM_ENABLE_PROJECTS=llvm

    runtime_swiftflags=$(echo $swiftcc | tr " " ";")
    cmake -S $src/swift -B $build/swift -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON \
        -DCMAKE_INSTALL_PREFIX=$sysroot/usr \
        -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
        -DCMAKE_C_FLAGS="$cflags" -DCMAKE_CXX_FLAGS="$cflags" \
        -DCMAKE_C_LINK_FLAGS="$linkflags" -DCMAKE_CXX_LINK_FLAGS="$linkflags" \
        -DCMAKE_SYSROOT=$sysroot -DCMAKE_OSX_SYSROOT= \
        -DCMAKE_Swift_FLAGS_DEBUG= -DCMAKE_Swift_FLAGS_RELEASE= -DCMAKE_Swift_FLAGS_RELWITHDEBINFO= \
        -DLLVM_DIR=$build/llvm/lib/cmake/llvm -DLLVM_BUILD_LIBRARY_DIR=$build/llvm -DLLVM_USE_LINKER=lld \
        -DSWIFT_USE_LINKER=lld -DSWIFT_BUILD_RUNTIME_WITH_HOST_COMPILER=ON \
        -DSWIFT_NATIVE_CLANG_TOOLS_PATH=/usr/bin -DSWIFT_NATIVE_SWIFT_TOOLS_PATH=/usr/bin \
        -DSWIFT_HOST_VARIANT_ARCH=i686 -DSWIFT_SDKS=LINUX -DSWIFT_SDK_LINUX_ARCH_i686_PATH=$sysroot \
        -DSWIFT_SDK_LINUX_CXX_OVERLAY_SWIFT_COMPILE_FLAGS= \
        -DSWIFT_INCLUDE_TOOLS=OFF -DSWIFT_INCLUDE_DOCS=OFF -DSWIFT_INCLUDE_TESTS=OFF \
        -DSWIFT_INCLUDE_TEST_BINARIES=OFF -DSWIFT_BUILD_TEST_SUPPORT_MODULES=OFF \
        -DSWIFT_BUILD_DYNAMIC_STDLIB=ON -DSWIFT_BUILD_DYNAMIC_SDK_OVERLAY=ON -DSWIFT_BUILD_STATIC_STDLIB=OFF \
        -DSWIFT_BUILD_REMOTE_MIRROR=OFF -DSWIFT_BUILD_STDLIB_EXTRA_TOOLCHAIN_CONTENT=ON \
        -DSWIFT_SHOULD_BUILD_EMBEDDED_STDLIB=OFF \
        -DSWIFT_PATH_TO_LIBDISPATCH_SOURCE=$src/swift-corelibs-libdispatch \
        -DSWIFT_PATH_TO_SWIFT_SYNTAX_SOURCE=$src/swift-syntax \
        -DSWIFT_PATH_TO_STRING_PROCESSING_SOURCE=$src/swift-experimental-string-processing \
        -DSWIFT_ENABLE_EXPERIMENTAL_CONCURRENCY=ON -DSWIFT_ENABLE_EXPERIMENTAL_STRING_PROCESSING=ON \
        -DSWIFT_ENABLE_EXPERIMENTAL_OBSERVATION=ON -DSWIFT_ENABLE_EXPERIMENTAL_NONESCAPABLE_TYPES=ON \
        -DSWIFT_ENABLE_SYNCHRONIZATION=ON -DSWIFT_ENABLE_VOLATILE=ON \
        -DSWIFT_ENABLE_EXPERIMENTAL_DIFFERENTIABLE_PROGRAMMING=OFF -DSWIFT_ENABLE_EXPERIMENTAL_DISTRIBUTED=OFF \
        -DSWIFT_ENABLE_EXPERIMENTAL_CXX_INTEROP=OFF -DSWIFT_BUILD_STDLIB_CXX_MODULE=OFF \
        -DSWIFT_THREADING_PACKAGE=c11 \
        -DSWIFT_RUNTIME_SWIFT_COMPILE_FLAGS="$runtime_swiftflags" \
        -DSWIFT_STDLIB_EXTRA_SWIFT_COMPILE_FLAGS="$runtime_swiftflags"
    # install does not build the C++ interop files it copies; this target does.
    ninja -C $build/swift swift-stdlib-linux install

    common() {
        cmake -S "$1" -B "$2" -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DBUILD_SHARED_LIBS=ON \
            -DCMAKE_INSTALL_PREFIX=$sysroot/usr -DCMAKE_TOOLCHAIN_FILE=$toolchain \
            -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
            -DCMAKE_C_FLAGS="$cflags" -DCMAKE_CXX_FLAGS="$cflags" \
            -DCMAKE_C_LINK_FLAGS="$linkflags" -DCMAKE_CXX_LINK_FLAGS="$linkflags" \
            -DCMAKE_Swift_FLAGS="$swiftflags" \
            -DCMAKE_Swift_FLAGS_DEBUG= -DCMAKE_Swift_FLAGS_RELEASE= -DCMAKE_Swift_FLAGS_RELWITHDEBINFO= "${@:3}"
    }
    common $src/swift-corelibs-libdispatch $build/dispatch -DENABLE_SWIFT=YES
    ninja -C $build/dispatch install

    common $src/swift-corelibs-foundation $build/foundation -DCF_DEPLOYMENT_SWIFT=ON \
        -Ddispatch_DIR=$build/dispatch/cmake/modules \
        -DSwiftFoundation_MACRO=/usr/lib/swift/host/plugins/libFoundationMacros.so \
        -D_SwiftFoundation_SourceDIR=$src/swift-foundation \
        -D_SwiftFoundationICU_SourceDIR=$src/swift-foundation-icu \
        -D_SwiftCollections_SourceDIR=$src/swift-collections
    ninja -C $build/foundation install
'
echo "$work/sysroot"
