import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryNetwork: the provider for Network.framework and libnetwork, whose
// C API (nw_*) the Swift overlay calls. Connections, listeners and groups
// are Linux sockets driven by one epoll thread (EventLoop.swift); each has
// a serial dispatch queue of its own for its protocol stack, and calls its
// handlers on the queue it was given, as on Darwin. TLS is Security's
// Secure Transport, configured from sec_protocol_options through
// Security's provider. PerryProviderPlugin generates perry_provider_startup
// and perry_provider_symbol from the module's Objective-C declarations;
// this file binds libobjc, libdispatch and the blocks runtime first.

let libobjc = "/usr/lib/libobjc.A.dylib"
let libSystem = "/usr/lib/libSystem.B.dylib"
let securityFramework = "/System/Library/Frameworks/Security.framework/Security"

/// The loader's symbol lookup, for Security's functions, which are looked
/// up when TLS is first used.
nonisolated(unsafe) var providerSymbolLookup: (@convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?)?

func lookupSymbol(_ library: String, _ name: String) -> UnsafeMutableRawPointer? {
    guard let lookup = providerSymbolLookup else { return nil }
    return library.withCString { library in name.withCString { lookup(library, $0) } }
}

func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    providerSymbolLookup = lookup
    guard ObjCRuntime.load({ lookupSymbol(libobjc, $0) }), Dispatch.load({ lookupSymbol(libSystem, $0) }),
          BlocksRuntime.load({ lookupSymbol(libSystem, $0) }) else {
        networkFatal("Network needs libPerryobjc and libPerrySystem, which are missing or incomplete")
    }
    return true
}

func networkWarning(_ message: String) {
    let line = "perry: Network: \(message)\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
}

func networkFatal(_ message: String) -> Never {
    let line = "perry: Network: *** \(message)\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
    abort()
}

// MARK: - libdispatch

/// libdispatch's C API: handlers go to the queues programs give, and each
/// connection's protocol stack runs on a serial queue of its own.
enum Dispatch {
    typealias Function = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias Async = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Function) -> Void
    typealias After = @convention(c) (UInt64, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Function) -> Void
    typealias Time = @convention(c) (UInt64, Int64) -> UInt64
    typealias Global = @convention(c) (Int, UInt) -> UnsafeMutableRawPointer?
    typealias QueueCreate = @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    typealias DataCreate = @convention(c) (UnsafeRawPointer?, Int, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    typealias DataMap = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeRawPointer?>?, UnsafeMutablePointer<Int>?) -> UnsafeMutableRawPointer?
    typealias DataSize = @convention(c) (UnsafeMutableRawPointer?) -> Int

    nonisolated(unsafe) static var async: Async!
    nonisolated(unsafe) static var afterFunction: After!
    nonisolated(unsafe) static var time: Time!
    nonisolated(unsafe) static var global: Global!
    nonisolated(unsafe) static var queueCreate: QueueCreate!
    nonisolated(unsafe) static var dataCreate: DataCreate!
    nonisolated(unsafe) static var dataMap: DataMap!
    nonisolated(unsafe) static var dataSize: DataSize!
    nonisolated(unsafe) static var main: UnsafeMutableRawPointer!

    static func load(_ lookup: (String) -> UnsafeMutableRawPointer?) -> Bool {
        guard let async = lookup("_dispatch_async_f"), let after = lookup("_dispatch_after_f"), let time = lookup("_dispatch_time"),
              let global = lookup("_dispatch_get_global_queue"), let main = lookup("__dispatch_main_q"),
              let queueCreate = lookup("_dispatch_queue_create"), let dataCreate = lookup("_dispatch_data_create"),
              let dataMap = lookup("_dispatch_data_create_map"), let dataSize = lookup("_dispatch_data_get_size") else { return false }
        self.async = unsafeBitCast(async, to: Async.self)
        self.afterFunction = unsafeBitCast(after, to: After.self)
        self.time = unsafeBitCast(time, to: Time.self)
        self.global = unsafeBitCast(global, to: Global.self)
        self.queueCreate = unsafeBitCast(queueCreate, to: QueueCreate.self)
        self.dataCreate = unsafeBitCast(dataCreate, to: DataCreate.self)
        self.dataMap = unsafeBitCast(dataMap, to: DataMap.self)
        self.dataSize = unsafeBitCast(dataSize, to: DataSize.self)
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

    /// Runs `body` on `queue`, or the main queue when there is none.
    static func on(_ queue: UnsafeMutableRawPointer?, _ body: @escaping () -> Void) {
        async(queue ?? main, Unmanaged.passRetained(Work(body)).toOpaque(), run)
    }

    /// Runs `body` on a global queue, for work that blocks (name lookups).
    static func background(_ body: @escaping () -> Void) {
        async(global(0, 0), Unmanaged.passRetained(Work(body)).toOpaque(), run)
    }

    /// Runs `body` on `queue` after `seconds`.
    static func after(_ seconds: Double, on queue: UnsafeMutableRawPointer?, _ body: @escaping () -> Void) {
        let when = time(0, Int64(max(0, seconds) * 1_000_000_000))
        afterFunction(when, queue ?? global(0, 0), Unmanaged.passRetained(Work(body)).toOpaque(), run)
    }

    /// A new serial queue (+1).
    static func serialQueue(_ label: String) -> UnsafeMutableRawPointer {
        guard let queue = label.withCString({ queueCreate($0, nil) }) else { networkFatal("dispatch_queue_create failed") }
        return queue
    }

    /// A dispatch_data_t (+1) holding a copy of `bytes`.
    static func data(_ bytes: [UInt8]) -> UnsafeMutableRawPointer? {
        bytes.withUnsafeBytes { dataCreate($0.baseAddress, $0.count, nil, nil) }
    }

    static func data(_ bytes: UnsafeRawBufferPointer) -> UnsafeMutableRawPointer? {
        dataCreate(bytes.baseAddress, bytes.count, nil, nil)
    }

    /// The bytes of a dispatch_data_t.
    static func bytes(_ data: UnsafeMutableRawPointer?) -> [UInt8] {
        guard let data, dataSize(data) > 0 else { return [] }
        var buffer: UnsafeRawPointer?
        var size = 0
        guard let mapped = dataMap(data, &buffer, &size) else { return [] }
        defer { ObjCRuntime.release(mapped) }
        guard let buffer, size > 0 else { return [] }
        return Array(UnsafeRawBufferPointer(start: buffer, count: size))
    }
}

// MARK: - Blocks

/// The blocks runtime, for blocks made from Swift closures, which Network
/// hands to programs: the completion of a send that needs none, and the
/// protocol configuration sentinels.
enum BlocksRuntime {
    nonisolated(unsafe) static var mallocBlockClass: UnsafeMutableRawPointer!

    static func load(_ lookup: (String) -> UnsafeMutableRawPointer?) -> Bool {
        guard let mallocBlockClass = lookup("__NSConcreteMallocBlock") else { return false }
        self.mallocBlockClass = mallocBlockClass
        return true
    }

    private static let word = MemoryLayout<UnsafeRawPointer>.size
    private static let invokeOffset = word + 8
    private static let descriptorOffset = invokeOffset + word
    private static let size = descriptorOffset + word

    nonisolated(unsafe) private static let descriptor: UnsafeMutableRawPointer = {
        // reserved, size: a word each.
        let descriptor = UnsafeMutableRawPointer.allocate(byteCount: 2 * word, alignment: word)
        descriptor.storeBytes(of: 0, as: UInt.self)
        descriptor.storeBytes(of: UInt(size), toByteOffset: word, as: UInt.self)
        return descriptor
    }()

    /// A heap block (+1) with no captures whose invoke function is
    /// `invoke`: one that is never freed, for blocks that stand for a
    /// behaviour.
    static func block(invoke: UnsafeRawPointer) -> UnsafeMutableRawPointer {
        guard let block = malloc(size) else { networkFatal("out of memory") }
        block.storeBytes(of: mallocBlockClass, as: UnsafeMutableRawPointer.self)
        // BLOCK_NEEDS_FREE, one reference.
        block.storeBytes(of: Int32(1 << 24 | 2), toByteOffset: word, as: Int32.self)
        block.storeBytes(of: Int32(0), toByteOffset: word + 4, as: Int32.self)
        block.storeBytes(of: invoke, toByteOffset: invokeOffset, as: UnsafeRawPointer.self)
        block.storeBytes(of: UnsafeRawPointer(descriptor), toByteOffset: descriptorOffset, as: UnsafeRawPointer.self)
        return block
    }
}

/// A program's block, held (+1) for as long as this lives.
typealias Block = ObjCBlock

extension ObjCBlock {
    static func from(_ pointer: UnsafeMutableRawPointer?) -> ObjCBlock? { pointer.map { ObjCBlock(objCArgument: $0) } }

    /// void (^)(void)
    func call() {
        function(as: (@convention(c) (UnsafeMutableRawPointer) -> Void).self)(object)
    }

    /// void (^)(id)
    func call(_ a: UnsafeMutableRawPointer?) {
        function(as: (@convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> Void).self)(object, a)
    }

    /// bool (^)(id)
    func test(_ a: UnsafeMutableRawPointer?) -> Bool {
        function(as: (@convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?) -> Bool).self)(object, a)
    }

    /// void (^)(id, id)
    func call(_ a: UnsafeMutableRawPointer?, _ b: UnsafeMutableRawPointer?) {
        function(as: (@convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Void).self)(object, a, b)
    }

    /// void (^)(int state, id error)
    func call(state: Int32, _ error: UnsafeMutableRawPointer?) {
        function(as: (@convention(c) (UnsafeMutableRawPointer, Int32, UnsafeMutableRawPointer?) -> Void).self)(object, state, error)
    }

    /// void (^)(bool)
    func call(_ value: Bool) {
        function(as: (@convention(c) (UnsafeMutableRawPointer, Bool) -> Void).self)(object, value)
    }

    /// void (^)(id, bool)
    func call(_ a: UnsafeMutableRawPointer?, _ value: Bool) {
        function(as: (@convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer?, Bool) -> Void).self)(object, a, value)
    }
}

// MARK: - Locks and objects

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

extension NSObject {
    @ObjCMethod("new") func newInstance() -> NSObject
}

/// The Swift state of a Network object, from creation until -dealloc.
class NWState: @unchecked Sendable {
    /// Called once the object is gone, outside the table's lock.
    func objectDeallocated() {}
}

/// Every Network object's state, by object.
enum NWObjects {
    private static let lock = Lock()
    nonisolated(unsafe) private static var states: [UnsafeMutableRawPointer: NWState] = [:]

    /// A new object of `cls` (+1) with `state`.
    static func make(_ cls: ObjCClass, _ state: NWState) -> UnsafeMutableRawPointer {
        let instance = NSObject(cls.pointer).newInstance()
        let object = withExtendedLifetime(instance) { ObjCRuntime.retain(instance.objcObject)! }
        lock.withLock { states[object] = state }
        return object
    }

    static func state<S: NWState>(_ object: UnsafeMutableRawPointer?, _ type: S.Type) -> S? {
        guard let object else { return nil }
        return lock.withLock { states[object] } as? S
    }

    static func anyState(_ object: UnsafeMutableRawPointer?) -> NWState? {
        guard let object else { return nil }
        return lock.withLock { states[object] }
    }

    static func remove(_ object: UnsafeMutableRawPointer) {
        let state = lock.withLock { states.removeValue(forKey: object) }
        state?.objectDeallocated()
    }
}

/// Network's objects: OS_nw_object and its subclasses, which Swift and
/// nw_retain/nw_release count as Objective-C objects.
@ObjCClass("OS_nw_object")
open class NWObject: NSObject {
    @ObjCMethod("dealloc")
    func dealloc() {
        let object = objcObject
        NWObjects.remove(object)
        ObjCRuntime.superDealloc(object, definedOn: NWObject.objCClass.pointer)
    }
}

@c(_nw_retain)
public func nw_retain(_ object: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? { ObjCRuntime.retain(object) }

@c(_nw_release)
public func nw_release(_ object: UnsafeMutableRawPointer?) {
    if let object { ObjCRuntime.release(object) }
}

/// A C string the caller owns, as copy functions return.
func copiedCString(_ string: String) -> UnsafeMutablePointer<CChar>? { strdup(string) }

/// A C string kept with an object, for get functions that return one.
final class HeldCString {
    let pointer: UnsafeMutablePointer<CChar>?
    init(_ string: String?) { pointer = string.flatMap { strdup($0) } }
    deinit { free(pointer) }
    var value: UnsafePointer<CChar>? { pointer.map { UnsafePointer($0) } }
}

/// Milliseconds since an arbitrary start, for reports.
func monotonicMilliseconds() -> UInt64 {
    var now = timespec()
    clock_gettime(CLOCK_MONOTONIC, &now)
    return UInt64(now.tv_sec) * 1000 + UInt64(now.tv_nsec) / 1_000_000
}
