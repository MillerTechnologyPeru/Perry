import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryCallKit: the provider for CallKit, with no telephone: an app's
// provider and call controller are made and kept, no call is ever reported
// by the system, and what an app asks of them (a transaction, a new incoming
// call) fails with CallKit's own errors. An app with calls makes these as it
// starts, whether or not there is ever a call.

private let libobjc = "/usr/lib/libobjc.A.dylib"

func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    func symbol(_ library: String, _ name: String) -> UnsafeMutableRawPointer? {
        library.withCString { library in name.withCString { lookup(library, $0) } }
    }
    guard ObjCRuntime.load({ symbol(libobjc, $0) }) else {
        let line = "perry: CallKit: *** CallKit needs libPerryobjc, which is missing or incomplete\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
        abort()
    }
    return true
}
