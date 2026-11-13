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
        .library(name: "PerryCXX", type: .dynamic, targets: ["PerryCXX"]),
        .library(name: "PerryStdCXX", type: .dynamic, targets: ["PerryStdCXX"]),
        // malloc from a window above 4 GB, as iOS's heap is, for games that
        // keep pointers in 32 bits; loaded with LD_PRELOAD.
        .library(name: "PerryLowHeap", type: .dynamic, targets: ["PerryLowHeap"]),
        .library(name: "PerryOpenAL", type: .dynamic, targets: ["PerryOpenAL"]),
        // OpenGL.framework: a Mac program's desktop OpenGL, over libGL.
        .library(name: "PerryOpenGL", type: .dynamic, targets: ["PerryOpenGL"]),
        // OpenCL.framework, with no devices.
        .library(name: "PerryOpenCL", type: .dynamic, targets: ["PerryOpenCL"]),
        // WPE WebKit's web process extension for AppKit's web views' scripting.
        .library(name: "PerryWebExtension", type: .dynamic, targets: ["PerryWebExtension"]),
        // Steamworks' libsteam_api, over the running Linux Steam client.
        .library(name: "Perrysteam_api", type: .dynamic, targets: ["PerrySteamAPI"]),
        .library(name: "Perrybz2", type: .dynamic, targets: ["PerryBZ2"]),
        .library(name: "PerryBom", type: .dynamic, targets: ["PerryBom"]),
        .library(name: "Perryxar", type: .dynamic, targets: ["PerryXar"]),
        // libcurl, Linux's, opened at run time.
        .library(name: "Perrycurl", type: .dynamic, targets: ["PerryCurl"]),
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
        // Accelerate: vDSP, vForce and vImage, with BLAS and LAPACK from OpenBLAS.
        .library(name: "PerryAccelerate", type: .dynamic, targets: ["PerryAccelerate"]),
        // JavaScriptCore over WebKitGTK's.
        .library(name: "PerryJavaScriptCore", type: .dynamic, targets: ["PerryJavaScriptCore"]),
        // AudioToolbox, played through GStreamer.
        .library(name: "PerryAudioToolbox", type: .dynamic, targets: ["PerryAudioToolbox"]),
        // UserNotifications.
        .library(name: "PerryUserNotifications", type: .dynamic, targets: ["PerryUserNotifications"]),
        .library(name: "PerryAVFoundation", type: .dynamic, targets: ["PerryAVFoundation"]),
        .library(name: "PerrySystemConfiguration", type: .dynamic, targets: ["PerrySystemConfiguration"]),
        // IOKit: the registry a Mac app reads, HID managers and power sources.
        .library(name: "PerryIOKit", type: .dynamic, targets: ["PerryIOKit"]),
        // CoreTelephony, on a device without a cellular radio.
        .library(name: "PerryCoreTelephony", type: .dynamic, targets: ["PerryCoreTelephony"]),
        .library(name: "PerryStoreKit", type: .dynamic, targets: ["PerryStoreKit"]),
        // VideoToolbox, with no video codecs.
        .library(name: "PerryVideoToolbox", type: .dynamic, targets: ["PerryVideoToolbox"]),
        .library(name: "PerryGameKit", type: .dynamic, targets: ["PerryGameKit"]),
        .library(name: "PerryGameController", type: .dynamic, targets: ["PerryGameController"]),
        // MediaPlayer, with no media library and no movies.
        .library(name: "PerryMediaPlayer", type: .dynamic, targets: ["PerryMediaPlayer"]),
        .library(name: "PerryCoreLocation", type: .dynamic, targets: ["PerryCoreLocation"]),
        // CoreBluetooth, a central over BlueZ.
        .library(name: "PerryCoreBluetooth", type: .dynamic, targets: ["PerryCoreBluetooth"]),
        .library(name: "PerryMapKit", type: .dynamic, targets: ["PerryMapKit"]),
        .library(name: "PerryMapKitAppKit", type: .dynamic, targets: ["PerryMapKitAppKit"]),
        .library(name: "PerryCloudKit", type: .dynamic, targets: ["PerryCloudKit"]),
        // Core Data.
        .library(name: "PerryCoreData", type: .dynamic, targets: ["PerryCoreData"]),
        // CoreGraphics.
        .library(name: "PerryCoreGraphics", type: .dynamic, targets: ["PerryCoreGraphics"]),
        // QuartzCore: Core Animation's layers, their rendering and animations.
        .library(name: "PerryQuartzCore", type: .dynamic, targets: ["PerryQuartzCore"]),
        // UIKit.
        .library(name: "PerryUIKit", type: .dynamic, targets: ["PerryUIKit"]),
        // AppKit, for macOS apps.
        .library(name: "PerryAppKit", type: .dynamic, targets: ["PerryAppKit"]),
        // Metal, on Vulkan.
        .library(name: "PerryMetal", type: .dynamic, targets: ["PerryMetal"]),
    ],
    dependencies: [
        // CoreModel's macros need swift-syntax 603; Perry's work with 603 and 604.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "603.0.1"..<"605.0.0"),
        .package(url: "https://github.com/PureSwift/CoreModel.git", from: "2.11.0"),
        .package(url: "https://github.com/PureSwift/CoreModel-SQLite.git", from: "0.3.3"),
        // CryptoKit's API with its own BoringSSL, and X.509, for Security.
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.15.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.21.0"),
        // Cairo and FontConfig, which Silica renders CoreGraphics with.
        .package(url: "https://github.com/PureSwift/Cairo.git", branch: "master"),
        .package(url: "https://github.com/PureSwift/FontConfig.git", branch: "master"),
        // D-Bus, which CoreBluetooth talks to BlueZ over; it has no releases.
        .package(url: "https://github.com/wendylabsinc/dbus.git", revision: "5727296ecaef9655b781f82c7ebde5c9f0d45551"),
        // Sockets and their addresses, typed, for CFSocket.
        .package(url: "https://github.com/PureSwift/Socket.git", from: "0.5.1"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-http-types.git", from: "1.0.0"),
    ],
    targets: [
        .target(name: "PerryInterface"),
        // The Cassowary constraint solver UIKit's and AppKit's Auto Layout share.
        .target(name: "PerryLayoutSolver"),
        // Compiled asset catalogs (Assets.car), which UIKit's and AppKit's
        // named images and colors read.
        .target(name: "PerryAssetCatalog"),
        // Touch scrolling's velocity and deceleration, for UIKit and AppKit.
        .target(name: "PerryScrollPhysics"),
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
            linkerSettings: [.linkedLibrary("m"), .linkedLibrary("gcc_s")]
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
        // C types for values at the Objective-C boundary.
        .target(name: "CPerryObjCInterop"),
        .target(
            name: "PerryObjCInterop",
            dependencies: ["CPerryObjCInterop", "PerryObjCMacros"]
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
        // swift-cmark, Swift's cmark-gfm, for NSAttributedString's Markdown.
        .systemLibrary(name: "CCmarkGFM"),
        // Foundation, a client of libobjc's C API.
        .target(
            name: "PerryFoundation",
            dependencies: [
                "CCmarkGFM", "CLibXML2", "CPerryFoundation", "CPerryGeometry", "PerryInterface", "PerryObjCInterop",
                .product(name: "Socket", package: "Socket"),
            ],
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
        .target(name: "PerryLowHeap"),
        // libc++ and libc++abi, and OpenAL: LLVM's and OpenAL Soft, opened at run time.
        .target(name: "PerryCXX", dependencies: ["CPerryWrapped"]),
        .target(name: "PerryStdCXX", dependencies: ["CPerryWrapped"]),
        .target(name: "PerryOpenAL", dependencies: ["CPerryWrapped"]),
        .target(name: "PerryOpenGL", dependencies: ["CPerryWrapped", "PerryInterface"]),
        .target(name: "PerryOpenCL"),
        .target(name: "PerryWebExtension"),
        // Steamworks: libsteam_api's part, over steamclient.so, opened at run time.
        .target(name: "PerrySteamAPI", dependencies: ["PerryInterface"]),
        .target(name: "PerryBZ2", dependencies: ["CPerryWrapped"], linkerSettings: [.linkedLibrary("bz2")]),
        // Bom's copier: unpacks zip archives and copies directories.
        .target(name: "PerryBom", linkerSettings: [.linkedLibrary("z")]),
        // libxar, Linux's, opened at run time.
        .target(name: "PerryXar", dependencies: ["CPerryWrapped"]),
        // libcurl, Linux's, opened at run time.
        .target(name: "PerryCurl", dependencies: ["CPerryWrapped"]),
        .target(name: "PerryExpat", dependencies: ["CPerryWrapped"], linkerSettings: [.linkedLibrary("expat")]),
        // SQLite 3.54, built in the Docker image as libperry-sqlite3.
        .target(name: "PerrySQLite3", dependencies: ["CPerryWrapped"], linkerSettings: [.linkedLibrary("perry-sqlite3")]),
        .target(name: "PerryIconv"),
        .target(name: "PerryAccelerate", dependencies: ["CPerryWrapped"], linkerSettings: [.linkedLibrary("openblas")]),
        // AudioToolbox: files, converters, queues and audio units, played
        // through GStreamer.
        .target(name: "PerryAudioToolbox", dependencies: ["PerryInterface"], linkerSettings: [.linkedLibrary("m")]),
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
            dependencies: [
                "PerryInterface", "PerryObjCInterop", "PerryURLLoading",
                .product(name: "HTTPTypes", package: "swift-http-types"),
            ],
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
        // WebKitGTK's JavaScriptCore, whose C API is Apple's, and the
        // Objective-C API built on it.
        .systemLibrary(name: "CJavaScriptCore", pkgConfig: "javascriptcoregtk-4.1"),
        .target(name: "CPerryJavaScriptCore"),
        .target(
            name: "PerryJavaScriptCore",
            dependencies: ["CJavaScriptCore", "CPerryJavaScriptCore", "PerryInterface", "PerryObjCInterop"],
            plugins: ["PerryProviderPlugin"]
        ),
        // Notification content, triggers and requests, and a center that
        // delivers them to its delegate.
        .target(
            name: "PerryUserNotifications",
            dependencies: ["PerryInterface", "PerryObjCInterop"],
            plugins: ["PerryProviderPlugin"]
        ),
        // CloudKit, with no iCloud account.
        .target(
            name: "PerryCloudKit",
            dependencies: ["PerryInterface", "PerryObjCInterop"],
            plugins: ["PerryProviderPlugin"]
        ),
        // CoreLocation, over GeoClue's D-Bus API.
        .target(
            name: "PerryCoreLocation",
            dependencies: [
                "CPerryGeometry", "PerryInterface", "PerryObjCInterop",
                .product(name: "DBUS", package: "dbus"),
                .product(name: "Logging", package: "swift-log"),
            ],
            plugins: ["PerryProviderPlugin"]
        ),
        // CoreBluetooth: a central over BlueZ's D-Bus API.
        .target(
            name: "PerryCoreBluetooth",
            dependencies: [
                "PerryInterface", "PerryObjCInterop",
                .product(name: "DBUS", package: "dbus"),
                .product(name: "Logging", package: "swift-log"),
            ],
            plugins: ["PerryProviderPlugin"]
        ),
        // MapKit, its map drawn by MapLibre when libPerryMapLibre.so is
        // there: an iOS app's, whose views are UIKit's, and a Mac app's map
        // views, AppKit's, which re-export the rest of it. Both providers'
        // map views share PerryMapKitShared.
        .target(
            name: "PerryMapKitShared",
            dependencies: ["CPerryGeometry", "PerryObjCInterop"]
        ),
        .target(
            name: "PerryMapKit",
            dependencies: ["CPerryGeometry", "PerryInterface", "PerryMapKitShared", "PerryObjCInterop"],
            plugins: ["PerryProviderPlugin"]
        ),
        .target(
            name: "PerryMapKitAppKit",
            dependencies: ["CPerryGeometry", "PerryInterface", "PerryMapKitShared", "PerryObjCInterop"],
            plugins: ["PerryProviderPlugin"]
        ),
        // GameController, over SDL3's gamepads, and CoreMotion, whose
        // attitude is a gamepad's stick.
        .target(
            name: "PerryGameController",
            dependencies: ["CPerryMotion", "PerryInterface", "PerryObjCInterop"],
            plugins: ["PerryProviderPlugin"]
        ),
        // SystemConfiguration's network reachability, always offline.
        .target(
            name: "PerrySystemConfiguration",
            dependencies: ["PerryInterface", "PerryObjCInterop"],
            plugins: ["PerryProviderPlugin"]
        ),
        // IOKit, over a registry with the platform device and no others.
        .target(
            name: "PerryIOKit",
            dependencies: ["PerryInterface", "PerryObjCInterop"],
            plugins: ["PerryProviderPlugin"]
        ),
        // StoreKit's Objective-C classes, with no App Store.
        .target(
            name: "PerryStoreKit",
            dependencies: ["PerryInterface", "PerryObjCInterop"],
            plugins: ["PerryProviderPlugin"]
        ),
        // VideoToolbox's functions and keys, with no video codecs.
        .target(
            name: "PerryVideoToolbox",
            dependencies: ["PerryInterface", "PerryObjCInterop"],
            plugins: ["PerryProviderPlugin"]
        ),
        // GameKit's Objective-C classes, with no Game Center account.
        .target(
            name: "PerryGameKit",
            dependencies: ["PerryInterface", "PerryObjCInterop"],
            plugins: ["PerryProviderPlugin"]
        ),
        // CoreTelephony, with no SIM and no carrier.
        .target(
            name: "PerryCoreTelephony",
            dependencies: ["PerryInterface", "PerryObjCInterop"],
            plugins: ["PerryProviderPlugin"]
        ),
        // MediaPlayer's names, and players with nothing to play.
        .target(
            name: "PerryMediaPlayer",
            dependencies: ["PerryInterface", "PerryObjCInterop"],
            plugins: ["PerryProviderPlugin"]
        ),
        // AVFoundation's players, assets and video outputs, played through
        // GStreamer, with CoreMedia's times and CoreVideo's pixel buffers.
        .target(
            name: "PerryAVFoundation",
            dependencies: ["CPerryGeometry", "CPerryMedia", "PerryInterface", "PerryObjCInterop"],
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
        // CoreMedia's times, which AVFoundation's provider passes.
        .target(name: "CPerryMedia"),
        // CoreMotion's accelerations, quaternions and rotation matrices.
        .target(name: "CPerryMotion"),
        // Entry points for programs' OpenGL ES calls, which give the calling
        // thread its context.
        .target(name: "CPerryOpenGL"),
        // CoreGraphics: exported constants, and geometry in Swift.
        .target(name: "CPerryCoreGraphics", dependencies: ["CPerryGeometry"]),
        // ImageIO's codecs over Linux's image libraries.
        .target(
            name: "CPerryImageIO",
            linkerSettings: [.linkedLibrary("png"), .linkedLibrary("jpeg"), .linkedLibrary("gif"), .linkedLibrary("webp"),
                             .linkedLibrary("heif"), .linkedLibrary("z")]
        ),
        // Silica (PureSwift, MIT): CoreGraphics' drawing model in Swift, and
        // its Cairo renderer. Copied from github.com/PureSwift/Silica.
        .target(name: "Silica", exclude: ["LICENSE"]),
        .target(
            name: "SilicaCairo",
            dependencies: [
                "Silica",
                .product(name: "Cairo", package: "Cairo"),
                .product(name: "FontConfig", package: "FontConfig"),
            ]
        ),
        // CoreGraphics' images, colors and bitmap contexts, which draw
        // through Silica's Cairo renderer, and ImageIO.
        .target(
            name: "PerryCoreGraphics",
            dependencies: ["CPerryCoreGraphics", "CPerryGeometry", "CPerryImageIO", "PerryInterface", "PerryObjCInterop",
                           "SilicaCairo"],
            plugins: ["PerryProviderPlugin"]
        ),
        // Core Animation: the layer tree UIKit's views are backed by, drawn
        // through CoreGraphics and composited on the GPU, and its animations.
        .target(
            name: "PerryQuartzCore",
            dependencies: ["CPerryGeometry", "PerryInterface", "PerryObjCInterop"],
            plugins: ["PerryProviderPlugin"]
        ),
        // UIKit, a client of libobjc's C API and Foundation's classes.
        .target(
            name: "PerryUIKit",
            dependencies: ["CPerryGeometry", "CPerryOpenGL", "PerryAssetCatalog", "PerryInterface", "PerryLayoutSolver", "PerryObjCInterop",
                           "PerryScrollPhysics"],
            plugins: ["PerryProviderPlugin"]
        ),
        // AppKit, a client of libobjc's C API and Foundation's classes, whose
        // views are backed by QuartzCore's layers.
        .target(
            name: "PerryAppKit",
            dependencies: ["CPerryGeometry", "PerryAssetCatalog", "PerryInterface", "PerryLayoutSolver", "PerryObjCInterop", "PerryScrollPhysics"],
            plugins: ["PerryProviderPlugin"]
        ),
        // Metal's declarations of metal2vulkan's C ABI, and its loader:
        // metal2vulkan (LGPL) is a separate library opened at run time.
        .target(name: "CPerryMetal"),
        // Metal over metal2vulkan's Metal API on Vulkan.
        .target(
            name: "PerryMetal",
            dependencies: ["CPerryGeometry", "CPerryMetal", "PerryInterface", "PerryObjCInterop"],
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
