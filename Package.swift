// swift-tools-version: 6.4
import CompilerPluginSupport
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
        // libxml2, over Linux's.
        .library(name: "Perryxml2", type: .dynamic, targets: ["PerryXML2"]),
        // CoreGraphics.
        .library(name: "PerryCoreGraphics", type: .dynamic, targets: ["PerryCoreGraphics"]),
        // UIKit.
        .library(name: "PerryUIKit", type: .dynamic, targets: ["PerryUIKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "604.0.0"),
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
            dependencies: ["CPerryObjC", "PerryObjCInterop"]
        ),
        // libobjc's C API under Darwin symbol names.
        .target(
            name: "PerryObjC",
            dependencies: ["PerryObjCRuntime", "CPerryObjC", "PerryInterface"]
        ),
        // @ObjCClass, @ObjCMethod and the other Objective-C macros.
        .macro(
            name: "PerryObjCMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(
            name: "PerryObjCInterop",
            dependencies: ["PerryObjCMacros"]
        ),
        .testTarget(
            name: "PerryObjCMacrosTests",
            dependencies: [
                "PerryObjCMacros",
                .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax"),
            ]
        ),
        // Foundation: exported class storage and variadic entry points.
        .target(name: "CPerryFoundation"),
        // Linux's libxml2, for NSXMLParser.
        .systemLibrary(name: "CLibXML2", pkgConfig: "libxml-2.0", providers: [.apt(["libxml2-dev"])]),
        // Foundation, a client of libobjc's C API.
        .target(
            name: "PerryFoundation",
            dependencies: ["CLibXML2", "CPerryFoundation", "PerryInterface", "PerryObjCInterop"],
            plugins: ["PerryProviderPlugin"]
        ),
        // libxml2: Linux's, with thunks for Darwin's variadic ABI.
        .target(
            name: "PerryXML2",
            linkerSettings: [.linkedLibrary("xml2")]
        ),
        // CoreGraphics' geometry types, shared by the providers that pass them.
        .target(name: "CPerryGeometry"),
        // CoreGraphics: exported constants, and geometry in Swift.
        .target(name: "CPerryCoreGraphics", dependencies: ["CPerryGeometry"]),
        .target(name: "PerryCoreGraphics", dependencies: ["CPerryCoreGraphics", "CPerryGeometry"]),
        // UIKit, a client of libobjc's C API and Foundation's classes.
        .target(
            name: "PerryUIKit",
            dependencies: ["CPerryGeometry", "PerryInterface", "PerryObjCInterop"],
            plugins: ["PerryProviderPlugin"]
        ),
        // Generates a provider's perry_provider_startup and perry_provider_symbol
        // from its Objective-C declarations.
        .executableTarget(
            name: "PerryProviderGenerator",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
        .plugin(
            name: "PerryProviderPlugin",
            capability: .buildTool(),
            dependencies: ["PerryProviderGenerator"]
        ),
        .testTarget(
            name: "PerryLoaderTests",
            dependencies: ["PerryLoaderCore"]
        ),
    ]
)
