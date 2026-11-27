// swift-tools-version: 6.0
import PackageDescription

// Native macOS tests for the representation logic. The Darwin runtime library
// itself is built with Scripts/build-framework.sh CoreTransferable.
let package = Package(
    name: "CoreTransferable",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "CoreTransferable", path: "Sources"),
        .testTarget(name: "CoreTransferableTests", dependencies: ["CoreTransferable"], path: "Tests")
    ],
    swiftLanguageModes: [.v5]
)
