import Glibc
import PerryInterface
import PerryObjCInterop

// libPerrySystemConfiguration: the provider for SystemConfiguration. PerryProviderPlugin
// generates its entry points from the module's Objective-C declarations;
// this file binds libobjc first.

private let libobjc = "/usr/lib/libobjc.A.dylib"

func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    func symbol(_ library: String, _ name: String) -> UnsafeMutableRawPointer? {
        library.withCString { library in name.withCString { lookup(library, $0) } }
    }
    guard ObjCRuntime.load({ symbol(libobjc, $0) }) else {
        let line = "perry: SystemConfiguration: *** SystemConfiguration needs libPerryobjc, which is missing or incomplete\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
        abort()
    }
    return true
}

