import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryIOKit: the provider for IOKit.framework, for Mac apps. Its
// registry has the root and the platform expert device, whose UUID and
// serial number come from this machine's /etc/machine-id; matching finds
// those and no other services. HID managers find no devices (games read
// controllers through GameController), and there are no power sources
// or sleep notifications. PerryProviderPlugin generates the entry points;
// this file binds libobjc first.

private let libobjc = "/usr/lib/libobjc.A.dylib"

func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    guard ObjCRuntime.load({ name in libobjc.withCString { library in name.withCString { lookup(library, $0) } } }),
          ObjCRuntime.functions.getClass("NSDictionary") != nil else {
        let line = "perry: IOKit: *** IOKit needs libPerryobjc and libPerryFoundation, which are missing or incomplete\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
        abort()
    }
    return true
}

/// kIOMainPortDefault and kIOMasterPortDefault: mach_port_t 0, the default.
func providerSymbol(_ name: String) -> UnsafeMutableRawPointer? {
    switch name {
    case "_kIOMainPortDefault", "_kIOMasterPortDefault": defaultPort
    default: nil
    }
}

nonisolated(unsafe) private let defaultPort: UnsafeMutableRawPointer = {
    let storage = UnsafeMutablePointer<UInt32>.allocate(capacity: 2)
    storage.initialize(repeating: 0, count: 2)
    return UnsafeMutableRawPointer(storage)
}()

/// IOReturn values.
enum IOReturn {
    static let success: Int32 = 0
    static let error = Int32(bitPattern: 0xe000_02bc)
    static let badArgument = Int32(bitPattern: 0xe000_02c2)
    static let noDevice = Int32(bitPattern: 0xe000_02c0)
    static let unsupported = Int32(bitPattern: 0xe000_02c7)
    static let notFound = Int32(bitPattern: 0xe000_02f0)
}

/// A mutex.
final class Lock: @unchecked Sendable {
    private let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)

    init() { pthread_mutex_init(mutex, nil) }

    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return try body()
    }
}

// MARK: - Foundation, as this provider calls it

extension NSObject {
    @ObjCMethod("new") func newInstance() -> NSObject
    @ObjCMethod("isKindOfClass:") func isKind(of cls: ObjCClass) -> Bool
    var stringValue: String { String(objCArgument: objcObject) }
    var isString: Bool { isKind(of: ObjCClass(named: "NSString")) }

    static func string(_ value: String) -> NSObject { NSObject(objCReturnValue: value.objCArgument()) }

    /// A new object of a plain class, +1: the opaque objects IOKit gives
    /// out, which CFRelease releases.
    static func opaque(_ className: String) -> UnsafeMutableRawPointer? {
        let object = NSObject(ObjCRuntime.classObject(className)).newInstance()
        return withExtendedLifetime(object) { ObjCRuntime.retain(object.objcObject) }
    }
}

@ObjCWrapper("NSNumber")
class NSNumber: NSObject {
    @ObjCClassMethod("numberWithLongLong:") static func make(int64: Int64) -> NSNumber
    @ObjCClassMethod("numberWithBool:") static func make(bool: Bool) -> NSNumber
}

@ObjCWrapper("NSData")
class NSData: NSObject {
    @ObjCClassMethod("dataWithBytes:length:") static func make(bytes: UnsafeRawPointer?, length: UInt) -> NSData

    static func of(_ text: String) -> NSData {
        var bytes = Array(text.utf8) + [0]
        return make(bytes: &bytes, length: UInt(bytes.count))
    }
}

@ObjCWrapper("NSArray")
class NSArray: NSObject {}

@ObjCWrapper("NSMutableArray")
class NSMutableArray: NSArray {
    @ObjCClassMethod("array") static func empty() -> NSMutableArray
}

@ObjCWrapper("NSDictionary")
class NSDictionary: NSObject {
    @ObjCMethod("objectForKey:") func object(forKey key: NSObject) -> NSObject?

    func object(_ key: String) -> NSObject? { object(forKey: NSObject.string(key)) }
}

@ObjCWrapper("NSMutableDictionary")
class NSMutableDictionary: NSDictionary {
    @ObjCClassMethod("dictionary") static func empty() -> NSMutableDictionary
    @ObjCMethod("setObject:forKey:") func set(_ object: NSObject, forKey key: NSObject)

    static func of(_ entries: [(String, NSObject)]) -> NSMutableDictionary {
        let dictionary = empty()
        for (key, value) in entries { dictionary.set(value, forKey: NSObject.string(key)) }
        return dictionary
    }
}

@ObjCClass("__IOKitOpaque")
final class IOKitOpaque: NSObject {}
