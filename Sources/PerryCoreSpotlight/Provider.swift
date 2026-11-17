import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryCoreSpotlight: the provider for CoreSpotlight, with no Spotlight:
// an app's searchable items are taken and forgotten, as indexing them
// succeeds and nothing ever searches or opens one. An app that indexes its
// content does so as it loads it, and treats a failure as one of its own.

private let libobjc = "/usr/lib/libobjc.A.dylib"

func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    guard ObjCRuntime.load({ name in libobjc.withCString { library in name.withCString { lookup(library, $0) } } }) else {
        let line = "perry: CoreSpotlight: *** CoreSpotlight needs libPerryobjc, which is missing or incomplete\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
        abort()
    }
    return true
}
