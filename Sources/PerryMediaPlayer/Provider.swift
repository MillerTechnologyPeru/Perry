import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryMediaPlayer: the provider for MediaPlayer, on a device with
// no media library and no movie player. PerryProviderPlugin generates its entry points from
// the module's Objective-C declarations; this file binds libobjc first.

private let libobjc = "/usr/lib/libobjc.A.dylib"

func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    guard ObjCRuntime.load({ name in libobjc.withCString { library in name.withCString { lookup(library, $0) } } }) else {
        let line = "perry: MediaPlayer: *** MediaPlayer needs libPerryobjc, which is missing or incomplete\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
        abort()
    }
    return true
}
