// swift-tools-version: 6.4
// sdk-scan: lists what the public macOS and iOS SDKs declare and export, and
// (in later phases) what Perry provides of it. See
// Documentation/Plans/sdk-symbol-coverage.md.
//
// Its own package, apart from Perry's, so it builds in seconds and with no
// dependencies on any host: scanning needs an SDK (a Mac with Xcode), but
// reading and comparing the manifests it writes runs anywhere.
import PackageDescription

let package = Package(
    name: "sdk-scan",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "sdk-scan", targets: ["sdk-scan"])
    ],
    targets: [
        .target(name: "SDKScan"),
        .executableTarget(name: "sdk-scan", dependencies: ["SDKScan"]),
        .testTarget(name: "SDKScanTests", dependencies: ["SDKScan"], resources: [.copy("Fixtures")])
    ]
)
