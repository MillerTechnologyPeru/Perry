import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryUniformTypeIdentifiers: the provider for UniformTypeIdentifiers,
// and for MobileCoreServices' and CoreServices' UTType C functions, which
// the loader maps here. PerryProviderPlugin generates its entry points from
// the module's Objective-C declarations; this file binds libobjc first.

private let libobjc = "/usr/lib/libobjc.A.dylib"

/// The loader's symbol lookup, for functions other providers define.
nonisolated(unsafe) var providerSymbolLookup: (@convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?)?

func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    providerSymbolLookup = lookup
    let loaded = ObjCRuntime.load { name in
        libobjc.withCString { library in name.withCString { lookup(library, $0) } }
    }
    guard loaded, ObjCClass(named: "NSDictionary").pointer != UnsafeMutableRawPointer(bitPattern: 0) else {
        typesFatal("UniformTypeIdentifiers needs libPerryobjc and libPerryFoundation, which are missing or incomplete")
    }
    return true
}

func typesFatal(_ message: String) -> Never {
    let line = "perry: UniformTypeIdentifiers: *** \(message)\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
    abort()
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

/// Swift state per Objective-C object, from creation until -dealloc.
final class StateTable<State: AnyObject>: @unchecked Sendable {
    private let lock = Lock()
    private var states: [UnsafeMutableRawPointer: State] = [:]

    subscript(object: UnsafeMutableRawPointer?) -> State? {
        guard let object else { return nil }
        return lock.withLock { states[object] }
    }

    func set(_ object: UnsafeMutableRawPointer, _ state: State) { lock.withLock { states[object] = state } }
    func remove(_ object: UnsafeMutableRawPointer) { _ = lock.withLock { states.removeValue(forKey: object) } }
}

// MARK: - Foundation, as this provider calls it

@ObjCWrapper("NSArray")
class NSArray: NSObject {
    @ObjCMethod("count") func count() -> UInt
    @ObjCMethod("objectAtIndex:") func object(at index: UInt) -> NSObject

    var elements: [NSObject] { (0..<count()).map { object(at: $0) } }
}

@ObjCWrapper("NSMutableArray")
class NSMutableArray: NSArray {
    @ObjCClassMethod("array") static func empty() -> Self
    @ObjCMethod("addObject:") func add(_ object: NSObject)

    static func of(_ objects: [NSObject]) -> NSMutableArray {
        let array = empty()
        objects.forEach(array.add)
        return array
    }
}

@ObjCWrapper("NSMutableSet")
class NSMutableSet: NSObject {
    @ObjCClassMethod("set") static func empty() -> Self
    @ObjCMethod("addObject:") func add(_ object: NSObject)

    static func of(_ objects: [NSObject]) -> NSMutableSet {
        let set = empty()
        objects.forEach(set.add)
        return set
    }
}

@ObjCWrapper("NSDictionary")
class NSDictionary: NSObject {
    @ObjCMethod("objectForKey:") func object(forKey key: NSObject) -> NSObject?

    func object(_ key: String) -> NSObject? { object(forKey: NSObject.string(key)) }
}

@ObjCWrapper("NSMutableDictionary")
class NSMutableDictionary: NSDictionary {
    @ObjCClassMethod("dictionary") static func empty() -> Self
    @ObjCMethod("setObject:forKey:") func set(_ object: NSObject, forKey key: NSObject)

    static func of(_ entries: [(String, NSObject)]) -> NSMutableDictionary {
        let dictionary = empty()
        for (key, value) in entries { dictionary.set(value, forKey: NSObject.string(key)) }
        return dictionary
    }
}

@ObjCWrapper("NSBundle")
class NSBundle: NSObject {
    @ObjCClassMethod("mainBundle") static func main() -> NSBundle
    @ObjCMethod("infoDictionary") func infoDictionary() -> NSDictionary?
}

extension NSObject {
    @ObjCMethod("isKindOfClass:") func isKind(of cls: ObjCClass) -> Bool

    var stringValue: String { String(objCArgument: objcObject) }
    var isString: Bool { isKind(of: ObjCClass(named: "NSString")) }
    var isArray: Bool { isKind(of: ObjCClass(named: "NSArray")) }
    var isDictionary: Bool { isKind(of: ObjCClass(named: "NSDictionary")) }

    /// A string, or each string of an array.
    var strings: [String] {
        if isString { return [stringValue] }
        if isArray { return unsafeCast(to: NSArray.self).elements.filter(\.isString).map(\.stringValue) }
        return []
    }

    static func string(_ value: String) -> NSObject { NSObject(objCReturnValue: value.objCArgument()) }
}

extension NSObject {
    @ObjCMethod("new") func newInstance() -> NSObject
}

extension ObjCClass {
    var object: NSObject { NSObject(pointer) }

    /// A new instance at +1, for Create and Copy functions.
    func ownedInstance() -> UnsafeMutableRawPointer {
        let instance = object.newInstance()
        return withExtendedLifetime(instance) { ObjCRuntime.retain(instance.objcObject)! }
    }
}
