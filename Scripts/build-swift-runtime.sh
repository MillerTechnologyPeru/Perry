#!/bin/bash
# Builds Swift's runtime and standard library from swift.org's sources, for a
# runtime directory of Perry's (PERRY_SWIFT_RUNTIME):
#
#   iphoneos-arm64  arm64-apple-ios18.0 (not arm64e), for iOS apps
#   macosx-x86_64   x86_64-apple-macos15.0, for macOS and Mac Catalyst apps
#
# on a Mac with Xcode, or in perry-dev under Scripts/docker-darwin.sh with
# Xcode's SDKs. It is the release Xcode's compiler matches, with
# Scripts/swift-runtime.patch, which lets a build:
#
# - reach thread-local data through pthread_getspecific instead of the
#   register Darwin points at it (TPIDRRO_EL0 on arm64, %gs on x86_64),
#   which Linux leaves zero or uses itself (SWIFT_THREADING_NO_DIRECT_TSD);
# - keep 55 bits of an arm64 isa pointer, as the simulators' runtime does,
#   rather than a device's 36: the classes Perry defines are in its Linux
#   libraries, far above 64 GB (SWIFT_ISA_MASK_OVERRIDE). x86_64's mask
#   already keeps 47 bits;
# - export the prespecializations Apple's own builds add (Dictionary, Set
#   and Array of String, Any and AnyHashable, in Prespecialize.swift) and
#   _StringGuts' inlinable accessors, which the SDKs' Swift interface
#   declares and programs built against it call. Against the SDKs'
#   libswiftCore.tbd only the unused stubs behind two of them, and
#   _availabilityNextMajorVersion, which no inlinable code reads, are
#   missing.
#
# The code is built for ARMv8.0 on arm64, where a device's runtime needs
# ARMv8.3 (pointer authentication).
#
# It runs Swift's CMake itself rather than utils/build-script, which only
# runs on a Mac: first LLVM's, for the tools and headers the standard
# library's build uses (llvm-tblgen, Clang's builtin headers), built for the
# host; then Swift's, for the standard library alone (SWIFT_INCLUDE_TOOLS
# off), with Xcode's (or the image's) compilers. In Linux the build is a
# cross build to Darwin (CMAKE_SYSTEM_NAME), and stand-ins answer for the
# tools CMake asks Xcode for: xcrun (the SDKs' paths and versions), lipo
# (one architecture, so a copy), codesign (ld64.lld signs what it links)
# and install_name_tool (LLVM's objcopy under that name). libswiftDemangle,
# a tool's library there, is compiled apart: SwiftUI links it.
#
# The libraries (the standard library, _Concurrency, _StringProcessing,
# RegexBuilder, Observation, Synchronization, Distributed, Volatile,
# SwiftOnoneSupport, the clang overlays such as _Builtin_float, and
# libswiftDemangle) go to <source>/install/<target>, and into the output
# directory when one is given. Remote Mirror, a debugger's library, is left
# out.
#
# Usage: Scripts/build-swift-runtime.sh <iphoneos-arm64|macosx-x86_64> [output directory]
#   PERRY_SWIFT_SOURCE: where the sources are cloned and built
#     (default .build/swift-source)
#   PERRY_SWIFT_TAG: the release to build (default swift-6.4.2-RELEASE,
#     Xcode 27.2's)
#   PERRY_SWIFT_JOBS: build jobs (default the CPUs')
# The first build clones about 3 GB and takes an hour or more.
set -eu
cd "$(dirname "$0")/.."
. Scripts/darwin-toolchain.sh

target=${1:-}
case $target in
    iphoneos-arm64) sdk_name=IOS os=iphoneos arch=arm64 deployment=18.0 triple=arm64-apple-ios18.0 ;;
    macosx-x86_64) sdk_name=OSX os=macosx arch=x86_64 deployment=15.0 triple=x86_64-apple-macos15.0 ;;
    *) echo "usage: $0 <iphoneos-arm64|macosx-x86_64> [output directory]" >&2; exit 1 ;;
esac
out=${2:-}
patch=$PWD/Scripts/swift-runtime.patch
tag=${PERRY_SWIFT_TAG:-swift-6.4.2-RELEASE}
jobs=${PERRY_SWIFT_JOBS:-$(getconf _NPROCESSORS_ONLN)}
mkdir -p "${PERRY_SWIFT_SOURCE:-.build/swift-source}"
work=$(cd "${PERRY_SWIFT_SOURCE:-.build/swift-source}" && pwd)
build=$work/build/$target
install=$work/install/$target
case $(uname -m) in
    arm64 | aarch64) host_arch=arm64 ;;
    *) host_arch=x86_64 ;;
esac

# The standard library alone needs these four, side by side.
for pair in swift:swift llvm-project:llvm-project swift-cmark:cmark \
            swift-experimental-string-processing:swift-experimental-string-processing; do
    repository=${pair%%:*}
    directory=$work/${pair##*:}
    [ -d "$directory" ] || git clone --depth 1 --branch "$tag" \
        "https://github.com/swiftlang/$repository.git" "$directory"
done
if git -C "$work/swift" apply --check "$patch" 2>/dev/null; then
    git -C "$work/swift" apply "$patch"
elif ! git -C "$work/swift" apply --reverse --check "$patch" 2>/dev/null; then
    echo "Scripts/swift-runtime.patch does not apply to $work/swift" >&2
    exit 1
fi

mkdir -p "$build"
# The compilers and Darwin's tools, as CMake and the standard library's
# build find them.
platform_cmake=()
if [ "$(uname)" = Darwin ]; then
    toolchain=$(dirname "$(darwin_find swiftc)")
    cc=$toolchain/clang cxx=$toolchain/clang++ swiftc=$toolchain/swiftc tools=$toolchain
    lipo=$toolchain/lipo host_cc=$cc host_cxx=$cxx
    # The toolchain's compilers, called by path rather than through xcrun,
    # find no SDK of their own: CMake gives them the host's, and checks
    # only its C compilers (the standard library's Swift is compiled by
    # the build's own rules, with each target's SDK).
    platform_cmake=(-DCMAKE_OSX_SYSROOT="$(darwin_sdk macosx)" -DCMAKE_OSX_ARCHITECTURES="$host_arch"
           -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 -DCMAKE_Swift_COMPILER_WORKS=YES)
else
    tools=$build/tools
    mkdir -p "$tools"
    # LLVM's tools run here: the image's compilers, before the stand-ins
    # below are on PATH.
    host_cc=$(command -v clang) host_cxx=$(command -v clang++)
    ld=$(darwin_find ld)
    for compiler in clang clang++; do
        printf '#!/bin/sh\nexec %s --ld-path=%s -mlinker-version=1100 -resource-dir %s -Wno-unused-command-line-argument "$@"\n' \
            "$(command -v $compiler)" "$ld" "$darwin_clang_resources" > "$tools/$compiler"
    done
    {
        echo '#!/bin/bash'
        echo "# xcrun's answers for Swift's CMake, from Scripts/darwin-toolchain.sh."
        echo ". $PWD/Scripts/darwin-toolchain.sh"
        cat <<'EOF'
sdk=macosx
while [ $# -gt 0 ]; do
    case $1 in
    --sdk | -sdk) sdk=${2%%[0-9]*}; shift 2 ;;
    --toolchain) shift 2 ;;
    --show-sdk-path) darwin_sdk "$sdk"; exit ;;
    --show-sdk-version) darwin_sdk_version "$sdk"; exit ;;
    --show-sdk-platform-path) darwin_platform_path "$sdk"; exit ;;
    --find | -f) command -v "$2" || command -v "llvm-$2"; exit ;;
    *) exec "$@" ;;
    esac
done
EOF
    } > "$tools/xcrun"
    printf '#!/bin/sh\n# One architecture: -create copies its input.\nwhile [ $# -gt 0 ]; do\n    case $1 in -create) shift ;; -output) out=$2; shift 2 ;; *) in=$1; shift ;; esac\ndone\ncp "$in" "$out"\n' > "$tools/lipo"
    printf '#!/bin/sh\n# ld64.lld signs what it links.\nexit 0\n' > "$tools/codesign"
    ln -sf "$(command -v llvm-objcopy)" "$tools/install_name_tool"
    chmod +x "$tools"/*
    export PATH=$tools:$PATH
    cc=$tools/clang cxx=$tools/clang++ swiftc=$(command -v swiftc) lipo=$tools/lipo
    host_sdk=$(darwin_sdk macosx)
    platform_cmake=(-DCMAKE_SYSTEM_NAME=Darwin -DCMAKE_SYSTEM_PROCESSOR="$host_arch"
           -DCMAKE_OSX_SYSROOT="$host_sdk" -DCMAKE_OSX_ARCHITECTURES="$host_arch"
           -DCMAKE_C_COMPILER_TARGET="$host_arch-apple-macosx13.0" -DCMAKE_CXX_COMPILER_TARGET="$host_arch-apple-macosx13.0"
           -DCMAKE_Swift_COMPILER_TARGET="$host_arch-apple-macosx13.0" -DCMAKE_Swift_COMPILER_WORKS=YES
           -DCMAKE_INSTALL_NAME_TOOL="$tools/install_name_tool"
           -DCMAKE_AR="$(command -v llvm-ar)" -DCMAKE_RANLIB="$(command -v llvm-ranlib)"
           "-DCMAKE_IGNORE_PATH=/usr/lib;/usr/local/lib;/lib")
fi

# LLVM, for the host.
if [ ! -f "$build/llvm/build.ninja" ]; then
    cmake -G Ninja -S "$work/llvm-project/llvm" -B "$build/llvm" \
        -DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_ASSERTIONS=FALSE \
        -DCMAKE_C_COMPILER="$host_cc" -DCMAKE_CXX_COMPILER="$host_cxx" \
        "-DLLVM_TARGETS_TO_BUILD=AArch64;X86" "-DLLVM_ENABLE_PROJECTS=clang" \
        -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF -DLLVM_INCLUDE_DOCS=OFF \
        -DCLANG_INCLUDE_TESTS=OFF -DLLVM_ENABLE_ZSTD=OFF -DLLVM_ENABLE_LIBXML2=OFF -DLLVM_ENABLE_TERMINFO=OFF
fi
ninja -C "$build/llvm" -j "$jobs" llvm-tblgen clang-resource-headers intrinsics_gen clang-tablegen-targets

# The standard library: the flags utils/build-script gives a release build of
# it, for this one target.
c_flags="-DSWIFT_THREADING_NO_DIRECT_TSD=1"
[ "$arch" = arm64 ] && c_flags="$c_flags;-DSWIFT_ISA_MASK_OVERRIDE=0x007ffffffffffff8ULL"
if [ ! -f "$build/swift/build.ninja" ]; then
    cmake -G Ninja -S "$work/swift" -B "$build/swift" ${platform_cmake[@]+"${platform_cmake[@]}"} \
        -DCMAKE_C_COMPILER="$cc" -DCMAKE_CXX_COMPILER="$cxx" -DCMAKE_Swift_COMPILER="$swiftc" \
        -DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_ASSERTIONS=FALSE -DCMAKE_INSTALL_PREFIX=/usr \
        -DLLVM_DIR="$build/llvm/lib/cmake/llvm" -DClang_DIR="$build/llvm/lib/cmake/clang" \
        -DSWIFT_PATH_TO_CMARK_SOURCE="$work/cmark" \
        -DSWIFT_PATH_TO_STRING_PROCESSING_SOURCE="$work/swift-experimental-string-processing" \
        -DSWIFT_HOST_VARIANT=macosx -DSWIFT_HOST_VARIANT_SDK=OSX -DSWIFT_HOST_VARIANT_ARCH="$host_arch" \
        -DSWIFT_HOST_TRIPLE="$host_arch-apple-macosx13.0" -DSWIFT_USE_LINKER= \
        -DSWIFT_SDKS="$sdk_name" -DSWIFT_DARWIN_SUPPORTED_ARCHS="$arch" \
        -DSWIFT_DARWIN_DEPLOYMENT_VERSION_OSX=13.0 -DSWIFT_DARWIN_DEPLOYMENT_VERSION_IOS=18.0 \
        -DSWIFT_DARWIN_DEPLOYMENT_VERSION_"$sdk_name"="$deployment" \
        -DSWIFT_NATIVE_LLVM_TOOLS_PATH="$tools" -DSWIFT_NATIVE_CLANG_TOOLS_PATH="$tools" \
        -DSWIFT_NATIVE_SWIFT_TOOLS_PATH="$(dirname "$swiftc")" \
        -DSWIFT_LIPO="$lipo" -DSWIFT_DARWIN_XCRUN_TOOLCHAIN=default \
        -DSWIFT_INCLUDE_TOOLS=FALSE -DSWIFT_INCLUDE_TESTS=FALSE -DSWIFT_INCLUDE_DOCS=FALSE \
        -DSWIFT_INCLUDE_APINOTES=FALSE -DSWIFT_BUILD_EXAMPLES=FALSE -DSWIFT_BUILD_LIBEXEC=FALSE \
        -DSWIFT_BUILD_REMOTE_MIRROR=FALSE -DSWIFT_BUILD_CLANG_OVERLAYS=TRUE \
        -DSWIFT_BUILD_DYNAMIC_STDLIB=TRUE -DSWIFT_BUILD_STATIC_STDLIB=FALSE \
        -DSWIFT_BUILD_DYNAMIC_SDK_OVERLAY=FALSE -DSWIFT_BUILD_STATIC_SDK_OVERLAY=FALSE \
        -DSWIFT_SHOULD_BUILD_EMBEDDED_STDLIB=FALSE -DSWIFT_SHOULD_BUILD_EMBEDDED_STDLIB_CROSS_COMPILING=FALSE \
        -DSWIFT_ENABLE_EXPERIMENTAL_DIFFERENTIABLE_PROGRAMMING=TRUE -DSWIFT_ENABLE_EXPERIMENTAL_CONCURRENCY=TRUE \
        -DSWIFT_ENABLE_EXPERIMENTAL_CXX_INTEROP=TRUE -DSWIFT_ENABLE_CXX_INTEROP_SWIFT_BRIDGING_HEADER=TRUE \
        -DSWIFT_ENABLE_EXPERIMENTAL_DISTRIBUTED=TRUE -DSWIFT_ENABLE_BACKTRACING=TRUE \
        -DSWIFT_ENABLE_EXPERIMENTAL_OBSERVATION=TRUE -DSWIFT_ENABLE_SYNCHRONIZATION=TRUE \
        -DSWIFT_ENABLE_VOLATILE=TRUE -DSWIFT_ENABLE_RUNTIME_MODULE=TRUE \
        -DSWIFT_ENABLE_EXPERIMENTAL_STRING_PROCESSING=TRUE -DSWIFT_ENABLE_NEW_RUNTIME_BUILD=FALSE \
        -DSWIFT_STDLIB_BUILD_TYPE=Release -DSWIFT_STDLIB_ASSERTIONS=FALSE \
        -DSWIFT_STDLIB_ENABLE_STDLIBCORE_EXCLUSIVITY_CHECKING=FALSE \
        -DSWIFT_STDLIB_BUILD_PRIVATE=TRUE -DSWIFT_STDLIB_ENABLE_UNICODE_DATA=TRUE \
        -DSWIFT_STDLIB_STATIC_PRINT=FALSE -DSWIFT_FREESTANDING_IS_DARWIN=FALSE \
        -DSWIFT_STDLIB_SUPPORT_BACK_DEPLOYMENT=TRUE -DSWIFT_STDLIB_OVERRIDABLE_RETAIN_RELEASE=TRUE \
        -DSWIFT_ENABLE_DISPATCH=TRUE -DSWIFT_IMPLICIT_CONCURRENCY_IMPORT=TRUE \
        -DSWIFT_STDLIB_EXTRA_C_COMPILE_FLAGS="$c_flags" \
        "-DSWIFT_STDLIB_EXTRA_SWIFT_COMPILE_FLAGS=-Xcc;-DSWIFT_THREADING_NO_DIRECT_TSD=1" \
        -DPKG_CONFIG_EXECUTABLE=/usr/bin/false
fi
ninja -C "$build/swift" -j "$jobs" "swift-stdlib-$os"

# libswiftDemangle: lib/Demangling and lib/SwiftDemangle, as the compiler's
# build links them (their CMakeLists.txt), over LLVM's headers.
demangle=$build/demangle
objects=()
for source in Demangling/{Demangler,Context,ManglingUtils,NodeDumper,NodePrinter,OldDemangler,OldRemangler,Punycode,Remangler,DemanglingErrorHandling,CrashReporter}.cpp \
              SwiftDemangle/{SwiftDemangle,MangleHack}.cpp; do
    object=$demangle/${source%.cpp}.o
    source=$work/swift/lib/$source
    mkdir -p "$(dirname "$object")"
    if [ ! -f "$object" ] || [ "$source" -nt "$object" ]; then
        darwin_clangxx "$os" -target "$triple" -isysroot "$(darwin_sdk "$os")" \
            -std=c++17 -O2 -fPIC -fno-exceptions -fno-rtti -DNDEBUG -DLLVM_DISABLE_ABI_BREAKING_CHECKS_ENFORCING=1 \
            -DSWIFT_SUPPORT_OLD_MANGLING=1 -DSWIFT_STDLIB_HAS_TYPE_PRINTING=1 \
            -I "$work/swift/include" -I "$build/swift/include" \
            -I "$work/llvm-project/llvm/include" -I "$build/llvm/include" \
            -c "$source" -o "$object"
    fi
    objects+=("$object")
done
darwin_clangxx "$os" -target "$triple" -isysroot "$(darwin_sdk "$os")" \
    -dynamiclib -install_name /usr/lib/swift/libswiftDemangle.dylib "${objects[@]}" \
    -o "$build/swift/lib/swift/$os/libswiftDemangle.dylib"

# The libraries, not the links to them (libswiftCompatibilitySpan is one to
# libswiftCore).
rm -rf "$install"
mkdir -p "$install"
for library in "$build/swift/lib/swift/$os"/*.dylib; do
    [ -L "$library" ] && continue
    cp "$library" "$install/"
done
if [ -n "$out" ]; then
    mkdir -p "$out"
    cp "$install"/*.dylib "$out/"
fi
echo "$install: $(ls "$install" | wc -l | tr -d ' ') libraries"
