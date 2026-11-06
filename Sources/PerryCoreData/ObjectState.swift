import Glibc
import PerryObjCInterop

// Core Data's objects keep their Swift state in a table per class, by
// object, from first use until the object is deallocated.

protocol ObjectState: AnyObject {
    init()
}

final class StateTable<State: ObjectState>: @unchecked Sendable {
    private let lock = Lock()
    private var states: [UnsafeMutableRawPointer: State] = [:]

    subscript(object: UnsafeMutableRawPointer) -> State {
        lock.withLock {
            if let state = states[object] { return state }
            let state = State()
            states[object] = state
            return state
        }
    }

    /// Drops the object's state, from its -dealloc; released outside the
    /// lock, as releasing it may deallocate other objects.
    func remove(_ object: UnsafeMutableRawPointer) {
        let state = lock.withLock { states.removeValue(forKey: object) }
        _ = state
    }
}

/// A recursive pthread mutex: Core Data calls back into itself while
/// holding state.
final class Lock: @unchecked Sendable {
    private let mutex: UnsafeMutablePointer<pthread_mutex_t>

    init() {
        mutex = .allocate(capacity: 1)
        var attributes = pthread_mutexattr_t()
        pthread_mutexattr_init(&attributes)
        pthread_mutexattr_settype(&attributes, Int32(PTHREAD_MUTEX_RECURSIVE))
        pthread_mutex_init(mutex, &attributes)
        pthread_mutexattr_destroy(&attributes)
    }

    func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return try body()
    }
}

/// Runs async work from synchronous Core Data calls, waiting for it on the
/// calling thread. CoreModel's stores are actors; Core Data's API is not.
func waitFor<T>(_ operation: @escaping @Sendable () async throws -> T) throws -> T {
    let box = WaitBox<T>()
    Task.detached {
        let result: Result<T, any Error>
        do { result = .success(try await operation()) } catch { result = .failure(error) }
        pthread_mutex_lock(&box.mutex)
        box.result = result
        pthread_cond_signal(&box.condition)
        pthread_mutex_unlock(&box.mutex)
    }
    pthread_mutex_lock(&box.mutex)
    while box.result == nil { pthread_cond_wait(&box.condition, &box.mutex) }
    pthread_mutex_unlock(&box.mutex)
    return try box.result!.get()
}

/// The result waitFor waits for.
final class WaitBox<T>: @unchecked Sendable {
    var result: Result<T, any Error>?
    var mutex = pthread_mutex_t()
    var condition = pthread_cond_t()

    init() {
        pthread_mutex_init(&mutex, nil)
        pthread_cond_init(&condition, nil)
    }
}

/// A thread running blocks in order, for private-queue contexts.
final class SerialQueue: @unchecked Sendable {
    private let lock = Lock()
    private var mutex = pthread_mutex_t()
    private var condition = pthread_cond_t()
    private var blocks: [() -> Void] = []
    private var thread: pthread_t?

    init() {
        pthread_mutex_init(&mutex, nil)
        pthread_cond_init(&condition, nil)
    }

    func async(_ block: @escaping () -> Void) {
        pthread_mutex_lock(&mutex)
        blocks.append(block)
        if thread == nil {
            var created = pthread_t()
            let context = Unmanaged.passRetained(self).toOpaque()
            pthread_create(&created, nil, { context in
                let queue = Unmanaged<SerialQueue>.fromOpaque(context!).takeRetainedValue()
                keepingLinuxRegisters { queue.run() }
                return nil
            }, context)
            pthread_detach(created)
            thread = created
        }
        pthread_cond_signal(&condition)
        pthread_mutex_unlock(&mutex)
    }

    private func run() {
        while true {
            pthread_mutex_lock(&mutex)
            while blocks.isEmpty { pthread_cond_wait(&condition, &mutex) }
            let block = blocks.removeFirst()
            pthread_mutex_unlock(&mutex)
            ObjCRuntime.autoreleasepool { block() }
        }
    }
}
