import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryAVFoundation: the provider for AVFoundation. PerryProviderPlugin
// generates its entry points from the module's Objective-C declarations;
// this file binds libobjc first.

private let libobjc = "/usr/lib/libobjc.A.dylib"

func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    func symbol(_ library: String, _ name: String) -> UnsafeMutableRawPointer? {
        library.withCString { library in name.withCString { lookup(library, $0) } }
    }
    guard ObjCRuntime.load({ symbol(libobjc, $0) }) else {
        let line = "perry: AVFoundation: *** AVFoundation needs libPerryobjc, which is missing or incomplete\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
        abort()
    }
    Players.load(symbol)
    return true
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
