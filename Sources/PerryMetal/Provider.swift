import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryMetal: the provider for Metal.framework, on Vulkan through
// metal2vulkan, a separate library opened when an app first asks for a
// device. Each Metal object is a peer holding metal2vulkan's handle for it.
// PerryProviderPlugin generates the entry points from the module's
// Objective-C declarations; this file binds libobjc and libdispatch first.

private let libobjc = "/usr/lib/libobjc.A.dylib"
private let libdispatch = "/usr/lib/system/libdispatch.dylib"

func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    func symbol(_ library: String, _ name: String) -> UnsafeMutableRawPointer? {
        library.withCString { library in name.withCString { lookup(library, $0) } }
    }
    guard ObjCRuntime.load({ symbol(libobjc, $0) }) else {
        metalFatal("Metal needs libPerryobjc, which is missing or incomplete")
    }
    DispatchData.createMap = symbol(libdispatch, "_dispatch_data_create_map")
        .map { unsafeBitCast($0, to: DispatchData.CreateMap.self) }
    return true
}

func metalFatal(_ message: String) -> Never {
    let line = "perry: Metal: *** \(message)\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
    abort()
}

func metalWarning(_ message: String) {
    let line = "perry: Metal: \(message)\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
}
