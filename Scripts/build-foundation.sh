#!/bin/bash
# Builds Perry's Swift Foundation on a Mac with Xcode: swift-foundation, from
# the perry branch of MillerTechnologyPeru/swift-foundation, compiled as one
# module named Foundation, as Apple's Foundation.framework carries it. Its
# FoundationEssentials and FoundationInternationalization sources are
# compiled together for iOS arm64 with library evolution, so apps and
# SwiftUI built against Apple's SDK bind to it by the same Swift symbols
# ($s10Foundation...), and linked with ICU and swift-collections into
# libswiftFoundation.dylib in the directory given.
#
# The Swift module is built over the SDK's Objective-C Foundation headers,
# as Apple's Foundation overlay is, and takes in Darwin/Foundation: Perry's
# bridging between the two, the part of Apple's Foundation that
# swift-foundation leaves to Apple's own build.
#
# Usage: [PERRY_OVERLAY_PLATFORM=macosx] [PERRY_OVERLAY_TARGET=<triple>] Scripts/build-foundation.sh [output directory]
#   default output: .build/perry-foundation/out
#   PERRY_OVERLAY_PLATFORM and PERRY_OVERLAY_TARGET name another SDK and
#   target, as for Scripts/build-overlay.sh: macosx and
#   x86_64-apple-macos15.0 for a Mac app on x86_64.
set -eu
cd "$(dirname "$0")/.."
[ "$(uname)" = Darwin ] || { echo "needs macOS with Xcode" >&2; exit 1; }

root=$PWD
work=$root/.build/perry-foundation
out=${1:-$work/out}
case $out in /*) ;; *) out=$root/$out ;; esac
platform=${PERRY_OVERLAY_PLATFORM:-iphoneos}
sdk=$(xcrun --sdk "$platform" --show-sdk-path)
target=${PERRY_OVERLAY_TARGET:-arm64-apple-ios18.0}
mkdir -p "$work" "$out"

# swift-foundation and its packages, side by side as its manifest expects
# with SWIFTCI_USE_LOCAL_DEPS.
fetch() { # directory url commit
    [ -e "$1/.perry-commit" ] && [ "$(cat "$1/.perry-commit")" = "$3" ] && return
    rm -rf "$1"; mkdir -p "$1"
    git -C "$1" init -q
    git -C "$1" fetch -q --depth 1 "$2" "$3"
    git -C "$1" checkout -q FETCH_HEAD
    echo "$3" > "$1/.perry-commit"
}
packages=$work/packages
fetch "$packages/swift-foundation" \
    https://github.com/MillerTechnologyPeru/swift-foundation.git 83a9a7a7f6ce5aa3e253c9fa720df0f12f95b871
fetch "$packages/swift-collections" \
    https://github.com/apple/swift-collections.git c11818f3cae0780656baa430b49e7f163f08dffd
fetch "$packages/swift-foundation-icu" \
    https://github.com/swiftlang/swift-foundation-icu.git e29ee41079d35eae68d98a7479864a19f2928d84
fetch "$packages/swift-syntax" \
    https://github.com/swiftlang/swift-syntax.git 79e4b74a295b6eb74a8b585e3a39d29e70c1dbd1
foundation=$packages/swift-foundation

# The package build gives the C shims, ICU and swift-collections as objects
# for the target, and the Foundation macros as a plugin for this Mac. The
# native build system separates host and target products and keeps ARM
# CPU flags out of host macro compilations. Each target's objects are in
# its own <Target>.build directory.
export SWIFTCI_USE_LOCAL_DEPS=1
# Keep ARM target CPU flags separate from the macOS macro tools.
spm=(--build-system native --scratch-path "$work/spm-$target")
# An arm64 target's code is for apple-a7, plain Armv8.0, as
# Scripts/darwin-toolchain.sh builds the overlays (Scripts/check-armv8.sh),
# and the modules SwiftPM precompiles for it with it. SwiftPM's build system
# gives -Xswiftc, -Xcc and -Xcxx to the target's compiles alone, not the
# macros' (a destination file would be taken for a macOS build instead).
spm_target=(--triple "$target" --sdk "$sdk") cpu=()
case $target in arm64-*)
    spm_target+=(-Xswiftc -target-cpu -Xswiftc apple-a7 -Xcc -mcpu=apple-a7 -Xcxx -mcpu=apple-a7)
    cpu=(-target-cpu apple-a7) ;;
esac
(cd "$foundation" && swift build "${spm[@]}" "${spm_target[@]}" --product FoundationInternationalization)
products=$(cd "$foundation" && swift build "${spm[@]}" "${spm_target[@]}" --show-bin-path)
host=$(cd "$foundation" && swift build "${spm[@]}" --show-bin-path)
objects=() modules=$products/Modules
for each in _FoundationCShims _FoundationICU _RopeModule DequeModule OrderedCollections InternalCollectionsUtilities; do
    while IFS= read -r file; do objects+=("$file"); done < <(find "$products/$each.build" -name '*.o' | sort)
done
macros=$host/FoundationMacros
[ -x "$macros" ] || macros=$host/FoundationMacros-tool
[ -x "$macros" ] || macros=$(dirname "$products")/Debug/FoundationMacros

# One module: Internationalization's imports of Essentials go, and names
# qualified by either module are qualified by Foundation.
merged=$work/merged
rm -rf "$merged"; mkdir -p "$merged"
cp -R "$foundation/Sources/FoundationEssentials" "$foundation/Sources/FoundationInternationalization" "$merged/"
# Stand-ins for Objective-C classes the SDK's headers bring in for real.
rm "$merged/FoundationEssentials/Bundle+Stub.swift"
grep -rlE 'import (FoundationEssentials|FoundationInternationalization)$|(FoundationEssentials|FoundationInternationalization)\.' "$merged" \
    | while IFS= read -r file; do
        perl -i -pe 's/^\s*(?:(?:internal|package|public|\@_exported|\@preconcurrency|\@_implementationOnly)\s+)*import (?:FoundationEssentials|FoundationInternationalization)\s*$/\n/; s/\b(FoundationEssentials|FoundationInternationalization)\./Foundation./g' "$file"
    done

# Measurement, Dimension and UnitDuration: swift-foundation stubs them for
# its format styles; they are Darwin/Foundation's Measurement and the SDK's
# NSDimension and NSUnitDuration.
perl -i -ne 'print unless /^public struct Measurement<UnitType> \{\}$|^public class Dimension \{\}$|^public class UnitDuration: Dimension \{\}$/' \
    "$merged/FoundationInternationalization/Formatting/Measurement+FormatStyle+Stub.swift"

# The JSON coders' dates formatted by a DateFormatter, which swift-foundation
# keeps for Apple's build: NSDateFormatter is here as there.
perl -i -pe 's/^#if FOUNDATION_FRAMEWORK && !NO_FORMATTERS\b/#if (FOUNDATION_FRAMEWORK || FOUNDATION_OBJC_TYPES) && !NO_FORMATTERS/' \
    "$merged/FoundationEssentials/JSON/JSONDecoder.swift" "$merged/FoundationEssentials/JSON/JSONEncoder.swift"

# The property list coders' format is NSPropertyListFormat, as in Apple's
# Foundation, whose symbols apps bind to (PropertyListEncoder.outputFormat).
perl -0777 -i -pe 's/^#if FOUNDATION_FRAMEWORK\n(\s*public typealias PropertyListFormat = PropertyListSerialization)/#if FOUNDATION_FRAMEWORK || FOUNDATION_OBJC_TYPES\n$1/m' \
    "$merged/FoundationEssentials/PropertyList/PlistDecoder.swift"

# The settings swift-foundation's manifest gives its targets.
settings=()
for version in 6.0.2 6.1 6.2 6.3; do
    settings+=(-enable-experimental-feature "AvailabilityMacro=FoundationPreview $version:macOS 15, iOS 18, tvOS 18, watchOS 11")
done
for feature in VariadicGenerics LifetimeDependence AddressableTypes AllowUnsafeAttribute BuiltinModule \
    AccessLevelOnImport StrictConcurrency ImportMacroAliases DebugDescriptionMacro; do
    settings+=(-enable-experimental-feature "$feature")
done
settings+=(-enable-upcoming-feature InferSendableFromCaptures -enable-upcoming-feature MemberImportVisibility)

sources=()
while IFS= read -r file; do sources+=("$file"); done < <(find "$merged" "$root/Darwin/Foundation/Sources" -name '*.swift' | sort)
shims=$foundation/Sources/_FoundationCShims/include
icu=$packages/swift-foundation-icu/icuSources/include
xcrun --sdk "$platform" swiftc -target "$target" -sdk "$sdk" ${cpu[@]+"${cpu[@]}"} \
    -module-name Foundation -package-name swift_foundation -parse-as-library \
    -enable-library-evolution -swift-version 5 -O -wmo -import-underlying-module -D FOUNDATION_OBJC_TYPES \
    -emit-library -emit-module -emit-module-path "$out/Foundation.swiftmodule" \
    -I "$modules" \
    -Xcc -fmodule-map-file="$shims/module.modulemap" -Xcc -I"$shims" \
    -Xcc -fmodule-map-file="$icu/_foundation_unicode/module.modulemap" -Xcc -I"$icu" \
    -load-plugin-executable "$macros#FoundationMacros" \
    "${settings[@]}" "${sources[@]}" \
    "${objects[@]}" -lc++ -framework Foundation \
    -Xlinker -install_name -Xlinker /usr/lib/swift/libswiftFoundation.dylib \
    -o "$out/libswiftFoundation.dylib"
echo "$out/libswiftFoundation.dylib"
