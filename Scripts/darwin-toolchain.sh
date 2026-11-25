# Sourced by the scripts that build for Apple's platforms on a Mac with
# Xcode: finds an SDK and the tools that build against it via xcrun, for
# the Xcode selected by xcode-select or DEVELOPER_DIR.
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
# Code for an arm64 target is built for apple-a7, plain Armv8.0, whatever
# the compiler's default: Perry runs it on any 64-bit Arm Linux machine, and
# a CPU without the newer extensions (the OnePlus 6T's has no dot product)
# traps on their instructions. Scripts/check-armv8.sh checks the result.

[ "$(uname)" = Darwin ] || { echo "needs macOS with Xcode" >&2; exit 1; }
command -v xcrun >/dev/null || { echo "needs Xcode's command line tools (xcrun)" >&2; exit 1; }

# The flag that pins the CPU of an arm64 target among a compiler's
# arguments, for swift or clang; nothing for another target.
darwin_cpu() {
    local kind=$1 previous= argument
    shift
    for argument; do
        case "$previous $argument" in
        "-target arm64-"* | *" --target=arm64-"* | *" -target=arm64-"*)
            if [ "$kind" = swift ]; then echo "-target-cpu apple-a7"; else echo "-mcpu=apple-a7"; fi
            return ;;
        esac
        previous=$argument
    done
}

darwin_sdk() { xcrun --sdk "$1" --show-sdk-path; }
darwin_sdk_version() { xcrun --sdk "$1" --show-sdk-version; }
darwin_platform_path() { xcrun --sdk "$1" --show-sdk-platform-path; }
darwin_swiftc() { local platform=$1; shift; xcrun --sdk "$platform" swiftc $(darwin_cpu swift "$@") "$@"; }
darwin_clang() { local platform=$1; shift; xcrun --sdk "$platform" clang $(darwin_cpu clang "$@") "$@"; }
darwin_clangxx() { local platform=$1; shift; xcrun --sdk "$platform" clang++ $(darwin_cpu clang "$@") "$@"; }
darwin_find() { xcrun --find "$1"; }
darwin_demangle() { xcrun swift-demangle "$@"; }
darwin_nm() { local arch=$1; shift; xcrun nm -arch "$arch" "$@"; }
