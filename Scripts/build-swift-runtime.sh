#!/bin/sh
# Builds Swift's runtime and standard library for iOS arm64 (not arm64e) from
# swift.org's sources, on a Mac with Xcode, for Scripts/swift-runtime.sh to
# use in place of the iOS Simulator runtime's. It is the release Xcode's
# compiler matches, with Scripts/swift-runtime.patch, which lets a build:
#
# - reach thread-local data through pthread_getspecific instead of the
#   TPIDRRO_EL0 register Darwin points at it, which Linux leaves zero
#   (SWIFT_THREADING_NO_DIRECT_TSD);
# - keep 55 bits of an isa pointer, as the simulators' runtime does, rather
#   than a device's 36: the classes Perry defines are in its Linux libraries,
#   far above 64 GB (SWIFT_ISA_MASK_OVERRIDE).
#
# The code is built for ARMv8.0, where the simulator runtime needs ARMv8.3.
#
# Usage: Scripts/build-swift-runtime.sh [build-script options]
#   PERRY_SWIFT_SOURCE: where the sources are cloned and built
#     (default .build/swift-source); the libraries are installed in its
#     install/usr/lib/swift/iphoneos
#   PERRY_SWIFT_TAG: the release to build (default swift-6.4.2-RELEASE)
# The first build clones about 3 GB and takes a few hours.
set -eu
cd "$(dirname "$0")/.."
[ "$(uname)" = Darwin ] || { echo "needs macOS with Xcode" >&2; exit 1; }

patch=$PWD/Scripts/swift-runtime.patch
tag=${PERRY_SWIFT_TAG:-swift-6.4.2-RELEASE}
mkdir -p "${PERRY_SWIFT_SOURCE:-.build/swift-source}"
work=$(cd "${PERRY_SWIFT_SOURCE:-.build/swift-source}" && pwd)

# The standard library alone needs these four; build-script expects them
# side by side, under these names.
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

toolchain=$(dirname "$(xcrun --find swiftc)")
cd "$work/swift"
exec utils/build-script \
    --release --no-assertions \
    --skip-build-llvm --skip-build-cmark --skip-build-benchmarks \
    --build-swift-tools=0 --build-swift-libexec=0 \
    --skip-early-swift-driver --skip-early-swiftsyntax --build-embedded-stdlib=0 \
    --native-swift-tools-path="$toolchain" --native-llvm-tools-path="$toolchain" --native-clang-tools-path="$toolchain" \
    --ios --skip-build-ios-simulator --skip-build-osx \
    --stdlib-deployment-targets=iphoneos-arm64 --swift-darwin-supported-archs=arm64 \
    --darwin-deployment-version-ios=18.0 \
    --build-subdir=perry-ios \
    --install-swift --install-destdir="$work/install" --install-prefix=/usr \
    --swift-install-components='stdlib;sdk-overlay;back-deployment' \
    --extra-cmake-options="-DSWIFT_STDLIB_EXTRA_C_COMPILE_FLAGS=-DSWIFT_THREADING_NO_DIRECT_TSD=1;-DSWIFT_ISA_MASK_OVERRIDE=0x007ffffffffffff8ULL,-DSWIFT_STDLIB_EXTRA_SWIFT_COMPILE_FLAGS=-Xcc;-DSWIFT_THREADING_NO_DIRECT_TSD=1" \
    "$@"
