#!/bin/sh
# Builds libPerryobjc.so for armv7, the provider for libobjc, into
# .build/armv7/bin: the C and assembly of CPerryObjC, CPerryObjCInterop and
# PerryInterface with clang, then the Swift modules PerryObjCInterop,
# PerryObjCRuntime and PerryObjC with the armv7 SDK and the host Swift
# toolchain of its version (PERRY_SWIFT, its bin directory).
# PerryObjCInterop's macros run on the host: build them first with
# Scripts/build-host-macros.sh, or name SwiftPM's build of them in
# PERRY_OBJC_MACROS: .build/linux/debug/PerryObjCMacros after Perry's own
# debug build in the perry-dev image.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
llvm=${PERRY_LLVM_BIN:-$(ls -d "$root"/.toolchains/LLVM-*/bin | head -1)}
swift=${PERRY_SWIFT:-$(ls -d "$root"/.toolchains/swift-6.4.0-RELEASE-*/usr/bin | head -1)}
sdk=${PERRY_ARMV7_SDK:-$(ls -d "$root"/.toolchains/swift-*-armv7-sdk/*/debian-* | head -1)}
out=$root/.build/armv7
mkdir -p "$out/bin" "$out/obj" "$out/modules" "$out/include/CPerryObjC" "$out/include/CPerryObjCInterop" \
    "$out/include/PerryInterface"

macros=${PERRY_OBJC_MACROS:-$root/.build/macros/PerryObjCMacros}
[ -x "$macros" ] || { echo "build the macro plugin first: Scripts/build-host-macros.sh" >&2; exit 1; }

# r9 is fixed (-ffixed-r9): Darwin's armv7 code treats it as a scratch
# register, which Linux's preserves across calls, so Perry's code never keeps
# a value in it across a call into Darwin code.
clang_flags="--target=armv7-linux-gnueabihf --sysroot=$sdk -march=armv7-a -mfloat-abi=hard -fPIC -O1 -g -D_GNU_SOURCE -ffixed-r9"
for name in msgsend_arm.S trampolines.c data.c exceptions_arm.c; do
    "$llvm/clang" $clang_flags -I"$root/Sources/CPerryObjC/include" -c "$root/Sources/CPerryObjC/$name" \
        -o "$out/obj/cobjc-$name.o"
done
# PerryInterface's C, which PerryObjC calls (perry_print_frames).
"$llvm/clang" $clang_flags -I"$root/Sources/PerryInterface/include" -c "$root/Sources/PerryInterface/interface.c" \
    -o "$out/obj/objc-interface.c.o"
for source in "$root"/Sources/CPerryObjCInterop/*.c; do
    "$llvm/clang" $clang_flags -I"$root/Sources/CPerryObjCInterop/include" -c "$source" \
        -o "$out/obj/cinterop-$(basename "$source").o"
done

# Clang modules for the C targets, as SwiftPM would make them.
cp "$root/Sources/CPerryObjC/include/CPerryObjC.h" "$out/include/CPerryObjC/"
printf 'module CPerryObjC { header "CPerryObjC.h" export * }\n' > "$out/include/CPerryObjC/module.modulemap"
cp "$root/Sources/CPerryObjCInterop/include/CPerryObjCInterop.h" "$out/include/CPerryObjCInterop/"
printf 'module CPerryObjCInterop { header "CPerryObjCInterop.h" export * }\n' \
    > "$out/include/CPerryObjCInterop/module.modulemap"
cp "$root/Sources/PerryInterface/include/perry_interface.h" "$out/include/PerryInterface/"
printf 'module PerryInterface { header "perry_interface.h" export * }\n' > "$out/include/PerryInterface/module.modulemap"

swiftc() {
    "$swift/swiftc" -target armv7-unknown-linux-gnueabihf -use-ld=lld -sdk "$sdk" \
        -resource-dir "$sdk/usr/lib/swift" -Xcc --gcc-toolchain="$sdk/usr" -Xcc -ffixed-r9 \
        -tools-directory "$swift" \
        -I "$out/include/CPerryObjC" -I "$out/include/CPerryObjCInterop" -I "$out/include/PerryInterface" \
        -I "$out/modules" \
        -load-plugin-executable "$macros#PerryObjCMacros" \
        -O -wmo -parse-as-library "$@"
}

module() {     # module name, source directory, extra swiftc arguments
    name=$1 dir=$2
    shift 2
    swiftc -module-name "$name" -emit-module -emit-module-path "$out/modules/$name.swiftmodule" \
        -c -o "$out/obj/$name.o" "$root/Sources/$dir"/*.swift "$@"
}

module PerryObjCInterop PerryObjCInterop
module PerryObjCRuntime PerryObjCRuntime
module PerryObjC PerryObjC

"$swift/swiftc" -target armv7-unknown-linux-gnueabihf -use-ld=lld -sdk "$sdk" \
    -resource-dir "$sdk/usr/lib/swift" -Xcc --gcc-toolchain="$sdk/usr" -tools-directory "$swift" -latomic \
    -emit-library -o "$out/bin/libPerryobjc.so" \
    "$out/obj/PerryObjC.o" "$out/obj/PerryObjCRuntime.o" "$out/obj/PerryObjCInterop.o" \
    "$out"/obj/cobjc-*.o "$out"/obj/cinterop-*.o "$out/obj/objc-interface.c.o" \
    -Xlinker -z -Xlinker defs -Xlinker -rpath -Xlinker '$ORIGIN'
echo "$out/bin/libPerryobjc.so"
