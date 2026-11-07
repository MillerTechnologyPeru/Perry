import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryGameKit: the provider for GameKit's Objective-C classes, on a
// device with no Game Center account. The local player is never signed
// in, and scores and achievements are kept by no one: reporting them
// succeeds at nothing, answering later on the main queue, as GameKit
// does, that the player is not authenticated. A game that reports a level's
// time without asking whether the player is signed in (Leo's Fortune) gets
// objects to report, rather than nil from a missing class.
// PerryProviderPlugin generates the entry points from the module's
// Objective-C declarations; this file binds libobjc and libdispatch first.

private let libobjc = "/usr/lib/libobjc.A.dylib"
private let libSystem = "/usr/lib/libSystem.B.dylib"

func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    func symbol(_ library: String, _ name: String) -> UnsafeMutableRawPointer? {
        library.withCString { library in name.withCString { lookup(library, $0) } }
    }
    guard ObjCRuntime.load({ symbol(libobjc, $0) }), Dispatch.load({ symbol(libSystem, $0) }) else {
        let line = "perry: GameKit: *** GameKit needs libPerryobjc and libPerrySystem, which are missing or incomplete\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
        abort()
    }
    return true
}

/// libdispatch: completion handlers run on the main queue.
enum Dispatch {
    typealias Function = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias Async = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Function) -> Void
    nonisolated(unsafe) static var async: Async!
    nonisolated(unsafe) static var main: UnsafeMutableRawPointer!

    static func load(_ lookup: (String) -> UnsafeMutableRawPointer?) -> Bool {
        guard let async = lookup("_dispatch_async_f"), let main = lookup("__dispatch_main_q") else { return false }
        self.async = unsafeBitCast(async, to: Async.self)
        self.main = main
        return true
    }

    final class Work {
        let body: () -> Void
        init(_ body: @escaping () -> Void) { self.body = body }
    }

    private static let run: Function = { context in
        guard let context else { return }
        ObjCRuntime.autoreleasepool { Unmanaged<Work>.fromOpaque(context).takeRetainedValue().body() }
    }

    static func onMain(_ body: @escaping () -> Void) { async(main, Unmanaged.passRetained(Work(body)).toOpaque(), run) }
}

// MARK: - Foundation, as this provider calls it

extension NSObject {
    /// A new NSArray of `objects`, autoreleased.
    static func array(_ objects: [NSObject]) -> NSObject {
        typealias Make = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?,
                                         UnsafePointer<UnsafeMutableRawPointer?>?, UInt) -> UnsafeMutableRawPointer?
        let pointers: [UnsafeMutableRawPointer?] = objects.map { $0.objcObject }
        let array = pointers.withUnsafeBufferPointer {
            unsafeBitCast(ObjCRuntime.msgSend, to: Make.self)(ObjCRuntime.classObject("NSArray"),
                                                            ObjCRuntime.selector("arrayWithObjects:count:"),
                                                            $0.baseAddress, UInt($0.count))
        }
        return NSObject(objCReturnValue: array)
    }
}

@ObjCWrapper("NSError")
class NSError: NSObject {
    @ObjCClassMethod("errorWithDomain:code:userInfo:") static func make(domain: String, code: Int, userInfo: NSObject?) -> NSError
}
