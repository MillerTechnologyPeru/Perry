// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Perry",
    products: [
        // Loader: runs arm64 iOS and macOS Mach-O binaries on arm64 Linux.
        .executable(name: "perry", targets: ["PerryLoader"]),
        // Darwin libSystem ABI over glibc, loaded by perry as a provider.
        .library(name: "PerrySystem", type: .dynamic, targets: ["PerrySystem"]),
        // Objective-C runtime, the provider for /usr/lib/libobjc.A.dylib.
        .library(name: "Perryobjc", type: .dynamic, targets: ["PerryObjC"]),
        // Foundation and CoreFoundation.
        .library(name: "PerryFoundation", type: .dynamic, targets: ["PerryFoundation"]),
    ],
    targets: [
        .target(name: "PerryInterface"),
        .target(
            name: "PerryLoaderCore",
            dependencies: ["PerryInterface"]
        ),
        .executableTarget(
            name: "PerryLoader",
            dependencies: ["PerryLoaderCore"]
        ),
        .target(
            name: "PerrySystem",
            dependencies: ["PerryInterface"],
            linkerSettings: [.linkedLibrary("m")]
        ),
        // Objective-C runtime: Apple's metadata layouts and objc_msgSend.
        .target(name: "CPerryObjC"),
        // Objective-C runtime engine.
        .target(
            name: "PerryObjCRuntime",
            dependencies: ["CPerryObjC"]
        ),
        // libobjc's C API under Darwin symbol names.
        .target(
            name: "PerryObjC",
            dependencies: ["PerryObjCRuntime", "CPerryObjC", "PerryInterface"]
        ),
        // Foundation: exported class storage and variadic entry points.
        .target(name: "CPerryFoundation"),
        // Foundation, a client of libobjc's C API.
        .target(
            name: "PerryFoundation",
            dependencies: ["CPerryFoundation", "PerryInterface"]
        ),
        .testTarget(
            name: "PerryLoaderTests",
            dependencies: ["PerryLoaderCore"]
        ),
    ]
)
