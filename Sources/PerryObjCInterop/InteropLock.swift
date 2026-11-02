#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// A small pthread mutex for the interop caches.
final class InteropLock: @unchecked Sendable {
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
