import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryUserNotifications: the provider for UserNotifications.
// PerryProviderPlugin generates its entry points from the module's
// Objective-C declarations; this file binds libobjc and libdispatch first,
// and holds the Foundation calls the framework makes.

private let libobjc = "/usr/lib/libobjc.A.dylib"
private let libSystem = "/usr/lib/libSystem.B.dylib"

func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    func symbol(_ library: String, _ name: String) -> UnsafeMutableRawPointer? {
        library.withCString { library in name.withCString { lookup(library, $0) } }
    }
    guard ObjCRuntime.load({ symbol(libobjc, $0) }), Dispatch.load({ symbol(libSystem, $0) }) else {
        notificationsFatal("UserNotifications needs libPerryobjc, libPerrySystem and libPerryFoundation, which are missing or incomplete")
    }
    return true
}

func notificationsFatal(_ message: String) -> Never {
    let line = "perry: UserNotifications: *** \(message)\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
    abort()
}

/// libdispatch: completion handlers run on a global queue, delegate calls
/// on the main queue, and triggers fire with dispatch_after.
enum Dispatch {
    typealias Function = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias Async = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Function) -> Void
    typealias After = @convention(c) (UInt64, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Function) -> Void
    typealias Time = @convention(c) (UInt64, Int64) -> UInt64
    typealias Global = @convention(c) (Int, UInt) -> UnsafeMutableRawPointer?
    nonisolated(unsafe) static var async: Async!
    nonisolated(unsafe) static var after: After!
    nonisolated(unsafe) static var time: Time!
    nonisolated(unsafe) static var global: Global!
    nonisolated(unsafe) static var main: UnsafeMutableRawPointer!
    /// Global blocks' isa, _NSConcreteGlobalBlock.
    nonisolated(unsafe) static var globalBlockClass: UnsafeMutableRawPointer!

    static func load(_ lookup: (String) -> UnsafeMutableRawPointer?) -> Bool {
        guard let async = lookup("_dispatch_async_f"), let after = lookup("_dispatch_after_f"), let time = lookup("_dispatch_time"),
              let global = lookup("_dispatch_get_global_queue"), let main = lookup("__dispatch_main_q"),
              let globalBlockClass = lookup("__NSConcreteGlobalBlock") else { return false }
        self.globalBlockClass = globalBlockClass
        self.async = unsafeBitCast(async, to: Async.self)
        self.after = unsafeBitCast(after, to: After.self)
        self.time = unsafeBitCast(time, to: Time.self)
        self.global = unsafeBitCast(global, to: Global.self)
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
    static func inBackground(_ body: @escaping () -> Void) { async(global(0, 0), Unmanaged.passRetained(Work(body)).toOpaque(), run) }

    static func after(_ seconds: Double, _ body: @escaping () -> Void) {
        let when = time(0, Int64(max(0, seconds) * 1_000_000_000))
        after(when, global(0, 0), Unmanaged.passRetained(Work(body)).toOpaque(), run)
    }
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

@ObjCWrapper("NSDictionary")
class NSDictionary: NSObject {
    @ObjCClassMethod("dictionary") static func empty() -> NSDictionary
}

@ObjCWrapper("NSDate")
class NSDate: NSObject {
    @ObjCClassMethod("dateWithTimeIntervalSinceNow:") static func make(sinceNow: Double) -> NSDate
    @ObjCClassMethod("date") static func now() -> NSDate
    @ObjCMethod("timeIntervalSinceNow") func timeIntervalSinceNow() -> Double
}

@ObjCWrapper("NSCalendar")
class NSCalendar: NSObject {
    @ObjCClassMethod("currentCalendar") static func current() -> NSCalendar
    @ObjCMethod("nextDateAfterDate:matchingComponents:options:")
    func nextDate(after date: NSDate, matching components: NSObject, options: UInt) -> NSDate?
}

@ObjCWrapper("NSSet")
class NSSet: NSObject {
    @ObjCMethod("allObjects") func allObjects() -> NSArray
}

@ObjCWrapper("NSMutableSet")
class NSMutableSet: NSSet {
    @ObjCClassMethod("set") static func empty() -> NSMutableSet
    @ObjCMethod("addObject:") func add(_ object: NSObject)
}

extension NSObject {
    @ObjCMethod("new") func newInstance() -> NSObject
    @ObjCMethod("copy") func copyObject() -> NSObject
    @ObjCMethod("isEqual:") func isEqualTo(_ other: NSObject?) -> Bool
    @ObjCMethod("hash") func hashValue() -> UInt
    @ObjCMethod("respondsToSelector:") func responds(toSelector selector: ObjCSelector) -> Bool

    // NSCoder, for the classes' secure coding.
    @ObjCMethod("encodeObject:forKey:") func encode(_ object: NSObject?, forKey key: String)
    @ObjCMethod("encodeDouble:forKey:") func encode(double value: Double, forKey key: String)
    @ObjCMethod("encodeBool:forKey:") func encode(bool value: Bool, forKey key: String)
    @ObjCMethod("encodeInteger:forKey:") func encode(integer value: Int, forKey key: String)
    @ObjCMethod("decodeObjectForKey:") func decodeObject(forKey key: String) -> NSObject?
    @ObjCMethod("decodeDoubleForKey:") func decodeDouble(forKey key: String) -> Double
    @ObjCMethod("decodeBoolForKey:") func decodeBool(forKey key: String) -> Bool
    @ObjCMethod("decodeIntegerForKey:") func decodeInteger(forKey key: String) -> Int

    func decodeString(_ key: String) -> String? { decodeObject(forKey: key).map { String(objCArgument: $0.objcObject) } }

    static func string(_ value: String) -> NSObject { NSObject(objCReturnValue: value.objCArgument()) }

    var arrayElements: [NSObject] { unsafeCast(to: NSArray.self).elements }
}

extension ObjCClass {
    var object: NSObject { NSObject(pointer) }

    /// A new instance an autorelease pool also holds (+0).
    func autoreleasedInstance() -> NSObject {
        let instance = object.newInstance()
        _ = ObjCRuntime.autorelease(ObjCRuntime.retain(instance.objcObject))
        return instance
    }
}

func equal(_ a: NSObject?, _ b: NSObject?) -> Bool {
    guard let a, let b else { return a == nil && b == nil }
    return a.objcObject == b.objcObject || a.isEqualTo(b)
}

/// Strings that are equal when both are nil.
func equal(_ a: String?, _ b: String?) -> Bool { a == b }
