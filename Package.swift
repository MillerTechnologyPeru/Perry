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
        // libdispatch, which libSystem re-exports.
        .library(name: "Perrydispatch", type: .dynamic, targets: ["PerryDispatch"]),
        // Foundation and CoreFoundation.
        .library(name: "PerryFoundation", type: .dynamic, targets: ["PerryFoundation"]),
        // C libraries over Linux's builds of the same libraries.
        .library(name: "Perryxml2", type: .dynamic, targets: ["PerryXML2"]),
        .library(name: "Perryz", type: .dynamic, targets: ["PerryZ"]),
        .library(name: "Perrybz2", type: .dynamic, targets: ["PerryBZ2"]),
        .library(name: "Perryexpat", type: .dynamic, targets: ["PerryExpat"]),
        .library(name: "Perrysqlite3", type: .dynamic, targets: ["PerrySQLite3"]),
        .library(name: "Perryiconv", type: .dynamic, targets: ["PerryIconv"]),
        // libcompression, Apple's API over open compressors.
        .library(name: "Perrycompression", type: .dynamic, targets: ["PerryCompression"]),
        // CFNetwork, whose URL loading classes Foundation re-exports.
        .library(name: "PerryCFNetwork", type: .dynamic, targets: ["PerryCFNetwork"]),
        // Security.
        .library(name: "PerrySecurity", type: .dynamic, targets: ["PerrySecurity"]),
        // UniformTypeIdentifiers, and MobileCoreServices' UTType functions.
        .library(name: "PerryUniformTypeIdentifiers", type: .dynamic, targets: ["PerryUniformTypeIdentifiers"]),
        // UserNotifications.
        .library(name: "PerryUserNotifications", type: .dynamic, targets: ["PerryUserNotifications"]),
        // Core Data.
        .library(name: "PerryCoreData", type: .dynamic, targets: ["PerryCoreData"]),
        // CoreGraphics.
        .library(name: "PerryCoreGraphics", type: .dynamic, targets: ["PerryCoreGraphics"]),
        // UIKit.
        .library(name: "PerryUIKit", type: .dynamic, targets: ["PerryUIKit"]),
    ],
    dependencies: [
        // CoreModel's macros need swift-syntax 603; Perry's work with 603 and 604.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "603.0.1"..<"605.0.0"),
        .package(url: "https://github.com/PureSwift/CoreModel.git", from: "2.11.0"),
        .package(url: "https://github.com/PureSwift/CoreModel-SQLite.git", from: "0.3.3"),
        // CryptoKit's API with its own BoringSSL, and X.509, for Security.
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.15.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.21.0"),
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
        // libdispatch: Linux's declared under other names, and Darwin's
        // exported data.
        .target(name: "CPerryDispatch"),
        // libdispatch's Darwin API over Linux's libdispatch.
        .target(
            name: "PerryDispatch",
            dependencies: ["CPerryDispatch", "PerryInterface", "PerryObjCInterop"],
            linkerSettings: [.linkedLibrary("dispatch")],
            plugins: ["PerryProviderPlugin"]
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
        // Binding a Darwin library's imports to the Linux build of the same
        // library, and thunks for Darwin's variadic ABI.
        .target(name: "CPerryWrapped"),
        // libxml2: Linux's, with thunks for Darwin's variadic ABI.
        .target(
            name: "PerryXML2",
            dependencies: ["CPerryWrapped"],
            linkerSettings: [.linkedLibrary("xml2")]
        ),
        .target(name: "PerryZ", dependencies: ["CPerryWrapped"], linkerSettings: [.linkedLibrary("z")]),
        .target(name: "PerryBZ2", dependencies: ["CPerryWrapped"], linkerSettings: [.linkedLibrary("bz2")]),
        .target(name: "PerryExpat", dependencies: ["CPerryWrapped"], linkerSettings: [.linkedLibrary("expat")]),
        // SQLite 3.54, built in the Docker image as libperry-sqlite3.
        .target(name: "PerrySQLite3", dependencies: ["CPerryWrapped"], linkerSettings: [.linkedLibrary("perry-sqlite3")]),
        .target(name: "PerryIconv"),
        .target(
            name: "PerryCompression",
            linkerSettings: [
                .linkedLibrary("z"), .linkedLibrary("lzma"), .linkedLibrary("lz4"),
                .linkedLibrary("brotlienc"), .linkedLibrary("brotlidec"), .linkedLibrary("lzfse"),
            ]
        ),
        // URL loading over swift-corelibs-foundation's URLSession.
        .target(name: "PerryURLLoading"),
        // CFNetwork's Objective-C classes over PerryURLLoading.
        .target(
            name: "PerryCFNetwork",
            dependencies: ["PerryInterface", "PerryObjCInterop", "PerryURLLoading"],
            plugins: ["PerryProviderPlugin"]
        ),
        // Security's exported data that Swift cannot define.
        .target(name: "CPerrySecurity"),
        // Security over swift-crypto and swift-certificates: keys,
        // certificates, trust and the keychain.
        .target(
            name: "PerrySecurity",
            dependencies: [
                "CPerrySecurity", "PerryInterface", "PerryObjCInterop",
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
                .product(name: "X509", package: "swift-certificates"),
            ],
            plugins: ["PerryProviderPlugin"]
        ),
        // UTType and the type database.
        .target(
            name: "PerryUniformTypeIdentifiers",
            dependencies: ["PerryInterface", "PerryObjCInterop"],
            plugins: ["PerryProviderPlugin"]
        ),
        // Notification content, triggers and requests, and a center that
        // delivers them to its delegate.
        .target(
            name: "PerryUserNotifications",
            dependencies: ["PerryInterface", "PerryObjCInterop"],
            plugins: ["PerryProviderPlugin"]
        ),
        // Core Data over CoreModel: SQLite stores through CoreModel-SQLite,
        // every other store type in memory.
        .target(
            name: "PerryCoreData",
            dependencies: [
                "PerryInterface", "PerryObjCInterop",
                .product(name: "CoreModel", package: "CoreModel"),
                .product(name: "CoreModelSQLite", package: "CoreModel-SQLite"),
            ],
            plugins: ["PerryProviderPlugin"]
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
