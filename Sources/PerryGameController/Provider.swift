import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryGameController: the provider for GameController. PerryProviderPlugin
// generates its entry points from the module's Objective-C declarations;
// this file binds libobjc first.

private let libobjc = "/usr/lib/libobjc.A.dylib"

func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    func symbol(_ library: String, _ name: String) -> UnsafeMutableRawPointer? {
        library.withCString { library in name.withCString { lookup(library, $0) } }
    }
    guard ObjCRuntime.load({ symbol(libobjc, $0) }) else {
        let line = "perry: GameController: *** GameController needs libPerryobjc, which is missing or incomplete\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
        abort()
    }
    Controllers.load(symbol)
    // As on iOS, controllers already connected are announced soon after
    // launch, for apps that only listen for the notifications.
    if let after = Controllers.dispatchAfter, let time = Controllers.dispatchTime, let main = Controllers.mainQueue {
        after(time(0, 500_000_000), main, nil) { _ in Controllers.start() }
    }
    return true
}

