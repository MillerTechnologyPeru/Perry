import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryCarPlay: the provider for CarPlay, with no car: its scene session
// roles are what an app compares a connecting scene's role with (an app that
// supports CarPlay does that in every launch), and no scene ever has them.

private let libobjc = "/usr/lib/libobjc.A.dylib"

func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    func symbol(_ library: String, _ name: String) -> UnsafeMutableRawPointer? {
        library.withCString { library in name.withCString { lookup(library, $0) } }
    }
    guard ObjCRuntime.load({ symbol(libobjc, $0) }) else {
        let line = "perry: CarPlay: *** CarPlay needs libPerryobjc, which is missing or incomplete\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
        abort()
    }
    return true
}
