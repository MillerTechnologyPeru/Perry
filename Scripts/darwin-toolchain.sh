# Sourced by the scripts that build for Apple's platforms: finds an SDK and
# the tools that build against it, so that one script runs on a Mac with
# Xcode and in Linux, in perry-dev under Scripts/docker-darwin.sh.
#
# On a Mac each comes from xcrun, for the Xcode xcode-select or
# DEVELOPER_DIR selects. In Linux they come from a copy of that Xcode's
# Developer directory (its SDKs and its toolchain's usr/lib/swift and
# usr/lib/clang), at PERRY_DEVELOPER_DIR (default /Developer), with the
# image's own compilers: Swift's swiftc, clang and swift-demangle, and
# LLVM's ld64.lld from PERRY_LLVM_BIN, since the lld Swift bundles cannot
# link Mach-O. swiftc gets Xcode's toolchain's usr/lib/swift as its
# resource directory, for its clang headers and shims, and its module cache
# at PERRY_MODULE_CACHE (default /module-cache): the SDKs' prebuilt modules
# are for Xcode's compiler, so another one compiles them from their
# interfaces, once.
#
#   darwin_sdk <platform>            the SDK's path (iphoneos, macosx, iphonesimulator)
#   darwin_sdk_version <platform>    its version, 27.2 say
#   darwin_platform_path <platform>  its platform directory (XCTest's frameworks are there)
#   darwin_swiftc <platform> ...     runs swiftc
#   darwin_clang <platform> ...      runs clang (clang++ as darwin_clangxx)
#   darwin_find <tool>               a tool's path: swiftc, clang, clang++, swift-demangle, ld
#   darwin_demangle ...              runs swift-demangle
#   darwin_nm <arch> ...             lists a Mach-O's symbols, for that architecture's slice
#
# None of them call xcodebuild or any other tool only Xcode has.

if [ "$(uname)" = Darwin ]; then
    command -v xcrun >/dev/null || { echo "needs Xcode's command line tools (xcrun)" >&2; exit 1; }
    darwin_sdk() { xcrun --sdk "$1" --show-sdk-path; }
    darwin_sdk_version() { xcrun --sdk "$1" --show-sdk-version; }
    darwin_platform_path() { xcrun --sdk "$1" --show-sdk-platform-path; }
    darwin_swiftc() { local platform=$1; shift; xcrun --sdk "$platform" swiftc "$@"; }
    darwin_clang() { local platform=$1; shift; xcrun --sdk "$platform" clang "$@"; }
    darwin_clangxx() { local platform=$1; shift; xcrun --sdk "$platform" clang++ "$@"; }
    darwin_find() { xcrun --find "$1"; }
    darwin_demangle() { xcrun swift-demangle "$@"; }
    darwin_nm() { local arch=$1; shift; xcrun nm -arch "$arch" "$@"; }
else
    darwin_developer=${PERRY_DEVELOPER_DIR:-/Developer}
    [ -d "$darwin_developer/Platforms" ] || {
        echo "no copy of Xcode's Developer directory at $darwin_developer: run this through Scripts/docker-darwin.sh" >&2
        exit 1
    }
    darwin_resources=$darwin_developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift
    darwin_ld=${PERRY_LLVM_BIN:-/usr/lib/llvm-19/bin}/ld64.lld
    darwin_module_cache=${PERRY_MODULE_CACHE:-/module-cache}
    # The platform directory's name for an SDK name.
    darwin_platform_name() {
        case $1 in
        iphoneos) echo iPhoneOS ;;
        iphonesimulator) echo iPhoneSimulator ;;
        macosx) echo MacOSX ;;
        *) echo "unknown SDK $1" >&2; return 1 ;;
        esac
    }
    darwin_platform_path() { echo "$darwin_developer/Platforms/$(darwin_platform_name "$1").platform"; }
    darwin_sdk() { echo "$(darwin_platform_path "$1")/Developer/SDKs/$(darwin_platform_name "$1").sdk"; }
    darwin_sdk_version() {
        python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["Version"])' "$(darwin_sdk "$1")/SDKSettings.json"
    }
    # Clang passes ld64.lld the options of a linker this new or newer
    # (-platform_version), not those of the ld64 it would otherwise assume.
    darwin_swiftc() {
        shift
        swiftc -resource-dir "$darwin_resources" -module-cache-path "$darwin_module_cache" \
            -ld-path="$darwin_ld" -Xclang-linker -mlinker-version=1100 "$@"
    }
    darwin_clang() { shift; clang --ld-path="$darwin_ld" -mlinker-version=1100 -Wno-unused-command-line-argument "$@"; }
    darwin_clangxx() { shift; clang++ --ld-path="$darwin_ld" -mlinker-version=1100 -Wno-unused-command-line-argument "$@"; }
    darwin_find() {
        case $1 in
        ld) echo "$darwin_ld" ;;
        *) command -v "$1" ;;
        esac
    }
    darwin_demangle() { swift-demangle "$@"; }
    darwin_nm() { local arch=$1; shift; llvm-nm --arch="$arch" "$@"; }
fi
