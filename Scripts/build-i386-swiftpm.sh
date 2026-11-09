#!/bin/sh
# Builds i386 providers with SwiftPM, cross-compiling in the perry-dev image
# against the SDK of Scripts/build-i386-sdk.sh. SwiftPM builds the macros and
# the provider generator for the host and runs them itself. Products are copied
# to .build/i386/bin beside perry32, where it looks for providers.
# Usage: Scripts/build-i386-swiftpm.sh [product...]   (default: Perryobjc)
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
[ $# -gt 0 ] || set -- Perryobjc
sdk=/perry/.toolchains/i386-sdk/sysroot
gcc=$(cd .toolchains/i386-sdk/sysroot && dirname "$(find usr/lib/gcc -name crtbegin.o | head -1)")
mkdir -p .build/i386/bin
# -freg-struct-return: small structures come back in eax:edx, as Darwin returns
# them, where Linux's i386 ABI returns them through a pointer.
cat > .build/i386/destination.json <<EOF
{
   "version": 1,
   "sdk": "$sdk",
   "toolchain-bin-dir": "/usr/bin",
   "target": "i686-unknown-linux-gnu",
   "dynamic-library-extension": "so",
   "extra-cc-flags": ["-march=i686", "-msse2", "-mfpmath=sse", "-D_FILE_OFFSET_BITS=64", "-fPIC", "-freg-struct-return", "--gcc-install-dir=$sdk/$gcc"],
   "extra-swiftc-flags": [
      "-target", "i686-unknown-linux-gnu", "-use-ld=lld",
      "-Xcc", "-freg-struct-return", "-Xcc", "-msse2", "-Xcc", "-D_FILE_OFFSET_BITS=64", "-Xcc", "--gcc-install-dir=$sdk/$gcc",
      "-Xclang-linker", "--gcc-install-dir=$sdk/$gcc",
      "-Xlinker", "-rpath", "-Xlinker", "$sdk/usr/lib/swift/linux",
      "-resource-dir", "$sdk/usr/lib/swift", "-sdk", "$sdk", "-latomic"
   ],
   "extra-cpp-flags": []
}
EOF
pc=$sdk/usr/lib/i386-linux-gnu/pkgconfig:$sdk/usr/share/pkgconfig
configuration=${PERRY_CONFIGURATION:-release}
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$root:/perry" -w /perry \
    -e PKG_CONFIG_SYSROOT_DIR="$sdk" -e PKG_CONFIG_LIBDIR="$pc" -e PKG_CONFIG_PATH="$pc" \
    --entrypoint sh perry-dev -c '
        configuration=$1; shift
        for product; do
            swift build --build-system native --destination .build/i386/destination.json \
                --scratch-path .build/i386-pm -c "$configuration" --product "$product" || exit
        done' sh "$configuration" "$@"
for product; do
    cp ".build/i386-pm/i686-unknown-linux-gnu/$configuration/lib$product.so" .build/i386/bin/
done
