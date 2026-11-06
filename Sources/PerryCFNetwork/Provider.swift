import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryCFNetwork: the provider for CFNetwork.framework, whose
// NSURLSession, NSURLRequest, NSURLResponse and NSHTTPCookie classes
// Foundation re-exports. The loading is swift-corelibs-foundation's
// URLSession, through PerryURLLoading. PerryProviderPlugin generates its
// perry_provider_startup and perry_provider_symbol from the module's
// Objective-C declarations; this file adds the provider's own steps.
// CFNetwork is a client of libobjc's C API and of Foundation's classes.

private let libobjc = "/usr/lib/libobjc.A.dylib"
private let libSystem = "/usr/lib/libSystem.B.dylib"

/// The blocks runtime, for blocks made from Swift closures.
enum BlocksRuntime {
    typealias Copy = @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    typealias Release = @convention(c) (UnsafeMutableRawPointer?) -> Void
    nonisolated(unsafe) static var copy: Copy!
    nonisolated(unsafe) static var release: Release!
    nonisolated(unsafe) static var mallocBlockClass: UnsafeMutableRawPointer!
}

func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    func symbol(_ library: String, _ name: String) -> UnsafeMutableRawPointer? {
        library.withCString { library in name.withCString { lookup(library, $0) } }
    }
    guard ObjCRuntime.load({ symbol(libobjc, $0) }), Classes.named("NSOperationQueue") != nil,
          let copy = symbol(libSystem, "__Block_copy"), let release = symbol(libSystem, "__Block_release"),
          let mallocBlockClass = symbol(libSystem, "__NSConcreteMallocBlock") else {
        networkFatal("CFNetwork needs libPerryobjc, libPerrySystem and libPerryFoundation, which are missing or incomplete")
    }
    BlocksRuntime.copy = unsafeBitCast(copy, to: BlocksRuntime.Copy.self)
    BlocksRuntime.release = unsafeBitCast(release, to: BlocksRuntime.Release.self)
    BlocksRuntime.mallocBlockClass = mallocBlockClass
    // The run loops CFNetService's callbacks are delivered through.
    guard RunLoopCalls.load({ library, name in symbol(library, name) }) else {
        networkFatal("CFNetwork needs CoreFoundation's run loops, which are missing")
    }
    return true
}

/// Reports a fatal error the way CFNetwork's exceptions read, and aborts.
func networkFatal(_ message: String) -> Never {
    let line = "perry: CFNetwork: *** \(message)\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
    abort()
}

enum Classes {
    static func named(_ name: String) -> ObjCClass? {
        name.withCString { ObjCRuntime.functions.getClass($0) }.map(ObjCClass.init)
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

/// Swift state per Objective-C object, from first use until -dealloc.
final class StateTable<State: AnyObject>: @unchecked Sendable {
    private let lock = Lock()
    private var states: [UnsafeMutableRawPointer: State] = [:]

    func get(_ object: UnsafeMutableRawPointer) -> State? { lock.withLock { states[object] } }
    func set(_ object: UnsafeMutableRawPointer, _ state: State) { lock.withLock { states[object] = state } }

    func remove(_ object: UnsafeMutableRawPointer) {
        let state = lock.withLock { states.removeValue(forKey: object) }
        _ = state
    }
}
