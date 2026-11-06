#!/bin/sh
# Builds the PerryObjCMacros compiler plugin for the host, into .build/macros,
# against the swift-syntax libraries the Swift toolchain ships. SwiftPM would
# build swift-syntax itself, which needs more memory than a small machine has;
# the toolchain lacks only SwiftCompilerPlugin, a small module built here from
# the package checkout (`swift package resolve` fetches it).
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
toolchain=${PERRY_HOST_SWIFT:-$(ls -d "$root"/.toolchains/swift-6.4.2-RELEASE-*/usr | head -1)}
host=$toolchain/lib/swift/host
out=$root/.build/macros
mkdir -p "$out"

"$toolchain/bin/swiftc" -module-name SwiftCompilerPlugin -parse-as-library \
    -emit-module -emit-module-path "$out/SwiftCompilerPlugin.swiftmodule" -c -o "$out/SwiftCompilerPlugin.o" \
    -I "$host" "$root"/.build/checkouts/swift-syntax/Sources/SwiftCompilerPlugin/*.swift

"$toolchain/bin/swiftc" -module-name PerryObjCMacros -parse-as-library -I "$out" -I "$host" \
    "$root"/Sources/PerryObjCMacros/*.swift "$out/SwiftCompilerPlugin.o" -L "$host" \
    -lSwiftSyntax -lSwiftSyntaxMacros -lSwiftSyntaxBuilder -lSwiftDiagnostics -lSwiftParser \
    -lSwiftCompilerPluginMessageHandling -lSwiftSyntaxMacroExpansion -lSwiftBasicFormat -lSwiftOperators \
    -lSwiftParserDiagnostics -lSwiftLibraryPluginProvider -lSwiftIfConfig -lSwiftWarningControl \
    -Xlinker -rpath -Xlinker "$host" -o "$out/PerryObjCMacros" 2>&1 | grep -v 'RWX permissions' || true
echo "$out/PerryObjCMacros"
