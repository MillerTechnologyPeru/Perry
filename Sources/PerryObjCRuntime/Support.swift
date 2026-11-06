import CPerryObjC
import Glibc

/// Sizes and offsets of the metadata that follow the process's pointer width:
/// 8 bytes for arm64, 4 for armv7. objc_msgSend (msgsend.S, msgsend_arm.S)
/// reads the same layouts.
public enum Layout {
    public static let word = MemoryLayout<UInt>.size
    public static let is64 = word == 8

    /// objc_class: isa, superclass, cache, vtable, bits.
    public static let classSuperclass = word
    public static let classCache = 2 * word
    public static let classVtable = 3 * word

    /// A realized class's cache points to { table, info }.
    public static let headerInfo = word

    /// A cache table is { mask, buckets of { sel, imp } }.
    public static let bucketsOffset = word
    public static let bucketSize = 2 * word
    /// How a selector's address becomes a bucket index.
    public static let hashShift: UInt = is64 ? 3 : 2

    /// Clears the Swift flag bits from objc_class.bits.
    public static let classBitsMask = ~UInt(PERRY_CLASS_BITS_FLAGS)

    /// A block's invoke pointer, after isa, flags and reserved.
    public static let blockInvoke = word + 8

    /// A protocol list is a pointer-sized count, then the pointers.
    public static func protocolEntry(_ index: Int) -> Int { word + index * word }

    /// property_t, method_description, and other pairs of pointers.
    public static let pair = 2 * word
}

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

public func objcWarning(_ message: String) {
    let line = "perry: objc: warning: \(message)\n"
    line.withCString { _ = write(2, $0, strlen($0)) }
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
