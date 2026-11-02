import CPerryObjC
import Glibc

/// An Objective-C object: a pointer whose first word is its class.
public typealias ObjectPointer = UnsafeMutableRawPointer

/// A selector: the unique C string for its name.
public typealias SEL = UnsafePointer<CChar>

/// A class or metaclass in Apple's objc_class layout.
public typealias ClassPointer = UnsafeMutablePointer<perry_objc_class>

/// A method implementation.
public typealias IMP = UnsafeMutableRawPointer

@inline(__always)
public func classOf(_ object: ObjectPointer) -> ClassPointer {
    object.load(as: ClassPointer.self)
}

/// Reports a fatal runtime error the way Apple's runtime does, then aborts.
public func objcFatal(_ message: String) -> Never {
    let line = "perry: objc: \(message)\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
    abort()
}

/// A C string that lives for the rest of the process.
func permanentCString(_ string: String) -> UnsafePointer<CChar> {
    UnsafePointer(strdup(string)!)
}

/// A recursive pthread mutex. The runtime calls back into Objective-C code
/// (+initialize, custom retain) while holding some locks, so they must allow
/// the same thread to enter again.
public final class RecursiveLock: @unchecked Sendable {
    private let mutex: UnsafeMutablePointer<pthread_mutex_t>

    public init() {
        mutex = .allocate(capacity: 1)
        var attributes = pthread_mutexattr_t()
        pthread_mutexattr_init(&attributes)
        pthread_mutexattr_settype(&attributes, Int32(PTHREAD_MUTEX_RECURSIVE))
        pthread_mutex_init(mutex, &attributes)
        pthread_mutexattr_destroy(&attributes)
    }

    @inline(__always) public func lock() { pthread_mutex_lock(mutex) }
    @inline(__always) public func unlock() { pthread_mutex_unlock(mutex) }

    @inline(__always)
    public func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try body()
    }
}

/// A C string compared and hashed by content, for name tables.
struct CStringKey: Hashable {
    let pointer: UnsafePointer<CChar>

    static func == (lhs: CStringKey, rhs: CStringKey) -> Bool {
        lhs.pointer == rhs.pointer || strcmp(lhs.pointer, rhs.pointer) == 0
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(bytes: UnsafeRawBufferPointer(start: pointer, count: strlen(pointer)))
    }
}
