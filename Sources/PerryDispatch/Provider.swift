import CPerryDispatch
import Glibc
import PerryInterface
import PerryObjCInterop

// libPerrydispatch: the provider for libdispatch, which libSystem
// re-exports. The work runs on Linux's libdispatch; this module gives it
// Darwin's API, where queues, groups, semaphores, sources and data are
// Objective-C objects that ARC retains and releases, and blocks are
// Darwin's. PerryProviderPlugin generates its perry_provider_startup and
// perry_provider_symbol from the module's Objective-C declarations; this
// file adds the provider's own steps.

private let libobjc = "/usr/lib/libobjc.A.dylib"
private let libSystem = "/usr/lib/libSystem.B.dylib"

/// libobjc and blocks runtime functions beyond the interop layer's.
enum Runtime {
    typealias Pointer = UnsafeMutableRawPointer
    typealias CreateInstance = @convention(c) (Pointer?, Int) -> Pointer?
    typealias InstanceSize = @convention(c) (Pointer?) -> Int
    typealias BlockCopy = @convention(c) (Pointer?) -> Pointer?
    typealias BlockRelease = @convention(c) (Pointer?) -> Void
    nonisolated(unsafe) static var createInstance: CreateInstance!
    nonisolated(unsafe) static var blockCopy: BlockCopy!
    nonisolated(unsafe) static var blockRelease: BlockRelease!
    /// Heap blocks' class, for the blocks dispatch_block_create makes.
    nonisolated(unsafe) static var mallocBlockClass: Pointer!
}

/// Before the generated startup defines the classes: binds libobjc and the
/// blocks runtime.
func providerWillStart(_ info: perry_startup_info) -> Bool {
    guard info.version >= 2, let lookup = info.lookup_symbol else { return false }
    func symbol(_ library: String, _ name: String) -> UnsafeMutableRawPointer? {
        library.withCString { library in name.withCString { lookup(library, $0) } }
    }
    guard ObjCRuntime.load({ symbol(libobjc, $0) }),
          let createInstance = symbol(libobjc, "_class_createInstance"),
          let blockCopy = symbol(libSystem, "__Block_copy"), let blockRelease = symbol(libSystem, "__Block_release"),
          let mallocBlockClass = symbol(libSystem, "__NSConcreteMallocBlock") else {
        dispatchFatal("libdispatch needs libPerryobjc and libPerrySystem, which are missing or incomplete")
    }
    Runtime.createInstance = unsafeBitCast(createInstance, to: Runtime.CreateInstance.self)
    Runtime.blockCopy = unsafeBitCast(blockCopy, to: Runtime.BlockCopy.self)
    Runtime.blockRelease = unsafeBitCast(blockRelease, to: Runtime.BlockRelease.self)
    Runtime.mallocBlockClass = mallocBlockClass
    return true
}

/// After the classes are defined: gives the static objects their classes,
/// and readies the main queue for the run loop.
func providerDidStart(_ info: perry_startup_info) {
    Classes.load()
    Objects.setUpStatic(perry_main_q(), Classes.mainQueue, linux: perry_linux_main_q())
    Objects.setUpStatic(perry_queue_attr_concurrent(), Classes.queueAttribute,
                        linux: perry_linux_queue_attr_concurrent(), flags: QueueAttributes.concurrent)
    Objects.setUpStatic(perry_data_empty(), Classes.emptyData, linux: perry_linux_data_empty())
    Queues.register(main: perry_main_q())
    MainQueue.start()
}

/// Reports a client error the way libdispatch's crashes read, and aborts.
func dispatchFatal(_ message: String) -> Never {
    let line = "perry: libdispatch: BUG IN CLIENT OF LIBDISPATCH: \(message)\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
    abort()
}

/// A mutex.
final class Lock: @unchecked Sendable {
    private let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)

    init() { pthread_mutex_init(mutex, nil) }

    deinit {
        pthread_mutex_destroy(mutex)
        mutex.deallocate()
    }

    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return try body()
    }
}
