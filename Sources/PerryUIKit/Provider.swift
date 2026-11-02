import CPerryGeometry
import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryUIKit: the provider for UIKit.framework. PerryProviderPlugin
// generates its perry_provider_startup and perry_provider_symbol from the
// module's Objective-C declarations; this file adds the provider's own
// steps. UIKit is a client of libobjc's C API and of Foundation's classes,
// which the loader starts first, and draws with CoreGraphics' C API. It is
// also QuartzCore, for layers.

private let libobjc = "/usr/lib/libobjc.A.dylib"

/// Before the generated startup defines UIKit's classes: binds libobjc's C
/// API and checks Foundation is running.
func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    func symbol(_ library: String, _ name: String) -> UnsafeMutableRawPointer? {
        library.withCString { library in name.withCString { lookup(library, $0) } }
    }
    let loaded = ObjCRuntime.load { symbol(libobjc, $0) }
    guard loaded, Classes.named("NSString") != nil else {
        uikitFatal("UIKit needs libPerryobjc and libPerryFoundation, which are missing or incomplete")
    }
    Methods.implementation = symbol(libobjc, "_class_getMethodImplementation").map { unsafeBitCast($0, to: Methods.Implementation.self) }
    guard Methods.implementation != nil, CG.load(symbol) else {
        uikitFatal("UIKit needs libPerryCoreGraphics, which is missing or incomplete")
    }
    guard Updates.load(symbol) else { uikitFatal("UIKit needs libdispatch's main queue") }
    Display.load(symbol)
    return true
}

/// UIKit's numeric and structure constants, which the loader asks for
/// while binding images, before the provider starts.
func providerSymbol(_ name: String) -> UnsafeMutableRawPointer? { Constants.values[name] }

enum Constants {
    /// Storage for each constant, made once.
    nonisolated(unsafe) static let values: [String: UnsafeMutableRawPointer] = {
        func value<T>(_ value: T) -> UnsafeMutableRawPointer {
            let storage = UnsafeMutablePointer<T>.allocate(capacity: 1)
            storage.initialize(to: value)
            return UnsafeMutableRawPointer(storage)
        }
        return [
            "_UIScrollViewDecelerationRateNormal": value(CGFloat(0.998)),
            "_UIScrollViewDecelerationRateFast": value(CGFloat(0.99)),
            "_UITableViewAutomaticDimension": value(CGFloat(-1)),
            "_UIViewNoIntrinsicMetric": value(CGFloat(-1)),
            "_UIEdgeInsetsZero": value(UIEdgeInsets.zero),
            "_UILayoutFittingCompressedSize": value(CGSize.zero),
            "_UILayoutFittingExpandedSize": value(CGSize(width: 1e7, height: 1e7)),
            "_UIFontWeightUltraLight": value(CGFloat(-0.8)),
            "_UIFontWeightThin": value(CGFloat(-0.6)),
            "_UIFontWeightLight": value(CGFloat(-0.4)),
            "_UIFontWeightRegular": value(CGFloat(0)),
            "_UIFontWeightMedium": value(CGFloat(0.23)),
            "_UIFontWeightSemibold": value(CGFloat(0.3)),
            "_UIFontWeightBold": value(CGFloat(0.4)),
            "_UIFontWeightHeavy": value(CGFloat(0.56)),
            "_UIFontWeightBlack": value(CGFloat(0.62)),
        ]
    }()
}

/// Reports a fatal error the way UIKit's assertions do, and aborts.
func uikitFatal(_ message: String) -> Never {
    let line = "perry: UIKit: *** \(message)\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
    abort()
}

enum Classes {
    /// The class named `name`, if one is registered.
    static func named(_ name: String) -> ObjCClass? {
        name.withCString { ObjCRuntime.functions.getClass($0) }.map(ObjCClass.init)
    }
}
