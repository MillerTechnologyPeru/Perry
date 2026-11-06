import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryStoreKit: the provider for StoreKit's Objective-C classes, with no
// App Store: nothing is for sale, nothing has been bought, payments cannot
// be made. Requests still answer, later on the main queue, as StoreKit's
// do: a program that waits for the store to answer before it goes on
// (Unity's purchasing code, which Temple Run waits for while it loads) goes
// on. StoreKit 2's Swift API is Darwin/StoreKit. PerryProviderPlugin
// generates the entry points from the module's Objective-C declarations;
// this file binds libobjc and libdispatch first.

private let libobjc = "/usr/lib/libobjc.A.dylib"
private let libSystem = "/usr/lib/libSystem.B.dylib"

func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    func symbol(_ library: String, _ name: String) -> UnsafeMutableRawPointer? {
        library.withCString { library in name.withCString { lookup(library, $0) } }
    }
    guard ObjCRuntime.load({ symbol(libobjc, $0) }), Dispatch.load({ symbol(libSystem, $0) }) else {
        let line = "perry: StoreKit: *** StoreKit needs libPerryobjc and libPerrySystem, which are missing or incomplete\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
        abort()
    }
    return true
}

/// libdispatch: delegate messages and observers' run on the main queue.
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
    static func string(_ value: String) -> NSObject { NSObject(objCReturnValue: value.objCArgument()) }

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

    /// An NSSet's or NSArray's objects, as an NSArray.
    @ObjCMethod("allObjects") func sendAllObjects() -> NSObject?
}

@ObjCWrapper("NSError")
class NSError: NSObject {
    @ObjCClassMethod("errorWithDomain:code:userInfo:") static func make(domain: String, code: Int, userInfo: NSObject?) -> NSError
}
