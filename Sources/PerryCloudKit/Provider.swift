import Glibc
import PerryInterface
import PerryObjCInterop

// libPerryCloudKit: the provider for CloudKit. PerryProviderPlugin
// generates its entry points from the module's Objective-C declarations;
// this file binds libobjc first.

private let libobjc = "/usr/lib/libobjc.A.dylib"

func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    func symbol(_ library: String, _ name: String) -> UnsafeMutableRawPointer? {
        library.withCString { library in name.withCString { lookup(library, $0) } }
    }
    guard ObjCRuntime.load({ symbol(libobjc, $0) }) else {
        let line = "perry: CloudKit: *** CloudKit needs libPerryobjc, which is missing or incomplete\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
        abort()
    }
    return true
}

/// CloudKit's numeric constants, which the loader asks for while binding
/// images: CKQueryOperationMaximumResults, 0, for as many as there are.
func providerSymbol(_ name: String) -> UnsafeMutableRawPointer? { Constants.values[name] }

enum Constants {
    nonisolated(unsafe) static let values: [String: UnsafeMutableRawPointer] = {
        let maximumResults = UnsafeMutablePointer<UInt>.allocate(capacity: 1)
        maximumResults.initialize(to: 0)
        return ["_CKQueryOperationMaximumResults": UnsafeMutableRawPointer(maximumResults)]
    }()
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

