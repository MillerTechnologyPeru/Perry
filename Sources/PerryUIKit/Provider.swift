import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryUIKit: the provider for UIKit.framework. PerryProviderPlugin
// generates its perry_provider_startup and perry_provider_symbol from the
// module's Objective-C declarations; this file adds the provider's own
// steps. UIKit is a client of libobjc's C API and of Foundation's classes,
// which the loader starts first.

private let libobjc = "/usr/lib/libobjc.A.dylib"

/// Before the generated startup defines UIKit's classes: binds libobjc's C
/// API and checks Foundation is running.
func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    let loaded = ObjCRuntime.load { name in
        libobjc.withCString { library in name.withCString { lookup(library, $0) } }
    }
    guard loaded, Classes.named("NSString") != nil else {
        uikitFatal("UIKit needs libPerryobjc and libPerryFoundation, which are missing or incomplete")
    }
    return true
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
