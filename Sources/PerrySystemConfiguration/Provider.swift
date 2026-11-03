import Glibc
import PerryInterface
import PerryObjCInterop

// libPerrySystemConfiguration: the provider for SystemConfiguration.
// PerryProviderPlugin generates its entry points from the module's
// Objective-C declarations; this file binds libobjc and libdispatch first.

private let libobjc = "/usr/lib/libobjc.A.dylib"
private let libSystem = "/usr/lib/libSystem.B.dylib"

func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    func symbol(_ library: String, _ name: String) -> UnsafeMutableRawPointer? {
        library.withCString { library in name.withCString { lookup(library, $0) } }
    }
    guard ObjCRuntime.load({ symbol(libobjc, $0) }), Dispatch.load({ symbol(libSystem, $0) }) else {
        let line = "perry: SystemConfiguration: *** SystemConfiguration needs libPerryobjc and libPerrySystem, which are missing or incomplete\n"
        line.withCString { _ = write(2, $0, strlen($0)) }
        abort()
    }
    return true
}

/// libdispatch: callbacks run on the queue a target is scheduled on, and
/// targets are checked again with dispatch_after.
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

    static func load(_ lookup: (String) -> UnsafeMutableRawPointer?) -> Bool {
        guard let async = lookup("_dispatch_async_f"), let after = lookup("_dispatch_after_f"), let time = lookup("_dispatch_time"),
              let global = lookup("_dispatch_get_global_queue"), let main = lookup("__dispatch_main_q") else { return false }
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

    static func on(_ queue: UnsafeMutableRawPointer?, _ body: @escaping () -> Void) {
        async(queue ?? main, Unmanaged.passRetained(Work(body)).toOpaque(), run)
    }

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
