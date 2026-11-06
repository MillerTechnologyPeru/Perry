#!/bin/sh
# Builds armv7 providers with SwiftPM, cross-compiling in the arm64 Linux
# container with the Swift 6.4.0 toolchain and the armv7 SDK under
# .toolchains. SwiftPM builds the macros and the provider generator for the
# host and runs them itself. Products go to
# .build/armv7-pm/armv7-unknown-linux-gnueabihf/release, optimized like the
# Swift runtime they run with, which has no SwiftOnoneSupport on armv7
# machines (PERRY_CONFIGURATION=debug builds them unoptimized), and are
# copied to .build/armv7/bin beside perry32, where it looks for providers.
# Usage: Scripts/build-armv7-swiftpm.sh [product...]
#   (default: Perryobjc Perrydispatch PerryFoundation; Foundation's provider loads
#   libdispatch's). Mac-only providers (PerryAppKit, PerryIOKit,
#   Perrysteam_api) are refused.
# swift-syntax needs several GB of memory to build; a 4 GB machine is not enough.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
[ $# -gt 0 ] || set -- Perryobjc Perrydispatch PerryFoundation

# armv7 runs iOS apps, so the providers only Mac apps load are not built
# for it: AppKit, IOKit and Steam's API.
for product; do
    case $product in
    PerryAppKit|PerryIOKit|Perrysteam_api)
        echo "$0: $product is for Mac apps and is not built for armv7" >&2
        exit 2 ;;
    esac
done

# Paths as the container sees the checkout, at /perry.
swift=$(cd .toolchains && ls -d swift-6.4.0-RELEASE-*/usr/bin | head -1)
sdk=$(cd .toolchains && ls -d swift-*-armv7-sdk/*/debian-* | head -1)
swift=/perry/.toolchains/$swift sdk=/perry/.toolchains/$sdk

# r9 is fixed (-ffixed-r9): Darwin's armv7 code treats it as a scratch
# register, which Linux's preserves across calls, so Perry's code never keeps
# a value in it across a call into Darwin code.
mkdir -p .build/armv7
cat > .build/armv7/destination.json <<EOF
{
   "version": 1,
   "sdk": "$sdk",
   "toolchain-bin-dir": "$swift",
   "target": "armv7-unknown-linux-gnueabihf",
   "dynamic-library-extension": "so",
   "extra-cc-flags": ["-march=armv7-a", "-mfpu=neon", "-mfloat-abi=hard", "-D_FILE_OFFSET_BITS=64", "-fPIC", "-ffixed-r9"],
   "extra-swiftc-flags": [
      "-target", "armv7-unknown-linux-gnueabihf", "-use-ld=lld",
      "-Xcc", "--gcc-toolchain=$sdk/usr", "-Xcc", "-ffixed-r9",
      "-Xlinker", "-rpath", "-Xlinker", "/usr/lib/swift/linux",
      "-Xlinker", "-rpath", "-Xlinker", "/usr/lib/swift/linux/armv7",
      "-resource-dir", "$sdk/usr/lib/swift", "-sdk", "$sdk", "-latomic"
   ],
   "extra-cpp-flags": []
}
EOF

# pkg-config reads the SDK's .pc files, so system libraries (libxml2) link
# the SDK's armv7 builds rather than the container's arm64 ones.
pc=$sdk/usr/lib/arm-linux-gnueabihf/pkgconfig:$sdk/usr/share/pkgconfig
configuration=${PERRY_CONFIGURATION:-release}
docker run --rm --platform linux/arm64 -v "$root:/perry" \
    -e PKG_CONFIG_SYSROOT_DIR="$sdk" -e PKG_CONFIG_LIBDIR="$pc" -e PKG_CONFIG_PATH="$pc" \
    perry-dev sh -c '
        swift=$1 configuration=$2; shift 2
        for product; do
            "$swift/swift" build --build-system native --destination .build/armv7/destination.json \
                --scratch-path .build/armv7-pm -c "$configuration" --product "$product" || exit
        done' sh "$swift" "$configuration" "$@"
mkdir -p .build/armv7/bin
for product; do
    cp ".build/armv7-pm/armv7-unknown-linux-gnueabihf/$configuration/lib$product.so" .build/armv7/bin/
done
