import Glibc
import PerryObjCInterop

// UIKit's objects keep their Swift state in a table per class, by object,
// from first use until the object is deallocated.

/// Swift state for one Objective-C object.
protocol ObjectState: AnyObject {
    init()
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

    /// The object's state if it has any, without making it.
    func existing(_ object: UnsafeMutableRawPointer) -> State? {
        lock.withLock { states[object] }
    }

    /// Drops the object's state, from its -dealloc. The state is released
    /// outside the lock, as releasing it may deallocate other objects.
    func remove(_ object: UnsafeMutableRawPointer) {
        let state = lock.withLock { states.removeValue(forKey: object) }
        _ = state
    }
}

/// A pthread mutex.
final class Lock: @unchecked Sendable {
    private let mutex: UnsafeMutablePointer<pthread_mutex_t>

    init() {
        mutex = .allocate(capacity: 1)
        pthread_mutex_init(mutex, nil)
    }

    func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return try body()
    }
}
