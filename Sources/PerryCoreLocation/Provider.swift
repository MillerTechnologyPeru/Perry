import CPerryGeometry
import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryCoreLocation: the provider for CoreLocation. PerryProviderPlugin
// generates its entry points from the module's Objective-C declarations;
// this file binds libobjc and libdispatch first, and holds the Foundation
// calls the framework makes.

private let libobjc = "/usr/lib/libobjc.A.dylib"
private let libSystem = "/usr/lib/libSystem.B.dylib"

func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    func symbol(_ library: String, _ name: String) -> UnsafeMutableRawPointer? {
        library.withCString { library in name.withCString { lookup(library, $0) } }
    }
    guard ObjCRuntime.load({ symbol(libobjc, $0) }), Dispatch.load({ symbol(libSystem, $0) }) else {
        let line = "perry: CoreLocation: *** CoreLocation needs libPerryobjc and libPerrySystem, which are missing or incomplete\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
        abort()
    }
    return true
}

/// CoreLocation's structure constants, which the loader asks for while
/// binding images.
func providerSymbol(_ name: String) -> UnsafeMutableRawPointer? { StructureConstants.values[name] }

enum StructureConstants {
    nonisolated(unsafe) static let values: [String: UnsafeMutableRawPointer] = {
        func value<T>(_ value: T) -> UnsafeMutableRawPointer {
            let storage = UnsafeMutablePointer<T>.allocate(capacity: 1)
            storage.initialize(to: value)
            return UnsafeMutableRawPointer(storage)
        }
        return ["_kCLLocationCoordinate2DInvalid": value(Coordinates.invalid)]
    }()
}

/// libdispatch: delegate messages and completion handlers run on the main
/// queue, as CoreLocation sends them on the thread its manager was made on.
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

/// A recursive mutex.
final class Lock: @unchecked Sendable {
    private let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)

    init() {
        var attributes = pthread_mutexattr_t()
        pthread_mutexattr_init(&attributes)
        pthread_mutexattr_settype(&attributes, Int32(PTHREAD_MUTEX_RECURSIVE))
        pthread_mutex_init(mutex, &attributes)
        pthread_mutexattr_destroy(&attributes)
    }

    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return try body()
    }
}

/// Swift state for an Objective-C object, from creation until -dealloc.
class ObjectState {
    required init() {}
}

final class StateTable<State: ObjectState>: @unchecked Sendable {
    private let lock = Lock()
    private var states: [UnsafeMutableRawPointer: State] = [:]

    /// The object's state, made on first use.
    subscript(object: UnsafeMutableRawPointer) -> State {
        lock.withLock {
            if let state = states[object] { return state }
            let state = State()
            states[object] = state
            return state
        }
    }

    func remove(_ object: UnsafeMutableRawPointer) { _ = lock.withLock { states.removeValue(forKey: object) } }
}

// MARK: - Foundation, as this provider calls it

extension NSObject {
    @ObjCMethod("new") func newInstance() -> NSObject
    @ObjCMethod("alloc") func allocated() -> NSObject
}

extension ObjCClass {
    var object: NSObject { NSObject(pointer) }
}

@ObjCWrapper("NSDate")
class NSDate: NSObject {
    @ObjCClassMethod("date") static func now() -> NSDate
}

@ObjCWrapper("NSNumber")
class NSNumber: NSObject {
    @ObjCClassMethod("numberWithInteger:") static func make(integer: Int) -> NSNumber
}

@ObjCWrapper("NSDictionary")
class NSDictionary: NSObject {
    @ObjCMethod("objectForKey:") func object(forKey key: String) -> NSObject?
}

@ObjCWrapper("NSError")
class NSError: NSObject {
    @ObjCClassMethod("errorWithDomain:code:userInfo:") static func make(domain: String, code: Int, userInfo: NSObject?) -> NSError

    /// A CLError in kCLErrorDomain.
    static func location(_ code: Int) -> NSError { make(domain: LocationConstants.kCLErrorDomain, code: code, userInfo: nil) }
}
