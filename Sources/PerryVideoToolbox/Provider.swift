import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryVideoToolbox: the provider for VideoToolbox, with no video codecs:
// sessions cannot be created, decoding and encoding report that no decoder or
// encoder is found, and no hardware decodes anything. An app that asks first
// (a player choosing between hardware and software decoding) goes on without.

private let libobjc = "/usr/lib/libobjc.A.dylib"

func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    func symbol(_ library: String, _ name: String) -> UnsafeMutableRawPointer? {
        library.withCString { library in name.withCString { lookup(library, $0) } }
    }
    guard ObjCRuntime.load({ symbol(libobjc, $0) }) else {
        let line = "perry: VideoToolbox: *** VideoToolbox needs libPerryobjc, which is missing or incomplete\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
        abort()
    }
    return true
}
