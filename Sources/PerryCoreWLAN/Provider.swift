import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryCoreWLAN: the provider for CoreWLAN, over Linux's Wi-Fi through
// NetworkManager's D-Bus API (NetworkManager.swift). It implements both the
// modern CoreWLAN (CWWiFiClient, CWChannel, the lowercase accessors) and the
// Snow Leopard-era one (CWInterface as the entry point, +interfaceNames, the
// uppercase SSID/BSSID accessors, scanForNetworksWithName:error: returning an
// array), so programs built against either generation link and run.
//
// PerryProviderPlugin generates the entry points from the module's
// Objective-C declarations; this file binds libobjc first and holds the
// Foundation calls the framework makes.

private let libobjc = "/usr/lib/libobjc.A.dylib"

func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    func symbol(_ library: String, _ name: String) -> UnsafeMutableRawPointer? {
        library.withCString { library in name.withCString { lookup(library, $0) } }
    }
    guard ObjCRuntime.load({ symbol(libobjc, $0) }) else {
        wlanFatal("CoreWLAN needs libPerryobjc, which is missing or incomplete")
    }
    return true
}

/// With PERRY_WIFI_TRACE set, what the interfaces ask of NetworkManager and
/// hear back, on stderr.
nonisolated(unsafe) private let tracing = getenv("PERRY_WIFI_TRACE") != nil

func wlanTrace(_ message: @autoclosure () -> String) {
    guard tracing else { return }
    let line = "perry: CoreWLAN: \(message())\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
}

/// Reports a fatal error, and aborts.
func wlanFatal(_ message: String) -> Never {
    let line = "perry: CoreWLAN: *** \(message)\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
    abort()
}

/// A value carried across concurrency domains that the provider keeps
/// consistent itself.
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

/// Runs an async body to completion on the calling thread. CoreWLAN's
/// accessors and its scan are synchronous, as on Darwin, where the interface
/// talks to NetworkManager on its actor.
enum Blocking {
    private final class Box<T>: @unchecked Sendable { var value: T? }

    static func wait<T: Sendable>(_ body: @escaping @Sendable () async -> T) -> T {
        let box = Box<T>()
        let semaphore = UnsafeMutablePointer<sem_t>.allocate(capacity: 1)
        sem_init(semaphore, 0, 0)
        let signal = Unchecked(semaphore)
        Task {
            box.value = await body()
            sem_post(signal.value)
        }
        while sem_wait(semaphore) != 0 {}
        sem_destroy(semaphore)
        semaphore.deallocate()
        return box.value!
    }
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

@ObjCWrapper("NSNumber")
class NSNumber: NSObject {
    @ObjCClassMethod("numberWithInteger:") static func make(integer: Int) -> NSNumber
    @ObjCClassMethod("numberWithBool:") static func make(bool: Bool) -> NSNumber
    @ObjCClassMethod("numberWithDouble:") static func make(double: Double) -> NSNumber
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

@ObjCWrapper("NSMutableSet")
class NSMutableSet: NSObject {
    @ObjCClassMethod("set") static func empty() -> NSMutableSet
    @ObjCMethod("addObject:") func add(_ object: NSObject)

    static func of(_ objects: [NSObject]) -> NSMutableSet {
        let set = empty()
        objects.forEach(set.add)
        return set
    }
}

@ObjCWrapper("NSDictionary")
class NSDictionary: NSObject {
    @ObjCMethod("objectForKey:") func object(forKey key: String) -> NSObject?
}

@ObjCWrapper("NSError")
class NSError: NSObject {
    @ObjCClassMethod("errorWithDomain:code:userInfo:") static func make(domain: String, code: Int, userInfo: NSObject?) -> NSError
}

extension String {
    /// An NSString of the string, as an object.
    var objCObject: NSObject { NSObject(objCArgument()!) }
}
