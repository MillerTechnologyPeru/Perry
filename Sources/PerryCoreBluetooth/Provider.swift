import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryCoreBluetooth: the provider for CoreBluetooth, a central over
// BlueZ (BlueZ.swift). PerryProviderPlugin generates its entry points from
// the module's Objective-C declarations; this file binds libobjc and
// libdispatch first, and holds the Foundation calls the framework makes.

private let libobjc = "/usr/lib/libobjc.A.dylib"
private let libSystem = "/usr/lib/libSystem.B.dylib"

func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    func symbol(_ library: String, _ name: String) -> UnsafeMutableRawPointer? {
        library.withCString { library in name.withCString { lookup(library, $0) } }
    }
    guard ObjCRuntime.load({ symbol(libobjc, $0) }), Dispatch.load({ symbol(libSystem, $0) }) else {
        bluetoothFatal("CoreBluetooth needs libPerryobjc and libPerrySystem, which are missing or incomplete")
    }
    return true
}

/// Reports a fatal error, and aborts.
func bluetoothFatal(_ message: String) -> Never {
    let line = "perry: CoreBluetooth: *** \(message)\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
    abort()
}

/// libdispatch: delegate messages go to the queue a manager was given, or
/// the main queue, as on Darwin.
enum Dispatch {
    typealias Function = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias Async = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Function) -> Void
    typealias Retain = @convention(c) (UnsafeMutableRawPointer?) -> Void
    nonisolated(unsafe) static var async: Async!
    nonisolated(unsafe) static var retain: Retain!
    nonisolated(unsafe) static var release: Retain!
    nonisolated(unsafe) static var main: UnsafeMutableRawPointer!

    static func load(_ lookup: (String) -> UnsafeMutableRawPointer?) -> Bool {
        guard let async = lookup("_dispatch_async_f"), let main = lookup("__dispatch_main_q"),
              let retain = lookup("_dispatch_retain"), let release = lookup("_dispatch_release") else { return false }
        self.async = unsafeBitCast(async, to: Async.self)
        self.retain = unsafeBitCast(retain, to: Retain.self)
        self.release = unsafeBitCast(release, to: Retain.self)
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

    /// Runs `body` on `queue`, or the main queue.
    static func on(_ queue: UnsafeMutableRawPointer?, _ body: @escaping () -> Void) {
        async(queue ?? main, Unmanaged.passRetained(Work(body)).toOpaque(), run)
    }
}

/// A value carried across concurrency domains that the provider keeps
/// consistent itself: Objective-C objects, which are reached from the
/// delegate queue and BlueZ's tasks alike.
struct Unchecked<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
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

@ObjCWrapper("NSData")
class NSData: NSObject {
    @ObjCClassMethod("dataWithBytes:length:") static func make(bytes: UnsafeRawPointer?, length: UInt) -> NSData
    @ObjCMethod("bytes") func bytes() -> UnsafeRawPointer?
    @ObjCMethod("length") func length() -> UInt

    var byteArray: [UInt8] {
        let count = Int(length())
        guard count > 0, let bytes = bytes() else { return [] }
        return Array(UnsafeBufferPointer(start: bytes.assumingMemoryBound(to: UInt8.self), count: count))
    }

    static func of(_ bytes: [UInt8]) -> NSData { bytes.withUnsafeBytes { make(bytes: $0.baseAddress, length: UInt($0.count)) } }
}

@ObjCWrapper("NSUUID")
class NSUUID: NSObject {
    @ObjCMethod("initWithUUIDString:") func initialize(string: String) -> NSUUID?
    @ObjCMethod("UUIDString") func uuidString() -> String

    static func make(_ string: String) -> NSUUID? { NSUUID.objCClass.object.allocated().unsafeCast(to: NSUUID.self).initialize(string: string) }
}

@ObjCWrapper("NSNumber")
class NSNumber: NSObject {
    @ObjCClassMethod("numberWithInteger:") static func make(integer: Int) -> NSNumber
    @ObjCClassMethod("numberWithBool:") static func make(bool: Bool) -> NSNumber
    @ObjCMethod("boolValue") func boolValue() -> Bool
    @ObjCMethod("integerValue") func integerValue() -> Int
}

@ObjCWrapper("NSArray")
class NSArray: NSObject {
    @ObjCMethod("count") func count() -> UInt
    @ObjCMethod("objectAtIndex:") func object(at index: UInt) -> NSObject

    var elements: [NSObject] { (0..<count()).map { object(at: $0) } }
}

@ObjCWrapper("NSMutableArray")
class NSMutableArray: NSObject {
    @ObjCClassMethod("array") static func empty() -> NSMutableArray
    @ObjCMethod("addObject:") func add(_ object: NSObject)

    static func of(_ objects: [NSObject]) -> NSMutableArray {
        let array = empty()
        objects.forEach(array.add)
        return array
    }
}

@ObjCWrapper("NSDictionary")
class NSDictionary: NSObject {
    @ObjCMethod("objectForKey:") func object(forKey key: String) -> NSObject?
}

@ObjCWrapper("NSMutableDictionary")
class NSMutableDictionary: NSObject {
    @ObjCClassMethod("dictionary") static func empty() -> NSMutableDictionary
    @ObjCMethod("setObject:forKey:") func set(_ object: NSObject, forKey key: String)
    @ObjCMethod("setObject:forKey:") func set(_ object: NSObject, forObjectKey key: NSObject)
    @ObjCMethod("setObject:forKey:") func set(string: String, forKey key: String)
}

@ObjCWrapper("NSError")
class NSError: NSObject {
    @ObjCClassMethod("errorWithDomain:code:userInfo:") static func make(domain: String, code: Int, userInfo: NSObject?) -> NSError
}

extension NSObject {
    /// An NSDictionary's value for `key`, of an options dictionary.
    func option(_ key: String) -> NSObject? {
        guard self.is(NSDictionary.self) else { return nil }
        return unsafeCast(to: NSDictionary.self).object(forKey: key)
    }

    /// The CBUUIDs of an NSArray of them.
    var uuids: [BluetoothUUID] {
        guard self.is(NSArray.self) else { return [] }
        return unsafeCast(to: NSArray.self).elements.compactMap { $0.is(CBUUID.self) ? $0.unsafeCast(to: CBUUID.self).uuid : nil }
    }
}
