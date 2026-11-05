#!/bin/sh
# Builds Perry's SwiftUI on a Mac with Xcode: Darwin/SwiftUI, OpenSwiftUI
# made to stand in for Apple's SwiftUI.framework. Its packages are built for
# iOS arm64 with library evolution under SwiftUI's ABI names, so apps built
# against Apple's bind to it by the same Swift symbols, and linked into
# SwiftUI.framework/SwiftUI in the directory given, the Swift runtime's
# (PERRY_SWIFT_RUNTIME), where the loader finds frameworks with Swift code.
#
# Usage: Scripts/build-swiftui.sh [output directory]
#   default output: .build/perry-swift-runtime
#   CONFIGURATION=release builds optimized (default debug).
set -eu
cd "$(dirname "$0")/.."
[ "$(uname)" = Darwin ] || { echo "needs macOS with Xcode" >&2; exit 1; }

root=$PWD
out=${1:-.build/perry-swift-runtime}
case $out in /*) ;; *) out=$root/$out ;; esac
work=$root/.build/perry-swiftui
configuration=${CONFIGURATION:-debug}
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
target=arm64-apple-ios18.0
packages=$root/Darwin/SwiftUI
mkdir -p "$work" "$out/SwiftUI.framework"

# Only MIT-licensed sources are kept in Darwin/SwiftUI. The rest, under
# Apache 2.0 (Swift's runtime and corelibs headers) or other
# licenses, is fetched from upstream at the commits the copies were taken
# from; Darwin/SwiftUI/.gitignore lists it.
fetch() { # directory url commit
    [ -e "$1/.perry-commit" ] && [ "$(cat "$1/.perry-commit")" = "$3" ] && return
    rm -rf "$1"; mkdir -p "$1"
    git -C "$1" init -q
    git -C "$1" fetch -q --depth 1 "$2" "$3"
    git -C "$1" checkout -q FETCH_HEAD
    echo "$3" > "$1/.perry-commit"
}
restore() { # package url commit paths...
    package=$1 url=$2 commit=$3; shift 3
    repository=$work/upstream/$package
    [ -e "$repository/.git" ] || git init -q "$repository"
    git -C "$repository" cat-file -e "$commit^{commit}" 2>/dev/null || git -C "$repository" fetch -q --depth 1 "$url" "$commit"
    git --git-dir="$repository/.git" --work-tree="$packages/$package" checkout -q "$commit" -- "$@"
}
fetch "$packages/Compute/Submodules/swift-runtime-headers" \
    https://github.com/jcmosc/swift-runtime-headers.git 626688ce65f43a83d5822532e1c9e85f92e21106
fetch "$packages/OpenAttributeGraph/Checkouts/swift" \
    https://github.com/OpenSwiftUIProject/swift-runtime-headers.git 42c0a0f7b02cc040c5a537fc5c577ca9b884dff8
restore OpenSwiftUI https://github.com/MillerTechnologyPeru/OpenSwiftUI.git 537003386f7388a3a56b8e573d3563ec9aa619cd \
    Sources/SwiftCorelibs Sources/OpenSwiftUI_SPI/OpenSwiftUITargetConditionals.h
restore OpenAttributeGraph https://github.com/OpenSwiftUIProject/OpenAttributeGraph.git 46f2e1b832fa9626bd88f62ba34ba0b799b5206c \
    Sources/SwiftCorelibs Sources/SwiftBridging/SwiftBridging.h \
    Sources/OpenAttributeGraphCxx/include/OpenAttributeGraph/OAGTargetConditionals.h \
    Sources/OpenAttributeGraphCxx/include/OpenAttributeGraph/Private/CFRuntime.h
restore OpenRenderBox https://github.com/OpenSwiftUIProject/OpenRenderBox.git 0bb9980ad7aab62231913c659d1909a95e50c5b4 \
    Sources/OpenRenderBoxCxx/include/OpenRenderBox/ORBTargetConditionals.h \
    Sources/OpenRenderBoxCxx/include/OpenRenderBox/CFCGTypes.h
restore Compute https://github.com/OpenSwiftUIProject/Compute.git 41ecaef85f8bd3f73c3ee42a253cc603fd8df0fe \
    Sources/SwiftCorelibsCoreFoundation Sources/Utilities/include/Utilities/SwiftBridging.h \
    Sources/ComputeCxx/internalInclude/CoreFoundationPrivate/CFRuntime.h \
    Sources/ComputeCxx/include/ComputeCxx/IAGTargetConditionals.h

# The SDK's UIKit interface imports SwiftUICore, which would bring in
# Apple's SwiftUI types beside these; this copy leaves it out, with the one
# protocol that needs it.
uikit=$work/sdk/UIKit.swiftmodule
mkdir -p "$uikit"
python3 -I - "$sdk/System/Library/Frameworks/UIKit.framework/Modules/UIKit.swiftmodule/arm64e-apple-ios.swiftinterface" \
    "$uikit/arm64-apple-ios.swiftinterface" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
s = s.replace("\nimport SwiftUICore\n", "\n", 1)
s = re.sub(r'@available\(iOS 17\.0, tvOS 17\.0, \*\)\n(@_originallyDefinedIn[^\n]*\n)+(@available[^\n]*\n)*'
           r'public protocol UITraitBridgedEnvironmentKey[^}]*\}\n', '', s)
assert "SwiftUICore" not in s
s = s.replace("-target arm64e-apple-ios", "-target arm64-apple-ios")
open(sys.argv[2], "w").write(s)
PY

# Perry's DeveloperToolsSupport (Scripts/build-framework.sh), in place of
# the SDK's: SwiftUI reads its resources' names and bundles through Perry's
# SPI.
dts=.build/perry-frameworks/DeveloperToolsSupport.swiftmodule
[ -d "$dts" ] || Scripts/build-framework.sh DeveloperToolsSupport "$out"
rm -rf "$work/sdk/DeveloperToolsSupport.swiftmodule"
cp -R "$dts" "$work/sdk/DeveloperToolsSupport.swiftmodule"

# The SDK's Observation interface leaves out the SPI SwiftUI tracks views'
# reads with, which libswiftObservation exports; this copy declares it, as
# Swift's Observation sources do.
observation=$work/sdk/Observation.swiftmodule
mkdir -p "$observation"
python3 -I - "$sdk/usr/lib/swift/Observation.swiftmodule/arm64e-apple-ios.swiftinterface" \
    "$observation/arm64-apple-ios.swiftinterface" <<'PY'
import sys
s = open(sys.argv[1]).read()
anchor = "public struct ObservationTracking : Swift::Sendable {\n"
assert s.count(anchor) == 1
s = s.replace(anchor, anchor + """  @_spi(SwiftUI) public struct _AccessList : Swift::Sendable {
  }
  @_spi(SwiftUI) public static func _installTracking(_ tracking: Observation::ObservationTracking, willSet: (@Sendable (Observation::ObservationTracking) -> Swift::Void)? = nil, didSet: (@Sendable (Observation::ObservationTracking) -> Swift::Void)? = nil)
  @_spi(SwiftUI) public static func _installTracking(_ list: Observation::ObservationTracking._AccessList, onChange: @escaping @Sendable () -> Swift::Void)
  @_spi(SwiftUI) public init(_ list: Observation::ObservationTracking._AccessList?)
  @_spi(SwiftUI) public func cancel()
  @_spi(SwiftUI) public var changed: Swift::AnyKeyPath? {
    get
  }
""", 1)
s = s.replace("-target arm64e-apple-ios", "-target arm64-apple-ios")
open(sys.argv[2], "w").write(s)
PY

# OpenSwiftUI's package settings: local packages, Compute for the attribute
# graph, no private frameworks, and SwiftUI's ABI.
export OPENSWIFTUI_USE_LOCAL_DEPS=1 OPENRENDERBOX_USE_LOCAL_DEPS=1 \
    OPENATTRIBUTEGRAPH_USE_LOCAL_DEPS=1 OPENCOREGRAPHICS_USE_LOCAL_DEPS=1 \
    OPENSWIFTUI_RENDERBOX=0 OPENRENDERBOX_RENDERBOX=0 \
    OPENSWIFTUI_LINK_COREUI=0 OPENSWIFTUI_LINK_CORESVG=0 OPENSWIFTUI_LINK_SFSYMBOLS=0 \
    OPENSWIFTUI_LINK_SYMBOLS=0 OPENSWIFTUI_LINK_FEATUREFLAGS=0 \
    OPENSWIFTUI_LINK_BACKLIGHTSERVICES=0 OPENSWIFTUI_LINK_GESTURES=0 \
    OPENSWIFTUI_OPENATTRIBUTESHIMS_COMPUTE=1 OPENATTRIBUTEGRAPH_COMPUTE=1 \
    OPENSWIFTUI_LIBRARY_EVOLUTION=1 OPENSWIFTUI_AS_SWIFTUI=1

# Each target's object file, linked below, is written anew by the build;
# those of targets no longer built are cleared first.
products=$(cd "$packages/OpenSwiftUI" && swift build -c "$configuration" --scratch-path "$work/spm" \
    --triple "$target" --sdk "$sdk" --show-bin-path)
rm -f "$products"/*.o
(cd "$packages/OpenSwiftUI" && swift build -c "$configuration" --scratch-path "$work/spm" \
    --triple "$target" --sdk "$sdk" -Xswiftc -I -Xswiftc "$work/sdk" --product OpenSwiftUI)

# Every package's objects in one image; libswiftDemangle, which the iOS SDK
# does not ship, links through a stub of the exports Compute uses, and
# DeveloperToolsSupport is Perry's.
link() { # extra linker arguments...
    xcrun --sdk iphoneos swiftc -target "$target" -sdk "$sdk" -emit-library "$products"/*.o \
        -framework UIKit -framework CoreServices -framework QuartzCore -framework CoreText \
        -lMobileGestalt -lAccessibility -lc++ -L "$packages/Stubs" -lswiftDemangle \
        "$out/DeveloperToolsSupport.framework/DeveloperToolsSupport" \
        -Xlinker -install_name -Xlinker /System/Library/Frameworks/SwiftUI.framework/SwiftUI \
        -Xlinker -not_for_dyld_shared_cache -Xlinker -ObjC "$@" \
        -o "$out/SwiftUI.framework/SwiftUI"
}
link

# OpenSwiftUI's extensions on OpenSwiftUICore's types (EnvironmentValues,
# Text...) are another module's to the compiler, so their members mangle as
# extension members ("…ValuesVAAE10scenePhase…"). SwiftUICore's types are
# originally SwiftUI's, so SwiftUI's own extensions mangle as the type's
# members ("…ValuesV10scenePhase…", "…ColorVyACSo7UIColorCcfC"), and apps
# bind those names. Each such member gets that name too, where it demangles
# to the same declaration.
aliases=$work/aliases.txt
nm -gU "$out/SwiftUI.framework/SwiftUI" | awk '{print $3}' | python3 -I -c '
import re, subprocess, sys
pairs = []
for symbol in sys.stdin.read().split():
    match = re.match(r"^(_\$s7SwiftUI\d+[A-Za-z_0-9]*?[VCO])AAE(.+)$", symbol)
    if match:
        pairs.append((symbol, match.group(1) + match.group(2)))
def demangled(names):
    output = subprocess.run(["xcrun", "swift-demangle", "--compact"], input="\n".join(names),
                            capture_output=True, text=True).stdout
    return output.split("\n")[:len(names)]
original = demangled([a for a, _ in pairs])
alias = demangled([b for _, b in pairs])
for (a, b), x, y in zip(pairs, original, alias):
    if x.replace("(extension in SwiftUI):", "") == y:
        print(a, b)
' > "$aliases"
link -Xlinker -alias_list -Xlinker "$aliases"
echo "$out/SwiftUI.framework/SwiftUI ($(wc -l < "$aliases" | tr -d ' ') same-module aliases)"
